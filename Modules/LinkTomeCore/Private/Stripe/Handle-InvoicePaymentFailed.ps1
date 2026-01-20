function Handle-InvoicePaymentFailed {
    param($Invoice)
    
    try {
        Write-Information "Handling invoice.payment_failed for invoice: $($Invoice.Id)"
        
        $SubscriptionId = $Invoice.Subscription
        if (-not $SubscriptionId) {
            Write-Information "No subscription associated with invoice"
            return $true
        }
        
        # Find user by Stripe subscription ID
        $Table = Get-LinkToMeTable -TableName 'Users'
        $SafeSubId = Protect-TableQueryValue -Value $SubscriptionId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "StripeSubscriptionId eq '$SafeSubId'" | Select-Object -First 1
        
        if (-not $UserData) {
            Write-Warning "Cannot find user for subscription: $SubscriptionId"
            return $false
        }
        
        $UserId = $UserData.RowKey
        
        # Mark as suspended (payment failed)
        $UserData.SubscriptionStatus = 'suspended'
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        Write-SecurityEvent -EventType 'SubscriptionPaymentFailed' -UserId $UserId -Reason "Invoice: $($Invoice.Id), Subscription: $SubscriptionId"
        Write-Warning "Payment failed for user $UserId, subscription marked as suspended"
        
        return $true
        
    } catch {
        Write-Error "Error handling invoice.payment_failed: $($_.Exception.Message)"
        return $false
    }
}