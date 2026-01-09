function Get-TierFeatures {
    <#
    .SYNOPSIS
        Get features and limits available for a subscription tier
    .DESCRIPTION
        Returns the features, limits, and capabilities available for each tier.
        Aligns with frontend tier configuration in src/types/tiers.ts
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('free', 'pro', 'premium', 'enterprise')]
        [string]$Tier
    )
    
    $TierFeatures = @{
        'free' = @{
            tierName = 'Free'
            features = @(
                'basic_profile',
                'basic_links',
                'basic_analytics',
                'basic_appearance',
                'custom_themes'
            )
            limits = @{
                # Page features
                maxPages = 1
                
                # Link features
                maxLinks = 10
                maxLinkGroups = 2
                customLayouts = $false
                linkAnimations = $false
                linkScheduling = $false
                linkLocking = $false
                
                # Appearance features
                customThemes = $false  # Premium themes (agate, astrid, aura, bloom, breeze)
                premiumFonts = $false
                customLogos = $false
                videoBackgrounds = $false
                removeFooter = $false
                
                # Analytics features
                advancedAnalytics = $false
                analyticsExport = $false
                analyticsRetentionDays = 30
                
                # API features
                apiAccess = $false
                apiKeysLimit = 0
                apiRequestsPerMinute = 0
                apiRequestsPerDay = 0
                
                # Other features
                customDomain = $false
                prioritySupport = $false
                whiteLabel = $false
            }
        }
        'pro' = @{
            tierName = 'Pro'
            features = @(
                'basic_profile',
                'basic_links',
                'advanced_links',
                'basic_analytics',
                'advanced_analytics',
                'basic_appearance',
                'custom_themes',
                'api_access'
            )
            limits = @{
                # Page features
                maxPages = 3
                
                # Link features
                maxLinks = 50
                maxLinkGroups = 10
                customLayouts = $true
                linkAnimations = $true
                linkScheduling = $true
                linkLocking = $true
                
                # Appearance features
                customThemes = $true
                premiumFonts = $true
                customLogos = $true
                videoBackgrounds = $false
                removeFooter = $true
                
                # Analytics features
                advancedAnalytics = $true
                analyticsExport = $true
                analyticsRetentionDays = 90
                
                # API features
                apiAccess = $true
                apiKeysLimit = 3
                apiRequestsPerMinute = 60
                apiRequestsPerDay = 10000
                
                # Other features
                customDomain = $false
                prioritySupport = $false
                whiteLabel = $false
            }
        }
        'premium' = @{
            tierName = 'Premium'
            features = @(
                'basic_profile',
                'basic_links',
                'advanced_links',
                'basic_analytics',
                'advanced_analytics',
                'basic_appearance',
                'custom_themes',
                'api_access',
                'custom_domain',
                'priority_support'
            )
            limits = @{
                # Page features
                maxPages = 10
                
                # Link features
                maxLinks = 100
                maxLinkGroups = 25
                customLayouts = $true
                linkAnimations = $true
                linkScheduling = $true
                linkLocking = $true
                
                # Appearance features
                customThemes = $true
                premiumFonts = $true
                customLogos = $true
                videoBackgrounds = $true
                removeFooter = $true
                
                # Analytics features
                advancedAnalytics = $true
                analyticsExport = $true
                analyticsRetentionDays = 365
                
                # API features
                apiAccess = $true
                apiKeysLimit = 10
                apiRequestsPerMinute = 120
                apiRequestsPerDay = 50000
                
                # Other features
                customDomain = $true
                prioritySupport = $true
                whiteLabel = $false
            }
        }
        'enterprise' = @{
            tierName = 'Enterprise'
            features = @(
                'basic_profile',
                'basic_links',
                'advanced_links',
                'basic_analytics',
                'advanced_analytics',
                'basic_appearance',
                'custom_themes',
                'api_access',
                'custom_domain',
                'priority_support',
                'team_management',
                'white_label'
            )
            limits = @{
                # Page features
                maxPages = -1  # Unlimited
                
                # Link features
                maxLinks = -1  # Unlimited
                maxLinkGroups = -1  # Unlimited
                customLayouts = $true
                linkAnimations = $true
                linkScheduling = $true
                linkLocking = $true
                
                # Appearance features
                customThemes = $true
                premiumFonts = $true
                customLogos = $true
                videoBackgrounds = $true
                removeFooter = $true
                
                # Analytics features
                advancedAnalytics = $true
                analyticsExport = $true
                analyticsRetentionDays = -1  # Unlimited
                
                # API features
                apiAccess = $true
                apiKeysLimit = -1  # Unlimited
                apiRequestsPerMinute = 300
                apiRequestsPerDay = -1  # Unlimited
                
                # Other features
                customDomain = $true
                prioritySupport = $true
                whiteLabel = $true
            }
        }
    }
    
    return $TierFeatures[$Tier]
}
