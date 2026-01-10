# Multi-Page Feature Testing Guide

This guide provides comprehensive test scenarios for the multi-page feature implementation.

## Prerequisites

1. Start Azure Functions locally:
   ```bash
   func start
   ```

2. Ensure Azurite or Azure Storage Emulator is running

3. Have a test user account created with JWT token

## Test Scenarios

### 1. Default Page Auto-Creation

**Scenario**: Existing user accesses pages for the first time

**Steps**:
1. Create a new user account (or use existing)
2. Add some links using `/admin/updateLinks` (without pageId)
3. Call `/admin/getPages`

**Expected Result**:
- User automatically gets a default page with slug "main" and name "Main Links"
- All existing links are migrated to this default page
- Response includes one page with `isDefault: true`

**Test Command**:
```bash
# Get pages (triggers auto-creation)
curl http://localhost:7071/api/admin/getPages \
  -H "Authorization: Bearer $TOKEN"
```

### 2. Create Page - Free Tier Limit

**Scenario**: Free tier user tries to create more than 1 page

**Steps**:
1. Login as free tier user
2. Get current pages (should have 1 default page)
3. Try to create a second page

**Expected Result**:
- First page creation succeeds
- Second page creation fails with 403 Forbidden
- Error message: "Page limit reached for your tier..."

**Test Commands**:
```bash
# This should fail for free tier
curl -X POST http://localhost:7071/api/admin/createPage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug":"music","name":"Music Links"}'
```

### 3. Create Page - Pro Tier

**Scenario**: Pro tier user creates multiple pages

**Steps**:
1. Login as pro tier user
2. Create pages with different slugs
3. Verify all pages are listed

**Expected Result**:
- Can create up to 3 pages
- Each page has unique slug
- Pages are returned sorted by isDefault, then createdAt

**Test Commands**:
```bash
# Create first page
curl -X POST http://localhost:7071/api/admin/createPage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug":"music","name":"Music Links"}'

# Create second page
curl -X POST http://localhost:7071/api/admin/createPage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug":"business","name":"Business Links"}'

# List all pages
curl http://localhost:7071/api/admin/getPages \
  -H "Authorization: Bearer $TOKEN"
```

### 4. Slug Validation

**Scenario**: Test slug format validation

**Test Cases**:

**Valid slugs**:
- `music` ✓
- `my-music` ✓
- `music123` ✓
- `abc` (minimum 3 chars) ✓

**Invalid slugs**:
- `ab` (too short) ✗
- `Music` (uppercase) ✗
- `-music` (starts with hyphen) ✗
- `music-` (ends with hyphen) ✗
- `my--music` (consecutive hyphens) ✗
- `admin` (reserved) ✗
- `api` (reserved) ✗
- `my music` (space) ✗
- `my_music` (underscore) ✗

**Test Command**:
```bash
# Test invalid slug (should fail)
curl -X POST http://localhost:7071/api/admin/createPage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug":"admin","name":"Admin Page"}'
```

### 5. Update Page

**Scenario**: Update page slug, name, and default status

**Steps**:
1. Create a page
2. Update its slug
3. Update its name
4. Set it as default

**Expected Result**:
- Slug changes successfully (if unique)
- Name updates
- When setting as default, previous default is unset
- Only one page has isDefault: true

**Test Commands**:
```bash
# Get page ID from list
PAGE_ID="<copy-from-response>"

# Update slug
curl -X PUT http://localhost:7071/api/admin/updatePage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"'$PAGE_ID'","slug":"my-music"}'

# Update name
curl -X PUT http://localhost:7071/api/admin/updatePage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"'$PAGE_ID'","name":"My Music Collection"}'

# Set as default
curl -X PUT http://localhost:7071/api/admin/updatePage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"'$PAGE_ID'","isDefault":true}'
```

### 6. Delete Page

**Scenario**: Delete a non-default page

**Steps**:
1. Create multiple pages
2. Try to delete the default page (should fail)
3. Delete a non-default page (should succeed)

**Expected Result**:
- Cannot delete default page (400 error)
- Can delete non-default pages
- All links and groups on deleted page are removed

**Test Commands**:
```bash
# Try to delete default page (should fail)
curl -X DELETE "http://localhost:7071/api/admin/deletePage?id=$DEFAULT_PAGE_ID" \
  -H "Authorization: Bearer $TOKEN"

# Delete non-default page (should succeed)
curl -X DELETE "http://localhost:7071/api/admin/deletePage?id=$PAGE_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### 7. Links Per Page

**Scenario**: Add links to specific pages

**Steps**:
1. Create two pages
2. Add links to first page
3. Add links to second page
4. Get links for each page separately

**Expected Result**:
- Links are isolated per page
- Each page returns only its own links
- Links include PageId in response

**Test Commands**:
```bash
# Add links to first page
curl -X PUT "http://localhost:7071/api/admin/updateLinks?pageId=$PAGE1_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"links":[{"operation":"add","title":"GitHub","url":"https://github.com/user"}]}'

# Add links to second page
curl -X PUT "http://localhost:7071/api/admin/updateLinks?pageId=$PAGE2_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"links":[{"operation":"add","title":"Twitter","url":"https://twitter.com/user"}]}'

# Get links for first page
curl "http://localhost:7071/api/admin/getLinks?pageId=$PAGE1_ID" \
  -H "Authorization: Bearer $TOKEN"

# Get links for second page
curl "http://localhost:7071/api/admin/getLinks?pageId=$PAGE2_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### 8. Public Profile with Slug

**Scenario**: Access different pages via public URL

**Steps**:
1. Create user with multiple pages
2. Add different links to each page
3. Access public profile without slug (should show default)
4. Access public profile with specific slug

**Expected Result**:
- Without slug: Shows default page
- With slug: Shows specified page
- Each page shows only its own links and groups
- Invalid slug returns 404

**Test Commands**:
```bash
# Default page
curl "http://localhost:7071/api/public/getUserProfile?username=testuser"

# Specific page
curl "http://localhost:7071/api/public/getUserProfile?username=testuser&slug=music"

# Invalid slug (should return 404)
curl "http://localhost:7071/api/public/getUserProfile?username=testuser&slug=nonexistent"
```

### 9. Default Page Behavior

**Scenario**: Test default page handling

**Steps**:
1. Create user (gets default page auto-created)
2. Create second page and set as default
3. Verify old default is no longer default

**Expected Result**:
- Only one page is default at any time
- Setting new default unsets previous default
- Admin endpoints without pageId use default page

**Test Commands**:
```bash
# Get pages - should show one default
curl http://localhost:7071/api/admin/getPages \
  -H "Authorization: Bearer $TOKEN"

# Create new page as default
curl -X POST http://localhost:7071/api/admin/createPage \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug":"new-default","name":"New Default","isDefault":true}'

# Get pages - should show new default, old one not default
curl http://localhost:7071/api/admin/getPages \
  -H "Authorization: Bearer $TOKEN"
```

### 10. Groups Per Page

**Scenario**: Add link groups to specific pages

**Steps**:
1. Create page
2. Add groups to page
3. Add links to those groups
4. Verify groups are isolated per page

**Expected Result**:
- Groups are specific to pages
- Links in groups show correct groupId
- Different pages can have groups with same name

**Test Commands**:
```bash
# Add group to page
curl -X PUT "http://localhost:7071/api/admin/updateLinks?pageId=$PAGE_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"groups":[{"operation":"add","title":"Social Media"}]}'

# Get groups for page
curl "http://localhost:7071/api/admin/getLinks?pageId=$PAGE_ID" \
  -H "Authorization: Bearer $TOKEN"
```

## Test Data Setup

### Create Test Users

```bash
# Free tier user
curl -X POST http://localhost:7071/api/public/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "free@test.com",
    "username": "freeuser",
    "password": "TestPass123"
  }'

# Pro tier user (you'll need to manually update SubscriptionTier in DB)
curl -X POST http://localhost:7071/api/public/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "pro@test.com",
    "username": "prouser",
    "password": "TestPass123"
  }'
```

### Update User Tier (via Azure Storage Explorer)

1. Open Azure Storage Explorer
2. Connect to local storage
3. Navigate to Users table
4. Find user by email
5. Update `SubscriptionTier` to `pro` or `premium`

## Verification Checklist

- [ ] Default page auto-created for existing users
- [ ] Free tier limited to 1 page
- [ ] Pro tier can create up to 3 pages
- [ ] Premium tier can create up to 10 pages
- [ ] Slug validation works correctly
- [ ] Cannot create duplicate slugs
- [ ] Cannot delete default page
- [ ] Links isolated per page
- [ ] Groups isolated per page
- [ ] Public profile shows correct page by slug
- [ ] Default page shown when no slug specified
- [ ] Only one page can be default
- [ ] Setting new default unsets old default
- [ ] Page updates work correctly
- [ ] Page deletion removes associated links and groups

## Performance Considerations

When testing with large datasets:
1. Create user with many pages (premium/enterprise tier)
2. Add many links per page
3. Verify queries remain performant
4. Check Azure Storage metrics for table scans

## Security Testing

1. Attempt to access another user's pages (should fail)
2. Attempt to delete another user's page (should fail)
3. Test SQL injection in slug field (should be sanitized)
4. Test XSS in page name (should be sanitized by frontend)
5. Verify tier limits are enforced
6. Test rate limiting on page creation

## Troubleshooting

### Issue: "Table not found" error
**Solution**: Ensure Azure Storage Emulator/Azurite is running

### Issue: "Page limit reached" but user has no pages
**Solution**: Check user's SubscriptionTier field in Users table

### Issue: Links not showing on public profile
**Solution**: Verify PageId matches between Links and Pages tables

### Issue: Multiple default pages
**Solution**: This shouldn't happen, but if it does, manually fix in storage
