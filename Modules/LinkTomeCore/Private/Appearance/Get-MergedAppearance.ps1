function Get-MergedAppearance {
    <#
    .SYNOPSIS
        Merges stored appearance customizations with theme defaults for curated themes.
    .DESCRIPTION
        For custom themes, returns stored data as-is.
        For curated themes, merges stored customizations (colors) with theme defaults (types, fonts, etc).
    .PARAMETER AppearanceData
        The stored appearance data from the database.
    .OUTPUTS
        Hashtable containing the complete appearance configuration ready for API response.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $AppearanceData
    )
    
    # Determine if this is a custom theme (full customization) or curated theme (limited customization)
    $IsCustomTheme = if ($AppearanceData -and $AppearanceData.PSObject.Properties['CustomTheme']) {
        [bool]$AppearanceData.CustomTheme
    } else {
        $true  # Default to custom if not specified
    }
    
    # If custom theme, return stored data as-is (no merging needed)
    if ($IsCustomTheme) {
        return $null  # Caller should use stored data directly
    }
    
    # For curated themes, merge with defaults
    $Theme = if ($AppearanceData.Theme) { $AppearanceData.Theme } else { 'custom' }
    $ThemeDefaults = Get-ThemeDefaults -Theme $Theme
    
    if (-not $ThemeDefaults) {
        # If no defaults found, treat as custom theme
        return $null
    }
    
    # Build merged appearance
    $MergedAppearance = @{
        wallpaper = @{}
        buttons = @{}
        text = @{}
    }
    
    # === Wallpaper ===
    # Use theme defaults for type, but allow color overrides
    $MergedAppearance.wallpaper.type = $ThemeDefaults.wallpaper.type
    
    # Color overrides (gradient colors, pattern colors, blur colors)
    if ($AppearanceData.WallpaperGradientStart) {
        $MergedAppearance.wallpaper.gradientStart = $AppearanceData.WallpaperGradientStart
    } elseif ($ThemeDefaults.wallpaper.gradientStart) {
        $MergedAppearance.wallpaper.gradientStart = $ThemeDefaults.wallpaper.gradientStart
    }
    
    if ($AppearanceData.WallpaperGradientEnd) {
        $MergedAppearance.wallpaper.gradientEnd = $AppearanceData.WallpaperGradientEnd
    } elseif ($ThemeDefaults.wallpaper.gradientEnd) {
        $MergedAppearance.wallpaper.gradientEnd = $ThemeDefaults.wallpaper.gradientEnd
    }
    
    if ($AppearanceData.WallpaperGradientDirection) {
        $MergedAppearance.wallpaper.gradientDirection = [int]$AppearanceData.WallpaperGradientDirection
    } elseif ($ThemeDefaults.wallpaper.gradientDirection) {
        $MergedAppearance.wallpaper.gradientDirection = $ThemeDefaults.wallpaper.gradientDirection
    }
    
    if ($AppearanceData.WallpaperColor) {
        $MergedAppearance.wallpaper.color = $AppearanceData.WallpaperColor
    } elseif ($ThemeDefaults.wallpaper.color) {
        $MergedAppearance.wallpaper.color = $ThemeDefaults.wallpaper.color
    }
    
    if ($AppearanceData.WallpaperPatternColor) {
        $MergedAppearance.wallpaper.patternColor = $AppearanceData.WallpaperPatternColor
    } elseif ($ThemeDefaults.wallpaper.patternColor) {
        $MergedAppearance.wallpaper.patternColor = $ThemeDefaults.wallpaper.patternColor
    }
    
    # Type-specific properties from theme defaults
    if ($ThemeDefaults.wallpaper.patternType) {
        $MergedAppearance.wallpaper.patternType = $ThemeDefaults.wallpaper.patternType
    }
    if ($ThemeDefaults.wallpaper.blur) {
        $MergedAppearance.wallpaper.blur = $ThemeDefaults.wallpaper.blur
    }
    if ($ThemeDefaults.wallpaper.opacity) {
        $MergedAppearance.wallpaper.opacity = $ThemeDefaults.wallpaper.opacity
    }
    
    # === Buttons ===
    # Use theme defaults for type, cornerRadius, shadow, but allow color overrides
    $MergedAppearance.buttons.type = $ThemeDefaults.buttons.type
    $MergedAppearance.buttons.cornerRadius = $ThemeDefaults.buttons.cornerRadius
    $MergedAppearance.buttons.shadow = $ThemeDefaults.buttons.shadow
    
    # Color overrides
    if ($AppearanceData.ButtonBackgroundColor) {
        $MergedAppearance.buttons.backgroundColor = $AppearanceData.ButtonBackgroundColor
    } else {
        $MergedAppearance.buttons.backgroundColor = $ThemeDefaults.buttons.backgroundColor
    }
    
    if ($AppearanceData.ButtonTextColor) {
        $MergedAppearance.buttons.textColor = $AppearanceData.ButtonTextColor
    } else {
        $MergedAppearance.buttons.textColor = $ThemeDefaults.buttons.textColor
    }
    
    if ($AppearanceData.ButtonBorderColor) {
        $MergedAppearance.buttons.borderColor = $AppearanceData.ButtonBorderColor
    } elseif ($ThemeDefaults.buttons.borderColor) {
        $MergedAppearance.buttons.borderColor = $ThemeDefaults.buttons.borderColor
    }
    
    # === Text ===
    # Use theme defaults for fonts, but allow color overrides
    $MergedAppearance.text.titleFont = $ThemeDefaults.text.titleFont
    $MergedAppearance.text.bodyFont = $ThemeDefaults.text.bodyFont
    $MergedAppearance.text.titleSize = $ThemeDefaults.text.titleSize
    
    # Color overrides
    if ($AppearanceData.TitleColor) {
        $MergedAppearance.text.titleColor = $AppearanceData.TitleColor
    } else {
        $MergedAppearance.text.titleColor = $ThemeDefaults.text.titleColor
    }
    
    if ($AppearanceData.PageTextColor) {
        $MergedAppearance.text.pageTextColor = $AppearanceData.PageTextColor
    } else {
        $MergedAppearance.text.pageTextColor = $ThemeDefaults.text.pageTextColor
    }
    
    return $MergedAppearance
}
