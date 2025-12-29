function Invoke-PublicSignup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body

    if (-not $Body.email -or -not $Body.username -or -not $Body.password) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Email, username, and password required" }
        }
    }

    # Validate email format
    if (-not (Test-EmailFormat -Email $Body.email)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid email format" }
        }
    }

    # Validate username format
    if (-not (Test-UsernameFormat -Username $Body.username)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Username must be 3-30 characters and contain only letters, numbers, underscore, or hyphen" }
        }
    }

    # Validate password strength
    $PasswordCheck = Test-PasswordStrength -Password $Body.password
    if (-not $PasswordCheck.Valid) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = $PasswordCheck.Message }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get client IP for logging
        $ClientIP = Get-ClientIPAddress -Request $Request
        
        # Check if email exists - sanitize for query
        $SafeEmail = Protect-TableQueryValue -Value $Body.email.ToLower()
        $ExistingEmail = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        if ($ExistingEmail) {
            # Log failed signup attempt
            Write-SecurityEvent -EventType 'SignupFailed' -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup' -Reason 'EmailAlreadyRegistered'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Conflict
                Body = @{ error = "Email already registered" }
            }
        }
        
        # Check if username exists - sanitize for query
        $SafeUsername = Protect-TableQueryValue -Value $Body.username.ToLower()
        $ExistingUsername = Get-LinkToMeAzDataTableEntity @Table -Filter "Username eq '$SafeUsername'" | Select-Object -First 1
        if ($ExistingUsername) {
            # Log failed signup attempt
            Write-SecurityEvent -EventType 'SignupFailed' -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup' -Reason 'UsernameAlreadyTaken'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Conflict
                Body = @{ error = "Username already taken" }
            }
        }
        
        # Create user
        $PasswordData = New-PasswordHash -Password $Body.password
        $UserId = 'user-' + (New-Guid).ToString()
        
        # Assign default role and permissions
        $DefaultRole = 'user'
        $DefaultPermissions = Get-DefaultRolePermissions -Role $DefaultRole
        
        # Convert arrays to JSON strings for Azure Table Storage compatibility
        # Both Roles and Permissions use [string] cast for JSON conversion
        $RolesJson = [string](@($DefaultRole) | ConvertTo-Json -Compress)
        $PermissionsJson = [string]($DefaultPermissions | ConvertTo-Json -Compress)
        
        $NewUser = @{
            PartitionKey = [string]$Body.email.ToLower()
            RowKey = [string]$UserId
            Username = [string]$Body.username.ToLower()
            DisplayName = [string]$Body.username
            Bio = [string]''
            Avatar = [string]"https://ui-avatars.com/api/?name=$($Body.username)&size=200"
            PasswordHash = [string]$PasswordData.Hash
            PasswordSalt = [string]$PasswordData.Salt
            IsActive = [bool]$true
            Roles = $RolesJson
            Permissions = $PermissionsJson
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $NewUser -Force
        
        $CreatedUser = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$UserId'" | Select-Object -First 1

        # Log successful signup
        Write-SecurityEvent -EventType 'SignupSuccess' -UserId $UserId -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup'

        try {
            $authContext = Get-UserAuthContext -User $CreatedUser
        } catch {
            Write-Error "Auth context error: $($_.Exception.Message)"
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = $_.Exception.Message }
            }
        }

        $Token = New-LinkToMeJWT -User $CreatedUser

        # Generate refresh token
        $RefreshToken = New-RefreshToken
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $RefreshToken -UserId $UserId -ExpiresAt $ExpiresAt

        $Results = @{
            user = @{
                UserId = $authContext.UserId
                email = $authContext.Email
                username = $authContext.Username
                userRole = $authContext.UserRole
                roles = $authContext.Roles
                permissions = $authContext.Permissions
                userManagements = $authContext.UserManagements
            }
        }
        $StatusCode = [HttpStatusCode]::Created
        
        # Set HTTP-only cookies for tokens using Set-Cookie headers
        $CookieHeader1 = "accessToken=$Token; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=900"
        $CookieHeader2 = "refreshToken=$RefreshToken; Path=/api/public/RefreshToken; HttpOnly; Secure; SameSite=Strict; Max-Age=604800"
        
        Write-Information "Setting cookies for signup: $CookieHeader1 | $CookieHeader2"
        
        # Return response as plain hashtable (NOT cast to [HttpResponseContext])
        return @{
            StatusCode = $StatusCode
            Body = $Results
            Headers = @{
                'Set-Cookie' = @($CookieHeader1, $CookieHeader2)
            }
        }
        
    } catch {
        Write-Error "Signup error: $($_.Exception.Message)"
        Write-Information "Signup error details: $($_.Exception | ConvertTo-Json -Depth 5)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Signup failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
        
        # Return error response without cookies
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
        }
    }
}