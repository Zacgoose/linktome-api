function Invoke-AdminApikeysDelete {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        delete:apiauth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $KeyId = $Request.Query.keyId
    
    if (-not $KeyId) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "keyId query parameter required" }
        }
    }
    
    $Result = Remove-ApiKey -UserId $User.UserId -KeyId $KeyId
    
    if ($Result.Success) {
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'ApiKeyDeleted' -UserId $User.UserId -IpAddress $ClientIP `
            -Endpoint 'admin/apikeysdelete' -Reason "KeyId: $KeyId"
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ message = "API key deleted" }
        }
    } else {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::NotFound
            Body = @{ error = $Result.Error }
        }
    }
}