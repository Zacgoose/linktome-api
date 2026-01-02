# User Tier & Premium Feature System

## Overview

LinkTome API now includes a comprehensive subscription tier system that enables you to:
- Define different subscription levels (Free, Premium, Enterprise)
- Validate user access to premium features
- Track feature usage for analytics and compliance
- Enforce usage limits based on subscription tier

## Architecture

### Components

1. **Tier Definitions** (`Get-TierFeatures`)
   - Defines available tiers: `free`, `premium`, `enterprise`
   - Specifies features and limits for each tier
   - Returns structured tier information

2. **Tier Validation** (`Test-UserTier`)
   - Checks if user meets minimum tier requirement
   - Validates subscription status (active, trial, expired)
   - Checks expiration dates

3. **Feature Access Control** (`Test-FeatureAccess`)
   - Validates user access to specific features
   - Checks both tier and subscription status
   - Returns boolean access permission

4. **Usage Tracking** (`Write-FeatureUsageEvent`)
   - Logs all feature access attempts
   - Tracks both allowed and denied access
   - Stores data in Azure Table Storage (`FeatureUsage` table)

## Database Schema

### Users Table (Extended Fields)

| Field | Type | Description |
|-------|------|-------------|
| `SubscriptionTier` | string | User's subscription tier: `free`, `premium`, or `enterprise` |
| `SubscriptionStatus` | string | Status: `active`, `trial`, or `expired` |
| `SubscriptionExpiresAt` | DateTimeOffset | When the subscription expires (optional) |

### FeatureUsage Table (New)

| Field | Type | Description |
|-------|------|-------------|
| `PartitionKey` | string | UserId (for efficient per-user queries) |
| `RowKey` | string | Timestamp + GUID for uniqueness |
| `EventTimestamp` | DateTimeOffset | When the feature was accessed |
| `Feature` | string | Feature identifier (e.g., `advanced_analytics`) |
| `Allowed` | bool | Whether access was granted or denied |
| `Tier` | string | User's tier at time of access |
| `IpAddress` | string | Client IP address (optional) |
| `Endpoint` | string | API endpoint accessed (optional) |

## Tier Definitions

### Free Tier
- **Max Links**: 5
- **Analytics Retention**: 30 days
- **Features**: 
  - `basic_profile`
  - `basic_links`
  - `basic_analytics`
  - `basic_appearance`
- **Limits**:
  - No custom themes
  - No advanced analytics
  - No API access
  - No custom domain

### Premium Tier
- **Max Links**: 25
- **Analytics Retention**: 365 days
- **Features**:
  - All free features
  - `advanced_links`
  - `advanced_analytics`
  - `custom_themes`
  - `api_access`
- **Limits**:
  - Custom themes enabled
  - Advanced analytics enabled
  - API access enabled
  - No custom domain

### Enterprise Tier
- **Max Links**: 100
- **Analytics Retention**: Unlimited
- **Features**:
  - All premium features
  - `custom_domain`
  - `priority_support`
  - `team_management`
- **Limits**:
  - All features enabled
  - Custom domain support
  - Priority support

## Usage Examples

### 1. Checking User Tier

```powershell
# Check if user has premium tier
$hasPremium = Test-UserTier -User $User -RequiredTier 'premium'

if (-not $hasPremium) {
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Body = @{ 
            error = "This feature requires a Premium subscription"
            upgradeRequired = $true
        }
    }
}
```

### 2. Checking Feature Access

```powershell
# Check if user can access advanced analytics
$hasAccess = Test-FeatureAccess -User $User -Feature 'advanced_analytics'

if (-not $hasAccess) {
    # Show limited data with upgrade message
    $Results.upgradeMessage = "Upgrade to Premium to unlock detailed analytics"
    $Results.advancedData = @()
} else {
    # Show full data
    $Results.advancedData = $DetailedAnalytics
}
```

### 3. Enforcing Link Limits

```powershell
# Get user's tier limits
$UserTier = if ($User.SubscriptionTier) { $User.SubscriptionTier } else { 'free' }
$TierInfo = Get-TierFeatures -Tier $UserTier
$MaxLinks = $TierInfo.limits.maxLinks

# Check if user would exceed limit
if ($ExistingLinks.Count + $NewLinks.Count -gt $MaxLinks) {
    Write-FeatureUsageEvent -UserId $UserId -Feature 'link_limit_exceeded' -Allowed $false -Tier $UserTier
    
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Body = @{ 
            error = "Link limit exceeded"
            currentTier = $UserTier
            maxLinks = $MaxLinks
            currentLinks = $ExistingLinks.Count
            upgradeRequired = $true
        }
    }
}
```

### 4. Tracking Feature Usage

```powershell
# Track when a user accesses a feature
$ClientIP = Get-ClientIPAddress -Request $Request
Write-FeatureUsageEvent `
    -UserId $UserId `
    -Feature 'advanced_analytics' `
    -Allowed $true `
    -Tier 'premium' `
    -IpAddress $ClientIP `
    -Endpoint 'admin/getAnalytics'
```

## Integration Points

### 1. User Signup
When users sign up, they are automatically assigned the `free` tier:
```powershell
$NewUser = @{
    # ... other fields ...
    SubscriptionTier = [string]'free'
    SubscriptionStatus = [string]'active'
}
```

### 2. Authentication Context
User tier information is included in the authentication context:
```powershell
$authContext = Get-UserAuthContext -User $User
# Returns:
# - SubscriptionTier
# - SubscriptionStatus
# - TierFeatures (array)
# - TierLimits (hashtable)
```

### 3. Analytics Endpoint
The analytics endpoint now includes tier-based feature gating:
- **Free tier**: Basic summary statistics only
- **Premium/Enterprise**: Full analytics with detailed data

### 4. Links Endpoint
The update links endpoint enforces tier-based limits:
- Checks against `maxLinks` from tier definition
- Returns detailed error with upgrade information
- Tracks denied attempts for analytics

## API Response Changes

### Authentication Responses (Login/Signup)
Now includes tier information:
```json
{
  "user": {
    "UserId": "user-123",
    "email": "user@example.com",
    "username": "johndoe",
    "userRole": "user",
    "roles": ["user"],
    "permissions": ["read:profile", "write:profile"],
    "subscriptionTier": "free",
    "subscriptionStatus": "active",
    "tierFeatures": ["basic_profile", "basic_links", "basic_analytics"],
    "tierLimits": {
      "maxLinks": 5,
      "analyticsRetentionDays": 30,
      "customThemes": false,
      "advancedAnalytics": false
    }
  }
}
```

### Analytics Endpoint
Now includes upgrade messaging for free users:
```json
{
  "summary": {
    "totalPageViews": 150,
    "totalLinkClicks": 45,
    "uniqueVisitors": 30
  },
  "hasAdvancedAnalytics": false,
  "upgradeMessage": "Upgrade to Premium to unlock detailed analytics...",
  "recentPageViews": [],
  "recentLinkClicks": [],
  "linkClicksByLink": [],
  "viewsByDay": [],
  "clicksByDay": []
}
```

### Links Endpoint (Limit Exceeded)
Returns detailed error with upgrade information:
```json
{
  "error": "Link limit exceeded. Your Free plan allows up to 5 links. You currently have 5 links.",
  "currentTier": "free",
  "maxLinks": 5,
  "currentLinks": 5,
  "upgradeRequired": true
}
```

## Future Enhancements

### Potential Additions
1. **Subscription Management Endpoints**
   - `POST /admin/upgradeSubscription` - Upgrade to higher tier
   - `GET /admin/subscriptionStatus` - Get current subscription details
   - `POST /admin/cancelSubscription` - Cancel or downgrade

2. **Usage Analytics Dashboard**
   - Track which features are most requested
   - Identify users hitting tier limits
   - Conversion funnel analytics

3. **Trial Periods**
   - Automatic trial period for new users
   - Time-limited access to premium features
   - Trial expiration handling

4. **Granular Feature Flags**
   - More specific feature controls
   - Per-feature enable/disable
   - A/B testing capabilities

5. **Usage Quotas**
   - API call limits per tier
   - Rate limiting by tier
   - Bandwidth/storage quotas

## Testing

Run the tier validation tests:
```bash
pwsh /tmp/test-tier-functions.ps1
```

### Test Coverage
- ✅ Tier feature definitions
- ✅ Tier validation logic
- ✅ Feature access checks
- ✅ Expired subscription handling
- ✅ Default tier behavior
- ✅ Link limit enforcement
- ✅ Analytics feature gating

## Maintenance

### Adding New Tiers
Edit `Get-TierFeatures.ps1` to add new tier definitions:
```powershell
$TierFeatures = @{
    'new_tier' = @{
        tierName = 'New Tier'
        features = @('feature1', 'feature2')
        limits = @{
            maxLinks = 50
            # ... other limits
        }
    }
}
```

### Adding New Features
1. Add feature to tier definitions in `Get-TierFeatures.ps1`
2. Implement feature gate using `Test-FeatureAccess`
3. Add usage tracking with `Write-FeatureUsageEvent`
4. Update documentation

### Querying Usage Data

Query feature usage from Azure Table Storage:
```powershell
$Table = Get-LinkToMeTable -TableName 'FeatureUsage'
$UsageEvents = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq 'user-123'"

# Analyze blocked attempts
$BlockedAttempts = $UsageEvents | Where-Object { -not $_.Allowed }
```

## Best Practices

1. **Always track feature usage** - Even for allowed access, track usage for analytics
2. **Provide clear upgrade messages** - Tell users what they need to do
3. **Check both tier and feature** - Use both validation methods for flexibility
4. **Handle expired subscriptions gracefully** - Downgrade to free tier automatically
5. **Default to free tier** - If no tier is set, assume free tier
6. **Return detailed error information** - Help users understand their limits

## Support

For questions or issues with the tier system:
- Review this documentation
- Check the test script for examples
- Examine existing implementations in:
  - `Invoke-AdminGetAnalytics.ps1`
  - `Invoke-AdminUpdateLinks.ps1`
