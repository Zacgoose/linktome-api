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

        # User manager endpoints
        'admin/UserManagerList' = @('list:user_manager')
        'admin/UserManagerInvite' = @('invite:user_manager')
        'admin/UserManagerRemove' = @('remove:user_manager')
        'admin/UserManagerRespond' = @('respond:user_manager')

        # API Authentication endpoints
        'admin/apiKeysList' = @('read:apiauth')
        'admin/apiKeysCreate' = @('create:apiauth')
        'admin/apiKeysUpdate' = @('update:apiauth')
        'admin/apiKeysDelete' = @('delete:apiauth')
    }
    
    return $EndpointPermissions[$Endpoint]
}
