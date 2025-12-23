function Invoke-AdminGetProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:profile
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize userId for query
        $SafeUserId = Protect-TableQueryValue -Value $User.UserId
        $filter = "RowKey eq '$SafeUserId'"
        $entities = Get-LinkToMeAzDataTableEntity @Table -Filter $filter
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
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get profile"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}