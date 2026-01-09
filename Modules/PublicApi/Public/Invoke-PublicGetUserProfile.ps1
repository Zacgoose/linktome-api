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
                # Get default page (ensure one exists)
                $DefaultPage = Ensure-DefaultPage -UserId $User.RowKey
                $Page = $DefaultPage
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
            
            # Build appearance object with new structure
            $Appearance = @{
                # Theme
                theme = if ($User.Theme) { $User.Theme } else { 'custom' }
                
                # Header
                header = @{
                    profileImageLayout = if ($User.ProfileImageLayout) { $User.ProfileImageLayout } else { 'classic' }
                    titleStyle = if ($User.TitleStyle) { $User.TitleStyle } else { 'text' }
                    displayName = if ($User.DisplayName) { $User.DisplayName } else { "@$($User.Username)" }
                }
                
                # Wallpaper/Background
                wallpaper = @{
                    type = if ($User.WallpaperType) { $User.WallpaperType } else { 'fill' }
                    color = if ($User.WallpaperColor) { $User.WallpaperColor } else { '#ffffff' }
                }
                
                # Buttons
                buttons = @{
                    type = if ($User.ButtonType) { $User.ButtonType } else { 'solid' }
                    cornerRadius = if ($User.ButtonCornerRadius) { $User.ButtonCornerRadius } else { 'rounded' }
                    shadow = if ($User.ButtonShadow) { $User.ButtonShadow } else { 'none' }
                    backgroundColor = if ($User.ButtonBackgroundColor) { $User.ButtonBackgroundColor } else { '#e4e5e6' }
                    textColor = if ($User.ButtonTextColor) { $User.ButtonTextColor } else { '#010101' }
                }
                
                # Text/Fonts
                text = @{
                    titleFont = if ($User.TitleFont) { $User.TitleFont } else { 'inter' }
                    titleColor = if ($User.TitleColor) { $User.TitleColor } else { '#010101' }
                    titleSize = if ($User.TitleSize) { $User.TitleSize } else { 'small' }
                    bodyFont = if ($User.BodyFont) { $User.BodyFont } else { 'inter' }
                    pageTextColor = if ($User.PageTextColor) { $User.PageTextColor } else { '#010101' }
                }
                
                # Footer
                hideFooter = [bool]$User.HideFooter
                
                # Legacy support
                buttonStyle = if ($User.ButtonStyle) { $User.ButtonStyle } else { 'rounded' }
                fontFamily = if ($User.FontFamily) { $User.FontFamily } else { 'default' }
                layoutStyle = if ($User.LayoutStyle) { $User.LayoutStyle } else { 'centered' }
                colors = @{
                    primary = if ($User.ColorPrimary) { $User.ColorPrimary } else { '#000000' }
                    secondary = if ($User.ColorSecondary) { $User.ColorSecondary } else { '#666666' }
                    background = if ($User.ColorBackground) { $User.ColorBackground } else { '#ffffff' }
                    buttonBackground = if ($User.ColorButtonBackground) { $User.ColorButtonBackground } else { '#000000' }
                    buttonText = if ($User.ColorButtonText) { $User.ColorButtonText } else { '#ffffff' }
                }
            }
            
            # Add optional header properties
            if ($User.LogoUrl) { $Appearance.header.logoUrl = $User.LogoUrl }
            if ($User.Bio) { $Appearance.header.bio = $User.Bio }
            
            # Add optional wallpaper properties
            if ($User.WallpaperGradientStart) { $Appearance.wallpaper.gradientStart = $User.WallpaperGradientStart }
            if ($User.WallpaperGradientEnd) { $Appearance.wallpaper.gradientEnd = $User.WallpaperGradientEnd }
            if ($User.WallpaperGradientDirection) { $Appearance.wallpaper.gradientDirection = [int]$User.WallpaperGradientDirection }
            if ($User.WallpaperPatternType) { $Appearance.wallpaper.patternType = $User.WallpaperPatternType }
            if ($User.WallpaperPatternColor) { $Appearance.wallpaper.patternColor = $User.WallpaperPatternColor }
            if ($User.WallpaperImageUrl) { $Appearance.wallpaper.imageUrl = $User.WallpaperImageUrl }
            if ($User.WallpaperVideoUrl) { $Appearance.wallpaper.videoUrl = $User.WallpaperVideoUrl }
            if ($User.WallpaperBlur) { $Appearance.wallpaper.blur = [int]$User.WallpaperBlur }
            if ($User.WallpaperOpacity) { $Appearance.wallpaper.opacity = [double]$User.WallpaperOpacity }
            
            # Add optional button properties
            if ($User.ButtonBorderColor) { $Appearance.buttons.borderColor = $User.ButtonBorderColor }
            if ($User.ButtonHoverEffect) { $Appearance.buttons.hoverEffect = $User.ButtonHoverEffect }
            
            # Add legacy customGradient if it exists
            if ($User.CustomGradientStart -and $User.CustomGradientEnd) {
                $Appearance.customGradient = @{
                    start = $User.CustomGradientStart
                    end = $User.CustomGradientEnd
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
            
            Write-AnalyticsEvent -EventType 'PageView' -UserId $User.RowKey -Username $User.Username -IpAddress $ClientIP -UserAgent $UserAgent -Referrer $Referrer
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