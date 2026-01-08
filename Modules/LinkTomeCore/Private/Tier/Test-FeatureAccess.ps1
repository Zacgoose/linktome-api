function Test-FeatureAccess {
    <#
    .SYNOPSIS
        Check if user has access to a specific feature
    .DESCRIPTION
        Validates that a user's subscription tier includes access to the requested feature
    .PARAMETER User
        User object from database
    .PARAMETER Feature
        Feature identifier to check access for
    .EXAMPLE
        Test-FeatureAccess -User $User -Feature 'advanced_analytics'
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,
        
        [Parameter(Mandatory)]
        [string]$Feature
    )
    
    # Get subscription info using centralized helper
    $Subscription = Get-UserSubscription -User $User
    
    # Use effective tier which accounts for expiration and cancellation
    $UserTier = $Subscription.EffectiveTier
    
    # Get features for user's tier
    $TierFeatures = Get-TierFeatures -Tier $UserTier
    
    # Check if feature is included
    $HasAccess = $TierFeatures.features -contains $Feature
    
    return $HasAccess
}
