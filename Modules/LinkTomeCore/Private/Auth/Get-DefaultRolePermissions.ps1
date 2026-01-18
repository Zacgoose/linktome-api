function Get-DefaultRolePermissions {
    <#
    NOTE: This function now supports user, user_manager, and sub_account_user roles for the simplified user management system.
    #>
    <#
    .SYNOPSIS
        Get default permissions for a role
    .DESCRIPTION
        Returns the default permissions assigned to each role type
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('user', 'user_manager', 'agency_admin_user', 'sub_account_user', 'site_super_admin')]
        [string]$Role
    )
    
    $RolePermissions = @{
        'user' = @(
            'read:dashboard',
            'write:2fauth',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:pages',
            'write:pages',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:users',
            'manage:users',
            'invite:user_manager',
            'list:user_manager',
            'remove:user_manager',
            'respond:user_manager',
            'read:apiauth',
            'create:apiauth',
            'update:apiauth',
            'delete:apiauth',
            'write:password',
            'write:email',
            'write:phone',
            'read:subscription',
            'write:subscription',
            'read:usersettings',
            'read:shortlinks',
            'write:shortlinks'
        )
        'user_manager' = @(
            'read:dashboard',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:pages',
            'write:pages',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:shortlinks',
            'write:shortlinks'
        )
        'agency_admin_user' = @(
            'read:dashboard',
            'write:2fauth',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:pages',
            'write:pages',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:users',
            'manage:users',
            'invite:user_manager',
            'list:user_manager',
            'remove:user_manager',
            'respond:user_manager',
            'read:apiauth',
            'create:apiauth',
            'update:apiauth',
            'delete:apiauth',
            'write:password',
            'write:email',
            'write:phone',
            'read:subscription',
            'write:subscription',
            'read:usersettings',
            'read:shortlinks',
            'write:shortlinks',
            'manage:subaccounts'
        )
        'sub_account_user' = @(
            'read:dashboard',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:pages',
            'write:pages',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:shortlinks',
            'write:shortlinks'
        )
        'site_super_admin' = @(
            # Full system access for site operators
            'read:dashboard',
            'write:2fauth',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:pages',
            'write:pages',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:users',
            'manage:users',
            'invite:user_manager',
            'list:user_manager',
            'remove:user_manager',
            'respond:user_manager',
            'read:apiauth',
            'create:apiauth',
            'update:apiauth',
            'delete:apiauth',
            'write:password',
            'write:email',
            'write:phone',
            'read:subscription',
            'write:subscription',
            'read:usersettings',
            'read:shortlinks',
            'write:shortlinks',
            'manage:subaccounts',
            # Site admin permissions
            'read:siteadmin',
            'write:siteadmin'
        )
    }
    
    return $RolePermissions[$Role]
}
