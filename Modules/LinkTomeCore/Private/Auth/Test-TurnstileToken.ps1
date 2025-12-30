function Test-TurnstileToken {
    <#
    .SYNOPSIS
        Validates a Cloudflare Turnstile token
    .PARAMETER Token
        The turnstile token from the client
    .PARAMETER RemoteIP
        The client's IP address (optional but recommended)
    .RETURNS
        $true if valid, $false otherwise
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Token,
        
        [Parameter()]
        [string]$RemoteIP
    )
    
    # Skip validation in development if no secret key configured
    if (-not $env:TURNSTILE_SECRET_KEY) {
        Write-Warning "TURNSTILE_SECRET_KEY not configured - skipping validation"
        return $true
    }
    
    # Cloudflare test keys for development (always pass/fail)
    # Secret: 1x0000000000000000000000000000000AA - always passes
    # Secret: 2x0000000000000000000000000000000AA - always fails
    
    try {
        $Body = @{
            secret   = $env:TURNSTILE_SECRET_KEY
            response = $Token
        }
        
        if ($RemoteIP) {
            $Body.remoteip = $RemoteIP
        }
        
        $Response = Invoke-RestMethod `
            -Uri 'https://challenges.cloudflare.com/turnstile/v0/siteverify' `
            -Method Post `
            -Body $Body `
            -ContentType 'application/x-www-form-urlencoded' `
            -ErrorAction Stop
        
        if ($Response.success -eq $true) {
            return $true
        }
        
        Write-Warning "Turnstile validation failed: $($Response.'error-codes' -join ', ')"
        return $false
        
    }
    catch {
        Write-Error "Turnstile API error: $($_.Exception.Message)"
        # Fail open or closed based on your preference
        # For denial-of-wallet protection, fail closed is safer
        return $false
    }
}