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
            fontFamily = if ($UserData.FontFamily) { $UserData.FontFamily } else { 'default' }
            layoutStyle = if ($UserData.LayoutStyle) { $UserData.LayoutStyle } else { 'centered' }
            colors = @{
                primary = if ($UserData.ColorPrimary) { $UserData.ColorPrimary } else { '#000000' }
                secondary = if ($UserData.ColorSecondary) { $UserData.ColorSecondary } else { '#666666' }
                background = if ($UserData.ColorBackground) { $UserData.ColorBackground } else { '#ffffff' }
                buttonBackground = if ($UserData.ColorButtonBackground) { $UserData.ColorButtonBackground } else { '#000000' }
                buttonText = if ($UserData.ColorButtonText) { $UserData.ColorButtonText } else { '#ffffff' }
            }
        }
        
        # Add customGradient if it exists
        if ($UserData.CustomGradientStart -and $UserData.CustomGradientEnd) {
            $Results.customGradient = @{
                start = $UserData.CustomGradientStart
                end = $UserData.CustomGradientEnd
            }
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
