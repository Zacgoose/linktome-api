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

        # Use the exact raw body for signature verification
        $RawPayload = $Request.RawBody
        $Event = Test-StripeWebhookSignature -Payload $RawPayload -Signature $Signature -WebhookSecret $WebhookSecret

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
                $Processed = Sync-CheckoutSessionCompleted -Session $Session
            }
            
            'customer.subscription.created' {
                $Subscription = $Event.Data.Object
                $Processed = Sync-SubscriptionCreated -Subscription $Subscription
            }
            
            'customer.subscription.updated' {
                $Subscription = $Event.Data.Object
                $Processed = Sync-SubscriptionUpdated -Subscription $Subscription
            }
            
            'customer.subscription.deleted' {
                $Subscription = $Event.Data.Object
                $Processed = Sync-SubscriptionDeleted -Subscription $Subscription
            }
            
            'invoice.payment_succeeded' {
                $Invoice = $Event.Data.Object
                $Processed = Sync-InvoicePaymentSucceeded -Invoice $Invoice
            }
            
            'invoice.payment_failed' {
                $Invoice = $Event.Data.Object
                $Processed = Sync-InvoicePaymentFailed -Invoice $Invoice
            }
            
            'invoice.finalized' {
                $Invoice = $Event.Data.Object
                $Processed = Sync-InvoiceFinalized -Invoice $Invoice
            }
            
            'customer.subscription.trial_will_end' {
                $Subscription = $Event.Data.Object
                $Processed = Sync-SubscriptionTrialWillEnd -Subscription $Subscription
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
            Body = @{ received = $true; error = "Internal processing error" }
        }
    }
}