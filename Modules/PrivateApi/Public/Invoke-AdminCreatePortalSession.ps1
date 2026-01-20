function Invoke-AdminCreatePortalSession {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:subscription
    .SYNOPSIS
        Create a Stripe Customer Portal session for subscription management
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }

    try {
        # Initialize Stripe
        $StripeInitialized = Initialize-StripeClient
        if (-not $StripeInitialized) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = "Stripe integration is not configured" }
            }
        }

        # Get user data
        $Table = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }

        # Check if user has a Stripe customer ID
        if (-not ($UserData.PSObject.Properties['StripeCustomerId'] -and $UserData.StripeCustomerId)) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ 
                    error = "No active subscription found. Please subscribe first."
                    needsSubscription = $true
                }
            }
        }

        # Create Stripe Portal Session
        $SessionService = [Stripe.BillingPortal.SessionService]::new()
        $SessionOptions = [Stripe.BillingPortal.SessionCreateOptions]::new()
        
        $SessionOptions.Customer = $UserData.StripeCustomerId
        
        # Set return URL
        $FrontendUrl = $env:FRONTEND_URL ?? 'http://localhost:3000'
        $SessionOptions.ReturnUrl = "$FrontendUrl/admin/subscription"
        
        # Configure flow to enable subscription updates if user has active subscription
        if ($UserData.PSObject.Properties['StripeSubscriptionId'] -and $UserData.StripeSubscriptionId) {
            $FlowData = [Stripe.BillingPortal.SessionFlowDataOptions]::new()
            $FlowData.Type = "subscription_update"
            
            # Configure subscription update options
            $SubscriptionUpdate = [Stripe.BillingPortal.SessionFlowDataSubscriptionUpdateOptions]::new()
            $SubscriptionUpdate.Subscription = $UserData.StripeSubscriptionId
            
            $FlowData.SubscriptionUpdate = $SubscriptionUpdate
            $SessionOptions.FlowData = $FlowData
        }
        
        # Create the session
        $Session = $SessionService.Create($SessionOptions)
        
        # Log security event
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'PortalSessionCreated' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/createPortalSession'
        
        $Results = @{
            portalUrl = $Session.Url
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Create portal session error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to create portal session"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
