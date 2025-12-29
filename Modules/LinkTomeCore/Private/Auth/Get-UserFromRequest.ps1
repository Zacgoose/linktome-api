function Get-UserFromRequest {
    <#
    .SYNOPSIS
        Extract and validate user from request cookie or Authorization header
    .DESCRIPTION
        Reads accessToken from cookie first (preferred), falls back to Authorization header for backward compatibility
    #>
    param(
        [Parameter(Mandatory)]
        $Request
    )
    
    # Try cookie first (preferred method)
    $Token = $Request.Cookies.accessToken
    
    # Fallback to Authorization header (for backward compatibility)
    if (-not $Token) {
        $AuthHeader = $Request.Headers.Authorization
        
        if ($AuthHeader -and $AuthHeader -match '^Bearer (.+)$') {
            $Token = $Matches[1]
        }
    }
    
    # No token found in either location
    if (-not $Token) {
        return $null
    }
    
    # Validate JWT token
    $User = Test-LinkTomeJWT -Token $Token
    
    return $User
}