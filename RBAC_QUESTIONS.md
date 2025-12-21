# RBAC Implementation - Questions for Frontend Engineer

This document outlines the questions and clarifications needed from the frontend engineering team regarding the RBAC implementation.

## Implementation Status

### ✅ Fully Implemented (Production Ready)

1. **Core RBAC System**
   - JWT tokens now include roles, permissions, and companyId
   - Access token expiration: 15 minutes (configurable)
   - Refresh token expiration: 7 days
   - Token rotation on refresh

2. **Authentication Endpoints**
   - POST /api/public/login - Returns tokens + roles/permissions
   - POST /api/public/signup - Assigns default role + returns tokens
   - POST /api/public/refreshToken - Refreshes tokens with rotation
   - POST /api/public/logout - Invalidates refresh tokens

3. **Permission Enforcement**
   - Automatic permission checking for all admin endpoints
   - Returns 403 with detailed error for insufficient permissions
   - Security event logging for all permission denials

4. **Role System**
   - Three roles defined: user, admin, company_owner
   - Each role has predefined permission set
   - Default 'user' role assigned on signup

5. **Database Support**
   - RefreshTokens table (auto-created)
   - Users table updated with Roles, Permissions, CompanyId fields
   - All backward compatible

### ⚠️ Partially Implemented (Foundation Ready, Endpoints Missing)

The following features have the foundation in place but are missing actual endpoint implementations:

1. **User Management Endpoints**
   - Permission mappings exist for:
     - GET /api/admin/getUsers (requires read:users)
     - POST /api/admin/createUser (requires write:users)
     - PUT /api/admin/updateUser (requires write:users)
     - DELETE /api/admin/deleteUser (requires manage:users)
   - Permissions are assigned to 'admin' role
   - Permission checking is implemented and will work automatically
   - **Missing**: The actual endpoint handler functions

2. **Company Management Endpoints**
   - Permission mappings exist for:
     - GET /api/admin/getCompany (requires read:company)
     - PUT /api/admin/updateCompany (requires write:company)
     - GET /api/admin/getCompanyMembers (requires read:company_members)
     - POST /api/admin/addCompanyMember (requires manage:company_members)
     - DELETE /api/admin/removeCompanyMember (requires manage:company_members)
   - Permissions are assigned to 'company_owner' role
   - Permission checking is implemented and will work automatically
   - **Missing**: The actual endpoint handler functions

## Questions Requiring Frontend Engineer Input

### Question 1: User Management Endpoints - Implementation Priority

**Context**: Permission system supports user management, but endpoints don't exist yet.

**Question**: Do you need the user management endpoints implemented now or in a future iteration?

**If YES, please specify**:
- What should getUsers return? (All users? Paginated? Filtered?)
- What fields should createUser accept? (email, username, password, role?)
- What fields can updateUser modify? (profile data? roles? permissions?)
- Should deleteUser be hard delete or soft delete?
- Should admins be able to see/manage all users or only their own?

**If NO**: We can defer this to a future iteration when you're ready to build the admin UI.

---

### Question 2: Company/Multi-tenant Support - Implementation Priority

**Context**: System supports companyId in JWT and database, but company endpoints don't exist.

**Question**: Is multi-tenant company support needed now or in a future iteration?

**If YES, please specify**:
- What defines a company? (Name, domain, settings?)
- How are users associated with companies? (During signup? By admin?)
- Can users belong to multiple companies?
- What should company member management do? (Add/remove users from company?)
- Should companies have their own settings/branding?

**If NO**: We can defer this to a future iteration. The foundation is in place.

---

### Question 3: Role and Permission Management API

**Context**: Currently, roles and permissions must be manually updated in Azure Tables.

**Question**: Do you need API endpoints to manage roles and permissions?

**Potential endpoints**:
- PUT /api/admin/assignRole - Assign role(s) to a user
- PUT /api/admin/revokeRole - Remove role(s) from a user
- PUT /api/admin/grantPermission - Grant permission(s) to a user
- PUT /api/admin/revokePermission - Revoke permission(s) from a user
- GET /api/admin/getUserRoles - Get roles for a user
- GET /api/admin/getUserPermissions - Get permissions for a user

**If YES**: Should this be admin-only or role-specific (e.g., company_owner can manage their company's users)?

**If NO**: Manual Azure Table updates are acceptable for admin role assignment.

---

### Question 4: Default Permission Customization

**Context**: Each role has hardcoded default permissions in Get-DefaultRolePermissions.

**Question**: Should default permissions be customizable, or are the hardcoded values acceptable?

**Current defaults**:
- `user`: 8 basic permissions (profile, links, appearance, analytics)
- `admin`: user permissions + 3 user management permissions
- `company_owner`: user permissions + 4 company management permissions

**If customization needed**:
- Should defaults be stored in database?
- Should there be an API to modify default permissions per role?
- Should permissions be additive (role + custom) or exclusive (custom only)?

**If acceptable**: No changes needed.

---

### Question 5: JWT Token Configuration

**Context**: Access token expiration is configurable via JWT_EXPIRATION_MINUTES environment variable.

**Question**: Is 15 minutes acceptable for production, or do you need a different default?

**Current settings**:
- Access token: 15 minutes (configurable)
- Refresh token: 7 days (hardcoded)

**Considerations**:
- Shorter = more secure but more frequent refreshes
- Longer = fewer refreshes but larger exposure window
- 15 minutes matches industry standards for SPAs

**If acceptable**: No changes needed.

**If change needed**: What should the default be? (5 min? 30 min? 60 min?)

---

### Question 6: Frontend Token Storage Strategy

**Question**: How will the frontend store and manage tokens?

**This affects our recommendation for**:
- Where to store refresh token (localStorage, sessionStorage, httpOnly cookie?)
- How to handle token refresh (automatic interceptor, manual?)
- How to handle token expiration (redirect to login, silent refresh?)

**Please share your approach** so we can:
- Verify our implementation aligns with your strategy
- Recommend any backend changes to support your approach
- Document any frontend-specific considerations

---

### Question 7: Testing and Deployment Timeline

**Question**: When do you plan to test and deploy this?

**Testing support needed**:
- Do you need a test environment deployed?
- Do you need sample test users with different roles?
- Do you need Postman collection or similar for testing?

**Deployment considerations**:
- Will this go to dev/staging first or directly to production?
- Do existing users need to be migrated (assigned roles)?
- Do you need a migration script for existing users?

---

### Question 8: Backward Compatibility Requirements

**Context**: Implementation maintains backward compatibility - old tokens work until expiration.

**Question**: Is gradual migration acceptable, or do you need all users to get new tokens immediately?

**Current approach**:
- Users with old tokens continue working
- Users without roles get defaults on next login
- New signups get roles immediately

**If immediate migration needed**:
- We could invalidate all existing tokens
- Force all users to login again
- Ensures everyone has RBAC-enabled tokens

**If gradual migration acceptable**: No changes needed.

---

### Question 9: Security Event Monitoring

**Context**: System logs security events to Azure Tables (permission denials, token refresh, etc.).

**Question**: Do you need an API to query security events, or is Azure Portal access sufficient?

**Potential endpoint**:
- GET /api/admin/getSecurityEvents - Query security event log

**If API needed**: What filtering/pagination is required?

**If Azure Portal sufficient**: No changes needed.

---

### Question 10: Error Response Format

**Context**: Permission errors return detailed messages including which permission is required.

**Question**: Is the current error format acceptable, or do you need changes?

**Current format**:
```json
{
  "success": false,
  "error": "Forbidden: Insufficient permissions. Required: read:users"
}
```

**Alternative format**:
```json
{
  "success": false,
  "error": {
    "code": "INSUFFICIENT_PERMISSIONS",
    "message": "You don't have permission to access this resource",
    "requiredPermissions": ["read:users"],
    "userPermissions": ["read:profile", "write:profile", ...]
  }
}
```

**If current format acceptable**: No changes needed.

**If change needed**: Please specify preferred format.

---

## Recommendations

### Immediate Next Steps (Recommended)

1. **Review and Answer Questions**: Go through the questions above and provide answers
2. **Test Authentication Flow**: Test signup, login, refresh, logout with the frontend
3. **Test Permission Enforcement**: Verify 403 responses work correctly in your UI
4. **Deploy to Dev Environment**: Get this into a dev environment for integration testing

### Short-term Additions (Based on Answers)

1. **Implement User Management Endpoints** (if needed)
2. **Implement Company Endpoints** (if needed)
3. **Create Role/Permission Management API** (if needed)
4. **Create Postman Collection** (if helpful for testing)

### Long-term Enhancements (Future Iterations)

1. **Token Cleanup Job**: Periodic cleanup of expired refresh tokens
2. **Rate Limiting**: Add rate limiting to refresh token endpoint
3. **Concurrent Session Management**: Limit active refresh tokens per user
4. **Audit Logging**: Enhanced audit trail for role/permission changes
5. **Custom Roles**: Allow creation of custom roles with custom permissions

---

## How to Proceed

Please review the questions above and provide answers in the following format:

```markdown
### Q1: User Management Endpoints
**Answer**: [YES/NO/DEFER]
**Notes**: [Your notes here]

### Q2: Company Support
**Answer**: [YES/NO/DEFER]
**Notes**: [Your notes here]

... (etc for all questions)
```

Once we have your answers, we can:
1. Implement any additional endpoints needed
2. Make any configuration changes required
3. Create testing resources (sample users, Postman collection, etc.)
4. Prepare deployment documentation
5. Provide migration guidance if needed

---

## Contact

If you have questions about the implementation or need clarification on any of the above, please:
1. Comment on this PR
2. Tag the backend team in GitHub issues
3. Schedule a sync call to discuss

We're ready to implement any additional features needed based on your requirements!
