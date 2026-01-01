function Invoke-AdminUpdateAppearance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:appearance
    .DESCRIPTION
        Updates the user's appearance settings including theme, header, wallpaper, buttons, text, and social icons.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

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
            Set-EntityProperty -Entity $UserData -PropertyName 'Theme' -Value $Body.theme
        }
        
        if ($Body.PSObject.Properties.Match('customTheme').Count -gt 0) {
            Set-EntityProperty -Entity $UserData -PropertyName 'CustomTheme' -Value ([bool]$Body.customTheme)
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
                Set-EntityProperty -Entity $UserData -PropertyName 'ProfileImageLayout' -Value $Body.header.profileImageLayout
            }
            
            if ($Body.header.titleStyle) {
                if ($Body.header.titleStyle -notin $validTitleStyles) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Title style must be 'text' or 'logo'" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'TitleStyle' -Value $Body.header.titleStyle
            }
            
            if ($Body.header.PSObject.Properties.Match('logoUrl').Count -gt 0) {
                if ($Body.header.logoUrl -and $Body.header.logoUrl -notmatch $urlRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Logo URL must be a valid http or https URL" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'LogoUrl' -Value $Body.header.logoUrl
            }
            
            if ($Body.header.displayName) {
                $NameCheck = Test-InputLength -Value $Body.header.displayName -MaxLength 100 -FieldName "Display name"
                if (-not $NameCheck.Valid) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = $NameCheck.Message }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'DisplayName' -Value $Body.header.displayName
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
                Set-EntityProperty -Entity $UserData -PropertyName 'Bio' -Value $Body.header.bio
            }
        }
        
        # === Profile Image URL ===
        if ($Body.PSObject.Properties.Match('profileImageUrl').Count -gt 0) {
            if ($Body.profileImageUrl -and $Body.profileImageUrl -notmatch $urlRegex) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Profile image URL must be a valid http or https URL" }
                }
            }
            Set-EntityProperty -Entity $UserData -PropertyName 'Avatar' -Value $Body.profileImageUrl
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
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperType' -Value $Body.wallpaper.type
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('color').Count -gt 0) {
                if ($Body.wallpaper.color -and $Body.wallpaper.color -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Wallpaper color must be a valid hex color (e.g., #ffffff)" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperColor' -Value $Body.wallpaper.color
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('gradientStart').Count -gt 0) {
                if ($Body.wallpaper.gradientStart -and $Body.wallpaper.gradientStart -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Gradient start color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperGradientStart' -Value $Body.wallpaper.gradientStart
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('gradientEnd').Count -gt 0) {
                if ($Body.wallpaper.gradientEnd -and $Body.wallpaper.gradientEnd -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Gradient end color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperGradientEnd' -Value $Body.wallpaper.gradientEnd
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('gradientDirection').Count -gt 0) {
                $direction = [int]$Body.wallpaper.gradientDirection
                if ($direction -lt 0 -or $direction -gt 360) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Gradient direction must be between 0 and 360" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperGradientDirection' -Value $direction
            }
            
            if ($Body.wallpaper.patternType) {
                if ($Body.wallpaper.patternType -notin $validPatternTypes) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Pattern type must be 'grid', 'dots', 'lines', 'waves', 'geometric' or 'honey'" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperPatternType' -Value $Body.wallpaper.patternType
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('patternColor').Count -gt 0) {
                if ($Body.wallpaper.patternColor -and $Body.wallpaper.patternColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Pattern color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperPatternColor' -Value $Body.wallpaper.patternColor
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('imageUrl').Count -gt 0) {
                if ($Body.wallpaper.imageUrl -and $Body.wallpaper.imageUrl -notmatch $urlRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Wallpaper image URL must be a valid http or https URL" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperImageUrl' -Value $Body.wallpaper.imageUrl
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('videoUrl').Count -gt 0) {
                if ($Body.wallpaper.videoUrl -and $Body.wallpaper.videoUrl -notmatch $urlRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Wallpaper video URL must be a valid http or https URL" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperVideoUrl' -Value $Body.wallpaper.videoUrl
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('blur').Count -gt 0) {
                $blur = [int]$Body.wallpaper.blur
                if ($blur -lt 0 -or $blur -gt 100) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Blur must be between 0 and 100" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperBlur' -Value $blur
            }
            
            if ($Body.wallpaper.PSObject.Properties.Match('opacity').Count -gt 0) {
                $opacity = [double]$Body.wallpaper.opacity
                if ($opacity -lt 0 -or $opacity -gt 1) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Opacity must be between 0 and 1" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'WallpaperOpacity' -Value $opacity
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
                Set-EntityProperty -Entity $UserData -PropertyName 'ButtonType' -Value $Body.buttons.type
            }
            
            if ($Body.buttons.cornerRadius) {
                if ($Body.buttons.cornerRadius -notin $validCornerRadii) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Corner radius must be 'square', 'rounded', or 'pill'" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'ButtonCornerRadius' -Value $Body.buttons.cornerRadius
            }
            
            if ($Body.buttons.shadow) {
                if ($Body.buttons.shadow -notin $validShadows) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Shadow must be 'none', 'subtle', 'strong', or 'hard'" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'ButtonShadow' -Value $Body.buttons.shadow
            }
            
            if ($Body.buttons.PSObject.Properties.Match('backgroundColor').Count -gt 0) {
                if ($Body.buttons.backgroundColor -and $Body.buttons.backgroundColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button background color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'ButtonBackgroundColor' -Value $Body.buttons.backgroundColor
            }
            
            if ($Body.buttons.PSObject.Properties.Match('textColor').Count -gt 0) {
                if ($Body.buttons.textColor -and $Body.buttons.textColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button text color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'ButtonTextColor' -Value $Body.buttons.textColor
            }
            
            if ($Body.buttons.PSObject.Properties.Match('borderColor').Count -gt 0) {
                if ($Body.buttons.borderColor -and $Body.buttons.borderColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button border color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'ButtonBorderColor' -Value $Body.buttons.borderColor
            }
            
            if ($Body.buttons.hoverEffect) {
                if ($Body.buttons.hoverEffect -notin $validHoverEffects) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Hover effect must be 'none', 'lift', 'glow', or 'fill'" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'ButtonHoverEffect' -Value $Body.buttons.hoverEffect
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
                Set-EntityProperty -Entity $UserData -PropertyName 'TitleFont' -Value $Body.text.titleFont
            }
            
            if ($Body.text.PSObject.Properties.Match('titleColor').Count -gt 0) {
                if ($Body.text.titleColor -and $Body.text.titleColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Title color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'TitleColor' -Value $Body.text.titleColor
            }
            
            if ($Body.text.titleSize) {
                if ($Body.text.titleSize -notin $validTitleSizes) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Title size must be 'small' or 'large'" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'TitleSize' -Value $Body.text.titleSize
            }
            
            if ($Body.text.bodyFont) {
                if ($Body.text.bodyFont -notin $validFonts) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Invalid body font" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'BodyFont' -Value $Body.text.bodyFont
            }
            
            if ($Body.text.PSObject.Properties.Match('pageTextColor').Count -gt 0) {
                if ($Body.text.pageTextColor -and $Body.text.pageTextColor -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Page text color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'PageTextColor' -Value $Body.text.pageTextColor
            }
        }
        
        # === Footer ===
        if ($Body.PSObject.Properties.Match('hideFooter').Count -gt 0) {
            Set-EntityProperty -Entity $UserData -PropertyName 'HideFooter' -Value ([bool]$Body.hideFooter)
        }
        
        # === Legacy support ===
        if ($Body.buttonStyle) {
            if ($Body.buttonStyle -notin $validButtonStyles) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Button style must be 'rounded', 'square', or 'pill'" }
                }
            }
            Set-EntityProperty -Entity $UserData -PropertyName 'ButtonStyle' -Value $Body.buttonStyle
        }
        
        if ($Body.fontFamily) {
            if ($Body.fontFamily -notin $validFonts) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Invalid font family" }
                }
            }
            Set-EntityProperty -Entity $UserData -PropertyName 'FontFamily' -Value $Body.fontFamily
        }
        
        if ($Body.layoutStyle) {
            if ($Body.layoutStyle -notin $validLayoutStyles) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Layout style must be 'centered' or 'card'" }
                }
            }
            Set-EntityProperty -Entity $UserData -PropertyName 'LayoutStyle' -Value $Body.layoutStyle
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
                    Set-EntityProperty -Entity $UserData -PropertyName $propName -Value $Body.colors.$colorProp
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
                Set-EntityProperty -Entity $UserData -PropertyName 'CustomGradientStart' -Value $Body.customGradient.start
            }
            
            if ($Body.customGradient.end) {
                if ($Body.customGradient.end -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Custom gradient end color must be a valid hex color" }
                    }
                }
                Set-EntityProperty -Entity $UserData -PropertyName 'CustomGradientEnd' -Value $Body.customGradient.end
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
        
        # Save updated user data
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        # Return success with current appearance
        $Results = @{ success = $true }
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
