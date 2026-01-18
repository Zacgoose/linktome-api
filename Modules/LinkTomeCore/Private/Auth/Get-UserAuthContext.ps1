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
    $AllowedRoles = @('user', 'user_manager', 'agency_admin_user', 'sub_account_user', 'site_super_admin')
    $ActualUserRole = $null
    $RolesArr = @()
    
    # Check if user has Role property (for sub-accounts)
    if ($User.PSObject.Properties['Role'] -and $User.Role) {
        $ActualUserRole = $User.Role
        if (-not ($AllowedRoles -contains $ActualUserRole)) {
            throw "Invalid user role in database: $ActualUserRole"
        }
    }
    # Otherwise check Roles array (legacy behavior)
    elseif ($User.Roles) {
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
        
        if ($RolesArr.Count -ge 1) {
            $CandidateRole = $RolesArr[0]
            if ($AllowedRoles -contains $CandidateRole) {
                $ActualUserRole = $CandidateRole
            } else {
                throw "Invalid user role in database: $CandidateRole"
            }
        }
    }
    
    if (-not $ActualUserRole) {
        throw "No valid user role found for user."
    }
    
    $Roles = @($ActualUserRole)
    $Permissions = Get-DefaultRolePermissions -Role $ActualUserRole
    
    # Build userManagements array (not applicable for sub-accounts)
    $UserManagements = @()
    if ($ActualUserRole -ne 'sub_account_user') {
        if ($User.HasUserManagers -or $User.IsUserManager) {
            $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'
            $UsersTable = Get-LinkToMeTable -TableName 'Users'
            
            if ($User.IsUserManager) {
                $managees = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$($User.RowKey)' and State eq 'accepted'"
                foreach ($um in $managees) {
                    $manageePermissions = Get-DefaultRolePermissions -Role $um.Role
                    $UserManager = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$($um.RowKey)'" | Select-Object -First 1
                    $manageeSubscription = Get-UserSubscription -User $UserManager
                    $UserManagements += @{
                        UserId = $um.RowKey
                        role = $um.Role
                        state = $um.State
                        direction = 'manager'
                        permissions = $manageePermissions
                        DisplayName = $UserManager.DisplayName
                        Email = $UserManager.PartitionKey
                        tier = $manageeSubscription.EffectiveTier
                    }
                }
            }
        }
    }
    
    # Build subAccounts array (only for agency_admin_user role)
    $SubAccounts = @()
    if ($ActualUserRole -eq 'agency_admin_user') {
        try {
            $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
            $UsersTable = Get-LinkToMeTable -TableName 'Users'
            
            # Get all sub-accounts for this parent (PartitionKey = ParentUserId)
            $SafeUserId = Protect-TableQueryValue -Value $User.RowKey
            $SubAccountRelationships = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeUserId'" -ErrorAction SilentlyContinue
            
            foreach ($relationship in $SubAccountRelationships) {
                $SubAccountId = $relationship.RowKey
                $SafeSubId = Protect-TableQueryValue -Value $SubAccountId
                
                # Get sub-account user details
                $SubAccountUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeSubId'" -ErrorAction SilentlyContinue | Select-Object -First 1
                
                if ($SubAccountUser) {
                    $SubAccountPermissions = Get-DefaultRolePermissions -Role 'sub_account_user'
                    $SubAccounts += @{
                        UserId = $SubAccountUser.RowKey
                        username = $SubAccountUser.Username
                        displayName = $SubAccountUser.DisplayName
                        role = 'sub_account_user'
                        permissions = $SubAccountPermissions
                        type = if ($relationship.PSObject.Properties['Type'] -and $relationship.Type) { $relationship.Type } else { 'client' }
                        status = if ($relationship.PSObject.Properties['Status'] -and $relationship.Status) { $relationship.Status } else { 'active' }
                    }
                }
            }
        } catch {
            Write-Warning "Failed to load sub-accounts: $($_.Exception.Message)"
            # Continue without sub-accounts - not critical for auth
        }
    }
    
    # Get user's subscription information using centralized helper
    $Subscription = Get-UserSubscription -User $User
    
    # Get 2FA status
    $TwoFactorEmailEnabled = $User.TwoFactorEmailEnabled -eq $true
    $TwoFactorTotpEnabled = $User.TwoFactorTotpEnabled -eq $true
    $TwoFactorEnabled = $TwoFactorEmailEnabled -or $TwoFactorTotpEnabled
    
    # Get sub-account flags (optional, for frontend display)
    $IsSubAccount = if ($User.PSObject.Properties['IsSubAccount'] -and $User.IsSubAccount) { $true } else { $false }
    $AuthDisabled = if ($User.PSObject.Properties['AuthDisabled'] -and $User.AuthDisabled) { $true } else { $false }
    
    return @{
        UserId = $User.RowKey
        Email = $User.PartitionKey
        Username = $User.Username
        UserRole = $ActualUserRole
        Roles = $Roles
        Permissions = $Permissions
        UserManagements = $UserManagements
        SubAccounts = $SubAccounts
        Tier = $Subscription.EffectiveTier
        TwoFactorEnabled = $TwoFactorEnabled
        TwoFactorEmailEnabled = $TwoFactorEmailEnabled
        TwoFactorTotpEnabled = $TwoFactorTotpEnabled
        IsSubAccount = $IsSubAccount
        AuthDisabled = $AuthDisabled
    }
}