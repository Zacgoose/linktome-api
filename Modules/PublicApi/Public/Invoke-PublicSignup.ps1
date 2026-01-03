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
    $ClientIP = Get-ClientIPAddress -Request $Request

    # === Validate Required Fields ===
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

    # === Validate Turnstile Token ===
    if (-not $Body.turnstileToken) {
        Write-SecurityEvent -EventType 'TurnstileMissing' -IpAddress $ClientIP -Endpoint 'public/signup' -Email $Body.email -Username $Body.username
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Security verification required" }
        }
    }

    if (-not (Test-TurnstileToken -Token $Body.turnstileToken -RemoteIP $ClientIP)) {
        Write-SecurityEvent -EventType 'TurnstileFailed' -IpAddress $ClientIP -Endpoint 'public/signup' -Email $Body.email -Username $Body.username
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Security verification failed. Please try again." }
        }
    }

    # === Log Suspicion Score (set by router) ===
    if ($Request.SuspicionScore) {
        Write-Information "Signup attempt | IP: $ClientIP | Email: $($Body.email) | Username: $($Body.username) | Suspicion: $($Request.SuspicionScore) | Flags: $($Request.SuspicionFlags -join ', ')"
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Check if email exists - sanitize for query
        $SafeEmail = Protect-TableQueryValue -Value $Body.email.ToLower()
        $ExistingEmail = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        if ($ExistingEmail) {
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
            Roles = '["user"]'
            Permissions = ([string](Get-DefaultRolePermissions -Role 'user' | ConvertTo-Json -Compress))
            SubscriptionTier = [string]'free'
            SubscriptionStatus = [string]'active'
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $NewUser -Force
        
        $CreatedUser = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$UserId'" | Select-Object -First 1

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
                tier = $authContext.Tier
            }
        }
        
        $AuthData = @{
            accessToken = $Token
            refreshToken = $RefreshToken
        } | ConvertTo-Json -Compress
        
        $CookieHeader = "auth=$AuthData; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=604800"
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Created
            Body = $Results
            Headers = @{
                'Set-Cookie' = $CookieHeader
            }
        }
        
    } catch {
        Write-Error "Signup error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Signup failed"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = $Results
        }
    }
}