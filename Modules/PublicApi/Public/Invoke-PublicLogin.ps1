function Invoke-PublicLogin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        auth:public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body

    if (-not $Body.email -or -not $Body.password) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Email and password required" }
        }
    }

    # Validate email format
    if (-not (Test-EmailFormat -Email $Body.email)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid email format" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize email for query to prevent injection
        $SafeEmail = Protect-TableQueryValue -Value $Body.email.ToLower()
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        
        # Get client IP for logging
        $ClientIP = Get-ClientIPAddress -Request $Request
        
        if (-not $User) {
            # Log failed login attempt
            Write-SecurityEvent -EventType 'LoginFailed' -Email $Body.email -IpAddress $ClientIP -Endpoint 'public/login' -Reason 'UserNotFound'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }
        
        $Valid = Test-PasswordHash -Password $Body.password -StoredHash $User.PasswordHash -StoredSalt $User.PasswordSalt
        
        if (-not $Valid) {
            # Log failed login attempt
            Write-SecurityEvent -EventType 'LoginFailed' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/login' -Reason 'InvalidPassword'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
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

        $Token = New-LinkToMeJWT -User $User

        # Generate refresh token
        $RefreshToken = New-RefreshToken
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $RefreshToken -UserId $User.RowKey -ExpiresAt $ExpiresAt

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
   
        # Log successful login
        Write-SecurityEvent -EventType 'LoginSuccess' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/login'
        
        # Set HTTP-only cookies for tokens using Set-Cookie headers
        # Azure Functions requires each Set-Cookie as a separate array element
        $Headers = @{
            'Set-Cookie' = @(
                "accessToken=$Token; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=900",
                "refreshToken=$RefreshToken; Path=/api/public/RefreshToken; HttpOnly; Secure; SameSite=Strict; Max-Age=604800"
            )
        }
        
    } catch {
        Write-Error "Login error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Login failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Headers = @{}
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers = $Headers
        Body = $Results
    }
}