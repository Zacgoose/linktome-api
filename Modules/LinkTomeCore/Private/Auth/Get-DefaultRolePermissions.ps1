function Get-DefaultRolePermissions {
    <#
    NOTE: Only 'user' permissions should be used for Users table/global context.
    'company_admin' and 'company_owner' permissions are only for company context (CompanyUsers table).
    #>
    <#
    .SYNOPSIS
        Get default permissions for a role
    .DESCRIPTION
        Returns the default permissions assigned to each role type
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('user', 'company_admin', 'company_owner')]
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
        'company_admin' = @(
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
            'read:company_members',
            'manage:company_members'
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
            'read:users',
            'manage:users',
            'read:company',
            'write:company',
            'read:company_members',
            'manage:company_members',
            'manage:billing',
            'manage:company_settings',
            'assign:company_admin',
            'revoke:company_admin',
            'assign:company_owner',
            'revoke:company_owner'
        )
    }
    
    return $RolePermissions[$Role]
}
