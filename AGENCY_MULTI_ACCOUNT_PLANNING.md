# Agency/Multi-Account Profiles - Planning Document

## Overview

This document outlines the comprehensive plan for implementing agency/multi-account profiles in LinkToMe. The feature enables a parent account to create and manage multiple sub-accounts (child profiles) that:
- Do **NOT** have independent login credentials (cannot login directly or via API)
- Do **NOT** have access to management features (API keys, MFA, user management, subscription settings)
- **DO** inherit the parent account's subscription tier and features
- **DO** maintain their own public profiles, links, pages, and appearance
- **DO** have analytics tracked separately
- **DO** operate like any other account (within feature limits)

This is designed for agencies or users who manage multiple brands/clients and want to consolidate billing and management under one account.

### Business Model

**User Pack Purchase System:**
- Parent accounts purchase their base subscription (Free, Pro, Premium, Enterprise)
- Additional sub-accounts are purchased in **user packs** separately
- User pack options: 3 users ($x), 10 users ($y), custom enterprise packs
- Features scale based on parent's plan and the user pack purchased
- All sub-accounts covered under parent's billing

---

## Current System Analysis

### Existing Infrastructure
The codebase already has foundational pieces that can be leveraged:

1. **User Management System** (`UserManagers` table)
   - Current: Allows user-to-user management relationships with roles
   - State: pending, accepted, rejected
   - Used for delegated management between separate accounts

2. **Role-Based Permissions** (`Get-DefaultRolePermissions.ps1`)
   - `user` role: Full permissions including subscription management
   - `user_manager` role: Limited permissions (no API keys, 2FA setup, subscription changes)

3. **Subscription Tier System** (`Get-TierFeatures.ps1`)
   - Four tiers: free, pro, premium, enterprise
   - Feature gating based on tier
   - Centralized subscription access via `Get-UserSubscription.ps1`

4. **Multi-Page Support** (`MULTI_PAGE_IMPLEMENTATION.md`)
   - Users can create multiple pages with unique slugs
   - Page limits based on tier
   - Separate analytics per page

5. **Authentication Context** (`Get-UserAuthContext.ps1`)
   - Already supports `UserManagements` array
   - Includes tier information from managed users

### Current Limitations
- `UserManagers` creates relationships between **existing accounts** with separate logins
- No concept of "sub-accounts" that exist solely under a parent
- No tier inheritance mechanism for managed accounts
- No restriction on login for sub-accounts

---

## Proposed Solution: Sub-Account System

### Core Concept

**Sub-Accounts** are lightweight user profiles that:
1. Are created and owned by a **Parent Account**
2. Cannot login independently (no credentials)
3. Inherit subscription tier from parent
4. Have their own public presence (username, pages, links, appearance)
5. Can only be managed through the parent account

**Parent Accounts** are regular user accounts that:
1. Purchase base subscription (Free, Pro, Premium, Enterprise)
2. Optionally purchase user packs to create sub-accounts
3. Can create multiple sub-accounts (based on purchased user pack)
4. Manage all aspects of their sub-accounts
5. Pay for base subscription + user pack (consolidated billing)
6. Can switch context to manage any of their sub-accounts

---

## Database Schema Changes

### 1. Users Table - New Fields

Add to existing `Users` table:

```plaintext
- IsSubAccount (boolean, default: false)
  - Marks this as a sub-account that cannot login
  
- ParentAccountId (string, nullable)
  - References the RowKey of the parent account
  - NULL for regular accounts
  - Required for sub-accounts
  
- SubAccountType (string, nullable)
  - Type classification: 'agency_client', 'brand', 'project', etc.
  - For future extensibility and filtering
  
- CreatedByUserId (string, nullable)
  - Tracks which user created this sub-account
  - Useful for audit trail
```

### 2. New Table: SubAccounts (Optional Alternative)

Instead of modifying Users table, could create a separate linking table:

```plaintext
Table: SubAccounts
PartitionKey: ParentAccountId (parent's UserId)
RowKey: SubAccountId (sub-account's UserId)
Fields:
  - SubAccountType (string)
  - CreatedAt (datetime)
  - CreatedByUserId (string)
  - Status (string: 'active', 'suspended', 'deleted')
  - Notes (string, optional)
```

**Recommendation**: Use the SubAccounts table approach for cleaner separation.

### 3. Subscription Inheritance Logic

Modify `Get-UserSubscription.ps1` to:
1. Check if user is a sub-account
2. If yes, recursively look up parent's subscription
3. Return parent's effective tier for feature gating

```powershell
if ($User.IsSubAccount -and $User.ParentAccountId) {
    # Get parent user
    $ParentUser = Get-User -UserId $User.ParentAccountId
    # Return parent's subscription
    return Get-UserSubscription -User $ParentUser
}
```

---

## User Pack System for Sub-Accounts

### Subscription Model

Instead of tier-based sub-account limits, sub-accounts are purchased separately as **user packs**:

**Base Subscription:**
- Free: Base features for parent account only
- Pro: Enhanced features for parent account
- Premium: Premium features for parent account
- Enterprise: Enterprise features for parent account

**User Pack Add-Ons** (purchased separately):
- **Starter Pack**: 3 sub-accounts ($x/month)
- **Business Pack**: 10 sub-accounts ($y/month)
- **Enterprise Pack**: Custom number of sub-accounts (custom pricing)

### User Pack Features

| Pack Type | Sub-Accounts | Monthly Cost | Notes |
|-----------|--------------|--------------|-------|
| No Pack | 0 | $0 | Default (no sub-accounts) |
| Starter Pack | 3 | $x | Small agencies/creators |
| Business Pack | 10 | $y | Mid-size agencies |
| Enterprise Pack | Custom | Custom | Large agencies, negotiated |

**Important**: 
- User packs are **add-ons** to base subscription
- Total cost = Base subscription + User pack
- Example: Pro ($15) + Business Pack ($30) = $45/month
- Sub-accounts inherit parent's tier features
- All sub-accounts share parent's billing

### Database Storage

Add to Users table or use separate Subscription table:

```plaintext
- UserPackType (string, nullable)
  - Values: null, 'starter', 'business', 'enterprise'
  - NULL = no pack purchased
  
- UserPackLimit (integer, default: 0)
  - Maximum sub-accounts allowed based on purchased pack
  - 0 = no pack, 3 = starter, 10 = business, -1 = enterprise unlimited
  
- UserPackPurchasedAt (datetime, nullable)
  - When the user pack was first purchased
  
- UserPackExpiresAt (datetime, nullable)
  - Expiration date for the user pack
  - Typically monthly or annual billing cycle
```

### Update `Get-TierFeatures.ps1`

Instead of embedding limits in tier features, check user pack separately:

```powershell
function Get-UserPackLimit {
    param([Parameter(Mandatory)][object]$User)
    
    $UserPackType = if ($User.UserPackType) { $User.UserPackType } else { $null }
    
    $PackLimits = @{
        $null = 0
        'starter' = 3
        'business' = 10
        'enterprise' = -1  # Unlimited
    }
    
    return $PackLimits[$UserPackType]
}
```

---

## API Changes

### New Admin Endpoints

#### 1. **GET /admin/getSubAccounts**
List all sub-accounts owned by the authenticated user.

**Authentication**: JWT (parent account only)

**Response**:
```json
{
  "subAccounts": [
    {
      "userId": "user-abc123",
      "username": "client-brand1",
      "displayName": "Brand One",
      "email": "brand1@parent.com",
      "type": "agency_client",
      "status": "active",
      "createdAt": "2024-01-01T00:00:00Z",
      "pagesCount": 2,
      "linksCount": 15
    }
  ],
  "total": 1,
  "limit": 10
}
```

#### 2. **POST /admin/createSubAccount**
Create a new sub-account under the authenticated parent account.

**Authentication**: JWT (parent account only)

**Request Body**:
```json
{
  "username": "client-brand1",
  "email": "brand1@parent.com",
  "displayName": "Brand One",
  "bio": "Official Brand One page",
  "type": "agency_client"
}
```

**Validation**:
- Username must be unique across entire system
- Email can be shared within parent's sub-accounts
- Parent must have purchased a user pack (Starter, Business, or Enterprise)
- Parent must be within their user pack limit for sub-accounts
- Verify user pack is not expired

**Response**:
```json
{
  "message": "Sub-account created successfully",
  "subAccount": {
    "userId": "user-abc123",
    "username": "client-brand1",
    "email": "brand1@parent.com",
    "displayName": "Brand One",
    "type": "agency_client"
  }
}
```

#### 3. **PUT /admin/updateSubAccount**
Update sub-account details (profile only, not credentials).

**Authentication**: JWT (parent account only)

**Request Body**:
```json
{
  "userId": "user-abc123",
  "displayName": "Brand One Updated",
  "bio": "Updated bio",
  "avatar": "https://example.com/avatar.jpg",
  "type": "brand"
}
```

#### 4. **DELETE /admin/deleteSubAccount**
Delete a sub-account and all associated data (pages, links, analytics).

**Authentication**: JWT (parent account only)

**Query Parameters**:
- `userId` (required): Sub-account user ID

**Response**:
```json
{
  "message": "Sub-account deleted successfully"
}
```

#### 5. **POST /admin/switchContext**
Switch management context to a sub-account.

**Authentication**: JWT (parent account only)

**Request Body**:
```json
{
  "userId": "user-abc123"
}
```

**Response**:
Returns a new JWT or session token that includes:
```json
{
  "accessToken": "eyJ...",
  "context": {
    "parentUserId": "user-parent123",
    "contextUserId": "user-abc123",
    "contextUsername": "client-brand1"
  }
}
```

**Note**: All subsequent requests with this token operate in the sub-account's context.

### Modified Existing Endpoints

#### Authentication Endpoints
- **POST /public/login**
  - Add validation to reject login attempts for sub-accounts
  - Return clear error: "This account cannot login directly"

- **POST /public/signup**
  - No changes needed (sub-accounts created via createSubAccount)

#### Profile & Link Management
All existing admin endpoints should:
1. Check if request has `contextUserId` (from switchContext)
2. Use `contextUserId` for operations instead of authenticated user ID
3. Verify parent owns the sub-account

Affected endpoints:
- GET/PUT /admin/getProfile, /admin/updateProfile
- GET/PUT /admin/getLinks, /admin/updateLinks
- GET/POST/PUT/DELETE /admin/getPages, /admin/createPage, /admin/updatePage, /admin/deletePage
- GET/PUT /admin/getAppearance, /admin/updateAppearance
- GET /admin/getAnalytics

#### Restricted Endpoints for Sub-Accounts
These endpoints should return 403 Forbidden when used in sub-account context:
- All 2FA endpoints (`/admin/2fatokensetup`)
- API key endpoints (`/admin/apikeys*`)
- Subscription endpoints (`/admin/getSubscription`, `/admin/upgradeSubscription`, `/admin/cancelSubscription`)
- Password/email/phone change endpoints
- User manager endpoints (`/admin/userManager*`)

---

## Permission System Updates

### New Permissions
Add to role permissions system:

```powershell
# Parent account permissions
'read:subaccounts'
'write:subaccounts'
'delete:subaccounts'
'switch:subaccounts'

# Context-aware restrictions
'restricted:apikeys'      # Cannot manage API keys in sub-account context
'restricted:2fa'          # Cannot manage 2FA in sub-account context
'restricted:subscription' # Cannot manage subscription in sub-account context
```

### Context-Aware Permission Checking

Update `Get-UserAuthContext.ps1` to include:
```powershell
@{
    UserId = $User.RowKey
    IsSubAccountContext = $false
    ParentUserId = $null
    ContextUserId = $User.RowKey
    
    # If in sub-account context:
    # IsSubAccountContext = $true
    # ParentUserId = "user-parent123"
    # ContextUserId = "user-subaccount123"
}
```

Update `Test-ContextAwarePermission.ps1` to:
1. Check if in sub-account context
2. Block restricted permissions in sub-account context
3. Allow normal permissions for content management

---

## Authentication & Session Management

### JWT Token Enhancement

When switching context, the JWT should include:

```json
{
  "userId": "user-parent123",        // Parent account (for auth)
  "contextUserId": "user-abc123",    // Sub-account (for operations)
  "isSubAccountContext": true,
  "exp": 1234567890
}
```

### Context Switching Flow

1. Parent logs in normally → Gets standard JWT
2. Parent calls `/admin/switchContext?userId=user-abc123`
3. Backend validates:
   - Parent owns the sub-account
   - Sub-account is active
4. Return new JWT with context info
5. Frontend stores and uses context JWT
6. All API calls use context JWT
7. Backend routes operations to `contextUserId`

### Security Considerations

1. **Ownership Validation**: Always verify parent owns sub-account
2. **Context Validation**: Validate contextUserId exists in every request
3. **Permission Isolation**: Block restricted operations in context
4. **Audit Logging**: Log all context switches and sub-account operations
5. **Rate Limiting**: Apply parent's rate limits across all sub-accounts

---

## Feature Gating & Tier Enforcement

### Subscription Tier Inheritance

Sub-accounts inherit parent's tier for:
- Link limits (maxLinks)
- Page limits (maxPages)
- Short link limits
- Advanced analytics access
- Custom themes
- API rate limits (even though they can't create API keys)

### Feature Usage Aggregation

Question for discussion: Should feature usage be:
1. **Option A - Individual**: Each sub-account has separate limits
   - Parent: 50 links, Sub1: 50 links, Sub2: 50 links
   - Pro: More flexible, easier to implement
   - Con: Could be seen as gaming the system

2. **Option B - Aggregated**: Combined limits across all sub-accounts
   - Parent + all subs share 50 links total
   - Pro: More fair, prevents abuse
   - Con: More complex tracking, may frustrate users

3. **Option C - Multiplied**: Limits scale with sub-account count
   - Pro tier: 50 links × (1 parent + 3 subs) = 200 links total
   - Pro: Scales well, feels generous
   - Con: Could devalue higher tiers

**Recommendation**: Option A (Individual limits) for MVP, with clear documentation. Consider Option C for future pricing model update.

---

## Analytics & Data Separation

### Analytics Table Updates

**Current**: Analytics track by `UserId`

**Proposed**: Continue tracking by `UserId`
- Each sub-account has distinct analytics
- Parent dashboard shows aggregate view option
- Drill-down to individual sub-account analytics

### Parent Dashboard Enhancements

New `/admin/getDashboardStats` response when parent has sub-accounts:

```json
{
  "parentAccount": {
    "links": 10,
    "views": 1000,
    "clicks": 500
  },
  "subAccounts": [
    {
      "userId": "user-abc123",
      "username": "client-brand1",
      "links": 15,
      "views": 2000,
      "clicks": 800
    }
  ],
  "aggregated": {
    "totalLinks": 25,
    "totalViews": 3000,
    "totalClicks": 1300
  }
}
```

---

## Frontend Coordination Requirements

### New UI Components Needed

1. **Sub-Account Management Dashboard**
   - List all sub-accounts
   - Create/edit/delete sub-accounts
   - Quick actions (view public profile, manage links)
   - Usage statistics per sub-account

2. **Context Switcher**
   - Dropdown/sidebar to switch between parent and sub-accounts
   - Clear visual indicator of current context
   - Quick context switching without page reload

3. **Tier Upgrade Prompts**
   - Show when user hits sub-account limit
   - Explain which tier is needed
   - Call-to-action for upgrade

4. **Sub-Account Creation Wizard**
   - Step-by-step creation flow
   - Username availability check
   - Profile information (display name, bio, avatar)
   - Type/category selection

5. **Restricted Feature UI**
   - When in sub-account context, hide/disable:
     - API Keys section
     - 2FA settings
     - Subscription management
     - Password change
     - User management
   - Show info banner: "Some settings are managed by parent account"

### URL Structure Options

**Option 1 - Query Parameter**
```
/dashboard?context=user-abc123
/links?context=user-abc123
```

**Option 2 - Path Segment**
```
/manage/user-abc123/dashboard
/manage/user-abc123/links
```

**Option 3 - Subdomain (Future)**
```
https://client-brand1.linktome.com/dashboard
```

**Recommendation**: Option 1 for MVP (simplest), plan for Option 2 long-term (cleaner URLs).

### State Management

Frontend needs to manage:
- Current context (parent or which sub-account)
- Available sub-accounts list
- Context-specific permissions
- Context-specific JWT token

Suggested state structure:
```typescript
interface AccountContext {
  parentAccount: {
    userId: string;
    username: string;
    tier: string;
  };
  currentContext: {
    userId: string;
    username: string;
    isSubAccount: boolean;
    permissions: string[];
  };
  availableSubAccounts: SubAccount[];
  contextToken: string;
}
```

---

## Implementation Roadmap

### Phase 1: Database & Core Logic (Backend)
**Estimated: 1-2 weeks**

1. ✅ Create planning document (this document)
2. Add `SubAccounts` table to schema
3. Add sub-account fields to `Users` table
4. Update `Get-UserSubscription.ps1` for tier inheritance
5. Update `Get-TierFeatures.ps1` with sub-account limits
6. Create `Get-SubAccountOwner.ps1` helper function
7. Create `Test-SubAccountOwnership.ps1` validation function
8. Update authentication middleware to support context switching

### Phase 2: Sub-Account CRUD Endpoints (Backend)
**Estimated: 1 week**

1. Implement `POST /admin/createSubAccount`
2. Implement `GET /admin/getSubAccounts`
3. Implement `PUT /admin/updateSubAccount`
4. Implement `DELETE /admin/deleteSubAccount`
5. Add tier limit validation
6. Add ownership validation
7. Add audit logging for sub-account operations
8. Write comprehensive tests

### Phase 3: Context Switching (Backend)
**Estimated: 1 week**

1. Implement `POST /admin/switchContext`
2. Update JWT generation to include context
3. Update all admin endpoints to respect `contextUserId`
4. Add permission restrictions in sub-account context
5. Block login for sub-accounts at `/public/login`
6. Update `Get-UserAuthContext.ps1` for context support
7. Write integration tests for context switching

### Phase 4: Frontend - Basic UI (Frontend)
**Estimated: 2 weeks**

1. Create sub-account management page
2. Create sub-account list component
3. Create sub-account creation form
4. Implement context switcher UI
5. Update navigation to show current context
6. Update all API calls to include context token
7. Add tier upgrade prompts for sub-account limits

### Phase 5: Frontend - Context-Aware UI (Frontend)
**Estimated: 1 week**

1. Hide/disable restricted features in sub-account context
2. Add info banners for context-specific restrictions
3. Update dashboard to show parent + sub-account stats
4. Add sub-account analytics views
5. Implement context persistence (localStorage)
6. Add context switching confirmation dialog

### Phase 6: Testing & Polish
**Estimated: 1 week**

1. End-to-end testing of full flows
2. Permission testing in all contexts
3. Tier limit enforcement testing
4. Analytics separation testing
5. Performance testing with many sub-accounts
6. UI/UX refinements
7. Documentation updates

### Phase 7: Documentation & Launch
**Estimated: 3-5 days**

1. Update API documentation
2. Create user guide for agencies
3. Create video tutorials
4. Update pricing page to highlight sub-accounts
5. Prepare changelog
6. Internal beta testing
7. Gradual rollout plan

---

## Security Considerations

### Critical Security Requirements

1. **Authentication Isolation**
   - Sub-accounts MUST NOT be able to login
   - Validate `IsSubAccount = false` on all login attempts
   - No password/credentials for sub-accounts

2. **Ownership Validation**
   - ALWAYS verify parent owns sub-account before any operation
   - Use `Test-SubAccountOwnership` in all endpoints
   - Check recursively if needed (for future nested accounts)

3. **Permission Enforcement**
   - Block restricted operations (API keys, 2FA, subscription) in context
   - Validate permissions on every request
   - Don't rely on frontend to hide features

4. **Context Validation**
   - Verify `contextUserId` exists and is owned by parent
   - Prevent context switching to other users' sub-accounts
   - Validate context JWT signature and expiration

5. **Data Isolation**
   - Sub-accounts cannot see other sub-accounts' data
   - Parent can see all sub-account data
   - Analytics must be properly scoped

6. **Rate Limiting**
   - Apply parent account rate limits
   - Track across all sub-accounts combined
   - Prevent abuse via sub-account creation

7. **Audit Trail**
   - Log all sub-account creation/deletion
   - Log all context switches
   - Log operations performed in sub-account context
   - Include both parent and context user IDs in logs

### Potential Security Risks

| Risk | Mitigation |
|------|-----------|
| Context hijacking | Validate JWT signature, check ownership |
| Permission escalation | Enforce context-aware permissions |
| Data leakage | Verify ownership on every query |
| Account enumeration | Rate limit creation, validate ownership |
| Sub-account limit bypass | Enforce tier limits server-side |
| Subscription abuse | Individual limits OR aggregate enforcement |

---

## Edge Cases & Considerations

### Parent Account Deletion
**Question**: What happens to sub-accounts when parent is deleted?

**Options**:
1. Cascade delete all sub-accounts (data loss)
2. Require deletion of sub-accounts first
3. Convert sub-accounts to standalone (complex)

**Recommendation**: Option 2 - Require explicit sub-account deletion first.

### Parent Subscription Downgrade
**Question**: What happens when parent downgrades to Free tier?

**Scenario**: Parent on Premium with 5 sub-accounts downgrades to Free.

**Options**:
1. Suspend all sub-accounts immediately
2. Grace period (30 days) to upgrade or delete
3. Keep active until next billing cycle

**Recommendation**: Option 3 - Keep active until `AccessUntil` date, then suspend. Send email notifications.

### Sub-Account Suspension
When parent's subscription expires or downgrades:
- Sub-accounts remain in database
- Mark as `Status = 'suspended'`
- Public profiles return 404 or "Account suspended"
- Parent sees suspension notice in dashboard
- Can be reactivated when parent upgrades

### Sub-Account Username Changes
**Question**: Can usernames be changed?

**Considerations**:
- Usernames are used in public URLs
- Changing breaks existing links/bookmarks
- Could be used for impersonation

**Recommendation**: Allow username changes with:
- Cooldown period (e.g., 30 days between changes)
- Redirect from old username for 90 days
- Log all username changes for audit

### Email Address Conflicts
**Question**: Can sub-accounts share email with parent or other sub-accounts?

**Recommendation**: 
- Email is required but doesn't need to be unique within parent's sub-accounts
- Email cannot be used for login (since sub-accounts can't login)
- Use format: `parent-email+subaccount@domain.com` for separation
- Validate email format but allow duplicates within parent's scope

### Analytics Retention
When parent downgrades tier:
- Keep analytics beyond retention period?
- Delete excess data?

**Recommendation**: Match parent's tier retention limits. Notify before deletion.

---

## Testing Strategy

### Unit Tests

1. **Subscription Inheritance**
   - Test tier inheritance from parent
   - Test with expired parent subscription
   - Test with suspended parent account

2. **Ownership Validation**
   - Test valid ownership checks
   - Test attempt to access other user's sub-account
   - Test attempt to nest sub-accounts (should fail)

3. **Permission Enforcement**
   - Test restricted operations in context
   - Test allowed operations in context
   - Test operations on parent account

4. **Tier Limits**
   - Test sub-account creation up to limit
   - Test rejection beyond limit
   - Test limit changes on tier upgrade/downgrade

### Integration Tests

1. **Full Creation Flow**
   - Parent creates sub-account
   - Switch context
   - Create pages and links
   - View public profile
   - Switch back to parent

2. **Multi-Context Operations**
   - Parent manages multiple sub-accounts
   - Switch between contexts
   - Verify data isolation
   - Verify analytics separation

3. **Subscription Changes**
   - Test tier upgrade with sub-accounts
   - Test tier downgrade with sub-accounts
   - Test subscription expiration
   - Test reactivation

### End-to-End Tests

1. **Agency User Journey**
   - Sign up and upgrade to Pro
   - Create 3 sub-accounts for clients
   - Configure each sub-account
   - View aggregated dashboard
   - Attempt to exceed limits
   - Downgrade and verify suspensions

2. **Security Testing**
   - Attempt sub-account login
   - Attempt context switching to unowned account
   - Attempt restricted operations in context
   - Verify JWT validation

---

## Open Questions for Discussion

### Product Questions

1. **Naming Convention**: What should we call these?
   - Sub-accounts vs. Child accounts vs. Brand profiles vs. Client profiles?
   - "Agency Mode" vs. "Multi-Account" vs. "Team Management"?

2. **Feature Usage Limits**: Should we use Option A, B, or C (see above)?

3. **Email Delivery**: Where should notification emails go?
   - Parent's email for all sub-accounts?
   - Individual sub-account emails (if they can't login)?
   - Both?

4. **Public Profile Branding**: Should sub-accounts show:
   - "Managed by [Parent]" badge?
   - No indication at all?
   - Optional "Powered by" link?

5. **Future Nesting**: Should we plan for sub-accounts of sub-accounts?
   - Agency → Client → Brand?
   - Probably overkill for MVP

### Technical Questions

1. **Context Token Storage**: 
   - Use query params vs. separate endpoint pattern?
   - Store in localStorage or sessionStorage?
   - How to handle token refresh?

2. **Database Design**:
   - Modify `Users` table vs. new `SubAccounts` table?
   - How to efficiently query all parent's sub-accounts?

3. **API Key Inheritance**:
   - Can parent's API keys be used in sub-account context?
   - Or must parent use JWT and switch context?

4. **Bulk Operations**:
   - Should we support bulk sub-account creation?
   - Bulk analytics export across sub-accounts?

5. **Migration Path**:
   - Can existing accounts be converted to sub-accounts?
   - What about their existing links/pages/analytics?

### Pricing Questions

1. **Premium Feature**: Which tiers should have sub-accounts?
   - Current recommendation: Pro (3), Premium (10), Enterprise (unlimited)
   - Should Free have 1 sub-account to try the feature?

2. **Add-on Option**: Should this be an add-on instead?
   - Base tier + $X per sub-account?
   - Separate "Agency" tier?

3. **Competitive Analysis**: What do competitors offer?
   - Linktree: No sub-accounts
   - Beacons: Team features in higher tiers
   - Bento: Individual accounts only

---

## Success Metrics

### Adoption Metrics
- Number of users creating sub-accounts
- Average sub-accounts per parent user
- Tier upgrades attributable to sub-account feature
- Retention rate of users with sub-accounts

### Usage Metrics
- Context switches per session
- Operations performed in sub-account context
- Sub-account public profile views
- Analytics views for sub-accounts

### Business Metrics
- Revenue from Pro+ tier attributed to sub-accounts
- Conversion rate from Free → Pro for sub-account feature
- Customer satisfaction scores for agency users
- Support ticket volume for sub-account issues

---

## Documentation Deliverables

### User Documentation
1. **Agency User Guide**
   - What are sub-accounts?
   - How to create and manage
   - Best practices
   - Limitations and restrictions

2. **FAQ**
   - Can sub-accounts login?
   - What happens when I downgrade?
   - How are limits enforced?
   - Can I convert existing accounts?

### Developer Documentation
1. **API Reference**
   - All new endpoints
   - Context switching flow
   - JWT structure
   - Error codes

2. **Implementation Guide**
   - Architecture overview
   - Database schema
   - Permission system
   - Security considerations

3. **Migration Guide**
   - Database migrations needed
   - Configuration changes
   - Deployment steps

---

## Next Steps

1. **Review this document** with team and stakeholders
2. **Decide on open questions** (naming, limits, pricing)
3. **Get frontend team input** on UI/UX proposals
4. **Finalize database schema** approach
5. **Create detailed technical specifications** for each endpoint
6. **Break down into tickets** for sprint planning
7. **Assign to development team**
8. **Begin Phase 1 implementation**

---

## Appendix: Alternative Architectures Considered

### Alternative 1: Separate Accounts with Billing Group
- Each account logs in independently
- Billing consolidated under parent
- **Rejected**: Too complex, security concerns with payment delegation

### Alternative 2: Workspace Model
- All users in workspace share single login
- Role-based access within workspace
- **Rejected**: Doesn't provide public profile separation

### Alternative 3: Multi-Tenancy
- Complete database/application separation per account
- **Rejected**: Over-engineered for use case, high maintenance cost

### Alternative 4: Profile Switching (Current Approach)
- Single login, multiple profiles under one account
- Context switching for management
- **Selected**: Right balance of simplicity and features

---

**Document Version**: 1.0  
**Date**: January 11, 2026  
**Status**: Draft - Awaiting Review  
**Next Review**: TBD after team discussion
