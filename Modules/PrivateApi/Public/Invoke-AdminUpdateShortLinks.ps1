function Invoke-AdminUpdateShortLinks {
    <#
    .SYNOPSIS
        Create, update, or delete short links in bulk.
    .DESCRIPTION
        Accepts an array of short link objects, each with an operation property ("add", "update", "remove").
        Enforces tier-based limits on number of short links.
    .PARAMETER shortLinks
        Array of short link objects. Each object must include an "operation" property with one of: "add", "update", "remove".
        For "add": requires slug, targetUrl, optional title
        For "update" and "remove": requires slug
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:shortlinks
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

    if (-not $Body.shortLinks) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "shortLinks array is required" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'ShortLinks'
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize UserId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        
        # Get user to check tier limits
        $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Get tier features to check short link limit
        $UserTier = if ($User.SubscriptionTier) { $User.SubscriptionTier } else { 'free' }
        $TierInfo = Get-TierFeatures -Tier $UserTier
        
        # Define short link limits per tier
        $ShortLinkLimits = @{
            'free' = 0          # Free tier: no short links
            'pro' = 5           # Pro tier: 5 short links
            'premium' = 20      # Premium tier: 20 short links
            'enterprise' = -1   # Enterprise: unlimited
        }
        
        $MaxShortLinks = $ShortLinkLimits[$UserTier]
        
        # Get existing short links to check total count
        $ExistingLinks = @(Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'")
        
        # Count adds vs removes to determine final count
        $addsCount = ($Body.shortLinks | Where-Object { $_.operation -eq 'add' }).Count
        $removesCount = ($Body.shortLinks | Where-Object { $_.operation -eq 'remove' }).Count
        $projectedTotal = $ExistingLinks.Count + $addsCount - $removesCount
        
        # Check against tier limit (unless unlimited)
        if ($MaxShortLinks -ne -1 -and $projectedTotal -gt $MaxShortLinks) {
            # Track feature usage for blocked attempt
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-FeatureUsageEvent -UserId $UserId -Feature 'shortlink_limit_exceeded' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateShortLinks'
            
            if ($MaxShortLinks -eq 0) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ 
                        error = "Short links are not available on the Free plan. Upgrade to Pro or higher to create short links."
                        upgradeRequired = $true
                        currentTier = $UserTier
                        feature = 'shortLinks'
                    }
                }
            } else {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ 
                        error = "Short link limit exceeded. Your $($TierInfo.tierName) plan allows up to $MaxShortLinks short links. You currently have $($ExistingLinks.Count) short links."
                        currentCount = $ExistingLinks.Count
                        limit = $MaxShortLinks
                    }
                }
            }
        }
        
        # Validate max number in single request
        if ($Body.shortLinks.Count -gt 20) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Maximum 20 short links allowed per request" }
            }
        }

        # Track created short links to return in response
        $CreatedShortLinks = @()

        foreach ($ShortLink in $Body.shortLinks) {
            $op = ($ShortLink.operation ?? '').ToLower()
            
            switch ($op) {
                'add' {
                    # Validate required fields
                    if (-not $ShortLink.targetUrl) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Target URL is required for add operation" }
                        }
                    }
                    
                    # Validate target URL
                    $UrlCheck = Test-InputLength -Value $ShortLink.targetUrl -MaxLength 2048 -FieldName "Target URL"
                    if (-not $UrlCheck.Valid) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = $UrlCheck.Message }
                        }
                    }
                    if (-not (Test-UrlFormat -Url $ShortLink.targetUrl)) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Target URL must be a valid http or https URL" }
                        }
                    }
                    
                    # Validate title if provided
                    if ($ShortLink.title) {
                        $TitleCheck = Test-InputLength -Value $ShortLink.title -MaxLength 100 -FieldName "Title"
                        if (-not $TitleCheck.Valid) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = $TitleCheck.Message }
                            }
                        }
                    }
                    
                    # Generate unique slug automatically
                    try {
                        $GeneratedSlug = New-ShortLinkSlug
                    } catch {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::InternalServerError
                            Body = @{ error = "Failed to generate unique short link. Please try again." }
                        }
                    }
                    
                    $NewLink = @{
                        PartitionKey = $UserId
                        RowKey = $GeneratedSlug
                        TargetUrl = $ShortLink.targetUrl
                        Username = $User.Username
                        Title = if ($ShortLink.title) { $ShortLink.title } else { '' }
                        Active = if ($null -ne $ShortLink.active) { [bool]$ShortLink.active } else { $true }
                        Clicks = 0
                        CreatedAt = [DateTimeOffset]::UtcNow
                        LastClickedAt = $null
                    }
                    
                    Add-LinkToMeAzDataTableEntity @Table -Entity $NewLink -Force
                    
                    # Track the created short link with its generated slug
                    $CreatedShortLinks += @{
                        slug = $GeneratedSlug
                        targetUrl = $ShortLink.targetUrl
                        title = if ($ShortLink.title) { $ShortLink.title } else { '' }
                    }
                }
                
                'update' {
                    if (-not $ShortLink.slug) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Slug is required for update operation" }
                        }
                    }
                    
                    $SafeSlug = Protect-TableQueryValue -Value $ShortLink.slug.ToLower()
                    # Security: Ensure the link belongs to this user by checking PartitionKey
                    $ExistingLink = $ExistingLinks | Where-Object { $_.RowKey -eq $ShortLink.slug.ToLower() -and $_.PartitionKey -eq $UserId } | Select-Object -First 1
                    
                    if (-not $ExistingLink) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::NotFound
                            Body = @{ error = "Short link not found: $($ShortLink.slug)" }
                        }
                    }
                    
                    # Update target URL if provided
                    if ($ShortLink.targetUrl) {
                        $UrlCheck = Test-InputLength -Value $ShortLink.targetUrl -MaxLength 2048 -FieldName "Target URL"
                        if (-not $UrlCheck.Valid) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = $UrlCheck.Message }
                            }
                        }
                        if (-not (Test-UrlFormat -Url $ShortLink.targetUrl)) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Target URL must be a valid http or https URL" }
                            }
                        }
                        $ExistingLink.TargetUrl = $ShortLink.targetUrl
                    }
                    
                    # Update title if provided
                    if ($ShortLink.PSObject.Properties.Match('title').Count -gt 0) {
                        if ($ShortLink.title) {
                            $TitleCheck = Test-InputLength -Value $ShortLink.title -MaxLength 100 -FieldName "Title"
                            if (-not $TitleCheck.Valid) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = $TitleCheck.Message }
                                }
                            }
                        }
                        $ExistingLink.Title = $ShortLink.title
                    }
                    
                    # Update active status if provided
                    if ($ShortLink.PSObject.Properties.Match('active').Count -gt 0) {
                        $ExistingLink.Active = [bool]$ShortLink.active
                    }
                    
                    Add-LinkToMeAzDataTableEntity @Table -Entity $ExistingLink -Force
                }
                
                'remove' {
                    if (-not $ShortLink.slug) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Slug is required for remove operation" }
                        }
                    }
                    
                    # Security: Ensure the link belongs to this user by checking PartitionKey
                    $ExistingLink = $ExistingLinks | Where-Object { $_.RowKey -eq $ShortLink.slug.ToLower() -and $_.PartitionKey -eq $UserId } | Select-Object -First 1
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

        $Results = @{ 
            success = $true
            created = $CreatedShortLinks
        }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        Write-Error "Update short links error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update short links"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
