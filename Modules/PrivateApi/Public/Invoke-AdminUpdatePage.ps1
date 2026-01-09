function Invoke-AdminUpdatePage {
    <#
    .SYNOPSIS
        Update an existing page
    .DESCRIPTION
        Updates a page's slug, name, or isDefault status. Validates slug uniqueness.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:pages
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body
    
    try {
        # Validate required field
        if (-not $Body.id) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Page id is required" }
            }
        }
        
        $PagesTable = Get-LinkToMeTable -TableName 'Pages'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $SafePageId = Protect-TableQueryValue -Value $Body.id
        
        # Get the page to update
        $Page = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId' and RowKey eq '$SafePageId'" | Select-Object -First 1
        
        if (-not $Page) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Page not found" }
            }
        }
        
        # Update slug if provided
        if ($Body.slug -and $Body.slug -ne $Page.Slug) {
            $NewSlug = $Body.slug.ToLower()
            
            # Validate slug format
            if (-not (Test-SlugFormat -Slug $NewSlug)) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Invalid slug format. Must be 3-30 characters, lowercase letters, numbers, and hyphens only. Cannot start/end with hyphen or be a reserved word." }
                }
            }
            
            # Check slug uniqueness
            $ExistingSlug = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId' and Slug eq '$NewSlug'" | Select-Object -First 1
            if ($ExistingSlug -and $ExistingSlug.RowKey -ne $SafePageId) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Slug already in use" }
                }
            }
            
            $Page.Slug = $NewSlug
        }
        
        # Update name if provided
        if ($Body.name) {
            $NameCheck = Test-InputLength -Value $Body.name -MaxLength 100 -FieldName "Page name"
            if (-not $NameCheck.Valid) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = $NameCheck.Message }
                }
            }
            $Page.Name = $Body.name
        }
        
        # Update isDefault if provided
        if ($Body.PSObject.Properties.Match('isDefault').Count -gt 0) {
            $NewIsDefault = [bool]$Body.isDefault
            
            # If setting as default, unset other defaults
            if ($NewIsDefault -and -not [bool]$Page.IsDefault) {
                $AllPages = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId'"
                foreach ($P in $AllPages) {
                    if ([bool]$P.IsDefault -and $P.RowKey -ne $SafePageId) {
                        $P.IsDefault = $false
                        Add-LinkToMeAzDataTableEntity @PagesTable -Entity $P -Force
                    }
                }
            }
            
            $Page.IsDefault = $NewIsDefault
        }
        
        # Update timestamp
        $Page.UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @PagesTable -Entity $Page -Force
        
        $Results = @{
            message = "Page updated successfully"
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Update page error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update page"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
