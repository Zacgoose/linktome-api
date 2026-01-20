function Handle-CheckoutSessionCompleted {
    param($Session)
    
    try {
        Write-Information "Handling checkout.session.completed for session: $($Session.Id)"
        
        # Get user ID from metadata
        $UserId = $Session.Metadata['user_id']
        if (-not $UserId) {
            # Fallback: Try to find user by customer ID
            Write-Information "No user_id in session metadata, looking up by customer ID: $($Session.Customer)"
            $Table = Get-LinkToMeTable -TableName 'Users'
            $SafeCustomerId = Protect-TableQueryValue -Value $Session.Customer
            $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "StripeCustomerId eq '$SafeCustomerId'" | Select-Object -First 1
            
            if ($UserData) {
                $UserId = $UserData.RowKey
                Write-Information "Found user by customer ID: $UserId"
            } else {
                Write-Warning "Cannot find user for customer: $($Session.Customer)"
                return $false
            }
        }
        
        # Get the subscription ID from the session
        $SubscriptionId = $Session.Subscription
        if (-not $SubscriptionId) {
            # If subscription ID not available yet, we can still store the customer ID
            # The subscription.created event will handle the full sync
            Write-Information "No subscription ID in checkout session yet, but customer linked to user"
            
            # Update user with customer ID if not already set
            $Table = Get-LinkToMeTable -TableName 'Users'
            $SafeUserId = Protect-TableQueryValue -Value $UserId
            $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
            
            if ($UserData) {
                if (-not ($UserData.PSObject.Properties['StripeCustomerId'] -and $UserData.StripeCustomerId)) {
                    if (-not $UserData.PSObject.Properties['StripeCustomerId']) {
                        $UserData | Add-Member -NotePropertyName 'StripeCustomerId' -NotePropertyValue $Session.Customer -Force
                    } else {
                        $UserData.StripeCustomerId = $Session.Customer
                    }
                    Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
                    Write-Information "Updated user $UserId with customer ID $($Session.Customer)"
                }
            }
            
            # Return true as this is not an error - subscription.created will do full sync
            return $true
        }
        
        # Fetch the full subscription details from Stripe
        $SubscriptionService = [Stripe.SubscriptionService]::new()
        $Subscription = $SubscriptionService.Get($SubscriptionId)
        
        # Sync subscription to user record
        $Result = Sync-UserSubscriptionFromStripe -UserId $UserId -StripeSubscription $Subscription -StripeCustomerId $Session.Customer
        
        if ($Result) {
            Write-SecurityEvent -EventType 'SubscriptionCheckoutCompleted' -UserId $UserId -Reason "Session: $($Session.Id), Subscription: $SubscriptionId"
        }
        
        return $Result
        
    } catch {
        Write-Error "Error handling checkout.session.completed: $($_.Exception.Message)"
        return $false
    }
}