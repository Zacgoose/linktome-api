function Handle-SubscriptionCreated {
    param($Subscription)
    
    try {
        Write-Information "Handling customer.subscription.created for subscription: $($Subscription.Id)"
        
        # Get user ID from metadata
        $UserId = $Subscription.Metadata['user_id']
        if (-not $UserId) {
            Write-Warning "No user_id in subscription metadata"
            return $false
        }
        
        # Sync subscription to user record
        $Result = Sync-UserSubscriptionFromStripe -UserId $UserId -StripeSubscription $Subscription
        
        if ($Result) {
            Write-SecurityEvent -EventType 'SubscriptionCreated' -UserId $UserId -Details "Subscription: $($Subscription.Id)"
        }
        
        return $Result
        
    } catch {
        Write-Error "Error handling customer.subscription.created: $($_.Exception.Message)"
        return $false
    }
}