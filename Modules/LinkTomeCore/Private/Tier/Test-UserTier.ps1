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
        [ValidateSet('free', 'premium', 'enterprise')]
        [string]$RequiredTier
    )
    
    # Define tier hierarchy (higher number = higher tier)
    $TierHierarchy = @{
        'free' = 1
        'premium' = 2
        'enterprise' = 3
    }
    
    # Get user's subscription tier (default to 'free' if not set)
    $UserTier = if ($User.SubscriptionTier) { 
        $User.SubscriptionTier 
    } else { 
        'free' 
    }
    
    # Validate tier exists
    if (-not $TierHierarchy.ContainsKey($UserTier)) {
        Write-Warning "Invalid user tier: $UserTier. Defaulting to 'free'"
        $UserTier = 'free'
    }
    
    # Check subscription status (if user has a paid tier)
    if ($UserTier -ne 'free') {
        $SubscriptionStatus = if ($User.SubscriptionStatus) { 
            $User.SubscriptionStatus 
        } else { 
            'expired' 
        }
        
        # Check if subscription is active
        if ($SubscriptionStatus -ne 'active' -and $SubscriptionStatus -ne 'trial') {
            # Expired subscription - treat as free tier
            $UserTier = 'free'
        }
        
        # Check expiration date if present
        if ($User.SubscriptionExpiresAt) {
            try {
                $ExpiresAt = [DateTimeOffset]$User.SubscriptionExpiresAt
                if ($ExpiresAt -lt [DateTimeOffset]::UtcNow) {
                    # Subscription expired - treat as free tier
                    $UserTier = 'free'
                }
            } catch {
                Write-Warning "Failed to parse SubscriptionExpiresAt: $($_.Exception.Message)"
            }
        }
    }
    
    # Compare tier levels
    $UserTierLevel = $TierHierarchy[$UserTier]
    $RequiredTierLevel = $TierHierarchy[$RequiredTier]
    
    return $UserTierLevel -ge $RequiredTierLevel
}
