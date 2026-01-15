# Agency/Multi-Account API Summary for Frontend Team

## Quick Overview

Four new API endpoints have been implemented for the agency/multi-account profiles feature:

1. **PurchaseUserPack** - Purchase or cancel user packs (auto-upgrades user role)
2. **GetSubAccounts** - List all sub-accounts with quota information
3. **CreateSubAccount** - Create a new sub-account
4. **DeleteSubAccount** - Delete an existing sub-account

All endpoints follow PowerShell conventions (PascalCase) and use the existing permission system.

---

## 1. Purchase User Pack

**Endpoint:** `POST /admin/PurchaseUserPack`

**Permission Required:** `write:subscription` (all regular users have this)

**Purpose:** Purchase or cancel user packs. Automatically upgrades user to `agency_admin_user` role on purchase.

### Request Body

```json
{
  "packType": "starter",           // Required: "starter" | "business" | "enterprise" | "none"
  "billingCycle": "monthly",       // Required: "monthly" | "annual"
  "customLimit": 25                // Optional: Only for enterprise pack (positive integer)
}
```

### Response

**Success (200):**
```json
{
  "userId": "user-abc123",
  "packType": "starter",
  "packLimit": 3,
  "role": "agency_admin_user",
  "expiresAt": "2026-02-15T10:00:00Z",
  "message": "User pack purchased successfully. Your account has been upgraded to Agency Admin."
}
```

**Cancellation (200):**
```json
{
  "userId": "user-abc123",
  "packType": "none",
  "packLimit": 0,
  "role": "user",
  "expiresAt": null,
  "message": "User pack cancelled successfully. Your account has been downgraded to regular user."
}
```

**Error (400):**
```json
{
  "error": "Invalid pack type. Must be: starter, business, enterprise, or none"
}
```

```json
{
  "error": "Cannot cancel user pack while sub-accounts exist. Please delete all sub-accounts first."
}
```

### Pack Types & Limits

| Pack Type  | Max Sub-Accounts | Monthly Cost |
|-----------|------------------|--------------|
| None      | 0                | $0           |
| Starter   | 3                | $15          |
| Business  | 10               | $50          |
| Enterprise| Custom or Unlimited | Custom   |

### Notes

- When purchasing a pack, user is automatically upgraded to `agency_admin_user` role
- When cancelling (`packType: "none"`), user is downgraded to `user` role
- Cannot cancel if sub-accounts exist (must delete them first)
- Enterprise pack with `customLimit: -1` means unlimited
- `expiresAt` is calculated based on billing cycle (monthly = +30 days, annual = +365 days)

---

## 2. Get Sub-Accounts

**Endpoint:** `GET /admin/GetSubAccounts`

**Permission Required:** `manage:subaccounts` (only `agency_admin_user` role has this)

**Purpose:** List all sub-accounts for the authenticated user with quota information.

### Request

No request body needed (uses authenticated user's ID from JWT).

### Response

**Success (200):**
```json
{
  "subAccounts": [
    {
      "userId": "user-sub1",
      "username": "client-acme",
      "displayName": "Acme Corp",
      "type": "client",
      "status": "active",
      "createdAt": "2026-01-10T08:30:00Z"
    },
    {
      "userId": "user-sub2",
      "username": "brand-techco",
      "displayName": "TechCo Brand",
      "type": "brand",
      "status": "active",
      "createdAt": "2026-01-12T14:20:00Z"
    }
  ],
  "total": 2,
  "limits": {
    "maxSubAccounts": 10,
    "usedSubAccounts": 2,
    "remainingSubAccounts": 8,
    "userPackType": "business",
    "userPackExpired": false
  }
}
```

**No Sub-Accounts (200):**
```json
{
  "subAccounts": [],
  "total": 0,
  "limits": {
    "maxSubAccounts": 3,
    "usedSubAccounts": 0,
    "remainingSubAccounts": 3,
    "userPackType": "starter",
    "userPackExpired": false
  }
}
```

**Error (403):**
```json
{
  "error": "You do not have permission to access this resource"
}
```

### Notes

- Only users with `agency_admin_user` role can access this endpoint
- Returns empty array if no sub-accounts exist
- `limits` object shows quota info for UI display (progress bars, etc.)
- `userPackExpired` is `true` if pack expired but sub-accounts still exist
- For unlimited enterprise packs, `maxSubAccounts` is displayed as "unlimited" in the UI

---

## 3. Create Sub-Account

**Endpoint:** `POST /admin/CreateSubAccount`

**Permission Required:** `manage:subaccounts` (only `agency_admin_user` role has this)

**Purpose:** Create a new sub-account under the authenticated user.

### Request Body

```json
{
  "username": "client-new",               // Required: 3-30 chars, alphanumeric + hyphens/underscores, must be unique
  "displayName": "New Client Name",       // Optional: Display name for the sub-account
  "type": "client"                        // Optional: "client" | "brand" | "other" (default: "client")
}
```

**Note:** Sub-accounts do NOT have email addresses. Any emails that would be sent to a sub-account will be sent to the parent account instead.

### Response

**Success (201):**
```json
{
  "userId": "user-sub3",
  "username": "client-new",
  "displayName": "New Client Name",
  "isSubAccount": true,
  "authDisabled": true,
  "tier": "premium",
  "createdAt": "2026-01-15T10:30:00Z",
  "message": "Sub-account created successfully"
}
```

**Error (400):**
```json
{
  "error": "Username is required"
}
```

```json
{
  "error": "Username must be 3-30 characters and contain only alphanumeric characters, hyphens, and underscores"
}
```

```json
{
  "error": "User pack limit reached. You have 3/3 sub-accounts. Upgrade your pack to create more."
}
```

```json
{
  "error": "Your user pack has expired. Please renew to create sub-accounts."
}
```

**Error (403):**
```json
{
  "error": "You do not have permission to access this resource"
}
```

### Notes

- Sub-accounts **do NOT have email addresses** - all notifications go to parent account
- Sub-account inherits parent's subscription tier
- Sub-account is created with `IsSubAccount=true` and `AuthDisabled=true`
- Sub-account gets `sub_account_user` role (content management permissions only)
- Sub-account **cannot login** directly or via API
- Sub-account **cannot** manage auth, billing, or users
- Username must be unique across all users

---

## 4. Delete Sub-Account

**Endpoint:** `DELETE /admin/DeleteSubAccount`

**Permission Required:** `manage:subaccounts` (only `agency_admin_user` role has this)

**Purpose:** Delete an existing sub-account.

### Request Body

```json
{
  "userId": "user-sub3"    // Required: ID of the sub-account to delete
}
```

### Response

**Success (200):**
```json
{
  "userId": "user-sub3",
  "message": "Sub-account deleted successfully"
}
```

**Error (400):**
```json
{
  "error": "User ID is required"
}
```

**Error (404):**
```json
{
  "error": "Sub-account not found or you do not own this sub-account"
}
```

**Error (403):**
```json
{
  "error": "You do not have permission to access this resource"
}
```

### Notes

- Only the parent (owner) can delete their own sub-accounts
- Verifies ownership via SubAccounts table
- Verifies target user is actually a sub-account
- Deletes both the relationship record and the user record
- This action is permanent and cannot be undone

---

## Permission System

### Three User Roles

1. **`user`** (Regular User)
   - All standard permissions
   - **Cannot** access sub-account management endpoints
   - Must purchase a user pack to become an agency admin

2. **`agency_admin_user`** (Agency Admin)
   - All `user` permissions
   - **Plus:** `manage:subaccounts` permission
   - Automatically assigned when purchasing a user pack
   - Can create/view/delete sub-accounts

3. **`sub_account_user`** (Sub-Account)
   - Content management only: profile, links, pages, appearance, analytics, shortlinks
   - **Cannot** login directly or via API (`AuthDisabled=true`)
   - **Cannot** manage: auth (2FA, API keys, credentials), billing, users, sub-accounts
   - Inherits parent's subscription tier

### Role Transition Flow

```
Regular User (user)
    |
    | Purchase User Pack
    ↓
Agency Admin (agency_admin_user) ← Can manage sub-accounts
    |
    | Cancel User Pack (only if no sub-accounts exist)
    ↓
Regular User (user)
```

---

## Authentication & JWT Updates

### Sub-Accounts in JWT and Auth Responses

Starting with this implementation, the JWT token and authentication responses (login, refresh token) now include a `subAccounts` array for agency admin users. This allows the frontend to:

1. **Display all sub-accounts** immediately upon login
2. **Use the existing user context system** to switch between parent and sub-accounts
3. **Show sub-account permissions** for each profile

### Updated Auth Response Structure

```json
{
  "user": {
    "UserId": "user-123",
    "username": "john-doe",
    "email": "john@example.com",
    "tier": "premium",
    "userRole": "agency_admin_user",
    "permissions": [
      "read:dashboard",
      "write:profile",
      "manage:subaccounts",
      // ... all other permissions
    ],
    "userManagements": [],        // Existing feature for user managers
    "subAccounts": [              // NEW: Sub-accounts array
      {
        "UserId": "sub-abc123",
        "username": "client-alpha",
        "displayName": "Client Alpha Inc",
        "role": "sub_account_user",
        "permissions": [
          "read:dashboard",
          "read:profile",
          "write:profile",
          "read:links",
          "write:links",
          // ... content management permissions only
        ],
        "type": "client",
        "status": "active"
      },
      {
        "UserId": "sub-def456",
        "username": "brand-beta",
        "displayName": "Brand Beta",
        "role": "sub_account_user",
        "permissions": [ /* ... */ ],
        "type": "brand",
        "status": "active"
      }
    ],
    "IsSubAccount": false,
    "AuthDisabled": false,
    "twoFactorEnabled": false,
    "twoFactorEmailEnabled": false,
    "twoFactorTotpEnabled": false
  }
}
```

### Key Points

- **`subAccounts` array** is only populated for `agency_admin_user` role
- **Regular users** and **sub-accounts** will have an empty array: `subAccounts: []`
- Each sub-account includes:
  - `UserId` - Unique identifier for context switching
  - `username` - Display name for the profile
  - `displayName` - Optional friendly name
  - `role` - Always `"sub_account_user"`
  - `permissions` - List of allowed operations (content management only)
  - `type` - Optional categorization (e.g., "client", "brand")
  - `status` - Account status (e.g., "active")

### Using Sub-Accounts for Context Switching

The frontend can use the existing user context mechanism to switch between parent and sub-accounts:

```javascript
// After login, store sub-accounts
const { user } = authResponse;
const subAccounts = user.subAccounts || [];

// Display sub-accounts in a switcher UI
<ProfileSwitcher 
  currentUser={user}
  subAccounts={subAccounts}
  onSwitch={(userId) => switchContext(userId)}
/>

// When user switches context
function switchContext(userId) {
  // Use existing context switching mechanism
  // The backend will validate that the user has access to this sub-account
  // and return updated permissions for the selected profile
  
  // For now, you can use the permissions from the subAccounts array
  // to determine what UI elements to show
  const selectedAccount = subAccounts.find(sa => sa.UserId === userId);
  updateUIBasedOnPermissions(selectedAccount.permissions);
}
```

### Benefits

1. **Single API call** - No need to call GetSubAccounts separately on login
2. **Immediate UX** - Show sub-account switcher immediately
3. **Consistent pattern** - Mirrors existing `userManagements` structure
4. **Efficient** - Sub-accounts loaded once and cached in JWT
5. **Secure** - Sub-account list is validated server-side during auth

---

## Authentication & Permissions

### How to Check Permissions in Frontend

The auth response includes a `permissions` array:

```json
{
  "UserId": "user-123",
  "username": "john-doe",
  "email": "john@example.com",
  "tier": "premium",
  "permissions": [
    "read:dashboard",
    "write:profile",
    "read:subscription",
    "write:subscription",
    "manage:subaccounts"     // ← Only present for agency_admin_user
  ],
  "IsSubAccount": false,
  "AuthDisabled": false
}
```

**To show sub-account management UI:**
```javascript
const canManageSubAccounts = user.permissions.includes('manage:subaccounts');

if (canManageSubAccounts) {
  // Show sub-account management section
}
```

**To show user pack purchase UI:**
```javascript
const canPurchasePacks = user.permissions.includes('write:subscription') && !user.IsSubAccount;

if (canPurchasePacks) {
  // Show user pack purchase section
}
```

---

## Error Handling

All endpoints return standard error responses:

**400 Bad Request:**
- Validation errors (missing fields, invalid formats, limits exceeded)

**403 Forbidden:**
- Permission denied (user doesn't have required permission)
- Auth disabled (sub-account trying to access restricted endpoint)

**404 Not Found:**
- Resource not found or ownership verification failed

**500 Internal Server Error:**
- Database errors or unexpected server issues

---

## Complete User Flow Example

### 1. User Purchases User Pack

```javascript
// User is currently role: "user"
POST /admin/PurchaseUserPack
{
  "packType": "business",
  "billingCycle": "monthly"
}

// Response: User is now role: "agency_admin_user"
{
  "userId": "user-123",
  "packType": "business",
  "packLimit": 10,
  "role": "agency_admin_user",
  "expiresAt": "2026-02-15T10:00:00Z",
  "message": "User pack purchased successfully. Your account has been upgraded to Agency Admin."
}
```

### 2. User Creates Sub-Accounts

```javascript
// User can now access sub-account endpoints
POST /admin/CreateSubAccount
{
  "email": "client1@example.com",
  "username": "client-one",
  "displayName": "Client One",
  "type": "client"
}

// Response: Sub-account created
{
  "userId": "user-sub1",
  "username": "client-one",
  "email": "client1@example.com",
  "displayName": "Client One",
  "isSubAccount": true,
  "authDisabled": true,
  "tier": "premium",
  "createdAt": "2026-01-15T10:30:00Z"
}
```

### 3. User Lists Sub-Accounts

```javascript
GET /admin/GetSubAccounts

// Response: Shows all sub-accounts with quota
{
  "subAccounts": [
    {
      "userId": "user-sub1",
      "username": "client-one",
      "email": "client1@example.com",
      "displayName": "Client One",
      "type": "client",
      "status": "active",
      "createdAt": "2026-01-15T10:30:00Z"
    }
  ],
  "total": 1,
  "limits": {
    "maxSubAccounts": 10,
    "usedSubAccounts": 1,
    "remainingSubAccounts": 9,
    "userPackType": "business",
    "userPackExpired": false
  }
}
```

### 4. User Switches Context (Existing Mechanism)

```javascript
// Use existing context switching to manage sub-account
// Sub-account has limited permissions (content only)
// Sub-account inherits parent's tier
```

### 5. User Deletes Sub-Account

```javascript
DELETE /admin/DeleteSubAccount
{
  "userId": "user-sub1"
}

// Response: Sub-account deleted
{
  "userId": "user-sub1",
  "message": "Sub-account deleted successfully"
}
```

### 6. User Cancels User Pack

```javascript
// User must delete all sub-accounts first
DELETE /admin/DeleteSubAccount (for each sub-account)

// Then cancel pack
POST /admin/PurchaseUserPack
{
  "packType": "none",
  "billingCycle": "monthly"
}

// Response: User is downgraded to role: "user"
{
  "userId": "user-123",
  "packType": "none",
  "packLimit": 0,
  "role": "user",
  "expiresAt": null,
  "message": "User pack cancelled successfully. Your account has been downgraded to regular user."
}
```

---

## UI Recommendations

### Sub-Account Management Page

**When user has no pack:**
- Show "Upgrade to Agency Plan" button
- Explain user pack benefits
- Show pricing table (Starter: 3, Business: 10, Enterprise: Custom)

**When user has pack:**
- Show current pack info (type, limit, expiration date)
- Show sub-account list with create/delete actions
- Show quota progress bar (X/Y sub-accounts used)
- Show "Manage Subscription" button (upgrade/downgrade/cancel)

**When pack is expired:**
- Show warning banner: "Your user pack has expired. Renew to create new sub-accounts."
- Disable "Create Sub-Account" button
- Show existing sub-accounts (read-only)
- Show "Renew Pack" button

### Context Switcher Component

- Show parent account + all sub-accounts in dropdown
- Mark sub-accounts with icon/badge
- Switch context on selection (use existing mechanism)
- Sub-accounts see limited navigation (no auth/billing/users sections)

### Error Messages

- Show validation errors inline on form fields
- Show quota warnings before hitting limit ("2/3 sub-accounts used")
- Show clear error messages from API responses
- Suggest upgrades when limit reached

---

## Testing Checklist

### Purchase User Pack
- [ ] Can purchase starter pack (monthly/annual)
- [ ] Can purchase business pack (monthly/annual)
- [ ] Can purchase enterprise pack with custom limit
- [ ] Enterprise pack with -1 shows "unlimited"
- [ ] User role upgrades to agency_admin_user
- [ ] Cannot purchase if already a sub-account
- [ ] Can cancel pack (packType: "none")
- [ ] Cannot cancel if sub-accounts exist
- [ ] User role downgrades to user on cancel

### Get Sub-Accounts
- [ ] Returns empty array when no sub-accounts
- [ ] Returns all sub-accounts with correct data
- [ ] Limits object shows correct quota
- [ ] userPackExpired flag is correct
- [ ] Regular users cannot access (403)
- [ ] Sub-accounts cannot access (403)

### Create Sub-Account
- [ ] Can create with valid data
- [ ] Cannot create with invalid email
- [ ] Cannot create with duplicate email
- [ ] Cannot create with invalid username
- [ ] Cannot create with duplicate username
- [ ] Cannot exceed pack limit
- [ ] Cannot create with expired pack
- [ ] Sub-account has correct permissions
- [ ] Sub-account inherits parent tier
- [ ] Sub-account cannot login

### Delete Sub-Account
- [ ] Can delete own sub-account
- [ ] Cannot delete other user's sub-account
- [ ] Cannot delete non-sub-account user
- [ ] Sub-account and relationship both deleted

---

## Database Schema Reference

### Users Table (New Fields)

```
Role: string
  - "user" (default)
  - "agency_admin_user" (when user pack active)
  - "sub_account_user" (for sub-accounts)
  - "user_manager" (existing)

IsSubAccount: boolean (default: false)
AuthDisabled: boolean (default: false)

UserPackType: string
  - "none" (default)
  - "starter" (3 sub-accounts)
  - "business" (10 sub-accounts)
  - "enterprise" (custom/unlimited)

UserPackLimit: integer (0, 3, 10, or custom, -1 for unlimited)
UserPackPurchasedAt: datetime
UserPackExpiresAt: datetime
```

### SubAccounts Table (New Table)

```
PartitionKey: ParentAccountId
RowKey: SubAccountId
Type: string ("client", "brand", "other")
Status: string ("active")
CreatedAt: datetime
```

---

## Questions or Issues?

If you encounter any issues or have questions about the API implementation, please reach out to the backend team.

**Implementation Status:** ✅ Complete and ready for integration
**Last Updated:** January 15, 2026
