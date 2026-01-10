function Invoke-PublicGetUserProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:profile
    .DESCRIPTION
        Returns a public user profile with appearance settings, links, and groups.
        Filters links based on active status and schedule settings.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Username = $Request.Query.username
    $Slug = $Request.Query.slug

    if (-not $Username) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Username is required" }
        }
    }

    # Validate username format
    if (-not (Test-UsernameFormat -Username $Username)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "Invalid username format" }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize username for query
        $SafeUsername = Protect-TableQueryValue -Value $Username.ToLower()
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "Username eq '$SafeUsername'" | Select-Object -First 1
        
        if (-not $User) {
            $StatusCode = [HttpStatusCode]::NotFound
            $Results = @{ error = "Profile not found" }
        } else {
            $SafeUserId = Protect-TableQueryValue -Value $User.RowKey
            
            # Get the page to display (by slug or default)
            $PagesTable = Get-LinkToMeTable -TableName 'Pages'
            $Page = $null
            
            if ($Slug) {
                # Get page by slug
                $SafeSlug = Protect-TableQueryValue -Value $Slug.ToLower()
                $Page = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId' and Slug eq '$SafeSlug'" | Select-Object -First 1
                
                if (-not $Page) {
                    $StatusCode = [HttpStatusCode]::NotFound
                    $Results = @{ error = "Page not found" }
                    return [HttpResponseContext]@{
                        StatusCode = $StatusCode
                        Body = $Results
                    }
                }
            } else {
                # Get default page
                $Page = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId' and IsDefault eq true" | Select-Object -First 1
                
                if (-not $Page) {
                    $StatusCode = [HttpStatusCode]::NotFound
                    $Results = @{ error = "No default page found for this user" }
                    return [HttpResponseContext]@{
                        StatusCode = $StatusCode
                        Body = $Results
                    }
                }
            }
            
            $PageId = $Page.RowKey
            $SafePageId = Protect-TableQueryValue -Value $PageId
            
            # Get links for this page
            $LinksTable = Get-LinkToMeTable -TableName 'Links'
            $AllLinks = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'"
            
            # Get groups for this page
            $GroupsTable = Get-LinkToMeTable -TableName 'LinkGroups'
            $AllGroups = Get-LinkToMeAzDataTableEntity @GroupsTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'"
            
            # Get social icons
            $SocialTable = Get-LinkToMeTable -TableName 'SocialIcons'
            $SocialIcons = @(Get-LinkToMeAzDataTableEntity @SocialTable -Filter "PartitionKey eq '$SafeUserId'" | ForEach-Object {
                if ([bool]$_.Active) {
                    @{
                        id = $_.RowKey
                        platform = $_.Platform
                        url = $_.Url
                        order = [int]$_.Order
                    }
                }
            } | Where-Object { $_ } | Sort-Object order)
            
            # Current time for schedule filtering
            $CurrentTime = Get-Date
            
            # Filter and transform links
            $FilteredLinks = @($AllLinks | Where-Object {
                # Must be active
                if (-not [bool]$_.Active) { return $false }
                
                # Check schedule if enabled
                if ([bool]$_.ScheduleEnabled) {
                    if ($_.ScheduleStartDate) {
                        $startDate = [DateTime]::Parse($_.ScheduleStartDate)
                        if ($CurrentTime -lt $startDate) { return $false }
                    }
                    if ($_.ScheduleEndDate) {
                        $endDate = [DateTime]::Parse($_.ScheduleEndDate)
                        if ($CurrentTime -gt $endDate) { return $false }
                    }
                }
                
                return $true
            } | ForEach-Object {
                $linkObj = @{
                    id = $_.RowKey
                    title = $_.Title
                    url = $_.Url
                    order = [int]$_.Order
                }
                
                # Include display-relevant properties
                if ($_.Icon) { $linkObj.icon = $_.Icon }
                if ($_.Thumbnail) { $linkObj.thumbnail = $_.Thumbnail }
                if ($_.ThumbnailType) { $linkObj.thumbnailType = $_.ThumbnailType }
                if ($_.Layout) { $linkObj.layout = $_.Layout }
                if ($_.Animation) { $linkObj.animation = $_.Animation }
                if ($_.GroupId) { $linkObj.groupId = $_.GroupId }
                
                # Include lock info (but not the actual code) for UI to show lock state
                if ([bool]$_.LockEnabled) {
                    $linkObj.lock = @{
                        enabled = $true
                        type = $_.LockType
                    }
                    if ($_.LockMessage) { $linkObj.lock.message = $_.LockMessage }
                }
                
                $linkObj
            } | Sort-Object order)
            
            # Filter and transform groups (only active ones with at least one link)
            $ActiveGroupIds = $FilteredLinks | Where-Object { $_.groupId } | Select-Object -ExpandProperty groupId -Unique
            $FilteredGroups = @($AllGroups | Where-Object {
                [bool]$_.Active -and ($_.RowKey -in $ActiveGroupIds)
            } | ForEach-Object {
                $groupObj = @{
                    id = $_.RowKey
                    title = $_.Title
                    order = [int]$_.Order
                }
                if ($_.Layout) { $groupObj.layout = $_.Layout }
                if ($null -ne $_.Collapsed) { $groupObj.collapsed = [bool]$_.Collapsed }
                $groupObj
            } | Sort-Object order)
            
            # Get appearance for this page from Appearance table
            $AppearanceTable = Get-LinkToMeTable -TableName 'Appearance'
            $AppearanceData = Get-LinkToMeAzDataTableEntity @AppearanceTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'" | Select-Object -First 1
            
            # Build appearance object with new structure
            # Use AppearanceData if exists, otherwise use defaults
            $Appearance = @{
                # Theme
                theme = if ($AppearanceData.Theme) { $AppearanceData.Theme } else { 'custom' }
                
                # Header
                header = @{
                    profileImageLayout = if ($AppearanceData.ProfileImageLayout) { $AppearanceData.ProfileImageLayout } else { 'classic' }
                    titleStyle = if ($AppearanceData.TitleStyle) { $AppearanceData.TitleStyle } else { 'text' }
                    displayName = if ($User.DisplayName) { $User.DisplayName } else { "@$($User.Username)" }
                }
                
                # Wallpaper/Background
                wallpaper = @{
                    type = if ($AppearanceData.WallpaperType) { $AppearanceData.WallpaperType } else { 'fill' }
                    color = if ($AppearanceData.WallpaperColor) { $AppearanceData.WallpaperColor } else { '#ffffff' }
                }
                
                # Buttons
                buttons = @{
                    type = if ($AppearanceData.ButtonType) { $AppearanceData.ButtonType } else { 'solid' }
                    cornerRadius = if ($AppearanceData.ButtonCornerRadius) { $AppearanceData.ButtonCornerRadius } else { 'rounded' }
                    shadow = if ($AppearanceData.ButtonShadow) { $AppearanceData.ButtonShadow } else { 'none' }
                    backgroundColor = if ($AppearanceData.ButtonBackgroundColor) { $AppearanceData.ButtonBackgroundColor } else { '#e4e5e6' }
                    textColor = if ($AppearanceData.ButtonTextColor) { $AppearanceData.ButtonTextColor } else { '#010101' }
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
                
                # Legacy support
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
            
            # Add optional header properties
            if ($AppearanceData.LogoUrl) { $Appearance.header.logoUrl = $AppearanceData.LogoUrl }
            if ($User.Bio) { $Appearance.header.bio = $User.Bio }
            
            # Add optional wallpaper properties
            if ($AppearanceData.WallpaperGradientStart) { $Appearance.wallpaper.gradientStart = $AppearanceData.WallpaperGradientStart }
            if ($AppearanceData.WallpaperGradientEnd) { $Appearance.wallpaper.gradientEnd = $AppearanceData.WallpaperGradientEnd }
            if ($AppearanceData.WallpaperGradientDirection) { $Appearance.wallpaper.gradientDirection = [int]$AppearanceData.WallpaperGradientDirection }
            if ($AppearanceData.WallpaperPatternType) { $Appearance.wallpaper.patternType = $AppearanceData.WallpaperPatternType }
            if ($AppearanceData.WallpaperPatternColor) { $Appearance.wallpaper.patternColor = $AppearanceData.WallpaperPatternColor }
            if ($AppearanceData.WallpaperImageUrl) { $Appearance.wallpaper.imageUrl = $AppearanceData.WallpaperImageUrl }
            if ($AppearanceData.WallpaperVideoUrl) { $Appearance.wallpaper.videoUrl = $AppearanceData.WallpaperVideoUrl }
            if ($AppearanceData.WallpaperBlur) { $Appearance.wallpaper.blur = [int]$AppearanceData.WallpaperBlur }
            if ($AppearanceData.WallpaperOpacity) { $Appearance.wallpaper.opacity = [double]$AppearanceData.WallpaperOpacity }
            
            # Add optional button properties
            if ($AppearanceData.ButtonBorderColor) { $Appearance.buttons.borderColor = $AppearanceData.ButtonBorderColor }
            if ($AppearanceData.ButtonHoverEffect) { $Appearance.buttons.hoverEffect = $AppearanceData.ButtonHoverEffect }
            
            # Add legacy customGradient if it exists
            if ($AppearanceData.CustomGradientStart -and $AppearanceData.CustomGradientEnd) {
                $Appearance.customGradient = @{
                    start = $AppearanceData.CustomGradientStart
                    end = $AppearanceData.CustomGradientEnd
                }
            }
            
            $Results = @{
                username = $User.Username
                displayName = if ($User.DisplayName) { $User.DisplayName } else { "@$($User.Username)" }
                bio = $User.Bio
                avatar = $User.Avatar
                appearance = $Appearance
                socialIcons = $SocialIcons
                links = $FilteredLinks
                groups = $FilteredGroups
            }
            
            $StatusCode = [HttpStatusCode]::OK
            
            # Track page view analytics
            $ClientIP = Get-ClientIPAddress -Request $Request
            $UserAgent = $Request.Headers.'User-Agent'
            $Referrer = $Request.Headers.Referer
            
            Write-AnalyticsEvent -EventType 'PageView' -UserId $User.RowKey -Username $User.Username -IpAddress $ClientIP -UserAgent $UserAgent -Referrer $Referrer -PageId $PageId
        }
        
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