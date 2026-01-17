function Start-AnalyticsAggregation {
    <#
    .SYNOPSIS
        Aggregate and summarize analytics data
    .DESCRIPTION
        Timer function to aggregate daily analytics data for reporting.
        Creates pre-computed aggregates in AnalyticsAggregated table for faster API responses.
        Aggregates data by user and by day for efficient queries.
        
        After successful aggregation, cleans up old raw events (older than 31 days).
        Also cleans up old aggregated data (older than 180 days extended retention).
    .FUNCTIONALITY
        Timer
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Information "Starting analytics aggregation process"
        
        # Get Analytics table (raw events)
        $AnalyticsTable = Get-LinkToMeTable -TableName 'Analytics'
        
        # Get or create AnalyticsAggregated table (pre-computed aggregates)
        $AggregatedTable = Get-LinkToMeTable -TableName 'AnalyticsAggregated'
        
        # Get all analytics events
        $AllEvents = Get-LinkToMeAzDataTableEntity @AnalyticsTable
        
        if (-not $AllEvents -or $AllEvents.Count -eq 0) {
            Write-Information "No analytics events found to aggregate"
            
            # Still run aggregated table cleanup even if no raw events
            $AggCleanupResult = Clear-OldAggregatedAnalytics -AggregatedTable $AggregatedTable
            
            return @{
                Status = "Success"
                Message = "No analytics events to aggregate"
                AggregatedCount = 0
                RawEventsDeleted = 0
                AggregatedRecordsDeleted = $AggCleanupResult.DeletedCount
            }
        }
        
        # Process events from the last 31 days (to cover 30-day window with buffer)
        $AggregationWindowDays = 31
        $StartDate = [DateTimeOffset]::UtcNow.AddDays(-$AggregationWindowDays).Date
        
        # Filter events within the aggregation window
        $RecentEvents = @($AllEvents | Where-Object { 
            $_.EventTimestamp -and ([DateTimeOffset]$_.EventTimestamp -ge $StartDate)
        })
        
        Write-Information "Processing $($RecentEvents.Count) events from last $AggregationWindowDays days"
        
        # Group events by UserId and Date
        $AggregatedData = @{}
        
        foreach ($Event in $RecentEvents) {
            $UserId = $Event.PartitionKey
            $EventDate = ([DateTimeOffset]$Event.EventTimestamp).ToString('yyyy-MM-dd')
            $EventType = $Event.EventType
            $PageId = $Event.PageId
            
            # Create composite key: UserId-Date or UserId-Date-PageId
            $AggKey = if ($PageId) { "$UserId-$EventDate-$PageId" } else { "$UserId-$EventDate" }
            
            if (-not $AggregatedData.ContainsKey($AggKey)) {
                $AggregatedData[$AggKey] = @{
                    UserId = $UserId
                    Date = $EventDate
                    PageId = $PageId
                    PageViewCount = 0
                    LinkClickCount = 0
                    UniqueVisitors = @{}
                    LinkClicks = @{}
                    Referrers = @{}
                    UserAgents = @{}
                }
            }
            
            # Increment counters
            if ($EventType -eq 'PageView') {
                $AggregatedData[$AggKey].PageViewCount++
                if ($Event.IpAddress) {
                    $AggregatedData[$AggKey].UniqueVisitors[$Event.IpAddress] = $true
                }
                # Track referrers
                if ($Event.Referrer) {
                    $Referrer = [string]$Event.Referrer
                    if (-not $AggregatedData[$AggKey].Referrers.ContainsKey($Referrer)) {
                        $AggregatedData[$AggKey].Referrers[$Referrer] = 0
                    }
                    $AggregatedData[$AggKey].Referrers[$Referrer]++
                }
                # Track user agents (browsers)
                if ($Event.UserAgent) {
                    $UserAgent = [string]$Event.UserAgent
                    if (-not $AggregatedData[$AggKey].UserAgents.ContainsKey($UserAgent)) {
                        $AggregatedData[$AggKey].UserAgents[$UserAgent] = 0
                    }
                    $AggregatedData[$AggKey].UserAgents[$UserAgent]++
                }
            } elseif ($EventType -eq 'LinkClick') {
                $AggregatedData[$AggKey].LinkClickCount++
                if ($Event.LinkId) {
                    $LinkId = $Event.LinkId
                    if (-not $AggregatedData[$AggKey].LinkClicks.ContainsKey($LinkId)) {
                        $AggregatedData[$AggKey].LinkClicks[$LinkId] = @{
                            Count = 0
                            Title = $Event.LinkTitle
                            Url = $Event.LinkUrl
                        }
                    }
                    $AggregatedData[$AggKey].LinkClicks[$LinkId].Count++
                }
            }
        }
        
        Write-Information "Created $($AggregatedData.Count) aggregated records"
        
        # Save aggregated data to table
        $SavedCount = 0
        foreach ($Key in $AggregatedData.Keys) {
            $Agg = $AggregatedData[$Key]
            
            # Create PartitionKey as UserId for efficient user-based queries
            # Create RowKey as Date or Date-PageId for efficient time-based queries
            $RowKey = if ($Agg.PageId) { "$($Agg.Date)-$($Agg.PageId)" } else { $Agg.Date }
            
            # Prepare aggregated record as a clean hashtable with only supported types
            # Azure Table Storage supports: String, Binary, Boolean, DateTime, Double, Guid, Int32, Int64
            $AggRecord = @{
                PartitionKey = [string]$Agg.UserId
                RowKey = [string]$RowKey
                Date = [string]$Agg.Date
                PageViewCount = [int]$Agg.PageViewCount
                LinkClickCount = [int]$Agg.LinkClickCount
                UniqueVisitorCount = [int]$Agg.UniqueVisitors.Count
                LastUpdated = [DateTimeOffset]::UtcNow
            }
            
            # Add PageId if present (as string)
            if ($Agg.PageId) {
                $AggRecord['PageId'] = [string]$Agg.PageId
            }
            
            # Add top clicked links as JSON string (up to 10)
            if ($Agg.LinkClicks.Count -gt 0) {
                $TopLinks = $Agg.LinkClicks.GetEnumerator() | 
                    Sort-Object { $_.Value.Count } -Descending | 
                    Select-Object -First 10
                
                # Build array of link objects
                $LinkArray = @($TopLinks | ForEach-Object {
                    @{
                        linkId = [string]$_.Key
                        count = [int]$_.Value.Count
                        title = if ($_.Value.Title) { [string]$_.Value.Title } else { '' }
                        url = if ($_.Value.Url) { [string]$_.Value.Url } else { '' }
                    }
                })
                
                # Convert to JSON string for storage
                $LinkClicksJson = $LinkArray | ConvertTo-Json -Compress -Depth 2
                
                # Store as string property
                $AggRecord['TopLinksJson'] = [string]$LinkClicksJson
            }
            
            # Add top referrers as JSON string (up to 10)
            if ($Agg.Referrers.Count -gt 0) {
                $TopReferrers = $Agg.Referrers.GetEnumerator() | 
                    Sort-Object Value -Descending | 
                    Select-Object -First 10
                
                $ReferrersArray = @($TopReferrers | ForEach-Object {
                    @{
                        referrer = [string]$_.Key
                        count = [int]$_.Value
                    }
                })
                
                $ReferrersJson = $ReferrersArray | ConvertTo-Json -Compress -Depth 2
                $AggRecord['TopReferrersJson'] = [string]$ReferrersJson
            }
            
            # Add top user agents (browsers) as JSON string (up to 5)
            if ($Agg.UserAgents.Count -gt 0) {
                $TopUserAgents = $Agg.UserAgents.GetEnumerator() | 
                    Sort-Object Value -Descending | 
                    Select-Object -First 5
                
                $UserAgentsArray = @($TopUserAgents | ForEach-Object {
                    @{
                        userAgent = [string]$_.Key
                        count = [int]$_.Value
                    }
                })
                
                $UserAgentsJson = $UserAgentsArray | ConvertTo-Json -Compress -Depth 2
                $AggRecord['TopUserAgentsJson'] = [string]$UserAgentsJson
            }
            
            try {
                Add-LinkToMeAzDataTableEntity @AggregatedTable -Entity $AggRecord -Force | Out-Null
                $SavedCount++
            } catch {
                Write-Warning "Failed to save aggregated record for ${Key}: $($_.Exception.Message)"
            }
        }
        
        Write-Information "Analytics aggregation completed - saved $SavedCount aggregated records"
        
        # After successful aggregation, clean up old raw events (older than aggregation window)
        Write-Information "Cleaning up old raw analytics events"
        $RawEventsDeleted = 0
        
        # Use same retention period as aggregation window (31 days)
        $RawDataRetentionDays = $AggregationWindowDays
        $RawDataCutoffDate = [DateTimeOffset]::UtcNow.AddDays(-$RawDataRetentionDays).Date
        
        # Find events older than the retention period
        $OldEvents = @($AllEvents | Where-Object { 
            $_.EventTimestamp -and ([DateTimeOffset]$_.EventTimestamp -lt $RawDataCutoffDate)
        })
        
        Write-Information "Found $($OldEvents.Count) old raw events to delete"
        
        foreach ($OldEvent in $OldEvents) {
            try {
                Remove-AzDataTableEntity -Context $AnalyticsTable.Context -Entity $OldEvent | Out-Null
                $RawEventsDeleted++
            } catch {
                Write-Warning "Failed to delete raw event $($OldEvent.RowKey): $($_.Exception.Message)"
            }
        }
        
        Write-Information "Deleted $RawEventsDeleted old raw analytics events"
        
        # Clean up old aggregated data (180 days extended retention)
        Write-Information "Cleaning up old aggregated analytics data"
        $AggCleanupResult = Clear-OldAggregatedAnalytics -AggregatedTable $AggregatedTable
        
        Write-Information "Analytics aggregation and cleanup completed"
        return @{
            Status = "Success"
            Message = "Analytics aggregation and cleanup completed"
            ProcessedEvents = $RecentEvents.Count
            AggregatedRecords = $SavedCount
            AggregationWindowDays = $AggregationWindowDays
            RawEventsDeleted = $RawEventsDeleted
            AggregatedRecordsDeleted = $AggCleanupResult.DeletedCount
            AggregatedRetentionDays = $AggCleanupResult.RetentionDays
        }
    } catch {
        Write-Warning "Analytics aggregation failed: $($_.Exception.Message)"
        throw
    }
}

function Clear-OldAggregatedAnalytics {
    <#
    .SYNOPSIS
        Clean up old aggregated analytics data
    .DESCRIPTION
        Helper function to remove aggregated analytics records older than extended retention period
    #>
    param(
        [Parameter(Mandatory)]
        $AggregatedTable
    )
    
    try {
        # Extended retention for aggregated data: 180 days (6 months)
        # This can be made configurable via environment variable if needed
        $RetentionDays = if ($env:ANALYTICS_AGGREGATED_RETENTION_DAYS) { 
            [int]$env:ANALYTICS_AGGREGATED_RETENTION_DAYS 
        } else { 
            180 
        }
        
        $CutoffDate = [DateTimeOffset]::UtcNow.AddDays(-$RetentionDays)
        
        # Get all aggregated records
        $AllAggregated = Get-LinkToMeAzDataTableEntity @AggregatedTable
        
        if (-not $AllAggregated -or $AllAggregated.Count -eq 0) {
            return @{
                DeletedCount = 0
                RetentionDays = $RetentionDays
            }
        }
        
        # Find records older than retention period (compare as DateTimeOffset)
        $OldRecords = @($AllAggregated | Where-Object { 
            $_.Date -and ([DateTimeOffset]::Parse($_.Date) -lt $CutoffDate)
        })
        
        $DeletedCount = 0
        foreach ($Record in $OldRecords) {
            try {
                Remove-AzDataTableEntity -Context $AggregatedTable.Context -Entity $Record | Out-Null
                $DeletedCount++
            } catch {
                Write-Warning "Failed to delete aggregated record $($Record.RowKey): $($_.Exception.Message)"
            }
        }
        
        Write-Information "Deleted $DeletedCount aggregated records older than $RetentionDays days"
        
        return @{
            DeletedCount = $DeletedCount
            RetentionDays = $RetentionDays
        }
    } catch {
        Write-Warning "Failed to clean up old aggregated analytics: $($_.Exception.Message)"
        return @{
            DeletedCount = 0
            RetentionDays = 180
        }
    }
}
