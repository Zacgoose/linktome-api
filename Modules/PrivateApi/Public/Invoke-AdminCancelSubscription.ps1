function Invoke-AdminCancelSubscription {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:subscription
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get user record
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Get subscription info using centralized helper
        $Subscription = Get-UserSubscription -User $UserData
        
        # Check if user has a paid subscription
        if ($Subscription.IsFree) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "No active subscription to cancel" }
            }
        }
        
        # Check if already cancelled
        if ($Subscription.IsCancelled) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Subscription is already cancelled" }
            }
        }
        
        # If user has a Stripe subscription, cancel it through Stripe
        if ($UserData.PSObject.Properties['StripeSubscriptionId'] -and $UserData.StripeSubscriptionId) {
            # Initialize Stripe
            $StripeInitialized = Initialize-StripeClient
            if ($StripeInitialized) {
                try {
                    # Cancel the subscription at period end (user keeps access until billing period ends)
                    $SubscriptionService = [Stripe.SubscriptionService]::new()
                    $UpdateOptions = [Stripe.SubscriptionUpdateOptions]::new()
                    $UpdateOptions.CancelAtPeriodEnd = $true
                    
                    $CancelledSubscription = $SubscriptionService.Update($UserData.StripeSubscriptionId, $UpdateOptions)
                    Write-Information "Cancelled Stripe subscription $($UserData.StripeSubscriptionId) at period end"
                    
                    # Sync the updated subscription data
                    Sync-UserSubscriptionFromStripe -UserId $UserId -StripeSubscription $CancelledSubscription
                    
                    # Reload user data after sync
                    $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
                    
                } catch {
                    Write-Warning "Failed to cancel Stripe subscription: $($_.Exception.Message). Proceeding with local cancellation."
                }
            } else {
                Write-Warning "Stripe not configured, proceeding with local cancellation only"
            }
        }
        
        # Get current timestamp
        $Now = (Get-Date).ToUniversalTime()
        $NowString = $Now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        
        # Mark subscription as cancelled (if not already done by Stripe sync)
        $UserData.SubscriptionStatus = 'cancelled'
        
        # Set cancellation timestamp
        if (-not $UserData.PSObject.Properties['CancelledAt']) {
            $UserData | Add-Member -NotePropertyName 'CancelledAt' -NotePropertyValue $NowString -Force
        } else {
            $UserData.CancelledAt = $NowString
        }
        
        # Get access until date (next billing date or now if not set/expired)
        $AccessUntil = $NowString
        if ($UserData.PSObject.Properties['NextBillingDate'] -and $UserData.NextBillingDate) {
            try {
                $NextBillingDateTime = [DateTime]::Parse($UserData.NextBillingDate)
                # Only use NextBillingDate if it's in the future
                if ($NextBillingDateTime -gt $Now) {
                    $AccessUntil = $UserData.NextBillingDate
                }
            } catch {
                # If date parsing fails, default to now
                Write-Warning "Could not parse NextBillingDate: $($UserData.NextBillingDate)"
            }
        }
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'SubscriptionCancelled' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/cancelSubscription'
        
        $Results = @{
            message = "Subscription cancelled successfully"
            tier = $Subscription.Tier
            status = 'cancelled'
            cancelledAt = $NowString
            accessUntil = $AccessUntil
        }
        
        # Add note about continued access if there's a future billing date
        if ($AccessUntil -ne $NowString) {
            $Results.note = "You can continue using $($Subscription.Tier) features until $AccessUntil"
        } else {
            $Results.note = "Subscription cancelled immediately. You will be downgraded to free tier."
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Cancel subscription error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to cancel subscription"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
