function Get-JwtSecret {
    <#
    .SYNOPSIS
        Get JWT secret from environment or generate one for dev
    #>
    
    $Secret = $env:JWT_SECRET
    
    if (-not $Secret) {
        # For local dev, use a consistent secret (DO NOT use in production)
        if ($env:AZURE_FUNCTIONS_ENVIRONMENT -eq 'Production') {
            throw "JWT_SECRET environment variable must be configured in production"
        }
        Write-Warning "No JWT_SECRET found in environment. Using development secret."
        $Secret = 'dev-secret-change-in-production-please-make-this-very-long-and-random-at-least-64-characters'
    }
    
    # Enforce minimum length for security (64 characters = 512 bits for HS256)
    if ($Secret.Length -lt 64) {
        $Message = "JWT_SECRET must be at least 64 characters long (current: $($Secret.Length)). " +
                   "Generate a strong secret with: openssl rand -base64 96"
        
        if ($env:AZURE_FUNCTIONS_ENVIRONMENT -eq 'Production') {
            throw $Message
        } else {
            Write-Warning $Message
        }
    }
    
    return $Secret
}