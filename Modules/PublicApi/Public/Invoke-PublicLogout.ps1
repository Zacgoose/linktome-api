function Invoke-PublicLogout {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Get refresh token from auth cookie (JSON format)
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
        Write-Information "Parsing auth cookie from Cookie header"
        
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
        Write-Information "No auth cookie found in request"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "Missing auth cookie" 
            }
        }
    }
    
    # Parse JSON from cookie to get refreshToken
    $RefreshTokenValue = $null
    try {
        Write-Information "Parsing auth cookie JSON for logout"
        $AuthData = $AuthCookieValue | ConvertFrom-Json
        $RefreshTokenValue = $AuthData.refreshToken
        Write-Information "Successfully extracted refreshToken from auth cookie"
    } catch {
        Write-Information "Failed to parse auth cookie: $($_.Exception.Message)"
        # Continue with logout even if we can't parse the token
    }
    
    if (-not $RefreshTokenValue) {
        Write-Information "No refreshToken found in auth cookie, clearing cookie anyway"
        # Still clear the cookie even if we can't get the token
    }

    try {
        # Invalidate refresh token if we have it
        if ($RefreshTokenValue) {
            $Removed = Remove-RefreshToken -Token $RefreshTokenValue
        } else {
            $Removed = $false
        }
        
        # Log logout event
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'Logout' -IpAddress $ClientIP -Endpoint 'public/logout' -Success $Removed
        
        $Results = @{
            success = $true
        }
        $StatusCode = [HttpStatusCode]::OK
        
        # Clear the auth cookie by setting Max-Age to 0
        $CookieHeader = "auth=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0"
        
        Write-Information "Clearing auth cookie for logout"
        
        # Return response using HttpResponseContext
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
            Headers = @{
                'Set-Cookie' = $CookieHeader
            }
        }
        
    } catch {
        Write-Error "Logout error: $($_.Exception.Message)"
        Write-Information "Logout error details: $($_.Exception | ConvertTo-Json -Depth 5)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Logout failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
        
        # Return error response without cookies
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
        }
    }
}
