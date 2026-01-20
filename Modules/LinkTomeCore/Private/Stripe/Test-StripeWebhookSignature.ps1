function Test-StripeWebhookSignature {
    <#
    .SYNOPSIS
        Verify Stripe webhook signature
    .DESCRIPTION
        Validates that a webhook request came from Stripe by verifying the signature.
        This is critical for security to prevent fake webhook requests.
    .PARAMETER Payload
        The raw request body (JSON string)
    .PARAMETER Signature
        The Stripe-Signature header value
    .PARAMETER WebhookSecret
        The webhook signing secret from Stripe dashboard
    .OUTPUTS
        Returns the verified Stripe Event object if valid, $null if invalid
    .EXAMPLE
        $Event = Test-StripeWebhookSignature -Payload $Request.Body -Signature $Request.Headers.'Stripe-Signature' -WebhookSecret $env:STRIPE_WEBHOOK_SECRET
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Payload,
        
        [Parameter(Mandatory)]
        [string]$Signature,
        
        [Parameter(Mandatory)]
        [string]$WebhookSecret
    )
    
    try {
        # Use Stripe's built-in signature verification
        $Event = [Stripe.EventUtility]::ConstructEvent(
            $Payload,
            $Signature,
            $WebhookSecret
        )
        
        Write-Information "Webhook signature verified successfully for event: $($Event.Type)"
        return $Event
        
    } catch [Stripe.StripeException] {
        Write-Warning "Webhook signature verification failed: $($_.Exception.Message)"
        return $null
        
    } catch {
        Write-Error "Error verifying webhook signature: $($_.Exception.Message)"
        return $null
    }
}
