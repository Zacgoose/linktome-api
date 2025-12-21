function Add-CorsHeaders {
    <#
    .SYNOPSIS
        Add CORS headers to HTTP response
    .DESCRIPTION
        Adds CORS headers based on configured allowed origins
    .PARAMETER Response
        The HTTP response object to add headers to
    .PARAMETER Request
        The HTTP request object to check origin
    .EXAMPLE
        $Response = Add-CorsHeaders -Response $Response -Request $Request
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Response,
        
        [Parameter(Mandatory)]
        $Request
    )
    
    # Initialize headers if not present
    if (-not $Response.Headers) {
        $Response.Headers = @{}
    }
    
    # Get allowed origins from environment or use defaults
    $AllowedOriginsEnv = $env:CORS_ALLOWED_ORIGINS
    if ($AllowedOriginsEnv) {
        $AllowedOrigins = $AllowedOriginsEnv -split ','
    } else {
        # Default allowed origins
        $AllowedOrigins = @(
            'http://localhost:3000',
            'http://localhost:5173'
        )
    }
    
    $Origin = $Request.Headers.Origin
    
    if ($Origin -and ($Origin -in $AllowedOrigins)) {
        $Response.Headers['Access-Control-Allow-Origin'] = $Origin
        $Response.Headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        $Response.Headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
        $Response.Headers['Access-Control-Max-Age'] = '86400'
        $Response.Headers['Access-Control-Allow-Credentials'] = 'true'
    }
    
    return $Response
}
