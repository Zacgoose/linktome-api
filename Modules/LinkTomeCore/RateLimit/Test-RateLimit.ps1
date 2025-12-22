function Test-RateLimit {
    <#
    .SYNOPSIS
        Check if request is within rate limits
    .DESCRIPTION
        Checks rate limits using Azure Table Storage to track request counts per IP/identifier.
        Can be upgraded to Azure API Management or Front Door for additional features.
    .PARAMETER Identifier
        Unique identifier for rate limiting (typically IP address or user ID)
    .PARAMETER Endpoint
        The endpoint being accessed (e.g., 'public/login', 'public/signup')
    .PARAMETER MaxRequests
        Maximum number of requests allowed in the time window
    .PARAMETER WindowSeconds
        Time window in seconds for rate limiting
    .EXAMPLE
        $IsAllowed = Test-RateLimit -Identifier $ClientIP -Endpoint 'public/login' -MaxRequests 5 -WindowSeconds 60
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Identifier,
        
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter(Mandatory)]
        [int]$MaxRequests,
        
        [Parameter(Mandatory)]
        [int]$WindowSeconds
    )
    
    try {
        # Get or create RateLimits table
        $Table = Get-LinkToMeTable -TableName 'RateLimits'
        
        # Create composite key from endpoint and identifier
        $PartitionKey = $Endpoint -replace '/', '-'
        # Sanitize identifier for use as RowKey (remove invalid chars and normalize dashes)
        $RowKey = $Identifier -replace '[^a-zA-Z0-9]', '-'
        $RowKey = $RowKey -replace '-+', '-'  # Replace consecutive dashes with single dash
        $RowKey = $RowKey.Trim('-')  # Remove leading/trailing dashes
        
        # Get current timestamp
        $Now = [DateTimeOffset]::UtcNow
        $WindowStart = $Now.AddSeconds(-$WindowSeconds)
        
        # Try to get existing rate limit record
        $RateLimitRecord = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$PartitionKey' and RowKey eq '$RowKey'" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if (-not $RateLimitRecord) {
            # First request - create new record
            $NewRecord = @{
                PartitionKey = $PartitionKey
                RowKey = $RowKey
                RequestCount = 1
                WindowStart = $Now
                LastRequest = $Now
            }
            Add-LinkToMeAzDataTableEntity @Table -Entity $NewRecord -Force | Out-Null
            
            return @{
                Allowed = $true
                RequestCount = 1
                MaxRequests = $MaxRequests
                RetryAfter = 0
            }
        }
        
        # Check if we're still in the same time window
        $RecordWindowStart = [DateTimeOffset]$RateLimitRecord.WindowStart
        
        if ($RecordWindowStart -lt $WindowStart) {
            # Window expired - reset counter
            $RateLimitRecord.RequestCount = 1
            $RateLimitRecord.WindowStart = $Now
            $RateLimitRecord.LastRequest = $Now
            Add-LinkToMeAzDataTableEntity @Table -Entity $RateLimitRecord -Force | Out-Null
            
            return @{
                Allowed = $true
                RequestCount = 1
                MaxRequests = $MaxRequests
                RetryAfter = 0
            }
        }
        
        # Still in time window - check if limit exceeded
        $CurrentCount = [int]$RateLimitRecord.RequestCount
        
        if ($CurrentCount ->= $MaxRequests) {
            # Rate limit exceeded
            $SecondsUntilReset = [int]($WindowSeconds - ($Now - $RecordWindowStart).TotalSeconds)
            
            return @{
                Allowed = $false
                RequestCount = $CurrentCount
                MaxRequests = $MaxRequests
                RetryAfter = $SecondsUntilReset
            }
        }
        
        # Within limit - increment counter
        $RateLimitRecord.RequestCount = $CurrentCount + 1
        $RateLimitRecord.LastRequest = $Now
        Add-LinkToMeAzDataTableEntity @Table -Entity $RateLimitRecord -Force | Out-Null
        
        return @{
            Allowed = $true
            RequestCount = $CurrentCount + 1
            MaxRequests = $MaxRequests
            RetryAfter = 0
        }
        
    } catch {
        # If rate limiting fails, allow the request (fail open)
        Write-Warning "Rate limit check failed: $($_.Exception.Message). Allowing request."
        return @{
            Allowed = $true
            RequestCount = 0
            MaxRequests = $MaxRequests
            RetryAfter = 0
        }
    }
}
