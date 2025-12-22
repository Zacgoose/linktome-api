function Invoke-AdminGetLinks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        User.Links.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser

    try {
        $Table = Get-LinkToMeTable -TableName 'Links'
        
        # Sanitize userId for query
        $SafeUserId = Protect-TableQueryValue -Value $User.UserId
        $Links = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeUserId'"
        
        $Results = @($Links | ForEach-Object {
            @{
                id = $_.RowKey
                title = $_.Title
                url = $_.Url
                order = [int]$_.Order
                active = [bool]$_.Active
            }
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