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
    $PageId = $Request.Query.pageId

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
        
        # Try to get pre-aggregated analytics first (much faster)
        # Apply tier-based limits on historical data days (from Get-TierFeatures)
        $TierFeatures = Get-TierFeatures -Tier $UserTier
        $DaysBackLimit = if ($TierFeatures.limits.analyticsRetentionDays -eq -1) {
            # Unlimited for enterprise - use the aggregated data retention period
            180
        } else {
            $TierFeatures.limits.analyticsRetentionDays
        }
        
        Write-Information "User tier: $UserTier, Days back limit: $DaysBackLimit"
        $AggregatedData = Get-AggregatedAnalytics -UserId $UserId -PageId $PageId -DaysBack $DaysBackLimit
        
        if ($AggregatedData) {
            Write-Information "Using pre-aggregated analytics data"
            
            # Use aggregated summary
            $Summary = $AggregatedData.summary
            
            # Basic analytics (available to all tiers)
            $Results = @{
                summary = $Summary
                hasAdvancedAnalytics = $HasAdvancedAnalytics
            }
            
            # Advanced analytics - only for premium/enterprise tiers
            if ($HasAdvancedAnalytics) {
                # For aggregated data, we don't have individual event details
                # But we have the pre-computed stats which are the main value
                $Results.recentPageViews = @()  # Not available in aggregated data
                $Results.recentLinkClicks = @()  # Not available in aggregated data
                $Results.linkClicksByLink = $AggregatedData.linkClicksByLink
                $Results.viewsByDay = $AggregatedData.viewsByDay
                $Results.clicksByDay = $AggregatedData.clicksByDay
                
                # Add new aggregated data
                if ($AggregatedData.topReferrers) {
                    $Results.topReferrers = $AggregatedData.topReferrers
                }
                if ($AggregatedData.topUserAgents) {
                    $Results.topUserAgents = $AggregatedData.topUserAgents
                }
                
                if ($AggregatedData.pageBreakdown.Count -gt 0) {
                    # Enrich with page names from Pages table
                    $PagesTable = Get-LinkToMeTable -TableName 'Pages'
                    $SafeUserId = Protect-TableQueryValue -Value $UserId
                    $UserPages = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId'"
                    
                    $Results.pageBreakdown = @($AggregatedData.pageBreakdown | ForEach-Object {
                        $pageInfo = $UserPages | Where-Object { $_.RowKey -eq $_.pageId } | Select-Object -First 1
                        if ($pageInfo) {
                            @{
                                pageId = $_.pageId
                                pageName = $pageInfo.Name
                                pageSlug = $pageInfo.Slug
                                totalPageViews = $_.totalPageViews
                                totalLinkClicks = $_.totalLinkClicks
                            }
                        }
                    } | Where-Object { $_ })
                }
            } else {
                # Return limited data for free tier
                $Results.recentPageViews = @()
                $Results.recentLinkClicks = @()
                $Results.linkClicksByLink = @()
                $Results.viewsByDay = @()
                $Results.clicksByDay = @()
            }
            
            $StatusCode = [HttpStatusCode]::OK
        } else {
            # Fallback to raw analytics events if aggregated data not available
            Write-Information "Falling back to raw analytics events"
            
            $Table = Get-LinkToMeTable -TableName 'Analytics'

            # Get analytics events for this user context
            $SafeUserId = Protect-TableQueryValue -Value $UserId
            $Events = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'"
            
            # Filter by page if specified
            if ($PageId) {
                $SafePageId = Protect-TableQueryValue -Value $PageId
                $Events = @($Events | Where-Object { $_.PageId -eq $SafePageId })
            }
            
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
                $pvObj = @{
                    timestamp = $_.EventTimestamp
                    ipAddress = $_.IpAddress
                    userAgent = $_.UserAgent
                    referrer = $_.Referrer
                }
                if ($_.PageId) { $pvObj.pageId = $_.PageId }
                $pvObj
            })
            
            # Get recent link clicks (last 100)
            $RecentLinkClicks = @($LinkClicks | Sort-Object EventTimestamp -Descending | Select-Object -First 100 | ForEach-Object {
                $lcObj = @{
                    timestamp = $_.EventTimestamp
                    ipAddress = $_.IpAddress
                    userAgent = $_.UserAgent
                    referrer = $_.Referrer
                    linkId = $_.LinkId
                    linkTitle = $_.LinkTitle
                    linkUrl = $_.LinkUrl
                }
                if ($_.PageId) { $lcObj.pageId = $_.PageId }
                $lcObj
            })
            
            # Get link clicks grouped by link (most popular links)
            $LinkClicksByLink = @($LinkClicks | Group-Object LinkId | ForEach-Object {
                $FirstClick = $_.Group | Select-Object -First 1
                $lcblObj = @{
                    linkId = $_.Name
                    linkTitle = $FirstClick.LinkTitle
                    linkUrl = $FirstClick.LinkUrl
                    clickCount = $_.Count
                }
                if ($FirstClick.PageId) { $lcblObj.pageId = $FirstClick.PageId }
                $lcblObj
            } | Sort-Object clickCount -Descending)
            
            # Get page views by day (apply tier-based days limit)
            $DaysAgo = [DateTimeOffset]::UtcNow.AddDays(-$DaysBackLimit)
            $ViewsByDay = @($PageViews | Where-Object { [DateTimeOffset]$_.EventTimestamp -gt $DaysAgo } | 
                Group-Object { ([DateTimeOffset]$_.EventTimestamp).ToString('yyyy-MM-dd') } | 
                ForEach-Object {
                    @{
                        date = $_.Name
                        count = $_.Count
                    }
                } | Sort-Object date)
            
            # Get link clicks by day (apply tier-based days limit)
            $ClicksByDay = @($LinkClicks | Where-Object { [DateTimeOffset]$_.EventTimestamp -gt $DaysAgo } | 
                Group-Object { ([DateTimeOffset]$_.EventTimestamp).ToString('yyyy-MM-dd') } | 
                ForEach-Object {
                    @{
                        date = $_.Name
                        count = $_.Count
                    }
                } | Sort-Object date)
            
            # Get per-page breakdown if no specific page filter
            $PageBreakdown = @()
            if (-not $PageId) {
                # Get all events with PageId
                $AllEventsWithPage = @($Events | Where-Object { $_.PageId })
                
                if ($AllEventsWithPage.Count -gt 0) {
                    # Get pages info
                    $PagesTable = Get-LinkToMeTable -TableName 'Pages'
                    $UserPages = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId'"
                    
                    # Group by PageId
                    $PageBreakdown = @($AllEventsWithPage | Group-Object PageId | ForEach-Object {
                        $pageId = $_.Name
                        $pageEvents = $_.Group
                        $pageInfo = $UserPages | Where-Object { $_.RowKey -eq $pageId } | Select-Object -First 1
                        
                        if ($pageInfo) {
                            @{
                                pageId = $pageId
                                pageName = $pageInfo.Name
                                pageSlug = $pageInfo.Slug
                                totalPageViews = @($pageEvents | Where-Object { $_.EventType -eq 'PageView' }).Count
                                totalLinkClicks = @($pageEvents | Where-Object { $_.EventType -eq 'LinkClick' }).Count
                            }
                        }
                    } | Where-Object { $_ } | Sort-Object totalPageViews -Descending)
                }
            }
            
            $Results.recentPageViews = $RecentPageViews
            $Results.recentLinkClicks = $RecentLinkClicks
            $Results.linkClicksByLink = $LinkClicksByLink
            $Results.viewsByDay = $ViewsByDay
            $Results.clicksByDay = $ClicksByDay
            if ($PageBreakdown.Count -gt 0) {
                $Results.pageBreakdown = $PageBreakdown
            }
            } else {
                # Return limited data for free tier (frontend manages upgrade prompts)
                $Results.recentPageViews = @()
                $Results.recentLinkClicks = @()
                $Results.linkClicksByLink = @()
                $Results.viewsByDay = @()
                $Results.clicksByDay = @()
            }
            
            $StatusCode = [HttpStatusCode]::OK
        }
        
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
