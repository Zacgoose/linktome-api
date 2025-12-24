function Invoke-PublicRefreshToken {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body

    if (-not $Body.refreshToken) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "Missing refresh token" 
            }
        }
    }

    try {
        # Validate refresh token from database
        $TokenRecord = Get-RefreshToken -Token $Body.refreshToken
        
        if (-not $TokenRecord) {
            # Log invalid refresh token attempt
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-SecurityEvent -EventType 'RefreshTokenFailed' -IpAddress $ClientIP -Endpoint 'public/refreshToken' -Reason 'InvalidOrExpiredToken'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ 
                    success = $false
                    error = "Invalid or expired refresh token" 
                }
            }
        }
        
        # Get user with latest roles and permissions
        $Table = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $TokenRecord.UserId
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ 
                    success = $false
                    error = "User not found" 
                }
            }
        }
        
        # Get roles and permissions (deserialize from JSON if needed)
        $Roles = if ($User.Roles) {
            if ($User.Roles -is [string] -and $User.Roles.StartsWith('[')) {
                $User.Roles | ConvertFrom-Json
            } elseif ($User.Roles -is [array]) {
                $User.Roles
            } else {
                @($User.Roles)
            }
        } else {
            @('user')
        }
        
        $Permissions = if ($User.Permissions) {
            if ($User.Permissions -is [string] -and $User.Permissions.StartsWith('[')) {
                $User.Permissions | ConvertFrom-Json
            } elseif ($User.Permissions -is [array]) {
                $User.Permissions
            } else {
                @($User.Permissions)
            }
        } else {
            Get-DefaultRolePermissions -Role $Roles[0]
        }
        
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

        $NewAccessToken = New-LinkToMeJWT -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -Roles $Roles -Permissions $Permissions -CompanyMemberships $CompanyMemberships -UserManagements $UserManagements

        # Determine actual user role
        $AllowedRoles = @('user', 'company_admin', 'company_owner', 'user_manager')
        $ActualUserRole = $null
        if ($Roles.Count -ge 1) {
            $CandidateRole = $Roles[0]
            if ($AllowedRoles -contains $CandidateRole) {
                $ActualUserRole = $CandidateRole
            }
        }

        # Generate new refresh token (rotation)
        $NewRefreshToken = New-RefreshToken

        # Invalidate old refresh token
        Remove-RefreshToken -Token $Body.refreshToken

        # Store new refresh token (7 days expiration)
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $NewRefreshToken -UserId $User.RowKey -ExpiresAt $ExpiresAt

        # Log successful token refresh
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'TokenRefreshed' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/refreshToken'

        $Results = @{
            accessToken = $NewAccessToken
            refreshToken = $NewRefreshToken
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
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Token refresh error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Token refresh failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
