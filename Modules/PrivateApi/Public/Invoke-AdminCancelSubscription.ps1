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
        
        # Check if already cancelled
        $CurrentStatus = if ($UserData.PSObject.Properties['SubscriptionStatus']) { $UserData.SubscriptionStatus } else { 'active' }
        if ($CurrentStatus -eq 'cancelled') {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Subscription is already cancelled" }
            }
        }
        
        # Get current timestamp
        $Now = (Get-Date).ToUniversalTime()
        $NowString = $Now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        
        # Mark subscription as cancelled
        $UserData.SubscriptionStatus = 'cancelled'
        
        # Set cancellation timestamp
        if (-not $UserData.PSObject.Properties['CancelledAt']) {
            $UserData | Add-Member -NotePropertyName 'CancelledAt' -NotePropertyValue $NowString -Force
        } else {
            $UserData.CancelledAt = $NowString
        }
        
        # Get access until date (next billing date or now if not set)
        $AccessUntil = if ($UserData.PSObject.Properties['NextBillingDate'] -and $UserData.NextBillingDate) {
            $UserData.NextBillingDate
        } else {
            $NowString
        }
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'SubscriptionCancelled' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/cancelSubscription'
        
        $Results = @{
            message = "Subscription cancelled successfully"
            tier = $Tier
            status = 'cancelled'
            cancelledAt = $NowString
            accessUntil = $AccessUntil
        }
        
        # Add note about continued access if there's a future billing date
        if ($AccessUntil -ne $NowString) {
            $Results.note = "You can continue using $Tier features until $AccessUntil"
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
