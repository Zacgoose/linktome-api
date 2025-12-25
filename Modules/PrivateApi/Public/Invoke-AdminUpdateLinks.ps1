function Invoke-AdminUpdateLinks {
    <#
    .SYNOPSIS
        Update, add, or remove user links in bulk.
    .DESCRIPTION
        Accepts an array of link objects, each with an operation property ("add", "update", "remove").
        Performs the requested operation for each link. Maximum 50 links per user.
    .PARAMETER links
        Array of link objects. Each object must include an "operation" property with one of: "add", "update", "remove".
        For "add" and "update": must include title, url, order, active. For "update" and "remove": must include id.
    .EXAMPLE
        Request body:
        {
            "links": [
                { "operation": "add", "title": "My Site", "url": "https://mysite.com", "order": 1, "active": true },
                { "operation": "update", "id": "link-abc123", "title": "New Title", "url": "https://new.com", "order": 2, "active": true },
                { "operation": "remove", "id": "link-def456" }
            ]
        }
    .ROLE
        write:links
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

    try {
        if (-not $Body.links) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Links array required" }
            }
        }

        $Table = Get-LinkToMeTable -TableName 'Links'

        # Validate max number of links (excluding removes)
        $addOrUpdateCount = ($Body.links | Where-Object { $_.operation -in @('add','update') }).Count
        if ($addOrUpdateCount -gt 50) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Maximum 50 links allowed per user" }
            }
        }

        # Sanitize UserId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $ExistingLinks = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'"

        foreach ($Link in $Body.links) {
            $op = ($Link.operation ?? '').ToLower()
            switch ($op) {
                'add' {
                    # Validate required fields
                    if (-not $Link.title) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Link title is required for add" }
                        }
                    }
                    if (-not $Link.url) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Link URL is required for add" }
                        }
                    }
                    $TitleCheck = Test-InputLength -Value $Link.title -MaxLength 100 -FieldName "Link title"
                    if (-not $TitleCheck.Valid) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = $TitleCheck.Message }
                        }
                    }
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
                    $NewLink = @{
                        PartitionKey = $UserId
                        RowKey = 'link-' + (New-Guid).ToString()
                        Title = $Link.title
                        Url = $Link.url
                        Order = $Link.order
                        Active = $Link.active
                    }
                    # Add icon if provided
                    if ($Link.icon) {
                        $NewLink.Icon = $Link.icon
                    }
                    Add-LinkToMeAzDataTableEntity @Table -Entity $NewLink -Force
                }
                'update' {
                    if (-not $Link.id) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Link id is required for update" }
                        }
                    }
                    $ExistingLink = $ExistingLinks | Where-Object { $_.RowKey -eq $Link.id } | Select-Object -First 1
                    if (-not $ExistingLink) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::NotFound
                            Body = @{ error = "Link not found for update: $($Link.id)" }
                        }
                    }
                    if ($Link.title) {
                        $TitleCheck = Test-InputLength -Value $Link.title -MaxLength 100 -FieldName "Link title"
                        if (-not $TitleCheck.Valid) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = $TitleCheck.Message }
                            }
                        }
                        $ExistingLink.Title = $Link.title
                    }
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
                        $ExistingLink.Url = $Link.url
                    }
                    if ($Link.PSObject.Properties.Match('order')) { $ExistingLink.Order = $Link.order }
                    if ($Link.PSObject.Properties.Match('active')) { $ExistingLink.Active = $Link.active }
                    if ($Link.PSObject.Properties.Match('icon') -and $Link.icon) {
                        $ExistingLink | Add-Member -MemberType NoteProperty -Name 'Icon' -Value $Link.icon -Force
                    }
                    Add-LinkToMeAzDataTableEntity @Table -Entity $ExistingLink -Force
                }
                'remove' {
                    if (-not $Link.id) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Link id is required for remove" }
                        }
                    }
                    $ExistingLink = $ExistingLinks | Where-Object { $_.RowKey -eq $Link.id } | Select-Object -First 1
                    if ($ExistingLink) {
                        Remove-AzDataTableEntity -Entity $ExistingLink -Context $Table.Context
                    }
                }
                default {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Invalid operation: $op. Must be add, update, or remove." }
                    }
                }
            }
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