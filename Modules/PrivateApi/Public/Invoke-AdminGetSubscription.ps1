function Invoke-AdminGetSubscription {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:subscription
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
        
        # Build response with all subscription details
        $Results = @{
            currentTier = $Subscription.Tier
            effectiveTier = $Subscription.EffectiveTier
            status = $Subscription.Status
            isTrial = $Subscription.IsTrial
            hasAccess = $Subscription.HasAccess
        }
        
        # Add subscription started date
        if ($Subscription.SubscriptionStartedAt) {
            $Results.subscriptionStartedAt = $Subscription.SubscriptionStartedAt
        }
        
        # Add billing information for paid tiers
        if ($Subscription.BillingCycle) {
            $Results.billingCycle = $Subscription.BillingCycle
        }
        
        if ($Subscription.NextBillingDate) {
            $Results.nextBillingDate = $Subscription.NextBillingDate
        }
        
        if ($Subscription.Amount) {
            $Results.amount = $Subscription.Amount
        }
        
        if ($Subscription.Currency) {
            $Results.currency = $Subscription.Currency
        }
        
        # Add cancellation info if applicable
        if ($Subscription.CancelledAt) {
            $Results.cancelledAt = $Subscription.CancelledAt
        }
        
        if ($Subscription.AccessUntil) {
            $Results.accessUntil = $Subscription.AccessUntil
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get subscription error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get subscription"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
