function Get-UserSubscription {
    <#
    .SYNOPSIS
        Get complete subscription information for a user
    .DESCRIPTION
        Centralizes all subscription data access and provides a consistent subscription object
        with all relevant fields including tier, status, billing info, and access control.
        For sub-accounts, inherits subscription from parent account.
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
    
    # Check if this is a sub-account and inherit parent's subscription
    if ($User.PSObject.Properties['IsSubAccount'] -and $User.IsSubAccount -eq $true) {
        # Get parent from SubAccounts table
        try {
            $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
            $SafeSubId = Protect-TableQueryValue -Value $User.RowKey
            $Relationship = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "RowKey eq '$SafeSubId'" | Select-Object -First 1
            
            if ($Relationship) {
                $ParentUserId = $Relationship.PartitionKey
                
                # Get parent user
                $UsersTable = Get-LinkToMeTable -TableName 'Users'
                $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
                $ParentUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeParentId'" | Select-Object -First 1
                
                if ($ParentUser) {
                    # Get parent's subscription (recursive in case parent is also a sub-account)
                    $ParentSubscription = Get-UserSubscription -User $ParentUser
                    
                    # Mark as inherited for display purposes
                    $ParentSubscription.IsInherited = $true
                    $ParentSubscription.InheritedFromUserId = $ParentUserId
                    
                    return $ParentSubscription
                }
            }
        } catch {
            Write-Warning "Failed to get parent subscription for sub-account $($User.RowKey): $($_.Exception.Message)"
            # Fall through to return sub-account's own subscription data
        }
    }
    
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

    # Get subscription quantity (total users allowed)
    $SubscriptionQuantity = if ($User.PSObject.Properties['SubscriptionQuantity'] -and $User.SubscriptionQuantity) {
        [int]$User.SubscriptionQuantity
    } else {
        1
    }

    # Calculate sub-account limit (quantity - 1 for main account)
    $SubAccountLimit = [Math]::Max(0, $SubscriptionQuantity - 1)
    
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

    # Get cancel_at
    $CancelAt = if ($User.PSObject.Properties['CancelAt'] -and $User.CancelAt) { 
        $User.CancelAt
    } else { 
        $null 
    }

    # Get payment information
    $Amount = if ($User.PSObject.Properties['SubscriptionAmount'] -and $User.SubscriptionAmount) {
        $User.SubscriptionAmount
    } else {
        $null
    }
    
    # Default currency constant
    $DefaultCurrency = 'AUD'
    $Currency = if ($User.PSObject.Properties['SubscriptionCurrency'] -and $User.SubscriptionCurrency) {
        $User.SubscriptionCurrency
    } else {
        $DefaultCurrency
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
                    $NextBillingDateTime = [DateTime]::Parse($NextBillingDate, [System.Globalization.CultureInfo]::InvariantCulture)
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
                    Write-Warning "Failed to parse NextBillingDate in subscription data"
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
                $NextBillingDateTime = [DateTime]::Parse($NextBillingDate, [System.Globalization.CultureInfo]::InvariantCulture)
                if ($NextBillingDateTime -lt $Now) {
                    # Subscription payment may have failed, but don't automatically downgrade
                    # This should be handled by a payment webhook or scheduled job
                    Write-Warning "Active subscription has passed billing date - payment processing may be required"
                }
            } catch {
                Write-Warning "Failed to parse NextBillingDate in active subscription"
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
        
        # Cancelation info
        CancelAt = $CancelAt

        # Quantity info
        SubscriptionQuantity = $SubscriptionQuantity
        SubAccountLimit = $SubAccountLimit
        
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
        
        # Sub-account inheritance markers
        IsInherited = $false
        InheritedFromUserId = $null
    }
}
