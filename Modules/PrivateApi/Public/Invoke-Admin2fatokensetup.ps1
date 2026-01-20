function Invoke-Admin2fatokensetup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:2fauth
    .SYNOPSIS
        Handle 2FA setup, enable, and disable for authenticated users
    .DESCRIPTION
        Handles 2FA management operations via action query parameter
        - ?action=setup: Setup 2FA for user (generates TOTP secret, QR code, backup codes)
        - ?action=enable: Enable 2FA after verification
        - ?action=disable: Disable 2FA for user
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body
    $Action = $Request.Query.action
    $ClientIP = Get-ClientIPAddress -Request $Request
    $User = $Request.AuthenticatedUser
    $UserId = $User.UserId

    # === Validate Action Parameter ===
    if (-not $Action) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Action parameter required" }
        }
    }

    # === Handle Different Actions ===
    switch ($Action) {
        "setup" {
            # === Setup 2FA for authenticated user ===
            try {
                $UsersTable = Get-LinkToMeTable -TableName 'Users'
                $UserRecord = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$UserId'" | Select-Object -First 1
                if (-not $UserRecord) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body = @{ error = "User not found" }
                    }
                }
                $SetupType = $Body.type
                if (-not $SetupType) { $SetupType = "totp" }
                $Response = @{}
                # Setup TOTP if requested
                if ($SetupType -eq "totp" -or $SetupType -eq "both") {
                    $TotpSecret = New-TotpSecret
                    $EncryptedSecret = Protect-TotpSecret -PlainText $TotpSecret
                    $QRData = New-TotpQRCode -Secret $TotpSecret -AccountName $UserRecord.PartitionKey
                    $BackupCodes = New-BackupCodes -Count 10
                    if (-not $UserRecord.PSObject.Properties['TotpSecret']) {
                        $UserRecord | Add-Member -NotePropertyName TotpSecret -NotePropertyValue $EncryptedSecret -Force
                    } else {
                        $UserRecord.TotpSecret = $EncryptedSecret
                    }
                    $SaveResult = Save-BackupCodes -UserId $UserId -PlainTextCodes $BackupCodes
                    if (-not $SaveResult) {
                        Write-Error "Failed to save backup codes"
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::InternalServerError
                            Body = @{ error = "Failed to save backup codes" }
                        }
                    }
                    Add-LinkToMeAzDataTableEntity @UsersTable -OperationType 'UpsertMerge' -Entity $UserRecord
                    $Response.totp = @{
                        secret = $TotpSecret
                        qrCodeUri = $QRData.uri
                        backupCodes = $BackupCodes
                        issuer = $QRData.issuer
                        accountName = $QRData.accountName
                    }
                }
                # Setup email 2FA if requested (session-based)
                if ($SetupType -eq "email" -or $SetupType -eq "both") {
                    $Email2FACode = New-TwoFactorCode
                    $Session = New-TwoFactorSession -UserId $UserId -Method 'email' -EmailCode $Email2FACode
                    Send-TwoFactorEmail -Email $UserRecord.PartitionKey -Code $Email2FACode | Out-Null
                    $Response.email = @{
                        ready = $true
                        accountEmail = $UserRecord.PartitionKey
                    }
                }
                Write-SecurityEvent -EventType '2FASetupInitiated' -UserId $UserId -Email $UserRecord.PartitionKey -Username $UserRecord.Username -IpAddress $ClientIP -Endpoint 'admin/2fatokensetup' -Reason "Type:$SetupType"
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body = @{
                        type = $SetupType
                        data = $Response
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

            # === Validate Required Fields ===
            if (-not $Body.type -or -not $Body.token) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Type and verification token required" }
                }
            }

            try {
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
                            Write-Information "Attempting to decrypt TOTP secret for user $UserId"
                            $DecryptedSecret = Unprotect-TotpSecret -EncryptedText $UserRecord.TotpSecret
                            Write-Information "TOTP secret decrypted successfully: length=$($DecryptedSecret.Length)"
                            Write-Information "Token received: '$($Body.token)' (length=$($Body.token.Length))"
                            
                            # Log the current time window for debugging
                            $UnixTime = [int][double]::Parse((Get-Date -UFormat %s))
                            $TimeStep = [Math]::Floor($UnixTime / 30)
                            Write-Information "Current time step: $TimeStep (Unix: $UnixTime)"
                            
                            if (Test-TotpToken -Token $Body.token -Secret $DecryptedSecret) {
                                Write-Information "TOTP token verified successfully"
                                $TokenValid = $true
                                if (-not $UserRecord.PSObject.Properties['TwoFactorTotpEnabled']) {
                                    $UserRecord | Add-Member -NotePropertyName TwoFactorTotpEnabled -NotePropertyValue $true -Force
                                } else {
                                    $UserRecord.TwoFactorTotpEnabled = $true
                                }
                            }
                            else {
                                Write-Warning "TOTP token verification failed - token does not match"
                                Write-Warning "Secret (first 10 chars): $($DecryptedSecret.Substring(0, [Math]::Min(10, $DecryptedSecret.Length)))"
                            }
                        }
                        catch {
                            Write-Error "TOTP verification error during enable for user $UserId : $($_.Exception.Message)"
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::InternalServerError
                                Body = @{ error = "Failed to verify TOTP token. Error: $($_.Exception.Message)" }
                            }
                        }
                    }
                    else {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "TOTP not set up. Use action=setup first." }
                        }
                    }
                }
                
                # Email 2FA: verify the code using session for the authenticated user
                if ($EnableType -eq "email") {
                    $TokenValid = $false
                    $SessionsTable = Get-LinkToMeTable -TableName 'TwoFactorSessions'
                    $Sessions = Get-LinkToMeAzDataTableEntity @SessionsTable -Filter "RowKey eq '$UserId' and Method eq 'email'" | Sort-Object -Property ExpiresAt -Descending
                    $Session = $Sessions | Where-Object { $_.ExpiresAt -gt (Get-Date).ToUniversalTime() -and $_.AttemptsRemaining -gt 0 } | Select-Object -First 1
                    if ($Session) {
                        $HashedToken = Get-StringHash -InputString $Body.token
                        if ($Session.EmailCodeHash -eq $HashedToken) {
                            $TokenValid = $true
                            if (-not $UserRecord.PSObject.Properties['TwoFactorEmailEnabled']) {
                                $UserRecord | Add-Member -NotePropertyName TwoFactorEmailEnabled -NotePropertyValue $true -Force
                            } else {
                                $UserRecord.TwoFactorEmailEnabled = $true
                            }
                            Remove-TwoFactorSession -SessionId $Session.PartitionKey
                        } else {
                            $Session.AttemptsRemaining--
                            Add-LinkToMeAzDataTableEntity -Entity $Session -TableName 'TwoFactorSessions' -Force
                        }
                    }
                }
                
                # For "both", enable email too if TOTP was verified
                if ($EnableType -eq "both" -and $TokenValid) {
                    if (-not $UserRecord.PSObject.Properties['TwoFactorEmailEnabled']) {
                        $UserRecord | Add-Member -NotePropertyName TwoFactorEmailEnabled -NotePropertyValue $true -Force
                    } else {
                        $UserRecord.TwoFactorEmailEnabled = $true
                    }
                }
                
                if (-not $TokenValid) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Invalid verification code. Please try again." }
                    }
                }
                
                # Save the enabled status
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $UserRecord -OperationType 'UpsertMerge'
                
                Write-SecurityEvent -EventType '2FAEnabled' -UserId $UserId -Email $UserRecord.PartitionKey -Username $UserRecord.Username -IpAddress $ClientIP -Endpoint 'admin/2fatokensetup' -Reason "Type:$EnableType"
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body = @{
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
            try {
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
                if (-not $UserRecord.PSObject.Properties['TwoFactorEmailEnabled']) {
                    $UserRecord | Add-Member -NotePropertyName TwoFactorEmailEnabled -NotePropertyValue $false -Force
                } else {
                    $UserRecord.TwoFactorEmailEnabled = $false
                }
                if (-not $UserRecord.PSObject.Properties['TwoFactorTotpEnabled']) {
                    $UserRecord | Add-Member -NotePropertyName TwoFactorTotpEnabled -NotePropertyValue $false -Force
                } else {
                    $UserRecord.TwoFactorTotpEnabled = $false
                }
                
                # Clear TOTP secret and backup codes for security
                if (-not $UserRecord.PSObject.Properties['TotpSecret']) {
                    $UserRecord | Add-Member -NotePropertyName TotpSecret -NotePropertyValue '' -Force
                } else {
                    $UserRecord.TotpSecret = ''
                }
                if (-not $UserRecord.PSObject.Properties['BackupCodes']) {
                    $UserRecord | Add-Member -NotePropertyName BackupCodes -NotePropertyValue '[]' -Force
                } else {
                    $UserRecord.BackupCodes = '[]'
                }
                
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $UserRecord -OperationType 'UpsertMerge'
                
                Write-SecurityEvent -EventType '2FADisabled' -UserId $UserId -Email $UserRecord.PartitionKey -Username $UserRecord.Username -IpAddress $ClientIP -Endpoint 'admin/2fatokensetup'
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body = @{
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
                Body = @{ error = "Invalid action parameter. Use: setup, enable, or disable" }
            }
        }
    }
}
