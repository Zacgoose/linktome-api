# RBAC Implementation Summary

## Overview
This document summarizes the implementation of the Role-Based Access Control (RBAC) and permissions system as specified in the backend API requirements.

## Implementation Status

### ✅ Completed Features

#### 1. JWT Token Enhancements
- **Access Token Expiration**: Reduced from 24 hours to 15 minutes for enhanced security
- **New JWT Claims**:
  - `roles`: Array of user roles (e.g., ['user'], ['admin'], ['company_owner'])
  - `permissions`: Array of permission strings (e.g., ['read:profile', 'write:links'])
  - `companyId`: Optional company identifier for multi-tenant support

#### 2. Refresh Token System
- **RefreshTokens Table**: New Azure Table Storage table for storing refresh tokens
  - PartitionKey: Token value (for direct lookup)
  - RowKey: Unique GUID
  - UserId: User identifier
  - ExpiresAt: Token expiration timestamp (7 days)
  - CreatedAt: Token creation timestamp
  - IsValid: Boolean flag for invalidation

- **Refresh Token Functions**:
  - `New-RefreshToken`: Generates secure 64-byte base64-encoded tokens
  - `Save-RefreshToken`: Stores tokens in Azure Tables with 7-day expiration
  - `Get-RefreshToken`: Retrieves and validates tokens (checks expiration)
  - `Remove-RefreshToken`: Invalidates tokens by setting IsValid to false

- **Token Rotation**: Implemented - each refresh generates new tokens and invalidates old ones

#### 3. New Endpoints
- **POST /api/public/RefreshToken**: Refresh access token using refresh token
  - Input: `{ "refreshToken": "string" }`
  - Output: `{ "accessToken": "string", "refreshToken": "string" }`
  - Automatically fetches latest user roles/permissions
  - Implements token rotation for enhanced security

- **POST /api/public/Logout**: Invalidate refresh token
  - Input: `{ "refreshToken": "string" }`
  - Output: `{ "success": true }`
  - Marks refresh token as invalid in database

#### 4. Updated Endpoints
- **POST /api/public/Login**: Now returns refresh token and user roles/permissions
  - New output fields:
    - `refreshToken`: 7-day refresh token
    - `user.roles`: Array of user roles
    - `user.permissions`: Array of user permissions

- **POST /api/public/Signup**: Assigns default 'user' role and returns tokens
  - Default role: `user`
  - Default permissions: 
    - `read:dashboard`, `read:profile`, `write:profile`
    - `read:links`, `write:links`
    - `read:appearance`, `write:appearance`
    - `read:analytics`
  - Returns access token, refresh token, and user info with roles/permissions

#### 5. Permission Enforcement System
- **Get-EndpointPermissions**: Maps endpoints to required permissions
- **Test-UserPermission**: Validates user has required permissions
- **Test-UserRole**: Validates user has required role
- **Router Integration**: Automatic permission checking for all admin endpoints
  - Returns 401 for invalid/missing tokens
  - Returns 403 for insufficient permissions

#### 6. Role System
- **Get-DefaultRolePermissions**: Provides default permissions for each role
  - `user`: Basic profile, links, appearance, analytics, dashboard access
  - `admin`: User role permissions + user management (`read:users`, `write:users`, `manage:users`)
  - `company_owner`: User role permissions + company management (`read:company`, `write:company`, `read:company_members`, `manage:company_members`)

#### 7. Security Events
- New security events logged:
  - `RefreshTokenFailed`: Invalid/expired refresh token attempts
  - `TokenRefreshed`: Successful token refresh
  - `Logout`: Logout attempts
  - `PermissionDenied`: Failed permission checks with details

#### 8. Database Schema Updates
- **Users Table**: New fields (stored as arrays in Azure Tables)
  - `Roles`: Array of role strings
  - `Permissions`: Array of permission strings
  - `CompanyId`: Optional company identifier

- **RefreshTokens Table**: New table structure (auto-created)
  - Indexed by token for fast lookup
  - Tracks validity and expiration
  - Links to user for audit trails

## Endpoint Permission Mapping

| Endpoint | Required Permission |
|----------|-------------------|
| `/api/admin/getProfile` | `read:profile` |
| `/api/admin/updateProfile` | `write:profile` |
| `/api/admin/getLinks` | `read:links` |
| `/api/admin/updateLinks` | `write:links` |
| `/api/admin/getAppearance` | `read:appearance` |
| `/api/admin/updateAppearance` | `write:appearance` |
| `/api/admin/getAnalytics` | `read:analytics` |
| `/api/admin/getDashboardStats` | `read:dashboard` |
| `/api/admin/getUsers` | `read:users` |
| `/api/admin/createUser` | `write:users` |
| `/api/admin/updateUser` | `write:users` |
| `/api/admin/deleteUser` | `manage:users` |
| `/api/admin/getCompany` | `read:company` |
| `/api/admin/updateCompany` | `write:company` |
| `/api/admin/getCompanyMembers` | `read:company_members` |
| `/api/admin/addCompanyMember` | `manage:company_members` |
| `/api/admin/removeCompanyMember` | `manage:company_members` |

## Files Created

### Core RBAC Functions
- `Modules/LinkTomeCore/Auth/Get-DefaultRolePermissions.ps1`
- `Modules/LinkTomeCore/Auth/Test-UserPermission.ps1`
- `Modules/LinkTomeCore/Auth/Test-UserRole.ps1`
- `Modules/LinkTomeCore/Auth/Get-EndpointPermissions.ps1`

### Refresh Token Functions
- `Modules/LinkTomeCore/Auth/New-RefreshToken.ps1`
- `Modules/LinkTomeCore/Auth/Save-RefreshToken.ps1`
- `Modules/LinkTomeCore/Auth/Get-RefreshToken.ps1`
- `Modules/LinkTomeCore/Auth/Remove-RefreshToken.ps1`

### New Endpoints
- `Modules/PublicApi/Public/Invoke-PublicRefreshToken.ps1`
- `Modules/PublicApi/Public/Invoke-PublicLogout.ps1`

## Files Modified

### JWT Token System
- `Modules/LinkTomeCore/Auth/New-LinkToMeJWT.ps1`
  - Added roles, permissions, companyId parameters
  - Changed expiration from 24 hours to 15 minutes
  
- `Modules/LinkTomeCore/Auth/Test-LinkToMeJWT.ps1`
  - Extracts roles, permissions, companyId from JWT payload
  - Handles both array and single value formats

### Authentication Endpoints
- `Modules/PublicApi/Public/Invoke-PublicLogin.ps1`
  - Returns refresh token
  - Returns user roles and permissions
  - Fetches roles/permissions from user record or uses defaults
  
- `Modules/PublicApi/Public/Invoke-PublicSignup.ps1`
  - Assigns default 'user' role and permissions
  - Returns refresh token
  - Stores roles and permissions in user record

### Router
- `Modules/LinkTomeEntrypoints/LinkTomeEntrypoints.psm1`
  - Added permission checking for admin endpoints
  - Returns 403 with detailed error for insufficient permissions
  - Logs permission denied events

## Implementation Notes

### Azure Tables Considerations
Since Azure Tables doesn't have traditional relational database features:

1. **Array Storage**: Roles and permissions are stored as array properties in Azure Tables, which PowerShell handles natively
2. **No Foreign Keys**: RefreshTokens table uses UserId string field instead of foreign key relationship
3. **Partitioning**: RefreshTokens are partitioned by token value for fast direct lookup
4. **Indexing**: All queries use indexed fields (PartitionKey, RowKey) for performance

### Token Rotation Strategy
- Each refresh generates both new access AND refresh tokens
- Old refresh token is immediately invalidated
- Provides forward secrecy - compromised old tokens can't be reused
- 7-day refresh token lifetime balances security and user experience

### Permission Checking Flow
1. Request arrives at admin endpoint
2. Router extracts JWT from Authorization header
3. JWT is validated and decoded
4. Router looks up required permissions for endpoint
5. User's permissions (from JWT) are checked against required permissions
6. If insufficient, 403 Forbidden is returned with details
7. If sufficient, request proceeds to endpoint handler

## Testing Recommendations

### 1. Token Refresh Flow
```bash
# 1. Login to get tokens
POST /api/public/login
{ "email": "user@example.com", "password": "password" }
# Save accessToken and refreshToken

# 2. Use accessToken for authenticated requests (valid for 15 minutes)
GET /api/admin/getProfile
Authorization: Bearer {accessToken}

# 3. When access token expires, refresh it
POST /api/public/refreshToken
{ "refreshToken": "{refreshToken}" }
# Receive new accessToken and refreshToken

# 4. Use new accessToken
GET /api/admin/getProfile
Authorization: Bearer {newAccessToken}
```

### 2. Permission Enforcement
```bash
# Create a new user (gets 'user' role by default)
POST /api/public/signup
{ "email": "test@example.com", "username": "testuser", "password": "Test123" }

# Try to access user management endpoint (requires 'read:users' permission)
GET /api/admin/getUsers
Authorization: Bearer {accessToken}
# Should return 403 Forbidden

# Manually update user in Azure Tables to add 'admin' role
# Then try again - should succeed
```

### 3. Token Rotation
```bash
# Use refresh token
POST /api/public/refreshToken
{ "refreshToken": "{refreshToken1}" }
# Receive refreshToken2

# Try to use old refresh token again
POST /api/public/refreshToken
{ "refreshToken": "{refreshToken1}" }
# Should return 401 Unauthorized
```

### 4. Logout
```bash
# Logout
POST /api/public/logout
{ "refreshToken": "{refreshToken}" }
# Returns success: true

# Try to use logged out refresh token
POST /api/public/refreshToken
{ "refreshToken": "{refreshToken}" }
# Should return 401 Unauthorized
```

## Questions for Frontend Engineer

### 1. Company/Multi-tenant Implementation
**Status**: Foundation implemented but not fully utilized
- JWT includes `companyId` field
- Database schema supports `CompanyId` in Users table
- Endpoint permissions defined for company operations

**Question**: Should we implement the company-specific endpoints now, or is this for future development?

### 2. User Management Endpoints
**Status**: Permission mapping defined but endpoints not yet created
- Permissions defined: `read:users`, `write:users`, `manage:users`
- Endpoint mapping exists for getUsers, createUser, updateUser, deleteUser

**Question**: Do you need these user management endpoints implemented now, or later?

### 3. Dynamic Role/Permission Assignment
**Status**: Currently uses static role definitions
- Roles assigned at signup: always 'user'
- Permissions derived from role using predefined mappings
- No API to change user roles/permissions

**Question**: Do we need endpoints to:
- Assign/revoke roles?
- Grant/revoke individual permissions?
- Create custom roles?

### 4. Company Endpoints Implementation
**Status**: Permission mappings exist but no endpoints
- getCompany, updateCompany
- getCompanyMembers, addCompanyMember, removeCompanyMember

**Question**: Should these be implemented now or deferred?

### 5. Frontend Token Management
**Question**: How will the frontend handle:
- Storing refresh tokens (localStorage, httpOnly cookies, other)?
- Automatic access token refresh (interceptor, manual)?
- Token expiration detection?

## Migration Guide for Existing Users

### Automatic Migration on Login/Signup
The system handles backward compatibility automatically:

1. **Existing Users (No Roles/Permissions in DB)**:
   - On login, if user has no roles/permissions in database
   - System assigns default 'user' role and permissions
   - JWT includes these defaults
   - User can continue using the app normally

2. **New Users**:
   - Signup automatically assigns 'user' role and permissions
   - Stored in database immediately
   - JWT includes roles and permissions from creation

3. **Admin Users**:
   - Must be manually updated in Azure Tables
   - Add `Roles: ['admin']` property to user record
   - Add `Permissions: [...admin permissions...]` property
   - Or rely on default permission lookup if only role is stored

### Manual Database Updates (if needed)
To grant admin access to a user:
```
1. Open Azure Portal
2. Navigate to Storage Account → Tables → Users
3. Find user record (search by email in PartitionKey)
4. Edit entity
5. Add property: Roles = ['admin']
6. (Optional) Add property: Permissions = ['read:dashboard', 'read:profile', ...]
7. Save
8. User must login again (or refresh token) to get new permissions
```

## Security Considerations

### Implemented Security Measures
1. **Short Access Token Lifespan**: 15 minutes reduces exposure window
2. **Refresh Token Rotation**: Prevents token replay attacks
3. **Secure Token Generation**: Uses cryptographic RNG for refresh tokens
4. **Token Invalidation**: Logout properly invalidates tokens
5. **Permission Logging**: All permission denials are logged with details
6. **Query Sanitization**: All table queries use Protect-TableQueryValue
7. **Automatic Expiration**: Expired refresh tokens are rejected

### Recommended Additional Security
1. **Rate Limiting**: Consider rate limiting refresh token endpoint
2. **IP Tracking**: Track IP address changes on token refresh
3. **Concurrent Session Limits**: Limit number of active refresh tokens per user
4. **Token Cleanup**: Periodic job to delete expired refresh tokens

## Compatibility Notes

### Backward Compatibility
- Existing login/signup calls still work (additional fields returned)
- Old access tokens (24-hour) will continue to work until they expire
- Admin endpoints work for users with or without explicit roles/permissions
- No breaking changes to existing API contracts

### Forward Compatibility
- JWT structure allows adding new claims without breaking existing code
- Permission system supports adding new permissions without code changes
- Role system supports adding new roles by updating Get-DefaultRolePermissions

## Next Steps

### Immediate
1. Test implementation with Azure Functions locally or in dev environment
2. Verify RefreshTokens table is created automatically
3. Test token refresh flow end-to-end
4. Verify permission enforcement works correctly

### Short Term
1. Implement user management endpoints if needed
2. Implement company endpoints if needed
3. Add role/permission management endpoints if needed
4. Add automated tests for RBAC system

### Long Term
1. Implement token cleanup job for expired refresh tokens
2. Add rate limiting to refresh token endpoint
3. Implement concurrent session management
4. Add audit logging for role/permission changes
