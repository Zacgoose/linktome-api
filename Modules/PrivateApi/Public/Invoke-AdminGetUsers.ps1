function Invoke-AdminGetUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:users
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        $entities = Get-LinkToMeAzDataTableEntity @Table

        # Return all users
        $Users = $entities | ForEach-Object {
            [PSCustomObject]@{
                UserId = $_.RowKey
                username = $_.Username
                email = $_.PartitionKey
                displayName = $_.DisplayName
                role = $_.Roles
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Results = @{ users = $Users }
    } catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get users"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
