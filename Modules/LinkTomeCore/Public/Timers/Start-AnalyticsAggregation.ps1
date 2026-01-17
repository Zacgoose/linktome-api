function Start-AnalyticsAggregation {
    <#
    .SYNOPSIS
        Aggregate and summarize analytics data
    .DESCRIPTION
        Timer function to aggregate daily analytics data for reporting.
        Creates pre-computed aggregates in AnalyticsAggregated table for faster API responses.
        Aggregates data by user and by day for efficient queries.
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
            return @{
                Status = "Success"
                Message = "No analytics events to aggregate"
                AggregatedCount = 0
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
                }
            }
            
            # Increment counters
            if ($EventType -eq 'PageView') {
                $AggregatedData[$AggKey].PageViewCount++
                if ($Event.IpAddress) {
                    $AggregatedData[$AggKey].UniqueVisitors[$Event.IpAddress] = $true
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
            
            try {
                Add-LinkToMeAzDataTableEntity @AggregatedTable -Entity $AggRecord -Force | Out-Null
                $SavedCount++
            } catch {
                Write-Warning "Failed to save aggregated record for ${Key}: $($_.Exception.Message)"
            }
        }
        
        Write-Information "Analytics aggregation completed - saved $SavedCount aggregated records"
        return @{
            Status = "Success"
            Message = "Analytics aggregation completed"
            ProcessedEvents = $RecentEvents.Count
            AggregatedRecords = $SavedCount
            AggregationWindowDays = $AggregationWindowDays
        }
    } catch {
        Write-Warning "Analytics aggregation failed: $($_.Exception.Message)"
        throw
    }
}
