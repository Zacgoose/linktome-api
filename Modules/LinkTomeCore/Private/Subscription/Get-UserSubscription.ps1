function Get-UserSubscription {
    <#
    .SYNOPSIS
        Get complete subscription information for a user
    .DESCRIPTION
        Centralizes all subscription data access and provides a consistent subscription object
        with all relevant fields including tier, status, billing info, and access control
    .PARAMETER User
        The user object from the Users table
    .OUTPUTS
        Hashtable with complete subscription information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$User
    )
    
    # Get current timestamp for comparisons
    $Now = (Get-Date).ToUniversalTime()
    
    # Get basic subscription fields with defaults
    $Tier = if ($User.PSObject.Properties['SubscriptionTier'] -and $User.SubscriptionTier) { 
        $User.SubscriptionTier 
    } else { 
        'free' 
    }
    
    $Status = if ($User.PSObject.Properties['SubscriptionStatus'] -and $User.SubscriptionStatus) { 
        $User.SubscriptionStatus 
    } else { 
        'active' 
    }
    
    # Get billing cycle (null for free tier)
    $BillingCycle = if ($User.PSObject.Properties['BillingCycle'] -and $User.BillingCycle) {
        $User.BillingCycle
    } else {
        $null
    }
    
    # Get subscription started date
    $SubscriptionStartedAt = if ($User.PSObject.Properties['SubscriptionStartedAt'] -and $User.SubscriptionStartedAt) {
        $User.SubscriptionStartedAt
    } elseif ($User.Timestamp) {
        # Fallback to account creation timestamp
        $User.Timestamp.ToString('yyyy-MM-ddTHH:mm:ssZ')
    } else {
        $null
    }
    
    # Get next billing date
    $NextBillingDate = if ($User.PSObject.Properties['NextBillingDate'] -and $User.NextBillingDate) {
        $User.NextBillingDate
    } else {
        $null
    }
    
    # Get cancellation date
    $CancelledAt = if ($User.PSObject.Properties['CancelledAt'] -and $User.CancelledAt) {
        $User.CancelledAt
    } else {
        $null
    }
    
    # Get payment information
    $Amount = if ($User.PSObject.Properties['SubscriptionAmount'] -and $User.SubscriptionAmount) {
        $User.SubscriptionAmount
    } else {
        $null
    }
    
    $Currency = if ($User.PSObject.Properties['SubscriptionCurrency'] -and $User.SubscriptionCurrency) {
        $User.SubscriptionCurrency
    } else {
        'USD'
    }
    
    # Determine if subscription is trial
    $IsTrial = $Status -eq 'trial'
    
    # Determine effective tier based on status and expiration
    $EffectiveTier = $Tier
    $HasAccess = $true
    $AccessUntil = $null
    
    # Check if subscription has expired or been cancelled
    if ($Tier -ne 'free') {
        # For cancelled subscriptions, check if they still have access
        if ($Status -eq 'cancelled') {
            if ($NextBillingDate) {
                try {
                    $NextBillingDateTime = [DateTime]::Parse($NextBillingDate)
                    if ($NextBillingDateTime -gt $Now) {
                        # Still has access until next billing date
                        $AccessUntil = $NextBillingDate
                        $HasAccess = $true
                    } else {
                        # Access expired
                        $EffectiveTier = 'free'
                        $HasAccess = $false
                        $AccessUntil = $NextBillingDate
                    }
                } catch {
                    # Invalid date, treat as expired
                    $EffectiveTier = 'free'
                    $HasAccess = $false
                }
            } else {
                # No billing date, treat as immediate cancellation
                $EffectiveTier = 'free'
                $HasAccess = $false
            }
        }
        
        # Check for expired subscriptions
        if ($Status -eq 'expired' -or $Status -eq 'suspended') {
            $EffectiveTier = 'free'
            $HasAccess = $false
        }
        
        # Check if next billing date has passed for active subscriptions
        if ($Status -eq 'active' -and $NextBillingDate) {
            try {
                $NextBillingDateTime = [DateTime]::Parse($NextBillingDate)
                if ($NextBillingDateTime -lt $Now) {
                    # Subscription payment may have failed, but don't automatically downgrade
                    # This should be handled by a payment webhook or scheduled job
                    Write-Warning "User $($User.RowKey) has active subscription but billing date has passed"
                }
            } catch {
                Write-Warning "Failed to parse NextBillingDate for user $($User.RowKey): $NextBillingDate"
            }
        }
    }
    
    # Build and return subscription object
    return @{
        # Basic subscription info
        Tier = $Tier
        EffectiveTier = $EffectiveTier
        Status = $Status
        IsTrial = $IsTrial
        HasAccess = $HasAccess
        
        # Billing information
        BillingCycle = $BillingCycle
        Amount = $Amount
        Currency = $Currency
        
        # Dates
        SubscriptionStartedAt = $SubscriptionStartedAt
        NextBillingDate = $NextBillingDate
        CancelledAt = $CancelledAt
        AccessUntil = $AccessUntil
        
        # Feature access helpers
        IsFree = ($EffectiveTier -eq 'free')
        IsPro = ($EffectiveTier -eq 'pro')
        IsPremium = ($EffectiveTier -eq 'premium')
        IsEnterprise = ($EffectiveTier -eq 'enterprise')
        IsPaid = ($EffectiveTier -ne 'free')
        
        # Status helpers
        IsActive = ($Status -eq 'active')
        IsCancelled = ($Status -eq 'cancelled')
        IsExpired = ($Status -eq 'expired')
        IsSuspended = ($Status -eq 'suspended')
    }
}
