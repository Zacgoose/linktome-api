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
        
        # Get all users (including free tier)
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $AllUsers = Get-LinkToMeAzDataTableEntity @UsersTable
        
        foreach ($User in $AllUsers) {
            try {
                # Get subscription details
                $Subscription = Get-UserSubscription -User $User

                # Determine tier to enforce
                $TierToEnforce = $User.SubscriptionTier
                if ($User.PSObject.Properties['IsSubAccount'] -and $User.IsSubAccount -eq $true) {
                    try {
                        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
                        $SafeSubId = Protect-TableQueryValue -Value $User.RowKey
                        $Relationship = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "RowKey eq '$SafeSubId'" | Select-Object -First 1
                        if ($Relationship) {
                            $ParentUserId = $Relationship.PartitionKey
                            $UsersTable = Get-LinkToMeTable -TableName 'Users'
                            $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
                            $ParentUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeParentId'" | Select-Object -First 1
                            if ($ParentUser) {
                                $TierToEnforce = $ParentUser.SubscriptionTier
                            }
                        }
                    } catch {
                        Write-Warning "Failed to get parent tier for sub-account $($User.RowKey): $($_.Exception.Message)"
                    }
                }

                # Always enforce correct features for current tier
                try {
                    $CleanupResult = Invoke-FeatureCleanup -UserId $User.RowKey -NewTier $TierToEnforce
                    Write-Information "Feature cleanup for $($User.RowKey): $($CleanupResult.cleanupActions.Count) actions (tier: $TierToEnforce)"
                } catch {
                    Write-Warning "Feature cleanup failed for $($User.RowKey): $($_.Exception.Message)"
                }

                # Only downgrade if not sub-account and subscription is not active
                if (-not ($User.PSObject.Properties['IsSubAccount'] -and $User.IsSubAccount -eq $true)) {
                    if (-not $Subscription.HasAccess) {
                        $ShouldDowngrade = $false
                        $Reason = ""
                        if ($Subscription.IsCancelled -and -not $Subscription.HasAccess) {
                            $ShouldDowngrade = $true
                            $Reason = "Cancelled subscription past end date"
                        }
                        if ($Subscription.IsExpired) {
                            $ShouldDowngrade = $true
                            $Reason = "Subscription expired"
                        }
                        if ($Subscription.IsSuspended) {
                            $ShouldDowngrade = $true
                            $Reason = "Payment failed - subscription suspended"
                        }
                        if ($ShouldDowngrade) {
                            Write-Information "Downgrading user $($User.RowKey): $Reason"
                            $User.SubscriptionTier = 'free'
                            $User.SubscriptionStatus = 'expired'
                            if ($User.PSObject.Properties['StripeSubscriptionId']) {
                                $User.StripeSubscriptionId = $null
                            }
                            $NowString = $Now.ToString('yyyy-MM-ddTHH:mm:ssZ')
                            if (-not ($User.PSObject.Properties['CancelledAt'] -and $User.CancelledAt)) {
                                if (-not $User.PSObject.Properties['CancelledAt']) {
                                    $User | Add-Member -NotePropertyName 'CancelledAt' -NotePropertyValue $NowString -Force
                                } else {
                                    $User.CancelledAt = $NowString
                                }
                            }
                            Add-LinkToMeAzDataTableEntity @UsersTable -Entity $User -Force
                            Write-SecurityEvent -EventType 'SubscriptionAutoDowngraded' -UserId $User.RowKey -Reason $Reason
                            $ProcessedCount++
                        }
                    }
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
