function Invoke-AdminGetLinks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:links
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }

    try {
        $Table = Get-LinkToMeTable -TableName 'Links'
        
        # Sanitize UserId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $Links = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'"
        
        $Results = @($Links | ForEach-Object {
            $linkObj = @{
                id = $_.RowKey
                title = $_.Title
                url = $_.Url
                order = [int]$_.Order
                active = [bool]$_.Active
            }
            # Add icon if it exists
            if ($_.Icon) {
                $linkObj.icon = $_.Icon
            }
            $linkObj
        } | Sort-Object order)
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get links error: $($_.Exception.Message)"
        $Results = @{ error = "Failed to get links" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = @{ links = $Results }
    }
}