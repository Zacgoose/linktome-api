function Get-AggregatedAnalytics {
    <#
    .SYNOPSIS
        Get pre-aggregated analytics data for a user
    .DESCRIPTION
        Retrieves pre-computed analytics aggregates from the AnalyticsAggregated table.
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
        
        # Get aggregated records for this user
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $AggregatedRecords = Get-LinkToMeAzDataTableEntity @AggregatedTable -Filter "PartitionKey eq '$SafeUserId'"
        
        # If no aggregated data, return null to trigger fallback to raw events
        if (-not $AggregatedRecords -or $AggregatedRecords.Count -eq 0) {
            Write-Information "No aggregated analytics found for user $UserId, will use raw events"
            return $null
        }
        
        # Filter by page if specified
        if ($PageId) {
            $SafePageId = Protect-TableQueryValue -Value $PageId
            $AggregatedRecords = @($AggregatedRecords | Where-Object { 
                $_.PageId -eq $SafePageId -or $_.RowKey -like "*-$SafePageId"
            })
        }
        
        # Filter by date range
        $StartDate = [DateTimeOffset]::UtcNow.AddDays(-$DaysBack).ToString('yyyy-MM-dd')
        $AggregatedRecords = @($AggregatedRecords | Where-Object { 
            $_.Date -ge $StartDate
        })
        
        if ($AggregatedRecords.Count -eq 0) {
            Write-Information "No aggregated analytics in date range for user $UserId"
            return $null
        }
        
        # Calculate summary totals
        $TotalPageViews = ($AggregatedRecords | Measure-Object -Property PageViewCount -Sum).Sum
        $TotalLinkClicks = ($AggregatedRecords | Measure-Object -Property LinkClickCount -Sum).Sum
        $TotalUniqueVisitors = ($AggregatedRecords | Measure-Object -Property UniqueVisitorCount -Sum).Sum
        
        # Get views and clicks by day
        $ViewsByDay = @($AggregatedRecords | 
            Group-Object Date | 
            ForEach-Object {
                @{
                    date = $_.Name
                    count = ($_.Group | Measure-Object -Property PageViewCount -Sum).Sum
                }
            } | Sort-Object date)
        
        $ClicksByDay = @($AggregatedRecords | 
            Group-Object Date | 
            ForEach-Object {
                @{
                    date = $_.Name
                    count = ($_.Group | Measure-Object -Property LinkClickCount -Sum).Sum
                }
            } | Sort-Object date)
        
        # Aggregate top clicked links across all days
        $AllTopLinks = @{}
        $AllTopReferrers = @{}
        $AllTopUserAgents = @{}
        
        foreach ($Record in $AggregatedRecords) {
            # Aggregate top links
            if ($Record.TopLinksJson) {
                try {
                    $TopLinks = $Record.TopLinksJson | ConvertFrom-Json
                    foreach ($Link in $TopLinks) {
                        $LinkId = $Link.linkId
                        if (-not $AllTopLinks.ContainsKey($LinkId)) {
                            $AllTopLinks[$LinkId] = @{
                                linkId = $LinkId
                                linkTitle = $Link.title
                                linkUrl = $Link.url
                                clickCount = 0
                            }
                        }
                        $AllTopLinks[$LinkId].clickCount += $Link.count
                    }
                } catch {
                    Write-Warning "Failed to parse TopLinksJson for record $($Record.RowKey): $($_.Exception.Message)"
                }
            }
            
            # Aggregate top referrers
            if ($Record.TopReferrersJson) {
                try {
                    $TopReferrers = $Record.TopReferrersJson | ConvertFrom-Json
                    foreach ($Ref in $TopReferrers) {
                        $Referrer = $Ref.referrer
                        if (-not $AllTopReferrers.ContainsKey($Referrer)) {
                            $AllTopReferrers[$Referrer] = 0
                        }
                        $AllTopReferrers[$Referrer] += $Ref.count
                    }
                } catch {
                    Write-Warning "Failed to parse TopReferrersJson for record $($Record.RowKey): $($_.Exception.Message)"
                }
            }
            
            # Aggregate top user agents
            if ($Record.TopUserAgentsJson) {
                try {
                    $TopUserAgents = $Record.TopUserAgentsJson | ConvertFrom-Json
                    foreach ($UA in $TopUserAgents) {
                        $UserAgent = $UA.userAgent
                        if (-not $AllTopUserAgents.ContainsKey($UserAgent)) {
                            $AllTopUserAgents[$UserAgent] = 0
                        }
                        $AllTopUserAgents[$UserAgent] += $UA.count
                    }
                } catch {
                    Write-Warning "Failed to parse TopUserAgentsJson for record $($Record.RowKey): $($_.Exception.Message)"
                }
            }
        }
        
        # Sort and get top 10 links overall
        $LinkClicksByLink = @($AllTopLinks.Values | Sort-Object clickCount -Descending | Select-Object -First 10)
        
        # Sort and get top 10 referrers
        $TopReferrersList = @($AllTopReferrers.GetEnumerator() | 
            Sort-Object Value -Descending | 
            Select-Object -First 10 | 
            ForEach-Object {
                @{
                    referrer = $_.Key
                    count = $_.Value
                }
            })
        
        # Sort and get top 5 user agents (browsers)
        $TopUserAgentsList = @($AllTopUserAgents.GetEnumerator() | 
            Sort-Object Value -Descending | 
            Select-Object -First 5 | 
            ForEach-Object {
                @{
                    userAgent = $_.Key
                    count = $_.Value
                }
            })
        
        # Get per-page breakdown if no specific page filter
        $PageBreakdown = @()
        if (-not $PageId) {
            $PageBreakdown = @($AggregatedRecords | 
                Where-Object { $_.PageId } |
                Group-Object PageId | 
                ForEach-Object {
                    $pageId = $_.Name
                    $pageRecords = $_.Group
                    
                    @{
                        pageId = $pageId
                        totalPageViews = ($pageRecords | Measure-Object -Property PageViewCount -Sum).Sum
                        totalLinkClicks = ($pageRecords | Measure-Object -Property LinkClickCount -Sum).Sum
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
