function Get-ClientIPAddress {
    <#
    .SYNOPSIS
        Extract client IP address from request headers
    .DESCRIPTION
        Extracts the client IP address from X-Forwarded-For or X-Real-IP headers.
        Returns 'unknown' if no IP can be determined.
    .PARAMETER Request
        The HTTP request object
    .EXAMPLE
        $ClientIP = Get-ClientIPAddress -Request $Request
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Request
    )
    
    # Try X-Forwarded-For first (standard for proxies/load balancers)
    $ClientIP = $Request.Headers.'X-Forwarded-For'
    
    # Fall back to X-Real-IP if X-Forwarded-For is not present
    if (-not $ClientIP) {
        $ClientIP = $Request.Headers.'X-Real-IP'
    }
    
    # Default to 'unknown' if no IP found
    if (-not $ClientIP) {
        $ClientIP = 'unknown'
    }
    
    # Extract first IP if multiple IPs in X-Forwarded-For (client, proxy1, proxy2, ...)
    if ($ClientIP -like '*,*') {
        $ClientIP = ($ClientIP -split ',')[0].Trim()
    }
    
    return $ClientIP
}
