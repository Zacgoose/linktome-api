function Invoke-AdminDeletePage {
    <#
    .SYNOPSIS
        Delete a page
    .DESCRIPTION
        Deletes a page and all associated links, groups, and appearance settings.
        Cannot delete the default page.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:pages
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $PageId = $Request.Query.id
    
    try {
        # Validate required parameter
        if (-not $PageId) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Page id is required" }
            }
        }
        
        $PagesTable = Get-LinkToMeTable -TableName 'Pages'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $SafePageId = Protect-TableQueryValue -Value $PageId
        
        # Get the page to delete
        $Page = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId' and RowKey eq '$SafePageId'" | Select-Object -First 1
        
        if (-not $Page) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Page not found" }
            }
        }
        
        # Prevent deleting default page
        if ([bool]$Page.IsDefault) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Cannot delete the default page" }
            }
        }
        
        # Delete associated links
        $LinksTable = Get-LinkToMeTable -TableName 'Links'
        $Links = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'"
        if ($Links) {
            foreach ($Link in $Links) {
                Remove-AzDataTableEntity -Entity $Link -Context $LinksTable.Context
            }
        }
        
        # Delete associated link groups
        $GroupsTable = Get-LinkToMeTable -TableName 'LinkGroups'
        $Groups = Get-LinkToMeAzDataTableEntity @GroupsTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'"
        if ($Groups) {
            foreach ($Group in $Groups) {
                Remove-AzDataTableEntity -Entity $Group -Context $GroupsTable.Context
            }
        }
        
        # Delete the page
        Remove-AzDataTableEntity -Entity $Page -Context $PagesTable.Context
        
        $Results = @{
            message = "Page deleted successfully"
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Delete page error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to delete page"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
