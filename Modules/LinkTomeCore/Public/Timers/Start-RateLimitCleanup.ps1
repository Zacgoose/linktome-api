function Start-RateLimitCleanup {
    <#
    .SYNOPSIS
        Cleanup expired rate limit entries
    .DESCRIPTION
        Timer function to remove expired rate limit tracking entries.
        Deletes rate limit records older than 1 hour (longest typical rate limit window).
    .FUNCTIONALITY
        Timer
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Information "Starting rate limit cleanup"
        
        # Get RateLimits table
        $Table = Get-LinkToMeTable -TableName 'RateLimits'
        
        # Get all rate limit entries
        $AllEntries = Get-LinkToMeAzDataTableEntity @Table
        
        if (-not $AllEntries -or $AllEntries.Count -eq 0) {
            Write-Information "No rate limit entries found to clean up"
            return @{
                Status = "Success"
                Message = "No rate limit entries to clean up"
                DeletedCount = 0
            }
        }
        
        # Calculate cutoff time (1 hour ago - covers most rate limit windows)
        $CutoffTime = [DateTimeOffset]::UtcNow.AddHours(-1)
        
        # Find entries to delete (older than cutoff based on LastRequest timestamp)
        $EntriesToDelete = @($AllEntries | Where-Object { 
            $_.LastRequest -and ([DateTimeOffset]$_.LastRequest -lt $CutoffTime)
        })
        
        $DeletedCount = 0
        
        # Delete old entries
        foreach ($Entry in $EntriesToDelete) {
            try {
                Remove-AzDataTableEntity -Context $Table.Context -Entity $Entry | Out-Null
                $DeletedCount++
            } catch {
                Write-Warning "Failed to delete rate limit entry $($Entry.RowKey): $($_.Exception.Message)"
            }
        }
        
        Write-Information "Rate limit cleanup completed - deleted $DeletedCount expired entries"
        return @{
            Status = "Success"
            Message = "Rate limit cleanup completed"
            DeletedCount = $DeletedCount
            TotalEntries = $AllEntries.Count
        }
    } catch {
        Write-Warning "Rate limit cleanup failed: $($_.Exception.Message)"
        throw
    }
}
