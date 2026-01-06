function Invoke-AdminUpdateEmail {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:email
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

    # Validate required fields
    if (-not $Body.newEmail -or -not $Body.password) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "New email and password are required" }
        }
    }

    # Validate email format
    if (-not (Test-EmailFormat -Email $Body.newEmail)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid email format" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get current user record
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Verify password
        $Valid = Test-PasswordHash -Password $Body.password -StoredHash $UserData.PasswordHash -StoredSalt $UserData.PasswordSalt
        
        if (-not $Valid) {
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-SecurityEvent -EventType 'EmailChangeFailed' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/updateEmail' -Reason 'InvalidPassword'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Password is incorrect" }
            }
        }

        $NewEmailLower = $Body.newEmail.ToLower()
        $CurrentEmailLower = $UserData.PartitionKey.ToLower()
        
        # Check if email is already the same
        if ($NewEmailLower -eq $CurrentEmailLower) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "New email is the same as current email" }
            }
        }
        
        # Check if new email is already in use
        $SafeNewEmail = Protect-TableQueryValue -Value $NewEmailLower
        $ExistingEmail = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeNewEmail'" | Select-Object -First 1
        if ($ExistingEmail) {
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-SecurityEvent -EventType 'EmailChangeFailed' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/updateEmail' -Reason 'EmailAlreadyInUse'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Conflict
                Body = @{ error = "Email address already in use" }
            }
        }
        
        # Create new entity with new PartitionKey (email)
        # Azure Table Storage requires creating a new entity when changing PartitionKey
        $NewUser = @{
            PartitionKey = [string]$NewEmailLower
            RowKey = [string]$UserData.RowKey
            Username = $UserData.Username
            DisplayName = $UserData.DisplayName
            Bio = $UserData.Bio
            Avatar = $UserData.Avatar
            PasswordHash = $UserData.PasswordHash
            PasswordSalt = $UserData.PasswordSalt
            IsActive = $UserData.IsActive
            Roles = $UserData.Roles
            Permissions = $UserData.Permissions
            SubscriptionTier = $UserData.SubscriptionTier
            SubscriptionStatus = $UserData.SubscriptionStatus
            TwoFactorEmailEnabled = $UserData.TwoFactorEmailEnabled
            TwoFactorTotpEnabled = $UserData.TwoFactorTotpEnabled
            TotpSecret = $UserData.TotpSecret
            BackupCodes = $UserData.BackupCodes
        }
        
        # Copy any additional fields that might exist
        foreach ($prop in $UserData.PSObject.Properties) {
            if ($prop.Name -notin @('PartitionKey', 'RowKey', 'Timestamp', 'ETag')) {
                if (-not $NewUser.ContainsKey($prop.Name)) {
                    $NewUser[$prop.Name] = $prop.Value
                }
            }
        }
        
        # Add new entity
        Add-LinkToMeAzDataTableEntity @Table -Entity $NewUser -Force
        
        # Delete old entity
        Remove-LinkToMeAzDataTableEntity @Table -Entity $UserData
        
        # Log security event
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'EmailChanged' -UserId $UserId -Email $NewEmailLower -IpAddress $ClientIP -Endpoint 'admin/updateEmail'
        
        $Results = @{
            message = "Email updated successfully"
            email = $NewEmailLower
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Update email error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update email"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
