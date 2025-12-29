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
    # Try multiple ways to access the cookie value
    $AuthCookieValue = $null
    
    # Method 1: Try Cookies collection
    if ($Request.Cookies -and $Request.Cookies.auth) {
        $AuthCookieValue = $Request.Cookies.auth
        Write-Information "Got auth cookie from Cookies collection"
    }
    # Method 2: Parse from Cookie header
    elseif ($Request.Headers -and $Request.Headers.Cookie) {
        $CookieHeader = $Request.Headers.Cookie
        Write-Information "Parsing auth cookie from Cookie header: $CookieHeader"
        
        # Parse Cookie header manually
        $Cookies = $CookieHeader -split ';' | ForEach-Object { $_.Trim() }
        foreach ($Cookie in $Cookies) {
            if ($Cookie -match '^auth=(.+)$') {
                $AuthCookieValue = $Matches[1]
                Write-Information "Extracted auth cookie value from header"
                break
            }
        }
    }
    
    if (-not $AuthCookieValue) {
        Write-Information "No auth cookie found in request (checked Cookies collection and Cookie header)"
        return $null
    }
    
    # URL decode if needed (Azure Functions may pass encoded values)
    if ($AuthCookieValue -match '%') {
        Write-Information "URL decoding auth cookie value"
        $AuthCookieValue = [System.Web.HttpUtility]::UrlDecode($AuthCookieValue)
    }
    
    # Parse JSON from cookie to get accessToken
    try {
        Write-Information "Parsing auth cookie JSON"
        $AuthData = $AuthCookieValue | ConvertFrom-Json
        $Token = $AuthData.accessToken
        Write-Information "Successfully extracted accessToken from auth cookie"
    } catch {
        Write-Warning "Failed to parse auth cookie: $($_.Exception.Message)"
        Write-Information "Auth cookie value: $AuthCookieValue"
        return $null
    }
    
    if (-not $Token) {
        Write-Warning "No accessToken found in auth cookie JSON"
        return $null
    }
    
    # Validate JWT token
    $User = Test-LinkToMeJWT -Token $Token
    
    return $User
}