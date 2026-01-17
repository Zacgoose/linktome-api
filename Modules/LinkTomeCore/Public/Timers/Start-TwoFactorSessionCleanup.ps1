function Start-TwoFactorSessionCleanup {
    <#
    .SYNOPSIS
        Cleanup expired 2FA sessions
    .DESCRIPTION
        Timer function to remove expired two-factor authentication sessions.
        2FA sessions typically expire after 10 minutes, but we clean up sessions
        older than 1 hour to be safe.
    .FUNCTIONALITY
        Timer
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Information "Starting 2FA session cleanup"
        
        # Get TwoFactorSessions table
        $Table = Get-LinkToMeTable -TableName 'TwoFactorSessions'
        
        # Get all 2FA sessions
        $AllSessions = Get-LinkToMeAzDataTableEntity @Table
        
        if (-not $AllSessions -or $AllSessions.Count -eq 0) {
            Write-Information "No 2FA sessions found to clean up"
            return @{
                Status = "Success"
                Message = "No 2FA sessions to clean up"
                DeletedCount = 0
            }
        }
        
        # Current time for expiration checks
        $Now = [DateTimeOffset]::UtcNow
        
        # Find expired sessions (ExpiresAt < now)
        $ExpiredSessions = @($AllSessions | Where-Object { 
            $_.ExpiresAt -and ([DateTimeOffset]$_.ExpiresAt -lt $Now)
        })
        
        $DeletedCount = 0
        
        # Delete expired sessions
        foreach ($Session in $ExpiredSessions) {
            try {
                Remove-AzDataTableEntity -Context $Table.Context -Entity $Session | Out-Null
                $DeletedCount++
            } catch {
                Write-Warning "Failed to delete 2FA session $($Session.PartitionKey): $($_.Exception.Message)"
            }
        }
        
        Write-Information "2FA session cleanup completed - deleted $DeletedCount expired sessions"
        return @{
            Status = "Success"
            Message = "2FA session cleanup completed"
            DeletedCount = $DeletedCount
            TotalSessions = $AllSessions.Count
        }
    } catch {
        Write-Warning "2FA session cleanup failed: $($_.Exception.Message)"
        throw
    }
}
