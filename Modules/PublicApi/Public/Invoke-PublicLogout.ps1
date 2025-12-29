function Invoke-PublicLogout {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Get refresh token from auth cookie (Cookie header)
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
        $AuthData = $AuthCookieValue | ConvertFrom-Json
        $RefreshTokenValue = $AuthData.refreshToken
    } catch {
        Write-Warning "Failed to parse auth cookie: $($_.Exception.Message)"
        # Continue with logout even if we can't parse the token
    }
    
    if (-not $RefreshTokenValue) {
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
        Write-SecurityEvent -EventType 'Logout' -IpAddress $ClientIP -Endpoint 'public/logout'
        
        $Results = @{
            success = $true
        }
        $StatusCode = [HttpStatusCode]::OK
        
        # Clear the auth cookie by setting Max-Age to 0
        $CookieHeader = "auth=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0"
        
        # Return response with cleared cookie
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
            Headers = @{
                'Set-Cookie' = $CookieHeader
            }
        }
        
    } catch {
        Write-Error "Logout error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Logout failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
        
        # Return error response without cookies
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
        }
    }
}
