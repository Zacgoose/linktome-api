function Invoke-AdminUserManagerRemove {
    <#
    .SYNOPSIS
        Remove a user management relationship.
    .DESCRIPTION
        Removes a user management relationship or invite between two users.
    .PARAMETER OtherUserId
        The user ID of the other user in the relationship (manager or managee).
    .EXAMPLE
        Invoke-AdminUserManagerRemove -OtherUserId "abc123"
    .ROLE
        remove:user_manager
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OtherUserId,
        $Request,
        $TriggerMetadata
    )
    try {
        $UserId = $Request.AuthenticatedUser.UserId
        if (-not $UserId) {
            throw 'Authenticated user not found in request.'
        }

        $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'
        $UsersTable = Get-LinkToMeTable -TableName 'Users'

        # Try both directions: (UserId, OtherUserId) and (OtherUserId, UserId)
        $entities = @()
        $entities += Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$UserId' and RowKey eq '$OtherUserId'"
        $entities += Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$OtherUserId' and RowKey eq '$UserId'"

        if ($entities.Count -eq 0) {
            throw 'No user management relationship or invite found.'
        }

        foreach ($entity in $entities) {
            Remove-AzDataTableEntity -Context $UserManagersTable.Context -PartitionKey $entity.PartitionKey -RowKey $entity.RowKey
        }

        # Update HasUserManagers/IsUserManager flags if needed
        # For both users, check if any remaining accepted relationships exist
        foreach ($uid in @($UserId, $OtherUserId)) {
            $asManaged = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$uid' and State eq 'accepted'"
            $asManager = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "RowKey eq '$uid' and State eq 'accepted'"
            $userEntities = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$uid'"
            if ($userEntities.Count -gt 0) {
                $user = $userEntities[0]
                $user.HasUserManagers = ($asManaged.Count -gt 0)
                $user.IsUserManager = ($asManager.Count -gt 0)
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $user -OperationType 'UpsertMerge'
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        $Results = @{ success = $true; message = 'User management relationship removed.' }
    } catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to remove user management relationship"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
