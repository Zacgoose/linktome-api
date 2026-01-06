function Invoke-AdminUpdatePhone {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:phone
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

    # Validate phone number if provided (can be empty to clear)
    if ($Body.PSObject.Properties['phoneNumber'] -and $Body.phoneNumber -ne '') {
        $LengthCheck = Test-InputLength -Value $Body.phoneNumber -MaxLength 20 -FieldName "Phone number"
        if (-not $LengthCheck.Valid) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = $LengthCheck.Message }
            }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get user record
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Update phone number (can be empty string to clear)
        $PhoneNumber = if ($Body.PSObject.Properties['phoneNumber']) { $Body.phoneNumber } else { '' }
        $UserData | Add-Member -NotePropertyName 'PhoneNumber' -NotePropertyValue ([string]$PhoneNumber) -Force
        
        # Save changes
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        # Log security event
        $ClientIP = Get-ClientIPAddress -Request $Request
        $Action = if ($PhoneNumber) { 'PhoneNumberUpdated' } else { 'PhoneNumberCleared' }
        Write-SecurityEvent -EventType $Action -UserId $UserId -IpAddress $ClientIP -Endpoint 'admin/updatePhone'
        
        $Results = @{
            message = "Phone number updated successfully"
            phoneNumber = $PhoneNumber
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Update phone error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update phone number"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
