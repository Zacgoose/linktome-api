function Invoke-AdminApikeysCreate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        create:apiauth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body
    
    if (-not $Body.name) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "name is required" }
        }
    }
    
    # Limit keys per user
    $ExistingKeys = Get-UserApiKeys -UserId $User.UserId
    if ($ExistingKeys.Count -ge 10) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Maximum 10 API keys allowed" }
        }
    }
    
    # Get user's available permissions (for validation)
    $AvailablePermissions = Get-UserAvailablePermissions -UserId $User.UserId
    
    # Validate requested permissions
    $RequestedPermissions = @()
    if ($Body.permissions) {
        $RequestedPermissions = @($Body.permissions)
        
        foreach ($Perm in $RequestedPermissions) {
            if ($Perm -notin $AvailablePermissions) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ 
                        error = "Cannot grant permission '$Perm' - not available to your account"
                        availablePermissions = $AvailablePermissions
                    }
                }
            }
        }
    }
    
    try {
        $NewKey = New-ApiKey -UserId $User.UserId -Name $Body.name -Permissions $RequestedPermissions
        
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'ApiKeyCreated' -UserId $User.UserId -IpAddress $ClientIP `
            -Endpoint 'admin/apikeys/create' -Reason "KeyId: $($NewKey.keyId), Permissions: $($RequestedPermissions -join ',')"
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Created
            Body = @{
                message = "API key created. Save this key now - it won't be shown again!"
                key     = $NewKey
            }
        }
    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{ error = "Failed to create key: $($_.Exception.Message)" }
        }
    }
}