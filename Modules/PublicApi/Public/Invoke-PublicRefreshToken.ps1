function Invoke-PublicRefreshToken {
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
        # Validate refresh token from database
        $TokenRecord = Get-RefreshToken -Token $Body.refreshToken
        
        if (-not $TokenRecord) {
            # Log invalid refresh token attempt
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-SecurityEvent -EventType 'RefreshTokenFailed' -IpAddress $ClientIP -Endpoint 'public/refreshToken' -Metadata @{
                Reason = 'InvalidOrExpiredToken'
            }
            
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
        
        # Get roles and permissions
        $Roles = if ($User.Roles) {
            if ($User.Roles -is [array]) { $User.Roles } else { @($User.Roles) }
        } else {
            @('user')
        }
        
        $Permissions = if ($User.Permissions) {
            if ($User.Permissions -is [array]) { $User.Permissions } else { @($User.Permissions) }
        } else {
            Get-DefaultRolePermissions -Role $Roles[0]
        }
        
        # Generate new access token
        $NewAccessToken = New-LinkToMeJWT -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -Roles $Roles -Permissions $Permissions -CompanyId $User.CompanyId
        
        # Generate new refresh token (rotation)
        $NewRefreshToken = New-RefreshToken
        
        # Invalidate old refresh token
        Remove-RefreshToken -Token $Body.refreshToken
        
        # Store new refresh token (7 days expiration)
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $NewRefreshToken -UserId $User.RowKey -ExpiresAt $ExpiresAt
        
        # Log successful token refresh
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'TokenRefreshed' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/refreshToken'
        
        $Results = @{
            accessToken = $NewAccessToken
            refreshToken = $NewRefreshToken
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Token refresh error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Token refresh failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
