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
        
    } catch {
        Write-Error "Logout error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Logout failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Return response without [HttpResponseContext] cast to allow proper cookie handling
    # Use plain hashtable with cookies array to clear cookies
    return @{
        StatusCode = $StatusCode
        Body = $Results
        Cookies = @(
            @{
                Name = 'accessToken'
                Value = ''
                Path = '/'
                HttpOnly = $true
                Secure = $true
                SameSite = 'Strict'
                MaxAge = 0
            }
            @{
                Name = 'refreshToken'
                Value = ''
                Path = '/api/public/RefreshToken'
                HttpOnly = $true
                Secure = $true
                SameSite = 'Strict'
                MaxAge = 0
            }
        )
    }
}
