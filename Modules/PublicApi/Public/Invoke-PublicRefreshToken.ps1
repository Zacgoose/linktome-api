function Invoke-PublicRefreshToken {
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
        # Validate refresh token from database
        $TokenRecord = Get-RefreshToken -Token $RefreshTokenValue
        
        if (-not $TokenRecord) {
            # Log invalid refresh token attempt
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-SecurityEvent -EventType 'RefreshTokenFailed' -IpAddress $ClientIP -Endpoint 'public/refreshToken' -Reason 'InvalidOrExpiredToken'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ 
                    success = $false
                    error = "Invalid or expired refresh token" 
                }
            }
        }
        
        # Get user with latest roles and permissions
        $Table = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $TokenRecord.UserId
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ 
                    success = $false
                    error = "User not found" 
                }
            }
        }
        
        try {
            $authContext = Get-UserAuthContext -User $User
        } catch {
            Write-Error "Auth context error: $($_.Exception.Message)"
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = @{ error = $_.Exception.Message }
            }
        }

        $NewAccessToken = New-LinkToMeJWT -User $User

        # Generate new refresh token (rotation)
        $NewRefreshToken = New-RefreshToken

        # Invalidate old refresh token
        Remove-RefreshToken -Token $RefreshTokenValue

        # Store new refresh token (7 days expiration)
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $NewRefreshToken -UserId $User.RowKey -ExpiresAt $ExpiresAt

        # Log successful token refresh
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'TokenRefreshed' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/refreshToken'

        $Results = @{
            user = @{
                UserId = $authContext.UserId
                email = $authContext.Email
                username = $authContext.Username
                userRole = $authContext.UserRole
                roles = $authContext.Roles
                permissions = $authContext.Permissions
                userManagements = $authContext.UserManagements
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        
        # Set HTTP-only cookies for new tokens using Set-Cookie headers
        $CookieHeader1 = "accessToken=$NewAccessToken; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=900"
        $CookieHeader2 = "refreshToken=$NewRefreshToken; Path=/api/public/RefreshToken; HttpOnly; Secure; SameSite=Strict; Max-Age=604800"
        
        Write-Information "Setting new cookies for refresh: $CookieHeader1 | $CookieHeader2"
        
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
            Headers = @{
                'Set-Cookie' = @($CookieHeader1, $CookieHeader2)
            }
        }
        
    } catch {
        Write-Error "Token refresh error: $($_.Exception.Message)"
        Write-Information "Token refresh error details: $($_.Exception | ConvertTo-Json -Depth 5)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Token refresh failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
        
        # Return error response without cookies
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
        }
    }
}
