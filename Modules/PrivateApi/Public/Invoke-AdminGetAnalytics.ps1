function Invoke-AdminGetAnalytics {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        User.Analytics.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser

    try {
        $Table = Get-LinkToMeTable -TableName 'Analytics'
        
        # Get analytics events for this user
        $SafeUserId = Protect-TableQueryValue -Value $User.UserId
        $Events = Get-AzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'"
        
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
        
        $Results = @{
            summary = $Summary
            recentPageViews = $RecentPageViews
            viewsByDay = $ViewsByDay
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
