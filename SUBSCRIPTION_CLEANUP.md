# Subscription Downgrade Feature Handling

## Overview

When a user's subscription ends, expires, or is cancelled, the system automatically **marks** features that exceed the new tier's limits with flags. **All data is preserved** and can be restored if the user upgrades again. Public APIs check these flags to hide or restrict access to features that exceed the user's current tier.

## Design Philosophy

**Data Preservation First**: Instead of deleting user data when a subscription downgrades, we:
1. Mark features that exceed tier limits with flags (e.g., `ExceedsTierLimit`)
2. Public APIs check these flags and hide/restrict access accordingly
3. Admin APIs show the flags so users know which features are affected
4. Data remains intact and can be immediately restored on upgrade

## Trigger Events

Feature flagging is automatically triggered by the following events:

1. **Subscription Deletion** (`customer.subscription.deleted` webhook)
   - User's subscription is cancelled and billing period has ended
   - Downgrade to free tier
   - Features marked immediately

2. **Payment Failure** (`invoice.payment_failed` webhook)
   - Payment method fails during renewal
   - Subscription status set to 'suspended'
   - Features marked to restrict access

3. **Timer-based Cleanup** (Daily scheduled task)
   - Processes subscriptions that have expired but webhook wasn't received
   - Handles cancelled subscriptions that have reached their end date
   - Catches edge cases and ensures consistency

## Features Handled

### 1. Excess Pages
- **Free tier limit:** 1 page
- **Pro tier limit:** 3 pages
- **Premium tier limit:** 10 pages
- **Enterprise tier limit:** Unlimited

**Handling behavior:**
- Pages beyond tier limit are marked with `ExceedsTierLimit = true`
- Pages within limit have `ExceedsTierLimit = false` or no flag
- Public API returns 403 Forbidden if accessing a page with this flag
- Admin API shows the flag so user knows which pages are affected
- **Data preserved:** All page content, settings, and links remain intact

### 2. Custom Themes
- **Free tier:** Default theme only
- **Pro+:** Custom themes allowed

**Premium themes:**
- agate
- astrid
- aura
- bloom
- breeze

**Handling behavior:**
- Appearance records with custom themes are marked with `ExceedsTierLimit = true`
- Public API serves default theme when flag is set, but preserves theme choice
- Admin API shows the flag so user can see theme is restricted
- **Data preserved:** Theme settings remain in database for restoration

### 3. Video Backgrounds
- **Free tier:** Not allowed
- **Pro tier:** Not allowed
- **Premium+:** Allowed

**Handling behavior:**
- Appearance records with video backgrounds marked with `VideoExceedsTierLimit = true`
- Public API doesn't serve video URL when flag is set
- Public API changes wallpaper type from 'video' to 'fill' for display
- **Data preserved:** Video URL remains in database for restoration

### 4. Short Links
- **Free tier:** 0 short links
- **Pro tier:** 5 short links
- **Premium tier:** 20 short links
- **Enterprise tier:** Unlimited

**Handling behavior:**
- Short links beyond tier limit are marked with `ExceedsTierLimit = true`
- Public redirect API returns 403 Forbidden if accessing marked short link
- Admin API shows which short links are marked
- **Data preserved:** All short links, click counts, and analytics remain intact

### 5. API Keys
- **Free tier:** 0 keys
- **Pro tier:** 3 keys
- **Premium tier:** 10 keys
- **Enterprise tier:** Unlimited

**Handling behavior:**
- Excess API keys are disabled (not deleted)
- `Active = false` and `DisabledReason = 'Subscription downgraded'`
- Keys can be re-enabled if subscription is upgraded
- **Data preserved:** All key data remains for restoration

### 6. Links
- **Free tier:** 10 links
- **Pro tier:** 50 links
- **Premium tier:** 100 links
- **Enterprise tier:** Unlimited

**Handling behavior:**
- Excess links are marked as inactive (not deleted)
- `Active = false`
- User can manually reactivate if they delete other links to make room
- **Data preserved:** All link data remains for restoration

## Implementation Details

### Core Function: `Invoke-FeatureCleanup`

**Location:** `Modules/LinkTomeCore/Private/Subscription/Invoke-FeatureCleanup.ps1`

**Parameters:**
- `UserId` - The user ID to process features for
- `NewTier` - The new tier to enforce limits for (typically 'free')

**Returns:**
```powershell
@{
    success = $true/$false
    tier = 'free'
    cleanupActions = @(
        "Marked excess page as exceeding limit: MyPage (id: page-123)",
        "Marked custom theme as exceeding limit for page: page-456",
        ...
    )
}
```

**Flags Added to Entities:**

1. **Pages table:**
   - `ExceedsTierLimit` (boolean) - Set to true if page exceeds tier's maxPages limit

2. **Appearance table:**
   - `ExceedsTierLimit` (boolean) - Set to true if custom theme exceeds tier limit
   - `VideoExceedsTierLimit` (boolean) - Set to true if video background exceeds tier limit

3. **ShortLinks table:**
   - `ExceedsTierLimit` (boolean) - Set to true if short link exceeds tier limit

4. **ApiKeys table:**
   - `Active` (boolean) - Set to false for excess keys
   - `DisabledReason` (string) - Set to 'Subscription downgraded'

5. **Links table:**
   - `Active` (boolean) - Set to false for excess links

**Security:**
- All operations are logged as security events
- Event type: 'FeatureCleanup'
- Includes user ID and count of actions taken

### Webhook Handlers

#### Handle-SubscriptionDeleted
**Location:** `Modules/LinkTomeCore/Private/Stripe/Handle-SubscriptionDeleted.ps1`

When a subscription is deleted:
1. Downgrade user to 'free' tier
2. Set status to 'expired'
3. Clear Stripe IDs
4. Set cancellation timestamp
5. Call `Invoke-FeatureCleanup` to mark excess features

#### Handle-InvoicePaymentFailed
**Location:** `Modules/LinkTomeCore/Private/Stripe/Handle-InvoicePaymentFailed.ps1`

When a payment fails:
1. Set subscription status to 'suspended'
2. Log security event
3. Call `Invoke-FeatureCleanup` to mark features exceeding new limits
4. User can restore access by updating payment method

### Public API Checks

Public APIs check the tier limit flags to restrict access:

#### Invoke-PublicL (Short Link Redirect)
**Location:** `Modules/PublicApi/Public/Invoke-PublicL.ps1`

- Checks `ExceedsTierLimit` flag on short link
- Returns 403 Forbidden if flag is true
- Message: "This short link is not available on the user's current plan"

#### Invoke-PublicGetUserProfile (User Profile)
**Location:** `Modules/PublicApi/Public/Invoke-PublicGetUserProfile.ps1`

- Checks `ExceedsTierLimit` flag on requested page
- Returns 403 Forbidden if accessing page that exceeds limit
- Checks `ExceedsTierLimit` on appearance for custom themes
- Serves 'default' theme if custom theme exceeds limit
- Checks `VideoExceedsTierLimit` on appearance
- Omits video URL and resets type to 'fill' if video exceeds limit

### Admin API Awareness

Admin APIs include the flags so users can see which features are affected:

#### Invoke-AdminGetPages
**Location:** `Modules/PrivateApi/Public/Invoke-AdminGetPages.ps1`

- Includes `exceedsTierLimit` field in page objects
- Users can see which pages are beyond their tier

#### Invoke-AdminGetShortLinks
**Location:** `Modules/PrivateApi/Public/Invoke-AdminGetShortLinks.ps1`

- Includes `exceedsTierLimit` field in short link objects
- Users can see which short links are beyond their tier

#### Invoke-AdminGetAppearance
**Location:** `Modules/PrivateApi/Public/Invoke-AdminGetAppearance.ps1`

- Includes `exceedsTierLimit` field for custom themes
- Includes `videoExceedsTierLimit` field for video backgrounds
- Users can see which appearance features are restricted

### Timer Function: Start-SubscriptionCleanup

**Location:** `Modules/LinkTomeCore/Public/Timers/Start-SubscriptionCleanup.ps1`

**Schedule:** Daily (configured in `LinkTomeTimers.json`)

**Process:**
1. Query all users with paid subscriptions
2. Skip sub-accounts (they inherit from parent)
3. Check each subscription's status:
   - Cancelled and past end date → downgrade and mark features
   - Expired status → downgrade and mark features
   - Suspended (payment failed) → downgrade and mark features
4. Update user record to free tier
5. Call `Invoke-FeatureCleanup` for each downgraded user
6. Log security events

**Returns:**
```powershell
@{
    Status = "Success"
    Message = "Subscription cleanup completed"
    ProcessedCount = 5
    ErrorCount = 0
}
```

## Restoration on Upgrade

When a user upgrades their subscription:

1. **Automatic Restoration:**
   - `Invoke-FeatureCleanup` is called with the new tier
   - Flags are removed from features now within limits
   - Example: User upgrades from Free to Pro
     - First 3 pages have `ExceedsTierLimit` set to false
     - Remaining pages keep the flag set

2. **Manual Restoration:**
   - Links and API keys remain in database with `Active = false`
   - User can manually reactivate them through admin panel
   - Data is immediately available (no re-creation needed)

3. **Seamless Experience:**
   - Custom themes automatically apply when tier allows
   - Video backgrounds automatically show when tier allows
   - Short links automatically work when tier allows

## Edge Cases Handled

### 1. Sub-Accounts
- Sub-accounts inherit subscription from parent
- Feature cleanup is NOT triggered for sub-accounts
- Only parent account downgrades affect sub-accounts

### 2. Cancelled with Grace Period
- If subscription is cancelled with `NextBillingDate` in the future
- User retains access until billing date passes
- Features are marked only after grace period ends

### 3. Data Preservation
- **No data deletion:** Pages, themes, videos, short links all preserved
- Flags are used to hide/restrict access, not delete data
- Instant restoration on upgrade (no re-creation needed)

### 4. API Keys and Links
- These are deactivated rather than deleted
- Allows for potential data recovery if subscription is restored
- User maintains historical data and analytics

### 5. Missing Tables
- Gracefully handles missing tables (e.g., ApiKeys, ShortLinks)
- Logs warning but continues processing other features
- Does not fail entire operation if one feature fails

### 6. Flag Consistency
- Flags are removed when tier allows feature
- Example: Pro user with 5 pages downgrades to Free (1 page)
  - Pages 2-5 get `ExceedsTierLimit = true`
  - User upgrades back to Pro
  - Pages 2-4 get `ExceedsTierLimit = false` (within Pro's 3-page limit)
  - Page 5 keeps `ExceedsTierLimit = true`

## Error Handling

- All operations are wrapped in try-catch blocks
- Individual feature marking failures do not stop other features
- Errors are logged with warnings
- Overall operation success is tracked separately from individual actions
- Security events are logged even if marking partially fails

## Monitoring and Logging

### Security Events
All operations generate security events in the `SecurityEvents` table:

- **FeatureCleanup:** When features are marked for a user
  - Includes user ID
  - Includes tier being downgraded to
  - Includes count of actions taken

- **SubscriptionDeleted:** When webhook processes deletion
- **SubscriptionPaymentFailed:** When payment fails
- **SubscriptionAutoDowngraded:** When timer function downgrades

### Information Logs
Detailed information is logged for operations:
- "Starting feature cleanup for user X, new tier: free"
- "Marked excess page Y as exceeding tier limit for user X"
- "Feature cleanup completed: N actions taken"

### Warning Logs
Warnings are logged for issues:
- "Failed to mark page X: error message"
- "Feature cleanup failed but subscription was still cancelled"

## Testing Recommendations

### Manual Testing Scenarios

1. **Test subscription cancellation:**
   - Create a Pro user with 5 pages, custom themes, and video backgrounds
   - Cancel subscription via Stripe webhook
   - Verify excess pages are marked with `ExceedsTierLimit = true`
   - Verify custom theme marked with `ExceedsTierLimit = true`
   - Verify video marked with `VideoExceedsTierLimit = true`
   - Verify public API returns 403 for marked pages
   - Verify public API serves default theme
   - Verify public API omits video URL

2. **Test payment failure:**
   - Create a Premium user with 10 short links
   - Trigger payment failure webhook
   - Verify short links beyond limit marked with `ExceedsTierLimit = true`
   - Verify subscription status is 'suspended'
   - Verify public redirect API returns 403 for marked short links

3. **Test restoration on upgrade:**
   - Downgrade user from Pro to Free (3 pages → 1 page)
   - Verify pages 2-3 marked with `ExceedsTierLimit = true`
   - Upgrade user back to Pro
   - Verify pages 2-3 have `ExceedsTierLimit = false`
   - Verify pages are immediately accessible via public API

4. **Test admin visibility:**
   - Downgrade user with excess features
   - Call admin APIs (getPages, getShortLinks, getAppearance)
   - Verify `exceedsTierLimit` flags are returned
   - User should see which features are restricted

5. **Test timer cleanup:**
   - Create users with expired/cancelled subscriptions
   - Run `Start-SubscriptionCleanup` manually
   - Verify users are downgraded
   - Verify features are marked appropriately

### Integration Testing

Test with actual Stripe webhooks in test mode:
```bash
# Use Stripe CLI to trigger test webhooks
stripe trigger customer.subscription.deleted
stripe trigger invoice.payment_failed
```

## Future Enhancements

Potential improvements for future iterations:

1. **Bulk Flag Management**
   - Admin endpoint to manually flag/unflag features
   - Bulk operations for testing or customer support

2. **Grace Period Notifications**
   - Email users before marking features
   - Allow users to download data before restriction

3. **Feature Usage Analytics**
   - Track which features users lose most often
   - Help prioritize retention strategies

4. **Restoration UI**
   - Frontend interface showing flagged features
   - One-click restoration on upgrade
   - Preview of what will be restored

5. **Soft Delete Archive**
   - Secondary table for truly deleted data (if needed in future)
   - 30-day recovery window
   - Automated purge after retention period

6. **Progressive Restrictions**
   - Warn users before marking features
   - 7-day grace period before restriction
   - Multiple reminder emails

## Related Documentation

- [TIER_SYSTEM.md](./TIER_SYSTEM.md) - Complete tier system documentation
- [STRIPE_SETUP.md](./STRIPE_SETUP.md) - Stripe integration guide
- [Get-TierFeatures.ps1](./Modules/LinkTomeCore/Private/Tier/Get-TierFeatures.ps1) - Tier feature definitions
