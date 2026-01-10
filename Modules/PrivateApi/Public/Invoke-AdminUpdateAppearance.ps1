function Invoke-AdminUpdateAppearance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:appearance
    .DESCRIPTION
        Updates the page appearance settings including theme, header, wallpaper, buttons, text, and social icons.
        Appearance is now per-page rather than per-user.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body
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
        
        # Get user data for tier validation
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $UserData = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Get tier features for validation
        $UserTier = $UserData.SubscriptionTier
        $TierInfo = Get-TierFeatures -Tier $UserTier
        
        # Validate premium appearance features against tier
        # Check custom logos (logoUrl)
        if ($Body.header -and $Body.header.PSObject.Properties.Match('logoUrl').Count -gt 0 -and $Body.header.logoUrl) {
            if (-not $TierInfo.limits.customLogos) {
                $ClientIP = Get-ClientIPAddress -Request $Request
                Write-FeatureUsageEvent -UserId $UserId -Feature 'customLogos' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ error = "Custom logos require Pro tier or higher. Upgrade to use a custom logo in your header." }
                }
            }
        }
        
        # Check video backgrounds (videoUrl)
        if ($Body.wallpaper -and $Body.wallpaper.PSObject.Properties.Match('videoUrl').Count -gt 0 -and $Body.wallpaper.videoUrl) {
            if (-not $TierInfo.limits.videoBackgrounds) {
                $ClientIP = Get-ClientIPAddress -Request $Request
                Write-FeatureUsageEvent -UserId $UserId -Feature 'videoBackgrounds' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ error = "Video backgrounds require Premium tier or higher. Upgrade to use video as your background." }
                }
            }
        }
        
        # Check video type wallpaper
        if ($Body.wallpaper -and $Body.wallpaper.type -eq 'video') {
            if (-not $TierInfo.limits.videoBackgrounds) {
                $ClientIP = Get-ClientIPAddress -Request $Request
                Write-FeatureUsageEvent -UserId $UserId -Feature 'videoBackgrounds' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ error = "Video backgrounds require Premium tier or higher. Upgrade to use video as your background." }
                }
            }
        }
        
        # Check remove footer (hideFooter)
        if ($Body.PSObject.Properties.Match('hideFooter').Count -gt 0 -and $Body.hideFooter -eq $true) {
            if (-not $TierInfo.limits.removeFooter) {
                $ClientIP = Get-ClientIPAddress -Request $Request
                Write-FeatureUsageEvent -UserId $UserId -Feature 'removeFooter' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ error = "Removing footer requires Pro tier or higher. Upgrade to hide the 'Powered by LinkToMe' footer." }
                }
            }
        }
        
        # Check premium fonts
        $premiumFonts = @('space-mono', 'playfair', 'oswald', 'montserrat', 'raleway', 'dm-sans')
        if ($Body.fontFamily -and $Body.fontFamily -in $premiumFonts) {
            if (-not $TierInfo.limits.premiumFonts) {
                $ClientIP = Get-ClientIPAddress -Request $Request
                Write-FeatureUsageEvent -UserId $UserId -Feature 'premiumFonts' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ error = "Premium fonts require Pro tier or higher. Upgrade to use fonts like Space Mono, Playfair, Oswald, Montserrat, Raleway, or DM Sans." }
                }
            }
        }
        
        # Get or create appearance record for this page
        $AppearanceTable = Get-LinkToMeTable -TableName 'Appearance'
        $SafePageId = Protect-TableQueryValue -Value $PageId
        $AppearanceData = Get-LinkToMeAzDataTableEntity @AppearanceTable -Filter "PartitionKey eq '$SafeUserId' and PageId eq '$SafePageId'" | Select-Object -First 1
        
        if (-not $AppearanceData) {
            # Create new appearance record
            $AppearanceData = @{
                PartitionKey = $UserId
                RowKey = 'appearance-' + (New-Guid).ToString()
                PageId = $PageId
                CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
            }
        }
        
        # Helper function to safely set property
        function Set-EntityProperty {
            param($Entity, $PropertyName, $Value)
            if ($null -eq $Entity.$PropertyName) {
                $Entity | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $Value -Force
            } else {
                $Entity.$PropertyName = $Value
            }
        }
        
        # Validation patterns
        $hexColorRegex = '^#[0-9A-Fa-f]{6}$'
        $urlRegex = '^https?://'
        
        # Valid enum values
        $validThemes = @('custom', 'air', 'blocks', 'lake', 'mineral', 'agate', 'astrid', 'aura', 'bloom', 'breeze', 'light', 'dark', 'sunset', 'ocean', 'forest', 'honeycomb')
        $premiumThemes = @('agate', 'astrid', 'aura', 'bloom', 'breeze')
        $validProfileImageLayouts = @('classic', 'hero')
        $validTitleStyles = @('text', 'logo')
        $validWallpaperTypes = @('fill', 'gradient', 'blur', 'pattern', 'image', 'video')
        $validPatternTypes = @('grid', 'dots', 'lines', 'waves', 'geometric', 'honey')
        $validButtonTypes = @('solid', 'glass', 'outline')
        $validCornerRadii = @('square', 'rounded', 'pill')
        $validShadows = @('none', 'subtle', 'strong', 'hard')
        $validHoverEffects = @('none', 'lift', 'glow', 'fill')
        $validTitleSizes = @('small', 'large')
        $validFonts = @('inter', 'space-mono', 'poppins', 'roboto', 'playfair', 'oswald', 'lato', 'montserrat', 'raleway', 'dm-sans', 'default', 'serif', 'mono')
        $validButtonStyles = @('rounded', 'square', 'pill')
        $validLayoutStyles = @('centered', 'card')
        
        # === Theme ===
        if ($Body.PSObject.Properties.Match('theme').Count -gt 0) {
            if ($Body.theme -and $Body.theme -notin $validThemes) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Invalid theme value" }
                }
            }
            # Validate premium themes require Pro+ tier
            if ($Body.theme -and $Body.theme -in $premiumThemes) {
                if (-not $TierInfo.limits.customThemes) {
                    $ClientIP = Get-ClientIPAddress -Request $Request
                    Write-FeatureUsageEvent -UserId $UserId -Feature 'customThemes' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body = @{ error = "Premium themes require Pro tier or higher. Upgrade to use themes like Agate, Astrid, Aura, Bloom, and Breeze." }
                    }
                }
            }
            Set-EntityProperty -Entity $AppearanceData -PropertyName 'Theme' -Value $Body.theme
        }
        
        if ($Body.PSObject.Properties.Match('customTheme').Count -gt 0) {
            Set-EntityProperty -Entity $AppearanceData -PropertyName 'CustomTheme' -Value ([bool]$Body.customTheme)
        }
        
        # === Header ===
        if ($Body.header) {
            if ($Body.header.profileImageLayout) {
                if ($Body.header.profileImageLayout -notin $validProfileImageLayouts) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Profile image layout must be 'classic' or 'hero'" }
                    }
                }
                # Validate hero layout requires Pro+ tier
                if ($Body.header.profileImageLayout -eq 'hero') {
                    if (-not (Test-UserTier -User $UserData -MinimumTier 'pro')) {
                        $ClientIP = Get-ClientIPAddress -Request $Request
                        Write-FeatureUsageEvent -UserId $UserId -Feature 'heroProfileLayout' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::Forbidden
                            Body = @{ error = "Hero profile layout requires Pro tier or higher. Upgrade to use the hero-style profile display." }
                        }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'ProfileImageLayout' -Value $Body.header.profileImageLayout
            }
            
            if ($Body.header.titleStyle) {
                if ($Body.header.titleStyle -notin $validTitleStyles) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Title style must be 'text' or 'logo'" }
                    }
                }
                # Validate logo title style requires Pro+ tier
                if ($Body.header.titleStyle -eq 'logo') {
                    if (-not (Test-UserTier -User $UserData -MinimumTier 'pro')) {
                        $ClientIP = Get-ClientIPAddress -Request $Request
                        Write-FeatureUsageEvent -UserId $UserId -Feature 'logoTitleStyle' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::Forbidden
                            Body = @{ error = "Logo title style requires Pro tier or higher. Upgrade to use a logo instead of text for your title." }
                        }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'TitleStyle' -Value $Body.header.titleStyle
            }
            
            if ($Body.header.PSObject.Properties.Match('logoUrl').Count -gt 0) {
                if ($Body.header.logoUrl -and $Body.header.logoUrl -notmatch $urlRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Logo URL must be a valid http or https URL" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'LogoUrl' -Value $Body.header.logoUrl
            }
            
            # Display name and bio are user-level (not per-page), save to Users table
            if ($Body.header.displayName) {
                $NameCheck = Test-InputLength -Value $Body.header.displayName -MaxLength 100 -FieldName "Display name"
                if (-not $NameCheck.Valid) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = $NameCheck.Message }
                    }
                }
                $UserData.DisplayName = $Body.header.displayName
            }
            
            if ($Body.header.PSObject.Properties.Match('bio').Count -gt 0) {
                if ($Body.header.bio) {
                    $BioCheck = Test-InputLength -Value $Body.header.bio -MaxLength 500 -FieldName "Bio"
                    if (-not $BioCheck.Valid) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = $BioCheck.Message }
                        }
                    }
                }
                $UserData.Bio = $Body.header.bio
            }
        }
        
        # === Profile Image URL ===
        # Avatar is user-level (not per-page), save to Users table
        if ($Body.PSObject.Properties.Match('profileImageUrl').Count -gt 0) {
            if ($Body.profileImageUrl -and $Body.profileImageUrl -notmatch $urlRegex) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Profile image URL must be a valid http or https URL" }
                }
            }
            $UserData.Avatar = $Body.profileImageUrl
        }
        
        # === Wallpaper ===
        if ($Body.wallpaper) {
            if ($Body.wallpaper.type) {
                if ($Body.wallpaper.type -notin $validWallpaperTypes) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Wallpaper type must be 'fill', 'gradient', 'blur', 'pattern', 'image', or 'video'" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperType' -Value $Body.wallpaper.type
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('color').Count -gt 0) {
                if ($Body.wallpaper.color -and $Body.wallpaper.color -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Wallpaper color must be a valid hex color (e.g., #ffffff)" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperColor' -Value $Body.wallpaper.color
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('gradientStart').Count -gt 0) {
                if ($Body.wallpaper.gradientStart -and $Body.wallpaper.gradientStart -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Gradient start color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperGradientStart' -Value $Body.wallpaper.gradientStart
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('gradientEnd').Count -gt 0) {
                if ($Body.wallpaper.gradientEnd -and $Body.wallpaper.gradientEnd -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Gradient end color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperGradientEnd' -Value $Body.wallpaper.gradientEnd
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('gradientDirection').Count -gt 0) {
                $direction = [int]$Body.wallpaper.gradientDirection
                if ($direction -lt 0 -or $direction -gt 360) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Gradient direction must be between 0 and 360" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperGradientDirection' -Value $direction
            }
            
            if ($Body.wallpaper.patternType) {
                if ($Body.wallpaper.patternType -notin $validPatternTypes) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Pattern type must be 'grid', 'dots', 'lines', 'waves', 'geometric' or 'honey'" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperPatternType' -Value $Body.wallpaper.patternType
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('patternColor').Count -gt 0) {
                if ($Body.wallpaper.patternColor -and $Body.wallpaper.patternColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Pattern color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperPatternColor' -Value $Body.wallpaper.patternColor
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('imageUrl').Count -gt 0) {
                if ($Body.wallpaper.imageUrl -and $Body.wallpaper.imageUrl -notmatch $urlRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Wallpaper image URL must be a valid http or https URL" }
                    }
                }
                # Validate image backgrounds require Premium+ tier
                if ($Body.wallpaper.imageUrl) {
                    if (-not (Test-UserTier -User $UserData -MinimumTier 'premium')) {
                        $ClientIP = Get-ClientIPAddress -Request $Request
                        Write-FeatureUsageEvent -UserId $UserId -Feature 'imageBackgrounds' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::Forbidden
                            Body = @{ error = "Image backgrounds require Premium tier or higher. Upgrade to use custom images as your background." }
                        }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperImageUrl' -Value $Body.wallpaper.imageUrl
            }
            
            # Check image type wallpaper
            if ($Body.wallpaper -and $Body.wallpaper.type -eq 'image') {
                if (-not (Test-UserTier -User $UserData -MinimumTier 'premium')) {
                    $ClientIP = Get-ClientIPAddress -Request $Request
                    Write-FeatureUsageEvent -UserId $UserId -Feature 'imageBackgrounds' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body = @{ error = "Image backgrounds require Premium tier or higher. Upgrade to use custom images as your background." }
                    }
                }
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('videoUrl').Count -gt 0) {
                if ($Body.wallpaper.videoUrl -and $Body.wallpaper.videoUrl -notmatch $urlRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Wallpaper video URL must be a valid http or https URL" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperVideoUrl' -Value $Body.wallpaper.videoUrl
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('blur').Count -gt 0) {
                $blur = [int]$Body.wallpaper.blur
                if ($blur -lt 0 -or $blur -gt 100) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Blur must be between 0 and 100" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperBlur' -Value $blur
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('opacity').Count -gt 0) {
                $opacity = [double]$Body.wallpaper.opacity
                if ($opacity -lt 0 -or $opacity -gt 1) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Opacity must be between 0 and 1" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'WallpaperOpacity' -Value $opacity
            }
        }
        
        # === Buttons ===
        if ($Body.buttons) {
            if ($Body.buttons.type) {
                if ($Body.buttons.type -notin $validButtonTypes) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button type must be 'solid', 'glass', or 'outline'" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'ButtonType' -Value $Body.buttons.type
            }
            
            if ($Body.buttons.cornerRadius) {
                if ($Body.buttons.cornerRadius -notin $validCornerRadii) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Corner radius must be 'square', 'rounded', or 'pill'" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'ButtonCornerRadius' -Value $Body.buttons.cornerRadius
            }
            
            if ($Body.buttons.shadow) {
                if ($Body.buttons.shadow -notin $validShadows) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Shadow must be 'none', 'subtle', 'strong', or 'hard'" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'ButtonShadow' -Value $Body.buttons.shadow
            }
            
            if ($Body.buttons.PSObject.Properties.Match('backgroundColor').Count -gt 0) {
                if ($Body.buttons.backgroundColor -and $Body.buttons.backgroundColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button background color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'ButtonBackgroundColor' -Value $Body.buttons.backgroundColor
            }
            
            if ($Body.buttons.PSObject.Properties.Match('textColor').Count -gt 0) {
                if ($Body.buttons.textColor -and $Body.buttons.textColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button text color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'ButtonTextColor' -Value $Body.buttons.textColor
            }
            
            if ($Body.buttons.PSObject.Properties.Match('borderColor').Count -gt 0) {
                if ($Body.buttons.borderColor -and $Body.buttons.borderColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button border color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'ButtonBorderColor' -Value $Body.buttons.borderColor
            }
            
            if ($Body.buttons.hoverEffect) {
                if ($Body.buttons.hoverEffect -notin $validHoverEffects) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Hover effect must be 'none', 'lift', 'glow', or 'fill'" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'ButtonHoverEffect' -Value $Body.buttons.hoverEffect
            }
        }
        
        # === Text ===
        if ($Body.text) {
            if ($Body.text.titleFont) {
                if ($Body.text.titleFont -notin $validFonts) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Invalid title font" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'TitleFont' -Value $Body.text.titleFont
            }
            
            if ($Body.text.PSObject.Properties.Match('titleColor').Count -gt 0) {
                if ($Body.text.titleColor -and $Body.text.titleColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Title color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'TitleColor' -Value $Body.text.titleColor
            }
            
            if ($Body.text.titleSize) {
                if ($Body.text.titleSize -notin $validTitleSizes) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Title size must be 'small' or 'large'" }
                    }
                }
                # Validate large title size requires Pro+ tier
                if ($Body.text.titleSize -eq 'large') {
                    if (-not (Test-UserTier -User $UserData -MinimumTier 'pro')) {
                        $ClientIP = Get-ClientIPAddress -Request $Request
                        Write-FeatureUsageEvent -UserId $UserId -Feature 'largeTitleSize' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateAppearance'
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::Forbidden
                            Body = @{ error = "Large title size requires Pro tier or higher. Upgrade to use larger title text." }
                        }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'TitleSize' -Value $Body.text.titleSize
            }
            
            if ($Body.text.bodyFont) {
                if ($Body.text.bodyFont -notin $validFonts) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Invalid body font" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'BodyFont' -Value $Body.text.bodyFont
            }
            
            if ($Body.text.PSObject.Properties.Match('pageTextColor').Count -gt 0) {
                if ($Body.text.pageTextColor -and $Body.text.pageTextColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Page text color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'PageTextColor' -Value $Body.text.pageTextColor
            }
        }
        
        # === Footer ===
        if ($Body.PSObject.Properties.Match('hideFooter').Count -gt 0) {
            Set-EntityProperty -Entity $AppearanceData -PropertyName 'HideFooter' -Value ([bool]$Body.hideFooter)
        }
        
        # === Legacy support ===
        if ($Body.buttonStyle) {
            if ($Body.buttonStyle -notin $validButtonStyles) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Button style must be 'rounded', 'square', or 'pill'" }
                }
            }
            Set-EntityProperty -Entity $AppearanceData -PropertyName 'ButtonStyle' -Value $Body.buttonStyle
        }
        
        if ($Body.fontFamily) {
            if ($Body.fontFamily -notin $validFonts) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Invalid font family" }
                }
            }
            Set-EntityProperty -Entity $AppearanceData -PropertyName 'FontFamily' -Value $Body.fontFamily
        }
        
        if ($Body.layoutStyle) {
            if ($Body.layoutStyle -notin $validLayoutStyles) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Layout style must be 'centered' or 'card'" }
                }
            }
            Set-EntityProperty -Entity $AppearanceData -PropertyName 'LayoutStyle' -Value $Body.layoutStyle
        }
        
        # Handle legacy colors object
        if ($Body.colors) {
            foreach ($colorProp in @('primary', 'secondary', 'background', 'buttonBackground', 'buttonText')) {
                if ($Body.colors.$colorProp) {
                    if ($Body.colors.$colorProp -notmatch $hexColorRegex) {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "$colorProp color must be a valid hex color" }
                        }
                    }
                    $propName = "Color" + (Get-Culture).TextInfo.ToTitleCase($colorProp)
                    Set-EntityProperty -Entity $AppearanceData -PropertyName $propName -Value $Body.colors.$colorProp
                }
            }
        }
        
        # Handle legacy customGradient object
        if ($Body.customGradient) {
            if ($Body.customGradient.start) {
                if ($Body.customGradient.start -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Custom gradient start color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'CustomGradientStart' -Value $Body.customGradient.start
            }
            
            if ($Body.customGradient.end) {
                if ($Body.customGradient.end -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Custom gradient end color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $AppearanceData -PropertyName 'CustomGradientEnd' -Value $Body.customGradient.end
            }
        }
        
        # === Handle Social Icons ===
        if ($Body.socialIcons) {
            $SocialTable = Get-LinkToMeTable -TableName 'SocialIcons'
            
            # Get existing social icons
            $ExistingIcons = @(Get-LinkToMeAzDataTableEntity @SocialTable -Filter "PartitionKey eq '$SafeUserId'")
            
            foreach ($icon in $Body.socialIcons) {
                $op = ($icon.operation ?? 'update').ToLower()
                
                switch ($op) {
                    'add' {
                        if (-not $icon.platform -or -not $icon.url) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Social icon requires platform and url" }
                            }
                        }
                        $NewIcon = @{
                            PartitionKey = $UserId
                            RowKey = 'social-' + (New-Guid).ToString()
                            Platform = $icon.platform
                            Url = $icon.url
                            Order = if ($null -ne $icon.order) { [int]$icon.order } else { 0 }
                            Active = if ($null -ne $icon.active) { [bool]$icon.active } else { $true }
                        }
                        Add-LinkToMeAzDataTableEntity @SocialTable -Entity $NewIcon -Force
                    }
                    'update' {
                        if (-not $icon.id) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Social icon id required for update" }
                            }
                        }
                        $ExistingIcon = $ExistingIcons | Where-Object { $_.RowKey -eq $icon.id } | Select-Object -First 1
                        if ($ExistingIcon) {
                            if ($icon.platform) { $ExistingIcon.Platform = $icon.platform }
                            if ($icon.url) { $ExistingIcon.Url = $icon.url }
                            if ($null -ne $icon.order) { $ExistingIcon.Order = [int]$icon.order }
                            if ($null -ne $icon.active) { $ExistingIcon.Active = [bool]$icon.active }
                            Add-LinkToMeAzDataTableEntity @SocialTable -Entity $ExistingIcon -Force
                        }
                    }
                    'remove' {
                        if (-not $icon.id) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Social icon id required for remove" }
                            }
                        }
                        $ExistingIcon = $ExistingIcons | Where-Object { $_.RowKey -eq $icon.id } | Select-Object -First 1
                        if ($ExistingIcon) {
                            Remove-AzDataTableEntity -Entity $ExistingIcon -Context $SocialTable.Context
                        }
                    }
                }
            }
        }
        
        # Save updated user data (displayName, bio, avatar are user-level)
        Add-LinkToMeAzDataTableEntity @UsersTable -Entity $UserData -Force
        
        # Save updated appearance data
        $AppearanceData.UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Add-LinkToMeAzDataTableEntity @AppearanceTable -Entity $AppearanceData -Force
        
        # Return success with current appearance
        $Results = @{ 
            success = $true
            pageId = $PageId
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Update appearance error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update appearance"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
