function Invoke-AdminGetAppearance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:appearance
    .DESCRIPTION
        Returns the page appearance settings including theme, header, wallpaper, buttons, text, and social icons.
        Appearance is now per-page rather than per-user.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $PageId = $Request.Query.pageId
    
    try {
        # If no pageId specified, get default page
        if (-not $PageId) {
            $PagesTable = Get-LinkToMeTable -TableName 'Pages'
            $SafeUserId = Protect-TableQueryValue -Value $UserId
            $DefaultPage = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId' and IsDefault eq true" | Select-Object -First 1
            
            if (-not $DefaultPage) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body = @{ error = "No default page found. Please create a page first." }
                }
            }
            
            $PageId = $DefaultPage.RowKey
        }
        
        # Get user data for username/bio (still stored on user)
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Get appearance for this page
        $AppearanceTable = Get-LinkToMeTable -TableName 'Appearance'
        $SafePageId = Protect-TableQueryValue -Value $PageId
        $AppearanceData = Get-LinkToMeAzDataTableEntity @AppearanceTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'" | Select-Object -First 1
        
        # Get social icons (stored per user, not per page)
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
        # Use AppearanceData if exists, otherwise use defaults
        $Results = @{
            pageId = $PageId
            
            # Theme
            theme = if ($AppearanceData.Theme) { $AppearanceData.Theme } else { 'custom' }
            customTheme = if ($AppearanceData) { [bool]$AppearanceData.CustomTheme } else { $true }
            
            # Header
            header = @{
                profileImageLayout = if ($AppearanceData.ProfileImageLayout) { $AppearanceData.ProfileImageLayout } else { 'classic' }
                titleStyle = if ($AppearanceData.TitleStyle) { $AppearanceData.TitleStyle } else { 'text' }
                displayName = if ($AppearanceData.DisplayName) { $AppearanceData.DisplayName } else { "@$($UserData.Username)" }
                bio = $AppearanceData.Bio
            }
            profileImageUrl = $UserData.Avatar
            socialIcons = $SocialIcons
            
            # Wallpaper/Background
            wallpaper = @{
                type = if ($AppearanceData.WallpaperType) { $AppearanceData.WallpaperType } else { 'fill' }
                color = if ($AppearanceData.WallpaperColor) { $AppearanceData.WallpaperColor } else { '#ffffff' }
                gradientStart = $AppearanceData.WallpaperGradientStart
                gradientEnd = $AppearanceData.WallpaperGradientEnd
                gradientDirection = if ($AppearanceData.WallpaperGradientDirection) { [int]$AppearanceData.WallpaperGradientDirection } else { 180 }
                patternType = $AppearanceData.WallpaperPatternType
                patternColor = $AppearanceData.WallpaperPatternColor
                imageUrl = $AppearanceData.WallpaperImageUrl
                videoUrl = $AppearanceData.WallpaperVideoUrl
                blur = if ($AppearanceData.WallpaperBlur) { [int]$AppearanceData.WallpaperBlur } else { 0 }
                opacity = if ($AppearanceData.WallpaperOpacity) { [double]$AppearanceData.WallpaperOpacity } else { 1.0 }
            }
            
            # Buttons
            buttons = @{
                type = if ($AppearanceData.ButtonType) { $AppearanceData.ButtonType } else { 'solid' }
                cornerRadius = if ($AppearanceData.ButtonCornerRadius) { $AppearanceData.ButtonCornerRadius } else { 'rounded' }
                shadow = if ($AppearanceData.ButtonShadow) { $AppearanceData.ButtonShadow } else { 'none' }
                backgroundColor = if ($AppearanceData.ButtonBackgroundColor) { $AppearanceData.ButtonBackgroundColor } else { '#e4e5e6' }
                textColor = if ($AppearanceData.ButtonTextColor) { $AppearanceData.ButtonTextColor } else { '#010101' }
                borderColor = $AppearanceData.ButtonBorderColor
                hoverEffect = if ($AppearanceData.ButtonHoverEffect) { $AppearanceData.ButtonHoverEffect } else { 'none' }
            }
            
            # Text/Fonts
            text = @{
                titleFont = if ($AppearanceData.TitleFont) { $AppearanceData.TitleFont } else { 'inter' }
                titleColor = if ($AppearanceData.TitleColor) { $AppearanceData.TitleColor } else { '#010101' }
                titleSize = if ($AppearanceData.TitleSize) { $AppearanceData.TitleSize } else { 'small' }
                bodyFont = if ($AppearanceData.BodyFont) { $AppearanceData.BodyFont } else { 'inter' }
                pageTextColor = if ($AppearanceData.PageTextColor) { $AppearanceData.PageTextColor } else { '#010101' }
            }
            
            # Footer
            hideFooter = if ($AppearanceData) { [bool]$AppearanceData.HideFooter } else { $false }
            
            # Legacy support (for backwards compatibility with old clients)
            buttonStyle = if ($AppearanceData.ButtonStyle) { $AppearanceData.ButtonStyle } else { 'rounded' }
            fontFamily = if ($AppearanceData.FontFamily) { $AppearanceData.FontFamily } else { 'default' }
            layoutStyle = if ($AppearanceData.LayoutStyle) { $AppearanceData.LayoutStyle } else { 'centered' }
            colors = @{
                primary = if ($AppearanceData.ColorPrimary) { $AppearanceData.ColorPrimary } else { '#000000' }
                secondary = if ($AppearanceData.ColorSecondary) { $AppearanceData.ColorSecondary } else { '#666666' }
                background = if ($AppearanceData.ColorBackground) { $AppearanceData.ColorBackground } else { '#ffffff' }
                buttonBackground = if ($AppearanceData.ColorButtonBackground) { $AppearanceData.ColorButtonBackground } else { '#000000' }
                buttonText = if ($AppearanceData.ColorButtonText) { $AppearanceData.ColorButtonText } else { '#ffffff' }
            }
        }
        
        # Add header logo URL if it exists
        if ($AppearanceData.LogoUrl) {
            $Results.header.logoUrl = $AppearanceData.LogoUrl
        }
        
        # Add customGradient if it exists (legacy support)
        if ($AppearanceData.CustomGradientStart -and $AppearanceData.CustomGradientEnd) {
            $Results.customGradient = @{
                start = $AppearanceData.CustomGradientStart
                end = $AppearanceData.CustomGradientEnd
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
