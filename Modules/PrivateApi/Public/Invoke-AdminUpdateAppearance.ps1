function Invoke-AdminUpdateAppearance {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        User.Appearance.Write
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get user data
        $SafeUserId = Protect-TableQueryValue -Value $User.UserId
        $UserData = Get-AzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Validate and update appearance settings
        if ($Body.theme) {
            if ($Body.theme -notin @('light', 'dark')) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Theme must be 'light' or 'dark'" }
                }
            }
            $UserData.Theme = $Body.theme
        }
        
        if ($Body.buttonStyle) {
            if ($Body.buttonStyle -notin @('rounded', 'square', 'pill')) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Button style must be 'rounded', 'square', or 'pill'" }
                }
            }
            $UserData.ButtonStyle = $Body.buttonStyle
        }
        
        # Validate hex color codes
        $hexColorRegex = '^#[0-9A-Fa-f]{6}$'
        
        if ($Body.backgroundColor) {
            if ($Body.backgroundColor -notmatch $hexColorRegex) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Background color must be a valid hex color (e.g., #ffffff)" }
                }
            }
            $UserData.BackgroundColor = $Body.backgroundColor
        }
        
        if ($Body.textColor) {
            if ($Body.textColor -notmatch $hexColorRegex) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Text color must be a valid hex color (e.g., #000000)" }
                }
            }
            $UserData.TextColor = $Body.textColor
        }
        
        if ($Body.buttonColor) {
            if ($Body.buttonColor -notmatch $hexColorRegex) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Button color must be a valid hex color (e.g., #000000)" }
                }
            }
            $UserData.ButtonColor = $Body.buttonColor
        }
        
        if ($Body.buttonTextColor) {
            if ($Body.buttonTextColor -notmatch $hexColorRegex) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Button text color must be a valid hex color (e.g., #ffffff)" }
                }
            }
            $UserData.ButtonTextColor = $Body.buttonTextColor
        }
        
        # Save updated appearance
        Add-AzDataTableEntity @Table -Entity $UserData -Force
        
        $Results = @{
            success = $true
            theme = $UserData.Theme
            buttonStyle = $UserData.ButtonStyle
            backgroundColor = $UserData.BackgroundColor
            textColor = $UserData.TextColor
            buttonColor = $UserData.ButtonColor
            buttonTextColor = $UserData.ButtonTextColor
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
