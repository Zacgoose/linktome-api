function Invoke-AdminGetAppearance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:appearance
    .DESCRIPTION
        Returns the user's appearance settings including theme, header, wallpaper, buttons, text, and social icons.
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
        
        # Get social icons
        $SocialTable = Get-LinkToMeTable -TableName 'SocialIcons'
        $SocialIcons = @(Get-LinkToMeAzDataTableEntity @SocialTable -Filter "PartitionKey eq '$SafeUserId'" | ForEach-Object {
            @{
                id = $_.RowKey
                platform = $_.Platform
                url = $_.Url
                order = [int]$_.Order
                active = [bool]$_.Active
            }
        } | Sort-Object order)
        
        # Build appearance response with new structure
        $Results = @{
            # Theme
            theme = if ($UserData.Theme) { $UserData.Theme } else { 'custom' }
            customTheme = [bool]($UserData.CustomTheme -eq $true -or -not $UserData.Theme -or $UserData.Theme -eq 'custom')
            
            # Header
            header = @{
                profileImageLayout = if ($UserData.ProfileImageLayout) { $UserData.ProfileImageLayout } else { 'classic' }
                titleStyle = if ($UserData.TitleStyle) { $UserData.TitleStyle } else { 'text' }
                displayName = if ($UserData.DisplayName) { $UserData.DisplayName } else { "@$($UserData.Username)" }
                bio = $UserData.Bio
            }
            profileImageUrl = $UserData.Avatar
            socialIcons = $SocialIcons
            
            # Wallpaper/Background
            wallpaper = @{
                type = if ($UserData.WallpaperType) { $UserData.WallpaperType } else { 'fill' }
                color = if ($UserData.WallpaperColor) { $UserData.WallpaperColor } else { '#ffffff' }
                gradientStart = $UserData.WallpaperGradientStart
                gradientEnd = $UserData.WallpaperGradientEnd
                gradientDirection = if ($UserData.WallpaperGradientDirection) { [int]$UserData.WallpaperGradientDirection } else { 180 }
                patternType = $UserData.WallpaperPatternType
                patternColor = $UserData.WallpaperPatternColor
                imageUrl = $UserData.WallpaperImageUrl
                videoUrl = $UserData.WallpaperVideoUrl
                blur = if ($UserData.WallpaperBlur) { [int]$UserData.WallpaperBlur } else { 0 }
                opacity = if ($UserData.WallpaperOpacity) { [double]$UserData.WallpaperOpacity } else { 1.0 }
            }
            
            # Buttons
            buttons = @{
                type = if ($UserData.ButtonType) { $UserData.ButtonType } else { 'solid' }
                cornerRadius = if ($UserData.ButtonCornerRadius) { $UserData.ButtonCornerRadius } else { 'rounded' }
                shadow = if ($UserData.ButtonShadow) { $UserData.ButtonShadow } else { 'none' }
                backgroundColor = if ($UserData.ButtonBackgroundColor) { $UserData.ButtonBackgroundColor } else { '#e4e5e6' }
                textColor = if ($UserData.ButtonTextColor) { $UserData.ButtonTextColor } else { '#010101' }
                borderColor = $UserData.ButtonBorderColor
                hoverEffect = if ($UserData.ButtonHoverEffect) { $UserData.ButtonHoverEffect } else { 'none' }
            }
            
            # Text/Fonts
            text = @{
                titleFont = if ($UserData.TitleFont) { $UserData.TitleFont } else { 'inter' }
                titleColor = if ($UserData.TitleColor) { $UserData.TitleColor } else { '#010101' }
                titleSize = if ($UserData.TitleSize) { $UserData.TitleSize } else { 'small' }
                bodyFont = if ($UserData.BodyFont) { $UserData.BodyFont } else { 'inter' }
                pageTextColor = if ($UserData.PageTextColor) { $UserData.PageTextColor } else { '#010101' }
                buttonTextColor = if ($UserData.ButtonTextColor) { $UserData.ButtonTextColor } else { '#010101' }
            }
            
            # Footer
            hideFooter = [bool]$UserData.HideFooter
            
            # Legacy support (for backwards compatibility with old clients)
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
        
        # Add header logo URL if it exists
        if ($UserData.LogoUrl) {
            $Results.header.logoUrl = $UserData.LogoUrl
        }
        
        # Add customGradient if it exists (legacy support)
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