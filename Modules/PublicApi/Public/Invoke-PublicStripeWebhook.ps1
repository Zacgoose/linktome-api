function Invoke-PublicStripeWebhook {
    <#
    .FUNCTIONALITY
        Entrypoint
    .SYNOPSIS
        Handle Stripe webhook events
    .DESCRIPTION
        Processes webhook events from Stripe to keep subscription data in sync.
        Verifies webhook signature before processing to ensure authenticity.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        # Get webhook secret
        $WebhookSecret = $env:STRIPE_WEBHOOK_SECRET
        if (-not $WebhookSecret) {
            Write-Warning "STRIPE_WEBHOOK_SECRET not configured"
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = "Webhook not configured" }
            }
        }

        # Initialize Stripe
        $StripeInitialized = Initialize-StripeClient
        if (-not $StripeInitialized) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = "Stripe not configured" }
            }
        }

        # Get signature from headers
        $Signature = $Request.Headers.'Stripe-Signature'
        if (-not $Signature) {
            Write-Warning "Missing Stripe-Signature header"
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Missing signature" }
            }
        }

        # Get raw body - webhook signature verification requires the raw JSON
        $Payload = if ($Request.Body -is [string]) {
            $Request.Body
        } else {
            $Request.Body | ConvertTo-Json -Depth 20 -Compress
        }

        # Verify webhook signature and construct event
        $Event = Test-StripeWebhookSignature -Payload $Payload -Signature $Signature -WebhookSecret $WebhookSecret
        
        if (-not $Event) {
            Write-Warning "Webhook signature verification failed"
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid signature" }
            }
        }

        Write-Information "Processing webhook event: $($Event.Type) (ID: $($Event.Id))"

        # Process event based on type
        $Processed = $false
        
        switch ($Event.Type) {
            'checkout.session.completed' {
                $Session = $Event.Data.Object
                $Processed = Handle-CheckoutSessionCompleted -Session $Session
            }
            
            'customer.subscription.created' {
                $Subscription = $Event.Data.Object
                $Processed = Handle-SubscriptionCreated -Subscription $Subscription
            }
            
            'customer.subscription.updated' {
                $Subscription = $Event.Data.Object
                $Processed = Handle-SubscriptionUpdated -Subscription $Subscription
            }
            
            'customer.subscription.deleted' {
                $Subscription = $Event.Data.Object
                $Processed = Handle-SubscriptionDeleted -Subscription $Subscription
            }
            
            'invoice.payment_succeeded' {
                $Invoice = $Event.Data.Object
                $Processed = Handle-InvoicePaymentSucceeded -Invoice $Invoice
            }
            
            'invoice.payment_failed' {
                $Invoice = $Event.Data.Object
                $Processed = Handle-InvoicePaymentFailed -Invoice $Invoice
            }
            
            default {
                Write-Information "Unhandled webhook event type: $($Event.Type)"
                $Processed = $true  # Return success for unhandled events
            }
        }

        if ($Processed) {
            Write-Information "Successfully processed webhook event: $($Event.Type)"
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body = @{ received = $true }
            }
        } else {
            Write-Warning "Failed to process webhook event: $($Event.Type)"
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = "Processing failed" }
            }
        }

    } catch {
        Write-Error "Stripe webhook error: $($_.Exception.Message)"
        Write-Error $_.ScriptStackTrace
        
        # Always return 200 to Stripe to prevent retries for code errors
        # Log the error but acknowledge receipt
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ received = $true, error = "Internal processing error" }
        }
    }
}

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

function Handle-SubscriptionDeleted {
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
        
        Write-SecurityEvent -EventType 'SubscriptionDeleted' -UserId $UserId -Details "Subscription: $($Subscription.Id)"
        
        return $true
        
    } catch {
        Write-Error "Error handling customer.subscription.deleted: $($_.Exception.Message)"
        return $false
    }
}

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
        
        Write-SecurityEvent -EventType 'SubscriptionPaymentFailed' -UserId $UserId -Details "Invoice: $($Invoice.Id), Subscription: $SubscriptionId"
        Write-Warning "Payment failed for user $UserId, subscription marked as suspended"
        
        return $true
        
    } catch {
        Write-Error "Error handling invoice.payment_failed: $($_.Exception.Message)"
        return $false
    }
}
