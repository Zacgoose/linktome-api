function Invoke-PublicLogout {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Get refresh token from cookie
    $RefreshTokenValue = $Request.Cookies.refreshToken

    if (-not $RefreshTokenValue) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "Missing refresh token" 
            }
        }
    }

    try {
        # Invalidate refresh token
        $Removed = Remove-RefreshToken -Token $RefreshTokenValue
        
        # Log logout event
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'Logout' -IpAddress $ClientIP -Endpoint 'public/logout' -Success $Removed
        
        $Results = @{
            success = $true
        }
        $StatusCode = [HttpStatusCode]::OK
        
        # Clear cookies by setting Max-Age to 0
        $CookieHeader1 = "accessToken=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0"
        $CookieHeader2 = "refreshToken=; Path=/api/public/RefreshToken; HttpOnly; Secure; SameSite=Strict; Max-Age=0"
        
        Write-Information "Clearing cookies for logout: $CookieHeader1 | $CookieHeader2"
        
        # Return response as plain hashtable (NOT cast to [HttpResponseContext])
        return @{
            StatusCode = $StatusCode
            Body = $Results
            Headers = @{
                'Set-Cookie' = @($CookieHeader1, $CookieHeader2)
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
