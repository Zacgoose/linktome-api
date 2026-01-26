function Get-ThemeDefaults {
    <#
    .SYNOPSIS
        Returns the default appearance configuration for a given theme.
    .DESCRIPTION
        Provides theme defaults for curated themes (agate, astrid, aura, bloom, breeze, honeycomb).
        These defaults are used when rendering curated themes to fill in non-customizable properties.
    .PARAMETER Theme
        The theme name to get defaults for.
    .OUTPUTS
        Hashtable containing the theme's default appearance configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Theme
    )
    
    # Define theme defaults for curated themes
    $ThemeDefaults = @{
        'agate' = @{
            wallpaper = @{
                type = 'gradient'
                gradientStart = '#1f1c2c'
                gradientEnd = '#928dab'
                gradientDirection = 220
            }
            buttons = @{
                type = 'solid'
                cornerRadius = 'pill'
                shadow = 'strong'
                backgroundColor = '#f8fafc'
                textColor = '#1f2937'
            }
            text = @{
                titleFont = 'playfair'
                titleColor = '#f8fafc'
                titleSize = 'small'
                bodyFont = 'dm-sans'
                pageTextColor = '#e2e8f0'
            }
        }
        'astrid' = @{
            wallpaper = @{
                type = 'blur'
                color = '#0b0f1a'
                blur = 14
                opacity = 0.94
            }
            buttons = @{
                type = 'glass'
                cornerRadius = 'pill'
                shadow = 'subtle'
                backgroundColor = '#7c3aed'
                textColor = '#f8f7ff'
                borderColor = '#c084fc'
            }
            text = @{
                titleFont = 'poppins'
                titleColor = '#f5f3ff'
                titleSize = 'small'
                bodyFont = 'inter'
                pageTextColor = '#e0def7'
            }
        }
        'aura' = @{
            wallpaper = @{
                type = 'gradient'
                gradientStart = '#667eea'
                gradientEnd = '#764ba2'
                gradientDirection = 135
            }
            buttons = @{
                type = 'solid'
                cornerRadius = 'rounded'
                shadow = 'subtle'
                backgroundColor = '#ffffff'
                textColor = '#4a5568'
            }
            text = @{
                titleFont = 'poppins'
                titleColor = '#ffffff'
                titleSize = 'small'
                bodyFont = 'inter'
                pageTextColor = '#f7fafc'
            }
        }
        'bloom' = @{
            wallpaper = @{
                type = 'gradient'
                gradientStart = '#ffecd2'
                gradientEnd = '#fcb69f'
                gradientDirection = 180
            }
            buttons = @{
                type = 'solid'
                cornerRadius = 'pill'
                shadow = 'none'
                backgroundColor = '#e53e3e'
                textColor = '#ffffff'
            }
            text = @{
                titleFont = 'playfair'
                titleColor = '#742a2a'
                titleSize = 'small'
                bodyFont = 'inter'
                pageTextColor = '#742a2a'
            }
        }
        'breeze' = @{
            wallpaper = @{
                type = 'gradient'
                gradientStart = '#a8edea'
                gradientEnd = '#fed6e3'
                gradientDirection = 45
            }
            buttons = @{
                type = 'solid'
                cornerRadius = 'rounded'
                shadow = 'subtle'
                backgroundColor = '#2c5282'
                textColor = '#ffffff'
            }
            text = @{
                titleFont = 'poppins'
                titleColor = '#1a365d'
                titleSize = 'small'
                bodyFont = 'inter'
                pageTextColor = '#2c5282'
            }
        }
        'honeycomb' = @{
            wallpaper = @{
                type = 'pattern'
                patternType = 'honey'
                color = '#fef3c7'
                patternColor = '#f59e0b'
            }
            buttons = @{
                type = 'solid'
                cornerRadius = 'rounded'
                shadow = 'none'
                backgroundColor = '#92400e'
                textColor = '#fef3c7'
            }
            text = @{
                titleFont = 'montserrat'
                titleColor = '#78350f'
                titleSize = 'small'
                bodyFont = 'inter'
                pageTextColor = '#92400e'
            }
        }
    }
    
    # Return the defaults for the requested theme, or null if not found
    if ($ThemeDefaults.ContainsKey($Theme)) {
        return $ThemeDefaults[$Theme]
    }
    
    return $null
}
