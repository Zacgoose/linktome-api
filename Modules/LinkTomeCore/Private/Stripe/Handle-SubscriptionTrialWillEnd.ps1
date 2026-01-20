function Handle-SubscriptionTrialWillEnd {
    param([Parameter(Mandatory)][object]$Subscription)
    Write-Information "Stub: Handle-SubscriptionTrialWillEnd called for subscription $($Subscription.id)"
    return $true
}