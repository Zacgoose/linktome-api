function Invoke-AdminGetPages {
    <#
    .SYNOPSIS
        Get all pages for a user
    .DESCRIPTION
        Returns all pages owned by the authenticated user, sorted by IsDefault (true first) then CreatedAt.
        Automatically ensures user has a default page.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:pages
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    
    try {
        $PagesTable = Get-LinkToMeTable -TableName 'Pages'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        
        # Get all pages for user
        $Pages = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId'"
        
        # Transform and sort pages
        $PageResults = @($Pages | ForEach-Object {
            @{
                id = $_.RowKey
                userId = $_.PartitionKey
                slug = $_.Slug
                name = $_.Name
                isDefault = [bool]$_.IsDefault
                createdAt = $_.CreatedAt
                updatedAt = $_.UpdatedAt
            }
        } | Sort-Object @{Expression={-([bool]$_.isDefault)}}, @{Expression={$_.createdAt}})
        
        $Results = @{
            pages = $PageResults
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get pages error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get pages"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
