function Start-SubscriptionCleanup {
    <#
    .SYNOPSIS
        Process expired subscriptions and downgrade accounts
    .DESCRIPTION
        Timer function to check for expired subscriptions and downgrade accounts to free tier.
        This handles cases where a subscription has expired but the webhook wasn't received,
        or where a cancelled subscription has reached its end date.
    .FUNCTIONALITY
        Timer
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Information "Starting subscription cleanup process"
        
        $Now = (Get-Date).ToUniversalTime()
        $ProcessedCount = 0
        $ErrorCount = 0
        
        # Get all users with paid subscriptions
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $AllUsers = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "SubscriptionTier ne 'free'"
        
        foreach ($User in $AllUsers) {
            try {
                # Skip sub-accounts (they inherit from parent)
                if ($User.PSObject.Properties['IsSubAccount'] -and $User.IsSubAccount -eq $true) {
                    continue
                }
                
                # Get subscription details
                $Subscription = Get-UserSubscription -User $User
                
                # Skip if subscription is still active with access
                if ($Subscription.HasAccess) {
                    continue
                }
                
                # Check if user needs to be downgraded
                $ShouldDowngrade = $false
                $Reason = ""
                
                # Case 1: Subscription is cancelled and past the billing date
                if ($Subscription.IsCancelled -and -not $Subscription.HasAccess) {
                    $ShouldDowngrade = $true
                    $Reason = "Cancelled subscription past end date"
                }
                
                # Case 2: Subscription is expired
                if ($Subscription.IsExpired) {
                    $ShouldDowngrade = $true
                    $Reason = "Subscription expired"
                }
                
                # Case 3: Subscription is suspended (payment failed)
                if ($Subscription.IsSuspended) {
                    $ShouldDowngrade = $true
                    $Reason = "Payment failed - subscription suspended"
                }
                
                # Downgrade if needed
                if ($ShouldDowngrade) {
                    Write-Information "Downgrading user $($User.RowKey): $Reason"
                    
                    # Update user to free tier
                    $User.SubscriptionTier = 'free'
                    $User.SubscriptionStatus = 'expired'
                    
                    # Clear Stripe IDs if present
                    if ($User.PSObject.Properties['StripeSubscriptionId']) {
                        $User.StripeSubscriptionId = $null
                    }
                    
                    # Set cancellation date if not already set
                    $NowString = $Now.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    if (-not ($User.PSObject.Properties['CancelledAt'] -and $User.CancelledAt)) {
                        if (-not $User.PSObject.Properties['CancelledAt']) {
                            $User | Add-Member -NotePropertyName 'CancelledAt' -NotePropertyValue $NowString -Force
                        } else {
                            $User.CancelledAt = $NowString
                        }
                    }
                    
                    # Save user changes
                    Add-LinkToMeAzDataTableEntity @UsersTable -Entity $User -Force
                    
                    # Clean up features
                    try {
                        $CleanupResult = Invoke-FeatureCleanup -UserId $User.RowKey -NewTier 'free'
                        Write-Information "Feature cleanup for $($User.RowKey): $($CleanupResult.cleanupActions.Count) actions"
                    } catch {
                        Write-Warning "Feature cleanup failed for $($User.RowKey): $($_.Exception.Message)"
                    }
                    
                    # Log security event
                    Write-SecurityEvent -EventType 'SubscriptionAutoDowngraded' -UserId $User.RowKey -Reason $Reason
                    
                    $ProcessedCount++
                }
                
            } catch {
                Write-Warning "Error processing user $($User.RowKey): $($_.Exception.Message)"
                $ErrorCount++
            }
        }
        
        Write-Information "Subscription cleanup completed: $ProcessedCount users downgraded, $ErrorCount errors"
        return @{
            Status = "Success"
            Message = "Subscription cleanup completed"
            ProcessedCount = $ProcessedCount
            ErrorCount = $ErrorCount
        }
    } catch {
        Write-Warning "Subscription cleanup failed: $($_.Exception.Message)"
        throw
    }
}
