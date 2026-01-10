function Invoke-AdminGetDashboardStats {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:dashboard
    .DESCRIPTION
        Returns simplified dashboard statistics showing only total links count.
        Analytics data (page views, link clicks) has been moved to the Analytics page.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $PageId = $Request.Query.pageId

    try {
        # Get user's links count
        $LinksTable = Get-LinkToMeTable -TableName 'Links'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $Links = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId'"
        
        # Filter links by page if specified
        if ($PageId) {
            $SafePageId = Protect-TableQueryValue -Value $PageId
            $Links = @($Links | Where-Object { $_.PageId -eq $SafePageId })
        }
        
        # Return simplified dashboard stats (only totalLinks as per redesign)
        $Results = @{
            stats = @{
                totalLinks = $Links.Count
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
