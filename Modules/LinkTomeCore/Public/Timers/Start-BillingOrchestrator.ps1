function Start-BillingOrchestrator {
    <#
    .SYNOPSIS
        Process billing and subscription renewals
    .DESCRIPTION
        Monitors subscriptions and syncs with Stripe to handle stale renewals.
        Finds subscriptions that should have renewed but haven't received webhook confirmation.
    .FUNCTIONALITY
        Timer
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Information "Starting billing orchestrator"
        
        # Check if Stripe is configured
        if (-not $env:STRIPE_API_KEY) {
            Write-Information "Stripe not configured, skipping billing orchestrator"
            return @{
                Status = "Skipped"
                Message = "Stripe not configured"
            }
        }
        
        # Initialize Stripe
        $StripeInitialized = Initialize-StripeClient
        if (-not $StripeInitialized) {
            Write-Warning "Failed to initialize Stripe client"
            return @{
                Status = "Failed"
                Message = "Failed to initialize Stripe"
            }
        }
        
        $Now = (Get-Date).ToUniversalTime()
        $SyncedCount = 0
        $ExpiredCount = 0
        $ErrorCount = 0
        
        # Get all users with active paid subscriptions
        $Table = Get-LinkToMeTable -TableName 'Users'
        $AllUsers = Get-LinkToMeAzDataTableEntity @Table
        
        foreach ($User in $AllUsers) {
            # Skip free tier users
            if (-not $User.PSObject.Properties['SubscriptionTier'] -or $User.SubscriptionTier -eq 'free') {
                continue
            }
            
            # Skip if no Stripe subscription ID
            if (-not ($User.PSObject.Properties['StripeSubscriptionId'] -and $User.StripeSubscriptionId)) {
                continue
            }
            
            # Check if subscription needs sync
            $NeedsSync = $false
            
            # Case 1: Active subscription with passed billing date and no recent renewal
            if ($User.SubscriptionStatus -eq 'active' -and $User.PSObject.Properties['NextBillingDate'] -and $User.NextBillingDate) {
                try {
                    $NextBillingDate = [DateTime]::Parse($User.NextBillingDate, [System.Globalization.CultureInfo]::InvariantCulture)
                    
                    # If billing date has passed
                    if ($NextBillingDate -lt $Now) {
                        # Check if we have a recent renewal confirmation
                        $LastRenewal = $null
                        if ($User.PSObject.Properties['LastStripeRenewal'] -and $User.LastStripeRenewal) {
                            $LastRenewal = [DateTime]::Parse($User.LastStripeRenewal, [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                        
                        # If no renewal or renewal is before the billing date, we need to sync
                        if (-not $LastRenewal -or $LastRenewal -lt $NextBillingDate) {
                            Write-Information "Stale subscription found for user $($User.RowKey), syncing with Stripe"
                            $NeedsSync = $true
                        }
                    }
                } catch {
                    Write-Warning "Failed to parse dates for user $($User.RowKey): $($_.Exception.Message)"
                }
            }
            
            # Case 2: Suspended subscriptions should be checked periodically
            if ($User.SubscriptionStatus -eq 'suspended') {
                Write-Information "Checking suspended subscription for user $($User.RowKey)"
                $NeedsSync = $true
            }
            
            # Sync with Stripe if needed
            if ($NeedsSync) {
                try {
                    $SubscriptionService = [Stripe.SubscriptionService]::new()
                    $StripeSubscription = $SubscriptionService.Get($User.StripeSubscriptionId)
                    
                    if ($StripeSubscription.Status -eq 'active') {
                        # Still active on Stripe, update our records
                        Write-Information "Syncing active subscription for user $($User.RowKey)"
                        $Result = Sync-UserSubscriptionFromStripe -UserId $User.RowKey -StripeSubscription $StripeSubscription
                        if ($Result) {
                            $SyncedCount++
                        } else {
                            $ErrorCount++
                        }
                    } elseif ($StripeSubscription.Status -in @('canceled', 'unpaid', 'incomplete_expired')) {
                        # Subscription ended on Stripe, downgrade user
                        Write-Information "Expiring subscription for user $($User.RowKey)"
                        $User.SubscriptionTier = 'free'
                        $User.SubscriptionStatus = 'expired'
                        if ($User.PSObject.Properties['StripeSubscriptionId']) {
                            $User.StripeSubscriptionId = $null
                        }
                        Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
                        $ExpiredCount++
                    } else {
                        # Other statuses (past_due, trialing, etc.) - sync the data
                        Write-Information "Syncing subscription status for user $($User.RowKey): $($StripeSubscription.Status)"
                        $Result = Sync-UserSubscriptionFromStripe -UserId $User.RowKey -StripeSubscription $StripeSubscription
                        if ($Result) {
                            $SyncedCount++
                        } else {
                            $ErrorCount++
                        }
                    }
                    
                } catch {
                    Write-Error "Failed to sync subscription for user $($User.RowKey): $($_.Exception.Message)"
                    $ErrorCount++
                }
            }
        }
        
        Write-Information "Billing orchestrator completed: Synced=$SyncedCount, Expired=$ExpiredCount, Errors=$ErrorCount"
        return @{
            Status = "Success"
            Message = "Billing orchestrator completed"
            SyncedCount = $SyncedCount
            ExpiredCount = $ExpiredCount
            ErrorCount = $ErrorCount
        }
    } catch {
        Write-Warning "Billing orchestrator failed: $($_.Exception.Message)"
        throw
    }
}
