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
        
        # Clear cookies by setting Max-Age to 0 using Set-Cookie headers
        $Headers = @{
            'Set-Cookie' = @(
                "accessToken=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0"
                "refreshToken=; Path=/api/public/RefreshToken; HttpOnly; Secure; SameSite=Strict; Max-Age=0"
            )
        }
        
    } catch {
        Write-Error "Logout error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Logout failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Headers = @{}
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers = $Headers
        Body = $Results
    }
}
