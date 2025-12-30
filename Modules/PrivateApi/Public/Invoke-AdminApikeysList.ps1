function Invoke-AdminApikeysList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:apiauth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    
    try {
        $Keys = Get-UserApiKeys -UserId $User.UserId
        $AvailablePermissions = Get-UserAvailablePermissions -UserId $User.UserId
        
        # Get user tier
        $UserTable = Get-LinkToMeTable -TableName 'Users'
        $UserRecord = Get-LinkToMeAzDataTableEntity @UserTable -Filter "RowKey eq '$($User.UserId)'" | Select-Object -First 1
        $Tier = if ($UserRecord -and $UserRecord.AccountTier) { $UserRecord.AccountTier } else { 'free' }
        
        $TierLimits = @{
            'free'       = @{ requestsPerMinute = 20; requestsPerDay = 1000 }
            'pro'        = @{ requestsPerMinute = 100; requestsPerDay = 50000 }
            'enterprise' = @{ requestsPerMinute = 500; requestsPerDay = 500000 }
        }
        
        $Limits = $TierLimits[$Tier] ?? $TierLimits['free']
        
        # Get daily usage (shared across all keys)
        $RateLimitTable = Get-LinkToMeTable -TableName 'RateLimits'
        $DailyRecord = Get-LinkToMeAzDataTableEntity @RateLimitTable -Filter "PartitionKey eq 'v1-daily' and RowKey eq 'apiuser-$($User.UserId)'" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        $DailyUsed = 0
        if ($DailyRecord) {
            $WindowStart = [DateTimeOffset]$DailyRecord.WindowStart
            $Now = [DateTimeOffset]::UtcNow
            
            if ($WindowStart -gt $Now.AddSeconds(-86400)) {
                $DailyUsed = [int]$DailyRecord.RequestCount
            }
        }
        
        # Get per-key minute usage
        $KeyUsage = @{}
        foreach ($Key in $Keys) {
            $MinuteRecord = Get-LinkToMeAzDataTableEntity @RateLimitTable -Filter "PartitionKey eq 'v1-minute' and RowKey eq 'apikey-$($Key.keyId)'" -ErrorAction SilentlyContinue | Select-Object -First 1
            
            $MinuteUsed = 0
            if ($MinuteRecord) {
                $WindowStart = [DateTimeOffset]$MinuteRecord.WindowStart
                $Now = [DateTimeOffset]::UtcNow
                
                if ($WindowStart -gt $Now.AddSeconds(-60)) {
                    $MinuteUsed = [int]$MinuteRecord.RequestCount
                }
            }
            
            $KeyUsage[$Key.keyId] = @{
                minuteUsed      = $MinuteUsed
                minuteRemaining = [Math]::Max(0, $Limits.requestsPerMinute - $MinuteUsed)
            }
        }
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ 
                keys                 = @($Keys)
                availablePermissions = @($AvailablePermissions)
                tier                 = $Tier
                rateLimits           = $Limits
                usage                = @{
                dailyUsed            = $DailyUsed
                dailyRemaining       = [Math]::Max(0, $Limits.requestsPerDay - $DailyUsed)
                perKey               = $KeyUsage
                }
            }
        }
    }
    catch {
        Write-Error "List API keys error: $($_.Exception.Message)"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{ error = "Failed to list API keys" }
        }
    }
}