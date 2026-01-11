function Invoke-AdminGetShortLinkAnalytics {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:analytics
    .DESCRIPTION
        Returns analytics for short link redirects.
        Shows detailed analytics including redirect history, referrers, and geographic data.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Slug = $Request.Query.slug
    
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
        $UserTier = $User.SubscriptionTier
        Write-FeatureUsageEvent -UserId $UserId -Feature 'shortlink_analytics' -Allowed $HasAdvancedAnalytics -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/getShortLinkAnalytics'
        
        $AnalyticsTable = Get-LinkToMeTable -TableName 'Analytics'
        
        # Get all short link redirect events for this user
        $Events = Get-LinkToMeAzDataTableEntity @AnalyticsTable -Filter "PartitionKey eq '$SafeUserId'"
        $ShortLinkRedirects = @($Events | Where-Object { $_.EventType -eq 'ShortLinkRedirect' })
        
        # If slug is specified, filter to that specific short link
        if ($Slug) {
            $SafeSlug = Protect-TableQueryValue -Value $Slug.ToLower()
            
            # Verify the short link belongs to this user
            $ShortLinksTable = Get-LinkToMeTable -TableName 'ShortLinks'
            $ShortLink = Get-LinkToMeAzDataTableEntity @ShortLinksTable -Filter "PartitionKey eq '$SafeUserId' and RowKey eq '$SafeSlug'" | Select-Object -First 1
            
            if (-not $ShortLink) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body = @{ error = "Short link not found" }
                }
            }
            
            $ShortLinkRedirects = @($ShortLinkRedirects | Where-Object { $_.LinkId -eq $Slug.ToLower() })
        }
        
        # Calculate summary statistics
        $Summary = @{
            totalRedirects = $ShortLinkRedirects.Count
            uniqueVisitors = @($ShortLinkRedirects | Select-Object -Property IpAddress -Unique).Count
        }
        
        # Basic analytics (available to all tiers)
        $Results = @{
            summary = $Summary
            hasAdvancedAnalytics = $HasAdvancedAnalytics
        }
        
        # Advanced analytics - only for pro/premium/enterprise tiers
        if ($HasAdvancedAnalytics) {
            # Get recent redirects (last 100)
            $RecentRedirects = @($ShortLinkRedirects | Sort-Object EventTimestamp -Descending | Select-Object -First 100 | ForEach-Object {
                @{
                    timestamp = $_.EventTimestamp.ToString('o')
                    slug = $_.LinkId
                    targetUrl = $_.LinkUrl
                    ipAddress = $_.IpAddress
                    userAgent = $_.UserAgent
                    referrer = $_.Referrer
                }
            })
            
            # Get redirects grouped by slug (most popular short links)
            $RedirectsBySlug = @($ShortLinkRedirects | Group-Object LinkId | ForEach-Object {
                $FirstRedirect = $_.Group | Select-Object -First 1
                @{
                    slug = $_.Name
                    targetUrl = $FirstRedirect.LinkUrl
                    clicks = $_.Count
                }
            } | Sort-Object clicks -Descending)
            
            # Get redirects by day (last 30 days)
            $Now = [DateTime]::UtcNow
            $ThirtyDaysAgo = $Now.AddDays(-30)
            $RecentRedirects = @($ShortLinkRedirects | Where-Object { 
                $_.EventTimestamp -and [DateTime]$_.EventTimestamp -gt $ThirtyDaysAgo 
            })
            
            $RedirectsByDay = @($RecentRedirects | Group-Object { 
                ([DateTime]$_.EventTimestamp).ToString('yyyy-MM-dd')
            } | ForEach-Object {
                @{
                    date = $_.Name
                    clicks = $_.Count
                }
            } | Sort-Object date)
            
            # Get top referrers
            $TopReferrers = @($ShortLinkRedirects | Where-Object { $_.Referrer } | 
                Group-Object Referrer | ForEach-Object {
                    @{
                        referrer = $_.Name
                        count = $_.Count
                    }
                } | Sort-Object count -Descending | Select-Object -First 10)
            
            $Results.recentRedirects = $RecentRedirects
            $Results.topShortLinks = $RedirectsBySlug
            $Results.redirectsByDay = $RedirectsByDay
            $Results.topReferrers = $TopReferrers
        } else {
            # Return upgrade message for users without advanced analytics
            $Results.message = "Upgrade to Pro or higher to access detailed short link analytics including redirect history, referrers, and trends."
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get short link analytics error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get short link analytics"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
