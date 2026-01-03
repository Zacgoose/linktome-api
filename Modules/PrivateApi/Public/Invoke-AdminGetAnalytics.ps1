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
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }

    try {
        # Get the actual user object to check tier
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Check if user has access to advanced analytics
        $HasAdvancedAnalytics = Test-FeatureAccess -User $User -Feature 'advanced_analytics'
        
        # Get client IP for usage tracking
        $ClientIP = Get-ClientIPAddress -Request $Request
        
        # Track feature usage
        $UserTier = $User.SubscriptionTier
        Write-FeatureUsageEvent -UserId $UserId -Feature 'advanced_analytics' -Allowed $HasAdvancedAnalytics -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/getAnalytics'
        
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
        
        # Basic analytics (available to all tiers)
        $Results = @{
            summary = $Summary
            hasAdvancedAnalytics = $HasAdvancedAnalytics
        }
        
        # Advanced analytics - only for premium/enterprise tiers
        if ($HasAdvancedAnalytics) {
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
            
            $Results.recentPageViews = $RecentPageViews
            $Results.recentLinkClicks = $RecentLinkClicks
            $Results.linkClicksByLink = $LinkClicksByLink
            $Results.viewsByDay = $ViewsByDay
            $Results.clicksByDay = $ClicksByDay
        } else {
            # Return limited data for free tier (frontend manages upgrade prompts)
            $Results.recentPageViews = @()
            $Results.recentLinkClicks = @()
            $Results.linkClicksByLink = @()
            $Results.viewsByDay = @()
            $Results.clicksByDay = @()
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
