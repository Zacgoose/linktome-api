function Invoke-AdminGetProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        User.Profile.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        $filter = "RowKey eq '$($User.UserId)'"
        $entities = Get-AzDataTableEntity @Table -Filter $filter
        $UserData = $entities | Select-Object -First 1

        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }

        $Results = @{
            userId = $UserData.RowKey
            username = $UserData.Username
            email = $UserData.PartitionKey
            displayName = $UserData.DisplayName
            bio = $UserData.Bio
            avatar = $UserData.Avatar
        }
        $StatusCode = [HttpStatusCode]::OK

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