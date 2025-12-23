# User-to-User Management Context for JWT

# Add this logic to both Invoke-PublicLogin.ps1 and Invoke-PublicRefreshToken.ps1 after companyMemberships logic

# Only run this if $User.HasUserManagers -or $User.IsUserManager
$UserManagements = @()
if ($User.HasUserManagers -or $User.IsUserManager) {
    $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'
    # As manager: users I manage
    if ($User.IsUserManager) {
        $managedEntities = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "RowKey eq '$($User.RowKey)' and State eq 'accepted'"
        foreach ($um in $managedEntities) {
            $UserManagements += @{
                userId = $um.PartitionKey
                role = $um.Role
                state = $um.State
                direction = 'manager' # I manage this user
            }
        }
    }
    # As managed: users who manage me
    if ($User.HasUserManagers) {
        $managerEntities = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$($User.RowKey)' and State eq 'accepted'"
        foreach ($um in $managerEntities) {
            $UserManagements += @{
                userId = $um.RowKey
                role = $um.Role
                state = $um.State
                direction = 'managed' # This user manages me
            }
        }
    }
}

# Add -UserManagements $UserManagements to New-LinkToMeJWT and to the user object in the response
# Example:
# $Token = New-LinkToMeJWT ... -UserManagements $UserManagements
# $Results = @{ user = @{ ...; userManagements = $UserManagements }; ... }
