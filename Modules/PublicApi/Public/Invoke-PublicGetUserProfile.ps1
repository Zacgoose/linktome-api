function Invoke-PublicGetUserProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public.Profile.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Username = $Request.Query.username

    if (-not $Username) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Username is required" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        $User = Get-AzDataTableEntity @Table -Filter "Username eq '$($Username.ToLower())'" | Select-Object -First 1
        
        if (-not $User) {
            $StatusCode = [HttpStatusCode]::NotFound
            $Results = @{ error = "Profile not found" }
        } else {
            $LinksTable = Get-LinkToMeTable -TableName 'Links'
            $Links = Get-AzDataTableEntity @LinksTable -Filter "PartitionKey eq '$($User.RowKey)' and Active eq true"
            
            $Results = @{
                username = $User.Username
                displayName = $User.DisplayName
                bio = $User.Bio
                avatar = $User.Avatar
                links = @($Links | ForEach-Object {
                    @{
                        id = $_.RowKey
                        title = $_.Title
                        url = $_.Url
                        order = [int]$_.Order
                    }
                } | Sort-Object order)
            }
            $StatusCode = [HttpStatusCode]::OK
        }
        
    } catch {
        Write-Error "Get profile error: $($_.Exception.Message)"
        $Results = @{ error = "Failed to get profile" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}