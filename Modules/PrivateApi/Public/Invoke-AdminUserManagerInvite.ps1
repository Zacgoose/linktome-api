function Invoke-AdminUserManagerInvite {
    <#
    .SYNOPSIS
        Invite a user to manage your account (user-to-user management).
    .DESCRIPTION
        Creates a user management invite from the current user to another user, specifying a role. Stores the invite in the UserManagers table with state 'pending'.
    .EXAMPLE
        Invoke-AdminUserManagerInvite -ToUserId "abc123" -Role "Manager"
    .ROLE
        invite:user_manager
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata
    )
    try {
        # Get current user from request context
        $FromUserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
        Write-Information "FromUserId: $FromUserId"
        if (-not $FromUserId) {
            throw 'Authenticated user not found in request.'
        }

        $ToUserEmail = $Request.Body.email
        $Role = $Request.Body.role
        if (-not $ToUserEmail) {
            throw 'Missing email in request body.'
        }
        if (-not $Role) {
            throw 'Missing role in request body.'
        }

        # Lookup ToUserId by email (case-insensitive)
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeEmail = Protect-TableQueryValue -Value $ToUserEmail.ToLower()
        $ToUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        if (-not $ToUser) {
            throw 'No user found with that email address.'
        }
        $ToUserId = $ToUser.RowKey

        # Prevent self-invite
        if ($FromUserId -eq $ToUserId) {
            throw 'You cannot invite yourself to manage your own account.'
        }

        $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'

        # Check for existing invite or relationship
        $existing = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$ToUserId' and RowKey eq '$FromUserId'"
        if ($existing.Count -gt 0) {
            $state = $existing[0].State
            if ($state -eq 'pending') {
                throw 'An invite is already pending for this user.'
            }
            elseif ($state -eq 'accepted') {
                throw 'This user is already your manager.'
            }
            elseif ($state -eq 'rejected') {
                # Allow re-invite by updating state below
            }
        }

        $now = [DateTime]::UtcNow.ToString('o')
        $entity = @{
            PartitionKey = $ToUserId
            RowKey       = $FromUserId
            Role         = $Role
            State        = 'pending'
            Created      = $now
            Updated      = $now
        }

        Add-LinkToMeAzDataTableEntity @UserManagersTable -Entity $entity -OperationType 'UpsertReplace'

        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to send invite"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{}
    }
}
