function Invoke-PublicL {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        public
    .DESCRIPTION
        Public endpoint that redirects a short link slug to its full URL.
        Tracks analytics for the redirect.
        URL: GET /public/l/{slug}
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Extract slug from the URL path
    # The router will pass the slug as a query parameter
    $Slug = $Request.Query.slug

    if (-not $Slug) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Slug is required" }
        }
    }

    # Validate slug format
    if (-not (Test-SlugFormat -Slug $Slug)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid slug format" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'ShortLinks'
        
        # Sanitize slug for query
        $SafeSlug = Protect-TableQueryValue -Value $Slug.ToLower()
        
        # Find the short link by slug (RowKey is the slug)
        $ShortLink = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeSlug'" | Select-Object -First 1
        
        if (-not $ShortLink) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Short link not found" }
            }
        }
        
        # Check if link is active
        if (-not [bool]$ShortLink.Active) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Gone
                Body = @{ error = "This short link is no longer active" }
            }
        }
        
        # Track analytics for the redirect
        $ClientIP = Get-ClientIPAddress -Request $Request
        $UserAgent = $Request.Headers.'User-Agent'
        $Referrer = $Request.Headers.Referer
        
        Write-AnalyticsEvent -EventType 'ShortLinkRedirect' -UserId $ShortLink.PartitionKey `
            -Username $ShortLink.Username -IpAddress $ClientIP -UserAgent $UserAgent `
            -Referrer $Referrer -LinkId $ShortLink.RowKey -LinkUrl $ShortLink.TargetUrl
        
        # Increment click count
        try {
            $ShortLink.Clicks = if ($ShortLink.Clicks) { [int]$ShortLink.Clicks + 1 } else { 1 }
            if (-not $ShortLink.PSObject.Properties['LastClickedAt']) {
                $ShortLink | Add-Member -NotePropertyName LastClickedAt -NotePropertyValue ([DateTimeOffset]::UtcNow) -Force
            } else {
                $ShortLink.LastClickedAt = [DateTimeOffset]::UtcNow
            }
            Add-LinkToMeAzDataTableEntity @Table -Entity $ShortLink -OperationType 'UpsertMerge' | Out-Null
        } catch {
            Write-Warning "Failed to update click count: $($_.Exception.Message)"
        }
        
        # Return JSON response for CSR redirect
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Headers = @{
                'Cache-Control' = 'no-cache, no-store, must-revalidate'
            }
            Body = @{
                redirectTo = $ShortLink.TargetUrl
            }
        }
        
    } catch {
        Write-Error "Short link redirect error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to redirect short link"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = $Results
        }
    }
}
