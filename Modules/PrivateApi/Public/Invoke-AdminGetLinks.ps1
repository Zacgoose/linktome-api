function Invoke-AdminGetLinks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:links
    .DESCRIPTION
        Returns the user's links and link groups with all properties including thumbnail, layout, animation, schedule, and lock settings.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $PageId = $Request.Query.pageId
    
    try {
        # If no pageId specified, get default page
        if (-not $PageId) {
            $PagesTable = Get-LinkToMeTable -TableName 'Pages'
            $SafeUserId = Protect-TableQueryValue -Value $UserId
            $DefaultPage = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId' and IsDefault eq true" | Select-Object -First 1
            
            if (-not $DefaultPage) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body = @{ error = "No default page found. Please create a page first." }
                }
            }
            
            $PageId = $DefaultPage.RowKey
        }
        
        $LinksTable = Get-LinkToMeTable -TableName 'Links'
        $GroupsTable = Get-LinkToMeTable -TableName 'LinkGroups'
        
        # Sanitize UserId and PageId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $SafePageId = Protect-TableQueryValue -Value $PageId
        
        # Get links for specific page
        $Links = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'"
        
        $LinkResults = @($Links | ForEach-Object {
            $linkObj = @{
                id = $_.RowKey
                title = $_.Title
                url = $_.Url
                order = [int]$_.Order
                active = [bool]$_.Active
            }
            
            # Basic properties
            if ($_.Icon) { $linkObj.icon = $_.Icon }
            if ($_.Thumbnail) { $linkObj.thumbnail = $_.Thumbnail }
            if ($_.ThumbnailType) { $linkObj.thumbnailType = $_.ThumbnailType }
            if ($_.Layout) { $linkObj.layout = $_.Layout }
            if ($_.Animation) { $linkObj.animation = $_.Animation }
            if ($_.GroupId) { $linkObj.groupId = $_.GroupId }
            
            # Analytics
            if ($null -ne $_.Clicks) { $linkObj.clicks = [int]$_.Clicks }
            if ($_.ClicksTrend) { $linkObj.clicksTrend = $_.ClicksTrend }
            
            # Schedule settings (stored as JSON string)
            if ($_.ScheduleEnabled) {
                $linkObj.schedule = @{
                    enabled = [bool]$_.ScheduleEnabled
                }
                if ($_.ScheduleStartDate) { $linkObj.schedule.startDate = $_.ScheduleStartDate }
                if ($_.ScheduleEndDate) { $linkObj.schedule.endDate = $_.ScheduleEndDate }
                if ($_.ScheduleTimezone) { $linkObj.schedule.timezone = $_.ScheduleTimezone }
            }
            
            # Lock settings
            if ($_.LockEnabled) {
                $linkObj.lock = @{
                    enabled = [bool]$_.LockEnabled
                }
                if ($_.LockType) { $linkObj.lock.type = $_.LockType }
                if ($_.LockCode) { $linkObj.lock.code = $_.LockCode }
                if ($_.LockMessage) { $linkObj.lock.message = $_.LockMessage }
            }
            
            $linkObj
        } | Sort-Object order)
        
        # Get all groups for specific page
        $Groups = Get-LinkToMeAzDataTableEntity @GroupsTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'"
        
        $GroupResults = @($Groups | ForEach-Object {
            $groupObj = @{
                id = $_.RowKey
                title = $_.Title
                order = [int]$_.Order
                active = [bool]$_.Active
            }
            if ($_.Layout) { $groupObj.layout = $_.Layout }
            if ($null -ne $_.Collapsed) { $groupObj.collapsed = [bool]$_.Collapsed }
            $groupObj
        } | Sort-Object order)
        
        $Results = @{
            links = $LinkResults
            groups = $GroupResults
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get links error: $($_.Exception.Message)"
        $Results = @{ error = "Failed to get links" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}