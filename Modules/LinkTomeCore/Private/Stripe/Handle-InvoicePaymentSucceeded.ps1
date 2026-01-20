function Handle-InvoicePaymentSucceeded {
    param($Invoice)
    
    try {
        Write-Information "Handling invoice.payment_succeeded for invoice: $($Invoice.Id)"
        
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
        
        # Update last renewal date
        $Now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        if (-not $UserData.PSObject.Properties['LastStripeRenewal']) {
            $UserData | Add-Member -NotePropertyName 'LastStripeRenewal' -NotePropertyValue $Now -Force
        } else {
            $UserData.LastStripeRenewal = $Now
        }
        
        # Ensure status is active
        $UserData.SubscriptionStatus = 'active'
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        Write-Information "Updated renewal date for user: $UserId"
        
        return $true
        
    } catch {
        Write-Error "Error handling invoice.payment_succeeded: $($_.Exception.Message)"
        return $false
    }
}