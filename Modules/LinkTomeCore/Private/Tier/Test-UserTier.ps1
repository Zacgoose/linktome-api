function Test-UserTier {
    <#
    .SYNOPSIS
        Check if user has required subscription tier
    .DESCRIPTION
        Validates that a user has at least the minimum required tier and that their subscription is active
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,
        
        [Parameter(Mandatory)]
        [ValidateSet('free', 'pro', 'premium', 'enterprise')]
        [string]$RequiredTier
    )
    
    # Define tier hierarchy (higher number = higher tier)
    $TierHierarchy = @{
        'free' = 1
        'pro' = 2
        'premium' = 3
        'enterprise' = 4
    }
    
    # Get subscription info using centralized helper
    $Subscription = Get-UserSubscription -User $User
    
    # Use effective tier which accounts for expiration and cancellation
    $UserTier = $Subscription.EffectiveTier
    
    # Compare tier levels
    $UserTierLevel = $TierHierarchy[$UserTier]
    $RequiredTierLevel = $TierHierarchy[$RequiredTier]
    
    return $UserTierLevel -ge $RequiredTierLevel
}
