# HTTP-Only Cookie Authentication Implementation

## Overview

The backend API now uses a **single HTTP-only cookie** containing both authentication tokens as JSON. This provides XSS protection while working reliably with Azure Functions PowerShell and Azure Static Web Apps.

## Cookie Format

### Cookie Name
- `auth`

### Cookie Attributes
- **HttpOnly**: `true` (protects against XSS attacks - JavaScript cannot access)
- **Secure**: `true` (HTTPS only transmission)
- **SameSite**: `Strict` (prevents CSRF attacks)
- **Max-Age**: `604800` seconds (7 days)
- **Path**: `/` (available to all routes)

### Cookie Value Structure
The cookie contains a JSON string with both tokens:

```json
{
  "accessToken": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "refreshToken": "ZpMRbrV36rZ_W3wYMTOy3y..."
}
```

## Frontend Implementation Guide

### 1. Login/Signup Response

**API Endpoints:**
- `POST /api/PublicLogin`
- `POST /api/PublicSignup`

**Request:**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response:**
- **Status**: `200 OK` (Login) or `201 Created` (Signup)
- **Headers**: `Set-Cookie: auth={...}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=604800`
- **Body**:
```json
{
  "user": {
    "UserId": "user-xxx",
    "email": "user@example.com",
    "username": "username",
    "userRole": "user",
    "roles": ["user"],
    "permissions": ["read:dashboard", "write:profile", ...],
    "userManagements": []
  }
}
```

**Frontend Actions:**
1. The browser automatically stores the cookie (no JavaScript action needed)
2. Extract user data from response body
3. Store user profile in state/context
4. Redirect to dashboard

### 2. Authenticated Requests

**Automatic Cookie Sending:**
The browser automatically includes the cookie in all requests to the API. No manual header configuration needed.

```javascript
// Example: Fetch user profile
const response = await fetch('/api/PrivateGetUserProfile', {
  method: 'GET',
  credentials: 'include'  // Important: ensures cookies are sent
});
```

**Note**: Set `credentials: 'include'` in fetch options to ensure cookies are sent with cross-origin requests.

### 3. Token Refresh

**API Endpoint:**
- `POST /api/PublicRefreshToken`

**Request:**
- No body needed (refresh token read from cookie)

**Response:**
- **Status**: `200 OK`
- **Headers**: `Set-Cookie: auth={...}` (with new tokens)
- **Body**:
```json
{
  "user": {
    "UserId": "user-xxx",
    "email": "user@example.com",
    "username": "username",
    "userRole": "user",
    "roles": ["user"],
    "permissions": [...],
    "userManagements": []
  }
}
```

**Frontend Actions:**
1. Call refresh endpoint (typically on 401 responses or before token expiry)
2. Browser automatically updates cookie
3. Update user profile in state if permissions changed

**Example Refresh Logic:**
```javascript
async function refreshAuthToken() {
  try {
    const response = await fetch('/api/PublicRefreshToken', {
      method: 'POST',
      credentials: 'include'
    });
    
    if (response.ok) {
      const data = await response.json();
      // Update user profile in state
      updateUserProfile(data.user);
      return true;
    }
    return false;
  } catch (error) {
    console.error('Token refresh failed:', error);
    return false;
  }
}

// Use in fetch interceptor for 401 responses
async function authenticatedFetch(url, options = {}) {
  options.credentials = 'include';
  
  let response = await fetch(url, options);
  
  if (response.status === 401) {
    // Try to refresh token
    const refreshed = await refreshAuthToken();
    if (refreshed) {
      // Retry original request
      response = await fetch(url, options);
    }
  }
  
  return response;
}
```

### 4. Logout

**API Endpoint:**
- `POST /api/PublicLogout`

**Request:**
- No body needed (refresh token read from cookie)

**Response:**
- **Status**: `200 OK`
- **Headers**: `Set-Cookie: auth=; Max-Age=0` (clears cookie)
- **Body**:
```json
{
  "success": true
}
```

**Frontend Actions:**
1. Call logout endpoint
2. Browser automatically deletes cookie
3. Clear user state/context
4. Redirect to login page

### 5. Error Handling

**401 Unauthorized:**
- Token expired or invalid
- Attempt token refresh
- If refresh fails, redirect to login

**403 Forbidden:**
- User doesn't have required permissions
- Show appropriate error message

**400 Bad Request:**
- Missing or invalid auth cookie
- Redirect to login

## Migration from localStorage

### Old Implementation (localStorage)
```javascript
// Login - OLD WAY
const response = await fetch('/api/PublicLogin', {
  method: 'POST',
  body: JSON.stringify({ email, password })
});
const data = await response.json();
localStorage.setItem('accessToken', data.accessToken);
localStorage.setItem('refreshToken', data.refreshToken);

// Authenticated request - OLD WAY
const response = await fetch('/api/SomeEndpoint', {
  headers: {
    'Authorization': `Bearer ${localStorage.getItem('accessToken')}`
  }
});
```

### New Implementation (HTTP-Only Cookies)
```javascript
// Login - NEW WAY
const response = await fetch('/api/PublicLogin', {
  method: 'POST',
  credentials: 'include',  // Important!
  body: JSON.stringify({ email, password })
});
const data = await response.json();
// No localStorage - tokens are in HTTP-only cookie
// Store only user profile
setUserProfile(data.user);

// Authenticated request - NEW WAY
const response = await fetch('/api/SomeEndpoint', {
  credentials: 'include'  // Cookie sent automatically
});
```

## Security Benefits

1. **XSS Protection**: JavaScript cannot access tokens (HttpOnly)
2. **CSRF Protection**: SameSite=Strict prevents cross-site requests
3. **Secure Transmission**: HTTPS-only (Secure flag)
4. **Automatic Management**: Browser handles cookie lifecycle
5. **Token Rotation**: Refresh endpoint rotates both tokens

## Testing Checklist

- [ ] Login successfully sets cookie and returns user data
- [ ] Signup successfully sets cookie and returns user data
- [ ] Authenticated endpoints work with cookie (credentials: 'include')
- [ ] Token refresh updates cookie and returns fresh user data
- [ ] Logout clears cookie successfully
- [ ] 401 errors trigger token refresh attempt
- [ ] After token refresh fails, user is redirected to login
- [ ] Cookies are not accessible via `document.cookie` in browser console
- [ ] Cookies are sent automatically with all API requests

## Common Issues

### Cookies Not Being Sent
**Problem**: Fetch requests don't include cookies
**Solution**: Add `credentials: 'include'` to all fetch options

### CORS Issues in Development
**Problem**: Cookies not working in local development with different ports
**Solution**: Ensure backend CORS allows credentials from frontend origin

### Cookie Not Visible in DevTools
**Problem**: Cannot see cookie value in browser DevTools
**Solution**: This is expected! HttpOnly cookies are hidden from JavaScript and DevTools for security

## Token Expiration

- **Access Token**: Embedded in JWT, typically 15 minutes
- **Refresh Token**: 7 days (Max-Age=604800)
- **Cookie**: 7 days (Max-Age=604800)

Implement automatic refresh before access token expires for seamless user experience.

## Questions?

Contact the backend team for any implementation questions or issues.
