function Sync-SubscriptionDeleted {
    param($Subscription)
    
    try {
        Write-Information "Handling customer.subscription.deleted for subscription: $($Subscription.Id)"
        
        # Find user by Stripe subscription ID
        $Table = Get-LinkToMeTable -TableName 'Users'
        $SafeSubId = Protect-TableQueryValue -Value $Subscription.Id
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "StripeSubscriptionId eq '$SafeSubId'" | Select-Object -First 1
        
        if (-not $UserData) {
            Write-Warning "Cannot find user for subscription: $($Subscription.Id)"
            return $false
        }
        
        $UserId = $UserData.RowKey
        
        # Downgrade to free tier
        $UserData.SubscriptionTier = 'free'
        $UserData.SubscriptionStatus = 'expired'
        
        # Clear Stripe IDs
        if ($UserData.PSObject.Properties['StripeSubscriptionId']) {
            $UserData.StripeSubscriptionId = $null
        }
        
        # Set cancellation date
        $Now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        if (-not $UserData.PSObject.Properties['CancelledAt']) {
            $UserData | Add-Member -NotePropertyName 'CancelledAt' -NotePropertyValue $Now -Force
        } else {
            $UserData.CancelledAt = $Now
        }
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        Write-SecurityEvent -EventType 'SubscriptionDeleted' -UserId $UserId -Reason "Subscription: $($Subscription.Id)"
        
        # Clean up features that are no longer available on free tier
        try {
            $CleanupResult = Invoke-FeatureCleanup -UserId $UserId -NewTier 'free'
            Write-Information "Feature cleanup completed: $($CleanupResult.cleanupActions.Count) actions taken"
        } catch {
            Write-Warning "Feature cleanup failed but subscription was still cancelled: $($_.Exception.Message)"
        }
        
        return $true
        
    } catch {
        Write-Error "Error handling customer.subscription.deleted: $($_.Exception.Message)"
        return $false
    }
}