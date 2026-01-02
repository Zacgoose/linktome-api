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
    
    # Get user's effective tier
    $UserTier = if ($User.SubscriptionTier) { 
        $User.SubscriptionTier 
    } else { 
        'free' 
    }
    
    # Validate tier exists
    $ValidTiers = @('free', 'premium', 'enterprise')
    if (-not ($ValidTiers -contains $UserTier)) {
        Write-Warning "Invalid user tier: $UserTier. Defaulting to 'free'"
        $UserTier = 'free'
    }
    
    # Check subscription status for paid tiers
    if ($UserTier -ne 'free') {
        $SubscriptionStatus = if ($User.SubscriptionStatus) { 
            $User.SubscriptionStatus 
        } else { 
            'expired' 
        }
        
        # Check if subscription is active
        if ($SubscriptionStatus -ne 'active' -and $SubscriptionStatus -ne 'trial') {
            $UserTier = 'free'
        }
        
        # Check expiration date if present
        if ($User.SubscriptionExpiresAt) {
            try {
                $ExpiresAt = [DateTimeOffset]$User.SubscriptionExpiresAt
                if ($ExpiresAt -lt [DateTimeOffset]::UtcNow) {
                    $UserTier = 'free'
                }
            } catch {
                Write-Warning "Failed to parse SubscriptionExpiresAt: $($_.Exception.Message)"
                $UserTier = 'free'
            }
        }
    }
    
    # Get features for user's tier
    $TierFeatures = Get-TierFeatures -Tier $UserTier
    
    # Check if feature is included
    $HasAccess = $TierFeatures.features -contains $Feature
    
    return $HasAccess
}
