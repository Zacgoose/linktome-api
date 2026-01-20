function Initialize-StripeClient {
    <#
    .SYNOPSIS
        Initialize Stripe API client with API key
    .DESCRIPTION
        Sets up the Stripe API client with the API key from environment variables.
        Must be called before making any Stripe API calls.
    .EXAMPLE
        Initialize-StripeClient
    #>
    [CmdletBinding()]
    param()
    
    try {
        $ApiKey = $env:STRIPE_API_KEY
        
        if (-not $ApiKey) {
            Write-Warning "STRIPE_API_KEY environment variable not set. Stripe integration will not work."
            return $false
        }
        
        # Initialize Stripe API key
        [Stripe.StripeConfiguration]::ApiKey = $ApiKey
        
        Write-Information "Stripe client initialized successfully"
        return $true
        
    } catch {
        Write-Error "Failed to initialize Stripe client: $($_.Exception.Message)"
        return $false
    }
}
