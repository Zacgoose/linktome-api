function Invoke-PublicSignup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public.Auth
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
            Write-SecurityEvent -EventType 'SignupFailed' -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup' -Metadata @{
                Reason = 'EmailAlreadyRegistered'
            }
            
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
            Write-SecurityEvent -EventType 'SignupFailed' -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup' -Metadata @{
                Reason = 'UsernameAlreadyTaken'
            }
            
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
        $RolesJson = [string](@($DefaultRole) | ConvertTo-Json -Compress)
        $PermissionsJson = [string]($DefaultPermissions | ConvertTo-Json -Compress)
        
        $NewUser = @{
            PartitionKey = $Body.email.ToLower()
            RowKey = [string]$UserId
            Username = $Body.username.ToLower()
            DisplayName = $Body.username
            Bio = ''
            Avatar = "https://ui-avatars.com/api/?name=$($Body.username)&size=200"
            PasswordHash = $PasswordData.Hash
            PasswordSalt = $PasswordData.Salt
            IsActive = [bool]$true
            Roles = $RolesJson
            Permissions = $PermissionsJson
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $NewUser -Force
        
        # Log successful signup
        Write-SecurityEvent -EventType 'SignupSuccess' -UserId $UserId -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup'
        
        $Token = New-LinkToMeJWT -UserId $UserId -Email $Body.email.ToLower() -Username $Body.username.ToLower() -Roles @($DefaultRole) -Permissions $DefaultPermissions
        
        # Generate refresh token
        $RefreshToken = New-RefreshToken
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $RefreshToken -UserId $UserId -ExpiresAt $ExpiresAt
        
        $Results = @{
            user = @{
                userId = $UserId
                email = $Body.email.ToLower()
                username = $Body.username.ToLower()
                roles = @($DefaultRole)
                permissions = $DefaultPermissions
            }
            accessToken = $Token
            refreshToken = $RefreshToken
        }
        $StatusCode = [HttpStatusCode]::Created
        
    } catch {
        Write-Error "Signup error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Signup failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}