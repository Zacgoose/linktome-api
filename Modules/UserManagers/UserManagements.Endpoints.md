# User Management Invite API Endpoints (PowerShell outline)

# 1. Invite a user to manage your account
function Invoke-UserInviteManager {
    param($Request, $TriggerMetadata)
    # $Request.Body: { toUserEmail, role }
    # Validate and lookup toUserId by email
    # Create UserManagers entity: PartitionKey=toUserId, RowKey=fromUserId, Role, State='pending', Created
    # Return success or error
}

# 2. Accept/Reject an invite
function Invoke-UserRespondToInvite {
    param($Request, $TriggerMetadata)
    # $Request.Body: { fromUserId, action: 'accept'|'reject' }
    # Lookup UserManagers entity by PartitionKey=yourUserId, RowKey=fromUserId
    # Update State to 'accepted' or 'rejected', set Updated
    # Update HasUserManagers/IsUserManager flags on Users table as needed
    # Return success or error
}

# 3. List managers/managees for a user
function Invoke-UserListManagers {
    param($Request, $TriggerMetadata)
    # $Request.Query.userId (optional, default to current user)
    # Query UserManagers table for PartitionKey=userId (managers) and RowKey=userId (managees)
    # Return both lists
}

# 4. (Optional) Remove a manager relationship
function Invoke-UserRemoveManager {
    param($Request, $TriggerMetadata)
    # $Request.Body: { otherUserId }
    # Delete UserManagers entity for either direction
    # Update HasUserManagers/IsUserManager flags as needed
    # Return success or error
}

# Table: UserManagers (PartitionKey=toUserId, RowKey=fromUserId)
# Table: Users (HasUserManagers, IsUserManager)

# These endpoints should be added to the PublicApi module and exposed as HTTP triggers.
