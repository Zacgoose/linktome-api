function Get-AggregatedAnalytics {
    <#
    .SYNOPSIS
        Get pre-aggregated analytics data for a user
    .DESCRIPTION
        Retrieves pre-computed analytics aggregates from the AnalyticsAggregated table.
        Queries user-level, page-level, and link-level aggregates separately.
        This is much faster than computing aggregates on-the-fly from raw events.
        Falls back to raw event aggregation if aggregated data is not available.
    .PARAMETER UserId
        User ID to get analytics for
    .PARAMETER PageId
        Optional page ID to filter analytics by page
    .PARAMETER DaysBack
        Number of days to look back (default: 30)
    .EXAMPLE
        $Analytics = Get-AggregatedAnalytics -UserId $UserId -DaysBack 30
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [string]$PageId,
        
        [int]$DaysBack = 30
    )
    
    try {
        # Get aggregated analytics table
        $AggregatedTable = Get-LinkToMeTable -TableName 'AnalyticsAggregated'
        
        # Query user-level aggregates (PartitionKey: user-{userId})
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserPartitionKey = "user-$SafeUserId"
        $UserRecords = Get-LinkToMeAzDataTableEntity @AggregatedTable -Filter "PartitionKey eq '$UserPartitionKey'"
        
        # Query page-level aggregates (PartitionKey: page-{userId})
        $PagePartitionKey = "page-$SafeUserId"
        $PageRecords = Get-LinkToMeAzDataTableEntity @AggregatedTable -Filter "PartitionKey eq '$PagePartitionKey'"
        
        # Query link-level aggregates (PartitionKey: link-{userId})
        $LinkPartitionKey = "link-$SafeUserId"
        $LinkRecords = Get-LinkToMeAzDataTableEntity @AggregatedTable -Filter "PartitionKey eq '$LinkPartitionKey'"
        
        # If no aggregated data at all, return null to trigger fallback to raw events
        if ((-not $UserRecords -or $UserRecords.Count -eq 0) -and 
            (-not $PageRecords -or $PageRecords.Count -eq 0) -and
            (-not $LinkRecords -or $LinkRecords.Count -eq 0)) {
            Write-Information "No aggregated analytics found for user $UserId, will use raw events"
            return $null
        }
        
        # Filter by date range
        $StartDate = [DateTimeOffset]::UtcNow.AddDays(-$DaysBack).ToString('yyyy-MM-dd')
        
        if ($UserRecords) {
            $UserRecords = @($UserRecords | Where-Object { $_.Date -ge $StartDate })
        }
        if ($PageRecords) {
            $PageRecords = @($PageRecords | Where-Object { $_.Date -ge $StartDate })
        }
        if ($LinkRecords) {
            $LinkRecords = @($LinkRecords | Where-Object { $_.Date -ge $StartDate })
        }
        
        # Filter by page if specified
        if ($PageId) {
            $PageRecords = @($PageRecords | Where-Object { $_.PageId -eq $PageId })
        }
        
        # Calculate summary totals from user-level aggregates
        $TotalPageViews = 0
        $TotalLinkClicks = 0
        $TotalUniqueVisitors = 0
        $AllTopReferrers = @{}
        $AllTopUserAgents = @{}
        
        if ($UserRecords -and $UserRecords.Count -gt 0) {
            $TotalPageViews = ($UserRecords | Measure-Object -Property PageViewCount -Sum).Sum
            $TotalLinkClicks = ($UserRecords | Measure-Object -Property LinkClickCount -Sum).Sum
            $TotalUniqueVisitors = ($UserRecords | Measure-Object -Property UniqueVisitorCount -Sum).Sum
            
            # Aggregate referrers and user agents from user-level records
            foreach ($Record in $UserRecords) {
                if ($Record.TopReferrersJson) {
                    try {
                        $TopReferrers = $Record.TopReferrersJson | ConvertFrom-Json
                        foreach ($Ref in $TopReferrers) {
                            if (-not $AllTopReferrers.ContainsKey($Ref.referrer)) {
                                $AllTopReferrers[$Ref.referrer] = 0
                            }
                            $AllTopReferrers[$Ref.referrer] += $Ref.count
                        }
                    } catch {
                        Write-Warning "Failed to parse TopReferrersJson: $($_.Exception.Message)"
                    }
                }
                
                if ($Record.TopUserAgentsJson) {
                    try {
                        $TopUserAgents = $Record.TopUserAgentsJson | ConvertFrom-Json
                        foreach ($UA in $TopUserAgents) {
                            if (-not $AllTopUserAgents.ContainsKey($UA.userAgent)) {
                                $AllTopUserAgents[$UA.userAgent] = 0
                            }
                            $AllTopUserAgents[$UA.userAgent] += $UA.count
                        }
                    } catch {
                        Write-Warning "Failed to parse TopUserAgentsJson: $($_.Exception.Message)"
                    }
                }
            }
        }
        
        # Get views and clicks by day from user-level
        $ViewsByDay = @()
        $ClicksByDay = @()
        
        if ($UserRecords -and $UserRecords.Count -gt 0) {
            $ViewsByDay = @($UserRecords | 
                Group-Object Date | 
                ForEach-Object {
                    @{
                        date = $_.Name
                        count = ($_.Group | Measure-Object -Property PageViewCount -Sum).Sum
                    }
                } | Sort-Object date)
            
            $ClicksByDay = @($UserRecords | 
                Group-Object Date | 
                ForEach-Object {
                    @{
                        date = $_.Name
                        count = ($_.Group | Measure-Object -Property LinkClickCount -Sum).Sum
                    }
                } | Sort-Object date)
        }
        
        # Get link clicks from link-level aggregates
        $LinkClicksByLink = @()
        if ($LinkRecords -and $LinkRecords.Count -gt 0) {
            # Group by LinkId and sum clicks
            $LinkClicksByLink = @($LinkRecords | 
                Group-Object LinkId | 
                ForEach-Object {
                    $linkId = $_.Name
                    $linkGroup = $_.Group
                    $totalClicks = ($linkGroup | Measure-Object -Property ClickCount -Sum).Sum
                    # Get title and URL from first record
                    $firstRecord = $linkGroup[0]
                    
                    @{
                        linkId = $linkId
                        linkTitle = if ($firstRecord.LinkTitle) { $firstRecord.LinkTitle } else { '' }
                        linkUrl = if ($firstRecord.LinkUrl) { $firstRecord.LinkUrl } else { '' }
                        clickCount = $totalClicks
                    }
                } | Sort-Object clickCount -Descending | Select-Object -First 10)
        }
        
        # Get top referrers and user agents
        $TopReferrersList = @($AllTopReferrers.GetEnumerator() | 
            Sort-Object Value -Descending | 
            Select-Object -First 10 | 
            ForEach-Object {
                @{
                    referrer = $_.Key
                    count = $_.Value
                }
            })
        
        $TopUserAgentsList = @($AllTopUserAgents.GetEnumerator() | 
            Sort-Object Value -Descending | 
            Select-Object -First 5 | 
            ForEach-Object {
                @{
                    userAgent = $_.Key
                    count = $_.Value
                }
            })
        
        # Get per-page breakdown from page-level aggregates (if no specific page filter)
        $PageBreakdown = @()
        if (-not $PageId -and $PageRecords -and $PageRecords.Count -gt 0) {
            $PageBreakdown = @($PageRecords | 
                Group-Object PageId | 
                ForEach-Object {
                    $pageId = $_.Name
                    $pageGroup = $_.Group
                    
                    @{
                        pageId = $pageId
                        totalPageViews = ($pageGroup | Measure-Object -Property PageViewCount -Sum).Sum
                        totalLinkClicks = ($pageGroup | Measure-Object -Property LinkClickCount -Sum).Sum
                    }
                } | Sort-Object totalPageViews -Descending)
        }
        
        # Return aggregated results
        return @{
            summary = @{
                totalPageViews = $TotalPageViews
                totalLinkClicks = $TotalLinkClicks
                uniqueVisitors = $TotalUniqueVisitors
            }
            viewsByDay = $ViewsByDay
            clicksByDay = $ClicksByDay
            linkClicksByLink = $LinkClicksByLink
            topReferrers = $TopReferrersList
            topUserAgents = $TopUserAgentsList
            pageBreakdown = $PageBreakdown
            source = 'aggregated'
        }
        
    } catch {
        Write-Warning "Failed to get aggregated analytics: $($_.Exception.Message)"
        return $null
    }
}
