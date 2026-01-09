# Multi-Page API Implementation

This document describes the multi-page feature implementation for LinkToMe API.

## Overview

The multi-page feature allows users to create multiple link pages, each with its own slug, name, and links. The number of pages a user can create is limited by their subscription tier.

## Tier Limits

| Tier | Max Pages |
|------|-----------|
| Free | 1 |
| Pro | 3 |
| Premium | 10 |
| Enterprise | Unlimited |

## New Tables

### Pages Table
- **PartitionKey**: UserId
- **RowKey**: PageId (GUID)
- **Columns**: Slug, Name, IsDefault, CreatedAt, UpdatedAt

### Updated Tables
The following tables now include a `PageId` column (nullable):
- Links
- LinkGroups

## New API Endpoints

### 1. GET /admin/getPages
List all pages for the authenticated user.

**Authentication**: Required (JWT/API Key)

**Response**:
```json
{
  "pages": [
    {
      "id": "guid-1",
      "userId": "user-guid",
      "slug": "main",
      "name": "Main Links",
      "isDefault": true,
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z"
    }
  ]
}
```

### 2. POST /admin/createPage
Create a new page.

**Authentication**: Required (JWT/API Key)

**Request Body**:
```json
{
  "slug": "music",
  "name": "Music Links",
  "isDefault": false
}
```

**Validation**:
- Slug must be 3-30 characters, lowercase letters, numbers, hyphens only
- Slug cannot start/end with hyphen or contain consecutive hyphens
- Slug must be unique per user
- Reserved slugs: admin, api, public, login, signup, settings, v1
- Respects tier page limits

**Response**:
```json
{
  "message": "Page created successfully",
  "page": {
    "id": "new-guid",
    "userId": "user-guid",
    "slug": "music",
    "name": "Music Links",
    "isDefault": false,
    "createdAt": "2024-01-02T00:00:00Z",
    "updatedAt": "2024-01-02T00:00:00Z"
  }
}
```

### 3. PUT /admin/updatePage
Update an existing page.

**Authentication**: Required (JWT/API Key)

**Request Body**:
```json
{
  "id": "page-guid",
  "slug": "music-updated",
  "name": "Music & Concerts",
  "isDefault": true
}
```

**Response**:
```json
{
  "message": "Page updated successfully"
}
```

### 4. DELETE /admin/deletePage
Delete a page and all associated links and groups.

**Authentication**: Required (JWT/API Key)

**Query Parameters**:
- `id` (required): Page ID to delete

**Validation**:
- Cannot delete the default page

**Response**:
```json
{
  "message": "Page deleted successfully"
}
```

## Updated Endpoints

### GET /admin/getLinks
Now supports optional `pageId` query parameter.

**Query Parameters**:
- `pageId` (optional): Filter links by page ID. If not provided, returns links for default page.

### PUT /admin/updateLinks
Now supports optional `pageId` query parameter for context when adding new links.

**Query Parameters**:
- `pageId` (optional): Page context for new links. If not provided, uses default page.

**Note**: New links and groups are automatically assigned to the specified page.

### GET /public/getUserProfile
Now supports optional `slug` query parameter to display a specific page.

**Query Parameters**:
- `username` (required): Username to look up
- `slug` (optional): Page slug. If not provided, returns default page.

**Example URLs**:
- `https://api.linktome.com/public/getUserProfile?username=johndoe` - Default page
- `https://api.linktome.com/public/getUserProfile?username=johndoe&slug=music` - Music page

## Migration & Backward Compatibility

### Automatic Migration
When a user logs in or accesses any page-related endpoint for the first time:
1. The system checks if the user has any pages
2. If not, it creates a default page with slug "main" and name "Main Links"
3. All existing links and groups without a PageId are automatically migrated to this default page

### Default Page Behavior
- If no `pageId` is specified in admin endpoints, the default page is used
- If no `slug` is specified in public profile, the default page is shown
- Users always have at least one page (the default page)

## Permissions

New permissions added:
- `read:pages` - View pages
- `write:pages` - Create, update, delete pages

These permissions are included by default in:
- `user` role
- `user_manager` role

## Error Responses

| Status Code | Description |
|-------------|-------------|
| 400 | Bad Request - Invalid input, validation error |
| 401 | Unauthorized - Missing or invalid authentication |
| 403 | Forbidden - Tier restriction (e.g., page limit reached) |
| 404 | Not Found - Page or user not found |
| 500 | Internal Server Error |

## Testing

### Create a Page
```bash
curl -X POST http://localhost:7071/api/admin/createPage \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{"slug":"music","name":"Music Links"}'
```

### List Pages
```bash
curl http://localhost:7071/api/admin/getPages \
  -H "Authorization: Bearer <jwt-token>"
```

### Get Links for Specific Page
```bash
curl "http://localhost:7071/api/admin/getLinks?pageId=<page-guid>" \
  -H "Authorization: Bearer <jwt-token>"
```

### View Public Profile with Slug
```bash
curl "http://localhost:7071/api/public/getUserProfile?username=johndoe&slug=music"
```

## Implementation Notes

1. **Appearance Settings**: Currently, appearance settings remain at the user level and are shared across all pages. Per-page appearance can be added in a future iteration if needed.

2. **Analytics**: The Analytics table structure remains unchanged. Future enhancements could add PageId tracking for per-page analytics.

3. **Slug Validation**: Slugs are validated on creation and update to ensure they meet format requirements and are unique per user.

4. **Default Page Protection**: The default page cannot be deleted to ensure users always have at least one page.

5. **Tier Enforcement**: Page creation enforces tier limits, with appropriate error messages and feature usage tracking.
