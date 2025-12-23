function Invoke-PublicGetUserProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:profile
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Username = $Request.Query.username

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
            $LinksTable = Get-LinkToMeTable -TableName 'Links'
            $Links = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$($User.RowKey)' and Active eq true"
            
            $Results = @{
                username = $User.Username
                displayName = $User.DisplayName
                bio = $User.Bio
                avatar = $User.Avatar
                appearance = @{
                    theme = if ($User.Theme) { $User.Theme } else { 'light' }
                    buttonStyle = if ($User.ButtonStyle) { $User.ButtonStyle } else { 'rounded' }
                    backgroundColor = if ($User.BackgroundColor) { $User.BackgroundColor } else { '#ffffff' }
                    textColor = if ($User.TextColor) { $User.TextColor } else { '#000000' }
                    buttonColor = if ($User.ButtonColor) { $User.ButtonColor } else { '#000000' }
                    buttonTextColor = if ($User.ButtonTextColor) { $User.ButtonTextColor } else { '#ffffff' }
                }
                links = @($Links | ForEach-Object {
                    @{
                        id = $_.RowKey
                        title = $_.Title
                        url = $_.Url
                        order = [int]$_.Order
                    }
                } | Sort-Object order)
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