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
        
        # Get subscription tier and status
        $Tier = if ($UserData.PSObject.Properties['SubscriptionTier']) { $UserData.SubscriptionTier } else { 'free' }
        $Status = if ($UserData.PSObject.Properties['SubscriptionStatus']) { $UserData.SubscriptionStatus } else { 'active' }
        
        # Build basic response
        $Results = @{
            currentTier = $Tier
            status = $Status
        }
        
        # Add subscription started date if available
        if ($UserData.PSObject.Properties['SubscriptionStartedAt']) {
            $Results.subscriptionStartedAt = $UserData.SubscriptionStartedAt
        } else {
            # Use account creation timestamp as fallback
            if ($UserData.Timestamp) {
                $Results.subscriptionStartedAt = $UserData.Timestamp.ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }
        
        # Add additional billing info if on paid tier and available
        if ($Tier -ne 'free') {
            if ($UserData.PSObject.Properties['BillingCycle']) {
                $Results.billingCycle = $UserData.BillingCycle
            }
            
            if ($UserData.PSObject.Properties['NextBillingDate']) {
                $Results.nextBillingDate = $UserData.NextBillingDate
            }
            
            if ($UserData.PSObject.Properties['SubscriptionAmount']) {
                $Results.amount = $UserData.SubscriptionAmount
            }
            
            if ($UserData.PSObject.Properties['SubscriptionCurrency']) {
                $Results.currency = $UserData.SubscriptionCurrency
            } else {
                $Results.currency = 'USD'
            }
            
            if ($UserData.PSObject.Properties['CancelledAt']) {
                $Results.cancelledAt = $UserData.CancelledAt
            }
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
