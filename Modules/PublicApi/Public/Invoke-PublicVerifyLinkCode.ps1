function Invoke-PublicVerifyLinkCode {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:profile
    .DESCRIPTION
        Verifies an access code for a locked link.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body

    if (-not $Body.linkId) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Link ID is required" }
        }
    }

    if (-not $Body.code) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Code is required" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Links'
        
        # Find the link - we need to search across all users since this is a public endpoint
        # Links are partitioned by UserId, so we need to use RowKey
        $SafeLinkId = Protect-TableQueryValue -Value $Body.linkId
        $Link = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeLinkId'" | Select-Object -First 1
        
        if (-not $Link) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Link not found" }
            }
        }
        
        # Check if link has code lock enabled
        if (-not [bool]$Link.LockEnabled -or $Link.LockType -ne 'code') {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Link is not code-locked" }
            }
        }
        
        # Verify the code (case-sensitive comparison)
        if ($Body.code -ceq $Link.LockCode) {
            $Results = @{
                success = $true
            }
            $StatusCode = [HttpStatusCode]::OK
            
            # Track the unlock event
            $ClientIP = Get-ClientIPAddress -Request $Request
            $UserAgent = $Request.Headers.'User-Agent'
            Write-AnalyticsEvent -EventType 'LinkUnlock' -UserId $Link.PartitionKey -LinkId $Link.RowKey -IpAddress $ClientIP -UserAgent $UserAgent
        } else {
            $Results = @{
                success = $false
                error = "Invalid code"
            }
            $StatusCode = [HttpStatusCode]::Unauthorized
        }
        
    } catch {
        Write-Error "Verify link code error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to verify code"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}