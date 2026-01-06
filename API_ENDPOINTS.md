# Settings and Subscription API Endpoints

This document provides a comprehensive guide for frontend engineers on implementing the Settings and Subscription pages. It explains which endpoints already exist, which are newly implemented, and how to use them.

## Table of Contents
1. [Settings Page Endpoints](#settings-page-endpoints)
2. [Subscription Page Endpoints](#subscription-page-endpoints)
3. [Authentication](#authentication)
4. [Questions & Clarifications](#questions--clarifications)

---

## Settings Page Endpoints

### 1. Get User Settings ✅ EXISTING ENDPOINT

**Use existing endpoint:** `GET /api/admin/getProfile`

**Purpose:** Retrieve current user security and account settings

**Authentication:** Required - JWT Bearer token

**Request:**
```http
GET /api/admin/getProfile
Authorization: Bearer <jwt-token>
```

**Response Format:**
```json
{
  "UserId": "user-abc123",
  "username": "johndoe",
  "email": "user@example.com",
  "displayName": "John Doe",
  "bio": "Software Developer",
  "avatar": "https://example.com/avatar.jpg"
}
```

**Note for Frontend:** 
- This endpoint provides basic profile information for display/editing
- For 2FA configuration status, use the auth context returned by `/login`, `/signup`, or `/refreshToken` endpoints
- For phone number, use the `/admin/updatePhone` endpoint to set/update it (field will be added to this response in future if needed)

---

### 2. Update Password 🆕 NEW ENDPOINT

**Endpoint:** `PUT /api/admin/updatePassword`

**Purpose:** Allow users to change their password

**Authentication:** Required - JWT Bearer token

**Request:**
```http
PUT /api/admin/updatePassword
Authorization: Bearer <jwt-token>
Content-Type: application/json

{
  "currentPassword": "oldPassword123",
  "newPassword": "newSecurePassword456"
}
```

**Validation:**
- Current password must match stored hash
- New password must be at least 8 characters (enforced by existing `Test-PasswordStrength` function)
- New password will be hashed using PBKDF2-SHA256 with 100,000 iterations

**Success Response (200):**
```json
{
  "message": "Password updated successfully"
}
```

**Error Responses:**
- `400` - Current password is incorrect
- `400` - New password does not meet requirements
- `401` - Unauthorized (no valid JWT)
- `500` - Internal server error

**Storage:**
- Updates `PasswordHash` and `PasswordSalt` fields in Users table
- PartitionKey: email (lowercase)
- RowKey: UserId

---

### 3. Update Email 🆕 NEW ENDPOINT

**Endpoint:** `PUT /api/admin/updateEmail`

**Purpose:** Allow users to change their email address

**Authentication:** Required - JWT Bearer token

**Request:**
```http
PUT /api/admin/updateEmail
Authorization: Bearer <jwt-token>
Content-Type: application/json

{
  "newEmail": "newemail@example.com",
  "password": "currentPassword123"
}
```

**Process:**
1. Verify password is correct
2. Check if new email is already in use (check PartitionKey in Users table)
3. Update email immediately (no verification flow in initial implementation)

**Success Response (200):**
```json
{
  "message": "Email updated successfully",
  "email": "newemail@example.com"
}
```

**Error Responses:**
- `400` - Password is incorrect
- `400` - Invalid email format
- `409` - Email address already in use
- `401` - Unauthorized
- `500` - Internal server error

**Important Notes:**
- The requirements document mentions email verification with tokens, but this adds significant complexity
- Initial implementation updates email immediately after password confirmation
- Future enhancement could add verification flow with `PendingEmailChanges` table
- Changing email means changing PartitionKey in Azure Table Storage, which requires:
  1. Creating a new entity with new PartitionKey
  2. Copying all data
  3. Deleting the old entity
  4. Updating refresh tokens table

---

### 4. Update Phone Number 🆕 NEW ENDPOINT

**Endpoint:** `PUT /api/admin/updatePhone`

**Purpose:** Add or update user's mobile phone number

**Authentication:** Required - JWT Bearer token

**Request:**
```http
PUT /api/admin/updatePhone
Authorization: Bearer <jwt-token>
Content-Type: application/json

{
  "phoneNumber": "+1 (555) 123-4567"
}
```

**Success Response (200):**
```json
{
  "message": "Phone number updated successfully",
  "phoneNumber": "+1 (555) 123-4567"
}
```

**Error Responses:**
- `400` - Invalid phone number format
- `401` - Unauthorized
- `500` - Internal server error

**Storage:**
- Adds `PhoneNumber` field to Users table
- This field doesn't currently exist and will be added

**Note:** 
- UI-only feature with no SMS functionality initially
- Basic format validation only
- Can be empty string to clear phone number

---

### 5. Reset/Disable Two-Factor Authentication ✅ EXISTING ENDPOINT

**Use existing endpoint:** `POST /api/admin/2fatokensetup?action=disable`

**Purpose:** Disable all 2FA methods for the user

**Authentication:** Required - JWT Bearer token

**Request:**
```http
POST /api/admin/2fatokensetup?action=disable
Authorization: Bearer <jwt-token>
Content-Type: application/json

{}
```

**Process:**
1. Disable all 2FA flags in Users table
2. Clear TOTP secret from Users table
3. Clear backup codes from Users table
4. Log security event

**Success Response (200):**
```json
{
  "message": "Two-factor authentication disabled successfully",
  "emailEnabled": false,
  "totpEnabled": false
}
```

**Error Responses:**
- `401` - Unauthorized
- `404` - User not found
- `500` - Internal server error

**Storage Updates:**
- Users table fields updated:
  - `TwoFactorEmailEnabled` = false
  - `TwoFactorTotpEnabled` = false
  - `TotpSecret` = "" (cleared)
  - `BackupCodes` = "[]" (cleared)
- Security event logged with type '2FADisabled'

**Note:** 
- This completely removes all 2FA configuration including secrets and backup codes
- User will need to set up 2FA from scratch if they want to re-enable it
- User should be notified via email when 2FA is disabled (future enhancement)

---

## Subscription Page Endpoints

### 6. Get Subscription Information 🆕 NEW ENDPOINT

**Endpoint:** `GET /api/admin/getSubscription`

**Purpose:** Retrieve user's current subscription details

**Authentication:** Required - JWT Bearer token

**Request:**
```http
GET /api/admin/getSubscription
Authorization: Bearer <jwt-token>
```

**Response Format (200):**
```json
{
  "currentTier": "free",
  "status": "active",
  "subscriptionStartedAt": "2024-01-15T00:00:00Z"
}
```

**Response Format for Pro/Premium/Enterprise:**
```json
{
  "currentTier": "premium",
  "billingCycle": "monthly",
  "nextBillingDate": "2024-02-15T00:00:00Z",
  "amount": 1.99,
  "currency": "USD",
  "status": "active",
  "subscriptionStartedAt": "2024-01-15T00:00:00Z",
  "cancelledAt": null
}
```

**Error Responses:**
- `401` - Unauthorized
- `500` - Internal server error

**Storage:**
- Primary data from Users table:
  - `SubscriptionTier` (string) - "free", "pro", "premium", "enterprise"
  - `SubscriptionStatus` (string) - "active", "cancelled", "expired"

**Current Implementation Notes:**
- Basic tier information is already in the Users table
- Advanced billing information (billing cycle, payment method, next billing date) is NOT currently stored
- Payment processing via Stripe is NOT currently implemented
- This endpoint returns available subscription data
- Full billing integration would require additional tables and Stripe integration

---

### 7. Upgrade Subscription ✅ IMPLEMENTED

**Endpoint:** `POST /api/admin/upgradeSubscription`

**Purpose:** Upgrade or change user's subscription plan

**Authentication:** Required - JWT Bearer token

**Request:**
```http
POST /api/admin/upgradeSubscription
Authorization: Bearer <jwt-token>
Content-Type: application/json

{
  "tier": "premium",
  "billingCycle": "monthly"
}
```

**Request Fields:**
- `tier` (required) - Subscription tier: "free", "pro", "premium", or "enterprise"
- `billingCycle` (required for paid tiers) - Billing cycle: "monthly" or "annual"

**Success Response (200):**
```json
{
  "message": "Subscription updated successfully",
  "tier": "premium",
  "billingCycle": "monthly",
  "status": "active"
}
```

**Error Responses:**
- `400` - Invalid tier specified
- `400` - Billing cycle required for paid tiers
- `400` - Invalid billing cycle
- `401` - Unauthorized
- `404` - User not found
- `500` - Internal server error

**Implementation Status:**
- ✅ Updates Users table with subscription tier and billing cycle
- ✅ Sets SubscriptionStartedAt when changing tiers
- ✅ Calculates and stores NextBillingDate based on billing cycle
- ✅ Clears billing info when downgrading to free tier
- ⚠️ Does NOT process actual payments (payment integration pending)
- ⚠️ Does NOT integrate with Stripe

**Storage:**
Updates the following fields in the Users table:
- `SubscriptionTier` - The selected tier
- `SubscriptionStatus` - Set to "active"
- `SubscriptionStartedAt` - Timestamp when subscription started/changed (ISO 8601 format)
- `BillingCycle` - "monthly" or "annual" (null for free tier)
- `NextBillingDate` - Calculated renewal date (null for free tier)

**Next Billing Date Calculation:**
- Monthly: Current date + 1 month
- Annual: Current date + 1 year

**Note:** Payment processing will be added in a future update. For now, this endpoint immediately updates the subscription without payment verification.

---

### 8. Cancel Subscription ✅ IMPLEMENTED

**Endpoint:** `POST /api/admin/cancelSubscription`

**Purpose:** Cancel the user's subscription

**Authentication:** Required - JWT Bearer token

**Request:**
```http
POST /api/admin/cancelSubscription
Authorization: Bearer <jwt-token>
Content-Type: application/json

{}
```

**Success Response (200):**
```json
{
  "message": "Subscription cancelled successfully",
  "tier": "premium",
  "status": "cancelled",
  "cancelledAt": "2024-01-15T10:30:00Z",
  "accessUntil": "2024-02-15T00:00:00Z",
  "note": "You can continue using premium features until 2024-02-15T00:00:00Z"
}
```

**Error Responses:**
- `400` - No active subscription to cancel
- `400` - Subscription is already cancelled
- `401` - Unauthorized
- `404` - User not found
- `500` - Internal server error

**Implementation Status:**
- ✅ Updates Users table with cancellation status
- ✅ Sets `SubscriptionStatus` to "cancelled"
- ✅ Records `CancelledAt` timestamp
- ✅ Preserves current tier and billing info until `NextBillingDate`
- ✅ Allows continued access until end of paid period
- ⚠️ Does NOT integrate with Stripe for refunds
- ⚠️ Does NOT automatically downgrade to free tier (requires separate scheduled job)

**Storage Updates:**
Updates the following fields in the Users table:
- `SubscriptionStatus` - Set to "cancelled"
- `CancelledAt` - Timestamp when subscription was cancelled (ISO 8601 format)
- Preserves `SubscriptionTier`, `BillingCycle`, and `NextBillingDate` to allow continued access

**Handling Non-Expired Subscriptions:**
When a user cancels a paid subscription before it expires:
1. Status is marked as "cancelled" immediately
2. User retains access to paid tier features until `NextBillingDate`
3. After `NextBillingDate`, a scheduled job should downgrade them to free tier
4. `CancelledAt` timestamp records when cancellation was requested

**Note:** Payment processing (Stripe) to be added later. Currently cancels subscription immediately but preserves access until billing period ends.

---

## Authentication

All admin endpoints require JWT authentication via Bearer token.

**Request Header:**
```http
Authorization: Bearer <jwt-token>
```

**Getting a Token:**
Tokens are obtained through:
1. `POST /api/public/signup` - Returns token on registration
2. `POST /api/public/login` - Returns token on login
3. `POST /api/public/refreshToken` - Refresh expired token

**Token Format:**
- JWT tokens are stored in HTTP-only cookies (secure)
- Tokens expire after 24 hours
- Refresh tokens valid for 7 days

**Authentication Context (User Object):**

The `/login`, `/signup`, and `/refreshToken` endpoints return a user object in the auth context that includes 2FA configuration:

```json
{
  "user": {
    "UserId": "user-abc123",
    "email": "user@example.com",
    "username": "johndoe",
    "userRole": "user",
    "roles": ["user"],
    "permissions": [...],
    "userManagements": [],
    "tier": "free",
    "twoFactorEnabled": true,
    "twoFactorEmailEnabled": true,
    "twoFactorTotpEnabled": false
  }
}
```

**2FA Configuration Fields:**
- `twoFactorEnabled` - Boolean indicating if ANY 2FA method is enabled
- `twoFactorEmailEnabled` - Boolean for email-based 2FA status
- `twoFactorTotpEnabled` - Boolean for TOTP-based 2FA status

**Note:** The 2FA configuration is available in the auth context from login/signup/refresh endpoints, NOT from the `/admin/getProfile` endpoint.

**Error Handling:**
If authentication fails, endpoints return:
```json
{
  "error": "Unauthorized"
}
```
Status Code: `401 Unauthorized`

---

## Questions & Clarifications

### For Frontend Engineers:

1. **Phone Number:**
   - Do you need phone number storage immediately?
   - What phone number format validation do you prefer?
   - Phone number is currently NOT stored in the database

2. **Email Change Verification:**
   - The requirements mention email verification with tokens
   - Initial implementation updates email immediately with password confirmation
   - Do you need the full verification flow, or is immediate update acceptable?

3. **2FA Reset Password Confirmation:**
   - Should resetting 2FA require password confirmation for extra security?
   - Current implementation allows reset with valid JWT only

4. **Payment Integration:**
   - Payment processing (Stripe) is NOT currently implemented
   - Upgrade/Cancel subscription endpoints are stubs
   - What is the timeline for payment integration?
   - Should these be implemented or documented as "coming soon"?

5. **Subscription Details:**
   - Current system tracks tier (free/premium/enterprise) and status
   - Detailed billing information (billing cycle, next billing date, amount) is NOT stored
   - Do you need this information displayed even without payment processing?

6. **Settings Page Display:**
   - The existing `/admin/getProfile` endpoint returns basic profile info
   - 2FA status is in the authentication context (login response)
   - Should we create a new dedicated `/admin/getSettings` endpoint that combines this data?
   - Or should frontend call multiple endpoints?

### For Backend Implementation:

1. **Email Change Complexity:**
   - Changing email requires changing PartitionKey in Azure Table Storage
   - This is a complex operation that needs to:
     - Create new entity with new PartitionKey
     - Copy all user data
     - Update related records (refresh tokens, API keys, etc.)
     - Delete old entity
   - Should we implement this or recommend external support/admin panel?

2. **Payment Provider:**
   - Requirements mention Stripe
   - Need Stripe account credentials
   - Need webhook endpoint URL for production
   - Test mode vs. production mode handling

3. **Subscription Tables:**
   - Should we create the additional tables mentioned in requirements now?
   - Or wait until payment integration is ready?

---

## Implementation Status Summary

| Endpoint | Status | Notes |
|----------|--------|-------|
| GET /admin/getProfile | ✅ Exists | Use for settings display |
| PUT /admin/updatePassword | 🆕 Implemented | Tested - Ready to use |
| PUT /admin/updateEmail | 🆕 Implemented | Tested - Simplified version without verification |
| PUT /admin/updatePhone | 🆕 Implemented | Tested - Adds new field to Users table |
| POST /admin/2fatokensetup?action=disable | ✅ Exists | Use for disabling 2FA |
| GET /admin/getSubscription | 🆕 Implemented | Returns tier, status, billing info |
| POST /admin/upgradeSubscription | 🆕 Implemented | Updates subscription in Users table (no payment processing) |
| POST /admin/cancelSubscription | 🆕 Implemented | Marks subscription as cancelled, preserves access until billing date |

---

## Testing Endpoints

### Using curl:

**Get Settings (existing):**
```bash
curl http://localhost:7071/api/admin/getProfile \
  -H "Authorization: Bearer <your-jwt-token>"
```

**Update Password:**
```bash
curl -X PUT http://localhost:7071/api/admin/updatePassword \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"currentPassword":"oldPass123","newPassword":"newPass123"}'
```

**Update Email:**
```bash
curl -X PUT http://localhost:7071/api/admin/updateEmail \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"newEmail":"new@example.com","password":"currentPass123"}'
```

**Update Phone:**
```bash
curl -X PUT http://localhost:7071/api/admin/updatePhone \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+1 555 123 4567"}'
```

**Reset 2FA:**
```bash
curl -X POST http://localhost:7071/api/admin/2fatokensetup?action=disable \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Get Subscription:**
```bash
curl http://localhost:7071/api/admin/getSubscription \
  -H "Authorization: Bearer <your-jwt-token>"
```

**Upgrade Subscription:**
```bash
curl -X POST http://localhost:7071/api/admin/upgradeSubscription \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"tier":"premium","billingCycle":"monthly"}'
```

**Cancel Subscription:**
```bash
curl -X POST http://localhost:7071/api/admin/cancelSubscription \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{}'
```

---

## Next Steps

1. **Review this documentation** with the frontend team
2. **Answer questions** listed in the clarifications section
3. **Test the new endpoints** using the curl examples above
4. **Decide on payment integration timeline** for subscription features
5. **Implement email verification flow** if required
6. **Add phone number validation** if needed

---

**Document Version:** 1.0  
**Last Updated:** January 6, 2026  
**Contact:** Backend team for questions
