
# UserManagers Table (Azure Table Storage)
# PartitionKey: ToUserId (the user being managed)
# RowKey: FromUserId (the user who is the manager)
# Columns:
#   - Role: string (e.g., 'user_delegate', 'user_admin')
#   - State: string ('pending', 'accepted', 'rejected')
#   - Created: datetime
#   - Updated: datetime
# (Each property is its own column. Permissions are derived from role using Get-DefaultRolePermissions.)

# Example PowerShell function to get managers for a user
function Get-UserManagers {
    param(
        [string]$UserId
    )
    $Table = Get-LinkToMeTable -TableName 'UserManagers'
    $entities = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$UserId' and State eq 'accepted'"
    return $entities
}

# Example PowerShell function to get users managed by a user
function Get-UsersManagedBy {
    param(
        [string]$ManagerUserId
    )
    $Table = Get-LinkToMeTable -TableName 'UserManagers'
    $entities = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$ManagerUserId' and State eq 'accepted'"
    return $entities
}


# Users Table: Add columns
#   - HasUserManagers: bool (true if user is managed by another user)
#   - IsUserManager: bool (true if user manages at least one other user)
# (This allows both parties to see the relationship efficiently.)

# Backend logic:
# - When checking for user-to-user management, first check HasUserManagers (or ManagedByUserId) on the Users entity.
# - Only query UserManagers table if flag is set.
# - When a user invites another, create a UserManagers entity with State='pending'.
# - When accepted, set State='accepted' and update HasUserManagers on the managed user.
