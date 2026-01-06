function Invoke-AdminGetProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:profile
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize UserId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $filter = "RowKey eq '$SafeUserId'"
        $entities = Get-LinkToMeAzDataTableEntity @Table -Filter $filter
        $UserData = $entities | Select-Object -First 1

        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }

        # Get 2FA status
        $TwoFactorEmailEnabled = $UserData.TwoFactorEmailEnabled -eq $true
        $TwoFactorTotpEnabled = $UserData.TwoFactorTotpEnabled -eq $true
        $TwoFactorEnabled = $TwoFactorEmailEnabled -or $TwoFactorTotpEnabled
        
        # Get phone number if available
        $PhoneNumber = if ($UserData.PSObject.Properties['PhoneNumber']) { $UserData.PhoneNumber } else { $null }

        $Results = @{
            UserId = $UserData.RowKey
            username = $UserData.Username
            email = $UserData.PartitionKey
            displayName = $UserData.DisplayName
            bio = $UserData.Bio
            avatar = $UserData.Avatar
            phoneNumber = $PhoneNumber
            twoFactorEnabled = $TwoFactorEnabled
            twoFactorEmailEnabled = $TwoFactorEmailEnabled
            twoFactorTotpEnabled = $TwoFactorTotpEnabled
        }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        Write-Error "Get profile error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get profile"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}