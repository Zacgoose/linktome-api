function Get-TierFromPriceId {
    <#
    .SYNOPSIS
        Map Stripe price ID to tier name
    .PARAMETER PriceId
        The Stripe price ID
    #>
    param([string]$PriceId)
    
    # Map price IDs to tiers from environment variables
    # Monthly prices
    $ProPriceId = $env:STRIPE_PRICE_ID_PRO
    $PremiumPriceId = $env:STRIPE_PRICE_ID_PREMIUM
    $EnterprisePriceId = $env:STRIPE_PRICE_ID_ENTERPRISE
    
    # Annual prices
    $ProAnnualPriceId = $env:STRIPE_PRICE_ID_PRO_ANNUAL
    $PremiumAnnualPriceId = $env:STRIPE_PRICE_ID_PREMIUM_ANNUAL
    $EnterpriseAnnualPriceId = $env:STRIPE_PRICE_ID_ENTERPRISE_ANNUAL
    
    # Check monthly prices
    if ($PriceId -eq $ProPriceId -or $PriceId -eq $ProAnnualPriceId) {
        return 'pro'
    } elseif ($PriceId -eq $PremiumPriceId -or $PriceId -eq $PremiumAnnualPriceId) {
        return 'premium'
    } elseif ($PriceId -eq $EnterprisePriceId -or $PriceId -eq $EnterpriseAnnualPriceId) {
        return 'enterprise'
    } else {
        Write-Warning "Unknown price ID: $PriceId, defaulting to free tier"
        return 'free'
    }
}