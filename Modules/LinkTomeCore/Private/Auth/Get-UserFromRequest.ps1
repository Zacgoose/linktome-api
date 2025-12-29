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
    
    # Get auth cookie from Cookie header (Azure Functions PowerShell doesn't populate $Request.Cookies)
    $AuthCookieValue = $null
    
    if ($Request.Headers -and $Request.Headers.Cookie) {
        $CookieHeader = $Request.Headers.Cookie
        
        # Parse Cookie header to extract auth cookie
        $Cookies = $CookieHeader -split ';' | ForEach-Object { $_.Trim() }
        foreach ($Cookie in $Cookies) {
            if ($Cookie -match '^auth=(.+)$') {
                $AuthCookieValue = $Matches[1]
                break
            }
        }
    }
    
    if (-not $AuthCookieValue) {
        return $null
    }
    
    # URL decode if needed
    if ($AuthCookieValue -match '%') {
        $AuthCookieValue = [System.Web.HttpUtility]::UrlDecode($AuthCookieValue)
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