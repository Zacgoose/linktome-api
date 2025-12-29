# Tier-Based API Access - Quick Start Guide

> **📖 Complete Guide**: See [TIER_BASED_API_ACCESS.md](./TIER_BASED_API_ACCESS.md) for comprehensive implementation details.

## Overview

This quick-start guide helps you understand how to restrict **direct API access** (via API keys) based on user account tiers (Free, Pro, Enterprise).

## ⚠️ Important: UI vs API Access

**Tier limits apply ONLY to API key requests, NOT to UI requests:**

- ✅ **UI Requests** (from your web app via JWT cookies): **Unlimited** - Users can use the UI freely
- 🔑 **API Key Requests** (for integrations): **Tier-limited** - Rate limited based on subscription

## 🎯 What You'll Achieve

- Issue API keys for programmatic access
- Restrict API access by subscription tier
- Enforce rate limits based on tier (API keys only)
- Prevent login endpoint abuse
- Track API usage per user
- Handle tier upgrades/downgrades

## 🏗️ Architecture Summary

```
User Request
    ↓
Authentication (JWT cookie OR API key) ✅
    ↓
Is API Key? → YES → Tier Access Check (NEW) ✅
    │            ↓
    │         Rate Limit Check (NEW) ✅
    │            ↓
    NO → UI Request → NO tier limits ✅
    │
    ↓
Permission Check (Existing) ✅
    ↓
Endpoint Handler ✅
    ↓
Feature Limit Check (NEW) ✅
    ↓
Response
```

## 📊 Tier Comparison

| Feature | Free | Pro | Enterprise |
|---------|------|-----|------------|
| **UI Access** | Unlimited | Unlimited | Unlimited |
| **API Keys** | ❌ None | ✅ 3 keys | ✅ Unlimited |
| **API Rate Limit** | N/A | 1,000/hour | 10,000/hour |
| **Max Links** | 5 | Unlimited | Unlimited |
| **Analytics** | 7 days | Unlimited | Unlimited |
| **Appearance Customization** | ❌ | ✅ | ✅ |
| **Team Management** | ❌ | ❌ | ✅ |
| **Cost** | $0 | $9/mo | $49/mo |

## 🔧 Implementation Steps

### Step 0: Protect Login Endpoint (Critical!)

**Problem**: Users could call `/login` programmatically to get JWT cookies and bypass API key limits.

**Solution**: Add CAPTCHA and detect automation at login:

```powershell
# In Invoke-PublicLogin
function Invoke-PublicLogin {
    param($Request, $TriggerMetadata)
    
    # 1. Detect programmatic access
    $IsUIRequest = Test-IsUIRequest -Request $Request
    if (-not $IsUIRequest) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{
                error = "Programmatic login not allowed"
                message = "Create an API key for API access"
            }
        }
    }
    
    # 2. Verify CAPTCHA
    if (-not (Verify-CaptchaToken -Token $Body.captchaToken)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "CAPTCHA verification failed" }
        }
    }
    
    # 3. Continue with normal login...
}

function Test-IsUIRequest {
    param($Request)
    
    # Check for browser-specific headers
    $Score = 0
    if ($Request.Headers.'sec-fetch-site') { $Score += 2 }
    if ($Request.Headers.'User-Agent' -match 'Chrome|Firefox|Safari') { $Score += 3 }
    if ($Request.Headers.'User-Agent' -match 'curl|python|postman') { $Score -= 5 }
    
    return $Score -ge 5
}
```

### Step 1: Update User Schema

Add these fields to your Users table:

```powershell
# In signup or migration script
$User = @{
    # ... existing fields ...
    
    # Tier fields
    Tier = 'free'  # 'free', 'pro', 'enterprise'
    TierStartDate = (Get-Date).ToUniversalTime()
    TierEndDate = $null  # For subscriptions
    
    # Usage tracking
    ApiUsageResetDate = (Get-Date).ToUniversalTime()
    ApiRequestCount = 0
    ApiRequestLimit = 100  # Based on tier
    
    # Feature limits
    MaxLinks = 5  # Free tier
    AnalyticsRetentionDays = 7
}
```

### Step 2: Create Tier Limits Function

Create `Modules/LinkTomeCore/Private/Auth/Get-UserTierLimits.ps1`:

```powershell
function Get-UserTierLimits {
    param([string]$Tier)
    
    $TierLimits = @{
        'free' = @{
            ApiRequestsPerHour = 100
            MaxLinks = 5
            AnalyticsRetentionDays = 7
            AllowedEndpoints = @(
                'admin/getProfile',
                'admin/updateProfile',
                'admin/getLinks',
                'admin/updateLinks',
                'admin/getDashboardStats'
            )
        }
        'pro' = @{
            ApiRequestsPerHour = 1000
            MaxLinks = -1  # Unlimited
            AnalyticsRetentionDays = -1
            AllowedEndpoints = @(
                # All basic endpoints plus:
                'admin/getAnalytics',
                'admin/getAppearance',
                'admin/updateAppearance'
            )
        }
        'enterprise' = @{
            ApiRequestsPerHour = 10000
            MaxLinks = -1
            AnalyticsRetentionDays = -1
            AllowedEndpoints = @(
                # All endpoints including team management
                'admin/UserManagerList',
                'admin/UserManagerInvite',
                'admin/UserManagerRemove',
                'admin/UserManagerRespond'
            )
        }
    }
    
    return $TierLimits[$Tier]
}
```

### Step 3: Create Tier Access Check

Create `Modules/LinkTomeCore/Private/Auth/Test-TierAccess.ps1`:

```powershell
function Test-TierAccess {
    param(
        [object]$User,
        [string]$Endpoint
    )
    
    $Tier = $User.Tier ?? 'free'
    $TierLimits = Get-UserTierLimits -Tier $Tier
    
    # Check endpoint access
    if ($TierLimits.AllowedEndpoints -notcontains $Endpoint) {
        return @{
            Allowed = $false
            Reason = 'EndpointNotAllowedForTier'
            Message = "Upgrade to Pro to access this feature"
        }
    }
    
    # Check rate limit
    $Now = [DateTimeOffset]::UtcNow
    $ResetDate = [DateTimeOffset]$User.ApiUsageResetDate
    
    if ($Now -gt $ResetDate.AddHours(1)) {
        return @{ Allowed = $true; ResetUsage = $true }
    }
    
    if ([int]$User.ApiRequestCount -ge $TierLimits.ApiRequestsPerHour) {
        return @{
            Allowed = $false
            Reason = 'TierRateLimitExceeded'
            Message = "Rate limit exceeded. Upgrade for higher limits."
            RetryAfter = 3600 - ($Now - $ResetDate).TotalSeconds
        }
    }
    
    return @{ Allowed = $true; IncrementUsage = $true }
}
```

### Step 4: Integrate into Request Router

Update `Modules/LinkTomeEntrypoints/LinkTomeEntrypoints.psm1`:

```powershell
# After authentication check for admin endpoints
if ($Endpoint -match '^admin/') {
    $User = Get-UserFromRequest -Request $Request
    if (-not $User) {
        # Handle auth failure...
    }
    
    # 🆕 ADD THIS: Tier access check
    $TierCheck = Test-TierAccess -User $User -Endpoint $Endpoint
    
    if (-not $TierCheck.Allowed) {
        $StatusCode = if ($TierCheck.Reason -eq 'TierRateLimitExceeded') {
            [HttpStatusCode]::TooManyRequests  # 429
        } else {
            [HttpStatusCode]::PaymentRequired  # 402
        }
        
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Body = @{
                error = $TierCheck.Message
                currentTier = $User.Tier
                upgradeUrl = "https://linktome.com/pricing"
            }
        }
    }
    
    # Update usage counter
    if ($TierCheck.IncrementUsage) {
        # Increment User.ApiRequestCount in database
    }
    
    # Continue to permission check...
}
```

### Step 5: Add Feature Limits

Example: Limit link count for free tier in `Invoke-AdminUpdateLinks.ps1`:

```powershell
# After authentication
$User = $Request.AuthenticatedUser
$TierLimits = Get-UserTierLimits -Tier $User.Tier

# Check link count
if ($TierLimits.MaxLinks -ne -1) {
    $LinkCount = ($Body.links | Measure-Object).Count
    if ($LinkCount -gt $TierLimits.MaxLinks) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::PaymentRequired
            Body = @{
                error = "Free tier limited to $($TierLimits.MaxLinks) links"
                currentTier = 'free'
                upgradeUrl = "https://linktome.com/pricing"
            }
        }
    }
}
```

### Step 6: Update Signup to Set Tier

Update `Invoke-PublicSignup.ps1`:

```powershell
$NewUser = @{
    # ... existing fields ...
    
    # Add tier fields
    Tier = 'free'
    TierStartDate = (Get-Date).ToUniversalTime()
    ApiUsageResetDate = (Get-Date).ToUniversalTime()
    ApiRequestCount = 0
    ApiRequestLimit = 100
    MaxLinks = 5
    AnalyticsRetentionDays = 7
}
```

## 🔄 Handling Tier Changes

### Upgrade User to Pro

```powershell
function Update-UserTier {
    param(
        [string]$UserId,
        [string]$NewTier  # 'pro' or 'enterprise'
    )
    
    $Table = Get-LinkToMeTable -TableName 'Users'
    $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$UserId'" | Select-Object -First 1
    
    $TierLimits = Get-UserTierLimits -Tier $NewTier
    
    $User.Tier = $NewTier
    $User.TierStartDate = (Get-Date).ToUniversalTime()
    $User.ApiRequestLimit = $TierLimits.ApiRequestsPerHour
    $User.MaxLinks = $TierLimits.MaxLinks
    $User.AnalyticsRetentionDays = $TierLimits.AnalyticsRetentionDays
    
    # Reset usage counters
    $User.ApiRequestCount = 0
    $User.ApiUsageResetDate = (Get-Date).ToUniversalTime()
    
    Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
}
```

## 📡 API Response Examples

### Success (200 OK)
```json
{
  "links": [...],
  "headers": {
    "X-RateLimit-Limit": "100",
    "X-RateLimit-Remaining": "87",
    "X-RateLimit-Reset": "1640995200",
    "X-Tier": "free"
  }
}
```

### Tier Restriction (402 Payment Required)
```json
{
  "error": "This endpoint requires a Pro or Enterprise subscription",
  "currentTier": "free",
  "requiredTier": "pro",
  "upgradeUrl": "https://linktome.com/pricing"
}
```

### Rate Limit Exceeded (429 Too Many Requests)
```json
{
  "error": "API rate limit exceeded. Upgrade to Pro for higher limits.",
  "reason": "TierRateLimitExceeded",
  "currentUsage": 100,
  "limit": 100,
  "retryAfter": 1847
}
```

## 💳 Payment Integration (Stripe Example)

### Webhook Handler

Create `Modules/PublicApi/Public/Invoke-WebhooksStripe.ps1`:

```powershell
function Invoke-WebhooksStripe {
    param($Request)
    
    # Verify Stripe signature
    $Event = $Request.Body
    
    switch ($Event.type) {
        'customer.subscription.created' {
            $CustomerId = $Event.data.object.customer
            # Get UserId from metadata
            Update-UserTier -UserId $UserId -NewTier 'pro'
        }
        
        'customer.subscription.deleted' {
            Update-UserTier -UserId $UserId -NewTier 'free'
        }
        
        'invoice.payment_failed' {
            # Send notification to user
        }
    }
    
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{ received = $true }
    }
}
```

## 🧪 Testing

### Test Tier Access
```powershell
# Test free tier denied from analytics
$User = @{ UserId = 'test'; Tier = 'free'; ApiRequestCount = 0 }
$Result = Test-TierAccess -User $User -Endpoint 'admin/getAnalytics'
# Expected: Allowed = $false

# Test pro tier allowed
$User.Tier = 'pro'
$Result = Test-TierAccess -User $User -Endpoint 'admin/getAnalytics'
# Expected: Allowed = $true
```

### Test Rate Limits
```powershell
# Simulate rate limit hit
$User = @{ 
    UserId = 'test'
    Tier = 'free'
    ApiRequestCount = 100
    ApiRequestLimit = 100
    ApiUsageResetDate = (Get-Date).ToUniversalTime()
}
$Result = Test-TierAccess -User $User -Endpoint 'admin/getProfile'
# Expected: Allowed = $false, Reason = 'TierRateLimitExceeded'
```

## 📋 Migration Checklist

- [ ] Add tier fields to Users table
- [ ] Create `Get-UserTierLimits` function
- [ ] Create `Test-TierAccess` function
- [ ] Update request router with tier checks
- [ ] Add feature limits to endpoints
- [ ] Update signup process
- [ ] Create tier management functions
- [ ] Migrate existing users to free tier
- [ ] Integrate payment processor
- [ ] Create webhook handlers
- [ ] Add rate limit headers to responses
- [ ] Test all tiers thoroughly

## 🎨 Frontend Integration

### Handle 402 Response
```javascript
async function apiCall(endpoint) {
  const response = await fetch(endpoint, { credentials: 'include' });
  
  if (response.status === 402) {
    const data = await response.json();
    // Show upgrade modal
    showUpgradeModal({
      message: data.error,
      currentTier: data.currentTier,
      upgradeUrl: data.upgradeUrl
    });
    return null;
  }
  
  return response.json();
}
```

### Display Tier Badge
```jsx
function TierBadge({ tier }) {
  const colors = {
    free: 'gray',
    pro: 'blue',
    enterprise: 'purple'
  };
  
  return (
    <Badge color={colors[tier]}>
      {tier.toUpperCase()}
    </Badge>
  );
}
```

## 🔍 Monitoring

### Key Metrics
- Users per tier (free/pro/enterprise)
- Conversion rate (free → paid)
- API requests per tier
- Rate limit violations
- Revenue (MRR/ARR)

### Log Events
```powershell
Write-SecurityEvent -EventType 'TierAccessDenied' -UserId $UserId -Endpoint $Endpoint
Write-SecurityEvent -EventType 'TierRateLimitExceeded' -UserId $UserId
Write-SecurityEvent -EventType 'TierChanged' -UserId $UserId -NewTier $NewTier
```

## 🚀 Deployment Steps

1. **Update database schema** - Add tier fields to Users table
2. **Deploy tier functions** - `Get-UserTierLimits`, `Test-TierAccess`
3. **Update request router** - Add tier checks
4. **Migrate existing users** - Set all to 'free' tier
5. **Test thoroughly** - All tiers and endpoints
6. **Deploy payment integration** - Stripe/PayPal webhooks
7. **Update frontend** - Handle 402 responses, show tier info
8. **Launch pricing page** - Enable upgrades
9. **Monitor** - Track metrics and errors

## 📞 Need Help?

- **Full Guide**: [TIER_BASED_API_ACCESS.md](./TIER_BASED_API_ACCESS.md)
- **Issues**: https://github.com/Zacgoose/linktome-api/issues
- **Architecture**: See README.md for overall system design

---

**Next Steps**: Start with Step 1 (Update User Schema) and work through each step sequentially. Test thoroughly at each stage before moving on.
