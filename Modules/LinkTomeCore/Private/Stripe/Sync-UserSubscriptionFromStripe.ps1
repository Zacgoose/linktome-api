function Sync-UserSubscriptionFromStripe {
    <#
    .SYNOPSIS
        Sync user subscription data from Stripe to Users table
    .DESCRIPTION
        Updates the Users table with the latest subscription information from Stripe.
        Maps Stripe subscription data to our internal user fields.
    .PARAMETER UserId
        The user ID (RowKey in Users table)
    .PARAMETER StripeSubscription
        The Stripe subscription object
    .PARAMETER StripeCustomerId
        The Stripe customer ID (optional, will be read from subscription if not provided)
    .EXAMPLE
        Sync-UserSubscriptionFromStripe -UserId "user-123" -StripeSubscription $subscription
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [object]$StripeSubscription,
        
        [Parameter()]
        [string]$StripeCustomerId
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get user record
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            Write-Warning "User not found: $UserId"
            return $false
        }
        
        # Extract tier from metadata
        $Tier = 'free'
        if ($StripeSubscription.Metadata -and $StripeSubscription.Metadata['tier']) {
            $Tier = $StripeSubscription.Metadata['tier']
        } elseif ($StripeSubscription.Items -and $StripeSubscription.Items.Data.Count -gt 0) {
            # Try to map from price ID if metadata not available
            $PriceId = $StripeSubscription.Items.Data[0].Price.Id
            $Tier = Get-TierFromPriceId -PriceId $PriceId
        }
        
        # Map Stripe status to our status
        $Status = switch ($StripeSubscription.Status) {
            'active' { 'active' }
            'canceled' { 'cancelled' }
            'incomplete' { 'active' }
            'incomplete_expired' { 'expired' }
            'past_due' { 'active' }
            'trialing' { 'trial' }
            'unpaid' { 'suspended' }
            default { 'active' }
        }
        
        # Update user subscription fields
        $UserData.SubscriptionTier = $Tier
        $UserData.SubscriptionStatus = $Status
        
        # Store Stripe customer ID
        if ($StripeCustomerId) {
            if (-not $UserData.PSObject.Properties['StripeCustomerId']) {
                $UserData | Add-Member -NotePropertyName 'StripeCustomerId' -NotePropertyValue $StripeCustomerId -Force
            } else {
                $UserData.StripeCustomerId = $StripeCustomerId
            }
        } elseif ($StripeSubscription.CustomerId) {
            if (-not $UserData.PSObject.Properties['StripeCustomerId']) {
                $UserData | Add-Member -NotePropertyName 'StripeCustomerId' -NotePropertyValue $StripeSubscription.CustomerId -Force
            } else {
                $UserData.StripeCustomerId = $StripeSubscription.CustomerId
            }
        }
        
        # Store Stripe subscription ID
        if (-not $UserData.PSObject.Properties['StripeSubscriptionId']) {
            $UserData | Add-Member -NotePropertyName 'StripeSubscriptionId' -NotePropertyValue $StripeSubscription.Id -Force
        } else {
            $UserData.StripeSubscriptionId = $StripeSubscription.Id
        }
        
        # Update billing cycle
        $BillingCycle = if ($StripeSubscription.Items.Data[0].Price.Recurring.Interval -eq 'year') {
            'annual'
        } else {
            'monthly'
        }
        
        if (-not $UserData.PSObject.Properties['BillingCycle']) {
            $UserData | Add-Member -NotePropertyName 'BillingCycle' -NotePropertyValue $BillingCycle -Force
        } else {
            $UserData.BillingCycle = $BillingCycle
        }
        
        # Update subscription dates
        # Read CurrentPeriodEnd from subscription items (this is where Stripe stores it)
        $PeriodEnd = $null
        if ($StripeSubscription.Items -and $StripeSubscription.Items.Data -and $StripeSubscription.Items.Data.Count -gt 0) {
            $PeriodEnd = $StripeSubscription.Items.Data[0].CurrentPeriodEnd
        }
        
        Write-Information "Subscription CurrentPeriodEnd value from items: $PeriodEnd (Type: $($PeriodEnd.GetType().Name))"
        
        # Convert to DateTime string for NextBillingDate
        if ($PeriodEnd) {
            try {
                # Check if it's already a DateTime object (Stripe.net SDK converts it automatically)
                if ($PeriodEnd -is [DateTime]) {
                    $CurrentPeriodEnd = $PeriodEnd.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    Write-Information "Using DateTime directly: $CurrentPeriodEnd"
                }
                # If it's a Unix timestamp (long/int), convert it
                elseif ($PeriodEnd -is [long] -or $PeriodEnd -is [int] -or $PeriodEnd -is [double]) {
                    $CurrentPeriodEnd = [DateTime]::UnixEpoch.AddSeconds($PeriodEnd).ToString('yyyy-MM-ddTHH:mm:ssZ')
                    Write-Information "Converted from Unix timestamp: $CurrentPeriodEnd"
                }
                else {
                    Write-Warning "CurrentPeriodEnd has unexpected type: $($PeriodEnd.GetType().FullName)"
                    $CurrentPeriodEnd = $null
                }
                
                if ($CurrentPeriodEnd) {
                    if (-not $UserData.PSObject.Properties['NextBillingDate']) {
                        $UserData | Add-Member -NotePropertyName 'NextBillingDate' -NotePropertyValue $CurrentPeriodEnd -Force
                    } else {
                        $UserData.NextBillingDate = $CurrentPeriodEnd
                    }
                }
            } catch {
                Write-Warning "Failed to process CurrentPeriodEnd: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "CurrentPeriodEnd not found in subscription items, skipping NextBillingDate update"
        }
        
        # Update last renewal if this is a payment success
        $Now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        if (-not $UserData.PSObject.Properties['LastStripeRenewal']) {
            $UserData | Add-Member -NotePropertyName 'LastStripeRenewal' -NotePropertyValue $Now -Force
        } else {
            $UserData.LastStripeRenewal = $Now
        }
        
        # Handle CancelledAt field based on subscription state
        # Set CancelledAt only when subscription is marked for cancellation at period end
        # Clear it when subscription is active/updated and not cancelled
        if ($StripeSubscription.CancelAtPeriodEnd -or $StripeSubscription.Status -eq 'canceled') {
            # Subscription is cancelled or will be cancelled
            if ($StripeSubscription.CanceledAt) {
                # Use the actual cancelled timestamp if available
                $CancelledAtValue = $null
                if ($StripeSubscription.CanceledAt -is [DateTime]) {
                    $CancelledAtValue = $StripeSubscription.CanceledAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                } elseif ($StripeSubscription.CanceledAt -is [long] -or $StripeSubscription.CanceledAt -is [int]) {
                    $CancelledAtValue = [DateTime]::UnixEpoch.AddSeconds($StripeSubscription.CanceledAt).ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                
                if ($CancelledAtValue) {
                    if (-not $UserData.PSObject.Properties['CancelledAt']) {
                        $UserData | Add-Member -NotePropertyName 'CancelledAt' -NotePropertyValue $CancelledAtValue -Force
                    } else {
                        $UserData.CancelledAt = $CancelledAtValue
                    }
                }
            } else {
                # No CanceledAt timestamp yet, but subscription is marked for cancellation
                # Set it to now
                if (-not $UserData.PSObject.Properties['CancelledAt']) {
                    $UserData | Add-Member -NotePropertyName 'CancelledAt' -NotePropertyValue $Now -Force
                } else {
                    $UserData.CancelledAt = $Now
                }
            }
        } else {
            # Subscription is active/updated and not cancelled - clear CancelledAt
            if ($UserData.PSObject.Properties['CancelledAt']) {
                $UserData.CancelledAt = $null
                Write-Information "Cleared CancelledAt for user $UserId (subscription active)"
            }
        }
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        Write-Information "Successfully synced subscription for user $UserId $Tier ($Status)"
        return $true
        
    } catch {
        Write-Error "Failed to sync subscription from Stripe: $($_.Exception.Message)"
        return $false
    }
}

function Get-TierFromPriceId {
    <#
    .SYNOPSIS
        Map Stripe price ID to tier name
    .PARAMETER PriceId
        The Stripe price ID
    #>
    param([string]$PriceId)
    
    # Map price IDs to tiers from environment variables
    # Monthly prices
    $ProPriceId = $env:STRIPE_PRICE_ID_PRO
    $PremiumPriceId = $env:STRIPE_PRICE_ID_PREMIUM
    $EnterprisePriceId = $env:STRIPE_PRICE_ID_ENTERPRISE
    
    # Annual prices
    $ProAnnualPriceId = $env:STRIPE_PRICE_ID_PRO_ANNUAL
    $PremiumAnnualPriceId = $env:STRIPE_PRICE_ID_PREMIUM_ANNUAL
    $EnterpriseAnnualPriceId = $env:STRIPE_PRICE_ID_ENTERPRISE_ANNUAL
    
    # Check monthly prices
    if ($PriceId -eq $ProPriceId -or $PriceId -eq $ProAnnualPriceId) {
        return 'pro'
    } elseif ($PriceId -eq $PremiumPriceId -or $PriceId -eq $PremiumAnnualPriceId) {
        return 'premium'
    } elseif ($PriceId -eq $EnterprisePriceId -or $PriceId -eq $EnterpriseAnnualPriceId) {
        return 'enterprise'
    } else {
        Write-Warning "Unknown price ID: $PriceId, defaulting to free tier"
        return 'free'
    }
}
