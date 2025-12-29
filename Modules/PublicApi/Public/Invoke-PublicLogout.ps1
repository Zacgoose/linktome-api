function Invoke-PublicLogout {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Try to get refresh token from cookie first
    $RefreshTokenValue = $Request.Cookies.refreshToken
    
    # Fallback to request body for backward compatibility
    if (-not $RefreshTokenValue -and $Request.Body.refreshToken) {
        $RefreshTokenValue = $Request.Body.refreshToken
    }

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
        
        # Clear cookies by setting MaxAge to 0
        $Cookies = @(
            @{
                Name = 'accessToken'
                Value = ''
                MaxAge = 0
                Path = '/'
                HttpOnly = $true
                Secure = $true
                SameSite = 'Strict'
            }
            @{
                Name = 'refreshToken'
                Value = ''
                MaxAge = 0
                Path = '/api/public/RefreshToken'
                HttpOnly = $true
                Secure = $true
                SameSite = 'Strict'
            }
        )
        
    } catch {
        Write-Error "Logout error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Logout failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Cookies = @()
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
        Cookies = $Cookies
    }
}
