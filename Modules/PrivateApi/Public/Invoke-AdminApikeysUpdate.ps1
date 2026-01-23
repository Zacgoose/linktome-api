function Invoke-AdminApikeysUpdate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        update:apiauth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body
    $KeyId = $Request.Query.keyId

    # Get user object to check tier
    $UsersTable = Get-LinkToMeTable -TableName 'Users'
    $SafeUserId = Protect-TableQueryValue -Value $User.UserId
    $UserData = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
    
    # Check if user has API access
    $UserTier = $UserData.SubscriptionTier
    $TierInfo = Get-TierFeatures -Tier $UserTier
    
    if (-not $TierInfo.limits.apiAccess) {
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-FeatureUsageEvent -UserId $User.UserId -Feature 'apiAccess' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/ApikeysUpdate'
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{ error = "API access requires Pro tier or higher. Upgrade to manage and use API keys." }
        }
    }
    
    if (-not $KeyId) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "keyId query parameter required" }
        }
    }
    
    if ($null -eq $Body.permissions) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "permissions array required" }
        }
    }
    
    # Validate permissions
    $AvailablePermissions = Get-UserAvailablePermissions -UserId $User.UserId
    
    foreach ($Perm in $Body.permissions) {
        if ($Perm -notin $AvailablePermissions) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ 
                    error = "Cannot grant permission '$Perm'"
                    availablePermissions = $AvailablePermissions
                }
            }
        }
    }
    
    $Result = Update-ApiKeyPermissions -UserId $User.UserId -KeyId $KeyId -Permissions @($Body.permissions)
    
    if ($Result.Success) {
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'ApiKeyUpdated' -UserId $User.UserId -IpAddress $ClientIP `
            -Endpoint 'admin/apikeys/update' -Reason "KeyId: $KeyId, Permissions: $($Body.permissions -join ',')"
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ message = "Permissions updated" }
        }
    } else {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::NotFound
            Body = @{ error = $Result.Error }
        }
    }
}