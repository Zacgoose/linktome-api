function Handle-SubscriptionCreated {
    param($Subscription)
    
    try {
        Write-Information "Handling customer.subscription.created for subscription: $($Subscription.Id)"
        
        # Get user ID from subscription metadata
        $UserId = $Subscription.Metadata['user_id']
        if (-not $UserId) {
            # Fallback: Try to find user by customer ID
            Write-Information "No user_id in subscription metadata, looking up by customer ID: $($Subscription.CustomerId)"
            $Table = Get-LinkToMeTable -TableName 'Users'
            $SafeCustomerId = Protect-TableQueryValue -Value $Subscription.CustomerId
            $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "StripeCustomerId eq '$SafeCustomerId'" | Select-Object -First 1
            
            if ($UserData) {
                $UserId = $UserData.RowKey
                Write-Information "Found user by customer ID: $UserId"
            } else {
                Write-Warning "Cannot find user for customer: $($Subscription.CustomerId)"
                return $false
            }
        }
        
        # Sync subscription to user record
        $Result = Sync-UserSubscriptionFromStripe -UserId $UserId -StripeSubscription $Subscription
        
        if ($Result) {
            Write-SecurityEvent -EventType 'SubscriptionCreated' -UserId $UserId -Reason "Subscription: $($Subscription.Id)"
        }
        
        return $Result
        
    } catch {
        Write-Error "Error handling customer.subscription.created: $($_.Exception.Message)"
        return $false
    }
}