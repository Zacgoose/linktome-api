function Start-SecurityEventCleanup {
    <#
    .SYNOPSIS
        Cleanup old security events and audit logs
    .DESCRIPTION
        Timer function to remove old security events based on retention policy.
        Keeps security events for 90 days, then deletes them to manage storage costs.
    .FUNCTIONALITY
        Timer
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Information "Starting security event cleanup"
        
        # Get SecurityEvents table
        $Table = Get-LinkToMeTable -TableName 'SecurityEvents'
        
        # Get all security events
        $AllEvents = Get-LinkToMeAzDataTableEntity @Table
        
        if (-not $AllEvents -or $AllEvents.Count -eq 0) {
            Write-Information "No security events found to clean up"
            return @{
                Status = "Success"
                Message = "No security events to clean up"
                DeletedCount = 0
            }
        }
        
        # Calculate cutoff time (90 days ago for retention policy)
        $RetentionDays = 90
        $CutoffTime = [DateTimeOffset]::UtcNow.AddDays(-$RetentionDays)
        
        # Find old events to delete
        $EventsToDelete = @($AllEvents | Where-Object { 
            $_.EventTimestamp -and ([DateTimeOffset]$_.EventTimestamp -lt $CutoffTime)
        })
        
        $DeletedCount = 0
        
        # Delete old events
        foreach ($Event in $EventsToDelete) {
            try {
                Remove-AzDataTableEntity -Context $Table.Context -Entity $Event | Out-Null
                $DeletedCount++
            } catch {
                Write-Warning "Failed to delete security event $($Event.RowKey): $($_.Exception.Message)"
            }
        }
        
        Write-Information "Security event cleanup completed - deleted $DeletedCount events older than $RetentionDays days"
        return @{
            Status = "Success"
            Message = "Security event cleanup completed"
            DeletedCount = $DeletedCount
            TotalEvents = $AllEvents.Count
            RetentionDays = $RetentionDays
        }
    } catch {
        Write-Warning "Security event cleanup failed: $($_.Exception.Message)"
        throw
    }
}
