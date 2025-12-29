function Invoke-AdminUpdateAppearance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:appearance
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
        
        # Validate and update appearance settings
        # Note: Need to use Add-Member to add new properties to table entity objects
        
        # Validate theme
        if ($Body.theme) {
            if ($Body.theme -notin @('light', 'dark', 'sunset', 'ocean', 'forest', 'custom')) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Theme must be 'light', 'dark', 'sunset', 'ocean', 'forest', or 'custom'" }
                }
            }
            if ($null -eq $UserData.Theme) {
                $UserData | Add-Member -MemberType NoteProperty -Name 'Theme' -Value $Body.theme -Force
            } else {
                $UserData.Theme = $Body.theme
            }
        }
        
        # Validate buttonStyle
        if ($Body.buttonStyle) {
            if ($Body.buttonStyle -notin @('rounded', 'square', 'pill')) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Button style must be 'rounded', 'square', or 'pill'" }
                }
            }
            if ($null -eq $UserData.ButtonStyle) {
                $UserData | Add-Member -MemberType NoteProperty -Name 'ButtonStyle' -Value $Body.buttonStyle -Force
            } else {
                $UserData.ButtonStyle = $Body.buttonStyle
            }
        }
        
        # Validate fontFamily
        if ($Body.fontFamily) {
            if ($Body.fontFamily -notin @('default', 'serif', 'mono', 'poppins', 'roboto')) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Font family must be 'default', 'serif', 'mono', 'poppins', or 'roboto'" }
                }
            }
            if ($null -eq $UserData.FontFamily) {
                $UserData | Add-Member -MemberType NoteProperty -Name 'FontFamily' -Value $Body.fontFamily -Force
            } else {
                $UserData.FontFamily = $Body.fontFamily
            }
        }
        
        # Validate layoutStyle
        if ($Body.layoutStyle) {
            if ($Body.layoutStyle -notin @('centered', 'card')) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Layout style must be 'centered' or 'card'" }
                }
            }
            if ($null -eq $UserData.LayoutStyle) {
                $UserData | Add-Member -MemberType NoteProperty -Name 'LayoutStyle' -Value $Body.layoutStyle -Force
            } else {
                $UserData.LayoutStyle = $Body.layoutStyle
            }
        }
        
        # Validate hex color codes
        $hexColorRegex = '^#[0-9A-Fa-f]{6}$'
        
        # Handle nested colors object
        if ($Body.colors) {
            if ($Body.colors.primary) {
                if ($Body.colors.primary -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Primary color must be a valid hex color (e.g., #000000)" }
                    }
                }
                if ($null -eq $UserData.ColorPrimary) {
                    $UserData | Add-Member -MemberType NoteProperty -Name 'ColorPrimary' -Value $Body.colors.primary -Force
                } else {
                    $UserData.ColorPrimary = $Body.colors.primary
                }
            }
            
            if ($Body.colors.secondary) {
                if ($Body.colors.secondary -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Secondary color must be a valid hex color (e.g., #666666)" }
                    }
                }
                if ($null -eq $UserData.ColorSecondary) {
                    $UserData | Add-Member -MemberType NoteProperty -Name 'ColorSecondary' -Value $Body.colors.secondary -Force
                } else {
                    $UserData.ColorSecondary = $Body.colors.secondary
                }
            }
            
            if ($Body.colors.background) {
                if ($Body.colors.background -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Background color must be a valid hex color (e.g., #ffffff)" }
                    }
                }
                if ($null -eq $UserData.ColorBackground) {
                    $UserData | Add-Member -MemberType NoteProperty -Name 'ColorBackground' -Value $Body.colors.background -Force
                } else {
                    $UserData.ColorBackground = $Body.colors.background
                }
            }
            
            if ($Body.colors.buttonBackground) {
                if ($Body.colors.buttonBackground -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button background color must be a valid hex color (e.g., #000000)" }
                    }
                }
                if ($null -eq $UserData.ColorButtonBackground) {
                    $UserData | Add-Member -MemberType NoteProperty -Name 'ColorButtonBackground' -Value $Body.colors.buttonBackground -Force
                } else {
                    $UserData.ColorButtonBackground = $Body.colors.buttonBackground
                }
            }
            
            if ($Body.colors.buttonText) {
                if ($Body.colors.buttonText -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Button text color must be a valid hex color (e.g., #ffffff)" }
                    }
                }
                if ($null -eq $UserData.ColorButtonText) {
                    $UserData | Add-Member -MemberType NoteProperty -Name 'ColorButtonText' -Value $Body.colors.buttonText -Force
                } else {
                    $UserData.ColorButtonText = $Body.colors.buttonText
                }
            }
        }
        
        # Handle customGradient object
        if ($Body.customGradient) {
            if ($Body.customGradient.start) {
                if ($Body.customGradient.start -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Custom gradient start color must be a valid hex color (e.g., #ff0000)" }
                    }
                }
                if ($null -eq $UserData.CustomGradientStart) {
                    $UserData | Add-Member -MemberType NoteProperty -Name 'CustomGradientStart' -Value $Body.customGradient.start -Force
                } else {
                    $UserData.CustomGradientStart = $Body.customGradient.start
                }
            }
            
            if ($Body.customGradient.end) {
                if ($Body.customGradient.end -notmatch $hexColorRegex) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body = @{ error = "Custom gradient end color must be a valid hex color (e.g., #00ff00)" }
                    }
                }
                if ($null -eq $UserData.CustomGradientEnd) {
                    $UserData | Add-Member -MemberType NoteProperty -Name 'CustomGradientEnd' -Value $Body.customGradient.end -Force
                } else {
                    $UserData.CustomGradientEnd = $Body.customGradient.end
                }
            }
        }
        
        # Save updated appearance
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
        $Results = @{
            theme = $UserData.Theme
            buttonStyle = $UserData.ButtonStyle
            fontFamily = $UserData.FontFamily
            layoutStyle = $UserData.LayoutStyle
            colors = @{
                primary = $UserData.ColorPrimary
                secondary = $UserData.ColorSecondary
                background = $UserData.ColorBackground
                buttonBackground = $UserData.ColorButtonBackground
                buttonText = $UserData.ColorButtonText
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
        Write-Error "Update appearance error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update appearance"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
