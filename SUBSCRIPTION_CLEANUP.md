# Subscription Downgrade Feature Cleanup

## Overview

When a user's subscription ends, expires, or is cancelled, the system automatically cleans up features that are no longer available in the user's new tier. This ensures that users who downgrade to a lower tier (typically the free tier) have their account properly adjusted to reflect the limitations of their new subscription level.

## Trigger Events

Feature cleanup is automatically triggered by the following events:

1. **Subscription Deletion** (`customer.subscription.deleted` webhook)
   - User's subscription is cancelled and billing period has ended
   - Downgrade to free tier
   - Cleanup is triggered immediately

2. **Payment Failure** (`invoice.payment_failed` webhook)
   - Payment method fails during renewal
   - Subscription status set to 'suspended'
   - Cleanup is triggered to restrict access

3. **Timer-based Cleanup** (Daily scheduled task)
   - Processes subscriptions that have expired but webhook wasn't received
   - Handles cancelled subscriptions that have reached their end date
   - Catches edge cases and ensures consistency

## Features Cleaned Up

### 1. Excess Pages
- **Free tier limit:** 1 page
- **Pro tier limit:** 3 pages
- **Premium tier limit:** 10 pages
- **Enterprise tier limit:** Unlimited

**Cleanup behavior:**
- Keeps pages up to the new tier limit
- Default page is always preserved
- Additional pages are deleted (oldest first)
- Page appearance settings are also removed

### 2. Custom Themes
- **Free tier:** Default theme only
- **Pro+:** Custom themes allowed

**Premium themes:**
- agate
- astrid
- aura
- bloom
- breeze

**Cleanup behavior:**
- Custom theme flag is set to false
- Premium themes are reset to 'default'
- Theme customizations are removed

### 3. Video Backgrounds
- **Free tier:** Not allowed
- **Pro tier:** Not allowed
- **Premium+:** Allowed

**Cleanup behavior:**
- Video background URLs are cleared
- Wallpaper type is reset to 'fill'
- User retains other wallpaper settings (colors, gradients)

### 4. API Keys
- **Free tier:** 0 keys
- **Pro tier:** 3 keys
- **Premium tier:** 10 keys
- **Enterprise tier:** Unlimited

**Cleanup behavior:**
- Excess API keys are disabled (not deleted)
- Keeps oldest keys active
- Disabled reason is set to 'Subscription downgraded'
- Keys can be re-enabled if subscription is upgraded again

### 5. Links
- **Free tier:** 10 links
- **Pro tier:** 50 links
- **Premium tier:** 100 links
- **Enterprise tier:** Unlimited

**Cleanup behavior:**
- Excess links are marked as inactive (not deleted)
- Keeps links in order preference (by Order field)
- Inactive links can be reactivated if subscription is upgraded
- User can manually delete inactive links to make room for new ones

## Implementation Details

### Core Function: `Invoke-FeatureCleanup`

**Location:** `Modules/LinkTomeCore/Private/Subscription/Invoke-FeatureCleanup.ps1`

**Parameters:**
- `UserId` - The user ID to clean up features for
- `NewTier` - The new tier to enforce limits for (typically 'free')

**Returns:**
```powershell
@{
    success = $true/$false
    tier = 'free'
    cleanupActions = @(
        "Deleted excess page: MyPage (id: page-123)",
        "Reset appearance to default theme for page: page-456",
        ...
    )
}
```

**Security:**
- All cleanup operations are logged as security events
- Event type: 'FeatureCleanup'
- Includes user ID and count of cleanup actions

### Webhook Handlers

#### Handle-SubscriptionDeleted
**Location:** `Modules/LinkTomeCore/Private/Stripe/Handle-SubscriptionDeleted.ps1`

When a subscription is deleted:
1. Downgrade user to 'free' tier
2. Set status to 'expired'
3. Clear Stripe IDs
4. Set cancellation timestamp
5. Call `Invoke-FeatureCleanup` to clean up features

#### Handle-InvoicePaymentFailed
**Location:** `Modules/LinkTomeCore/Private/Stripe/Handle-InvoicePaymentFailed.ps1`

When a payment fails:
1. Set subscription status to 'suspended'
2. Log security event
3. Call `Invoke-FeatureCleanup` to restrict access
4. User can restore access by updating payment method

### Timer Function: Start-SubscriptionCleanup

**Location:** `Modules/LinkTomeCore/Public/Timers/Start-SubscriptionCleanup.ps1`

**Schedule:** Daily (configured in `LinkTomeTimers.json`)

**Process:**
1. Query all users with paid subscriptions
2. Skip sub-accounts (they inherit from parent)
3. Check each subscription's status:
   - Cancelled and past end date → downgrade
   - Expired status → downgrade
   - Suspended (payment failed) → downgrade
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

## Edge Cases Handled

### 1. Sub-Accounts
- Sub-accounts inherit subscription from parent
- Feature cleanup is NOT triggered for sub-accounts
- Only parent account downgrades affect sub-accounts

### 2. Cancelled with Grace Period
- If subscription is cancelled with `NextBillingDate` in the future
- User retains access until billing date passes
- Cleanup is deferred until grace period ends

### 3. Default Page Protection
- Default page is never deleted during cleanup
- If user has more pages than allowed, excess non-default pages are removed
- If only default page exists, it is always preserved

### 4. API Keys and Links
- These are disabled/deactivated rather than deleted
- Allows for potential data recovery if subscription is restored
- User maintains historical data

### 5. Missing Tables
- Gracefully handles missing tables (e.g., ApiKeys)
- Logs warning but continues cleanup
- Does not fail entire cleanup if one feature fails

## Error Handling

- All cleanup operations are wrapped in try-catch blocks
- Individual feature cleanup failures do not stop other cleanups
- Errors are logged with warnings
- Overall cleanup success is tracked separately from individual actions
- Security events are logged even if cleanup partially fails

## Monitoring and Logging

### Security Events
All cleanup operations generate security events in the `SecurityEvents` table:

- **FeatureCleanup:** When cleanup is performed for a user
  - Includes user ID
  - Includes tier being downgraded to
  - Includes count of cleanup actions

- **SubscriptionDeleted:** When webhook processes deletion
- **SubscriptionPaymentFailed:** When payment fails
- **SubscriptionAutoDowngraded:** When timer function downgrades

### Information Logs
Detailed information is logged for operations:
- "Starting feature cleanup for user X, new tier: free"
- "Deleted excess page Y for user X"
- "Feature cleanup completed: N actions taken"

### Warning Logs
Warnings are logged for issues:
- "Failed to delete page X: error message"
- "Feature cleanup failed but subscription was still cancelled"

## Testing Recommendations

### Manual Testing Scenarios

1. **Test subscription cancellation:**
   - Create a Pro user with multiple pages, custom themes, and video backgrounds
   - Cancel subscription via Stripe webhook
   - Verify excess features are cleaned up
   - Verify default page remains

2. **Test payment failure:**
   - Create a Premium user with API keys
   - Trigger payment failure webhook
   - Verify API keys are disabled
   - Verify subscription status is 'suspended'

3. **Test timer cleanup:**
   - Create users with expired/cancelled subscriptions
   - Run `Start-SubscriptionCleanup` manually
   - Verify users are downgraded
   - Verify features are cleaned up

4. **Test sub-accounts:**
   - Create sub-account under Premium parent
   - Cancel parent subscription
   - Verify sub-account loses access
   - Verify sub-account features are not directly cleaned up

### Integration Testing

Test with actual Stripe webhooks in test mode:
```bash
# Use Stripe CLI to trigger test webhooks
stripe trigger customer.subscription.deleted
stripe trigger invoice.payment_failed
```

## Future Enhancements

Potential improvements for future iterations:

1. **Grace Period for Payment Failures**
   - Allow users a grace period to update payment method
   - Only cleanup features after multiple failed attempts

2. **Email Notifications**
   - Send email when subscription ends
   - Notify user about cleaned up features
   - Offer upgrade options

3. **Backup Before Cleanup**
   - Archive deleted pages before removal
   - Allow recovery within 30 days

4. **Granular Cleanup Control**
   - Admin panel to manually trigger cleanup
   - Option to preserve specific features temporarily

5. **Analytics**
   - Track cleanup statistics
   - Monitor downgrade reasons
   - Measure re-subscription rates

## Related Documentation

- [TIER_SYSTEM.md](./TIER_SYSTEM.md) - Complete tier system documentation
- [STRIPE_SETUP.md](./STRIPE_SETUP.md) - Stripe integration guide
- [Get-TierFeatures.ps1](./Modules/LinkTomeCore/Private/Tier/Get-TierFeatures.ps1) - Tier feature definitions
