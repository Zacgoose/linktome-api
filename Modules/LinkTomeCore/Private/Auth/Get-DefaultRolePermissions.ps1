function Get-DefaultRolePermissions {
    <#
    NOTE: This function now only supports user and user_manager roles for the simplified user management system.
    #>
    <#
    .SYNOPSIS
        Get default permissions for a role
    .DESCRIPTION
        Returns the default permissions assigned to each role type
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('user', 'user_manager')]
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
            'read:usersettings'
        )
        'user_manager' = @(
            'read:dashboard',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:appearance',
            'write:appearance',
            'read:analytics'
        )
    }
    
    return $RolePermissions[$Role]
}
