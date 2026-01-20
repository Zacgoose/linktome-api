function Handle-SubscriptionUpdated {
    param($Subscription)
    
    try {
        Write-Information "Handling customer.subscription.updated for subscription: $($Subscription.Id)"
        
        # Get user ID from metadata
        $UserId = $Subscription.Metadata['user_id']
        if (-not $UserId) {
            # Try to find user by Stripe subscription ID
            $Table = Get-LinkToMeTable -TableName 'Users'
            $SafeSubId = Protect-TableQueryValue -Value $Subscription.Id
            $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "StripeSubscriptionId eq '$SafeSubId'" | Select-Object -First 1
            
            if ($UserData) {
                $UserId = $UserData.RowKey
            } else {
                Write-Warning "Cannot find user for subscription: $($Subscription.Id)"
                return $false
            }
        }
        
        # Sync subscription to user record
        $Result = Sync-UserSubscriptionFromStripe -UserId $UserId -StripeSubscription $Subscription
        
        if ($Result) {
            Write-SecurityEvent -EventType 'SubscriptionUpdated' -UserId $UserId -Details "Subscription: $($Subscription.Id), Status: $($Subscription.Status)"
        }
        
        return $Result
        
    } catch {
        Write-Error "Error handling customer.subscription.updated: $($_.Exception.Message)"
        return $false
    }
}