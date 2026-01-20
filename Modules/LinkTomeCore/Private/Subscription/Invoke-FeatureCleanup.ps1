function Invoke-FeatureCleanup {
    <#
    .SYNOPSIS
        Clean up features when a user's subscription is downgraded
    .DESCRIPTION
        When a subscription ends, expires, or is cancelled, this function removes or disables
        features that are no longer available in the user's new tier.
        
        Handles:
        - Excess pages (beyond new tier limit)
        - Custom themes (reset to default if not allowed)
        - Video backgrounds (remove if not allowed)
        - API keys (disable excess keys)
        - Links (mark excess as inactive)
    .PARAMETER UserId
        The user ID to clean up features for
    .PARAMETER NewTier
        The new tier to enforce limits for (typically 'free' on downgrade)
    .OUTPUTS
        Hashtable with cleanup results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [ValidateSet('free', 'pro', 'premium', 'enterprise')]
        [string]$NewTier
    )
    
    try {
        Write-Information "Starting feature cleanup for user $UserId, new tier: $NewTier"
        
        # Get tier features and limits
        $TierFeatures = Get-TierFeatures -Tier $NewTier
        $Limits = $TierFeatures.limits
        
        $Results = @{
            success = $true
            tier = $NewTier
            cleanupActions = @()
        }
        
        # Protect user ID for queries
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        
        # 1. Clean up excess pages
        if ($Limits.maxPages -gt 0) {
            $PagesTable = Get-LinkToMeTable -TableName 'Pages'
            $Pages = @(Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId'" | Sort-Object @{Expression={-([bool]$_.IsDefault)}}, CreatedAt)
            
            if ($Pages.Count -gt $Limits.maxPages) {
                $PagesToDelete = $Pages | Select-Object -Skip $Limits.maxPages
                foreach ($Page in $PagesToDelete) {
                    # Don't delete the default page
                    if (-not $Page.IsDefault) {
                        try {
                            Remove-LinkToMeAzDataTableEntity @PagesTable -Entity $Page
                            $Results.cleanupActions += "Deleted excess page: $($Page.Name) (id: $($Page.RowKey))"
                            Write-Information "Deleted excess page $($Page.RowKey) for user $UserId"
                        } catch {
                            Write-Warning "Failed to delete page $($Page.RowKey): $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
        
        # 2. Clean up custom themes if not allowed
        if (-not $Limits.customThemes) {
            $AppearanceTable = Get-LinkToMeTable -TableName 'Appearance'
            $Appearances = Get-LinkToMeAzDataTableEntity @AppearanceTable -Filter "PartitionKey eq '$SafeUserId'"
            
            # Premium themes that require Pro+ tiers (should match frontend configuration)
            # These are the themes that are not available on the free tier
            $PremiumThemes = @('agate', 'astrid', 'aura', 'bloom', 'breeze')
            
            foreach ($Appearance in $Appearances) {
                $Updated = $false
                
                # Reset to default theme if using custom theme
                if ($Appearance.CustomTheme -eq $true) {
                    $Appearance.CustomTheme = $false
                    $Appearance.Theme = 'default'
                    $Updated = $true
                }
                
                # Reset premium theme to default
                if ($Appearance.Theme -and $PremiumThemes -contains $Appearance.Theme) {
                    $Appearance.Theme = 'default'
                    $Updated = $true
                }
                
                if ($Updated) {
                    try {
                        Add-LinkToMeAzDataTableEntity @AppearanceTable -Entity $Appearance -Force
                        $Results.cleanupActions += "Reset appearance to default theme for page: $($Appearance.PageId)"
                        Write-Information "Reset theme for appearance $($Appearance.RowKey)"
                    } catch {
                        Write-Warning "Failed to update appearance $($Appearance.RowKey): $($_.Exception.Message)"
                    }
                }
            }
        }
        
        # 3. Remove video backgrounds if not allowed
        if (-not $Limits.videoBackgrounds) {
            $AppearanceTable = Get-LinkToMeTable -TableName 'Appearance'
            $Appearances = Get-LinkToMeAzDataTableEntity @AppearanceTable -Filter "PartitionKey eq '$SafeUserId'"
            
            foreach ($Appearance in $Appearances) {
                if ($Appearance.WallpaperType -eq 'video' -or $Appearance.WallpaperVideoUrl) {
                    $Appearance.WallpaperType = 'fill'
                    $Appearance.WallpaperVideoUrl = $null
                    
                    try {
                        Add-LinkToMeAzDataTableEntity @AppearanceTable -Entity $Appearance -Force
                        $Results.cleanupActions += "Removed video background for page: $($Appearance.PageId)"
                        Write-Information "Removed video background for appearance $($Appearance.RowKey)"
                    } catch {
                        Write-Warning "Failed to remove video background $($Appearance.RowKey): $($_.Exception.Message)"
                    }
                }
            }
        }
        
        # 4. Disable excess API keys if limit changed
        if ($Limits.apiKeysLimit -ge 0) {
            try {
                $ApiKeysTable = Get-LinkToMeTable -TableName 'ApiKeys'
                $ApiKeys = @(Get-LinkToMeAzDataTableEntity @ApiKeysTable -Filter "PartitionKey eq '$SafeUserId' and Active eq true" | Sort-Object CreatedAt)
                
                if ($ApiKeys.Count -gt $Limits.apiKeysLimit) {
                    $KeysToDisable = $ApiKeys | Select-Object -Skip $Limits.apiKeysLimit
                    foreach ($Key in $KeysToDisable) {
                        $Key.Active = $false
                        $Key.DisabledReason = 'Subscription downgraded'
                        
                        try {
                            Add-LinkToMeAzDataTableEntity @ApiKeysTable -Entity $Key -Force
                            $Results.cleanupActions += "Disabled API key: $($Key.Name)"
                            Write-Information "Disabled API key $($Key.RowKey) for user $UserId"
                        } catch {
                            Write-Warning "Failed to disable API key $($Key.RowKey): $($_.Exception.Message)"
                        }
                    }
                }
            } catch {
                # ApiKeys table might not exist
                Write-Information "ApiKeys table not found or accessible, skipping API key cleanup"
            }
        }
        
        # 5. Mark excess links as inactive if over new limit
        if ($Limits.maxLinks -gt 0) {
            try {
                $LinksTable = Get-LinkToMeTable -TableName 'Links'
                $Links = @(Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId' and Active eq true" | Sort-Object Order)
                
                if ($Links.Count -gt $Limits.maxLinks) {
                    $LinksToDisable = $Links | Select-Object -Skip $Limits.maxLinks
                    foreach ($Link in $LinksToDisable) {
                        $Link.Active = $false
                        
                        try {
                            Add-LinkToMeAzDataTableEntity @LinksTable -Entity $Link -Force
                            $Results.cleanupActions += "Deactivated excess link: $($Link.Title)"
                            Write-Information "Deactivated link $($Link.RowKey) for user $UserId"
                        } catch {
                            Write-Warning "Failed to deactivate link $($Link.RowKey): $($_.Exception.Message)"
                        }
                    }
                }
            } catch {
                Write-Warning "Failed to clean up links: $($_.Exception.Message)"
            }
        }
        
        # Log cleanup event
        $CleanupCount = $Results.cleanupActions.Count
        Write-SecurityEvent -EventType 'FeatureCleanup' -UserId $UserId -Reason "Downgraded to $NewTier tier, cleaned up $CleanupCount items"
        
        Write-Information "Feature cleanup completed for user ${UserId}: $CleanupCount actions taken"
        return $Results
        
    } catch {
        $ErrorMessage = $_.Exception.Message
        Write-Error "Feature cleanup failed for user ${UserId}: $ErrorMessage"
        return @{
            success = $false
            error = $ErrorMessage
            tier = $NewTier
            cleanupActions = @()
        }
    }
}
