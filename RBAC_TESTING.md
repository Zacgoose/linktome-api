# RBAC System Testing Guide

This document provides manual testing procedures for the RBAC implementation.

## Prerequisites

1. Azure Functions running locally or in dev environment
2. Azure Storage Emulator or Azurite running
3. curl or Postman for API testing
4. JWT_SECRET configured in local.settings.json

## Test Scenarios

### Scenario 1: New User Signup with RBAC

**Test**: Verify new users get default role and permissions

```bash
# 1. Sign up a new user
curl -X POST http://localhost:7071/api/public/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "testuser@example.com",
    "username": "testuser",
    "password": "SecurePass123"
  }'
```

**Expected Response**:
```json
{
  "user": {
    "userId": "user-xxxxx",
    "email": "testuser@example.com",
    "username": "testuser",
    "roles": ["user"],
    "permissions": [
      "read:dashboard",
      "read:profile",
      "write:profile",
      "read:links",
      "write:links",
      "read:appearance",
      "write:appearance",
      "read:analytics"
    ]
  },
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "base64-encoded-token..."
}
```

**Verification**:
- ✅ User object contains roles array with 'user' role
- ✅ User object contains permissions array with 8 default permissions
- ✅ accessToken is present (JWT format)
- ✅ refreshToken is present (base64 string)

---

### Scenario 2: User Login with RBAC

**Test**: Verify existing users get roles and permissions on login

```bash
# 1. Login with existing user
curl -X POST http://localhost:7071/api/public/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "testuser@example.com",
    "password": "SecurePass123"
  }'
```

**Expected Response**:
```json
{
  "user": {
    "userId": "user-xxxxx",
    "email": "testuser@example.com",
    "username": "testuser",
    "roles": ["user"],
    "permissions": [...]
  },
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "base64-encoded-token..."
}
```

**Verification**:
- ✅ Response includes roles and permissions
- ✅ Both accessToken and refreshToken are present
- ✅ User can use accessToken for authenticated requests

---

### Scenario 3: Access Protected Endpoint with Valid Token

**Test**: Verify user can access endpoints they have permission for

```bash
# 1. Use accessToken from login/signup
export ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# 2. Access profile endpoint (requires read:profile permission)
curl http://localhost:7071/api/admin/getProfile \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

**Expected Response**:
```json
{
  "userId": "user-xxxxx",
  "username": "testuser",
  "email": "testuser@example.com",
  "displayName": "testuser",
  "bio": "",
  "avatar": "https://ui-avatars.com/api/?name=testuser&size=200"
}
```

**Verification**:
- ✅ Request succeeds with 200 OK
- ✅ Profile data is returned
- ✅ No permission errors

---

### Scenario 4: Permission Enforcement - Forbidden Access

**Test**: Verify users cannot access endpoints without required permissions

```bash
# 1. Try to access admin user management endpoint
# (requires read:users permission, which 'user' role doesn't have)
curl http://localhost:7071/api/admin/getUsers \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

**Expected Response**:
```json
{
  "success": false,
  "error": "Forbidden: Insufficient permissions. Required: read:users"
}
```

**HTTP Status**: 403 Forbidden

**Verification**:
- ✅ Request is rejected with 403 status
- ✅ Error message indicates which permission is required
- ✅ Security event is logged (check SecurityEvents table)

---

### Scenario 5: Token Refresh Flow

**Test**: Verify token refresh works and rotates tokens

```bash
# 1. Save refresh token from login/signup
export REFRESH_TOKEN="base64-encoded-token..."

# 2. Wait 1 minute (or modify JWT expiration for faster testing)

# 3. Refresh the token
curl -X POST http://localhost:7071/api/public/refreshToken \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\": \"$REFRESH_TOKEN\"}"
```

**Expected Response**:
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "new-base64-encoded-token..."
}
```

**Verification**:
- ✅ New accessToken is returned
- ✅ New refreshToken is returned (different from original)
- ✅ New accessToken works for authenticated requests
- ✅ Old refreshToken no longer works (next test)

---

### Scenario 6: Token Rotation - Old Token Invalid

**Test**: Verify old refresh tokens are invalidated after refresh

```bash
# 1. Try to use the OLD refresh token again
curl -X POST http://localhost:7071/api/public/refreshToken \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\": \"$REFRESH_TOKEN\"}"
```

**Expected Response**:
```json
{
  "success": false,
  "error": "Invalid or expired refresh token"
}
```

**HTTP Status**: 401 Unauthorized

**Verification**:
- ✅ Request is rejected with 401 status
- ✅ Error indicates invalid/expired token
- ✅ Security event is logged

---

### Scenario 7: Logout Flow

**Test**: Verify logout invalidates refresh token

```bash
# 1. Use the NEW refresh token from scenario 5
export NEW_REFRESH_TOKEN="new-base64-encoded-token..."

# 2. Logout
curl -X POST http://localhost:7071/api/public/logout \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\": \"$NEW_REFRESH_TOKEN\"}"
```

**Expected Response**:
```json
{
  "success": true
}
```

**Verification**:
- ✅ Logout succeeds with 200 OK
- ✅ Response indicates success

```bash
# 3. Try to use logged out refresh token
curl -X POST http://localhost:7071/api/public/refreshToken \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\": \"$NEW_REFRESH_TOKEN\"}"
```

**Expected**: 401 Unauthorized - Token is invalid

---

### Scenario 8: Access Token Expiration

**Test**: Verify access tokens expire after 15 minutes

```bash
# 1. Get access token from login
export ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# 2. Use immediately (should work)
curl http://localhost:7071/api/admin/getProfile \
  -H "Authorization: Bearer $ACCESS_TOKEN"
# Expected: 200 OK

# 3. Wait 16 minutes (or decode JWT to verify exp claim)

# 4. Try to use expired token
curl http://localhost:7071/api/admin/getProfile \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

**Expected Response**:
```json
{
  "success": false,
  "error": "Unauthorized: Invalid or expired token"
}
```

**HTTP Status**: 401 Unauthorized

**Verification**:
- ✅ Expired token is rejected
- ✅ User must use refresh token to get new access token

---

### Scenario 9: JWT Claims Validation

**Test**: Verify JWT contains all required claims

```bash
# 1. Decode JWT token (use jwt.io or jwt-cli)
echo "$ACCESS_TOKEN" | jwt decode -

# Or use online tool: https://jwt.io/
```

**Expected Claims**:
```json
{
  "sub": "user-xxxxx",
  "email": "testuser@example.com",
  "username": "testuser",
  "roles": ["user"],
  "permissions": [
    "read:dashboard",
    "read:profile",
    "write:profile",
    "read:links",
    "write:links",
    "read:appearance",
    "write:appearance",
    "read:analytics"
  ],
  "iat": 1234567890,
  "exp": 1234568790,
  "iss": "LinkTome-app"
}
```

**Verification**:
- ✅ JWT contains sub (userId)
- ✅ JWT contains email
- ✅ JWT contains username
- ✅ JWT contains roles array
- ✅ JWT contains permissions array
- ✅ JWT contains iat (issued at)
- ✅ JWT contains exp (expiration) - should be iat + 900 seconds (15 minutes)
- ✅ JWT contains iss (issuer)

---

### Scenario 10: Admin User Permissions

**Test**: Verify admin users can access user management endpoints

**Setup**: Manually update user in Azure Tables
```
1. Open Azure Portal or Storage Explorer
2. Navigate to Users table
3. Find test user
4. Add property: Roles = ["admin"]
5. Add property: Permissions = ["read:dashboard","read:profile","write:profile","read:links","write:links","read:appearance","write:appearance","read:analytics","read:users","write:users","manage:users"]
6. Save
```

```bash
# 1. Login again to get new JWT with admin role
curl -X POST http://localhost:7071/api/public/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "testuser@example.com",
    "password": "SecurePass123"
  }'

# 2. Extract new accessToken
export ADMIN_ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# 3. Try to access user management endpoint
curl http://localhost:7071/api/admin/getUsers \
  -H "Authorization: Bearer $ADMIN_ACCESS_TOKEN"
```

**Expected**: 
- If endpoint exists: 200 OK with user list
- If endpoint not implemented: 404 Not Found (but NOT 403 Forbidden)

**Verification**:
- ✅ Admin user is NOT blocked by permission check
- ✅ JWT contains admin role and additional permissions

---

## Database Verification

### Check RefreshTokens Table

```bash
# Using Azure Storage Explorer or Portal
1. Open Azure Storage Explorer
2. Connect to local storage emulator
3. Navigate to Tables → RefreshTokens
4. Verify table exists and contains entries after login/signup
```

**Expected Data**:
- PartitionKey: The actual refresh token value
- RowKey: A GUID
- UserId: The user's ID
- ExpiresAt: Timestamp 7 days in future
- CreatedAt: Current timestamp
- IsValid: true (false after logout/refresh)

### Check Users Table

```bash
# Verify users have roles and permissions
1. Open Azure Storage Explorer
2. Navigate to Tables → Users
3. Find a user created after RBAC implementation
4. Verify properties exist:
   - Roles: ["user"]
   - Permissions: [array of 8 permissions]
```

---

## Security Events Verification

### Check Security Events Table

```bash
# Verify security events are logged
1. Open Azure Storage Explorer
2. Navigate to Tables → SecurityEvents
3. Look for new event types:
   - TokenRefreshed
   - RefreshTokenFailed
   - Logout
   - PermissionDenied
```

**Expected Events**:
- PermissionDenied: When user tries to access endpoint without permission
- RefreshTokenFailed: When invalid/expired refresh token is used
- TokenRefreshed: When token is successfully refreshed
- Logout: When user logs out

---

## Troubleshooting

### Issue: "Function not found" errors
**Solution**: Ensure all new functions are being loaded by the module system
- Check that files are in correct directories
- Verify module exports include new functions
- Restart function app

### Issue: RefreshTokens table doesn't exist
**Solution**: Table is created automatically on first use
- Try signup or login once
- Check Azure Storage Explorer
- Verify AzureWebJobsStorage connection string is correct

### Issue: Permissions not enforced
**Solution**: Check endpoint mapping
- Verify endpoint name matches exactly in Get-EndpointPermissions
- Check router is calling Test-UserPermission
- Verify JWT contains permissions claim

### Issue: JWT doesn't contain new claims
**Solution**: Need to login/signup again
- Old JWTs don't have new claims
- User must get new token via login or refresh
- Or manually update JWT generation code

### Issue: "Insufficient permissions" for basic endpoints
**Solution**: Check user has correct default permissions
- Verify signup assigns permissions correctly
- Check Users table for Roles and Permissions properties
- Verify Get-DefaultRolePermissions returns correct permissions

---

## Testing Checklist

- [ ] New user signup returns roles and permissions
- [ ] Login returns refresh token
- [ ] Access token expires after 15 minutes (or verify exp claim)
- [ ] Refresh token generates new tokens
- [ ] Old refresh tokens are invalidated after refresh
- [ ] Logout invalidates refresh tokens
- [ ] Users can access endpoints they have permission for
- [ ] Users get 403 for endpoints they lack permission for
- [ ] JWT contains all required claims
- [ ] RefreshTokens table is created and populated
- [ ] Users table stores roles and permissions
- [ ] Security events are logged correctly
- [ ] Admin users can access admin endpoints
- [ ] Permission errors include which permission is required

---

## Performance Testing

### Recommended Tests
1. **Token Refresh Load**: 100 concurrent refresh requests
2. **Permission Check Speed**: Measure overhead of permission checking
3. **Table Query Performance**: Check RefreshTokens lookup speed
4. **JWT Decode Speed**: Measure JWT validation overhead

### Expected Performance
- Token refresh: < 500ms
- Permission check: < 10ms (in-memory)
- Table query: < 100ms
- JWT decode: < 50ms

---

## Next Steps After Testing

1. **If all tests pass**:
   - Mark implementation as complete
   - Update documentation
   - Prepare for frontend integration

2. **If tests fail**:
   - Document failures
   - Debug and fix issues
   - Re-test

3. **Additional features** (if requested):
   - Implement user management endpoints
   - Implement company endpoints
   - Add role/permission management API
   - Add automated tests

---

## Scenario 11: Assign Role to User (MVP Feature)

**Test**: Verify admin/company_owner can assign roles to users

**Setup**: Need users with admin or company_owner role

```bash
# 1. Login as admin user
curl -X POST http://localhost:7071/api/public/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "AdminPass123"
  }'

# Extract admin access token
export ADMIN_TOKEN="eyJ..."

# 2. Assign admin role to a user
curl -X PUT http://localhost:7071/api/admin/assignRole \
  -H "Authorization: ******" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user-xxxxx",
    "role": "admin"
  }'
```

**Expected Response**:
```json
{
  "success": true,
  "userId": "user-xxxxx",
  "role": "admin",
  "permissions": [
    "read:dashboard",
    "read:profile",
    "write:profile",
    "read:links",
    "write:links",
    "read:appearance",
    "write:appearance",
    "read:analytics",
    "read:users",
    "write:users",
    "manage:users"
  ]
}
```

**Verification**:
- ✅ Request succeeds with 200 OK
- ✅ User role is updated in database
- ✅ User permissions are automatically updated based on role
- ✅ Security event logged for role assignment

---

## Scenario 12: Get User Roles and Permissions

**Test**: Verify admin/company_owner can view user roles and permissions

```bash
# 1. Get roles for a specific user
curl "http://localhost:7071/api/admin/getUserRoles?userId=user-xxxxx" \
  -H "Authorization: ******"
```

**Expected Response**:
```json
{
  "success": true,
  "userId": "user-xxxxx",
  "username": "testuser",
  "email": "testuser@example.com",
  "roles": ["admin"],
  "permissions": [
    "read:dashboard",
    "read:profile",
    "write:profile",
    "read:links",
    "write:links",
    "read:appearance",
    "write:appearance",
    "read:analytics",
    "read:users",
    "write:users",
    "manage:users"
  ],
  "companyId": null
}
```

**Verification**:
- ✅ Request succeeds with 200 OK
- ✅ Returns current roles and permissions
- ✅ Includes company information if applicable

---

## Scenario 13: Company Owner Access Control

**Test**: Verify company_owner can only manage users in their company

**Setup**: Need two users with company_owner role in different companies

```bash
# 1. Login as company_owner
curl -X POST http://localhost:7071/api/public/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "owner1@company1.com",
    "password": "Pass123"
  }'

export OWNER1_TOKEN="eyJ..."

# 2. Try to view user from different company
curl "http://localhost:7071/api/admin/getUserRoles?userId=user-from-company2" \
  -H "Authorization: ******"
```

**Expected Response**:
```json
{
  "success": false,
  "error": "Company owners can only view users in their own company"
}
```

**HTTP Status**: 403 Forbidden

**Verification**:
- ✅ Request is rejected with 403 status
- ✅ Company_owner cannot view users from other companies
- ✅ Company_owner cannot assign roles to users from other companies

---

## Scenario 14: Invalid Role Assignment

**Test**: Verify system rejects invalid role values

```bash
# Try to assign invalid role
curl -X PUT http://localhost:7071/api/admin/assignRole \
  -H "Authorization: ******" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user-xxxxx",
    "role": "superadmin"
  }'
```

**Expected Response**:
```json
{
  "success": false,
  "error": "Invalid role. Allowed roles: user, admin, company_owner"
}
```

**HTTP Status**: 400 Bad Request

**Verification**:
- ✅ Request is rejected with 400 status
- ✅ Only valid roles are accepted
- ✅ User's role remains unchanged

---

## Updated Testing Checklist

- [ ] New user signup returns roles and permissions
- [ ] Login returns refresh token
- [ ] Access token expires after 15 minutes (or verify exp claim)
- [ ] Refresh token generates new tokens
- [ ] Old refresh tokens are invalidated after refresh
- [ ] Logout invalidates refresh tokens
- [ ] Users can access endpoints they have permission for
- [ ] Users get 403 for endpoints they lack permission for
- [ ] JWT contains all required claims
- [ ] RefreshTokens table is created and populated
- [ ] Users table stores roles and permissions
- [ ] Security events are logged correctly
- [ ] Admin users can access admin endpoints
- [ ] Permission errors include which permission is required
- [ ] **Admin can assign roles to users**
- [ ] **Company_owner can assign roles to their company's users**
- [ ] **Admin can view user roles and permissions**
- [ ] **Company_owner can only manage their own company's users**
- [ ] **Invalid roles are rejected**
