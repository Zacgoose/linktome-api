function Invoke-PublicLogin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body

    if (-not $Body.email -or -not $Body.password) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Email and password required" }
        }
    }

    # Validate email format
    if (-not (Test-EmailFormat -Email $Body.email)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid email format" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize email for query to prevent injection
        $SafeEmail = Protect-TableQueryValue -Value $Body.email.ToLower()
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        
        # Get client IP for logging
        $ClientIP = Get-ClientIPAddress -Request $Request
        
        if (-not $User) {
            # Log failed login attempt
            Write-SecurityEvent -EventType 'LoginFailed' -Email $Body.email -IpAddress $ClientIP -Endpoint 'public/login' -Reason 'UserNotFound'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }
        
        $Valid = Test-PasswordHash -Password $Body.password -StoredHash $User.PasswordHash -StoredSalt $User.PasswordSalt
        
        if (-not $Valid) {
            # Log failed login attempt
            Write-SecurityEvent -EventType 'LoginFailed' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/login' -Reason 'InvalidPassword'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }
        
        # Log successful login
        Write-SecurityEvent -EventType 'LoginSuccess' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/login'
        
        # Get roles and permissions (deserialize from JSON if needed)
        # Get the actual user role from the Users table (should be 'user', 'admin', or 'company_owner')
        $AllowedRoles = @('user', 'company_admin', 'company_owner', 'user_manager')
        $ActualUserRole = $null
        $RolesArr = @()
        if ($User.Roles) {
            if ($User.Roles -is [string] -and $User.Roles.StartsWith('[')) {
                $parsed = $User.Roles | ConvertFrom-Json
                if ($parsed -is [string]) {
                    $RolesArr = @($parsed)
                } else {
                    $RolesArr = $parsed
                }
            } elseif ($User.Roles -is [array]) {
                $RolesArr = $User.Roles
            } elseif ($User.Roles -is [string]) {
                $RolesArr = @($User.Roles)
            }
        }
        if ($RolesArr.Count -ge 1) {
            $CandidateRole = $RolesArr[0]
            if ($AllowedRoles -contains $CandidateRole) {
                $ActualUserRole = $CandidateRole
            } else {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body = @{ error = "Invalid user role in database: $CandidateRole" }
                }
            }
        } else {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = "No valid user role found for user." }
            }
        }
        $Roles = @($ActualUserRole)
        $Permissions = Get-DefaultRolePermissions -Role $ActualUserRole

        # Lookup company memberships for this user, include role and permissions (permissions are per company)
        $CompanyMemberships = @()
        $CompanyUsersTable = Get-LinkToMeTable -TableName 'CompanyUsers'
        $CompanyUserEntities = Get-LinkToMeAzDataTableEntity @CompanyUsersTable -Filter "RowKey eq '$($User.RowKey)'"
        foreach ($cu in $CompanyUserEntities) {
            $companyRole = $cu.Role
            $companyPermissions = @()
            if ($companyRole) {
                $companyPermissions = Get-DefaultRolePermissions -Role $companyRole
            }
            # Ensure permissions is always an array
            if ($companyPermissions -is [string]) {
                $companyPermissions = @($companyPermissions)
            }
            $CompanyMemberships += @{
                companyId = $cu.PartitionKey
                role = $companyRole
                permissions = $companyPermissions
            }
        }

        # Build userManagements array for user-to-user management context
        $UserManagements = @()
        if ($User.HasUserManagers -or $User.IsUserManager) {
            $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'
            # As manager: users I manage
            if ($User.IsUserManager) {
                $managees = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$($User.RowKey)' and State eq 'accepted'"
                foreach ($um in $managees) {
                    $manageePermissions = Get-DefaultRolePermissions -Role $um.Role
                    $UserManagements += @{
                        UserId = $um.RowKey
                        role = $um.Role
                        state = $um.State
                        direction = 'manager'
                        permissions = $manageePermissions
                    }
                }
            }
        }

        $Token = New-LinkToMeJWT -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -Roles $Roles -Permissions $Permissions -CompanyMemberships $CompanyMemberships -UserManagements $UserManagements

        # Generate refresh token
        $RefreshToken = New-RefreshToken
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $RefreshToken -UserId $User.RowKey -ExpiresAt $ExpiresAt

        $Results = @{
            user = @{
                UserId = $User.RowKey
                email = $User.PartitionKey
                username = $User.Username
                userRole = $ActualUserRole
                roles = $Roles
                permissions = $Permissions
                companyMemberships = $CompanyMemberships
                userManagements = $UserManagements
            }
            accessToken = $Token
            refreshToken = $RefreshToken
        }

        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Login error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Login failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}