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
        
        # Check if user has an active subscription
        $Tier = if ($UserData.PSObject.Properties['SubscriptionTier']) { $UserData.SubscriptionTier } else { 'free' }
        
        if ($Tier -eq 'free') {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "No active subscription to cancel" }
            }
        }
        
        # This is a stub implementation - payment processing not implemented
        # In a full implementation, this would:
        # 1. Call Stripe API to cancel subscription
        # 2. Mark subscription as cancelled but keep active until end of billing period
        # 3. Send confirmation email
        # 4. Store cancellation date
        
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'SubscriptionCancellationRequested' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/cancelSubscription'
        
        $Results = @{
            message = "Subscription cancellation requested"
            note = "Payment processing not yet implemented. Contact support to cancel your subscription."
            currentTier = $Tier
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
