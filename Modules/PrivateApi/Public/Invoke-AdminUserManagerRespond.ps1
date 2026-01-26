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
        $Request,
        $TriggerMetadata
    )
    try {
        $Body = $Request.Body
        $FromUserId = $Body.FromUserId
        $State = $Body.State
        if (-not $FromUserId) { 
            throw 'Missing FromUserId in request body.'
        }
        if (-not $State) { 
            throw 'Missing State in request body.'
        }
        if ($State -notin @('accepted','rejected')) { 
            throw 'State must be "accepted" or "rejected".'
        }

        # Get current user (the one responding to the invite)
        $ToUserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
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

        # If accepted, update HasUserManagers/IsUserManager flags first
        if ($State -eq 'accepted') {
            # Set HasUserManagers on the managed user (FromUserId)
            $managedUserEntities = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$FromUserId'"
            if ($managedUserEntities.Count -gt 0) {
                $managedUser = $managedUserEntities[0]
                $managedUser | Add-Member -NotePropertyName HasUserManagers -NotePropertyValue $true -Force
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $managedUser -OperationType 'UpsertMerge'
            }
            # Set IsUserManager on the manager (ToUserId)
            $managerEntities = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$ToUserId'"
            if ($managerEntities.Count -gt 0) {
                $manager = $managerEntities[0]
                $manager | Add-Member -NotePropertyName IsUserManager -NotePropertyValue $true -Force
                Add-LinkToMeAzDataTableEntity @UsersTable -Entity $manager -OperationType 'UpsertMerge'
            }
        }

        # Now update invite state and timestamp
        $invite.State = $State
        $invite.Updated = [DateTime]::UtcNow.ToString('o')
        Add-LinkToMeAzDataTableEntity @UserManagersTable -Entity $invite -OperationType 'UpsertReplace'

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to respond to invite"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = @{message = "Invite response processed successfully"}
    }
}
