function Test-ApiRateLimit {
    <#
    .SYNOPSIS
        Check rate limits based on user tier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$KeyId,
        
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [string]$Tier
    )
    
    $TierLimits = @{
        'free' = @{
            RequestsPerMinute = 0
            RequestsPerDay    = 0
        }
        'pro' = @{
            RequestsPerMinute = 60
            RequestsPerDay    = 10000
        }
        'premium' = @{
            RequestsPerMinute = 120
            RequestsPerDay    = 50000
        }
        'enterprise' = @{
            RequestsPerMinute = 300
            RequestsPerDay    = -1
        }
    }
    
    $Limits = $TierLimits[$Tier]
    if (-not $Limits) { $Limits = $TierLimits['free'] }
    
    # Per-minute per key
    $MinuteCheck = Test-RateLimit `
        -Identifier "apikey:$KeyId" `
        -Endpoint 'v1-minute' `
        -MaxRequests $Limits.RequestsPerMinute `
        -WindowSeconds 60
    
    if (-not $MinuteCheck.Allowed) {
        return @{
            Allowed    = $false
            LimitType  = 'minute'
            Limit      = $Limits.RequestsPerMinute
            RetryAfter = $MinuteCheck.RetryAfter
        }
    }
    
    # Daily per user (across all keys)
    $DayCheck = Test-RateLimit `
        -Identifier "apiuser:$UserId" `
        -Endpoint 'v1-daily' `
        -MaxRequests $Limits.RequestsPerDay `
        -WindowSeconds 86400
    
    if (-not $DayCheck.Allowed) {
        return @{
            Allowed    = $false
            LimitType  = 'daily'
            Limit      = $Limits.RequestsPerDay
            RetryAfter = $DayCheck.RetryAfter
        }
    }
    
    return @{
        Allowed         = $true
        MinuteLimit     = $Limits.RequestsPerMinute
        MinuteRemaining = $Limits.RequestsPerMinute - $MinuteCheck.RequestCount
        DayLimit        = $Limits.RequestsPerDay
        DayRemaining    = $Limits.RequestsPerDay - $DayCheck.RequestCount
    }
}