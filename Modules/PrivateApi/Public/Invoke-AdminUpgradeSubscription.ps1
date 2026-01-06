function Invoke-AdminUpgradeSubscription {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:subscription
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

    # Validate required fields
    if (-not $Body.tier) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Tier is required" }
        }
    }

    # Validate tier value
    $ValidTiers = @('free', 'premium', 'enterprise')
    if ($Body.tier -notin $ValidTiers) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid tier. Valid options are: free, premium, enterprise" }
        }
    }

    # Validate billing cycle is provided for paid tiers
    if ($Body.tier -ne 'free' -and -not $Body.billingCycle) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Billing cycle is required for premium and enterprise tiers" }
        }
    }

    # Validate billing cycle if provided
    if ($Body.billingCycle) {
        $ValidCycles = @('monthly', 'annual')
        if ($Body.billingCycle -notin $ValidCycles) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid billing cycle. Valid options are: monthly, annual" }
            }
        }
    }

    try {
        # This is a stub implementation - payment processing not implemented
        # In a full implementation, this would:
        # 1. Create a Stripe checkout session
        # 2. Return checkout URL
        # 3. Store pending subscription change
        # 4. Update subscription when payment confirmed via webhook
        
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'SubscriptionUpgradeRequested' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/upgradeSubscription'
        
        $Results = @{
            message = "Subscription upgrade requested"
            tier = $Body.tier
            note = "Payment processing not yet implemented. Contact support to upgrade your subscription."
        }
        
        if ($Body.billingCycle) {
            $Results.billingCycle = $Body.billingCycle
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Upgrade subscription error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to upgrade subscription"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
