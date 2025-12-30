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
    $ClientIP = Get-ClientIPAddress -Request $Request

    # === Validate Required Fields ===
    if (-not $Body.email -or -not $Body.password) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Email and password required" }
        }
    }

    if (-not (Test-EmailFormat -Email $Body.email)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid email format" }
        }
    }

    # === Validate Turnstile Token ===
    if (-not $Body.turnstileToken) {
        Write-SecurityEvent -EventType 'TurnstileMissing' -IpAddress $ClientIP -Endpoint 'public/login' -Email $Body.email
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Security verification required" }
        }
    }

    if (-not (Test-TurnstileToken -Token $Body.turnstileToken -RemoteIP $ClientIP)) {
        Write-SecurityEvent -EventType 'TurnstileFailed' -IpAddress $ClientIP -Endpoint 'public/login' -Email $Body.email
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Security verification failed. Please try again." }
        }
    }

    # === Log Suspicion Score (set by router, optional) ===
    if ($Request.SuspicionScore) {
        Write-Information "Login attempt | IP: $ClientIP | Email: $($Body.email) | Suspicion: $($Request.SuspicionScore) | Flags: $($Request.SuspicionFlags -join ', ')"
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        $SafeEmail = Protect-TableQueryValue -Value $Body.email.ToLower()
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        
        if (-not $User) {
            Write-SecurityEvent -EventType 'LoginFailed' -Email $Body.email -IpAddress $ClientIP -Endpoint 'public/login' -Reason 'UserNotFound'
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }
        
        $Valid = Test-PasswordHash -Password $Body.password -StoredHash $User.PasswordHash -StoredSalt $User.PasswordSalt
        
        if (-not $Valid) {
            Write-SecurityEvent -EventType 'LoginFailed' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/login' -Reason 'InvalidPassword'
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }

        try {
            $authContext = Get-UserAuthContext -User $User
        } catch {
            Write-Error "Auth context error: $($_.Exception.Message)"
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = $_.Exception.Message }
            }
        }

        $Token = New-LinkToMeJWT -User $User
        $RefreshToken = New-RefreshToken
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $RefreshToken -UserId $User.RowKey -ExpiresAt $ExpiresAt

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

        Write-SecurityEvent -EventType 'LoginSuccess' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/login'
        
        $AuthData = @{
            accessToken = $Token
            refreshToken = $RefreshToken
        } | ConvertTo-Json -Compress
        
        $CookieHeader = "auth=$AuthData; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=604800"
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = $Results
            Headers = @{
                'Set-Cookie' = $CookieHeader
            }
        }
        
    } catch {
        Write-Error "Login error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Login failed"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = $Results
        }
    }
}