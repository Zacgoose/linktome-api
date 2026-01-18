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

        # User 2fa endpoints
        'admin/2fatokensetup' = @('write:2fauth')
        
        # Links endpoints
        'admin/getLinks' = @('read:links')
        'admin/updateLinks' = @('write:links')
        
        # Page endpoints
        'admin/getPages' = @('read:pages')
        'admin/createPage' = @('write:pages')
        'admin/updatePage' = @('write:pages')
        'admin/deletePage' = @('write:pages')
        
        # Appearance endpoints
        'admin/getAppearance' = @('read:appearance')
        'admin/updateAppearance' = @('write:appearance')
        
        # Analytics endpoints
        'admin/getAnalytics' = @('read:analytics')
        
        # Short link endpoints
        'admin/getShortLinks' = @('read:shortlinks')
        'admin/updateShortLinks' = @('write:shortlinks')
        'admin/getShortLinkAnalytics' = @('read:analytics')

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
        
        # Settings endpoints
        'admin/updatePassword' = @('write:password')
        'admin/updateEmail' = @('write:email')
        'admin/updatePhone' = @('write:phone')
        
        # Subscription endpoints
        'admin/getSubscription' = @('read:subscription')
        'admin/upgradeSubscription' = @('write:subscription')
        'admin/cancelSubscription' = @('write:subscription')
        'admin/purchaseUserPack' = @('write:subscription')

        # Sub-account endpoints
        'admin/getSubAccounts' = @('manage:subaccounts')
        'admin/createSubAccount' = @('manage:subaccounts')
        'admin/deleteSubAccount' = @('manage:subaccounts')
        
        # Site Admin endpoints
        'siteadmin/listtimers' = @('read:siteadmin')
        'siteadmin/runtimer' = @('write:siteadmin')
    }
    
    return $EndpointPermissions[$Endpoint]
}
