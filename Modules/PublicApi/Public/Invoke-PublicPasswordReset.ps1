function Invoke-PublicPasswordReset {
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
    $Table = Get-LinkToMeTable -TableName 'Users'

    if (-not $Body.email -and (-not $Body.code -or -not $Body.newPassword)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Email or code and new password required" }
        }
    }

    # Request password reset (send code via email)
    if ($Body.email) {
        $SafeEmail = Protect-TableQueryValue -Value $Body.email.ToLower()
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        if ($User) {
            # Generate 6-digit code
            $Code = -join ((0..5) | ForEach-Object { Get-Random -Minimum 0 -Maximum 10 })
            $Expiry = (Get-Date).AddHours(1).ToUniversalTime()
            $User | Add-Member -MemberType NoteProperty -Name PasswordResetCode -Value $Code -Force
            $User | Add-Member -MemberType NoteProperty -Name PasswordResetCodeExpiry -Value $Expiry -Force
            Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
            # Send code via email
            New-EmailMessage -To $User.PartitionKey -Template 'PasswordReset' -TemplateParams @{ ResetCode = $Code }
        }
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ message = "If your email exists, a reset code has been sent." }
        }
    }

    # Reset password (with code)
    if ($Body.code -and $Body.newPassword) {
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "PasswordResetCode eq '$($Body.code)'" | Select-Object -First 1
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid or expired code" }
            }
        }
        if ($User.PasswordResetCodeExpiry) {
            $expiryDate = $User.PasswordResetCodeExpiry
            if ($expiryDate -is [datetimeoffset]) {
                $expiryDate = $expiryDate.UtcDateTime
            }
            if ([DateTimeOffset]$expiryDate -lt [DateTimeOffset]::UtcNow) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Code expired" }
                }
            }
        }
        $PasswordCheck = Test-PasswordStrength -Password $Body.newPassword
        if (-not $PasswordCheck.Valid) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = $PasswordCheck.Message }
            }
        }
        $PasswordData = New-PasswordHash -Password $Body.newPassword
        $User.PasswordHash = $PasswordData.Hash
        $User.PasswordSalt = $PasswordData.Salt
        $User.PSObject.Properties.Remove('PasswordResetCode')
        $User.PSObject.Properties.Remove('PasswordResetCodeExpiry')
        Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
        Write-SecurityEvent -EventType 'PasswordReset' -UserId $User.RowKey -Email $User.PartitionKey -IpAddress $ClientIP -Endpoint 'public/passwordreset'
        # Send confirmation email
        New-EmailMessage -To $User.PartitionKey -Template 'PasswordResetConfirm'
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ message = "Password has been reset." }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = @{ error = "Invalid request" }
    }
}
