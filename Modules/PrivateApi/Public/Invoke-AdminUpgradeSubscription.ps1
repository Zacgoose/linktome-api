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
    $ValidTiers = @('free', 'pro', 'premium', 'enterprise')
    if ($Body.tier -notin $ValidTiers) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid tier. Valid options are: free, pro, premium, enterprise" }
        }
    }

    # Validate billing cycle is provided for paid tiers
    if ($Body.tier -ne 'free' -and -not $Body.billingCycle) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Billing cycle is required for pro, premium and enterprise tiers" }
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
        
        # Get current timestamp for consistency
        $Now = (Get-Date).ToUniversalTime()
        $NowString = $Now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        
        # Update subscription tier
        $UserData.SubscriptionTier = $Body.tier
        
        # Update status - set to active when upgrading/changing, preserve if already cancelled
        $CurrentStatus = if ($UserData.PSObject.Properties['SubscriptionStatus']) { $UserData.SubscriptionStatus } else { 'active' }
        if ($CurrentStatus -ne 'cancelled') {
            $UserData.SubscriptionStatus = 'active'
        }
        
        # Set subscription started date if upgrading from free or changing tier
        $CurrentTier = if ($UserData.PSObject.Properties['SubscriptionTier']) { $UserData.SubscriptionTier } else { 'free' }
        if ($CurrentTier -ne $Body.tier) {
            if (-not $UserData.PSObject.Properties['SubscriptionStartedAt']) {
                $UserData | Add-Member -NotePropertyName 'SubscriptionStartedAt' -NotePropertyValue $NowString -Force
            } else {
                $UserData.SubscriptionStartedAt = $NowString
            }
        }
        
        # Update billing cycle for paid tiers
        if ($Body.tier -ne 'free' -and $Body.billingCycle) {
            if (-not $UserData.PSObject.Properties['BillingCycle']) {
                $UserData | Add-Member -NotePropertyName 'BillingCycle' -NotePropertyValue $Body.billingCycle -Force
            } else {
                $UserData.BillingCycle = $Body.billingCycle
            }
            
            # Calculate next billing date based on billing cycle using same base timestamp
            $NextBillingDate = if ($Body.billingCycle -eq 'annual') {
                $Now.AddYears(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
            } else {
                $Now.AddMonths(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            
            if (-not $UserData.PSObject.Properties['NextBillingDate']) {
                $UserData | Add-Member -NotePropertyName 'NextBillingDate' -NotePropertyValue $NextBillingDate -Force
            } else {
                $UserData.NextBillingDate = $NextBillingDate
            }
        } else {
            # Clear billing info for free tier
            if ($UserData.PSObject.Properties['BillingCycle']) {
                $UserData.BillingCycle = $null
            }
            if ($UserData.PSObject.Properties['NextBillingDate']) {
                $UserData.NextBillingDate = $null
            }
        }
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'SubscriptionUpgraded' -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/upgradeSubscription'
        
        $Results = @{
            message = "Subscription updated successfully"
            tier = $Body.tier
            status = 'active'
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
