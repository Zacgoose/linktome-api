# Frontend API Requirements - Backend Review & Feedback

## Summary

The frontend team's requirements document is **excellent and well-aligned** with our backend planning. Below are minor discrepancies and recommendations for alignment.

---

## ✅ Aligned Items (No Changes Needed)

### 1. Database Schema
- ✅ Users table additions match: `IsSubAccount`, `AuthDisabled`, `UserPackType`, `UserPackLimit`, `UserPackExpiresAt`
- ✅ SubAccounts table structure matches exactly
- ✅ Relationship tracking approach is identical

### 2. Permission System
- ✅ `sub_account_user` role with limited permissions is documented
- ✅ Permission exclusions match (auth, billing, user management)
- ✅ Permission-based access control approach is consistent

### 3. Authentication Blocking
- ✅ `AuthDisabled` check in login/API validation matches
- ✅ 403 error response for blocked authentication is correct

### 4. Core Architecture
- ✅ Sub-accounts as regular users with flags
- ✅ Leveraging existing permission system
- ✅ No special frontend logic needed

---

## 🔄 Minor Discrepancies to Address

### 1. Endpoint Naming Convention

**Frontend Expects**: PascalCase endpoint names
- `GET /admin/GetSubAccounts`
- `POST /admin/CreateSubAccount`
- `DELETE /admin/DeleteSubAccount`

**Backend Planning Uses**: camelCase endpoint names
- `GET /admin/getSubAccounts`
- `POST /admin/createSubAccount`
- `DELETE /admin/deleteSubAccount`

**Recommendation**: ✅ **Use PascalCase** (frontend expectation)
- Aligns with existing codebase pattern (e.g., `Invoke-AdminApikeysCreate`)
- PowerShell function naming convention uses PascalCase
- Routes should map: `/admin/GetSubAccounts` → `Invoke-AdminGetSubAccounts.ps1`

**Action Required**: Update all planning documents to use PascalCase for endpoint URLs.

---

### 2. Permission Name for Sub-Account Management

**Frontend Expects**: `manage:subaccounts` (singular)

**Backend Planning Uses**: Mixed usage
- Some docs: `create:subaccounts`, `manage:subaccounts`, `delete:subaccounts` (plural)
- Some docs: `manage:subaccounts` (singular)

**Recommendation**: ✅ **Use `manage:subaccounts`** (singular, as frontend expects)
- Single permission covers create/read/delete operations
- Simpler than three separate permissions
- Matches existing pattern (e.g., `manage:users`)

**Action Required**: 
- Update `Get-DefaultRolePermissions.ps1` code examples to use `manage:subaccounts`
- Remove references to `create:subaccounts`, `delete:subaccounts`
- Add `.ROLE` annotation: `manage:subaccounts` to all three endpoints

---

### 3. Endpoint Request/Response Field Naming

**Frontend Expects**: camelCase in JSON
```json
{
  "userId": "user-abc123",
  "displayName": "Brand One",
  "pagesCount": 2,
  "linksCount": 15,
  "createdAt": "2024-01-01T00:00:00Z"
}
```

**Backend Planning Uses**: camelCase (correct)
```json
{
  "userId": "user-abc123",
  "displayName": "Brand One"
}
```

**Recommendation**: ✅ **Already aligned** - no changes needed.

---

### 4. UserAuth Object Updates

**Frontend Expects**: `IsSubAccount` and `AuthDisabled` in auth response
```typescript
{
  "UserId": "user-123",
  "permissions": ["read:dashboard", "write:links"],
  "IsSubAccount": false,
  "AuthDisabled": false
}
```

**Backend Planning**: Not explicitly documented in auth response

**Recommendation**: ✅ **Add to JWT/Auth response documentation**
- Update JWT generation to include these optional fields
- Document in `New-LinkToMeJWT.ps1` section
- Mark as optional (only relevant for display, not authorization)

**Action Required**: Add section documenting auth response updates.

---

### 5. GET /admin/GetSubAccounts Response Structure

**Frontend Expects**: Includes `pagesCount` and `linksCount` for each sub-account
```json
{
  "subAccounts": [{
    "pagesCount": 2,
    "linksCount": 15
  }]
}
```

**Backend Planning**: Basic user info only

**Recommendation**: ✅ **Add optional counts to response**
- Query counts when returning sub-account list
- Mark as optional (can add later for performance)
- Document as "optional, may be added in future for dashboard stats"

**Action Required**: Update `Invoke-AdminGetSubAccounts` implementation to optionally include counts.

---

### 6. Tier Inheritance Implementation

**Frontend Expects**: `Get-UserSubscription.ps1` returns parent's tier for sub-accounts with inheritance flag
```powershell
$ParentSubscription.IsInherited = $true
$ParentSubscription.InheritedFromUserId = $ParentUserId
```

**Backend Planning**: Tier inheritance mentioned but not detailed

**Recommendation**: ✅ **Add detailed tier inheritance section**
- Document the recursive lookup logic
- Show `IsInherited` and `InheritedFromUserId` fields
- Include in `Get-UserSubscription.ps1` update section

**Action Required**: Add tier inheritance implementation details to backend guide.

---

### 7. DELETE Endpoint Request Format

**Frontend Sends**: Request body with `userId`
```json
{
  "userId": "user-abc123"
}
```

**Backend Planning Uses**: Query parameter
```
DELETE /admin/deleteSubAccount?userId=user-abc123
```

**Recommendation**: ✅ **Use request body** (frontend expectation)
- POST/PUT/DELETE should use request body for data
- More secure (not in URL logs)
- Consistent with other endpoints

**Action Required**: Update delete endpoint to accept request body instead of query parameter.

---

## 📝 Recommendations for Backend Implementation

### 1. Endpoint Implementations

Update endpoint names and .ROLE annotations:

```powershell
# Modules/PrivateApi/Public/Invoke-AdminGetSubAccounts.ps1
function Invoke-AdminGetSubAccounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        manage:subaccounts
    #>
    # Implementation...
}

# Modules/PrivateApi/Public/Invoke-AdminCreateSubAccount.ps1
function Invoke-AdminCreateSubAccount {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        manage:subaccounts
    #>
    # Implementation...
}

# Modules/PrivateApi/Public/Invoke-AdminDeleteSubAccount.ps1
function Invoke-AdminDeleteSubAccount {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        manage:subaccounts
    #>
    # Implementation...
}
```

### 2. Permission Updates

Update `Get-DefaultRolePermissions.ps1`:

```powershell
'user' = @(
    # All existing permissions...
    # Does NOT include 'manage:subaccounts'
)

'agency_admin_user' = @(
    # All 'user' permissions...
    'manage:subaccounts'  # Only agency admins (users with user packs)
)

'sub_account_user' = @(
    # Content management only (no manage:subaccounts)
    'read:dashboard',
    'read:profile',
    'write:profile',
    # ...
)
```

### 3. Auth Response Updates

Update `New-LinkToMeJWT.ps1` or auth response builder:

```powershell
$AuthResponse = @{
    UserId = $User.RowKey
    email = $User.PartitionKey
    username = $User.Username
    permissions = $UserPermissions
    tier = $Subscription.EffectiveTier
    # Optional fields for display
    IsSubAccount = if ($User.IsSubAccount) { $true } else { $false }
    AuthDisabled = if ($User.AuthDisabled) { $true } else { $false }
}
```

### 4. Tier Inheritance

Update `Get-UserSubscription.ps1`:

```powershell
function Get-UserSubscription {
    param([Parameter(Mandatory)][object]$User)
    
    # Check if this is a sub-account
    if ($User.IsSubAccount -eq $true) {
        # Get parent from SubAccounts table
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        $SafeSubId = Protect-TableQueryValue -Value $User.RowKey
        $Relationship = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "RowKey eq '$SafeSubId'" | Select-Object -First 1
        
        if ($Relationship) {
            $ParentUserId = $Relationship.ParentAccountId
            
            # Get parent user
            $UsersTable = Get-LinkToMeTable -TableName 'Users'
            $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
            $ParentUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeParentId'" | Select-Object -First 1
            
            if ($ParentUser) {
                # Get parent's subscription (recursive)
                $ParentSubscription = Get-UserSubscription -User $ParentUser
                
                # Mark as inherited
                $ParentSubscription | Add-Member -NotePropertyName 'IsInherited' -NotePropertyValue $true -Force
                $ParentSubscription | Add-Member -NotePropertyName 'InheritedFromUserId' -NotePropertyValue $ParentUserId -Force
                
                return $ParentSubscription
            }
        }
    }
    
    # Normal subscription logic for regular users
    # ...
}
```

---

## ✅ Action Items

### Documentation Updates Required

1. **Update endpoint URLs to PascalCase** in:
   - AGENCY_MULTI_ACCOUNT_PLANNING.md
   - BACKEND_IMPLEMENTATION_GUIDE.md
   - FRONTEND_COORDINATION_MULTI_ACCOUNT.md

2. **Consolidate permission to `manage:subaccounts`** in:
   - BACKEND_IMPLEMENTATION_GUIDE.md (Get-DefaultRolePermissions section)
   - AGENCY_MULTI_ACCOUNT_PLANNING.md (Permission System section)

3. **Add tier inheritance details** in:
   - BACKEND_IMPLEMENTATION_GUIDE.md (new section for Get-UserSubscription updates)

4. **Add auth response updates** in:
   - BACKEND_IMPLEMENTATION_GUIDE.md (JWT generation section)
   - Document optional `IsSubAccount` and `AuthDisabled` fields

5. **Update DELETE endpoint to use request body** in:
   - BACKEND_IMPLEMENTATION_GUIDE.md
   - AGENCY_MULTI_ACCOUNT_PLANNING.md

6. **Add optional counts to GET response** in:
   - BACKEND_IMPLEMENTATION_GUIDE.md (Invoke-AdminGetSubAccounts section)

---

## 🎯 Conclusion

The frontend requirements are **excellently aligned** with our backend planning. Only minor naming conventions and format adjustments needed:

**Critical Changes** (must do):
- ✅ Use PascalCase for endpoint URLs
- ✅ Use single `manage:subaccounts` permission
- ✅ DELETE endpoint accepts request body

**Recommended Changes** (should do):
- ✅ Add tier inheritance implementation details
- ✅ Add auth response optional fields
- ✅ Add optional counts to GET sub-accounts response

**Nice to Have** (can do later):
- Detailed error response examples
- Additional validation rules
- Performance optimization notes

Overall, the frontend team has done excellent work understanding the architecture and using the permission-based approach. The API contract is well-defined and ready for implementation.
