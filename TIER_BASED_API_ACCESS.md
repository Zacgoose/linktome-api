# Tier-Based API Access Restriction - Implementation Guide

## Overview

This document provides a comprehensive guide for implementing tier-based API access restrictions in the LinkTome API. The system will allow you to restrict direct API access based on user account tiers/pricing models (e.g., Free, Pro, Enterprise).

## Table of Contents

1. [Current System Architecture](#current-system-architecture)
2. [Proposed Tier System](#proposed-tier-system)
3. [Database Schema Changes](#database-schema-changes)
4. [Tier Enforcement Layer](#tier-enforcement-layer)
5. [API Endpoint Tier Restrictions](#api-endpoint-tier-restrictions)
6. [Rate Limiting by Tier](#rate-limiting-by-tier)
7. [Backend Integration Requirements](#backend-integration-requirements)
8. [Implementation Roadmap](#implementation-roadmap)
9. [Monitoring and Analytics](#monitoring-and-analytics)

---

## Current System Architecture

### Authentication & Authorization
The LinkTome API currently uses:
- **JWT-based authentication** with HTTP-only cookies
- **Role-based access control (RBAC)** with two roles:
  - `user` - Full access to their own profile, links, analytics, and appearance
  - `user_manager` - Limited access to manage specific user accounts
- **Permission system** with granular permissions like:
  - `read:profile`, `write:profile`
  - `read:links`, `write:links`
  - `read:analytics`, `read:dashboard`
  - `read:appearance`, `write:appearance`
- **Rate limiting** on authentication endpoints (login/signup)

### Current User Schema
Users table stores:
- `PartitionKey`: Email (lowercase)
- `RowKey`: UserId (guid)
- `Username`: Username (lowercase)
- `DisplayName`, `Bio`, `Avatar`: Profile information
- `PasswordHash`, `PasswordSalt`: Authentication
- `IsActive`: Account status
- `Roles`: JSON array of role names
- `Permissions`: JSON array of permission strings

### Request Flow
1. HTTP request → `HttpTrigger/function.json`
2. Request routing → `LinkTomeEntrypoints.psm1`
3. Authentication check → `Get-UserFromRequest` (JWT validation)
4. Permission check → `Test-ContextAwarePermission`
5. Endpoint handler → `Invoke-Admin*` or `Invoke-Public*` functions

---

## Proposed Tier System

### Tier Definitions

#### Free Tier
- **Cost**: $0/month
- **Target**: Individual users testing the platform
- **API Access**: Limited to basic profile and link management
- **Rate Limits**: Strict (e.g., 100 requests/hour)
- **Features**:
  - Basic profile management (read/write)
  - Up to 5 links
  - Basic analytics (last 7 days)
  - Public profile page

#### Pro Tier
- **Cost**: $9/month (example)
- **Target**: Content creators and professionals
- **API Access**: Full API access for personal use
- **Rate Limits**: Moderate (e.g., 1,000 requests/hour)
- **Features**:
  - Full profile management
  - Unlimited links
  - Full analytics (unlimited history)
  - Custom appearance themes
  - API access for integrations

#### Enterprise Tier
- **Cost**: $49/month (example)
- **Target**: Businesses and agencies
- **API Access**: Full API access with higher limits
- **Rate Limits**: High (e.g., 10,000 requests/hour)
- **Features**:
  - All Pro features
  - Team management (user_manager role support)
  - Priority support
  - Advanced analytics
  - Webhook support (future)
  - Custom domain (future)

---

## Database Schema Changes

### 1. Add Tier Field to Users Table

**Modify User Entity** to include:
```powershell
# New fields to add to Users table
$NewUser = @{
    # ... existing fields ...
    
    # Tier System
    Tier = [string]'free'  # Options: 'free', 'pro', 'enterprise'
    TierStartDate = [datetime]$Now  # When current tier started
    TierEndDate = [datetime]$null  # Null for active, date for expired
    
    # API Usage Tracking
    ApiUsageResetDate = [datetime]$Now  # When to reset usage counters
    ApiRequestCount = [int]0  # Current period request count
    ApiRequestLimit = [int]100  # Requests allowed per period (hourly)
    
    # Feature Limits
    MaxLinks = [int]5  # Free tier limit
    AnalyticsRetentionDays = [int]7  # Free tier limit
}
```

### 2. Create Subscriptions Table (Optional - for payment tracking)

If you want to track subscription history and payments:

```powershell
# Table: Subscriptions
# Purpose: Track subscription history and billing
$Subscription = @{
    PartitionKey = [string]$UserId  # User identifier
    RowKey = [string]$SubscriptionId  # Unique subscription ID
    
    Tier = [string]'pro'  # Subscription tier
    Status = [string]'active'  # active, cancelled, expired, past_due
    
    StartDate = [datetime]$Now
    EndDate = [datetime]$EndDate  # When subscription ends
    RenewalDate = [datetime]$RenewalDate  # Next billing date
    
    # Payment Information (DO NOT store full card details)
    PaymentProcessor = [string]'stripe'  # stripe, paypal, etc.
    PaymentProcessorCustomerId = [string]'cus_xxx'  # External customer ID
    PaymentProcessorSubscriptionId = [string]'sub_xxx'  # External subscription ID
    
    # Pricing
    Price = [decimal]9.99
    Currency = [string]'USD'
    BillingPeriod = [string]'monthly'  # monthly, yearly
    
    # Metadata
    CreatedAt = [datetime]$Now
    UpdatedAt = [datetime]$Now
    CancelledAt = [datetime]$null
}
```

### 3. Create ApiUsageHistory Table (for analytics)

Track API usage over time:

```powershell
# Table: ApiUsageHistory
# Purpose: Track API usage for analytics and billing
$UsageRecord = @{
    PartitionKey = [string]"$UserId-$Date"  # User + Date (YYYY-MM-DD)
    RowKey = [string]$Timestamp  # ISO 8601 timestamp
    
    Endpoint = [string]'/admin/getProfile'
    Method = [string]'GET'
    StatusCode = [int]200
    ResponseTime = [int]150  # milliseconds
    
    Tier = [string]'pro'  # User's tier at time of request
    
    IpAddress = [string]$ClientIP
    UserAgent = [string]$UserAgent
}
```

---

## Tier Enforcement Layer

### 1. Create Tier Validation Function

Create a new file: `Modules/LinkTomeCore/Private/Auth/Get-UserTierLimits.ps1`

```powershell
function Get-UserTierLimits {
    <#
    .SYNOPSIS
        Get tier limits for a user
    .DESCRIPTION
        Returns tier-specific limits and restrictions for a user
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Tier
    )
    
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
            RateLimitWindow = 3600  # 1 hour in seconds
        }
        'pro' = @{
            ApiRequestsPerHour = 1000
            MaxLinks = -1  # Unlimited
            AnalyticsRetentionDays = -1  # Unlimited
            AllowedEndpoints = @(
                'admin/getProfile',
                'admin/updateProfile',
                'admin/getLinks',
                'admin/updateLinks',
                'admin/getAnalytics',
                'admin/getDashboardStats',
                'admin/getAppearance',
                'admin/updateAppearance'
            )
            RateLimitWindow = 3600
        }
        'enterprise' = @{
            ApiRequestsPerHour = 10000
            MaxLinks = -1  # Unlimited
            AnalyticsRetentionDays = -1  # Unlimited
            AllowedEndpoints = @(
                # All endpoints allowed
                'admin/getProfile',
                'admin/updateProfile',
                'admin/getLinks',
                'admin/updateLinks',
                'admin/getAnalytics',
                'admin/getDashboardStats',
                'admin/getAppearance',
                'admin/updateAppearance',
                'admin/UserManagerList',
                'admin/UserManagerInvite',
                'admin/UserManagerRemove',
                'admin/UserManagerRespond'
            )
            RateLimitWindow = 3600
        }
    }
    
    return $TierLimits[$Tier]
}
```

### 2. Create Tier Access Check Function

Create a new file: `Modules/LinkTomeCore/Private/Auth/Test-TierAccess.ps1`

```powershell
function Test-TierAccess {
    <#
    .SYNOPSIS
        Check if user's tier allows access to endpoint
    .DESCRIPTION
        Validates tier-based access and rate limits
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,
        
        [Parameter(Mandatory)]
        [string]$Endpoint
    )
    
    # Get user's tier (default to free if not set)
    $Tier = $User.Tier
    if (-not $Tier) {
        $Tier = 'free'
    }
    
    # Get tier limits
    $TierLimits = Get-UserTierLimits -Tier $Tier
    
    # Check if endpoint is allowed for this tier
    if ($TierLimits.AllowedEndpoints -notcontains $Endpoint) {
        return @{
            Allowed = $false
            Reason = 'EndpointNotAllowedForTier'
            RequiredTier = 'pro'  # Could be dynamic based on endpoint
            Message = "This endpoint requires a Pro or Enterprise subscription"
        }
    }
    
    # Check API rate limits
    $Now = [DateTimeOffset]::UtcNow
    $ResetDate = [DateTimeOffset]$User.ApiUsageResetDate
    
    # Reset counter if window expired
    if ($Now -gt $ResetDate.AddSeconds($TierLimits.RateLimitWindow)) {
        return @{
            Allowed = $true
            ResetUsage = $true  # Signal to reset counter
            NewResetDate = $Now
        }
    }
    
    # Check if limit exceeded
    $CurrentCount = [int]$User.ApiRequestCount
    if ($CurrentCount -ge $TierLimits.ApiRequestsPerHour) {
        $SecondsUntilReset = [int]($TierLimits.RateLimitWindow - ($Now - $ResetDate).TotalSeconds)
        
        return @{
            Allowed = $false
            Reason = 'TierRateLimitExceeded'
            CurrentUsage = $CurrentCount
            Limit = $TierLimits.ApiRequestsPerHour
            RetryAfter = $SecondsUntilReset
            Message = "API rate limit exceeded. Upgrade to Pro for higher limits."
        }
    }
    
    # Access allowed
    return @{
        Allowed = $true
        IncrementUsage = $true  # Signal to increment counter
    }
}
```

### 3. Modify Request Router

Update `Modules/LinkTomeEntrypoints/LinkTomeEntrypoints.psm1`:

```powershell
# In New-LinkTomeCoreRequest function, after authentication check
if ($Endpoint -match '^admin/') {
    $User = Get-UserFromRequest -Request $Request
    if (-not $User) {
        # ... existing auth failure handling ...
    }
    
    # NEW: Tier-based access check
    $TierCheck = Test-TierAccess -User $User -Endpoint $Endpoint
    
    if (-not $TierCheck.Allowed) {
        # Log tier restriction event
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'TierAccessDenied' -UserId $User.UserId -Endpoint $Endpoint -IpAddress $ClientIP -Reason $TierCheck.Reason
        
        $StatusCode = if ($TierCheck.Reason -eq 'TierRateLimitExceeded') {
            [HttpStatusCode]::TooManyRequests
        } else {
            [HttpStatusCode]::PaymentRequired  # 402
        }
        
        $ResponseHeaders = @{}
        if ($TierCheck.RetryAfter) {
            $ResponseHeaders['Retry-After'] = $TierCheck.RetryAfter.ToString()
            $ResponseHeaders['X-RateLimit-Limit'] = $TierCheck.Limit.ToString()
            $ResponseHeaders['X-RateLimit-Remaining'] = '0'
            $ResponseHeaders['X-RateLimit-Reset'] = $TierCheck.RetryAfter.ToString()
        }
        
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Headers = $ResponseHeaders
            Body = @{ 
                error = $TierCheck.Message
                reason = $TierCheck.Reason
                currentTier = $User.Tier
                requiredTier = $TierCheck.RequiredTier
                upgradeUrl = "https://linktome.com/pricing"  # Your pricing page
            }
        }
    }
    
    # Update API usage counter if needed
    if ($TierCheck.IncrementUsage -or $TierCheck.ResetUsage) {
        $Table = Get-LinkToMeTable -TableName 'Users'
        $UserEntity = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$($User.UserId)'" | Select-Object -First 1
        
        if ($TierCheck.ResetUsage) {
            $UserEntity.ApiRequestCount = 1
            $UserEntity.ApiUsageResetDate = $TierCheck.NewResetDate
        } else {
            $UserEntity.ApiRequestCount = [int]$UserEntity.ApiRequestCount + 1
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserEntity -Force | Out-Null
    }
    
    # Continue with existing permission check...
}
```

---

## API Endpoint Tier Restrictions

### Recommended Endpoint-to-Tier Mapping

| Endpoint | Free | Pro | Enterprise | Notes |
|----------|------|-----|------------|-------|
| **Public Endpoints** |
| `POST /public/signup` | ✅ | ✅ | ✅ | Open to all |
| `POST /public/login` | ✅ | ✅ | ✅ | Open to all |
| `GET /public/getUserProfile` | ✅ | ✅ | ✅ | Open to all |
| `POST /public/trackLinkClick` | ✅ | ✅ | ✅ | Open to all |
| **Profile Management** |
| `GET /admin/getProfile` | ✅ | ✅ | ✅ | Basic access |
| `PUT /admin/updateProfile` | ✅ | ✅ | ✅ | Basic access |
| **Link Management** |
| `GET /admin/getLinks` | ✅ | ✅ | ✅ | All tiers |
| `PUT /admin/updateLinks` | ✅* | ✅ | ✅ | *Free limited to 5 links |
| **Analytics** |
| `GET /admin/getDashboardStats` | ✅* | ✅ | ✅ | *Free limited to basic stats |
| `GET /admin/getAnalytics` | ❌ | ✅ | ✅ | Pro+ only |
| **Appearance** |
| `GET /admin/getAppearance` | ❌ | ✅ | ✅ | Pro+ only |
| `PUT /admin/updateAppearance` | ❌ | ✅ | ✅ | Pro+ only |
| **Team Management** |
| `GET /admin/UserManagerList` | ❌ | ❌ | ✅ | Enterprise only |
| `POST /admin/UserManagerInvite` | ❌ | ❌ | ✅ | Enterprise only |
| `DELETE /admin/UserManagerRemove` | ❌ | ❌ | ✅ | Enterprise only |
| `POST /admin/UserManagerRespond` | ❌ | ❌ | ✅ | Enterprise only |

### Feature-Level Restrictions

Some endpoints need feature-level checks within the handler:

#### Example: Link Count Limit

Modify `Invoke-AdminUpdateLinks.ps1`:

```powershell
# After authentication, before saving links
$User = $Request.AuthenticatedUser
$TierLimits = Get-UserTierLimits -Tier $User.Tier

if ($TierLimits.MaxLinks -ne -1) {
    $LinkCount = ($Body.links | Measure-Object).Count
    if ($LinkCount -gt $TierLimits.MaxLinks) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::PaymentRequired  # 402
            Body = @{
                error = "Link limit exceeded. Free tier allows up to $($TierLimits.MaxLinks) links."
                currentCount = $LinkCount
                maxAllowed = $TierLimits.MaxLinks
                currentTier = $User.Tier
                upgradeUrl = "https://linktome.com/pricing"
            }
        }
    }
}
```

#### Example: Analytics Retention

Modify `Invoke-AdminGetAnalytics.ps1`:

```powershell
# Filter analytics data based on tier retention
$User = $Request.AuthenticatedUser
$TierLimits = Get-UserTierLimits -Tier $User.Tier

if ($TierLimits.AnalyticsRetentionDays -ne -1) {
    $RetentionDate = (Get-Date).AddDays(-$TierLimits.AnalyticsRetentionDays)
    # Filter analytics records to only include data after RetentionDate
}
```

---

## Rate Limiting by Tier

### Tier-Specific Rate Limits

| Tier | Requests/Hour | Burst Limit | Window |
|------|---------------|-------------|--------|
| Free | 100 | 10/minute | 1 hour |
| Pro | 1,000 | 50/minute | 1 hour |
| Enterprise | 10,000 | 200/minute | 1 hour |

### Implementation Notes

1. **Per-User Rate Limiting**: Track usage per `UserId` instead of per IP
2. **Endpoint-Specific Limits**: Public endpoints (like profile views) shouldn't count against user limits
3. **Admin Endpoints**: All admin endpoints count against the tier limit
4. **Bypass for Critical Operations**: Authentication endpoints (login/signup) use separate limits

### Rate Limit Response Headers

Include these headers in all API responses:

```powershell
Headers = @{
    'X-RateLimit-Limit' = $TierLimits.ApiRequestsPerHour
    'X-RateLimit-Remaining' = ($TierLimits.ApiRequestsPerHour - $User.ApiRequestCount)
    'X-RateLimit-Reset' = $User.ApiUsageResetDate.ToUnixTimeSeconds()
    'X-Tier' = $User.Tier
}
```

---

## Backend Integration Requirements

### 1. Subscription Management System

You'll need a backend system to handle:

#### Subscription Lifecycle
- **Creation**: When user upgrades from free to paid tier
- **Activation**: Enable tier features after successful payment
- **Renewal**: Auto-renew subscriptions monthly/yearly
- **Cancellation**: Handle user-initiated cancellations (keep access until period ends)
- **Expiration**: Downgrade to free tier when subscription expires
- **Payment Failures**: Handle failed payments, retry logic, grace periods

#### Payment Integration (Example: Stripe)
```powershell
# Webhook endpoint: POST /api/webhooks/stripe
function Invoke-WebhooksStripe {
    param($Request)
    
    # Verify webhook signature
    $Event = $Request.Body
    
    switch ($Event.type) {
        'customer.subscription.created' {
            # Upgrade user to paid tier
            $CustomerId = $Event.data.object.customer
            $User = Get-UserByStripeCustomerId -CustomerId $CustomerId
            Update-UserTier -UserId $User.UserId -Tier 'pro'
        }
        'customer.subscription.deleted' {
            # Downgrade to free tier
            $CustomerId = $Event.data.object.customer
            $User = Get-UserByStripeCustomerId -CustomerId $CustomerId
            Update-UserTier -UserId $User.UserId -Tier 'free'
        }
        'invoice.payment_failed' {
            # Send notification, update status to past_due
            $CustomerId = $Event.data.object.customer
            $User = Get-UserByStripeCustomerId -CustomerId $CustomerId
            Send-PaymentFailureNotification -User $User
        }
    }
}
```

### 2. Tier Management Functions

Create these helper functions:

```powershell
# Update-UserTier.ps1
function Update-UserTier {
    param(
        [string]$UserId,
        [string]$Tier,
        [string]$SubscriptionId
    )
    
    $Table = Get-LinkToMeTable -TableName 'Users'
    $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$UserId'" | Select-Object -First 1
    
    # Update tier
    $User.Tier = $Tier
    $User.TierStartDate = (Get-Date).ToUniversalTime()
    
    # Update limits based on new tier
    $TierLimits = Get-UserTierLimits -Tier $Tier
    $User.MaxLinks = $TierLimits.MaxLinks
    $User.AnalyticsRetentionDays = $TierLimits.AnalyticsRetentionDays
    $User.ApiRequestLimit = $TierLimits.ApiRequestsPerHour
    
    # Reset API usage counters for new tier
    $User.ApiRequestCount = 0
    $User.ApiUsageResetDate = (Get-Date).ToUniversalTime()
    
    Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
    
    # Log tier change
    Write-SecurityEvent -EventType 'TierChanged' -UserId $UserId -OldTier $User.Tier -NewTier $Tier -SubscriptionId $SubscriptionId
}
```

### 3. Scheduled Tasks

#### Daily Tier Expiration Check
```powershell
# Azure Function Timer Trigger: Run daily at 00:00 UTC
function Check-ExpiredSubscriptions {
    $Table = Get-LinkToMeTable -TableName 'Users'
    $Now = (Get-Date).ToUniversalTime()
    
    # Find users with expired subscriptions
    $ExpiredUsers = Get-LinkToMeAzDataTableEntity @Table -Filter "TierEndDate lt datetime'$($Now.ToString('o'))' and Tier ne 'free'"
    
    foreach ($User in $ExpiredUsers) {
        Update-UserTier -UserId $User.RowKey -Tier 'free'
        Send-SubscriptionExpiredNotification -User $User
    }
}
```

#### Monthly Usage Reports
```powershell
# Generate monthly reports for enterprise customers
function Generate-MonthlyUsageReport {
    param([string]$UserId)
    
    $Table = Get-LinkToMeTable -TableName 'ApiUsageHistory'
    $StartDate = (Get-Date).AddMonths(-1).ToString('yyyy-MM-dd')
    $EndDate = (Get-Date).ToString('yyyy-MM-dd')
    
    $UsageData = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey ge '$UserId-$StartDate' and PartitionKey le '$UserId-$EndDate'"
    
    # Generate report with total requests, top endpoints, error rates, etc.
}
```

### 4. Migration Script

Create a script to add tier fields to existing users:

```powershell
# Tools/Migrate-UsersToTierSystem.ps1
$Table = Get-LinkToMeTable -TableName 'Users'
$Users = Get-LinkToMeAzDataTableEntity @Table

foreach ($User in $Users) {
    # Add tier fields if they don't exist
    if (-not $User.Tier) {
        $User | Add-Member -NotePropertyName 'Tier' -NotePropertyValue 'free'
        $User | Add-Member -NotePropertyName 'TierStartDate' -NotePropertyValue (Get-Date).ToUniversalTime()
        $User | Add-Member -NotePropertyName 'ApiUsageResetDate' -NotePropertyValue (Get-Date).ToUniversalTime()
        $User | Add-Member -NotePropertyName 'ApiRequestCount' -NotePropertyValue 0
        $User | Add-Member -NotePropertyName 'ApiRequestLimit' -NotePropertyValue 100
        $User | Add-Member -NotePropertyName 'MaxLinks' -NotePropertyValue 5
        $User | Add-Member -NotePropertyName 'AnalyticsRetentionDays' -NotePropertyValue 7
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
    }
}
```

---

## Implementation Roadmap

### Phase 1: Database & Core Functions (Week 1)
1. ✅ Add tier fields to Users table schema
2. ✅ Create migration script for existing users
3. ✅ Implement `Get-UserTierLimits` function
4. ✅ Implement `Test-TierAccess` function
5. ✅ Update signup process to set default tier
6. ✅ Test with development data

### Phase 2: Tier Enforcement (Week 2)
1. ✅ Integrate tier checks into request router
2. ✅ Add tier validation to all admin endpoints
3. ✅ Implement feature-level restrictions (link count, analytics retention)
4. ✅ Add rate limit headers to responses
5. ✅ Update error messages with upgrade prompts
6. ✅ Test all endpoints with different tiers

### Phase 3: Subscription Management (Week 3-4)
1. ✅ Create Subscriptions table
2. ✅ Integrate payment processor (Stripe/PayPal)
3. ✅ Implement webhook handlers
4. ✅ Create tier upgrade/downgrade flows
5. ✅ Add subscription management UI endpoints
6. ✅ Test payment flows end-to-end

### Phase 4: Monitoring & Analytics (Week 5)
1. ✅ Create ApiUsageHistory table
2. ✅ Implement usage tracking
3. ✅ Create scheduled tasks (expiration check, reports)
4. ✅ Add monitoring dashboards
5. ✅ Set up alerts for rate limit violations
6. ✅ Test at scale

### Phase 5: Frontend Integration (Week 6)
1. ✅ Update frontend to display tier information
2. ✅ Add upgrade prompts when tier limits hit
3. ✅ Create pricing page
4. ✅ Add subscription management page
5. ✅ Handle 402 Payment Required responses
6. ✅ Final end-to-end testing

---

## Monitoring and Analytics

### Key Metrics to Track

#### Tier Distribution
- Number of users per tier
- Conversion rate (free → pro → enterprise)
- Churn rate by tier
- Average revenue per user (ARPU)

#### API Usage
- Requests per tier (daily/weekly/monthly)
- Most used endpoints per tier
- Rate limit violations by tier
- Average response time by tier

#### Business Metrics
- Monthly recurring revenue (MRR)
- Subscription renewals vs cancellations
- Failed payment rate
- Customer lifetime value (LTV)

### Logging Events

Add these security event types to `Write-SecurityEvent`:

```powershell
# New event types for tier system
Write-SecurityEvent -EventType 'TierAccessDenied'
Write-SecurityEvent -EventType 'TierRateLimitExceeded'
Write-SecurityEvent -EventType 'TierChanged'
Write-SecurityEvent -EventType 'SubscriptionCreated'
Write-SecurityEvent -EventType 'SubscriptionCancelled'
Write-SecurityEvent -EventType 'PaymentFailed'
```

### Azure Monitor Queries

```kusto
// Rate limit violations by tier
SecurityEvents
| where EventType == "TierRateLimitExceeded"
| summarize count() by Tier, bin(Timestamp, 1h)
| render timechart

// Tier access denials (upgrade opportunities)
SecurityEvents
| where EventType == "TierAccessDenied"
| summarize count() by Endpoint, RequiredTier
| order by count_ desc

// API usage by tier
ApiUsageHistory
| summarize RequestCount = count() by Tier, bin(Timestamp, 1d)
| render timechart
```

---

## Security Considerations

### 1. Prevent Tier Bypass
- Always validate tier on the server side (never trust client)
- Check tier before AND during endpoint execution
- Validate subscription status before processing payments

### 2. Secure Subscription Data
- Never expose payment processor customer IDs in API responses
- Store only references to payment processor objects, not full card details
- Verify webhook signatures from payment processors

### 3. Handle Edge Cases
- Grace periods for failed payments (e.g., 3 days)
- Grandfather existing users during tier rollout
- Allow scheduled downgrades (at period end, not immediate)
- Handle partial feature access during transitions

### 4. Rate Limiting
- Implement per-user rate limits (not just per-IP)
- Use exponential backoff for repeated violations
- Consider burst allowances for legitimate spikes
- Log all rate limit violations for monitoring

---

## Testing Strategy

### Unit Tests
```powershell
Describe "Tier Access Tests" {
    It "Should deny free tier access to analytics endpoint" {
        $User = @{ UserId = 'user-1'; Tier = 'free' }
        $Result = Test-TierAccess -User $User -Endpoint 'admin/getAnalytics'
        $Result.Allowed | Should -Be $false
    }
    
    It "Should allow pro tier access to analytics endpoint" {
        $User = @{ UserId = 'user-1'; Tier = 'pro' }
        $Result = Test-TierAccess -User $User -Endpoint 'admin/getAnalytics'
        $Result.Allowed | Should -Be $true
    }
    
    It "Should enforce link count limit for free tier" {
        $TierLimits = Get-UserTierLimits -Tier 'free'
        $TierLimits.MaxLinks | Should -Be 5
    }
}
```

### Integration Tests
- Test tier upgrade flow end-to-end
- Test tier downgrade when subscription expires
- Test rate limiting at tier boundaries
- Test webhook processing

### Load Tests
- Simulate rate limits being hit
- Test with high API usage across all tiers
- Verify performance of tier checks

---

## Frontend Changes Needed

### 1. Display Tier Information
```javascript
// Show current tier in user profile
const userTier = user.tier || 'free';
const tierBadge = <Badge color={tierColors[userTier]}>{userTier.toUpperCase()}</Badge>;
```

### 2. Handle Tier Restrictions
```javascript
// Handle 402 Payment Required responses
try {
  const response = await fetch('/api/admin/getAnalytics', {
    credentials: 'include'
  });
  
  if (response.status === 402) {
    const data = await response.json();
    // Show upgrade prompt
    showUpgradeModal({
      message: data.error,
      currentTier: data.currentTier,
      requiredTier: data.requiredTier,
      upgradeUrl: data.upgradeUrl
    });
    return;
  }
  
  // Process normal response
} catch (error) {
  // Handle error
}
```

### 3. Pricing Page
Create a pricing comparison page showing:
- Feature matrix (Free vs Pro vs Enterprise)
- Monthly/annual pricing toggle
- Clear upgrade buttons
- FAQ section

### 4. Usage Dashboard
Show users their current usage:
- API requests used / limit
- Links created / limit
- Current tier and benefits
- Upgrade CTA if approaching limits

---

## Cost Considerations

### Azure Table Storage
- Minimal cost impact (~$0.045 per 10k transactions)
- New tables: Subscriptions, ApiUsageHistory
- Increased writes for usage tracking

### Azure Functions
- Additional execution time for tier checks (~10-20ms per request)
- New scheduled functions (daily expiration check)
- Webhook endpoint for payment processing

### Payment Processing
- Stripe: 2.9% + $0.30 per transaction
- Refunds, disputes, currency conversion fees
- Consider passing fees to customers

---

## Support & Maintenance

### Customer Support Scenarios
1. **User wants to upgrade**: Direct to pricing page, process payment, upgrade tier
2. **User wants to cancel**: Process cancellation, keep access until period ends
3. **Payment failed**: Send notification, offer retry, grace period
4. **Tier limits hit**: Explain limits, offer upgrade, show usage stats
5. **Billing dispute**: Access subscription history, provide receipts

### Maintenance Tasks
- Monthly: Review tier distribution and conversion rates
- Weekly: Check for failed payments and expired subscriptions
- Daily: Monitor rate limit violations and API usage spikes
- Quarterly: Analyze pricing and adjust tier limits if needed

---

## Conclusion

Implementing tier-based API access restrictions requires:

1. **Database changes**: Add tier and usage tracking fields
2. **Middleware**: Validate tier access before endpoint execution
3. **Payment integration**: Handle subscriptions and billing
4. **Monitoring**: Track usage and business metrics
5. **Frontend updates**: Display tier info and handle restrictions

This system provides a solid foundation for monetizing your API while maintaining a good user experience. Start with Phase 1 (database and core functions) and progressively roll out additional features.

For questions or clarifications about any section, please refer to the existing codebase or create issues in the repository.
