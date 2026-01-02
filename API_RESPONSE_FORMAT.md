# LinkToMe API Response Format - Standardization Guide

## Overview

The LinkToMe API has been standardized to use a consistent, RESTful response format across all endpoints. This document outlines the new format for frontend integration.

## Response Format

### Success Responses

**HTTP Status Code**: 2xx (200, 201, 204)  
**Body**: Contains the requested data directly, without wrapper objects

```json
// User profile
{
  "UserId": "user-123",
  "username": "john",
  "email": "john@example.com",
  "displayName": "John Doe"
}

// List of links
{
  "links": [
    { "id": "1", "title": "GitHub", "url": "https://github.com/..." },
    { "id": "2", "title": "Twitter", "url": "https://twitter.com/..." }
  ]
}

// User data with nested object
{
  "user": {
    "UserId": "user-123",
    "username": "john",
    "email": "john@example.com",
    "roles": ["user"],
    "permissions": ["read:profile", "write:profile"]
  }
}
```

**No `success` flag** - HTTP status code indicates success

### Error Responses

**HTTP Status Code**: 4xx or 5xx  
**Body**: Contains a single `error` field with the error message

```json
{
  "error": "Error message here"
}
```

## Status Codes

| Code | Meaning | Usage |
|------|---------|-------|
| 200 | OK | Successful GET, PUT, PATCH |
| 201 | Created | Successful POST that creates a resource |
| 204 | No Content | Successful DELETE or action with no return data |
| 400 | Bad Request | Invalid input, missing required fields |
| 401 | Unauthorized | Missing, invalid, or expired authentication |
| 403 | Forbidden | Authenticated but lacks required permissions |
| 404 | Not Found | Resource doesn't exist |
| 500 | Internal Server Error | Server-side error |

## Frontend Integration

### Example: Handling Responses

```javascript
async function fetchProfile() {
  try {
    const response = await fetch('/api/admin/GetProfile', {
      method: 'GET',
      credentials: 'include', // Important: sends cookies
      headers: {
        'Content-Type': 'application/json'
      }
    });

    // Check HTTP status code
    if (!response.ok) {
      // Parse error message
      const errorData = await response.json();
      throw new Error(errorData.error || 'Request failed');
    }

    // Parse success data
    const data = await response.json();
    return data; // Direct access to fields like data.UserId, data.username, etc.
    
  } catch (error) {
    console.error('Failed to fetch profile:', error.message);
    throw error;
  }
}
```

### Example: Error Handling Pattern

```javascript
// Generic API call wrapper
async function apiCall(url, options = {}) {
  const defaultOptions = {
    credentials: 'include', // Always include cookies
    headers: {
      'Content-Type': 'application/json',
      ...options.headers
    }
  };

  const response = await fetch(url, { ...defaultOptions, ...options });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({ error: 'Unknown error' }));
    const error = new Error(errorData.error || `HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }

  // For 204 No Content, don't try to parse JSON
  if (response.status === 204) {
    return null;
  }

  return response.json();
}

// Usage
try {
  const profile = await apiCall('/api/admin/GetProfile');
  console.log(profile.username); // Direct field access
} catch (error) {
  if (error.status === 401) {
    // Redirect to login
    window.location.href = '/login';
  } else {
    // Show error message
    showErrorToast(error.message);
  }
}
```

## Migration Notes

### Changes from Previous Format

**Before**: Responses sometimes included `success` flag
```json
{
  "success": false,
  "error": "Missing auth cookie"
}
```

**After**: Use HTTP status code instead
```json
{
  "error": "Missing auth cookie"
}
```
*Status code: 400*

### Removed Fields

- `success` boolean - **Use HTTP status code instead**
- No more mixed formats - all errors use simple `{ "error": "..." }`

### What Stayed the Same

- Success responses still return data directly
- Cookie-based authentication unchanged
- Endpoint URLs unchanged

## Authentication Responses

### Login / Signup

**Success (200)**:
```json
{
  "user": {
    "UserId": "user-123",
    "email": "user@example.com",
    "username": "username",
    "userRole": "user",
    "roles": ["user"],
    "permissions": ["read:profile", "write:profile"],
    "userManagements": [],
    "subscriptionTier": "free",
    "subscriptionStatus": "active",
    "tierFeatures": ["basic_profile", "basic_links", "basic_analytics", "basic_appearance"],
    "tierLimits": {
      "maxLinks": 5,
      "analyticsRetentionDays": 30,
      "customThemes": false,
      "advancedAnalytics": false,
      "apiAccess": false,
      "customDomain": false,
      "prioritySupport": false
    }
  }
}
```
*Cookies set automatically in response headers*

**Error (401)**:
```json
{
  "error": "Invalid credentials"
}
```

### Refresh Token

**Success (200)**:
```json
{
  "user": {
    "UserId": "user-123",
    "email": "user@example.com",
    "username": "username",
    "userRole": "user",
    "roles": ["user"],
    "permissions": ["read:profile", "write:profile"],
    "userManagements": [],
    "subscriptionTier": "free",
    "subscriptionStatus": "active",
    "tierFeatures": ["basic_profile", "basic_links", "basic_analytics", "basic_appearance"],
    "tierLimits": {
      "maxLinks": 5,
      "analyticsRetentionDays": 30,
      "customThemes": false,
      "advancedAnalytics": false
    }
  }
}
```
*New tokens set automatically in cookies*

**Error (400/401)**:
```json
{
  "error": "Invalid or expired refresh token"
}
```

### Logout

**Success (200)**:
```json
{}
```
*Or empty body - cookie cleared in response headers*

## Common Endpoints

### GET /api/admin/GetProfile
**Success (200)**:
```json
{
  "UserId": "user-123",
  "username": "john",
  "email": "john@example.com",
  "displayName": "John Doe",
  "bio": "Developer",
  "avatar": "https://example.com/avatar.jpg"
}
```

### GET /api/admin/GetLinks
**Success (200)**:
```json
{
  "links": [
    {
      "id": "link-1",
      "title": "GitHub",
      "url": "https://github.com/user",
      "order": 0,
      "active": true,
      "icon": "github"
    }
  ]
}
```

### PUT /api/admin/UpdateProfile
**Success (200)**:
```json
{
  "UserId": "user-123",
  "username": "john",
  "email": "john@example.com",
  "displayName": "John Updated",
  "bio": "Updated bio",
  "avatar": "https://example.com/new-avatar.jpg"
}
```

**Error (400)**:
```json
{
  "error": "Display name exceeds maximum length of 100 characters"
}
```

## Benefits of Standardization

1. **Simpler Client Code**: No need to check `success` flag - just use try/catch with HTTP status
2. **RESTful**: Follows HTTP standards and best practices
3. **Consistent**: Same pattern across all endpoints
4. **Type-Safe**: Easier to create TypeScript interfaces
5. **Less Bandwidth**: Smaller response payloads (no redundant success flags)

## TypeScript Types (Suggested)

```typescript
// Generic API response handler
interface ApiError {
  error: string;
}

// Success responses
interface User {
  UserId: string;
  username: string;
  email: string;
  displayName?: string;
  bio?: string;
  avatar?: string;
}

interface Link {
  id: string;
  title: string;
  url: string;
  order: number;
  active: boolean;
  icon?: string;
}

interface LoginResponse {
  user: {
    UserId: string;
    email: string;
    username: string;
    userRole: string;
    roles: string[];
    permissions: string[];
    userManagements: any[];
  };
}

interface LinksResponse {
  links: Link[];
}
```

## Subscription Tier Responses

### Tier-Gated Feature Responses

When a user tries to access a premium feature without the required subscription tier, the response includes tier information:

#### Analytics Endpoint (Free Tier)
**Success (200)** - Limited data with upgrade message:
```json
{
  "summary": {
    "totalPageViews": 150,
    "totalLinkClicks": 45,
    "uniqueVisitors": 30
  },
  "hasAdvancedAnalytics": false,
  "upgradeMessage": "Upgrade to Premium to unlock detailed analytics including visitor details, click patterns, and historical trends.",
  "recentPageViews": [],
  "recentLinkClicks": [],
  "linkClicksByLink": [],
  "viewsByDay": [],
  "clicksByDay": []
}
```

#### Analytics Endpoint (Premium/Enterprise Tier)
**Success (200)** - Full data:
```json
{
  "summary": {
    "totalPageViews": 150,
    "totalLinkClicks": 45,
    "uniqueVisitors": 30
  },
  "hasAdvancedAnalytics": true,
  "recentPageViews": [...],
  "recentLinkClicks": [...],
  "linkClicksByLink": [...],
  "viewsByDay": [...],
  "clicksByDay": [...]
}
```

#### Links Endpoint (Limit Exceeded)
**Error (403)** - Tier limit exceeded:
```json
{
  "error": "Link limit exceeded. Your Free plan allows up to 5 links. You currently have 5 links.",
  "currentTier": "free",
  "maxLinks": 5,
  "currentLinks": 5,
  "upgradeRequired": true
}
```

### Tier Information in User Object

All authentication endpoints now include tier information in the user object:
```typescript
interface User {
  UserId: string;
  email: string;
  username: string;
  userRole: string;
  roles: string[];
  permissions: string[];
  userManagements: any[];
  subscriptionTier: 'free' | 'premium' | 'enterprise';
  subscriptionStatus: 'active' | 'trial' | 'expired';
  tierFeatures: string[];
  tierLimits: {
    maxLinks: number;
    analyticsRetentionDays: number;
    customThemes: boolean;
    advancedAnalytics: boolean;
    apiAccess: boolean;
    customDomain: boolean;
    prioritySupport: boolean;
  };
}
```

## Questions?

If you encounter any response format that doesn't match this specification, please report it as it may be a bug that needs fixing.

For information about subscription tiers and feature gating, see [TIER_SYSTEM.md](./TIER_SYSTEM.md).
