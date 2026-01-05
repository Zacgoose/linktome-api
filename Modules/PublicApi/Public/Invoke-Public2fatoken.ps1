function Invoke-Public2fatoken {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    .SYNOPSIS
        Handle 2FA token verification, setup, and management
    .DESCRIPTION
        Handles 2FA operations via action query parameter
        - ?action=verify: Verify 2FA code and complete authentication (public)
        - ?action=resend: Resend 2FA email code (public)
        - ?action=setup: Setup 2FA for user (requires authentication)
        - ?action=enable: Enable 2FA after verification (requires authentication)
        - ?action=disable: Disable 2FA for user (requires authentication)
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
                        try {
                            # Decrypt TOTP secret before verification
                            $DecryptedSecret = Unprotect-TotpSecret -EncryptedText $User.TotpSecret
                            if (Test-TotpToken -Token $Body.token -Secret $DecryptedSecret) {
                                $TokenValid = $true
                                $MethodUsed = "totp"
                            }
                        }
                        catch {
                            Write-Warning "TOTP verification failed for user $($Session.RowKey)"
                        }
                    }
                }

                # Check backup code if not already valid
                if (-not $TokenValid) {
                    # Only check backup codes if user has them
                    if ($User.BackupCodes -and $User.BackupCodes -ne '[]') {
                        if (Test-BackupCode -UserId $Session.RowKey -SubmittedCode $Body.token) {
                            $TokenValid = $true
                            $MethodUsed = "backup"
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
        
        "setup" {
            # === Setup 2FA for authenticated user ===
            # This action requires authentication
            if (-not $Request.AuthenticatedUser) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Unauthorized
                    Body = @{ error = "Authentication required" }
                }
            }

            try {
                $User = $Request.AuthenticatedUser
                $UserId = $User.UserId
                
                # Get full user record from database
                $UsersTable = Get-LinkToMeTable -TableName 'Users'
                $UserRecord = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$UserId'" | Select-Object -First 1
                
                if (-not $UserRecord) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body = @{ error = "User not found" }
                    }
                }
                
                # Check if setup type is specified (email, totp, or both)
                $SetupType = $Body.type
                if (-not $SetupType) {
                    $SetupType = "totp"  # Default to TOTP
                }
                
                $Response = @{}
                
                # Setup TOTP if requested
                if ($SetupType -eq "totp" -or $SetupType -eq "both") {
                    # Generate TOTP secret
                    $TotpSecret = New-TotpSecret
                    
                    # Encrypt the secret
                    $EncryptedSecret = Protect-TotpSecret -PlainText $TotpSecret
                    
                    # Generate QR code data
                    $QRData = New-TotpQRCode -Secret $TotpSecret -AccountName $UserRecord.PartitionKey
                    
                    # Generate backup codes
                    $BackupCodes = New-BackupCodes -Count 10
                    
                    # Store encrypted secret and backup codes
                    $UserRecord.TotpSecret = $EncryptedSecret
                    Save-BackupCodes -UserId $UserId -PlainTextCodes $BackupCodes | Out-Null
                    
                    # Don't enable yet - user needs to verify it works first
                    # That will happen in a separate "enable" action
                    
                    Add-LinkToMeAzDataTableEntity @UsersTable -Entity $UserRecord -Force
                    
                    $Response.totp = @{
                        secret = $TotpSecret
                        qrCodeUri = $QRData.uri
                        backupCodes = $BackupCodes
                        issuer = $QRData.issuer
                        accountName = $QRData.accountName
                    }
                }
                
                # Setup email 2FA if requested
                if ($SetupType -eq "email" -or $SetupType -eq "both") {
                    # Email 2FA doesn't require setup - just enable it
                    $Response.email = @{
                        ready = $true
                        accountEmail = $UserRecord.PartitionKey
                    }
                }
                
                Write-SecurityEvent -EventType '2FASetupInitiated' -UserId $UserId -Email $UserRecord.PartitionKey -Username $UserRecord.Username -IpAddress $ClientIP -Endpoint 'public/2fatoken' -Reason "Type:$SetupType"
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body = @{
                        message = "2FA setup initiated"
                        type = $SetupType
                        data = $Response
                        note = "Please verify TOTP code before enabling. Use action=enable to complete setup."
                    }
                }
                
            } catch {
                Write-Error "2FA setup error: $($_.Exception.Message)"
                $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Setup failed"
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body = $Results
                }
            }
        }
        
        "enable" {
            # === Enable 2FA after verification ===
            # This action requires authentication
            if (-not $Request.AuthenticatedUser) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Unauthorized
                    Body = @{ error = "Authentication required" }
                }
            }

            # === Validate Required Fields ===
            if (-not $Body.type -or -not $Body.token) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Type and verification token required" }
                }
            }

            try {
                $User = $Request.AuthenticatedUser
                $UserId = $User.UserId
                
                # Get full user record from database
                $UsersTable = Get-LinkToMeTable -TableName 'Users'
                $UserRecord = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$UserId'" | Select-Object -First 1
                
                if (-not $UserRecord) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body = @{ error = "User not found" }
                    }
                }
                
                $EnableType = $Body.type  # "email", "totp", or "both"
                $TokenValid = $false
                
                # Verify token before enabling
                if ($EnableType -eq "totp" -or $EnableType -eq "both") {
                    if ($UserRecord.TotpSecret) {
                        try {
                            $DecryptedSecret = Unprotect-TotpSecret -EncryptedText $UserRecord.TotpSecret
                            if (Test-TotpToken -Token $Body.token -Secret $DecryptedSecret) {
                                $TokenValid = $true
                                $UserRecord.TwoFactorTotpEnabled = $true
                            }
                        }
                        catch {
                            Write-Warning "TOTP verification failed during enable for user $UserId"
                        }
                    }
                    else {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "TOTP not set up. Use action=setup first." }
                        }
                    }
                }
                
                # Email doesn't need token verification for enable
                if ($EnableType -eq "email") {
                    $TokenValid = $true
                    $UserRecord.TwoFactorEmailEnabled = $true
                }
                
                # For "both", enable email too if TOTP was verified
                if ($EnableType -eq "both" -and $TokenValid) {
                    $UserRecord.TwoFactorEmailEnabled = $true
                }
                
                if (-not $TokenValid) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Invalid verification code. Please try again." }
                    }
                }
                
                # Save the enabled status
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $UserRecord -Force
                
                Write-SecurityEvent -EventType '2FAEnabled' -UserId $UserId -Email $UserRecord.PartitionKey -Username $UserRecord.Username -IpAddress $ClientIP -Endpoint 'public/2fatoken' -Reason "Type:$EnableType"
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body = @{
                        message = "Two-factor authentication enabled successfully"
                        type = $EnableType
                        emailEnabled = $UserRecord.TwoFactorEmailEnabled -eq $true
                        totpEnabled = $UserRecord.TwoFactorTotpEnabled -eq $true
                    }
                }
                
            } catch {
                Write-Error "2FA enable error: $($_.Exception.Message)"
                $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Enable failed"
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body = $Results
                }
            }
        }
        
        "disable" {
            # === Disable 2FA for authenticated user ===
            # This action requires authentication
            if (-not $Request.AuthenticatedUser) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Unauthorized
                    Body = @{ error = "Authentication required" }
                }
            }

            try {
                $User = $Request.AuthenticatedUser
                $UserId = $User.UserId
                
                # Get full user record from database
                $UsersTable = Get-LinkToMeTable -TableName 'Users'
                $UserRecord = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$UserId'" | Select-Object -First 1
                
                if (-not $UserRecord) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body = @{ error = "User not found" }
                    }
                }
                
                # Disable both methods
                $UserRecord.TwoFactorEmailEnabled = $false
                $UserRecord.TwoFactorTotpEnabled = $false
                
                # Optionally clear TOTP secret and backup codes for security
                # $UserRecord.TotpSecret = ""
                # $UserRecord.BackupCodes = "[]"
                
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $UserRecord -Force
                
                Write-SecurityEvent -EventType '2FADisabled' -UserId $UserId -Email $UserRecord.PartitionKey -Username $UserRecord.Username -IpAddress $ClientIP -Endpoint 'public/2fatoken'
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body = @{
                        message = "Two-factor authentication disabled successfully"
                        emailEnabled = $false
                        totpEnabled = $false
                    }
                }
                
            } catch {
                Write-Error "2FA disable error: $($_.Exception.Message)"
                $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Disable failed"
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
