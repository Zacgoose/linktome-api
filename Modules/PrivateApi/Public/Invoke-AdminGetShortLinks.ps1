function Invoke-AdminGetShortLinks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:shortlinks
    .DESCRIPTION
        Returns the user's short links with usage statistics.
        Supports pagination and sorting.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    
    try {
        $Table = Get-LinkToMeTable -TableName 'ShortLinks'
        
        # Sanitize UserId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        
        # Get all short links for this user
        $ShortLinks = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'"
        
        $LinkResults = @($ShortLinks | ForEach-Object {
            @{
                slug = $_.RowKey
                targetUrl = $_.TargetUrl
                title = $_.Title
                active = [bool]$_.Active
                clicks = if ($null -ne $_.Clicks) { [int]$_.Clicks } else { 0 }
                createdAt = if ($_.CreatedAt) { $_.CreatedAt.ToString('o') } else { $null }
                lastClickedAt = if ($_.LastClickedAt) { $_.LastClickedAt.ToString('o') } else { $null }
            }
        } | Sort-Object { -$_.clicks })
        
        $Results = @{
            shortLinks = $LinkResults
            total = $LinkResults.Count
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get short links error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get short links"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
