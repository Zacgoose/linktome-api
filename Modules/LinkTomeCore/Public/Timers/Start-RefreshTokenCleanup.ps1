function Start-RefreshTokenCleanup {
    <#
    .SYNOPSIS
        Cleanup expired refresh tokens
    .DESCRIPTION
        Timer function to remove expired refresh tokens from the RefreshTokens table.
        Refresh tokens typically expire after 30-90 days. This cleanup removes tokens
        that are expired or invalidated.
    .FUNCTIONALITY
        Timer
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Information "Starting refresh token cleanup"
        
        # Get RefreshTokens table
        $Table = Get-LinkToMeTable -TableName 'RefreshTokens'
        
        # Get all refresh tokens
        $AllTokens = Get-LinkToMeAzDataTableEntity @Table
        
        if (-not $AllTokens -or $AllTokens.Count -eq 0) {
            Write-Information "No refresh tokens found to clean up"
            return @{
                Status = "Success"
                Message = "No refresh tokens to clean up"
                DeletedCount = 0
            }
        }
        
        # Current time for expiration checks
        $Now = [DateTimeOffset]::UtcNow
        
        # Find expired or invalid tokens
        $TokensToDelete = @($AllTokens | Where-Object { 
            # Delete if explicitly marked as invalid
            if ($_.IsValid -eq $false) {
                return $true
            }
            
            # Delete if expired (ExpiresAt is in ISO 8601 string format)
            if ($_.ExpiresAt) {
                try {
                    $ExpiresAt = [DateTimeOffset]::Parse($_.ExpiresAt)
                    if ($ExpiresAt -lt $Now) {
                        return $true
                    }
                } catch {
                    # If we can't parse the date, consider it for deletion
                    Write-Warning "Failed to parse ExpiresAt for token $($_.PartitionKey): $($Error[0].Exception.Message)"
                    return $true
                }
            }
            
            return $false
        })
        
        $DeletedCount = 0
        $InvalidCount = 0
        $ExpiredCount = 0
        
        # Delete expired or invalid tokens
        foreach ($Token in $TokensToDelete) {
            try {
                # Track reason for deletion
                if ($Token.IsValid -eq $false) {
                    $InvalidCount++
                } else {
                    $ExpiredCount++
                }
                
                Remove-AzDataTableEntity -Context $Table.Context -Entity $Token | Out-Null
                $DeletedCount++
            } catch {
                Write-Warning "Failed to delete refresh token $($Token.PartitionKey): $($_.Exception.Message)"
            }
        }
        
        Write-Information "Refresh token cleanup completed - deleted $DeletedCount tokens ($ExpiredCount expired, $InvalidCount invalid)"
        return @{
            Status = "Success"
            Message = "Refresh token cleanup completed"
            DeletedCount = $DeletedCount
            ExpiredCount = $ExpiredCount
            InvalidCount = $InvalidCount
            TotalTokens = $AllTokens.Count
            RemainingTokens = $AllTokens.Count - $DeletedCount
        }
    } catch {
        Write-Warning "Refresh token cleanup failed: $($_.Exception.Message)"
        throw
    }
}
