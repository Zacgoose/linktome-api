function Invoke-AdminGetDashboardStats {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:dashboard
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser

    try {
        # Get user's links count
        $LinksTable = Get-LinkToMeTable -TableName 'Links'
        $SafeUserId = Protect-TableQueryValue -Value $User.UserId
        $Links = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId'"
        $ActiveLinks = @($Links | Where-Object { $_.Active -eq $true })
        
        # Get analytics summary
        $AnalyticsTable = Get-LinkToMeTable -TableName 'Analytics'
        $AnalyticsEvents = Get-LinkToMeAzDataTableEntity @AnalyticsTable -Filter "PartitionKey eq '$SafeUserId'"
        
        $PageViews = @($AnalyticsEvents | Where-Object { $_.EventType -eq 'PageView' })
        $LinkClicks = @($AnalyticsEvents | Where-Object { $_.EventType -eq 'LinkClick' })
        
        # Calculate views for last 30 days
        $ThirtyDaysAgo = [DateTimeOffset]::UtcNow.AddDays(-30)
        $RecentViews = @($PageViews | Where-Object { [DateTimeOffset]$_.EventTimestamp -gt $ThirtyDaysAgo })
        
        # Calculate views for last 7 days
        $SevenDaysAgo = [DateTimeOffset]::UtcNow.AddDays(-7)
        $LastWeekViews = @($PageViews | Where-Object { [DateTimeOffset]$_.EventTimestamp -gt $SevenDaysAgo })
        
        $Results = @{
            stats = @{
                totalLinks = $Links.Count
                activeLinks = $ActiveLinks.Count
                totalPageViews = $PageViews.Count
                totalLinkClicks = $LinkClicks.Count
                uniqueVisitors = @($PageViews | Select-Object -Property IpAddress -Unique).Count
                viewsLast30Days = $RecentViews.Count
                viewsLast7Days = $LastWeekViews.Count
            }
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get dashboard stats error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get dashboard stats"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
