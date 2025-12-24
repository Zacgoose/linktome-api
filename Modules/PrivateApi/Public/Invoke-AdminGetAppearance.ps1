function Invoke-AdminGetAppearance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:appearance
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get user data
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Return appearance settings
        # These fields can be customized by the user later
        $Results = @{
            theme = if ($UserData.Theme) { $UserData.Theme } else { 'light' }
            buttonStyle = if ($UserData.ButtonStyle) { $UserData.ButtonStyle } else { 'rounded' }
            backgroundColor = if ($UserData.BackgroundColor) { $UserData.BackgroundColor } else { '#ffffff' }
            textColor = if ($UserData.TextColor) { $UserData.TextColor } else { '#000000' }
            buttonColor = if ($UserData.ButtonColor) { $UserData.ButtonColor } else { '#000000' }
            buttonTextColor = if ($UserData.ButtonTextColor) { $UserData.ButtonTextColor } else { '#ffffff' }
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get appearance error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get appearance"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
