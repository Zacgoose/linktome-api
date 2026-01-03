# Example: Adding Tier Gates to a New Feature

This guide shows you how to add tier validation to a new feature in the LinkTome API.

## Scenario: Adding Custom Themes (Premium Feature)

Let's say you want to add a custom themes feature that should only be available to Premium and Enterprise users.

### Step 1: Update Tier Definitions

If the feature isn't already defined, add it to the tier definitions in `Get-TierFeatures.ps1`:

```powershell
# Already included in premium tier:
'premium' = @{
    features = @(
        # ... other features ...
        'custom_themes'  # Already defined
    )
    limits = @{
        customThemes = $true
    }
}
```

### Step 2: Create or Update the Endpoint

Create a new endpoint file (e.g., `Invoke-AdminApplyCustomTheme.ps1`):

```powershell
function Invoke-AdminApplyCustomTheme {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:appearance
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = $Request.AuthenticatedUser.UserId
    $Body = $Request.Body
    
    try {
        # Step 1: Get the user object
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Step 2: Check feature access
        $hasCustomThemes = Test-FeatureAccess -User $User -Feature 'custom_themes'
        
        # Step 3: Track the access attempt
        $ClientIP = Get-ClientIPAddress -Request $Request
        $UserTier = if ($User.SubscriptionTier) { $User.SubscriptionTier } else { 'free' }
        Write-FeatureUsageEvent `
            -UserId $UserId `
            -Feature 'custom_themes' `
            -Allowed $hasCustomThemes `
            -Tier $UserTier `
            -IpAddress $ClientIP `
            -Endpoint 'admin/applyCustomTheme'
        
        # Step 4: Deny access if not allowed
        if (-not $hasCustomThemes) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{ 
                    error = "Custom themes are only available for Premium and Enterprise users"
                    currentTier = $UserTier
                    requiredTier = "premium"
                    upgradeRequired = $true
                    feature = "custom_themes"
                }
            }
        }
        
        # Step 5: Apply the custom theme (your feature logic here)
        $AppearanceTable = Get-LinkToMeTable -TableName 'Appearance'
        
        # Validate theme data
        if (-not $Body.customTheme) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Custom theme data required" }
            }
        }
        
        # Save custom theme
        $ThemeEntity = @{
            PartitionKey = $UserId
            RowKey = 'custom-theme'
            ThemeData = ($Body.customTheme | ConvertTo-Json -Compress)
            UpdatedAt = [DateTimeOffset]::UtcNow
        }
        
        Add-LinkToMeAzDataTableEntity @AppearanceTable -Entity $ThemeEntity -Force
        
        # Return success
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = @{ 
                message = "Custom theme applied successfully"
                theme = $Body.customTheme
            }
        }
        
    } catch {
        Write-Error "Apply custom theme error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to apply custom theme"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = $Results
        }
    }
}
```

### Step 3: Alternative - Soft Feature Gate (Show Limited Version)

For features where you want to show a limited version to free users:

```powershell
function Invoke-AdminGetThemes {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = $Request.AuthenticatedUser.UserId
    
    try {
        # Get user
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$UserId'" | Select-Object -First 1
        
        # Check access
        $hasCustomThemes = Test-FeatureAccess -User $User -Feature 'custom_themes'
        $UserTier = if ($User.SubscriptionTier) { $User.SubscriptionTier } else { 'free' }
        
        # Track access
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-FeatureUsageEvent -UserId $UserId -Feature 'custom_themes' -Allowed $hasCustomThemes -Tier $UserTier -IpAddress $ClientIP
        
        # Get themes
        $ThemesTable = Get-LinkToMeTable -TableName 'Themes'
        $AllThemes = Get-LinkToMeAzDataTableEntity @ThemesTable
        
        if ($hasCustomThemes) {
            # Premium users: Return all themes including custom ones
            $Results = @{
                themes = $AllThemes
                canCreateCustom = $true
                tier = $UserTier
            }
        } else {
            # Free users: Return only basic themes
            $BasicThemes = $AllThemes | Where-Object { $_.IsBasic -eq $true }
            $Results = @{
                themes = $BasicThemes
                canCreateCustom = $false
                tier = $UserTier
                upgradeMessage = "Upgrade to Premium to create and use custom themes"
                premiumThemesCount = ($AllThemes | Where-Object { $_.IsBasic -ne $true }).Count
            }
        }
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = $Results
        }
        
    } catch {
        # Error handling...
    }
}
```

## Quick Checklist for Adding Tier Gates

When adding a new premium feature, follow this checklist:

- [ ] 1. **Define the feature** in tier definitions (`Get-TierFeatures.ps1`)
- [ ] 2. **Get the user object** from the database
- [ ] 3. **Check feature access** using `Test-FeatureAccess`
- [ ] 4. **Track the access attempt** using `Write-FeatureUsageEvent`
- [ ] 5. **Return appropriate response**:
  - If denied: Return 403 with upgrade message
  - If allowed: Proceed with feature logic
- [ ] 6. **Document the feature** in `TIER_SYSTEM.md`
- [ ] 7. **Update API response docs** in `API_RESPONSE_FORMAT.md`

## Common Patterns

### Pattern 1: Hard Gate (Block Free Users)
```powershell
if (-not (Test-FeatureAccess -User $User -Feature 'premium_feature')) {
    Write-FeatureUsageEvent -UserId $UserId -Feature 'premium_feature' -Allowed $false -Tier $UserTier
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Body = @{ 
            error = "This feature requires Premium"
            upgradeRequired = $true
        }
    }
}
```

### Pattern 2: Soft Gate (Show Limited Version)
```powershell
$hasAdvanced = Test-FeatureAccess -User $User -Feature 'advanced_feature'
Write-FeatureUsageEvent -UserId $UserId -Feature 'advanced_feature' -Allowed $hasAdvanced -Tier $UserTier

if ($hasAdvanced) {
    $Results.fullData = $CompleteData
} else {
    $Results.limitedData = $BasicData
    $Results.upgradeMessage = "Upgrade for full access"
}
```

### Pattern 3: Usage Limit (Links, API Calls, etc.)
```powershell
$TierInfo = Get-TierFeatures -Tier $UserTier
$MaxAllowed = $TierInfo.limits.maxItems

if ($CurrentCount + $NewCount -gt $MaxAllowed) {
    Write-FeatureUsageEvent -UserId $UserId -Feature 'limit_exceeded' -Allowed $false -Tier $UserTier
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Body = @{ 
            error = "Limit exceeded"
            currentTier = $UserTier
            maxAllowed = $MaxAllowed
            current = $CurrentCount
            upgradeRequired = $true
        }
    }
}
```

## Testing Your Feature Gate

Create a test script:

```powershell
#!/usr/bin/env pwsh

$ProjectRoot = '/path/to/linktome-api'
Import-Module (Join-Path $ProjectRoot 'Modules/LinkTomeCore/LinkTomeCore.psd1') -Force

# Test 1: Free user should be blocked
$freeUser = @{ SubscriptionTier = 'free'; SubscriptionStatus = 'active' }
$result = Test-FeatureAccess -User $freeUser -Feature 'custom_themes'
Write-Host "Free user accessing custom_themes: $result (expected: False)" -ForegroundColor $(if (-not $result) { 'Green' } else { 'Red' })

# Test 2: Premium user should have access
$premiumUser = @{ SubscriptionTier = 'premium'; SubscriptionStatus = 'active' }
$result = Test-FeatureAccess -User $premiumUser -Feature 'custom_themes'
Write-Host "Premium user accessing custom_themes: $result (expected: True)" -ForegroundColor $(if ($result) { 'Green' } else { 'Red' })

# Test 3: Expired premium user should be blocked
$expiredUser = @{ SubscriptionTier = 'premium'; SubscriptionStatus = 'expired' }
$result = Test-FeatureAccess -User $expiredUser -Feature 'custom_themes'
Write-Host "Expired user accessing custom_themes: $result (expected: False)" -ForegroundColor $(if (-not $result) { 'Green' } else { 'Red' })
```

## Best Practices

1. **Always track usage** - Even for allowed access, so you can see feature adoption
2. **Provide clear messages** - Tell users exactly what they need to do
3. **Be consistent** - Use the same error format across all gated features
4. **Default to free** - If tier is missing, assume free tier
5. **Check subscription status** - Don't forget to validate expiration
6. **Document everything** - Update all relevant docs when adding features

## Need Help?

- See full examples in:
  - `Invoke-AdminGetAnalytics.ps1` - Soft gate example
  - `Invoke-AdminUpdateLinks.ps1` - Usage limit example
- Read the complete guide: `TIER_SYSTEM.md`
- Check API docs: `API_RESPONSE_FORMAT.md`
