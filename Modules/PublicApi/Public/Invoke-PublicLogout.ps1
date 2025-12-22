function Invoke-PublicLogout {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public.Auth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body

    if (-not $Body.refreshToken) {
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
        $Removed = Remove-RefreshToken -Token $Body.refreshToken
        
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

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
