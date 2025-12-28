function Get-DefaultRolePermissions {
    <#
    NOTE: Only 'user' and 'user_manager' permissions should be used for Users table/global context.
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
            'respond:user_manager'
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
