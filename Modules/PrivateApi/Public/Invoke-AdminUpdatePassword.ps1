function Invoke-AdminUpdatePassword {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:password
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

    # Validate required fields
    if (-not $Body.currentPassword -or -not $Body.newPassword) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Current password and new password are required" }
        }
    }

    # Validate new password strength
    $PasswordCheck = Test-PasswordStrength -Password $Body.newPassword
    if (-not $PasswordCheck.Valid) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = $PasswordCheck.Message }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get user record
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Verify current password
        $Valid = Test-PasswordHash -Password $Body.currentPassword -StoredHash $UserData.PasswordHash -StoredSalt $UserData.PasswordSalt
        
        if (-not $Valid) {
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-SecurityEvent -EventType 'PasswordChangeFailed' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/updatePassword' -Reason 'InvalidCurrentPassword'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Current password is incorrect" }
            }
        }
        
        # Generate new password hash
        $PasswordData = New-PasswordHash -Password $Body.newPassword
        
        # Update password
        $UserData.PasswordHash = $PasswordData.Hash
        $UserData.PasswordSalt = $PasswordData.Salt
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        # Log security event
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'PasswordChanged' -UserId $UserId -Email $UserData.PartitionKey -IpAddress $ClientIP -Endpoint 'admin/updatePassword'
        
        $Results = @{
            message = "Password updated successfully"
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Update password error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update password"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
