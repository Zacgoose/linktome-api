function Get-EndpointPermissions {
    <#
    .SYNOPSIS
        Get required permissions for an endpoint
    .DESCRIPTION
        Returns the permissions required to access a specific endpoint
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint
    )
    
    # Map endpoints to required permissions
    $EndpointPermissions = @{
        # Profile endpoints
        'admin/getProfile' = @('read:profile')
        'admin/updateProfile' = @('write:profile')
        
        # Links endpoints
        'admin/getLinks' = @('read:links')
        'admin/updateLinks' = @('write:links')
        
        # Appearance endpoints
        'admin/getAppearance' = @('read:appearance')
        'admin/updateAppearance' = @('write:appearance')
        
        # Analytics endpoints
        'admin/getAnalytics' = @('read:analytics')
        'admin/getDashboardStats' = @('read:dashboard')
        
        # User management endpoints (admin only)
        'admin/getUsers' = @('read:users')
        'admin/createUser' = @('write:users')
        'admin/updateUser' = @('write:users')
        'admin/deleteUser' = @('manage:users')
        'admin/assignRole' = @('manage:users')
        'admin/getUserRoles' = @('read:users')
        
        # Company endpoints (company_owner)
        'admin/getCompany' = @('read:company')
        'admin/updateCompany' = @('write:company')
        'admin/getCompanyMembers' = @('read:company_members')
        'admin/addCompanyMember' = @('manage:company_members')
        'admin/removeCompanyMember' = @('manage:company_members')
    }
    
    return $EndpointPermissions[$Endpoint]
}
