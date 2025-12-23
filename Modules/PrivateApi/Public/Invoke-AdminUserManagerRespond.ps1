function Invoke-AdminUserManagerRespond {
    <#
    .SYNOPSIS
        Accept or reject a user management invite.
    .DESCRIPTION
        Allows the invited user to accept or reject a pending user management invite. Updates the state in the UserManagers table.
    .PARAMETER FromUserId
        The user ID of the user who sent the invite.
    .PARAMETER State
        The new state for the invite ('accepted' or 'rejected').
    .EXAMPLE
        Invoke-AdminUserManagerRespond -FromUserId "abc123" -State "accepted"
    .ROLE
        respond:user_manager
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FromUserId,
        [Parameter(Mandatory)]
        [ValidateSet('accepted','rejected')]
        [string]$State,
        $Request,
        $TriggerMetadata
    )
    try {
        # Get current user (the one responding to the invite)
        $ToUserId = $Request.AuthenticatedUser.UserId
        if (-not $ToUserId) {
            throw 'Authenticated user not found in request.'
        }

        $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'
        $UsersTable = Get-LinkToMeTable -TableName 'Users'

        # Lookup the invite entity
        $entities = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$ToUserId' and RowKey eq '$FromUserId'"
        if ($entities.Count -eq 0) {
            throw 'No invite found from this user.'
        }
        $invite = $entities[0]
        if ($invite.State -ne 'pending') {
            throw "Invite is not pending (current state: $($invite.State))."
        }

        # Update invite state and timestamp
        $invite.State = $State
        $invite.Updated = [DateTime]::UtcNow.ToString('o')
        Add-LinkToMeAzDataTableEntity @UserManagersTable -Entity $invite -OperationType 'UpsertReplace'

        # If accepted, update HasUserManagers/IsUserManager flags
        if ($State -eq 'accepted') {
            # Set HasUserManagers on the managed user (ToUserId)
            $toUserEntities = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$ToUserId'"
            if ($toUserEntities.Count -gt 0) {
                $toUser = $toUserEntities[0]
                $toUser.HasUserManagers = $true
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $toUser -OperationType 'UpsertMerge'
            }
            # Set IsUserManager on the manager (FromUserId)
            $fromUserEntities = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$FromUserId'"
            if ($fromUserEntities.Count -gt 0) {
                $fromUser = $fromUserEntities[0]
                $fromUser.IsUserManager = $true
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $fromUser -OperationType 'UpsertMerge'
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        $Results = @{ success = $true; message = "Invite $State." }
    } catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to respond to invite"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
