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

    # Validate username format
    if (-not (Test-UsernameFormat -Username $Username)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid username format" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize username for query
        $SafeUsername = Protect-TableQueryValue -Value $Username.ToLower()
        $User = Get-AzDataTableEntity @Table -Filter "Username eq '$SafeUsername'" | Select-Object -First 1
        
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
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get profile"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}