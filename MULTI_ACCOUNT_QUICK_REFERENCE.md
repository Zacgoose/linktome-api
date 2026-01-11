# Agency/Multi-Account Profiles - Quick Reference

## Overview

This feature allows a parent account to create and manage multiple sub-accounts (brand profiles, client profiles) that share the parent's subscription but cannot login independently.

## Key Documents

1. **[AGENCY_MULTI_ACCOUNT_PLANNING.md](./AGENCY_MULTI_ACCOUNT_PLANNING.md)** - Main planning document (comprehensive)
2. **[FRONTEND_COORDINATION_MULTI_ACCOUNT.md](./FRONTEND_COORDINATION_MULTI_ACCOUNT.md)** - Frontend team guide with API specs
3. **[BACKEND_IMPLEMENTATION_GUIDE.md](./BACKEND_IMPLEMENTATION_GUIDE.md)** - Backend technical implementation guide

## Quick Facts

### User Pack System
| Pack Type | Sub-Accounts | Monthly Cost |
|-----------|--------------|--------------|
| No Pack | 0 | $0 |
| Starter Pack | 3 | $x |
| Business Pack | 10 | $y |
| Enterprise Pack | Custom | Custom |

**Billing Model**: Base subscription + User pack (separate add-on)
- Parent gets their tier's features (Free, Pro, Premium, Enterprise)
- Purchase user pack separately to enable sub-accounts
- Sub-accounts inherit parent's tier features

### What Sub-Accounts CAN Do
✅ Have their own public profile (username, display name, bio, avatar)  
✅ Create and manage pages  
✅ Create and manage links  
✅ Customize appearance (theme, colors, etc.)  
✅ View their analytics  
✅ Create short links (based on parent's tier)  

### What Sub-Accounts CANNOT Do
❌ Login independently or via API (no credentials)  
❌ Manage API keys  
❌ Enable/disable 2FA  
❌ Change subscription settings  
❌ Change password/email/phone  
❌ Invite user managers  
❌ Create their own sub-accounts
❌ Access user management features  

## New API Endpoints

### 1. List Sub-Accounts
```
GET /api/admin/getSubAccounts
Authorization: Bearer {parentJWT}
```

### 2. Create Sub-Account
```
POST /api/admin/createSubAccount
Authorization: Bearer {parentJWT}

Body:
{
  "username": "clientbrand",
  "email": "brand@client.com",
  "displayName": "Client Brand",
  "bio": "Optional bio",
  "type": "agency_client"
}
```

### 3. Update Sub-Account
```
PUT /api/admin/updateSubAccount
Authorization: Bearer {parentJWT}

Body:
{
  "userId": "user-abc123",
  "displayName": "Updated Name",
  "bio": "Updated bio",
  "type": "brand"
}
```

### 4. Delete Sub-Account
```
DELETE /api/admin/deleteSubAccount?userId={userId}
Authorization: Bearer {parentJWT}
```

### 5. Switch Context (Most Important)
```
POST /api/admin/switchContext
Authorization: Bearer {currentJWT}

Body:
{
  "userId": "user-abc123"  // Sub-account to switch to, or null for parent
}

Response:
{
  "accessToken": "eyJ...",  // NEW JWT with context
  "context": {
    "parentUserId": "user-parent123",
    "contextUserId": "user-abc123",
    "contextUsername": "clientbrand",
    "isSubAccountContext": true
  }
}
```

## Context Switching Flow

1. Parent logs in → Gets standard JWT
2. Parent calls `switchContext` with sub-account ID → Gets context JWT
3. All API calls now operate on sub-account using context JWT
4. Create pages, links, etc. for sub-account
5. Call `switchContext` with null to return to parent

## Database Schema

### New Table: SubAccounts
```
PartitionKey: ParentAccountId (parent's UserId)
RowKey: SubAccountId (sub-account's UserId)
Fields:
  - SubAccountType: string ('agency_client', 'brand', 'project', 'other')
  - Status: string ('active', 'suspended', 'deleted')
  - CreatedAt: datetime
  - CreatedByUserId: string
```

### Update to Users Table
Add field:
- `IsSubAccount`: boolean (default: false)

## JWT Token Structure

### Standard Token (Parent)
```json
{
  "userId": "user-parent123",
  "email": "parent@example.com",
  "username": "parentuser",
  "tier": "premium",
  "isSubAccountContext": false,
  "exp": 1234567890
}
```

### Context Token (Managing Sub-Account)
```json
{
  "userId": "user-parent123",              // Parent (for auth)
  "contextUserId": "user-subaccount123",   // Sub-account (for operations)
  "username": "parentuser",
  "contextUsername": "clientbrand",
  "tier": "premium",
  "isSubAccountContext": true,
  "exp": 1234567890
}
```

## Implementation Timeline

| Phase | Description | Duration | Team |
|-------|-------------|----------|------|
| 1 | Database & Core Logic | 1-2 weeks | Backend |
| 2 | Sub-Account CRUD Endpoints | 1 week | Backend |
| 3 | Context Switching | 1 week | Backend |
| 4 | Frontend - Basic UI | 2 weeks | Frontend |
| 5 | Frontend - Context-Aware UI | 1 week | Frontend |
| 6 | Testing & Polish | 1 week | Both |
| 7 | Documentation & Launch | 3-5 days | Both |
| **Total** | | **6-8 weeks** | |

## Key Design Decisions

### Why SubAccounts Table?
- Clean separation from Users table
- Efficient bi-directional queries
- Easy to add relationship metadata
- Doesn't clutter user records

### Why Individual Limits?
- Simpler to implement
- Clearer for users
- More generous (feels like better value)
- Can change later if needed

### Why No Nested Sub-Accounts?
- Adds significant complexity
- Unclear use case
- Can add later if demand exists

### Why Block Login?
- Security: Can't steal access
- Simplicity: No credential management
- Clear separation of concerns
- Parent maintains full control

## Security Considerations

### Critical Checks
✅ Validate ownership on every sub-account operation  
✅ Block login attempts for sub-accounts  
✅ Verify context JWT on every request  
✅ Enforce tier limits server-side  
✅ Log all sub-account operations  
✅ Block restricted operations in sub-account context  

### Audit Events
New security event types:
- `SubAccountCreated`
- `SubAccountUpdated`
- `SubAccountDeleted`
- `SubAccountSuspended`
- `ContextSwitch`
- `SubAccountLoginAttempt` (blocked)

## Testing Checklist

### Backend
- [ ] Create sub-account (valid data)
- [ ] Create sub-account (exceed tier limit)
- [ ] Create sub-account (duplicate username)
- [ ] Switch context to sub-account
- [ ] Create pages/links in context
- [ ] Attempt restricted operation in context (should fail)
- [ ] Return to parent context
- [ ] Sub-account login attempt (should fail)
- [ ] Tier inheritance works correctly
- [ ] Parent subscription expiration handling

### Frontend
- [ ] List sub-accounts
- [ ] Create new sub-account (form validation)
- [ ] Switch context (UI updates correctly)
- [ ] Context banner displays
- [ ] Restricted features hidden in context
- [ ] Create content in sub-account context
- [ ] View aggregated dashboard
- [ ] Delete sub-account (with confirmation)
- [ ] Upgrade prompt when limit reached
- [ ] Context persists on page refresh

## Open Questions

### Product Decisions Needed
1. **Naming**: "Sub-accounts" vs "Brand profiles" vs "Client profiles"?
2. **Feature Limits**: Individual per sub-account or aggregated?
3. **Email Notifications**: Parent's email or sub-account email?
4. **Public Branding**: Show "Managed by X" on public profiles?

### Technical Decisions Needed
1. **Context Storage**: localStorage vs sessionStorage?
2. **URL Strategy**: Query params vs path segments?
3. **API Keys**: Can parent's API keys operate in context?
4. **Username Changes**: Allow with cooldown or block entirely?

## Migration Considerations

### For Existing Users
- No automatic conversion of existing accounts
- Must manually create sub-accounts if desired
- Existing user management (UserManagers) remains separate feature

### For New Features
- Plan for future: teams, workspaces, organizations?
- Keep architecture flexible
- Document extension points

## Support & Documentation

### User Guides Needed
- "Getting Started with Sub-Accounts"
- "Agency Mode: Managing Multiple Brands"
- "Sub-Account Limits by Tier"
- "Switching Between Accounts"

### API Documentation Updates
- Add new endpoints to API reference
- Document context switching flow
- Add JWT structure documentation
- Update authentication guide

## Pricing & Marketing

### Value Proposition
- **For Agencies**: Manage all clients under one subscription
- **For Creators**: Multiple brands, one bill
- **For Projects**: Separate profiles per project
- **For Testing**: Test accounts without extra cost

### Competitive Analysis
- **Linktree**: No multi-account feature (gap we can fill)
- **Beacons**: Team features but each pays separately
- **Bento**: Individual accounts only

### Pricing Impact
- Feature available Pro+ (validates tier pricing)
- May increase Pro tier adoption
- Enterprise unlimited = clear upgrade path
- Consider "Agency Plan" in future

## Success Metrics

### Adoption
- % of Pro+ users creating sub-accounts
- Average sub-accounts per parent
- Tier upgrades for sub-account feature

### Usage
- Context switches per session
- Operations in sub-account context
- Sub-account public profile views

### Business
- Revenue attributed to feature
- Customer satisfaction scores
- Support ticket volume

## Resources

### Code Locations
- **Helper Functions**: `Modules/LinkTomeCore/Private/SubAccount/`
- **New Endpoints**: `Modules/PrivateApi/Public/Invoke-AdminSubAccount*.ps1`
- **Updated Functions**: See BACKEND_IMPLEMENTATION_GUIDE.md
- **Frontend Components**: To be determined by frontend team

### Related Features
- **Existing**: User Management (UserManagers table)
- **Existing**: Multi-Page support
- **Existing**: Tier system
- **Future**: Teams/Organizations feature?

## Next Actions

### Immediate (This Week)
- [ ] Review all three planning documents with team
- [ ] Hold kickoff meeting to discuss open questions
- [ ] Get design mockups for new UI components
- [ ] Set up feature branch in both repos
- [ ] Create initial tickets in project board

### Short Term (Next 2 Weeks)
- [ ] Backend: Implement Phase 1 (database & helpers)
- [ ] Backend: Implement Phase 2 (CRUD endpoints)
- [ ] Frontend: Set up API integration layer
- [ ] Frontend: Design state management

### Medium Term (Weeks 3-6)
- [ ] Backend: Implement Phase 3 (context switching)
- [ ] Backend: Update existing endpoints
- [ ] Frontend: Build sub-account management UI
- [ ] Frontend: Implement context switcher
- [ ] Both: Integration testing

### Long Term (Weeks 7-8)
- [ ] Frontend: Context-aware UI updates
- [ ] Both: End-to-end testing
- [ ] Both: Documentation
- [ ] Both: Polish and bug fixes
- [ ] Launch preparation

## Contact & Questions

For questions about:
- **Product/Features**: Contact product team
- **Backend Implementation**: See BACKEND_IMPLEMENTATION_GUIDE.md
- **Frontend Implementation**: See FRONTEND_COORDINATION_MULTI_ACCOUNT.md
- **Overall Architecture**: See AGENCY_MULTI_ACCOUNT_PLANNING.md

---

**Last Updated**: January 11, 2026  
**Status**: Planning Complete - Awaiting Team Review  
**Version**: 1.0
