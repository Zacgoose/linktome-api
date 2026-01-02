function Get-TierFeatures {
    <#
    .SYNOPSIS
        Get features and limits available for a subscription tier
    .DESCRIPTION
        Returns the features, limits, and capabilities available for each tier
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('free', 'premium', 'enterprise')]
        [string]$Tier
    )
    
    $TierFeatures = @{
        'free' = @{
            tierName = 'Free'
            features = @(
                'basic_profile',
                'basic_links',
                'basic_analytics',
                'basic_appearance'
            )
            limits = @{
                maxLinks = 5
                analyticsRetentionDays = 30
                customThemes = $false
                advancedAnalytics = $false
                apiAccess = $false
                customDomain = $false
                prioritySupport = $false
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
                'api_access'
            )
            limits = @{
                maxLinks = 25
                analyticsRetentionDays = 365
                customThemes = $true
                advancedAnalytics = $true
                apiAccess = $true
                customDomain = $false
                prioritySupport = $false
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
                'team_management'
            )
            limits = @{
                maxLinks = 100
                analyticsRetentionDays = -1  # Unlimited
                customThemes = $true
                advancedAnalytics = $true
                apiAccess = $true
                customDomain = $true
                prioritySupport = $true
            }
        }
    }
    
    return $TierFeatures[$Tier]
}
