# Agency/Multi-Account Profiles - Planning Documentation

## 📋 Documentation Index

This folder contains comprehensive planning documentation for the agency/multi-account profiles feature. Start with the Quick Reference and dive into specific documents as needed.

### 🚀 Start Here
**[MULTI_ACCOUNT_QUICK_REFERENCE.md](./MULTI_ACCOUNT_QUICK_REFERENCE.md)**  
Quick reference guide with key facts, API endpoints, timelines, and checklists. Perfect for getting up to speed quickly.

### 📖 Main Documentation

#### 1. **[AGENCY_MULTI_ACCOUNT_PLANNING.md](./AGENCY_MULTI_ACCOUNT_PLANNING.md)** (27KB)
**Comprehensive planning document covering:**
- ✅ Core concept and architecture
- ✅ Database schema changes (SubAccounts table)
- ✅ New API endpoints (5 endpoints)
- ✅ Tier limits and feature gating
- ✅ Authentication with context switching
- ✅ Frontend requirements
- ✅ Security considerations
- ✅ Implementation roadmap (7 phases)
- ✅ Open questions for discussion
- ✅ Alternative architectures considered

**Audience**: Everyone (Product, Design, Development, QA)  
**Read time**: ~45 minutes

#### 2. **[FRONTEND_COORDINATION_MULTI_ACCOUNT.md](./FRONTEND_COORDINATION_MULTI_ACCOUNT.md)** (28KB)
**Frontend-specific implementation guide with:**
- ✅ Complete API specifications with TypeScript types
- ✅ JWT token structure for authentication
- ✅ State management examples (Zustand)
- ✅ UI component requirements
- ✅ React/TypeScript code samples
- ✅ URL routing strategies
- ✅ Error handling patterns
- ✅ Testing checklist
- ✅ Accessibility requirements
- ✅ Timeline: 17-23 days

**Audience**: Frontend developers, UI/UX designers  
**Read time**: ~45 minutes

#### 3. **[BACKEND_IMPLEMENTATION_GUIDE.md](./BACKEND_IMPLEMENTATION_GUIDE.md)** (35KB)
**Backend technical specifications including:**
- ✅ Database schema with query patterns
- ✅ New helper functions (4 functions)
- ✅ Updates to existing functions
- ✅ JWT generation for context support
- ✅ Complete PowerShell code for new endpoints
- ✅ Pattern for updating existing endpoints
- ✅ Permission system updates
- ✅ Security event logging
- ✅ Migration steps
- ✅ Performance optimization

**Audience**: Backend developers  
**Read time**: ~60 minutes

#### 4. **[DISCUSSION_TOPICS_MULTI_ACCOUNT.md](./DISCUSSION_TOPICS_MULTI_ACCOUNT.md)** (13KB)
**Open questions requiring team decisions:**
- ❓ Product naming and terminology
- ❓ Feature limit enforcement strategy
- ❓ Public profile indication
- ❓ Email notification handling
- ❓ Technical implementation choices
- ❓ Pricing model confirmation
- ❓ Beta testing strategy
- ❓ Future feature considerations

**Audience**: Product managers, team leads, stakeholders  
**Read time**: ~30 minutes  
**Action**: Schedule team meeting to decide

---

## 🎯 Feature Summary

### What Is It?
Agency/multi-account profiles allow a parent account to create and manage multiple sub-accounts (brand profiles, client profiles) that:
- ✅ Share the parent's subscription tier and features
- ✅ Have their own public presence (username, pages, links)
- ❌ Cannot login independently (no credentials)
- ❌ Cannot manage sensitive settings (API, 2FA, subscription)

### Who Is It For?
- **Agencies** managing multiple client profiles
- **Creators** with multiple brands or projects
- **Businesses** managing different divisions
- **Power users** wanting consolidated billing

### Key Benefits
- 💰 One subscription for multiple profiles
- 🎯 Centralized management
- 🔒 Parent maintains full control
- 📊 Separate analytics per profile
- 🚀 Professional multi-brand presence

---

## 📊 Quick Stats

### User Pack System
| Pack Type | Sub-Accounts | Add-on Cost |
|-----------|--------------|-------------|
| No Pack | 0 | $0 |
| Starter Pack | 3 | $x/month |
| Business Pack | 10 | $y/month |
| Enterprise Pack | Custom | Custom |

**Note**: User packs are purchased separately from base subscription tiers. Any tier can purchase a user pack.

### Implementation Effort
- **Backend**: 4-5 weeks (3 phases)
- **Frontend**: 3.5-4.5 weeks (5 components)
- **Testing**: 1-2 weeks
- **Total**: 8-10 weeks

### New API Endpoints
5 new admin endpoints:
1. `GET /admin/getSubAccounts` - List all sub-accounts
2. `POST /admin/createSubAccount` - Create new sub-account
3. `PUT /admin/updateSubAccount` - Update sub-account
4. `DELETE /admin/deleteSubAccount` - Delete sub-account
5. `POST /admin/switchContext` - Switch management context

### Database Changes
- New `SubAccounts` table for relationships
- Add `IsSubAccount` boolean to Users table
- Update `Get-UserSubscription.ps1` for inheritance
- Update `Get-TierFeatures.ps1` with limits

---

## 🚦 Implementation Status

### ✅ Completed
- [x] Comprehensive planning documentation
- [x] Architecture design
- [x] API specification
- [x] Database schema design
- [x] Security analysis
- [x] Frontend coordination guide
- [x] Backend implementation guide
- [x] Testing strategy
- [x] Timeline estimation

### 🔄 In Progress
- [ ] Team review of documentation
- [ ] Decision making on open questions
- [ ] Design mockups for UI components

### 📅 Upcoming
- [ ] Feature branch setup
- [ ] Ticket creation
- [ ] Phase 1: Database & core logic
- [ ] Phase 2: Sub-account CRUD endpoints
- [ ] Phase 3: Context switching
- [ ] Phase 4: Frontend UI
- [ ] Phase 5: Testing & polish
- [ ] Phase 6: Documentation & launch

---

## 🎨 Key Design Decisions

### ✅ Confirmed Decisions
1. **SubAccounts table approach** - Clean separation from Users table
2. **Individual feature limits** - Each sub-account has full tier limits (Option A)
3. **No nested sub-accounts** - Keep it simple for MVP
4. **Block sub-account login** - Security and simplicity
5. **Context switching via JWT** - Secure and stateless
6. **Pro+ tier requirement** - Free tier gets 0 sub-accounts

### ❓ Pending Decisions (See Discussion Doc)
1. Feature naming ("Sub-Accounts" vs "Brand Profiles" vs "Agency Mode")
2. Public profile indication (show parent or not)
3. Email notification destination (parent or sub-account)
4. Dashboard default view (parent only vs aggregated)
5. URL strategy (query params vs path segments)
6. Beta rollout strategy (public vs invite-only)

---

## 🔐 Security Highlights

### Critical Security Requirements
✅ Sub-accounts cannot login (validated at login endpoint)  
✅ Ownership verified on all operations  
✅ Context validated on every request  
✅ Restricted operations blocked in sub-account context  
✅ All operations audited and logged  
✅ Tier limits enforced server-side  

### New Security Events
- `SubAccountCreated`
- `SubAccountUpdated`
- `SubAccountDeleted`
- `SubAccountSuspended`
- `ContextSwitch`
- `SubAccountLoginAttempt` (blocked)

---

## 🔄 Context Switching Flow

```
1. Parent logs in
   ↓
2. Receives standard JWT
   ↓
3. Calls /admin/switchContext with sub-account ID
   ↓
4. Receives context JWT (includes contextUserId)
   ↓
5. All operations now affect sub-account
   ↓
6. Can return to parent via switchContext(null)
```

### JWT Structure Comparison

**Standard JWT (Parent)**:
```json
{
  "userId": "user-parent123",
  "username": "parentuser",
  "tier": "premium",
  "isSubAccountContext": false
}
```

**Context JWT (Sub-Account)**:
```json
{
  "userId": "user-parent123",
  "contextUserId": "user-sub123",
  "contextUsername": "clientbrand",
  "tier": "premium",
  "isSubAccountContext": true
}
```

---

## 📝 Testing Strategy

### Backend Tests
- Unit tests for helper functions
- Integration tests for endpoints
- Security tests for ownership validation
- Tier limit enforcement tests

### Frontend Tests
- Component unit tests
- Context switching flow tests
- UI state management tests
- Accessibility tests

### End-to-End Tests
- Complete user journey (create → manage → delete)
- Multi-context switching
- Permission restrictions
- Subscription tier changes

---

## 🚀 Getting Started

### For Product Managers
1. Read [MULTI_ACCOUNT_QUICK_REFERENCE.md](./MULTI_ACCOUNT_QUICK_REFERENCE.md)
2. Review [DISCUSSION_TOPICS_MULTI_ACCOUNT.md](./DISCUSSION_TOPICS_MULTI_ACCOUNT.md)
3. Schedule team meeting to decide on open questions
4. Provide input on marketing positioning

### For Frontend Developers
1. Read [MULTI_ACCOUNT_QUICK_REFERENCE.md](./MULTI_ACCOUNT_QUICK_REFERENCE.md)
2. Study [FRONTEND_COORDINATION_MULTI_ACCOUNT.md](./FRONTEND_COORDINATION_MULTI_ACCOUNT.md)
3. Review API specifications and code examples
4. Estimate effort and create tickets

### For Backend Developers
1. Read [MULTI_ACCOUNT_QUICK_REFERENCE.md](./MULTI_ACCOUNT_QUICK_REFERENCE.md)
2. Study [BACKEND_IMPLEMENTATION_GUIDE.md](./BACKEND_IMPLEMENTATION_GUIDE.md)
3. Review database schema and helper functions
4. Estimate effort and create tickets

### For QA Engineers
1. Read [MULTI_ACCOUNT_QUICK_REFERENCE.md](./MULTI_ACCOUNT_QUICK_REFERENCE.md)
2. Review testing checklists in all documents
3. Create test plan and test cases
4. Set up test data and environments

### For Designers
1. Read [MULTI_ACCOUNT_QUICK_REFERENCE.md](./MULTI_ACCOUNT_QUICK_REFERENCE.md)
2. Review UI requirements in [FRONTEND_COORDINATION_MULTI_ACCOUNT.md](./FRONTEND_COORDINATION_MULTI_ACCOUNT.md)
3. Create wireframes and mockups
4. Design context switcher and management interface

---

## 📞 Contact & Questions

### For Questions About:
- **Overall Architecture**: See [AGENCY_MULTI_ACCOUNT_PLANNING.md](./AGENCY_MULTI_ACCOUNT_PLANNING.md)
- **Frontend Implementation**: See [FRONTEND_COORDINATION_MULTI_ACCOUNT.md](./FRONTEND_COORDINATION_MULTI_ACCOUNT.md)
- **Backend Implementation**: See [BACKEND_IMPLEMENTATION_GUIDE.md](./BACKEND_IMPLEMENTATION_GUIDE.md)
- **Product Decisions**: See [DISCUSSION_TOPICS_MULTI_ACCOUNT.md](./DISCUSSION_TOPICS_MULTI_ACCOUNT.md)

### Documentation Feedback
If you find any gaps, errors, or areas needing clarification in these documents, please:
1. Create an issue in the repository
2. Tag with "documentation" and "multi-account"
3. Reference the specific document and section

---

## 📈 Success Criteria

### Launch Criteria
- [ ] All critical decisions made
- [ ] Backend implementation complete and tested
- [ ] Frontend implementation complete and tested
- [ ] Security audit passed
- [ ] Documentation complete
- [ ] Beta testing successful
- [ ] Marketing materials ready

### Success Metrics
- **Adoption**: 30%+ of Pro+ users create sub-accounts within 3 months
- **Usage**: Average 2+ sub-accounts per parent user
- **Revenue**: 15%+ increase in Pro tier signups
- **Satisfaction**: 4.5+ star rating for feature
- **Support**: <5% increase in support tickets

---

## 🗓️ Timeline

### Phase 1: Planning ✅ COMPLETE
**Duration**: 1 week  
**Deliverables**: All planning documents

### Phase 2: Backend Development (Weeks 2-5)
- Week 2: Database schema & helper functions
- Week 3: CRUD endpoints
- Week 4: Context switching
- Week 5: Endpoint updates & testing

### Phase 3: Frontend Development (Weeks 4-7)
- Week 4: API integration setup
- Week 5: Sub-account management UI
- Week 6: Context switcher & awareness
- Week 7: Polish & testing

### Phase 4: Testing & Launch (Weeks 8-10)
- Week 8: Integration testing
- Week 9: Beta testing & fixes
- Week 10: Documentation & launch

---

## 📚 Related Documentation

### Existing Features
- [MULTI_PAGE_IMPLEMENTATION.md](./MULTI_PAGE_IMPLEMENTATION.md) - Multi-page support
- [SHORT_LINKS_API_GUIDE.md](./SHORT_LINKS_API_GUIDE.md) - URL shortener
- [README.md](./README.md) - Main API documentation

### Future Enhancements
- Team/workspace features
- Organization management
- Advanced role-based access control
- White-label capabilities

---

## 🎉 Acknowledgments

### Contributors
- Product Team: Feature concept and requirements
- Backend Team: Architecture and implementation guide
- Frontend Team: UI/UX coordination
- QA Team: Testing strategy
- Security Team: Security review

### Inspiration
- Feedback from agencies using LinkToMe
- Competitor analysis (Linktree, Beacons, Bento)
- User requests for multi-brand management

---

**Planning Complete**: January 11, 2026  
**Status**: ✅ Ready for Team Review  
**Next Step**: Schedule kickoff meeting  
**Version**: 1.0

---

## 📥 Download Documentation

All documents are available in this repository:
- [Main Planning](./AGENCY_MULTI_ACCOUNT_PLANNING.md) (27KB)
- [Frontend Guide](./FRONTEND_COORDINATION_MULTI_ACCOUNT.md) (28KB)
- [Backend Guide](./BACKEND_IMPLEMENTATION_GUIDE.md) (35KB)
- [Quick Reference](./MULTI_ACCOUNT_QUICK_REFERENCE.md) (10KB)
- [Discussion Topics](./DISCUSSION_TOPICS_MULTI_ACCOUNT.md) (13KB)

**Total**: ~113KB of comprehensive planning documentation
