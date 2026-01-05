function Invoke-Public2fatoken {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    .SYNOPSIS
        Handle 2FA token verification and resend requests
    .DESCRIPTION
        Handles 2FA token verification and resend requests via action query parameter
        - ?action=verify: Verify 2FA code and complete authentication
        - ?action=resend: Resend 2FA email code
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body
    $Action = $Request.Query.action
    $ClientIP = Get-ClientIPAddress -Request $Request

    # === Validate Action Parameter ===
    if (-not $Action) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Action parameter required" }
        }
    }

    # === Handle Different Actions ===
    switch ($Action) {
        "verify" {
            # === Validate Required Fields ===
            if (-not $Body.sessionId -or -not $Body.token) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Session ID and token required" }
                }
            }

            try {
                # Get 2FA session
                $Session = Get-TwoFactorSession -SessionId $Body.sessionId
                
                if (-not $Session) {
                    Write-SecurityEvent -EventType '2FAVerifyFailed' -IpAddress $ClientIP -Endpoint 'public/2fatoken' -Reason 'SessionNotFound'
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Unauthorized
                        Body = @{ error = "Session expired or invalid" }
                    }
                }

                # Check attempts remaining
                if ($Session.AttemptsRemaining -le 0) {
                    Write-SecurityEvent -EventType '2FAVerifyFailed' -UserId $Session.RowKey -IpAddress $ClientIP -Endpoint 'public/2fatoken' -Reason 'MaxAttemptsExceeded'
                    Remove-TwoFactorSession -SessionId $Body.sessionId
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Unauthorized
                        Body = @{ error = "Maximum verification attempts exceeded" }
                    }
                }

                # Get user
                $UsersTable = Get-LinkToMeTable -TableName 'Users'
                $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$($Session.RowKey)'" | Select-Object -First 1
                
                if (-not $User) {
                    Write-SecurityEvent -EventType '2FAVerifyFailed' -IpAddress $ClientIP -Endpoint 'public/2fatoken' -Reason 'UserNotFound'
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Unauthorized
                        Body = @{ error = "Invalid session" }
                    }
                }

                # Verify the token based on available methods
                $TokenValid = $false
                $MethodUsed = ""

                # Check email code if available
                if ($Session.Method -eq 'email' -or $Session.Method -eq 'both') {
                    if ($Session.EmailCodeHash) {
                        $ProvidedHash = Get-StringHash -InputString $Body.token
                        if ($ProvidedHash -eq $Session.EmailCodeHash) {
                            $TokenValid = $true
                            $MethodUsed = "email"
                        }
                    }
                }

                # Check TOTP if not already valid and TOTP is enabled
                if (-not $TokenValid -and ($Session.Method -eq 'totp' -or $Session.Method -eq 'both')) {
                    if ($User.TotpSecret) {
                        if (Test-TotpToken -Token $Body.token -Secret $User.TotpSecret) {
                            $TokenValid = $true
                            $MethodUsed = "totp"
                        }
                    }
                }

                if (-not $TokenValid) {
                    # Decrement attempts
                    $Session.AttemptsRemaining = $Session.AttemptsRemaining - 1
                    
                    $Table = Get-LinkToMeTable -TableName 'TwoFactorSessions'
                    Add-LinkToMeAzDataTableEntity @Table -Entity $Session -Force
                    
                    Write-SecurityEvent -EventType '2FAVerifyFailed' -UserId $Session.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/2fatoken' -Reason 'InvalidToken'
                    
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Invalid verification code" }
                    }
                }

                # Token is valid - complete authentication
                Remove-TwoFactorSession -SessionId $Body.sessionId

                # Generate tokens
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
                        tier = $authContext.Tier
                    }
                }

                Write-SecurityEvent -EventType '2FAVerifySuccess' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/2fatoken' -Reason "Method:$MethodUsed"
                
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
                Write-Error "2FA verification error: $($_.Exception.Message)"
                $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Verification failed"
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body = $Results
                }
            }
        }
        
        "resend" {
            # === Validate Required Fields ===
            if (-not $Body.sessionId) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Session ID required" }
                }
            }

            try {
                # Get 2FA session
                $Session = Get-TwoFactorSession -SessionId $Body.sessionId
                
                if (-not $Session) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Unauthorized
                        Body = @{ error = "Session expired or invalid" }
                    }
                }

                # Check if this is an email 2FA session
                if ($Session.Method -ne 'email' -and $Session.Method -ne 'both') {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Code resend is only available for email verification" }
                    }
                }

                # Check rate limit (60 seconds between resends)
                $Now = (Get-Date).ToUniversalTime()
                $TimeSinceLastResend = ($Now - $Session.LastResendAt).TotalSeconds
                
                if ($TimeSinceLastResend -lt 60) {
                    $WaitTime = [Math]::Ceiling(60 - $TimeSinceLastResend)
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::TooManyRequests
                        Body = @{ error = "Please wait before requesting another code" }
                        Headers = @{ 'Retry-After' = $WaitTime.ToString() }
                    }
                }

                # Get user
                $UsersTable = Get-LinkToMeTable -TableName 'Users'
                $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$($Session.RowKey)'" | Select-Object -First 1
                
                if (-not $User) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Unauthorized
                        Body = @{ error = "Invalid session" }
                    }
                }

                # Generate new code
                $NewCode = New-TwoFactorCode
                $HashedCode = Get-StringHash -InputString $NewCode

                # Send email
                $EmailSent = Send-TwoFactorEmail -Email $User.PartitionKey -Code $NewCode
                
                if (-not $EmailSent) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::InternalServerError
                        Body = @{ error = "Failed to send verification code" }
                    }
                }

                # Update session
                $Session.EmailCodeHash = $HashedCode
                $Session.LastResendAt = $Now
                
                $Table = Get-LinkToMeTable -TableName 'TwoFactorSessions'
                Add-LinkToMeAzDataTableEntity @Table -Entity $Session -Force

                Write-SecurityEvent -EventType '2FACodeResent' -UserId $Session.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/2fatoken'
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body = @{ message = "Code resent successfully" }
                }
                
            } catch {
                Write-Error "2FA resend error: $($_.Exception.Message)"
                $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Resend failed"
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body = $Results
                }
            }
        }
        
        default {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid action parameter" }
            }
        }
    }
}
