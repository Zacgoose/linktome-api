function Invoke-AdminCreatePage {
    <#
    .SYNOPSIS
        Create a new page
    .DESCRIPTION
        Creates a new page for the authenticated user. Validates tier limits and slug format.
        Free tier users are limited to 1 page.
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
        # Validate required fields
        if (-not $Body.slug) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Slug is required" }
            }
        }
        if (-not $Body.name) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Name is required" }
            }
        }
        
        # Validate slug format
        $Slug = $Body.slug.ToLower()
        if (-not (Test-SlugFormat -Slug $Slug)) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid slug format. Must be 3-30 characters, lowercase letters, numbers, and hyphens only. Cannot start/end with hyphen or be a reserved word." }
            }
        }
        
        # Validate name length
        $NameCheck = Test-InputLength -Value $Body.name -MaxLength 100 -FieldName "Page name"
        if (-not $NameCheck.Valid) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = $NameCheck.Message }
            }
        }
        
        # Get user to check tier
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        $UserTier = $User.SubscriptionTier
        $TierInfo = Get-TierFeatures -Tier $UserTier
        $MaxPages = $TierInfo.limits.maxPages
        
        # Get existing pages
        $PagesTable = Get-LinkToMeTable -TableName 'Pages'
        $ExistingPages = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId'"
        
        # Check page limit
        if ($MaxPages -ne -1 -and $ExistingPages.Count -ge $MaxPages) {
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-FeatureUsageEvent -UserId $UserId -Feature 'page_limit_exceeded' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/createPage'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{ error = "Page limit reached for your tier. Your $($TierInfo.tierName) plan allows up to $MaxPages page(s)." }
            }
        }
        
        # Check slug uniqueness
        $ExistingSlug = $ExistingPages | Where-Object { $_.Slug -eq $Slug } | Select-Object -First 1
        if ($ExistingSlug) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "A page with this slug already exists" }
            }
        }
        
        # Determine if this should be default (if isDefault specified or if it's first page)
        $IsDefault = if ($Body.PSObject.Properties.Match('isDefault').Count -gt 0) {
            [bool]$Body.isDefault
        } else {
            $ExistingPages.Count -eq 0
        }
        
        # If setting as default, unset other defaults
        if ($IsDefault) {
            foreach ($Page in $ExistingPages) {
                if ([bool]$Page.IsDefault) {
                    $Page.IsDefault = $false
                    Add-LinkToMeAzDataTableEntity @PagesTable -Entity $Page -Force
                }
            }
        }
        
        # Create new page
        $PageId = [guid]::NewGuid().ToString()
        $NewPage = @{
            PartitionKey = $UserId
            RowKey = $PageId
            Slug = $Slug
            Name = $Body.name
            IsDefault = $IsDefault
            CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
            UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
        
        Add-LinkToMeAzDataTableEntity @PagesTable -Entity $NewPage -Force
        
        $Results = @{
            message = "Page created successfully"
            page = @{
                id = $PageId
                userId = $UserId
                slug = $Slug
                name = $Body.name
                isDefault = $IsDefault
                createdAt = $NewPage.CreatedAt
                updatedAt = $NewPage.UpdatedAt
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Create page error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to create page"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
