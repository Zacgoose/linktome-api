function Invoke-AdminUpdateLinks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        User.Links.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body

    try {
        $Table = Get-LinkToMeTable -TableName 'Links'
        
        # Body should contain array of links with id, title, url, order, active
        if (-not $Body.links) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Links array required" }
            }
        }
        
        # Get existing links
        $ExistingLinks = Get-AzDataTableEntity @Table -Filter "PartitionKey eq '$($User.UserId)'"
        
        # Process each link in request
        foreach ($Link in $Body.links) {
            if ($Link.id) {
                # Update existing link
                $ExistingLink = $ExistingLinks | Where-Object { $_.RowKey -eq $Link.id } | Select-Object -First 1
                if ($ExistingLink) {
                    $ExistingLink.Title = $Link.title
                    $ExistingLink.Url = $Link.url
                    $ExistingLink.Order = $Link.order
                    $ExistingLink.Active = $Link.active
                    Add-AzDataTableEntity @Table -Entity $ExistingLink -Force
                }
            } else {
                # Create new link
                $NewLink = @{
                    PartitionKey = $User.UserId
                    RowKey = 'link-' + (New-Guid).ToString()
                    Title = $Link.title
                    Url = $Link.url
                    Order = $Link.order
                    Active = $Link.active
                }
                Add-AzDataTableEntity @Table -Entity $NewLink -Force
            }
        }
        
        # Delete links not in request
        $RequestIds = $Body.links | Where-Object { $_.id } | ForEach-Object { $_.id }
        $LinksToDelete = $ExistingLinks | Where-Object { $_.RowKey -notin $RequestIds }
        foreach ($LinkToDelete in $LinksToDelete) {
            Remove-AzDataTableEntity @Table -Entity $LinkToDelete
        }
        
        $Results = @{ success = $true }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Update links error: $($_.Exception.Message)"
        $Results = @{ error = "Failed to update links" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}