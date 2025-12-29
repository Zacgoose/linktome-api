function Get-UserFromRequest {
    <#
    .SYNOPSIS
        Extract and validate user from request auth cookie
    .DESCRIPTION
        Reads accessToken from HTTP-only auth cookie (JSON format)
    #>
    param(
        [Parameter(Mandatory)]
        $Request
    )
    
    # Get auth cookie (contains both tokens as JSON)
    $AuthCookieValue = $Request.Cookies.auth
    
    if (-not $AuthCookieValue) {
        return $null
    }
    
    # Parse JSON from cookie to get accessToken
    try {
        $AuthData = $AuthCookieValue | ConvertFrom-Json
        $Token = $AuthData.accessToken
    } catch {
        Write-Warning "Failed to parse auth cookie: $($_.Exception.Message)"
        return $null
    }
    
    if (-not $Token) {
        return $null
    }
    
    # Validate JWT token
    $User = Test-LinkToMeJWT -Token $Token
    
    return $User
}