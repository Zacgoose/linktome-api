function Invoke-AdminApikeysList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:apiauth
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    
    try {
        $Keys = Get-UserApiKeys -UserId $User.UserId
        $AvailablePermissions = Get-UserAvailablePermissions -UserId $User.UserId
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ 
                keys                 = @($Keys)
                availablePermissions = @($AvailablePermissions)
            }
        }
    }
    catch {
        Write-Error "List API keys error: $($_.Exception.Message)"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{ error = "Failed to list API keys" }
        }
    }
}