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

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Check if email exists
        $ExistingEmail = Get-AzDataTableEntity @Table -Filter "PartitionKey eq '$($Body.email.ToLower())'" | Select-Object -First 1
        if ($ExistingEmail) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Conflict
                Body = @{ error = "Email already registered" }
            }
        }
        
        # Check if username exists
        $ExistingUsername = Get-AzDataTableEntity @Table -Filter "Username eq '$($Body.username.ToLower())'" | Select-Object -First 1
        if ($ExistingUsername) {
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
        $Results = @{ error = "Signup failed" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}