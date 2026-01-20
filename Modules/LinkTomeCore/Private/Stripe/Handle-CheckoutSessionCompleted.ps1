function Handle-CheckoutSessionCompleted {
    param($Session)
    
    try {
        Write-Information "Handling checkout.session.completed for session: $($Session.Id)"
        
        # Get user ID from metadata
        $UserId = $Session.Metadata['user_id']
        if (-not $UserId) {
            Write-Warning "No user_id in checkout session metadata"
            return $false
        }
        
        # Get the subscription ID from the session
        $SubscriptionId = $Session.Subscription
        if (-not $SubscriptionId) {
            Write-Warning "No subscription ID in checkout session"
            return $false
        }
        
        # Fetch the full subscription details from Stripe
        $SubscriptionService = [Stripe.SubscriptionService]::new()
        $Subscription = $SubscriptionService.Get($SubscriptionId)
        
        # Sync subscription to user record
        $Result = Sync-UserSubscriptionFromStripe -UserId $UserId -StripeSubscription $Subscription -StripeCustomerId $Session.Customer
        
        if ($Result) {
            Write-SecurityEvent -EventType 'SubscriptionCheckoutCompleted' -UserId $UserId -Details "Session: $($Session.Id), Subscription: $SubscriptionId"
        }
        
        return $Result
        
    } catch {
        Write-Error "Error handling checkout.session.completed: $($_.Exception.Message)"
        return $false
    }
}