function Invoke-AdminApikeysCreate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        create:apiauth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body
    
    # Get user object to check tier
    $UsersTable = Get-LinkToMeTable -TableName 'Users'
    $SafeUserId = Protect-TableQueryValue -Value $User.UserId
    $UserData = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
    
    if (-not $UserData) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::NotFound
            Body = @{ error = "User not found" }
        }
    }
    
    # Check if user has API access
    $UserTier = $UserData.SubscriptionTier
    $TierInfo = Get-TierFeatures -Tier $UserTier
    
    if (-not $TierInfo.limits.apiAccess) {
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-FeatureUsageEvent -UserId $User.UserId -Feature 'apiAccess' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/apikeys/create'
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{ error = "API access requires Pro tier or higher. Upgrade to create and use API keys." }
        }
    }
    
    if (-not $Body.name) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "name is required" }
        }
    }
    
    # Check API keys limit based on tier
    $ExistingKeys = Get-UserApiKeys -UserId $User.UserId
    $MaxKeys = $TierInfo.limits.apiKeysLimit
    
    if ($MaxKeys -ne -1 -and $ExistingKeys.Count -ge $MaxKeys) {
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-FeatureUsageEvent -UserId $User.UserId -Feature 'apiKeysLimit_exceeded' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/apikeys/create'
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{ error = "API key limit exceeded. Your $($TierInfo.tierName) plan allows up to $MaxKeys API keys. You currently have $($ExistingKeys.Count) keys." }
        }
    }
    
    # Get user's available permissions (for validation)
    $AvailablePermissions = Get-UserAvailablePermissions -UserId $User.UserId
    
    # Validate requested permissions
    $RequestedPermissions = @()
    if ($Body.permissions) {
        $RequestedPermissions = @($Body.permissions)
        
        foreach ($Perm in $RequestedPermissions) {
            if ($Perm -notin $AvailablePermissions) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ 
                        error = "Cannot grant permission '$Perm' - not available to your account"
                        availablePermissions = $AvailablePermissions
                    }
                }
            }
        }
    }
    
    try {
        $NewKey = New-ApiKey -UserId $User.UserId -Name $Body.name -Permissions $RequestedPermissions
        
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'ApiKeyCreated' -UserId $User.UserId -IpAddress $ClientIP `
            -Endpoint 'admin/apikeys/create' -Reason "KeyId: $($NewKey.keyId), Permissions: $($RequestedPermissions -join ',')"
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Created
            Body = @{
                message = "API key created. Save this key now - it won't be shown again!"
                key     = $NewKey
            }
        }
    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{ error = "Failed to create key: $($_.Exception.Message)" }
        }
    }
}