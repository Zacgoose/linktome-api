function Invoke-AdminApikeysUpdate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        update:apiauth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body
    $KeyId = $Request.Query.keyId
    
    if (-not $KeyId) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "keyId query parameter required" }
        }
    }
    
    if ($null -eq $Body.permissions) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "permissions array required" }
        }
    }
    
    # Validate permissions
    $AvailablePermissions = Get-UserAvailablePermissions -UserId $User.UserId
    
    foreach ($Perm in $Body.permissions) {
        if ($Perm -notin $AvailablePermissions) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ 
                    error = "Cannot grant permission '$Perm'"
                    availablePermissions = $AvailablePermissions
                }
            }
        }
    }
    
    $Result = Update-ApiKeyPermissions -UserId $User.UserId -KeyId $KeyId -Permissions @($Body.permissions)
    
    if ($Result.Success) {
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'ApiKeyUpdated' -UserId $User.UserId -IpAddress $ClientIP `
            -Endpoint 'admin/apikeys/update' -Reason "KeyId: $KeyId, Permissions: $($Body.permissions -join ',')"
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ message = "Permissions updated" }
        }
    } else {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::NotFound
            Body = @{ error = $Result.Error }
        }
    }
}