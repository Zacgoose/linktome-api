function Get-UserAuthContext {
    <#
    .SYNOPSIS
        Get complete authentication context for a user including roles, permissions, and memberships
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User
    )
    
    # Parse and validate user role
    $AllowedRoles = @('user', 'company_admin', 'company_owner', 'user_manager')
    $ActualUserRole = $null
    $RolesArr = @()
    
    if ($User.Roles) {
        if ($User.Roles -is [string] -and $User.Roles.StartsWith('[')) {
            $parsed = $User.Roles | ConvertFrom-Json
            if ($parsed -is [string]) {
                $RolesArr = @($parsed)
            } else {
                $RolesArr = $parsed
            }
        } elseif ($User.Roles -is [array]) {
            $RolesArr = $User.Roles
        } elseif ($User.Roles -is [string]) {
            $RolesArr = @($User.Roles)
        }
    }
    
    if ($RolesArr.Count -ge 1) {
        $CandidateRole = $RolesArr[0]
        if ($AllowedRoles -contains $CandidateRole) {
            $ActualUserRole = $CandidateRole
        } else {
            throw "Invalid user role in database: $CandidateRole"
        }
    } else {
        throw "No valid user role found for user."
    }
    
    $Roles = @($ActualUserRole)
    $Permissions = Get-DefaultRolePermissions -Role $ActualUserRole
    
    # Lookup company memberships
    $CompanyMemberships = @()
    $CompanyUsersTable = Get-LinkToMeTable -TableName 'CompanyUsers'
    $CompanyUserEntities = Get-LinkToMeAzDataTableEntity @CompanyUsersTable -Filter "RowKey eq '$($User.RowKey)'"
    
    foreach ($cu in $CompanyUserEntities) {
        $companyRole = $cu.Role
        $companyPermissions = @()
        if ($companyRole) {
            $companyPermissions = Get-DefaultRolePermissions -Role $companyRole
        }
        # Ensure permissions is always an array
        if ($companyPermissions -is [string]) {
            $companyPermissions = @($companyPermissions)
        }
        $CompanyMemberships += @{
            companyId = $cu.PartitionKey
            role = $companyRole
            permissions = $companyPermissions
        }
    }
    
    # Build userManagements array
    $UserManagements = @()
    if ($User.HasUserManagers -or $User.IsUserManager) {
        $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        
        if ($User.IsUserManager) {
            $managees = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$($User.RowKey)' and State eq 'accepted'"
            foreach ($um in $managees) {
                $manageePermissions = Get-DefaultRolePermissions -Role $um.Role
                $user = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$($um.RowKey)'" | Select-Object -First 1
                $UserManagements += @{
                    UserId = $um.RowKey
                    role = $um.Role
                    state = $um.State
                    direction = 'manager'
                    permissions = $manageePermissions
                    DisplayName = $user.DisplayName
                    Email = $user.PartitionKey
                }
            }
        }
    }
    
    return @{
        UserId = $User.RowKey
        Email = $User.PartitionKey
        Username = $User.Username
        UserRole = $ActualUserRole
        Roles = $Roles
        Permissions = $Permissions
        CompanyMemberships = $CompanyMemberships
        UserManagements = $UserManagements
    }
}