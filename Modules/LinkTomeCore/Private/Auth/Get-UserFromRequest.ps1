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
        Write-Verbose "No auth cookie found in request"
        return $null
    }
    
    # URL decode if needed (Azure Functions may pass encoded values)
    if ($AuthCookieValue -match '%') {
        $AuthCookieValue = [System.Web.HttpUtility]::UrlDecode($AuthCookieValue)
    }
    
    # Parse JSON from cookie to get accessToken
    try {
        $AuthData = $AuthCookieValue | ConvertFrom-Json
        $Token = $AuthData.accessToken
    } catch {
        Write-Warning "Failed to parse auth cookie: $($_.Exception.Message)"
        Write-Verbose "Auth cookie value: $AuthCookieValue"
        return $null
    }
    
    if (-not $Token) {
        Write-Verbose "No accessToken found in auth cookie"
        return $null
    }
    
    # Validate JWT token
    $User = Test-LinkToMeJWT -Token $Token
    
    return $User
}