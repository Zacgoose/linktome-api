function Invoke-PublicSignup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public.Auth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body

    if (-not $Body.email -or -not $Body.username -or -not $Body.password) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Email, username, and password required" }
        }
    }

    # Validate email format
    if (-not (Test-EmailFormat -Email $Body.email)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid email format" }
        }
    }

    # Validate username format
    if (-not (Test-UsernameFormat -Username $Body.username)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Username must be 3-30 characters and contain only letters, numbers, underscore, or hyphen" }
        }
    }

    # Validate password strength
    $PasswordCheck = Test-PasswordStrength -Password $Body.password
    if (-not $PasswordCheck.Valid) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = $PasswordCheck.Message }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get client IP for logging
        $ClientIP = Get-ClientIPAddress -Request $Request
        
        # Check if email exists - sanitize for query
        $SafeEmail = Protect-TableQueryValue -Value $Body.email.ToLower()
        $ExistingEmail = Get-AzDataTableEntity @Table -Filter "PartitionKey eq '$SafeEmail'" | Select-Object -First 1
        if ($ExistingEmail) {
            # Log failed signup attempt
            Write-SecurityEvent -EventType 'SignupFailed' -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup' -Reason 'EmailAlreadyRegistered'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Conflict
                Body = @{ error = "Email already registered" }
            }
        }
        
        # Check if username exists - sanitize for query
        $SafeUsername = Protect-TableQueryValue -Value $Body.username.ToLower()
        $ExistingUsername = Get-AzDataTableEntity @Table -Filter "Username eq '$SafeUsername'" | Select-Object -First 1
        if ($ExistingUsername) {
            # Log failed signup attempt
            Write-SecurityEvent -EventType 'SignupFailed' -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup' -Reason 'UsernameAlreadyTaken'
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Conflict
                Body = @{ error = "Username already taken" }
            }
        }
        
        # Create user
        $PasswordData = New-PasswordHash -Password $Body.password
        $UserId = 'user-' + (New-Guid).ToString()
        
        $NewUser = @{
            PartitionKey = $Body.email.ToLower()
            RowKey = $UserId
            Username = $Body.username.ToLower()
            DisplayName = $Body.username
            Bio = ''
            Avatar = "https://ui-avatars.com/api/?name=$($Body.username)&size=200"
            PasswordHash = $PasswordData.Hash
            PasswordSalt = $PasswordData.Salt
            IsActive = $true
        }
        
        Add-AzDataTableEntity @Table -Entity $NewUser -Force
        
        # Log successful signup
        Write-SecurityEvent -EventType 'SignupSuccess' -UserId $UserId -Email $Body.email -Username $Body.username -IpAddress $ClientIP -Endpoint 'public/signup'
        
        $Token = New-LinkToMeJWT -UserId $UserId -Email $Body.email.ToLower() -Username $Body.username.ToLower()
        
        $Results = @{
            user = @{
                userId = $UserId
                email = $Body.email.ToLower()
                username = $Body.username.ToLower()
            }
            accessToken = $Token
        }
        $StatusCode = [HttpStatusCode]::Created
        
    } catch {
        Write-Error "Signup error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Signup failed"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}