function Add-SecurityHeaders {
    <#
    .SYNOPSIS
        Add security headers to HTTP response
    .DESCRIPTION
        Adds standard security headers to protect against common web vulnerabilities
    .PARAMETER Response
        The HTTP response object to add headers to
    .EXAMPLE
        $Response = Add-SecurityHeaders -Response $Response
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Response
    )
    
    # Initialize headers if not present
    if (-not $Response.Headers) {
        $Response.Headers = @{}
    }
    
    # Prevent MIME type sniffing
    $Response.Headers['X-Content-Type-Options'] = 'nosniff'
    
    # Prevent clickjacking
    $Response.Headers['X-Frame-Options'] = 'DENY'
    
    # Enable XSS filter in browsers
    $Response.Headers['X-XSS-Protection'] = '1; mode=block'
    
    # Control referrer information
    $Response.Headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    # Only add HSTS in production with HTTPS
    if ($env:AZURE_FUNCTIONS_ENVIRONMENT -eq 'Production') {
        $Response.Headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    }
    
    # Set secure Content-Type
    if (-not $Response.Headers['Content-Type']) {
        $Response.Headers['Content-Type'] = 'application/json; charset=utf-8'
    }
    
    return $Response
}
