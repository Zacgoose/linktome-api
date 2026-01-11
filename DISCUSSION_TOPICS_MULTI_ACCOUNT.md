# Discussion Topics: Agency/Multi-Account Profiles

This document outlines the key questions and decisions that need team input before implementation begins. Please review and provide feedback.

---

## 1. Product & Naming Decisions

### 1.1 Feature Naming
**Question**: What should we call this feature?

**Options**:
- **"Sub-Accounts"** - Technical but clear
- **"Brand Profiles"** - User-friendly, marketing angle
- **"Client Profiles"** - Agency-focused
- **"Multi-Account Management"** - Descriptive
- **"Agency Mode"** - Premium feature positioning

**Considerations**:
- Will be used in UI, documentation, marketing
- Should appeal to target users (agencies, creators, businesses)
- Should be intuitive and self-explanatory

**Recommendation**: "Sub-Accounts" in technical docs, "Brand Profiles" or "Agency Mode" in marketing

**Decision Needed**: [ ] Team to vote/discuss

---

### 1.2 Account Type Terminology
**Question**: What should we call the relationship?

Currently using:
- "Parent Account" and "Sub-Account"

**Alternatives**:
- "Primary Account" and "Secondary Account"
- "Master Account" and "Child Account"
- "Main Profile" and "Brand Profile"

**Recommendation**: Keep "Parent Account" and "Sub-Account" (clear, hierarchical)

**Decision Needed**: [ ] Approve or suggest alternative

---

## 2. Feature Usage & Limits

### 2.1 Limit Enforcement Strategy
**Question**: How should feature limits work across sub-accounts?

**Option A - Individual Limits (Recommended)**
- Each sub-account has full tier limits independently
- Pro parent: 50 links, each sub-account: 50 links
- Pros: Simple, generous, clear
- Cons: Could be seen as gaming the system

**Option B - Aggregated Limits**
- Combined limits across all sub-accounts
- Pro parent + 3 subs share 50 links total
- Pros: Fair, prevents abuse
- Cons: Confusing, may frustrate users

**Option C - Multiplied Limits**
- Limits scale with sub-account count
- Pro tier: 50 links × (1 parent + 3 subs) = 200 links
- Pros: Scales well, generous
- Cons: Devalues higher tiers, complex

**Current Recommendation**: Option A for MVP

**Discussion Points**:
- What feels fair to users?
- What prevents abuse?
- What's easiest to explain?
- Impact on tier pricing?

**Decision Needed**: [ ] Choose option A, B, or C

---

### 2.2 Sub-Account Creation Limits
**Question**: Should we allow sub-accounts on Free tier?

**Current Plan**:
- Free: 0 sub-accounts
- Pro: 3 sub-accounts  
- Premium: 10 sub-accounts
- Enterprise: Unlimited

**Alternative**: Free tier gets 1 sub-account to try the feature

**Pros**: Lower barrier to entry, trial experience
**Cons**: Devalues Pro tier, potential abuse

**Decision Needed**: [ ] Stick with current plan or allow 1 on Free?

---

## 3. User Experience & Interface

### 3.1 Public Profile Indication
**Question**: Should sub-account public profiles show they're managed by a parent?

**Option A - No Indication**
- Public profiles look like any other profile
- No mention of parent account
- Pros: Clean, professional appearance
- Cons: Less transparency

**Option B - Subtle Badge**
- Small "Managed by [Parent]" badge
- Optional "Powered by LinkToMe" link
- Pros: Transparency, trust
- Cons: May look less professional

**Option C - Optional Setting**
- Parent chooses whether to show
- Pros: Flexibility
- Cons: Another setting to manage

**Current Recommendation**: Option A (no indication) for MVP

**Decision Needed**: [ ] Choose option

---

### 3.2 Email Notifications
**Question**: Where should notifications be sent for sub-accounts?

**Scenarios**:
- Password reset requests (blocked, but future-proofing)
- Analytics reports
- System notifications
- Feature updates

**Option A - Parent Email Only**
- All notifications go to parent account email
- Pros: Simple, parent maintains control
- Cons: May miss sub-account specific info

**Option B - Sub-Account Email**
- Notifications go to sub-account's configured email
- Pros: Appropriate audience receives info
- Cons: Sub-account may not check that email

**Option C - Both (with preferences)**
- Configurable per notification type
- Pros: Maximum flexibility
- Cons: Complex to manage

**Current Recommendation**: Option A for MVP, add preferences later

**Decision Needed**: [ ] Choose option

---

### 3.3 Dashboard View
**Question**: What should the parent's dashboard show by default?

**Option A - Parent Only**
- Dashboard shows parent account stats only
- Link to view aggregated or per-sub-account stats
- Pros: Not overwhelming, focused
- Cons: Less visibility

**Option B - Aggregated by Default**
- Dashboard shows combined stats
- Parent + all sub-accounts
- Drill down for details
- Pros: Complete picture, valuable insights
- Cons: May be confusing

**Option C - Switchable View**
- Toggle between parent-only, aggregated, and per-account
- Pros: Flexibility
- Cons: Another UI element

**Current Recommendation**: Option C (switchable)

**Decision Needed**: [ ] Choose option

---

## 4. Technical Decisions

### 4.1 Context Token Storage
**Question**: Where should the context JWT be stored in frontend?

**Option A - localStorage**
- Persists across browser sessions
- Context maintained on page refresh
- Pros: Better UX, less re-authentication
- Cons: XSS vulnerability if not careful

**Option B - sessionStorage**
- Cleared when tab closes
- More secure
- Pros: Better security
- Cons: Context lost on refresh (poor UX)

**Option C - Secure cookie**
- HttpOnly, Secure flags
- Backend manages
- Pros: Most secure
- Cons: More backend work, CORS complexity

**Current Recommendation**: Option A (localStorage) with XSS protection

**Decision Needed**: [ ] Frontend team to decide

---

### 4.2 URL Strategy
**Question**: How should context be reflected in URLs?

**Option A - Query Parameter**
```
/dashboard?context=user-abc123
/links?context=user-abc123
```
Pros: Simple, works with existing routing
Cons: Clutters URLs

**Option B - Path Segment**
```
/manage/user-abc123/dashboard
/manage/user-abc123/links
```
Pros: Clean URLs, RESTful
Cons: Requires routing changes

**Option C - No URL Reflection**
- Context stored only in state
- URLs remain unchanged
Pros: Clean URLs
Cons: Can't bookmark/share links to specific context

**Current Recommendation**: Option A for MVP, migrate to Option B later

**Decision Needed**: [ ] Frontend team to decide

---

### 4.3 API Key Context Support
**Question**: Should parent's API keys be able to operate in sub-account context?

**Scenario**: Parent has API key. Can they use it with a header like `X-Context-User: user-abc123`?

**Option A - No Context Support**
- API keys only work for the account they belong to
- Sub-account operations must use JWT + switchContext
- Pros: Simple, secure, consistent
- Cons: Less flexible for automation

**Option B - Context Header Support**
- API keys can include `X-Context-User` header
- Ownership verified server-side
- Pros: More flexible, better for automation
- Cons: More complex, potential security risks

**Current Recommendation**: Option A for MVP

**Decision Needed**: [ ] Decide if context support needed

---

## 5. Business & Pricing

### 5.1 Pricing Model
**Question**: Should sub-accounts be included in tier price or an add-on?

**Current Plan - Included in Tier**:
- Pro: 3 sub-accounts included
- Premium: 10 sub-accounts included
- Enterprise: Unlimited included

**Alternative - Add-On Model**:
- Base tier + $X per sub-account
- Or: Separate "Agency" tier

**Pros of Current Plan**:
- Simple pricing
- Better value proposition
- Encourages tier upgrades

**Pros of Add-On**:
- More revenue potential
- Users only pay for what they use
- Flexible for different use cases

**Current Recommendation**: Stick with included-in-tier for MVP

**Decision Needed**: [ ] Confirm pricing approach

---

### 5.2 Marketing Positioning
**Question**: How should we market this feature?

**Target Audiences**:
1. **Agencies** - Manage multiple client profiles
2. **Creators** - Multiple personal brands/projects  
3. **Businesses** - Separate company divisions
4. **Influencers** - Main profile + side projects

**Messaging Options**:
- **"Agency Mode"** - Premium feature for professionals
- **"Multi-Brand Management"** - For creators with multiple brands
- **"All Your Brands, One Bill"** - Cost savings angle
- **"Professional Profile Management"** - Enterprise positioning

**Decision Needed**: [ ] Marketing team to decide positioning

---

## 6. Security & Compliance

### 6.1 Parent Account Deletion
**Question**: What happens to sub-accounts when parent account is deleted?

**Option A - Require Sub-Account Deletion First**
- Can't delete parent until all sub-accounts deleted
- Pros: Prevents accidental data loss, clear process
- Cons: Extra steps

**Option B - Cascade Delete**
- Deleting parent automatically deletes all sub-accounts
- With confirmation and warning
- Pros: Simpler workflow
- Cons: Risk of accidental mass deletion

**Option C - Convert to Standalone**
- Sub-accounts become independent accounts
- With default credentials sent to emails
- Pros: Preserves data
- Cons: Very complex, security issues

**Current Recommendation**: Option A (require deletion first)

**Decision Needed**: [ ] Confirm approach

---

### 6.2 Audit & Compliance
**Question**: What audit logging is needed?

**Current Plan**:
- Log all sub-account creation/deletion
- Log all context switches
- Log operations performed in context
- Include both parent and context user IDs

**Additional Considerations**:
- GDPR compliance for sub-account data
- Data export requirements
- Right to deletion (parent vs sub-account)

**Decision Needed**: [ ] Legal/compliance team to review

---

## 7. Future Considerations

### 7.1 Nested Sub-Accounts
**Question**: Should we plan for sub-accounts of sub-accounts?

**Use Case**: Agency → Client → Brand hierarchy

**Recommendation**: Not for MVP, but design with extensibility in mind

**Decision Needed**: [ ] Confirm "no" for MVP

---

### 7.2 Sub-Account Login (Future)
**Question**: Should we ever allow sub-accounts to login?

**Use Case**: Client wants direct access to their profile

**Considerations**:
- Adds complexity to authentication
- Security implications
- Billing implications
- May conflict with "parent control" concept

**Recommendation**: Not for MVP, evaluate based on user feedback

**Decision Needed**: [ ] Confirm "no" for MVP

---

### 7.3 Sub-Account to Standalone Conversion
**Question**: Should we support converting a sub-account to a standalone account?

**Use Case**: Client wants to take over their profile

**Considerations**:
- Data ownership transfer
- New subscription required
- Billing transition
- Historical analytics

**Recommendation**: Not for MVP, but may be valuable feature later

**Decision Needed**: [ ] Confirm "no" for MVP

---

## 8. Migration & Rollout

### 8.1 Beta Testing
**Question**: Should we do a limited beta before full rollout?

**Option A - Public Beta**
- All Pro+ users can access
- Gather feedback quickly
- Pros: Fast feedback, real usage data
- Cons: Risk of bugs affecting many users

**Option B - Invite-Only Beta**
- Select group of agencies/power users
- Controlled rollout
- Pros: Safer, targeted feedback
- Cons: Slower rollout

**Option C - Internal/Team Beta**
- Team members only initially
- Then gradual rollout
- Pros: Safest
- Cons: Slowest, limited feedback

**Current Recommendation**: Option B (invite-only beta)

**Decision Needed**: [ ] Choose rollout strategy

---

### 8.2 Existing UserManagers Feature
**Question**: How does this relate to existing user management?

**Current UserManagers**: Separate accounts with delegation

**Sub-Accounts**: Profiles owned by parent

**Options**:
- **Keep Both** - Different use cases
- **Deprecate UserManagers** - Replace with sub-accounts
- **Merge Features** - Complex

**Current Recommendation**: Keep both, clearly document differences

**Decision Needed**: [ ] Confirm approach

---

## Decision Summary

Please mark decisions as they're made:

### Product Decisions
- [ ] 1.1 Feature naming
- [ ] 1.2 Account terminology
- [ ] 2.1 Limit enforcement strategy
- [ ] 2.2 Free tier sub-account allowance
- [ ] 3.1 Public profile indication
- [ ] 3.2 Email notification destination
- [ ] 3.3 Dashboard default view

### Technical Decisions
- [ ] 4.1 Context token storage
- [ ] 4.2 URL strategy
- [ ] 4.3 API key context support

### Business Decisions
- [ ] 5.1 Pricing model confirmation
- [ ] 5.2 Marketing positioning

### Security Decisions
- [ ] 6.1 Parent deletion handling
- [ ] 6.2 Audit logging review

### Future Features
- [ ] 7.1 Nested sub-accounts (No for MVP)
- [ ] 7.2 Sub-account login (No for MVP)
- [ ] 7.3 Conversion to standalone (No for MVP)

### Rollout Decisions
- [ ] 8.1 Beta testing strategy
- [ ] 8.2 UserManagers feature relationship

---

## Next Steps

1. **Schedule Team Meeting**: Review this document together
2. **Make Decisions**: Go through each item and decide
3. **Document Decisions**: Update this document with final decisions
4. **Update Planning Docs**: Reflect decisions in main planning documents
5. **Create Tickets**: Break down into implementation tasks
6. **Begin Development**: Start Phase 1

---

## Meeting Notes

Date: _________________

Attendees: _________________

Decisions Made:
- 
- 
- 

Action Items:
- 
- 
- 

---

**Document Version**: 1.0  
**Date**: January 11, 2026  
**Status**: Pending Team Discussion  
**Next Review**: To be scheduled
