function Invoke-AdminCreateCheckoutSession {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:subscription
    .SYNOPSIS
        Create a Stripe Checkout session for subscription upgrade
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

    try {
        # Validate required fields
        if (-not $Body.tier) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Tier is required (pro, premium, or enterprise)" }
            }
        }

        # Validate tier
        $ValidTiers = @('pro', 'premium', 'enterprise')
        if ($Body.tier -notin $ValidTiers) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid tier. Valid options: pro, premium, enterprise" }
            }
        }

        # Validate billing cycle (default to monthly if not specified)
        $BillingCycle = if ($Body.billingCycle) { $Body.billingCycle } else { 'monthly' }
        if ($BillingCycle -notin @('monthly', 'annual')) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid billing cycle. Valid options: monthly, annual" }
            }
        }

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

        # Get price ID based on tier and billing cycle
        $PriceId = switch ($Body.tier) {
            'pro' { 
                if ($BillingCycle -eq 'annual') { 
                    $env:STRIPE_PRICE_ID_PRO_ANNUAL 
                } else { 
                    $env:STRIPE_PRICE_ID_PRO 
                }
            }
            'premium' { 
                if ($BillingCycle -eq 'annual') { 
                    $env:STRIPE_PRICE_ID_PREMIUM_ANNUAL 
                } else { 
                    $env:STRIPE_PRICE_ID_PREMIUM 
                }
            }
            'enterprise' { 
                if ($BillingCycle -eq 'annual') { 
                    $env:STRIPE_PRICE_ID_ENTERPRISE_ANNUAL 
                } else { 
                    $env:STRIPE_PRICE_ID_ENTERPRISE 
                }
            }
        }

        if (-not $PriceId) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = "Price configuration not found for tier: $($Body.tier) ($BillingCycle)" }
            }
        }

        # Create or get Stripe customer
        $CustomerId = $null
        if ($UserData.PSObject.Properties['StripeCustomerId'] -and $UserData.StripeCustomerId) {
            $CustomerId = $UserData.StripeCustomerId
        } else {
            # Create new Stripe customer
            $CustomerService = [Stripe.CustomerService]::new()
            $CustomerOptions = [Stripe.CustomerCreateOptions]::new()
            $CustomerOptions.Email = $UserData.Email
            $CustomerMetadataDict = New-Object 'System.Collections.Generic.Dictionary[string,string]'
            $CustomerMetadataDict.Add('user_id', [string]$UserId)
            $CustomerMetadataDict.Add('username', [string]$UserData.Username)
            $CustomerOptions.Metadata = $CustomerMetadataDict
            
            $Customer = $CustomerService.Create($CustomerOptions)
            $CustomerId = $Customer.Id
            
            # Store customer ID in user record
            if (-not $UserData.PSObject.Properties['StripeCustomerId']) {
                $UserData | Add-Member -NotePropertyName 'StripeCustomerId' -NotePropertyValue $CustomerId -Force
            } else {
                $UserData.StripeCustomerId = $CustomerId
            }
            Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        }

        # Create Stripe Checkout Session
        $SessionService = [Stripe.Checkout.SessionService]::new()
        $SessionOptions = [Stripe.Checkout.SessionCreateOptions]::new()
        
        # Set basic session options
        $SessionOptions.Customer = $CustomerId
        $SessionOptions.Mode = 'subscription'
        $SessionOptions.LineItems = [System.Collections.Generic.List[Stripe.Checkout.SessionLineItemOptions]]::new()
        
        $LineItem = [Stripe.Checkout.SessionLineItemOptions]::new()
        $LineItem.Price = $PriceId
        $LineItem.Quantity = 1
        $SessionOptions.LineItems.Add($LineItem)
        
        # Set success and cancel URLs
        $FrontendUrl = $env:FRONTEND_URL ?? 'http://localhost:3000'
        $SessionOptions.SuccessUrl = "$FrontendUrl/subscription/success?session_id={CHECKOUT_SESSION_ID}"
        $SessionOptions.CancelUrl = "$FrontendUrl/subscription/cancel"
        
        # Add metadata to session
        $MetadataDict = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $MetadataDict.Add('user_id', [string]$UserId)
        $MetadataDict.Add('tier', [string]$Body.tier)
        $MetadataDict.Add('billing_cycle', [string]$BillingCycle)
        $SessionOptions.Metadata = $MetadataDict
        
        # IMPORTANT: Add metadata to the subscription that will be created
        # This ensures the subscription has the user_id in metadata
        $SessionOptions.SubscriptionData = [Stripe.Checkout.SessionSubscriptionDataOptions]::new()
        $SubscriptionMetadataDict = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $SubscriptionMetadataDict.Add('user_id', [string]$UserId)
        $SubscriptionMetadataDict.Add('tier', [string]$Body.tier)
        $SubscriptionMetadataDict.Add('billing_cycle', [string]$BillingCycle)
        $SessionOptions.SubscriptionData.Metadata = $SubscriptionMetadataDict
        
        # Allow promotion codes
        $SessionOptions.AllowPromotionCodes = $true
        
        # Create the session
        $Session = $SessionService.Create($SessionOptions)
        
        # Log security event
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'CheckoutSessionCreated' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/createCheckoutSession' -Reason "Tier: $($Body.tier), Cycle: $BillingCycle"
        
        $Results = @{
            sessionId = $Session.Id
            checkoutUrl = $Session.Url
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Create checkout session error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to create checkout session"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
