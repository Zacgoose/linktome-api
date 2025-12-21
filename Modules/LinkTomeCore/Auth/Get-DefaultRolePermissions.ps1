function Get-DefaultRolePermissions {
    <#
    .SYNOPSIS
        Get default permissions for a role
    .DESCRIPTION
        Returns the default permissions assigned to each role type
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('user', 'admin', 'company_owner')]
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
            'read:analytics'
        )
        'admin' = @(
            'read:dashboard',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:users',
            'write:users',
            'manage:users'
        )
        'company_owner' = @(
            'read:dashboard',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:company',
            'write:company',
            'read:company_members',
            'manage:company_members'
        )
    }
    
    return $RolePermissions[$Role]
}
