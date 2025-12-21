function Get-JwtSecret {
    <#
    .SYNOPSIS
        Get JWT secret from environment or generate one for dev
    #>
    
    $Secret = $env:JWT_SECRET
    
    if (-not $Secret) {
        # For local dev, use a consistent secret (DO NOT use in production)
        Write-Warning "No JWT_SECRET found in environment. Using dev secret."
        $Secret = 'dev-secret-change-in-production-please-make-this-very-long-and-random'
    }
    
    return $Secret
}