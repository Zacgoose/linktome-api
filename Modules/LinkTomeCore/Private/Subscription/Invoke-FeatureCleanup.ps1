function Invoke-FeatureCleanup {
    <#
    .SYNOPSIS
        Mark features that exceed tier limits when a user's subscription is downgraded
    .DESCRIPTION
        When a subscription ends, expires, or is cancelled, this function marks features
        that exceed the new tier's limits. Data is preserved and can be restored on upgrade.
        
        Handles:
        - Excess pages (mark as exceeding limit, hide from public)
        - Custom themes (mark as exceeding limit)
        - Video backgrounds (mark as exceeding limit)
        - API keys (disable excess keys)
        - Links (mark excess as inactive)
        - Short links (mark excess as exceeding limit)
        
        Note: Public APIs check these flags to hide/restrict access to features.
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
        
        # 1. Mark excess pages (preserve data, hide from public)
        if ($Limits.maxPages -gt 0) {
            $PagesTable = Get-LinkToMeTable -TableName 'Pages'
            $Pages = @(Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId'" | Sort-Object @{Expression={-([bool]$_.IsDefault)}}, CreatedAt)
            
            if ($Pages.Count -gt $Limits.maxPages) {
                $AllowedPages = $Pages | Select-Object -First $Limits.maxPages
                $ExcessPages = $Pages | Select-Object -Skip $Limits.maxPages
                
                foreach ($Page in $ExcessPages) {
                    # Mark as exceeding tier limit (don't delete)
                    if (-not $Page.PSObject.Properties['ExceedsTierLimit']) {
                        $Page | Add-Member -NotePropertyName 'ExceedsTierLimit' -NotePropertyValue $true -Force
                    } else {
                        $Page.ExceedsTierLimit = $true
                    }
                    
                    try {
                        Add-LinkToMeAzDataTableEntity @PagesTable -Entity $Page -Force
                        $Results.cleanupActions += "Marked excess page as exceeding limit: $($Page.Name) (id: $($Page.RowKey))"
                        Write-Information "Marked excess page $($Page.RowKey) as exceeding tier limit for user $UserId"
                    } catch {
                        Write-Warning "Failed to mark page $($Page.RowKey): $($_.Exception.Message)"
                    }
                }
                
                # Ensure allowed pages are marked as not exceeding limit
                foreach ($Page in $AllowedPages) {
                    if ($Page.PSObject.Properties['ExceedsTierLimit'] -and $Page.ExceedsTierLimit -eq $true) {
                        $Page.ExceedsTierLimit = $false
                        try {
                            Add-LinkToMeAzDataTableEntity @PagesTable -Entity $Page -Force
                        } catch {
                            Write-Warning "Failed to update page $($Page.RowKey): $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
        
        # 2. Mark custom themes as exceeding limit if not allowed (preserve data)
        if (-not $Limits.customThemes) {
            $AppearanceTable = Get-LinkToMeTable -TableName 'Appearance'
            $Appearances = Get-LinkToMeAzDataTableEntity @AppearanceTable -Filter "PartitionKey eq '$SafeUserId'"
            
            # Premium themes that require Pro+ tiers (should match frontend configuration)
            # These are the themes that are not available on the free tier
            $PremiumThemes = @('agate', 'astrid', 'aura', 'bloom', 'breeze')
            
            foreach ($Appearance in $Appearances) {
                $Updated = $false
                
                # Mark custom theme as exceeding limit (preserve data)
                if ($Appearance.CustomTheme -eq $true) {
                    if (-not $Appearance.PSObject.Properties['ExceedsTierLimit']) {
                        $Appearance | Add-Member -NotePropertyName 'ExceedsTierLimit' -NotePropertyValue $true -Force
                    } else {
                        $Appearance.ExceedsTierLimit = $true
                    }
                    $Updated = $true
                }
                
                # Mark premium theme as exceeding limit (preserve theme choice)
                if ($Appearance.Theme -and $PremiumThemes -contains $Appearance.Theme) {
                    if (-not $Appearance.PSObject.Properties['ExceedsTierLimit']) {
                        $Appearance | Add-Member -NotePropertyName 'ExceedsTierLimit' -NotePropertyValue $true -Force
                    } else {
                        $Appearance.ExceedsTierLimit = $true
                    }
                    $Updated = $true
                }
                
                if ($Updated) {
                    try {
                        Add-LinkToMeAzDataTableEntity @AppearanceTable -Entity $Appearance -Force
                        $Results.cleanupActions += "Marked custom theme as exceeding limit for page: $($Appearance.PageId)"
                        Write-Information "Marked theme as exceeding limit for appearance $($Appearance.RowKey)"
                    } catch {
                        Write-Warning "Failed to update appearance $($Appearance.RowKey): $($_.Exception.Message)"
                    }
                }
            }
        }
        
        # 3. Mark video backgrounds as exceeding limit if not allowed (preserve data)
        if (-not $Limits.videoBackgrounds) {
            $AppearanceTable = Get-LinkToMeTable -TableName 'Appearance'
            $Appearances = Get-LinkToMeAzDataTableEntity @AppearanceTable -Filter "PartitionKey eq '$SafeUserId'"
            
            foreach ($Appearance in $Appearances) {
                if ($Appearance.WallpaperType -eq 'video' -or $Appearance.WallpaperVideoUrl) {
                    # Mark video background as exceeding limit (preserve URL)
                    if (-not $Appearance.PSObject.Properties['VideoExceedsTierLimit']) {
                        $Appearance | Add-Member -NotePropertyName 'VideoExceedsTierLimit' -NotePropertyValue $true -Force
                    } else {
                        $Appearance.VideoExceedsTierLimit = $true
                    }
                    
                    try {
                        Add-LinkToMeAzDataTableEntity @AppearanceTable -Entity $Appearance -Force
                        $Results.cleanupActions += "Marked video background as exceeding limit for page: $($Appearance.PageId)"
                        Write-Information "Marked video background as exceeding limit for appearance $($Appearance.RowKey)"
                    } catch {
                        Write-Warning "Failed to mark video background $($Appearance.RowKey): $($_.Exception.Message)"
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
        
        # 5b. Mark links with premium features that exceed tier limits (preserve data)
        try {
            $LinksTable = Get-LinkToMeTable -TableName 'Links'
            $AllLinks = @(Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId'")
            
            foreach ($Link in $AllLinks) {
                $Updated = $false
                
                # Check custom layouts (non-classic layouts)
                if (-not $Limits.customLayouts -and $Link.Layout -and $Link.Layout -ne 'classic') {
                    if (-not $Link.PSObject.Properties['LayoutExceedsTier']) {
                        $Link | Add-Member -NotePropertyName 'LayoutExceedsTier' -NotePropertyValue $true -Force
                    } else {
                        $Link.LayoutExceedsTier = $true
                    }
                    $Updated = $true
                }
                
                # Check link animations (non-none animations)
                if (-not $Limits.linkAnimations -and $Link.Animation -and $Link.Animation -ne 'none') {
                    if (-not $Link.PSObject.Properties['AnimationExceedsTier']) {
                        $Link | Add-Member -NotePropertyName 'AnimationExceedsTier' -NotePropertyValue $true -Force
                    } else {
                        $Link.AnimationExceedsTier = $true
                    }
                    $Updated = $true
                }
                
                # Check link scheduling
                if (-not $Limits.linkScheduling -and $Link.PSObject.Properties['ScheduleEnabled'] -and $Link.ScheduleEnabled -eq $true) {
                    if (-not $Link.PSObject.Properties['ScheduleExceedsTier']) {
                        $Link | Add-Member -NotePropertyName 'ScheduleExceedsTier' -NotePropertyValue $true -Force
                    } else {
                        $Link.ScheduleExceedsTier = $true
                    }
                    $Updated = $true
                }
                
                # Check link locking
                if (-not $Limits.linkLocking -and $Link.PSObject.Properties['LockEnabled'] -and $Link.LockEnabled -eq $true) {
                    if (-not $Link.PSObject.Properties['LockExceedsTier']) {
                        $Link | Add-Member -NotePropertyName 'LockExceedsTier' -NotePropertyValue $true -Force
                    } else {
                        $Link.LockExceedsTier = $true
                    }
                    $Updated = $true
                }
                
                # Clear flags if tier now allows features
                if ($Limits.customLayouts -and $Link.PSObject.Properties['LayoutExceedsTier'] -and $Link.LayoutExceedsTier -eq $true) {
                    $Link.LayoutExceedsTier = $false
                    $Updated = $true
                }
                if ($Limits.linkAnimations -and $Link.PSObject.Properties['AnimationExceedsTier'] -and $Link.AnimationExceedsTier -eq $true) {
                    $Link.AnimationExceedsTier = $false
                    $Updated = $true
                }
                if ($Limits.linkScheduling -and $Link.PSObject.Properties['ScheduleExceedsTier'] -and $Link.ScheduleExceedsTier -eq $true) {
                    $Link.ScheduleExceedsTier = $false
                    $Updated = $true
                }
                if ($Limits.linkLocking -and $Link.PSObject.Properties['LockExceedsTier'] -and $Link.LockExceedsTier -eq $true) {
                    $Link.LockExceedsTier = $false
                    $Updated = $true
                }
                
                if ($Updated) {
                    try {
                        Add-LinkToMeAzDataTableEntity @LinksTable -Entity $Link -Force
                        $Results.cleanupActions += "Marked premium features on link: $($Link.Title)"
                        Write-Information "Marked premium features as exceeding tier for link $($Link.RowKey)"
                    } catch {
                        Write-Warning "Failed to mark link features $($Link.RowKey): $($_.Exception.Message)"
                    }
                }
            }
        } catch {
            Write-Warning "Failed to mark link premium features: $($_.Exception.Message)"
        }
        
        # 6. Mark excess short links as exceeding limit (preserve data)
        try {
            # Get short link limit from tier features
            $MaxShortLinks = $Limits.maxShortLinks
            
            if ($MaxShortLinks -ne -1) {
                $ShortLinksTable = Get-LinkToMeTable -TableName 'ShortLinks'
                $ShortLinks = @(Get-LinkToMeAzDataTableEntity @ShortLinksTable -Filter "PartitionKey eq '$SafeUserId'" | Sort-Object CreatedAt)
                
                if ($ShortLinks.Count -gt $MaxShortLinks) {
                    $AllowedShortLinks = $ShortLinks | Select-Object -First $MaxShortLinks
                    $ExcessShortLinks = $ShortLinks | Select-Object -Skip $MaxShortLinks
                    
                    foreach ($ShortLink in $ExcessShortLinks) {
                        # Mark as exceeding tier limit (preserve data)
                        if (-not $ShortLink.PSObject.Properties['ExceedsTierLimit']) {
                            $ShortLink | Add-Member -NotePropertyName 'ExceedsTierLimit' -NotePropertyValue $true -Force
                        } else {
                            $ShortLink.ExceedsTierLimit = $true
                        }
                        
                        try {
                            Add-LinkToMeAzDataTableEntity @ShortLinksTable -Entity $ShortLink -Force
                            $Results.cleanupActions += "Marked excess short link as exceeding limit: $($ShortLink.RowKey)"
                            Write-Information "Marked short link $($ShortLink.RowKey) as exceeding tier limit"
                        } catch {
                            Write-Warning "Failed to mark short link $($ShortLink.RowKey): $($_.Exception.Message)"
                        }
                    }
                    
                    # Ensure allowed short links are not marked as exceeding limit
                    foreach ($ShortLink in $AllowedShortLinks) {
                        if ($ShortLink.PSObject.Properties['ExceedsTierLimit'] -and $ShortLink.ExceedsTierLimit -eq $true) {
                            $ShortLink.ExceedsTierLimit = $false
                            try {
                                Add-LinkToMeAzDataTableEntity @ShortLinksTable -Entity $ShortLink -Force
                            } catch {
                                Write-Warning "Failed to update short link $($ShortLink.RowKey): $($_.Exception.Message)"
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Information "ShortLinks table not found or accessible, skipping short link cleanup"
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
