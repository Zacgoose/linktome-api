function Invoke-PublicRefreshToken {
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
            Body = @{ error = "Missing auth cookie" }
        }
    }
    
    # Parse JSON from cookie to get refreshToken
    try {
        $AuthData = $AuthCookieValue | ConvertFrom-Json
        $RefreshTokenValue = $AuthData.refreshToken
    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid auth cookie format" }
        }
    }

    if (-not $RefreshTokenValue) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Missing refresh token in auth cookie" }
        }
    }

    try {
        # Validate refresh token from database
        $TokenRecord = Get-RefreshToken -Token $RefreshTokenValue
        
        if (-not $TokenRecord) {
            $ClientIP = Get-ClientIPAddress -Request $Request
            
            # Rate limit failed refresh attempts by IP
            $FailedRefreshCheck = Test-RateLimit -Identifier "refresh-failed:$ClientIP" -Endpoint 'public/refreshToken-failed' `
                -MaxRequests 5 -WindowSeconds 300
            
            if (-not $FailedRefreshCheck.Allowed) {
                Write-SecurityEvent -EventType 'RefreshBruteForce' -IpAddress $ClientIP -Endpoint 'public/refreshToken'
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::TooManyRequests
                    Body = @{ error = "Too many failed attempts. Please log in again." }
                }
            }
            
            Write-SecurityEvent -EventType 'RefreshTokenFailed' -IpAddress $ClientIP -Endpoint 'public/refreshToken' -Reason 'InvalidOrExpiredToken'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid or expired refresh token" }
            }
        }
        
        # Get user with latest roles and permissions
        $Table = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $TokenRecord.UserId
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "User not found" }
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
                tier = $authContext.Tier
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        
        # Use single HTTP-only cookie with both new tokens as JSON
        # This avoids Azure Functions PowerShell limitations with multiple Set-Cookie headers
        $AuthData = @{
            accessToken = $NewAccessToken
            refreshToken = $NewRefreshToken
        } | ConvertTo-Json -Compress
        
        $CookieHeader = "auth=$AuthData; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=604800"
        
        # Return response with HTTP-only cookie containing refreshed tokens
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
            Headers = @{
                'Set-Cookie' = $CookieHeader
            }
        }
        
    } catch {
        Write-Error "Token refresh error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Token refresh failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
        
        # Return error response without cookies
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = $Results
        }
    }
}
