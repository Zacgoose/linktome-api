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
        $User = Get-AzDataTableEntity @Table -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        
        # Get client IP for logging
        $ClientIP = $Request.Headers.'X-Forwarded-For'
        if (-not $ClientIP) {
            $ClientIP = $Request.Headers.'X-Real-IP'
        }
        if (-not $ClientIP) {
            $ClientIP = 'unknown'
        }
        if ($ClientIP -like '*,*') {
            $ClientIP = ($ClientIP -split ',')[0].Trim()
        }
        
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
        
        $Token = New-LinkToMeJWT -UserId $User.RowKey -Email $User.PartitionKey -Username $User.Username
        
        $Results = @{
            user = @{
                userId = $User.RowKey
                email = $User.PartitionKey
                username = $User.Username
            }
            accessToken = $Token
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