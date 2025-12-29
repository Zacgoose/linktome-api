function Invoke-PublicTrackLinkClick {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body

    # Validate required fields
    if (-not $Body.username) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Username is required" }
        }
    }

    if (-not $Body.linkId) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Link ID is required" }
        }
    }

    # Validate username format
    if (-not (Test-UsernameFormat -Username $Body.username)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid username format" }
        }
    }

    try {
        # Get user to verify they exist and get their UserId
        $Table = Get-LinkToMeTable -TableName 'Users'
        $SafeUsername = Protect-TableQueryValue -Value $Body.username.ToLower()
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "Username eq '$SafeUsername'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }

        # Get link details to verify it exists and belongs to this user
        $LinksTable = Get-LinkToMeTable -TableName 'Links'
        $SafeLinkId = Protect-TableQueryValue -Value $Body.linkId
        $Link = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$($User.RowKey)' and RowKey eq '$SafeLinkId'" | Select-Object -First 1
        
        if (-not $Link) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Link not found" }
            }
        }

        # Track link click analytics
        $ClientIP = Get-ClientIPAddress -Request $Request
        $UserAgent = $Request.Headers.'User-Agent'
        $Referrer = $Request.Headers.Referer
        
        Write-AnalyticsEvent `
            -EventType 'LinkClick' `
            -UserId $User.RowKey `
            -Username $User.Username `
            -IpAddress $ClientIP `
            -UserAgent $UserAgent `
            -Referrer $Referrer `
            -LinkId $Link.RowKey `
            -LinkTitle $Link.Title `
            -LinkUrl $Link.Url
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Track link click error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to track link click"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = @{}
    }
}
