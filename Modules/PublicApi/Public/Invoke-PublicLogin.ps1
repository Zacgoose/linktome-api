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
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }
        
        $Valid = Test-PasswordHash -Password $Body.password -StoredHash $User.PasswordHash -StoredSalt $User.PasswordSalt
        
        if (-not $Valid) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body = @{ error = "Invalid credentials" }
            }
        }
        
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