function Invoke-AdminGetProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:profile
    .DESCRIPTION
        DEPRECATED: This endpoint is deprecated. Display name and bio should be managed through UpdateAppearance.
        Kept for backward compatibility with Dashboard.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize UserId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
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
            UserId = $UserData.RowKey
            username = $UserData.Username
            email = $UserData.PartitionKey
            displayName = $UserData.DisplayName
            bio = $UserData.Bio
            avatar = $UserData.Avatar
            phoneNumber = $UserData.PhoneNumber
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