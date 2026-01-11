# Frontend Coordination: Agency/Multi-Account Profiles

## Overview for Frontend Team

This document outlines the frontend changes needed to support the agency/multi-account profiles feature. Please read this in conjunction with the main planning document (`AGENCY_MULTI_ACCOUNT_PLANNING.md`).

---

## Core Concept Summary

**For Users**: Agency or power users can create multiple "sub-accounts" (think brand profiles, client profiles) that:
- Share the parent account's subscription/billing
- Have their own public presence (username, pages, links)
- **Cannot** login independently
- **Cannot** manage sensitive settings (API keys, 2FA, subscription)
- Are managed entirely by the parent account through context switching

**For Frontend**: You'll need to build:
1. Sub-account management interface
2. Context switcher to manage different sub-accounts
3. Context-aware UI that shows/hides features based on current context
4. Clear visual indicators of which account is being managed

---

## New API Endpoints

### 1. Create Sub-Account
```typescript
POST /api/admin/createSubAccount
Authorization: Bearer {parentJWT}

Request:
{
  username: string;        // Unique across system, 3-30 chars
  email: string;           // Can be shared within parent's sub-accounts
  displayName: string;     // Display name for the sub-account
  bio?: string;            // Optional bio
  type: 'agency_client' | 'brand' | 'project' | 'other';
}

Response:
{
  message: string;
  subAccount: {
    userId: string;
    username: string;
    email: string;
    displayName: string;
    type: string;
    createdAt: string;
  }
}

Errors:
- 400: Validation error (username taken, invalid format)
- 403: Tier limit reached (e.g., "You need Pro tier to create sub-accounts")
- 500: Server error
```

### 2. List Sub-Accounts
```typescript
GET /api/admin/getSubAccounts
Authorization: Bearer {parentJWT}

Response:
{
  subAccounts: Array<{
    userId: string;
    username: string;
    displayName: string;
    email: string;
    type: string;
    status: 'active' | 'suspended';
    createdAt: string;
    pagesCount: number;
    linksCount: number;
  }>;
  total: number;
  limit: number;  // Based on tier
}
```

### 3. Update Sub-Account
```typescript
PUT /api/admin/updateSubAccount
Authorization: Bearer {parentJWT}

Request:
{
  userId: string;          // Required
  displayName?: string;
  bio?: string;
  avatar?: string;
  type?: string;
}

Response:
{
  message: "Sub-account updated successfully"
}
```

### 4. Delete Sub-Account
```typescript
DELETE /api/admin/deleteSubAccount?userId={userId}
Authorization: Bearer {parentJWT}

Response:
{
  message: "Sub-account deleted successfully"
}

Note: This deletes ALL data (pages, links, analytics) for the sub-account.
Consider adding a confirmation dialog.
```

### 5. Switch Context (IMPORTANT)
```typescript
POST /api/admin/switchContext
Authorization: Bearer {parentJWT}

Request:
{
  userId: string;  // Sub-account userId to switch to
}

Response:
{
  accessToken: string;  // New JWT with context
  context: {
    parentUserId: string;
    contextUserId: string;
    contextUsername: string;
    isSubAccountContext: boolean;
  }
}

This returns a NEW JWT token that includes context information.
Store this token and use it for all subsequent API calls.
```

### 6. Return to Parent Context
```typescript
POST /api/admin/switchContext
Authorization: Bearer {contextJWT}

Request:
{
  userId: null  // or omit field, or pass parent's userId
}

Response:
{
  accessToken: string;  // Parent's standard JWT
  context: {
    parentUserId: string;
    contextUserId: string;  // Same as parentUserId
    contextUsername: string;
    isSubAccountContext: false;
  }
}
```

---

## JWT Token Structure

### Standard Token (Parent Context)
```json
{
  "userId": "user-parent123",
  "email": "parent@example.com",
  "username": "parentuser",
  "tier": "premium",
  "exp": 1234567890
}
```

### Context Token (Sub-Account Context)
```json
{
  "userId": "user-parent123",           // Still the parent (for auth)
  "contextUserId": "user-subaccount123",  // Sub-account (for operations)
  "email": "parent@example.com",
  "username": "parentuser",
  "contextUsername": "clientbrand",
  "tier": "premium",                     // Parent's tier
  "isSubAccountContext": true,
  "exp": 1234567890
}
```

**Important**: 
- Always use the most recent JWT from switchContext
- When in sub-account context, ALL operations affect the sub-account
- Parent's tier is used for feature gating

---

## State Management

### Recommended State Structure

```typescript
interface SubAccount {
  userId: string;
  username: string;
  displayName: string;
  email: string;
  type: 'agency_client' | 'brand' | 'project' | 'other';
  status: 'active' | 'suspended';
  createdAt: string;
  pagesCount?: number;
  linksCount?: number;
}

interface AccountContext {
  // Parent account info
  parentAccount: {
    userId: string;
    username: string;
    email: string;
    tier: 'free' | 'pro' | 'premium' | 'enterprise';
  };
  
  // Current context
  currentContext: {
    userId: string;              // Could be parent or sub-account
    username: string;
    isSubAccount: boolean;
    parentUserId?: string;       // Only if isSubAccount
  };
  
  // Available sub-accounts
  subAccounts: SubAccount[];
  
  // Tier limits
  subAccountLimit: number;       // Based on parent's tier
  canCreateMore: boolean;        // subAccounts.length < subAccountLimit
  
  // Auth token
  accessToken: string;           // Current JWT (updated on context switch)
}
```

### State Management Flow

1. **Initial Load** (after login)
   ```typescript
   const parentJWT = loginResponse.accessToken;
   
   // Fetch sub-accounts
   const subAccounts = await getSubAccounts(parentJWT);
   
   // Initialize state
   setState({
     parentAccount: { userId, username, email, tier },
     currentContext: { userId, username, isSubAccount: false },
     subAccounts: subAccounts.subAccounts,
     subAccountLimit: subAccounts.limit,
     canCreateMore: subAccounts.total < subAccounts.limit,
     accessToken: parentJWT
   });
   ```

2. **Switch to Sub-Account**
   ```typescript
   const contextResponse = await switchContext(userId, currentToken);
   
   setState({
     currentContext: {
       userId: contextResponse.context.contextUserId,
       username: contextResponse.context.contextUsername,
       isSubAccount: true,
       parentUserId: contextResponse.context.parentUserId
     },
     accessToken: contextResponse.accessToken  // NEW TOKEN!
   });
   
   // Redirect to dashboard or refresh current page
   ```

3. **Return to Parent**
   ```typescript
   const parentResponse = await switchContext(null, currentToken);
   
   setState({
     currentContext: {
       userId: parentAccount.userId,
       username: parentAccount.username,
       isSubAccount: false
     },
     accessToken: parentResponse.accessToken
   });
   ```

### Persistence

Store context in `localStorage` or `sessionStorage`:

```typescript
// On context switch
localStorage.setItem('accountContext', JSON.stringify({
  currentUserId: context.userId,
  isSubAccount: context.isSubAccount,
  accessToken: newToken
}));

// On page load
const savedContext = localStorage.getItem('accountContext');
if (savedContext) {
  const { currentUserId, isSubAccount, accessToken } = JSON.parse(savedContext);
  // Validate token is still valid
  // Restore context
}
```

---

## UI Components Needed

### 1. Sub-Account Management Page

**Location**: `/dashboard/sub-accounts` or similar

**Components**:

#### Sub-Account List
```typescript
<SubAccountList>
  {subAccounts.map(account => (
    <SubAccountCard
      key={account.userId}
      account={account}
      onManage={() => switchToSubAccount(account.userId)}
      onEdit={() => openEditModal(account)}
      onDelete={() => confirmDelete(account)}
      onViewPublic={() => window.open(`/profile/${account.username}`)}
    />
  ))}
  
  {canCreateMore && (
    <CreateSubAccountButton onClick={openCreateModal} />
  )}
  
  {!canCreateMore && (
    <UpgradePrompt
      currentTier={tier}
      message="Upgrade to create more sub-accounts"
      limit={subAccountLimit}
    />
  )}
</SubAccountList>
```

#### Sub-Account Card Design
```
┌─────────────────────────────────────────┐
│ 👤 Client Brand One                     │
│ @clientbrand1                           │
│ Type: Agency Client | Status: Active    │
│                                         │
│ 📊 2 Pages | 15 Links | 1.2K Views     │
│                                         │
│ [Manage] [Edit] [View Profile] [...]   │
└─────────────────────────────────────────┘
```

#### Create Sub-Account Modal
```typescript
<CreateSubAccountModal>
  <Form onSubmit={handleCreate}>
    <Input
      label="Username"
      name="username"
      placeholder="clientbrand1"
      validation={usernameValidation}
      asyncValidation={checkUsernameAvailable}
    />
    
    <Input
      label="Display Name"
      name="displayName"
      placeholder="Client Brand One"
    />
    
    <Input
      label="Email"
      name="email"
      type="email"
      placeholder="brand@client.com"
      helpText="Used for notifications (not for login)"
    />
    
    <Textarea
      label="Bio (Optional)"
      name="bio"
      placeholder="Brief description..."
    />
    
    <Select
      label="Type"
      name="type"
      options={[
        { value: 'agency_client', label: 'Agency Client' },
        { value: 'brand', label: 'Brand Profile' },
        { value: 'project', label: 'Project' },
        { value: 'other', label: 'Other' }
      ]}
    />
    
    <Button type="submit">Create Sub-Account</Button>
  </Form>
</CreateSubAccountModal>
```

### 2. Context Switcher

**Location**: Top navigation bar, always visible

**Design Options**:

#### Option A: Dropdown Menu
```
┌──────────────────────────────┐
│ 🏢 Parent Account ▼          │
├──────────────────────────────┤
│ ✓ Parent Account (You)       │
│   └─ All features enabled    │
├──────────────────────────────┤
│   Client Brand One           │
│   └─ @clientbrand1           │
│                              │
│   Client Brand Two           │
│   └─ @clientbrand2           │
├──────────────────────────────┤
│ + Manage Sub-Accounts        │
└──────────────────────────────┘
```

#### Option B: Tab-like Switcher
```
┌──────────────────────────────────────────┐
│ [Parent] [Client1] [Client2] [+]         │
└──────────────────────────────────────────┘
```

**Recommendation**: Option A (dropdown) for better scalability.

**Implementation**:
```typescript
<ContextSwitcher
  currentContext={currentContext}
  parentAccount={parentAccount}
  subAccounts={subAccounts}
  onSwitch={(userId) => {
    if (userId === parentAccount.userId) {
      returnToParent();
    } else {
      switchToSubAccount(userId);
    }
  }}
  onManage={() => navigate('/dashboard/sub-accounts')}
/>
```

### 3. Context Indicator Banner

When in sub-account context, show a clear banner:

```
┌────────────────────────────────────────────────────────────┐
│ ℹ️ You are managing: Client Brand One (@clientbrand1)      │
│ [Return to Parent Account]                                 │
└────────────────────────────────────────────────────────────┘
```

**Styling**: Subtle background color, not intrusive but always visible.

### 4. Restricted Features UI

When in sub-account context, certain sections should be:
- Hidden entirely, OR
- Shown with disabled state + tooltip

**Affected Sections**:
- Settings → API Keys (hide or disable)
- Settings → Two-Factor Authentication (hide or disable)
- Settings → Subscription (hide or disable)
- Settings → Password Change (hide or disable)
- Settings → Email/Phone Change (hide or disable)
- Settings → User Management (hide or disable)

**Example**:
```typescript
{!isSubAccountContext ? (
  <ApiKeysSection />
) : (
  <RestrictedFeatureNotice
    feature="API Keys"
    message="API keys are managed by your parent account"
  />
)}
```

### 5. Aggregated Dashboard (Parent View)

When viewing parent dashboard, show combined stats:

```typescript
<DashboardStats>
  <StatCard
    title="Your Account"
    links={parentStats.links}
    views={parentStats.views}
    clicks={parentStats.clicks}
  />
  
  {subAccounts.length > 0 && (
    <>
      <StatCard
        title="All Sub-Accounts"
        links={aggregatedStats.totalLinks}
        views={aggregatedStats.totalViews}
        clicks={aggregatedStats.totalClicks}
      />
      
      <SubAccountBreakdown>
        {subAccounts.map(account => (
          <SubAccountStat
            key={account.userId}
            account={account}
            stats={getStatsForSubAccount(account.userId)}
            onViewDetails={() => switchAndNavigate(account.userId, '/analytics')}
          />
        ))}
      </SubAccountBreakdown>
    </>
  )}
</DashboardStats>
```

---

## URL Routing Strategy

### Option 1: Query Parameter (Recommended for MVP)
```
/dashboard?context=user-abc123
/links?context=user-abc123
/pages?context=user-abc123
/analytics?context=user-abc123
```

**Pros**: Simple, works with existing routing
**Cons**: Clutters URLs

### Option 2: Path Segment
```
/manage/user-abc123/dashboard
/manage/user-abc123/links
/manage/user-abc123/pages
```

**Pros**: Clean URLs, clear separation
**Cons**: Requires routing changes

### Option 3: Separate Section
```
/sub-accounts/user-abc123
/sub-accounts/user-abc123/links
/sub-accounts/user-abc123/pages
```

**Pros**: Very clear, easy to secure
**Cons**: More routing to maintain

**Recommendation**: Start with Option 1 (query param), migrate to Option 2 later.

---

## Example Flows

### Flow 1: Create First Sub-Account

1. User upgrades to Pro tier
2. Navigate to Dashboard
3. See banner: "New! Create sub-accounts for your clients or brands"
4. Click "Manage Sub-Accounts"
5. See empty state with "Create Your First Sub-Account" button
6. Click button → Modal opens
7. Fill in form (username, display name, email, type)
8. Submit → API call → Success message
9. Redirected to sub-account management page
10. See new sub-account in list
11. Click "Manage" → Context switches
12. Redirect to dashboard with sub-account context
13. See context banner at top
14. Create pages, add links for sub-account

### Flow 2: Switch Between Multiple Sub-Accounts

1. User is on parent dashboard
2. Click context switcher dropdown
3. See list of parent + all sub-accounts
4. Select "Client Brand One"
5. API call to switch context → New JWT received
6. Page refreshes (or soft reload)
7. Context banner shows "Managing: Client Brand One"
8. Navigation remains same, but context is different
9. Edit links for Client Brand One
10. Click context switcher again
11. Select "Client Brand Two"
12. Repeat context switch
13. Now managing Client Brand Two

### Flow 3: Attempt Restricted Action

1. User is managing sub-account (in context)
2. Navigate to Settings → API Keys
3. See message: "API keys are managed by your parent account"
4. Button is disabled or section is hidden
5. Tooltip/info icon explains: "Switch to parent account to manage API keys"
6. User clicks "Return to Parent Account"
7. Context switches back
8. Now can access API keys section

---

## Error Handling

### Common Errors

```typescript
// Sub-account creation errors
{
  error: "Username already taken",
  code: "USERNAME_TAKEN",
  field: "username"
}

{
  error: "Sub-account limit reached. Upgrade to Premium for more.",
  code: "LIMIT_REACHED",
  upgradeRequired: true,
  currentTier: "pro",
  currentCount: 3,
  limit: 3
}

{
  error: "Invalid username format. Use 3-30 lowercase letters, numbers, hyphens.",
  code: "INVALID_USERNAME",
  field: "username"
}

// Context switching errors
{
  error: "Sub-account not found or you don't have permission",
  code: "FORBIDDEN"
}

{
  error: "Your subscription has expired. Renew to manage sub-accounts.",
  code: "SUBSCRIPTION_EXPIRED",
  upgradeRequired: true
}
```

### Error Display

```typescript
<ErrorBoundary>
  {error.upgradeRequired && (
    <UpgradePrompt
      message={error.error}
      currentTier={error.currentTier}
      targetTier={getRequiredTier(error)}
    />
  )}
  
  {error.code === 'LIMIT_REACHED' && (
    <LimitReachedDialog
      message={error.error}
      currentCount={error.currentCount}
      limit={error.limit}
      onUpgrade={handleUpgrade}
    />
  )}
  
  {/* Generic error */}
  {!error.upgradeRequired && (
    <ErrorAlert message={error.error} />
  )}
</ErrorBoundary>
```

---

## API Integration Examples

### React/TypeScript Example

```typescript
// api/subAccounts.ts
import { apiClient } from './client';

export interface SubAccount {
  userId: string;
  username: string;
  displayName: string;
  email: string;
  type: 'agency_client' | 'brand' | 'project' | 'other';
  status: 'active' | 'suspended';
  createdAt: string;
  pagesCount?: number;
  linksCount?: number;
}

export interface CreateSubAccountRequest {
  username: string;
  email: string;
  displayName: string;
  bio?: string;
  type: 'agency_client' | 'brand' | 'project' | 'other';
}

export const subAccountsAPI = {
  async list(token: string): Promise<{ subAccounts: SubAccount[]; total: number; limit: number }> {
    return apiClient.get('/admin/getSubAccounts', {
      headers: { Authorization: `Bearer ${token}` }
    });
  },

  async create(data: CreateSubAccountRequest, token: string): Promise<{ subAccount: SubAccount }> {
    return apiClient.post('/admin/createSubAccount', data, {
      headers: { Authorization: `Bearer ${token}` }
    });
  },

  async update(userId: string, data: Partial<SubAccount>, token: string): Promise<void> {
    return apiClient.put('/admin/updateSubAccount', { userId, ...data }, {
      headers: { Authorization: `Bearer ${token}` }
    });
  },

  async delete(userId: string, token: string): Promise<void> {
    return apiClient.delete(`/admin/deleteSubAccount?userId=${userId}`, {
      headers: { Authorization: `Bearer ${token}` }
    });
  },

  async switchContext(userId: string | null, token: string): Promise<{
    accessToken: string;
    context: {
      parentUserId: string;
      contextUserId: string;
      contextUsername: string;
      isSubAccountContext: boolean;
    }
  }> {
    return apiClient.post('/admin/switchContext', { userId }, {
      headers: { Authorization: `Bearer ${token}` }
    });
  }
};

// hooks/useAccountContext.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface AccountContextState {
  parentAccount: {
    userId: string;
    username: string;
    tier: string;
  } | null;
  
  currentContext: {
    userId: string;
    username: string;
    isSubAccount: boolean;
  } | null;
  
  subAccounts: SubAccount[];
  accessToken: string | null;
  
  setParentAccount: (account: any) => void;
  setCurrentContext: (context: any) => void;
  setSubAccounts: (accounts: SubAccount[]) => void;
  setAccessToken: (token: string) => void;
  switchToSubAccount: (userId: string) => Promise<void>;
  returnToParent: () => Promise<void>;
  reset: () => void;
}

export const useAccountContext = create<AccountContextState>()(
  persist(
    (set, get) => ({
      parentAccount: null,
      currentContext: null,
      subAccounts: [],
      accessToken: null,
      
      setParentAccount: (account) => set({ parentAccount: account }),
      setCurrentContext: (context) => set({ currentContext: context }),
      setSubAccounts: (accounts) => set({ subAccounts: accounts }),
      setAccessToken: (token) => set({ accessToken: token }),
      
      async switchToSubAccount(userId: string) {
        const { accessToken } = get();
        if (!accessToken) return;
        
        const response = await subAccountsAPI.switchContext(userId, accessToken);
        set({
          currentContext: {
            userId: response.context.contextUserId,
            username: response.context.contextUsername,
            isSubAccount: true
          },
          accessToken: response.accessToken
        });
      },
      
      async returnToParent() {
        const { accessToken, parentAccount } = get();
        if (!accessToken || !parentAccount) return;
        
        const response = await subAccountsAPI.switchContext(null, accessToken);
        set({
          currentContext: {
            userId: parentAccount.userId,
            username: parentAccount.username,
            isSubAccount: false
          },
          accessToken: response.accessToken
        });
      },
      
      reset: () => set({
        parentAccount: null,
        currentContext: null,
        subAccounts: [],
        accessToken: null
      })
    }),
    {
      name: 'account-context',
      partialize: (state) => ({
        currentContext: state.currentContext,
        accessToken: state.accessToken
      })
    }
  )
);

// components/ContextSwitcher.tsx
export function ContextSwitcher() {
  const {
    parentAccount,
    currentContext,
    subAccounts,
    switchToSubAccount,
    returnToParent
  } = useAccountContext();
  
  const [isOpen, setIsOpen] = useState(false);
  
  const handleSwitch = async (userId: string) => {
    if (userId === parentAccount?.userId) {
      await returnToParent();
    } else {
      await switchToSubAccount(userId);
    }
    setIsOpen(false);
    window.location.reload(); // Or use router to refresh data
  };
  
  return (
    <DropdownMenu open={isOpen} onOpenChange={setIsOpen}>
      <DropdownMenuTrigger>
        <Button variant="outline">
          {currentContext?.isSubAccount ? '🏢' : '👤'} {currentContext?.username}
          <ChevronDown className="ml-2" />
        </Button>
      </DropdownMenuTrigger>
      
      <DropdownMenuContent>
        <DropdownMenuItem
          onClick={() => handleSwitch(parentAccount!.userId)}
          className={!currentContext?.isSubAccount ? 'bg-accent' : ''}
        >
          <Check className={!currentContext?.isSubAccount ? 'mr-2' : 'mr-2 invisible'} />
          {parentAccount?.username} (You)
        </DropdownMenuItem>
        
        <DropdownMenuSeparator />
        
        {subAccounts.map(account => (
          <DropdownMenuItem
            key={account.userId}
            onClick={() => handleSwitch(account.userId)}
            className={currentContext?.userId === account.userId ? 'bg-accent' : ''}
          >
            <Check className={currentContext?.userId === account.userId ? 'mr-2' : 'mr-2 invisible'} />
            {account.username}
          </DropdownMenuItem>
        ))}
        
        <DropdownMenuSeparator />
        
        <DropdownMenuItem onClick={() => navigate('/dashboard/sub-accounts')}>
          <Plus className="mr-2" />
          Manage Sub-Accounts
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

---

## Testing Checklist

### Manual Testing

- [ ] Create sub-account with valid data
- [ ] Create sub-account with duplicate username (should fail)
- [ ] Create sub-account beyond tier limit (should fail)
- [ ] Switch to sub-account context
- [ ] Verify context banner appears
- [ ] Verify restricted features are hidden/disabled
- [ ] Create pages/links in sub-account context
- [ ] View sub-account public profile
- [ ] Return to parent context
- [ ] Verify context banner disappears
- [ ] Verify all features are accessible again
- [ ] Edit sub-account details
- [ ] Delete sub-account (with confirmation)
- [ ] Test with multiple sub-accounts
- [ ] Test context switching between multiple sub-accounts
- [ ] Test tier downgrade behavior
- [ ] Test subscription expiration behavior

### Edge Cases

- [ ] Switch context with expired JWT
- [ ] Switch context to non-existent sub-account
- [ ] Switch context to another user's sub-account (should fail)
- [ ] Create sub-account on Free tier (should fail)
- [ ] Access restricted feature directly via URL in sub-account context
- [ ] Token refresh while in sub-account context
- [ ] Browser refresh while in sub-account context (should persist)
- [ ] Logout while in sub-account context
- [ ] Parent account deletion (should require sub-account deletion first)

---

## Performance Considerations

### Optimization Tips

1. **Lazy Load Sub-Account List**
   - Only fetch when needed (e.g., when dropdown opens)
   - Cache for duration of session

2. **Minimize Context Switches**
   - Batch operations if possible
   - Don't auto-switch on every navigation

3. **Optimize Dashboard Queries**
   - Fetch aggregated stats in single API call
   - Consider pagination for large sub-account lists

4. **Cache Context State**
   - Use localStorage/sessionStorage
   - Validate on load (check token expiration)

5. **Debounce Username Validation**
   - Don't check availability on every keystroke
   - Wait 500ms after user stops typing

---

## Accessibility

### Requirements

1. **Keyboard Navigation**
   - Context switcher fully keyboard accessible
   - Tab through all controls
   - Enter to select

2. **Screen Reader Support**
   - Announce context changes
   - Label all controls clearly
   - Provide context in restricted features

3. **Visual Indicators**
   - High contrast for context banner
   - Clear disabled states
   - Focus indicators on all interactive elements

4. **ARIA Labels**
   ```html
   <button
     aria-label="Switch account context"
     aria-expanded={isOpen}
     aria-haspopup="menu"
   >
     Context Switcher
   </button>
   
   <div
     role="alert"
     aria-live="polite"
     aria-atomic="true"
   >
     Now managing: {currentContext.username}
   </div>
   ```

---

## Questions for Backend Team

### Before Starting Frontend Work

1. **Context Token Expiration**: 
   - Same as regular JWT (24 hours)?
   - Need token refresh endpoint?

2. **Username Validation Endpoint**:
   - Is there an endpoint to check username availability before creation?
   - Or only validation on create?

3. **Batch Operations**:
   - Can we delete multiple sub-accounts at once?
   - Can we fetch stats for multiple sub-accounts in one call?

4. **Analytics API**:
   - Does `/admin/getAnalytics` need a query param for sub-account?
   - Or does it use context from JWT?

5. **Public Profile**:
   - Any indication that a profile is a sub-account?
   - Or completely transparent to public viewers?

6. **Email Notifications**:
   - Where do sub-account notifications go?
   - Parent email or sub-account email?

7. **Migration**:
   - Can existing accounts be converted to sub-accounts?
   - Need a migration flow?

---

## Timeline Estimate

Based on complexity and dependencies:

| Phase | Tasks | Estimate |
|-------|-------|----------|
| **Phase 1** | API integration, state management | 3-4 days |
| **Phase 2** | Sub-account management UI | 4-5 days |
| **Phase 3** | Context switcher component | 2-3 days |
| **Phase 4** | Context-aware UI updates | 3-4 days |
| **Phase 5** | Dashboard aggregation | 2-3 days |
| **Phase 6** | Testing, polish, docs | 3-4 days |
| **Total** | | **17-23 days** (~3.5-4.5 weeks) |

This assumes:
- One frontend developer full-time
- Backend APIs are ready and tested
- No major design changes
- Some parallel work possible

---

## Open Questions

1. **Design System**: Do we have designs for sub-account UI? Or should frontend design it?
2. **Mobile Experience**: How should context switching work on mobile?
3. **Onboarding**: Should we add a guided tour for first sub-account creation?
4. **Bulk Import**: Should we support CSV import of multiple sub-accounts?
5. **Templates**: Should we offer templates (e.g., "Agency Setup", "Brand Portfolio")?

---

## Next Steps

1. **Review this document** with frontend team
2. **Clarify open questions** with backend team
3. **Create wireframes/mockups** for new UI components
4. **Set up feature branch** in frontend repo
5. **Start with Phase 1** (API integration)
6. **Regular syncs** with backend team during development

---

**Document Version**: 1.0  
**Date**: January 11, 2026  
**Audience**: Frontend Development Team  
**Related**: `AGENCY_MULTI_ACCOUNT_PLANNING.md`
