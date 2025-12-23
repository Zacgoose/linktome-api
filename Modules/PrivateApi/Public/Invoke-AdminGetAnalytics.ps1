function Invoke-AdminGetAnalytics {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:analytics
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    # Use context-aware UserId if present, fallback to authenticated user
    $UserId = $Request.UserId
    if (-not $UserId) {
        $UserId = $Request.AuthenticatedUser.UserId
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Analytics'

        # Get analytics events for this user context
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $Events = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'"
        
        # Group events by type and calculate stats
        $PageViews = @($Events | Where-Object { $_.EventType -eq 'PageView' })
        $LinkClicks = @($Events | Where-Object { $_.EventType -eq 'LinkClick' })
        
        # Calculate summary statistics
        $Summary = @{
            totalPageViews = $PageViews.Count
            totalLinkClicks = $LinkClicks.Count
            uniqueVisitors = @($PageViews | Select-Object -Property IpAddress -Unique).Count
        }
        
        # Get recent page views (last 100)
        $RecentPageViews = @($PageViews | Sort-Object EventTimestamp -Descending | Select-Object -First 100 | ForEach-Object {
            @{
                timestamp = $_.EventTimestamp
                ipAddress = $_.IpAddress
                userAgent = $_.UserAgent
                referrer = $_.Referrer
            }
        })
        
        # Get recent link clicks (last 100)
        $RecentLinkClicks = @($LinkClicks | Sort-Object EventTimestamp -Descending | Select-Object -First 100 | ForEach-Object {
            @{
                timestamp = $_.EventTimestamp
                ipAddress = $_.IpAddress
                userAgent = $_.UserAgent
                referrer = $_.Referrer
                linkId = $_.LinkId
                linkTitle = $_.LinkTitle
                linkUrl = $_.LinkUrl
            }
        })
        
        # Get link clicks grouped by link (most popular links)
        $LinkClicksByLink = @($LinkClicks | Group-Object LinkId | ForEach-Object {
            $FirstClick = $_.Group | Select-Object -First 1
            @{
                linkId = $_.Name
                linkTitle = $FirstClick.LinkTitle
                linkUrl = $FirstClick.LinkUrl
                clickCount = $_.Count
            }
        } | Sort-Object clickCount -Descending)
        
        # Get page views by day (last 30 days)
        $ThirtyDaysAgo = [DateTimeOffset]::UtcNow.AddDays(-30)
        $ViewsByDay = @($PageViews | Where-Object { [DateTimeOffset]$_.EventTimestamp -gt $ThirtyDaysAgo } | 
            Group-Object { ([DateTimeOffset]$_.EventTimestamp).ToString('yyyy-MM-dd') } | 
            ForEach-Object {
                @{
                    date = $_.Name
                    count = $_.Count
                }
            } | Sort-Object date)
        
        # Get link clicks by day (last 30 days)
        $ClicksByDay = @($LinkClicks | Where-Object { [DateTimeOffset]$_.EventTimestamp -gt $ThirtyDaysAgo } | 
            Group-Object { ([DateTimeOffset]$_.EventTimestamp).ToString('yyyy-MM-dd') } | 
            ForEach-Object {
                @{
                    date = $_.Name
                    count = $_.Count
                }
            } | Sort-Object date)
        
        $Results = @{
            summary = $Summary
            recentPageViews = $RecentPageViews
            recentLinkClicks = $RecentLinkClicks
            linkClicksByLink = $LinkClicksByLink
            viewsByDay = $ViewsByDay
            clicksByDay = $ClicksByDay
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get analytics error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get analytics"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
