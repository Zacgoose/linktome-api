function Invoke-AdminUpdateLinks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:links
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
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
        
        # Validate max number of links
        if ($Body.links.Count -gt 50) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Maximum 50 links allowed per user" }
            }
        }
        
        # Validate each link before processing
        foreach ($Link in $Body.links) {
            # Validate title
            if ($Link.title) {
                $TitleCheck = Test-InputLength -Value $Link.title -MaxLength 100 -FieldName "Link title"
                if (-not $TitleCheck.Valid) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = $TitleCheck.Message }
                    }
                }
            } else {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Link title is required" }
                }
            }
            
            # Validate URL
            if ($Link.url) {
                $UrlCheck = Test-InputLength -Value $Link.url -MaxLength 2048 -FieldName "Link URL"
                if (-not $UrlCheck.Valid) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = $UrlCheck.Message }
                    }
                }
                
                if (-not (Test-UrlFormat -Url $Link.url)) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Link URL must be a valid http or https URL: $($Link.title)" }
                    }
                }
            } else {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Link URL is required" }
                }
            }
        }
        
        # Sanitize UserId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        
        # Get existing links
        $ExistingLinks = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'"
        
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
                    Add-LinkToMeAzDataTableEntity @Table -Entity $ExistingLink -Force
                }
            } else {
                # Create new link
                $NewLink = @{
                    PartitionKey = $UserId
                    RowKey = 'link-' + (New-Guid).ToString()
                    Title = $Link.title
                    Url = $Link.url
                    Order = $Link.order
                    Active = $Link.active
                }
                Add-LinkToMeAzDataTableEntity @Table -Entity $NewLink -Force
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
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update links"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}