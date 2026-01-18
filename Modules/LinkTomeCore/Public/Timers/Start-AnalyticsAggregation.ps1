function Start-AnalyticsAggregation {
    <#
    .SYNOPSIS
        Aggregate and summarize analytics data
    .DESCRIPTION
        Timer function to aggregate daily analytics data for reporting.
        Creates pre-computed aggregates in AnalyticsAggregated table at three levels:
        - User-level: Overall stats per user per day
        - Page-level: Stats per page per user per day
        - Link-level: Stats per link per user per day
        
        Uses incremental aggregation - merges with existing data and deletes processed raw events.
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
        
        # Get all analytics events (unprocessed raw data)
        $AllEvents = Get-LinkToMeAzDataTableEntity @AnalyticsTable
        
        if (-not $AllEvents -or $AllEvents.Count -eq 0) {
            Write-Information "No analytics events found to aggregate"
            
            # Still run aggregated table cleanup even if no raw events
            $AggCleanupResult = Clear-OldAggregatedAnalytics -AggregatedTable $AggregatedTable
            
            return @{
                Status = "Success"
                Message = "No analytics events to aggregate"
                ProcessedEvents = 0
                UserLevelRecords = 0
                PageLevelRecords = 0
                LinkLevelRecords = 0
                RawEventsDeleted = 0
                AggregatedRecordsDeleted = $AggCleanupResult.DeletedCount
            }
        }
        
        Write-Information "Processing $($AllEvents.Count) raw analytics events"
        
        # Group events at three levels with new partition/row key structure:
        # PartitionKey format: {type}-{guid} (e.g., user-abc123, page-abc123, link-abc123)
        # RowKey format: yyyy-MM-dd (e.g., 2026-01-18)
        # 
        # 1. User-level: PK=user-{userId}, RK={date}
        # 2. Page-level: PK=page-{pageId}, RK={date}
        # 3. Link-level: PK=link-{linkId}, RK={date}
        
        $UserLevelData = @{}
        $PageLevelData = @{}
        $LinkLevelData = @{}
        $EventsToDelete = @()
        
        foreach ($Event in $AllEvents) {
            $UserId = $Event.PartitionKey
            $EventDate = ([DateTimeOffset]$Event.EventTimestamp).ToString('yyyy-MM-dd')
            $EventType = $Event.EventType
            $PageId = $Event.PageId
            $LinkId = $Event.LinkId
            
            # ===== USER-LEVEL AGGREGATION =====
            $UserKey = "user-$UserId|$EventDate"
            if (-not $UserLevelData.ContainsKey($UserKey)) {
                $UserLevelData[$UserKey] = @{
                    Type = 'User'
                    UserId = $UserId
                    Date = $EventDate
                    PageViewCount = 0
                    LinkClickCount = 0
                    UniqueVisitors = @{}
                    Referrers = @{}
                    UserAgents = @{}
                }
            }
            
            if ($EventType -eq 'PageView') {
                $UserLevelData[$UserKey].PageViewCount++
                if ($Event.IpAddress) {
                    $UserLevelData[$UserKey].UniqueVisitors[$Event.IpAddress] = $true
                }
                if ($Event.Referrer) {
                    $Ref = [string]$Event.Referrer
                    if (-not $UserLevelData[$UserKey].Referrers.ContainsKey($Ref)) {
                        $UserLevelData[$UserKey].Referrers[$Ref] = 0
                    }
                    $UserLevelData[$UserKey].Referrers[$Ref]++
                }
                if ($Event.UserAgent) {
                    $UA = [string]$Event.UserAgent
                    if (-not $UserLevelData[$UserKey].UserAgents.ContainsKey($UA)) {
                        $UserLevelData[$UserKey].UserAgents[$UA] = 0
                    }
                    $UserLevelData[$UserKey].UserAgents[$UA]++
                }
            } elseif ($EventType -eq 'LinkClick') {
                $UserLevelData[$UserKey].LinkClickCount++
            }
            
            # ===== PAGE-LEVEL AGGREGATION =====
            if ($PageId) {
                $PageKey = "page-$PageId|$EventDate"
                if (-not $PageLevelData.ContainsKey($PageKey)) {
                    $PageLevelData[$PageKey] = @{
                        Type = 'Page'
                        UserId = $UserId
                        Date = $EventDate
                        PageId = $PageId
                        PageViewCount = 0
                        LinkClickCount = 0
                        UniqueVisitors = @{}
                        Referrers = @{}
                        UserAgents = @{}
                    }
                }
                
                if ($EventType -eq 'PageView') {
                    $PageLevelData[$PageKey].PageViewCount++
                    if ($Event.IpAddress) {
                        $PageLevelData[$PageKey].UniqueVisitors[$Event.IpAddress] = $true
                    }
                    if ($Event.Referrer) {
                        $Ref = [string]$Event.Referrer
                        if (-not $PageLevelData[$PageKey].Referrers.ContainsKey($Ref)) {
                            $PageLevelData[$PageKey].Referrers[$Ref] = 0
                        }
                        $PageLevelData[$PageKey].Referrers[$Ref]++
                    }
                    if ($Event.UserAgent) {
                        $UA = [string]$Event.UserAgent
                        if (-not $PageLevelData[$PageKey].UserAgents.ContainsKey($UA)) {
                            $PageLevelData[$PageKey].UserAgents[$UA] = 0
                        }
                        $PageLevelData[$PageKey].UserAgents[$UA]++
                    }
                } elseif ($EventType -eq 'LinkClick') {
                    $PageLevelData[$PageKey].LinkClickCount++
                }
            }
            
            # ===== LINK-LEVEL AGGREGATION =====
            if ($LinkId -and $EventType -eq 'LinkClick') {
                $LinkKey = "link-$LinkId|$EventDate"
                if (-not $LinkLevelData.ContainsKey($LinkKey)) {
                    $LinkLevelData[$LinkKey] = @{
                        Type = 'Link'
                        UserId = $UserId
                        Date = $EventDate
                        LinkId = $LinkId
                        LinkTitle = $Event.LinkTitle
                        LinkUrl = $Event.LinkUrl
                        ClickCount = 0
                        Referrers = @{}
                        UniqueVisitors = @{}
                    }
                }
                
                $LinkLevelData[$LinkKey].ClickCount++
                if ($Event.IpAddress) {
                    $LinkLevelData[$LinkKey].UniqueVisitors[$Event.IpAddress] = $true
                }
                if ($Event.Referrer) {
                    $Ref = [string]$Event.Referrer
                    if (-not $LinkLevelData[$LinkKey].Referrers.ContainsKey($Ref)) {
                        $LinkLevelData[$LinkKey].Referrers[$Ref] = 0
                    }
                    $LinkLevelData[$LinkKey].Referrers[$Ref]++
                }
            }
            
            # Track this event for deletion after successful aggregation
            $EventsToDelete += $Event
        }
        
        Write-Information "Created user-level: $($UserLevelData.Count), page-level: $($PageLevelData.Count), link-level: $($LinkLevelData.Count) records"
        
        # ===== SAVE/MERGE USER-LEVEL AGGREGATES =====
        $UserSavedCount = 0
        foreach ($Key in $UserLevelData.Keys) {
            $Agg = $UserLevelData[$Key]
            $PartitionKey = "user-$($Agg.UserId)"
            $RowKey = $Agg.Date
            
            # Try to get existing aggregate to merge
            $ExistingAgg = Get-LinkToMeAzDataTableEntity @AggregatedTable -Filter "PartitionKey eq '$PartitionKey' and RowKey eq '$RowKey'" -ErrorAction SilentlyContinue | Select-Object -First 1
            
            # Merge with existing or create new
            $PageViewCount = [int]$Agg.PageViewCount
            $LinkClickCount = [int]$Agg.LinkClickCount
            $UniqueVisitors = $Agg.UniqueVisitors
            $Referrers = $Agg.Referrers
            $UserAgents = $Agg.UserAgents
            
            if ($ExistingAgg) {
                # Merge counts
                $PageViewCount += [int]$ExistingAgg.PageViewCount
                $LinkClickCount += [int]$ExistingAgg.LinkClickCount
                
                # Merge unique visitors (IPs)
                if ($ExistingAgg.UniqueVisitorsJson) {
                    $ExistingVisitors = $ExistingAgg.UniqueVisitorsJson | ConvertFrom-Json
                    foreach ($Visitor in $ExistingVisitors) {
                        $UniqueVisitors[$Visitor] = $true
                    }
                }
                
                # Merge referrers
                if ($ExistingAgg.TopReferrersJson) {
                    $ExistingReferrers = $ExistingAgg.TopReferrersJson | ConvertFrom-Json
                    foreach ($Ref in $ExistingReferrers) {
                        if (-not $Referrers.ContainsKey($Ref.referrer)) {
                            $Referrers[$Ref.referrer] = 0
                        }
                        $Referrers[$Ref.referrer] += $Ref.count
                    }
                }
                
                # Merge user agents
                if ($ExistingAgg.TopUserAgentsJson) {
                    $ExistingUAs = $ExistingAgg.TopUserAgentsJson | ConvertFrom-Json
                    foreach ($UA in $ExistingUAs) {
                        if (-not $UserAgents.ContainsKey($UA.userAgent)) {
                            $UserAgents[$UA.userAgent] = 0
                        }
                        $UserAgents[$UA.userAgent] += $UA.count
                    }
                }
            }
            
            # Build aggregate record
            $AggRecord = @{
                PartitionKey = [string]$PartitionKey
                RowKey = [string]$RowKey
                RecordType = [string]'User'
                UserId = [string]$Agg.UserId
                Date = [string]$Agg.Date
                PageViewCount = [int]$PageViewCount
                LinkClickCount = [int]$LinkClickCount
                UniqueVisitorCount = [int]$UniqueVisitors.Count
                LastUpdated = [DateTimeOffset]::UtcNow
            }
            
            # Store unique visitors as JSON array
            if ($UniqueVisitors.Count -gt 0) {
                $VisitorsArray = @($UniqueVisitors.Keys)
                $AggRecord['UniqueVisitorsJson'] = [string]($VisitorsArray | ConvertTo-Json -Compress)
            }
            
            # Store top 10 referrers as JSON
            if ($Referrers.Count -gt 0) {
                $TopRefs = $Referrers.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
                $RefsArray = @($TopRefs | ForEach-Object {
                    @{ referrer = [string]$_.Key; count = [int]$_.Value }
                })
                $AggRecord['TopReferrersJson'] = [string]($RefsArray | ConvertTo-Json -Compress -Depth 2)
            }
            
            # Store top 5 user agents as JSON
            if ($UserAgents.Count -gt 0) {
                $TopUAs = $UserAgents.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5
                $UAsArray = @($TopUAs | ForEach-Object {
                    @{ userAgent = [string]$_.Key; count = [int]$_.Value }
                })
                $AggRecord['TopUserAgentsJson'] = [string]($UAsArray | ConvertTo-Json -Compress -Depth 2)
            }
            
            try {
                Add-LinkToMeAzDataTableEntity @AggregatedTable -Entity $AggRecord -Force | Out-Null
                $UserSavedCount++
            } catch {
                Write-Warning "Failed to save user-level aggregate for ${Key}: $($_.Exception.Message)"
            }
        }
        
        # ===== SAVE/MERGE PAGE-LEVEL AGGREGATES =====
        $PageSavedCount = 0
        foreach ($Key in $PageLevelData.Keys) {
            $Agg = $PageLevelData[$Key]
            $PartitionKey = "page-$($Agg.PageId)"
            $RowKey = $Agg.Date
            
            # Try to get existing aggregate to merge
            $ExistingAgg = Get-LinkToMeAzDataTableEntity @AggregatedTable -Filter "PartitionKey eq '$PartitionKey' and RowKey eq '$RowKey'" -ErrorAction SilentlyContinue | Select-Object -First 1
            
            # Merge with existing or create new
            $PageViewCount = [int]$Agg.PageViewCount
            $LinkClickCount = [int]$Agg.LinkClickCount
            $UniqueVisitors = $Agg.UniqueVisitors
            $Referrers = $Agg.Referrers
            $UserAgents = $Agg.UserAgents
            
            if ($ExistingAgg) {
                # Merge counts
                $PageViewCount += [int]$ExistingAgg.PageViewCount
                $LinkClickCount += [int]$ExistingAgg.LinkClickCount
                
                # Merge unique visitors
                if ($ExistingAgg.UniqueVisitorsJson) {
                    $ExistingVisitors = $ExistingAgg.UniqueVisitorsJson | ConvertFrom-Json
                    foreach ($Visitor in $ExistingVisitors) {
                        $UniqueVisitors[$Visitor] = $true
                    }
                }
                
                # Merge referrers
                if ($ExistingAgg.TopReferrersJson) {
                    $ExistingReferrers = $ExistingAgg.TopReferrersJson | ConvertFrom-Json
                    foreach ($Ref in $ExistingReferrers) {
                        if (-not $Referrers.ContainsKey($Ref.referrer)) {
                            $Referrers[$Ref.referrer] = 0
                        }
                        $Referrers[$Ref.referrer] += $Ref.count
                    }
                }
                
                # Merge user agents
                if ($ExistingAgg.TopUserAgentsJson) {
                    $ExistingUAs = $ExistingAgg.TopUserAgentsJson | ConvertFrom-Json
                    foreach ($UA in $ExistingUAs) {
                        if (-not $UserAgents.ContainsKey($UA.userAgent)) {
                            $UserAgents[$UA.userAgent] = 0
                        }
                        $UserAgents[$UA.userAgent] += $UA.count
                    }
                }
            }
            
            # Build aggregate record
            $AggRecord = @{
                PartitionKey = [string]$PartitionKey
                RowKey = [string]$RowKey
                RecordType = [string]'Page'
                UserId = [string]$Agg.UserId
                Date = [string]$Agg.Date
                PageId = [string]$Agg.PageId
                PageViewCount = [int]$PageViewCount
                LinkClickCount = [int]$LinkClickCount
                UniqueVisitorCount = [int]$UniqueVisitors.Count
                LastUpdated = [DateTimeOffset]::UtcNow
            }
            
            # Store unique visitors as JSON array
            if ($UniqueVisitors.Count -gt 0) {
                $VisitorsArray = @($UniqueVisitors.Keys)
                $AggRecord['UniqueVisitorsJson'] = [string]($VisitorsArray | ConvertTo-Json -Compress)
            }
            
            # Store top 10 referrers as JSON
            if ($Referrers.Count -gt 0) {
                $TopRefs = $Referrers.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
                $RefsArray = @($TopRefs | ForEach-Object {
                    @{ referrer = [string]$_.Key; count = [int]$_.Value }
                })
                $AggRecord['TopReferrersJson'] = [string]($RefsArray | ConvertTo-Json -Compress -Depth 2)
            }
            
            # Store top 5 user agents as JSON
            if ($UserAgents.Count -gt 0) {
                $TopUAs = $UserAgents.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5
                $UAsArray = @($TopUAs | ForEach-Object {
                    @{ userAgent = [string]$_.Key; count = [int]$_.Value }
                })
                $AggRecord['TopUserAgentsJson'] = [string]($UAsArray | ConvertTo-Json -Compress -Depth 2)
            }
            
            try {
                Add-LinkToMeAzDataTableEntity @AggregatedTable -Entity $AggRecord -Force | Out-Null
                $PageSavedCount++
            } catch {
                Write-Warning "Failed to save page-level aggregate for ${Key}: $($_.Exception.Message)"
            }
        }
        
        # ===== SAVE/MERGE LINK-LEVEL AGGREGATES =====
        $LinkSavedCount = 0
        foreach ($Key in $LinkLevelData.Keys) {
            $Agg = $LinkLevelData[$Key]
            $PartitionKey = "link-$($Agg.LinkId)"
            $RowKey = $Agg.Date
            
            # Try to get existing aggregate to merge
            $ExistingAgg = Get-LinkToMeAzDataTableEntity @AggregatedTable -Filter "PartitionKey eq '$PartitionKey' and RowKey eq '$RowKey'" -ErrorAction SilentlyContinue | Select-Object -First 1
            
            # Merge with existing or create new
            $ClickCount = [int]$Agg.ClickCount
            $UniqueVisitors = $Agg.UniqueVisitors
            $Referrers = $Agg.Referrers
            
            if ($ExistingAgg) {
                # Merge counts
                $ClickCount += [int]$ExistingAgg.ClickCount
                
                # Merge unique visitors
                if ($ExistingAgg.UniqueVisitorsJson) {
                    $ExistingVisitors = $ExistingAgg.UniqueVisitorsJson | ConvertFrom-Json
                    foreach ($Visitor in $ExistingVisitors) {
                        $UniqueVisitors[$Visitor] = $true
                    }
                }
                
                # Merge referrers
                if ($ExistingAgg.TopReferrersJson) {
                    $ExistingReferrers = $ExistingAgg.TopReferrersJson | ConvertFrom-Json
                    foreach ($Ref in $ExistingReferrers) {
                        if (-not $Referrers.ContainsKey($Ref.referrer)) {
                            $Referrers[$Ref.referrer] = 0
                        }
                        $Referrers[$Ref.referrer] += $Ref.count
                    }
                }
            }
            
            # Build aggregate record
            $AggRecord = @{
                PartitionKey = [string]$PartitionKey
                RowKey = [string]$RowKey
                RecordType = [string]'Link'
                UserId = [string]$Agg.UserId
                Date = [string]$Agg.Date
                LinkId = [string]$Agg.LinkId
                LinkTitle = if ($Agg.LinkTitle) { [string]$Agg.LinkTitle } else { [string]'' }
                LinkUrl = if ($Agg.LinkUrl) { [string]$Agg.LinkUrl } else { [string]'' }
                ClickCount = [int]$ClickCount
                UniqueVisitorCount = [int]$UniqueVisitors.Count
                LastUpdated = [DateTimeOffset]::UtcNow
            }
            
            # Store unique visitors as JSON array
            if ($UniqueVisitors.Count -gt 0) {
                $VisitorsArray = @($UniqueVisitors.Keys)
                $AggRecord['UniqueVisitorsJson'] = [string]($VisitorsArray | ConvertTo-Json -Compress)
            }
            
            # Store top 10 referrers as JSON
            if ($Referrers.Count -gt 0) {
                $TopRefs = $Referrers.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
                $RefsArray = @($TopRefs | ForEach-Object {
                    @{ referrer = [string]$_.Key; count = [int]$_.Value }
                })
                $AggRecord['TopReferrersJson'] = [string]($RefsArray | ConvertTo-Json -Compress -Depth 2)
            }
            
            try {
                Add-LinkToMeAzDataTableEntity @AggregatedTable -Entity $AggRecord -Force | Out-Null
                $LinkSavedCount++
            } catch {
                Write-Warning "Failed to save link-level aggregate for ${Key}: $($_.Exception.Message)"
            }
        }
        
        Write-Information "Saved aggregates - User: $UserSavedCount, Page: $PageSavedCount, Link: $LinkSavedCount"
        
        # ===== DELETE RAW EVENTS AFTER SUCCESSFUL AGGREGATION =====
        Write-Information "Deleting $($EventsToDelete.Count) processed raw analytics events"
        $RawEventsDeleted = 0
        
        foreach ($Event in $EventsToDelete) {
            try {
                Remove-AzDataTableEntity -Context $AnalyticsTable.Context -Entity $Event | Out-Null
                $RawEventsDeleted++
            } catch {
                Write-Warning "Failed to delete raw event $($Event.RowKey): $($_.Exception.Message)"
            }
        }
        
        Write-Information "Deleted $RawEventsDeleted raw analytics events"
        
        # Clean up old aggregated data (180 days extended retention)
        Write-Information "Cleaning up old aggregated analytics data"
        $AggCleanupResult = Clear-OldAggregatedAnalytics -AggregatedTable $AggregatedTable
        
        Write-Information "Analytics aggregation and cleanup completed"
        return @{
            Status = "Success"
            Message = "Analytics aggregation and cleanup completed"
            ProcessedEvents = $AllEvents.Count
            UserLevelRecords = $UserSavedCount
            PageLevelRecords = $PageSavedCount
            LinkLevelRecords = $LinkSavedCount
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
