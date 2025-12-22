function Invoke-PublicLogin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public.Auth
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
            Write-SecurityEvent -EventType 'LoginFailed' -Email $Body.email -IpAddress $ClientIP -Endpoint 'public/login' -Metadata @{
                Reason = 'UserNotFound'
            }
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }
        
        $Valid = Test-PasswordHash -Password $Body.password -StoredHash $User.PasswordHash -StoredSalt $User.PasswordSalt
        
        if (-not $Valid) {
            # Log failed login attempt
            Write-SecurityEvent -EventType 'LoginFailed' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/login' -Metadata @{
                Reason = 'InvalidPassword'
            }
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }
        
        # Log successful login
        Write-SecurityEvent -EventType 'LoginSuccess' -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -IpAddress $ClientIP -Endpoint 'public/login'
        
        # Get roles and permissions (deserialize from JSON if needed)
        $Roles = if ($User.Roles) {
            if ($User.Roles -is [string] -and $User.Roles.StartsWith('[')) {
                $User.Roles | ConvertFrom-Json
            } elseif ($User.Roles -is [array]) {
                $User.Roles
            } else {
                @($User.Roles)
            }
        } else {
            @('user')
        }
        
        $Permissions = if ($User.Permissions) {
            if ($User.Permissions -is [string] -and $User.Permissions.StartsWith('[')) {
                $User.Permissions | ConvertFrom-Json
            } elseif ($User.Permissions -is [array]) {
                $User.Permissions
            } else {
                @($User.Permissions)
            }
        } else {
            Get-DefaultRolePermissions -Role $Roles[0]
        }
        
        $Token = New-LinkToMeJWT -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username -Roles $Roles -Permissions $Permissions -CompanyId $User.CompanyId
        
        # Generate refresh token
        $RefreshToken = New-RefreshToken
        $ExpiresAt = (Get-Date).ToUniversalTime().AddDays(7)
        Save-RefreshToken -Token $RefreshToken -UserId $User.RowKey -ExpiresAt $ExpiresAt
        
        $Results = @{
            user = @{
                userId = $User.RowKey
                email = $User.PartitionKey
                username = $User.Username
                roles = $Roles
                permissions = $Permissions
            }
            accessToken = $Token
            refreshToken = $RefreshToken
        }

        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Login error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Login failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}