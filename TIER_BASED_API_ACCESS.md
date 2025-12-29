# Tier-Based API Access Restriction - Implementation Guide

## Overview

This document provides a comprehensive guide for implementing tier-based API access restrictions in the LinkTome API. The system will allow you to restrict **direct API access** (via API keys) based on user account tiers/pricing models (e.g., Free, Pro, Enterprise).

## ⚠️ Important Distinction

**This tier system applies ONLY to direct API access, NOT to UI-based requests:**

- ✅ **UI Requests** (from your frontend app via JWT cookies): **NO tier limits** - Users can use the UI freely regardless of tier
- 🔑 **API Key Requests** (for integrations, external apps): **Tier limits apply** - Rate limited based on subscription tier

This is the standard approach used by services like Stripe, GitHub, and Twilio where:
- The web UI is free/unlimited for all users
- API access for third-party integrations requires a paid plan

## Table of Contents

1. [Current System Architecture](#current-system-architecture)
2. [Proposed Tier System](#proposed-tier-system)
3. [API Key Authentication System](#api-key-authentication-system)
4. [Preventing JWT Cookie Abuse](#preventing-jwt-cookie-abuse)
5. [Database Schema Changes](#database-schema-changes)
6. [Tier Enforcement Layer](#tier-enforcement-layer)
7. [API Endpoint Tier Restrictions](#api-endpoint-tier-restrictions)
8. [Rate Limiting by Tier](#rate-limiting-by-tier)
9. [Backend Integration Requirements](#backend-integration-requirements)
10. [Implementation Roadmap](#implementation-roadmap)
11. [Monitoring and Analytics](#monitoring-and-analytics)

---

## Current System Architecture

### Authentication & Authorization
The LinkTome API currently uses:
- **JWT-based authentication** with HTTP-only cookies
- **Role-based access control (RBAC)** with two roles:
  - `user` - Full access to their own profile, links, analytics, and appearance
  - `user_manager` - Limited access to manage specific user accounts
- **Permission system** with granular permissions like:
  - `read:profile`, `write:profile`
  - `read:links`, `write:links`
  - `read:analytics`, `read:dashboard`
  - `read:appearance`, `write:appearance`
- **Rate limiting** on authentication endpoints (login/signup)

### Current User Schema
Users table stores:
- `PartitionKey`: Email (lowercase)
- `RowKey`: UserId (guid)
- `Username`: Username (lowercase)
- `DisplayName`, `Bio`, `Avatar`: Profile information
- `PasswordHash`, `PasswordSalt`: Authentication
- `IsActive`: Account status
- `Roles`: JSON array of role names
- `Permissions`: JSON array of permission strings

### Request Flow
1. HTTP request → `HttpTrigger/function.json`
2. Request routing → `LinkTomeEntrypoints.psm1`
3. Authentication check → `Get-UserFromRequest` (JWT validation)
4. Permission check → `Test-ContextAwarePermission`
5. Endpoint handler → `Invoke-Admin*` or `Invoke-Public*` functions

---

## API Key Authentication System

### Why API Keys?

To distinguish between UI requests and direct API access, you need an API key system:

- **UI Requests**: Authenticated via JWT cookies (existing system) - **No tier limits**
- **API Requests**: Authenticated via API keys in `Authorization: Bearer <key>` header - **Tier limits apply**

### API Key Structure

```powershell
# API Key Format: ltm_<environment>_<random_string>
# Examples:
#   ltm_live_4x8Kf9mN2pQrSt3vWxYz1aBcDeFgHiJk
#   ltm_test_7Lm9Np2Qr4St6Vw8Xy1Za3Bc5De7Fg9H

# Prefix indicates:
#   ltm_ = LinkToMe
#   live_ = Production key
#   test_ = Development/testing key
```

### Database Schema for API Keys

Create new table: `ApiKeys`

```powershell
# Table: ApiKeys
# Purpose: Store API keys for direct API access
$ApiKey = @{
    PartitionKey = [string]$UserId  # User who owns the key
    RowKey = [string]$ApiKeyId  # Unique key ID (GUID)
    
    # Key Information
    KeyHash = [string]$HashedKey  # SHA256 hash of the full API key
    KeyPrefix = [string]'ltm_live_4x8K'  # First 16 chars for identification
    
    # Metadata
    Name = [string]'Production Integration'  # User-defined name
    CreatedAt = [datetime]$Now
    LastUsedAt = [datetime]$null  # Track usage
    ExpiresAt = [datetime]$null  # Optional expiration
    
    # Status
    IsActive = [bool]$true  # Can be revoked
    
    # Permissions (optional - can restrict key to specific scopes)
    Scopes = [string]'read:profile,write:links'  # JSON or comma-separated
}
```

### API Key Authentication Flow

```
API Request with Authorization: Bearer ltm_live_xxx
    ↓
Parse API key from Authorization header
    ↓
Hash the key and look up in ApiKeys table
    ↓
If found and active:
    ↓
    Get User from ApiKey.PartitionKey
    ↓
    Check User.Tier
    ↓
    Apply tier limits (rate limiting, endpoint access)
    ↓
    Process request
    
If Authorization header is Cookie (JWT):
    ↓
    Existing JWT authentication
    ↓
    NO tier limits applied (UI request)
    ↓
    Process request normally
```

### Implementation Functions

#### Get-UserFromApiKey

Create `Modules/LinkTomeCore/Private/Auth/Get-UserFromApiKey.ps1`:

```powershell
function Get-UserFromApiKey {
    <#
    .SYNOPSIS
        Authenticate user via API key
    .DESCRIPTION
        Validates API key and returns user object
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ApiKey
    )
    
    # Hash the provided key
    $KeyHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($ApiKey)
    )
    $KeyHashString = [System.BitConverter]::ToString($KeyHash) -replace '-', ''
    
    # Look up API key
    $ApiKeysTable = Get-LinkToMeTable -TableName 'ApiKeys'
    $ApiKeyRecord = Get-LinkToMeAzDataTableEntity @ApiKeysTable -Filter "KeyHash eq '$KeyHashString' and IsActive eq true" | Select-Object -First 1
    
    if (-not $ApiKeyRecord) {
        return $null
    }
    
    # Check expiration
    if ($ApiKeyRecord.ExpiresAt -and $ApiKeyRecord.ExpiresAt -lt (Get-Date).ToUniversalTime()) {
        return $null
    }
    
    # Update last used timestamp
    $ApiKeyRecord.LastUsedAt = (Get-Date).ToUniversalTime()
    Add-LinkToMeAzDataTableEntity @ApiKeysTable -Entity $ApiKeyRecord -Force | Out-Null
    
    # Get user
    $UsersTable = Get-LinkToMeTable -TableName 'Users'
    $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$($ApiKeyRecord.PartitionKey)'" | Select-Object -First 1
    
    # Add API key context
    $User | Add-Member -NotePropertyName 'AuthMethod' -NotePropertyValue 'ApiKey' -Force
    $User | Add-Member -NotePropertyName 'ApiKeyId' -NotePropertyValue $ApiKeyRecord.RowKey -Force
    
    return $User
}
```

#### Update Get-UserFromRequest

Modify existing function to check for API keys:

```powershell
function Get-UserFromRequest {
    param(
        [Parameter(Mandatory)]
        $Request
    )
    
    # Check for API key in Authorization header
    if ($Request.Headers -and $Request.Headers.Authorization) {
        $AuthHeader = $Request.Headers.Authorization
        
        # Check for Bearer token (API key)
        if ($AuthHeader -match '^Bearer\s+(ltm_[a-z]+_[A-Za-z0-9]+)$') {
            $ApiKey = $Matches[1]
            $User = Get-UserFromApiKey -ApiKey $ApiKey
            if ($User) {
                return $User
            }
        }
    }
    
    # Fall back to JWT cookie authentication (existing code)
    $AuthCookieValue = $null
    
    if ($Request.Headers -and $Request.Headers.Cookie) {
        # ... existing JWT cookie code ...
    }
    
    return $null
}
```

### API Key Management Endpoints

Users need endpoints to manage their API keys:

#### POST /admin/createApiKey
Create a new API key

```powershell
function Invoke-AdminCreateApiKey {
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body
    
    # Generate API key
    $RandomBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($RandomBytes)
    $RandomString = [System.Convert]::ToBase64String($RandomBytes) -replace '[^A-Za-z0-9]', ''
    $ApiKey = "ltm_live_$($RandomString.Substring(0, 32))"
    
    # Hash for storage
    $KeyHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($ApiKey)
    )
    $KeyHashString = [System.BitConverter]::ToString($KeyHash) -replace '-', ''
    
    # Store in database
    $ApiKeysTable = Get-LinkToMeTable -TableName 'ApiKeys'
    $ApiKeyId = "key-$(New-Guid)"
    
    $NewApiKey = @{
        PartitionKey = $User.UserId
        RowKey = $ApiKeyId
        KeyHash = $KeyHashString
        KeyPrefix = $ApiKey.Substring(0, 16)
        Name = $Body.name ?? 'API Key'
        CreatedAt = (Get-Date).ToUniversalTime()
        IsActive = $true
    }
    
    Add-LinkToMeAzDataTableEntity @ApiKeysTable -Entity $NewApiKey -Force
    
    # Return key ONCE (never shown again)
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Created
        Body = @{
            apiKey = $ApiKey  # ONLY TIME this is returned
            keyId = $ApiKeyId
            keyPrefix = $NewApiKey.KeyPrefix
            name = $NewApiKey.Name
            createdAt = $NewApiKey.CreatedAt
        }
    }
}
```

#### GET /admin/listApiKeys
List user's API keys (without revealing full keys)

#### DELETE /admin/revokeApiKey
Revoke an API key

---

## Preventing JWT Cookie Abuse

### The Security Challenge

**Problem 1**: Users could extract their JWT cookie from the browser and use it in curl/Postman to make unlimited API calls, bypassing API key tier limits.

```bash
# Example of potential abuse:
curl -H "Cookie: auth={...}" https://api.linktome.com/admin/getProfile
```

**Problem 2 (More Critical)**: Users could programmatically call the `/login` endpoint to authenticate and get JWT cookies, then use those cookies for unlimited API access:

```bash
# Login programmatically
curl -X POST https://api.linktome.com/public/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password123"}' \
  -c cookies.txt

# Use the cookies for API calls
curl -b cookies.txt https://api.linktome.com/admin/getProfile
curl -b cookies.txt https://api.linktome.com/admin/getLinks
# ... unlimited calls, bypassing API key tier limits
```

This is the **primary attack vector** since login is intentionally public and returns authentication cookies.

### Solution: Protect the Login Endpoint

#### Option 1: CAPTCHA on Login (Recommended for Public Apps)

Add CAPTCHA verification to `/login` to prevent automated authentication:

```powershell
function Invoke-PublicLogin {
    param($Request, $TriggerMetadata)
    
    $Body = $Request.Body
    
    # NEW: Require CAPTCHA for login
    if (-not $Body.captchaToken) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{
                error = "CAPTCHA verification required"
                requiresCaptcha = $true
            }
        }
    }
    
    # Verify CAPTCHA (Google reCAPTCHA v3 or hCaptcha)
    $CaptchaValid = Verify-CaptchaToken -Token $Body.captchaToken -ExpectedAction 'login'
    if (-not $CaptchaValid) {
        Write-SecurityEvent -EventType 'LoginFailedCaptcha' -Email $Body.email -IpAddress (Get-ClientIPAddress -Request $Request)
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "CAPTCHA verification failed" }
        }
    }
    
    # Continue with normal login flow...
}
```

**CAPTCHA Implementation**:

```powershell
function Verify-CaptchaToken {
    param(
        [string]$Token,
        [string]$ExpectedAction = 'login'
    )
    
    # Google reCAPTCHA v3 verification
    $SecretKey = Get-EnvironmentVariable -Name 'RECAPTCHA_SECRET_KEY'
    $VerifyUrl = 'https://www.google.com/recaptcha/api/siteverify'
    
    $Response = Invoke-RestMethod -Uri $VerifyUrl -Method Post -Body @{
        secret = $SecretKey
        response = $Token
    }
    
    # Check if verification succeeded and score is high enough
    if ($Response.success -and $Response.score -ge 0.5) {
        if ($Response.action -eq $ExpectedAction) {
            return $true
        }
    }
    
    return $false
}
```

**Frontend Integration**:

```javascript
// In your login component
async function handleLogin(email, password) {
  // Get reCAPTCHA token
  const captchaToken = await grecaptcha.execute('YOUR_SITE_KEY', {
    action: 'login'
  });
  
  // Send with login request
  const response = await fetch('/api/public/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email,
      password,
      captchaToken  // Include CAPTCHA token
    })
  });
}
```

#### Option 2: Device/Browser Fingerprinting

Track device fingerprints and require verification for new devices:

```powershell
function Invoke-PublicLogin {
    param($Request, $TriggerMetadata)
    
    # Generate device fingerprint from request
    $DeviceFingerprint = Get-DeviceFingerprint -Request $Request
    
    # Check if this device has logged in before
    $KnownDevice = Test-KnownDevice -UserId $UserId -Fingerprint $DeviceFingerprint
    
    if (-not $KnownDevice) {
        # New device - require additional verification
        # Option A: Send email verification
        # Option B: Require 2FA
        # Option C: CAPTCHA
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{
                error = "New device detected. Please verify your email to continue."
                requiresVerification = $true
            }
        }
    }
    
    # Known device - proceed normally
}

function Get-DeviceFingerprint {
    param($Request)
    
    # Combine multiple signals
    $Signals = @(
        $Request.Headers.'User-Agent'
        $Request.Headers.'Accept-Language'
        $Request.Headers.'sec-ch-ua'
        $Request.Headers.'sec-ch-ua-platform'
        (Get-ClientIPAddress -Request $Request)
    )
    
    $Combined = $Signals -join '|'
    $Hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($Combined)
    )
    
    return [System.BitConverter]::ToString($Hash) -replace '-', ''
}
```

#### Option 3: Separate Auth Flow for API Access

**Recommended Hybrid Approach**: Use different authentication for UI vs API:

```
UI Authentication (Current):
  POST /public/login → Returns JWT cookies → Use in browser only

API Authentication (New):
  POST /public/api-token → Returns API key → Use in programmatic access
```

Modify login endpoint:

```powershell
function Invoke-PublicLogin {
    param($Request, $TriggerMetadata)
    
    # Detect if this is a programmatic request
    $IsUIRequest = Test-IsUIRequest -Request $Request -User $null
    
    if (-not $IsUIRequest) {
        # This is a programmatic login attempt
        Write-SecurityEvent -EventType 'ProgrammaticLoginAttempt' -Email $Body.email -IpAddress (Get-ClientIPAddress -Request $Request) -UserAgent $Request.Headers.'User-Agent'
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{
                error = "Programmatic login detected. For API access, please create an API key in your account settings."
                message = "The /login endpoint is only for browser-based authentication. Use API keys for programmatic access."
                documentation = "https://docs.linktome.com/api-keys"
            }
        }
    }
    
    # Normal UI login continues...
}
```

**Modified Test-IsUIRequest for Login** (no User parameter needed):

```powershell
function Test-IsUIRequest {
    param([Parameter(Mandatory)]$Request)
    
    $UiScore = 0
    
    # Browser-specific headers (modern browsers send these)
    $BrowserHeaders = @('sec-fetch-site', 'sec-fetch-mode', 'sec-fetch-dest', 'sec-ch-ua')
    foreach ($Header in $BrowserHeaders) {
        if ($Request.Headers.$Header) {
            $UiScore += 2
        }
    }
    
    # Check User-Agent
    $UserAgent = $Request.Headers.'User-Agent'
    if ($UserAgent) {
        if ($UserAgent -match '(Chrome|Firefox|Safari|Edge)\/[\d\.]+') {
            $UiScore += 3
        }
        elseif ($UserAgent -match '(curl|python|postman|insomnia|httpie|wget|go-http-client)') {
            $UiScore -= 5  # Strong negative for automation tools
        }
    }
    
    # Check Origin header
    $AllowedOrigins = @('https://linktome.com', 'https://www.linktome.com')
    if ($Request.Headers.Origin -and $AllowedOrigins -contains $Request.Headers.Origin) {
        $UiScore += 3
    }
    
    # Check Referer
    if ($Request.Headers.Referer) {
        $RefererHost = ([System.Uri]$Request.Headers.Referer).Host
        if ($RefererHost -in @('linktome.com', 'www.linktome.com')) {
            $UiScore += 2
        }
    }
    
    return $UiScore -ge 5
}
```

#### Option 4: Two-Factor Authentication (2FA)

Require 2FA for login, making automated login impossible:

```powershell
function Invoke-PublicLogin {
    param($Request, $TriggerMetadata)
    
    # After password verification
    if ($PasswordValid) {
        # Check if user has 2FA enabled
        if ($User.TwoFactorEnabled) {
            # Don't return auth cookies yet
            # Create temporary session token
            $TempToken = New-TemporaryLoginToken -UserId $User.UserId
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body = @{
                    requires2FA = $true
                    tempToken = $TempToken
                    message = "Please enter your 2FA code"
                }
            }
        }
        
        # No 2FA - return cookies normally
    }
}

# New endpoint: POST /public/verify2FA
function Invoke-PublicVerify2FA {
    param($Request, $TriggerMetadata)
    
    $TempToken = $Request.Body.tempToken
    $TwoFactorCode = $Request.Body.code
    
    # Verify temp token and 2FA code
    if (Verify-TwoFactorCode -Token $TempToken -Code $TwoFactorCode) {
        # Now return auth cookies
        # ... standard login response
    }
}
```

### Recommended Combined Strategy

**For Maximum Security**:

1. ✅ **CAPTCHA on login** - Blocks automated login attempts
2. ✅ **Detect programmatic requests** - Block curl/scripts at login endpoint
3. ✅ **Rate limiting on login** - Already implemented (5 attempts/min)
4. ✅ **Require API keys for API access** - Clear separation of UI vs API
5. ⚠️ **Optional: 2FA** - Additional security layer

**Implementation Priority**:

```powershell
# High Priority (Implement First)
# 1. Add CAPTCHA to login endpoint
# 2. Detect and block obvious automation (curl, python, etc.)
# 3. Clear error messages directing to API keys

# Medium Priority
# 4. Device fingerprinting for new device detection
# 5. Enhanced rate limiting based on User-Agent

# Low Priority (Nice to Have)
# 6. 2FA for high-security accounts
# 7. Behavioral analysis for suspicious login patterns
```

### Example: Complete Secure Login Implementation

```powershell
function Invoke-PublicLogin {
    param($Request, $TriggerMetadata)
    
    $Body = $Request.Body
    $ClientIP = Get-ClientIPAddress -Request $Request
    
    # 1. Check rate limiting (existing)
    $RateCheck = Test-RateLimit -Identifier $ClientIP -Endpoint 'public/login' -MaxRequests 5 -WindowSeconds 60
    if (-not $RateCheck.Allowed) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::TooManyRequests
            Body = @{ error = "Too many login attempts" }
        }
    }
    
    # 2. Detect programmatic access
    $IsUIRequest = Test-IsUIRequest -Request $Request
    if (-not $IsUIRequest) {
        Write-SecurityEvent -EventType 'ProgrammaticLoginBlocked' -Email $Body.email -IpAddress $ClientIP -UserAgent $Request.Headers.'User-Agent'
        
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{
                error = "Programmatic login is not allowed"
                message = "For API access, create an API key at: https://linktome.com/settings/api-keys"
            }
        }
    }
    
    # 3. Verify CAPTCHA
    if (-not $Body.captchaToken) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "CAPTCHA required", requiresCaptcha = $true }
        }
    }
    
    $CaptchaValid = Verify-CaptchaToken -Token $Body.captchaToken -ExpectedAction 'login'
    if (-not $CaptchaValid) {
        Write-SecurityEvent -EventType 'LoginCaptchaFailed' -Email $Body.email -IpAddress $ClientIP
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ error = "CAPTCHA verification failed" }
        }
    }
    
    # 4. Verify credentials (existing logic)
    # ... password check ...
    
    # 5. Return JWT cookies (only for verified UI requests)
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @{ user = $UserInfo }
        Headers = @{
            'Set-Cookie' = $CookieHeader
        }
    }
}
```

### Testing Your Protection

Try these attacks to verify protection:

```bash
# Test 1: Direct curl login (should be blocked)
curl -X POST https://api.linktome.com/public/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"pass123"}'
# Expected: 403 Forbidden - "Programmatic login is not allowed"

# Test 2: Login without CAPTCHA (should be blocked)
# Even from browser, if CAPTCHA token missing
# Expected: 400 Bad Request - "CAPTCHA required"

# Test 3: Normal browser login (should work)
# From your actual web app with CAPTCHA
# Expected: 200 OK with cookies
```

### Multi-Layer Defense Strategy

Implement multiple detection mechanisms to identify and block programmatic access using JWT cookies:

#### 1. Request Origin Validation

**Check Origin and Referer Headers**

```powershell
function Test-IsUIRequest {
    <#
    .SYNOPSIS
        Detect if request comes from legitimate UI
    .DESCRIPTION
        Uses multiple signals to determine if request is from browser UI or programmatic access
    #>
    param(
        [Parameter(Mandatory)]
        $Request,
        
        [Parameter(Mandatory)]
        $User
    )
    
    # If using API key, it's NOT a UI request
    if ($User.AuthMethod -eq 'ApiKey') {
        return $false
    }
    
    # Score-based system (higher score = more likely UI)
    $UiScore = 0
    $AllowedOrigins = @('https://linktome.com', 'https://www.linktome.com')
    
    # Check Origin header (present in CORS requests from browser)
    if ($Request.Headers.Origin) {
        if ($AllowedOrigins -contains $Request.Headers.Origin) {
            $UiScore += 3  # Strong signal
        } else {
            $UiScore -= 2  # Wrong origin
        }
    }
    
    # Check Referer header
    if ($Request.Headers.Referer) {
        $RefererDomain = ([System.Uri]$Request.Headers.Referer).Host
        if ($RefererDomain -in @('linktome.com', 'www.linktome.com')) {
            $UiScore += 2
        } else {
            $UiScore -= 1
        }
    } else {
        # No referer is suspicious for UI requests
        $UiScore -= 1
    }
    
    # Check User-Agent
    $UserAgent = $Request.Headers.'User-Agent'
    if ($UserAgent) {
        # Known browsers
        if ($UserAgent -match '(Chrome|Firefox|Safari|Edge)\/[\d\.]+') {
            $UiScore += 2
        }
        # Mobile browsers
        elseif ($UserAgent -match '(Mobile|Android|iPhone|iPad)') {
            $UiScore += 2
        }
        # Known automation tools (curl, python, postman, etc.)
        elseif ($UserAgent -match '(curl|python|postman|insomnia|httpie|wget|go-http-client)/i') {
            $UiScore -= 3  # Strong negative signal
        }
        # Generic/minimal user agents
        elseif ($UserAgent.Length -lt 20) {
            $UiScore -= 1
        }
    } else {
        # No user agent is very suspicious
        $UiScore -= 2
    }
    
    # Check for CORS preflight (OPTIONS requests from browsers)
    if ($Request.Method -eq 'OPTIONS' -and $Request.Headers.'Access-Control-Request-Method') {
        $UiScore += 2
    }
    
    # Check for browser-specific headers
    $BrowserHeaders = @('sec-fetch-site', 'sec-fetch-mode', 'sec-fetch-dest', 'sec-ch-ua')
    foreach ($Header in $BrowserHeaders) {
        if ($Request.Headers.$Header) {
            $UiScore += 1  # Each browser header is a signal
        }
    }
    
    # Decision threshold
    return $UiScore -ge 3
}
```

#### 2. Integration into Request Router

Update `LinkTomeEntrypoints.psm1`:

```powershell
# After authentication check for admin endpoints
if ($Endpoint -match '^admin/') {
    $User = Get-UserFromRequest -Request $Request
    if (-not $User) {
        # Handle auth failure...
    }
    
    # NEW: Detect request type and apply tier limits accordingly
    $IsUIRequest = Test-IsUIRequest -Request $Request -User $User
    
    if (-not $IsUIRequest) {
        # This is a programmatic request (likely curl/API client)
        
        # If using JWT cookie (not API key), this is suspicious
        if ($User.AuthMethod -ne 'ApiKey') {
            # Log suspicious activity
            $ClientIP = Get-ClientIPAddress -Request $Request
            Write-SecurityEvent -EventType 'SuspiciousJWTUsage' -UserId $User.UserId -IpAddress $ClientIP -UserAgent $Request.Headers.'User-Agent'
            
            # Option 1: Block completely
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{
                    error = "Direct API access requires an API key. Please use an API key or access via the web interface."
                    documentation = "https://docs.linktome.com/api-keys"
                }
            }
            
            # Option 2: Apply tier limits (treat like API key request)
            # $TierCheck = Test-TierAccess -User $User -Endpoint $Endpoint
            # if (-not $TierCheck.Allowed) { ... }
        }
        
        # If using API key, apply tier limits normally
        if ($User.AuthMethod -eq 'ApiKey') {
            $TierCheck = Test-TierAccess -User $User -Endpoint $Endpoint
            if (-not $TierCheck.Allowed) {
                # Return 402 Payment Required...
            }
        }
    }
    
    # Continue with permission check...
}
```

#### 3. Enhanced Cookie Security

Strengthen cookie attributes (already in place, but verify):

```powershell
# In login/signup responses
$CookieHeader = "auth=$AuthData; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=604800"

# HttpOnly: Prevents JavaScript access (XSS protection)
# Secure: Only sent over HTTPS
# SameSite=Strict: Not sent on cross-site requests (CSRF protection)
```

**SameSite=Strict** is crucial - it prevents the cookie from being sent if:
- Request originates from a different domain
- User clicks a link from external site
- curl/Postman makes a direct request (no browser context)

However, **curl can still send cookies manually**, so we need additional checks.

#### 4. Rate Limiting for Suspicious Requests

Even if you can't perfectly detect all abuse, rate limiting helps:

```powershell
# Apply aggressive rate limits to suspicious requests
if (-not $IsUIRequest -and $User.AuthMethod -ne 'ApiKey') {
    # Use more restrictive rate limit for suspicious JWT usage
    $RateCheck = Test-RateLimit -Identifier $User.UserId -Endpoint $Endpoint -MaxRequests 10 -WindowSeconds 60
    
    if (-not $RateCheck.Allowed) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::TooManyRequests
            Body = @{
                error = "Rate limit exceeded for direct API access. Please use an API key for programmatic access."
            }
        }
    }
}
```

#### 5. Request Fingerprinting

Track request patterns to detect automation:

```powershell
# Detect automation patterns
function Test-AutomationPattern {
    param($UserId, $Endpoint)
    
    # Get recent requests from this user
    $RecentRequests = Get-RecentUserRequests -UserId $UserId -Minutes 5
    
    # Suspicious patterns:
    # - Exact same intervals between requests (e.g., every 5 seconds)
    # - No human-like variations
    # - Unusual request sequences
    # - High request rate without typical UI navigation patterns
    
    $Intervals = @()
    $PreviousTime = $null
    foreach ($Req in $RecentRequests) {
        if ($PreviousTime) {
            $Intervals += ($Req.Timestamp - $PreviousTime).TotalSeconds
        }
        $PreviousTime = $Req.Timestamp
    }
    
    # Check if intervals are suspiciously regular (variance < 0.5 seconds)
    if ($Intervals.Count -gt 5) {
        $AvgInterval = ($Intervals | Measure-Object -Average).Average
        $Variance = ($Intervals | ForEach-Object { [Math]::Pow($_ - $AvgInterval, 2) } | Measure-Object -Average).Average
        $StdDev = [Math]::Sqrt($Variance)
        
        if ($StdDev -lt 0.5) {
            return $true  # Too regular, likely automation
        }
    }
    
    return $false
}
```

#### 6. CAPTCHA Challenge (Nuclear Option)

For highly suspicious requests:

```powershell
if (-not $IsUIRequest -and $User.AuthMethod -ne 'ApiKey') {
    # Require CAPTCHA verification
    if (-not $Request.Headers.'X-Captcha-Token') {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{
                error = "CAPTCHA verification required"
                requiresCaptcha = $true
            }
        }
    }
    
    # Verify CAPTCHA token (Google reCAPTCHA, hCaptcha, etc.)
    $CaptchaValid = Verify-CaptchaToken -Token $Request.Headers.'X-Captcha-Token'
    if (-not $CaptchaValid) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Forbidden
            Body = @{ error = "Invalid CAPTCHA" }
        }
    }
}
```

### Detection Strategy Summary

| Signal | Weight | Notes |
|--------|--------|-------|
| **API Key Auth** | ✅ Allowed | Legitimate programmatic access |
| **JWT + Browser Headers** | ✅ Allowed | Legitimate UI access |
| **JWT + curl User-Agent** | 🚫 Block | Obvious abuse |
| **JWT + No Origin/Referer** | ⚠️ Suspicious | Apply strict rate limits |
| **JWT + Wrong Origin** | 🚫 Block | Potential attack |
| **JWT + Automation Pattern** | 🚫 Block | Detected bot behavior |

### Recommended Policy

**Option A: Strict (Recommended)**
- JWT cookies ONLY work from your domain with proper browser headers
- All other access MUST use API keys
- Clear error message directing users to API key documentation

**Option B: Lenient with Rate Limits**
- Allow JWT cookie usage from anywhere
- Apply strict rate limits (10 req/min) to suspicious requests
- Monitor and alert on abuse patterns

**Option C: Hybrid**
- Allow JWT cookies from your domain (normal UI usage)
- Apply strict rate limits to JWT cookies from other origins
- Block obvious automation (curl, python, etc.)
- Require API keys for sustained programmatic access

### Implementation Code

Create `Modules/LinkTomeCore/Private/Auth/Test-IsUIRequest.ps1` with the function above, then integrate into request router:

```powershell
# In LinkTomeEntrypoints.psm1, after JWT authentication
if ($User) {
    $IsUIRequest = Test-IsUIRequest -Request $Request -User $User
    $Request | Add-Member -NotePropertyName 'IsUIRequest' -NotePropertyValue $IsUIRequest -Force
    
    # If NOT UI and NOT API key, apply restrictions
    if (-not $IsUIRequest -and $User.AuthMethod -ne 'ApiKey') {
        # Your policy here (block, rate limit, or challenge)
    }
}
```

### Monitoring and Alerts

Track these metrics:

```powershell
# Security Events to log
Write-SecurityEvent -EventType 'SuspiciousJWTUsage' -UserId $UserId -IpAddress $IP -UserAgent $UserAgent -Endpoint $Endpoint
Write-SecurityEvent -EventType 'JWTAbuseBlocked' -UserId $UserId
Write-SecurityEvent -EventType 'AutomationPatternDetected' -UserId $UserId

# Alert thresholds:
# - User has >10 blocked suspicious requests in 1 hour
# - Automation pattern detected 3+ times
# - Same IP attempting access for multiple users
```

### User Communication

When blocking suspicious requests, provide helpful error messages:

```json
{
  "error": "Direct API access requires an API key",
  "message": "We detected this request was made programmatically. For API access, please create an API key in your account settings.",
  "documentation": "https://docs.linktome.com/api-keys",
  "accountSettings": "https://linktome.com/settings/api-keys"
}
```

---

## Proposed Tier System

### Tier Definitions

**Note**: Tier limits apply ONLY to API key requests, NOT to UI requests.

#### Free Tier
- **Cost**: $0/month
- **Target**: Individual users testing the platform
- **Direct API Access**: Limited to basic profile and link management
- **API Rate Limits**: 100 requests/hour (via API key only)
- **UI Access**: Unlimited (no tier restrictions)
- **Features**:
  - Basic profile management (read/write)
  - Up to 5 links
  - Basic analytics (last 7 days)
  - Public profile page
  - No API keys (must upgrade for API access)

#### Pro Tier
- **Cost**: $9/month (example)
- **Target**: Content creators and professionals
- **Direct API Access**: Full API access for personal use
- **API Rate Limits**: 1,000 requests/hour (via API key)
- **UI Access**: Unlimited (no tier restrictions)
- **Features**:
  - Full profile management
  - Unlimited links
  - Full analytics (unlimited history)
  - Custom appearance themes
  - API keys for integrations (up to 3 keys)

#### Enterprise Tier
- **Cost**: $49/month (example)
- **Target**: Businesses and agencies
- **Direct API Access**: Full API access with higher limits
- **Rate Limits**: High (e.g., 10,000 requests/hour)
- **Features**:
  - All Pro features
  - Team management (user_manager role support)
  - Priority support
  - Advanced analytics
  - Webhook support (future)
  - Custom domain (future)

---

## Database Schema Changes

### 1. Add Tier Field to Users Table

**Modify User Entity** to include:
```powershell
# New fields to add to Users table
$NewUser = @{
    # ... existing fields ...
    
    # Tier System
    Tier = [string]'free'  # Options: 'free', 'pro', 'enterprise'
    TierStartDate = [datetime]$Now  # When current tier started
    TierEndDate = [datetime]$null  # Null for active, date for expired
    
    # API Usage Tracking
    ApiUsageResetDate = [datetime]$Now  # When to reset usage counters
    ApiRequestCount = [int]0  # Current period request count
    ApiRequestLimit = [int]100  # Requests allowed per period (hourly)
    
    # Feature Limits
    MaxLinks = [int]5  # Free tier limit
    AnalyticsRetentionDays = [int]7  # Free tier limit
}
```

### 2. Create Subscriptions Table (Optional - for payment tracking)

If you want to track subscription history and payments:

```powershell
# Table: Subscriptions
# Purpose: Track subscription history and billing
$Subscription = @{
    PartitionKey = [string]$UserId  # User identifier
    RowKey = [string]$SubscriptionId  # Unique subscription ID
    
    Tier = [string]'pro'  # Subscription tier
    Status = [string]'active'  # active, cancelled, expired, past_due
    
    StartDate = [datetime]$Now
    EndDate = [datetime]$EndDate  # When subscription ends
    RenewalDate = [datetime]$RenewalDate  # Next billing date
    
    # Payment Information (DO NOT store full card details)
    PaymentProcessor = [string]'stripe'  # stripe, paypal, etc.
    PaymentProcessorCustomerId = [string]'cus_xxx'  # External customer ID
    PaymentProcessorSubscriptionId = [string]'sub_xxx'  # External subscription ID
    
    # Pricing
    Price = [decimal]9.99
    Currency = [string]'USD'
    BillingPeriod = [string]'monthly'  # monthly, yearly
    
    # Metadata
    CreatedAt = [datetime]$Now
    UpdatedAt = [datetime]$Now
    CancelledAt = [datetime]$null
}
```

### 3. Create ApiUsageHistory Table (for analytics)

Track API usage over time:

```powershell
# Table: ApiUsageHistory
# Purpose: Track API usage for analytics and billing
$UsageRecord = @{
    PartitionKey = [string]"$UserId-$Date"  # User + Date (YYYY-MM-DD)
    RowKey = [string]$Timestamp  # ISO 8601 timestamp
    
    Endpoint = [string]'/admin/getProfile'
    Method = [string]'GET'
    StatusCode = [int]200
    ResponseTime = [int]150  # milliseconds
    
    Tier = [string]'pro'  # User's tier at time of request
    
    IpAddress = [string]$ClientIP
    UserAgent = [string]$UserAgent
}
```

---

## Tier Enforcement Layer

### 1. Create Tier Validation Function

Create a new file: `Modules/LinkTomeCore/Private/Auth/Get-UserTierLimits.ps1`

```powershell
function Get-UserTierLimits {
    <#
    .SYNOPSIS
        Get tier limits for a user
    .DESCRIPTION
        Returns tier-specific limits and restrictions for a user
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Tier
    )
    
    $TierLimits = @{
        'free' = @{
            ApiRequestsPerHour = 100
            MaxLinks = 5
            AnalyticsRetentionDays = 7
            AllowedEndpoints = @(
                'admin/getProfile',
                'admin/updateProfile',
                'admin/getLinks',
                'admin/updateLinks',
                'admin/getDashboardStats'
            )
            RateLimitWindow = 3600  # 1 hour in seconds
        }
        'pro' = @{
            ApiRequestsPerHour = 1000
            MaxLinks = -1  # Unlimited
            AnalyticsRetentionDays = -1  # Unlimited
            AllowedEndpoints = @(
                'admin/getProfile',
                'admin/updateProfile',
                'admin/getLinks',
                'admin/updateLinks',
                'admin/getAnalytics',
                'admin/getDashboardStats',
                'admin/getAppearance',
                'admin/updateAppearance'
            )
            RateLimitWindow = 3600
        }
        'enterprise' = @{
            ApiRequestsPerHour = 10000
            MaxLinks = -1  # Unlimited
            AnalyticsRetentionDays = -1  # Unlimited
            AllowedEndpoints = @(
                # All endpoints allowed
                'admin/getProfile',
                'admin/updateProfile',
                'admin/getLinks',
                'admin/updateLinks',
                'admin/getAnalytics',
                'admin/getDashboardStats',
                'admin/getAppearance',
                'admin/updateAppearance',
                'admin/UserManagerList',
                'admin/UserManagerInvite',
                'admin/UserManagerRemove',
                'admin/UserManagerRespond'
            )
            RateLimitWindow = 3600
        }
    }
    
    return $TierLimits[$Tier]
}
```

### 2. Create Tier Access Check Function

Create a new file: `Modules/LinkTomeCore/Private/Auth/Test-TierAccess.ps1`

```powershell
function Test-TierAccess {
    <#
    .SYNOPSIS
        Check if user's tier allows access to endpoint
    .DESCRIPTION
        Validates tier-based access and rate limits
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,
        
        [Parameter(Mandatory)]
        [string]$Endpoint
    )
    
    # Get user's tier (default to free if not set)
    $Tier = $User.Tier
    if (-not $Tier) {
        $Tier = 'free'
    }
    
    # Get tier limits
    $TierLimits = Get-UserTierLimits -Tier $Tier
    
    # Check if endpoint is allowed for this tier
    if ($TierLimits.AllowedEndpoints -notcontains $Endpoint) {
        return @{
            Allowed = $false
            Reason = 'EndpointNotAllowedForTier'
            RequiredTier = 'pro'  # Could be dynamic based on endpoint
            Message = "This endpoint requires a Pro or Enterprise subscription"
        }
    }
    
    # Check API rate limits
    $Now = [DateTimeOffset]::UtcNow
    $ResetDate = [DateTimeOffset]$User.ApiUsageResetDate
    
    # Reset counter if window expired
    if ($Now -gt $ResetDate.AddSeconds($TierLimits.RateLimitWindow)) {
        return @{
            Allowed = $true
            ResetUsage = $true  # Signal to reset counter
            NewResetDate = $Now
        }
    }
    
    # Check if limit exceeded
    $CurrentCount = [int]$User.ApiRequestCount
    if ($CurrentCount -ge $TierLimits.ApiRequestsPerHour) {
        $SecondsUntilReset = [int]($TierLimits.RateLimitWindow - ($Now - $ResetDate).TotalSeconds)
        
        return @{
            Allowed = $false
            Reason = 'TierRateLimitExceeded'
            CurrentUsage = $CurrentCount
            Limit = $TierLimits.ApiRequestsPerHour
            RetryAfter = $SecondsUntilReset
            Message = "API rate limit exceeded. Upgrade to Pro for higher limits."
        }
    }
    
    # Access allowed
    return @{
        Allowed = $true
        IncrementUsage = $true  # Signal to increment counter
    }
}
```

### 3. Modify Request Router

Update `Modules/LinkTomeEntrypoints/LinkTomeEntrypoints.psm1`:

```powershell
# In New-LinkTomeCoreRequest function, after authentication check
if ($Endpoint -match '^admin/') {
    $User = Get-UserFromRequest -Request $Request
    if (-not $User) {
        # ... existing auth failure handling ...
    }
    
    # NEW: Tier-based access check
    $TierCheck = Test-TierAccess -User $User -Endpoint $Endpoint
    
    if (-not $TierCheck.Allowed) {
        # Log tier restriction event
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'TierAccessDenied' -UserId $User.UserId -Endpoint $Endpoint -IpAddress $ClientIP -Reason $TierCheck.Reason
        
        $StatusCode = if ($TierCheck.Reason -eq 'TierRateLimitExceeded') {
            [HttpStatusCode]::TooManyRequests
        } else {
            [HttpStatusCode]::PaymentRequired  # 402
        }
        
        $ResponseHeaders = @{}
        if ($TierCheck.RetryAfter) {
            $ResponseHeaders['Retry-After'] = $TierCheck.RetryAfter.ToString()
            $ResponseHeaders['X-RateLimit-Limit'] = $TierCheck.Limit.ToString()
            $ResponseHeaders['X-RateLimit-Remaining'] = '0'
            $ResponseHeaders['X-RateLimit-Reset'] = $TierCheck.RetryAfter.ToString()
        }
        
        return [HttpResponseContext]@{
            StatusCode = $StatusCode
            Headers = $ResponseHeaders
            Body = @{ 
                error = $TierCheck.Message
                reason = $TierCheck.Reason
                currentTier = $User.Tier
                requiredTier = $TierCheck.RequiredTier
                upgradeUrl = "https://linktome.com/pricing"  # Your pricing page
            }
        }
    }
    
    # Update API usage counter if needed
    if ($TierCheck.IncrementUsage -or $TierCheck.ResetUsage) {
        $Table = Get-LinkToMeTable -TableName 'Users'
        $UserEntity = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$($User.UserId)'" | Select-Object -First 1
        
        if ($TierCheck.ResetUsage) {
            $UserEntity.ApiRequestCount = 1
            $UserEntity.ApiUsageResetDate = $TierCheck.NewResetDate
        } else {
            $UserEntity.ApiRequestCount = [int]$UserEntity.ApiRequestCount + 1
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserEntity -Force | Out-Null
    }
    
    # Continue with existing permission check...
}
```

---

## API Endpoint Tier Restrictions

### Recommended Endpoint-to-Tier Mapping

| Endpoint | Free | Pro | Enterprise | Notes |
|----------|------|-----|------------|-------|
| **Public Endpoints** |
| `POST /public/signup` | ✅ | ✅ | ✅ | Open to all |
| `POST /public/login` | ✅ | ✅ | ✅ | Open to all |
| `GET /public/getUserProfile` | ✅ | ✅ | ✅ | Open to all |
| `POST /public/trackLinkClick` | ✅ | ✅ | ✅ | Open to all |
| **Profile Management** |
| `GET /admin/getProfile` | ✅ | ✅ | ✅ | Basic access |
| `PUT /admin/updateProfile` | ✅ | ✅ | ✅ | Basic access |
| **Link Management** |
| `GET /admin/getLinks` | ✅ | ✅ | ✅ | All tiers |
| `PUT /admin/updateLinks` | ✅* | ✅ | ✅ | *Free limited to 5 links |
| **Analytics** |
| `GET /admin/getDashboardStats` | ✅* | ✅ | ✅ | *Free limited to basic stats |
| `GET /admin/getAnalytics` | ❌ | ✅ | ✅ | Pro+ only |
| **Appearance** |
| `GET /admin/getAppearance` | ❌ | ✅ | ✅ | Pro+ only |
| `PUT /admin/updateAppearance` | ❌ | ✅ | ✅ | Pro+ only |
| **Team Management** |
| `GET /admin/UserManagerList` | ❌ | ❌ | ✅ | Enterprise only |
| `POST /admin/UserManagerInvite` | ❌ | ❌ | ✅ | Enterprise only |
| `DELETE /admin/UserManagerRemove` | ❌ | ❌ | ✅ | Enterprise only |
| `POST /admin/UserManagerRespond` | ❌ | ❌ | ✅ | Enterprise only |

### Feature-Level Restrictions

Some endpoints need feature-level checks within the handler:

#### Example: Link Count Limit

Modify `Invoke-AdminUpdateLinks.ps1`:

```powershell
# After authentication, before saving links
$User = $Request.AuthenticatedUser
$TierLimits = Get-UserTierLimits -Tier $User.Tier

if ($TierLimits.MaxLinks -ne -1) {
    $LinkCount = ($Body.links | Measure-Object).Count
    if ($LinkCount -gt $TierLimits.MaxLinks) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::PaymentRequired  # 402
            Body = @{
                error = "Link limit exceeded. Free tier allows up to $($TierLimits.MaxLinks) links."
                currentCount = $LinkCount
                maxAllowed = $TierLimits.MaxLinks
                currentTier = $User.Tier
                upgradeUrl = "https://linktome.com/pricing"
            }
        }
    }
}
```

#### Example: Analytics Retention

Modify `Invoke-AdminGetAnalytics.ps1`:

```powershell
# Filter analytics data based on tier retention
$User = $Request.AuthenticatedUser
$TierLimits = Get-UserTierLimits -Tier $User.Tier

if ($TierLimits.AnalyticsRetentionDays -ne -1) {
    $RetentionDate = (Get-Date).AddDays(-$TierLimits.AnalyticsRetentionDays)
    # Filter analytics records to only include data after RetentionDate
}
```

---

## Rate Limiting by Tier

### Tier-Specific Rate Limits

| Tier | Requests/Hour | Burst Limit | Window |
|------|---------------|-------------|--------|
| Free | 100 | 10/minute | 1 hour |
| Pro | 1,000 | 50/minute | 1 hour |
| Enterprise | 10,000 | 200/minute | 1 hour |

### Implementation Notes

1. **Per-User Rate Limiting**: Track usage per `UserId` instead of per IP
2. **Endpoint-Specific Limits**: Public endpoints (like profile views) shouldn't count against user limits
3. **Admin Endpoints**: All admin endpoints count against the tier limit
4. **Bypass for Critical Operations**: Authentication endpoints (login/signup) use separate limits

### Rate Limit Response Headers

Include these headers in all API responses:

```powershell
Headers = @{
    'X-RateLimit-Limit' = $TierLimits.ApiRequestsPerHour
    'X-RateLimit-Remaining' = ($TierLimits.ApiRequestsPerHour - $User.ApiRequestCount)
    'X-RateLimit-Reset' = $User.ApiUsageResetDate.ToUnixTimeSeconds()
    'X-Tier' = $User.Tier
}
```

---

## Backend Integration Requirements

### 1. Subscription Management System

You'll need a backend system to handle:

#### Subscription Lifecycle
- **Creation**: When user upgrades from free to paid tier
- **Activation**: Enable tier features after successful payment
- **Renewal**: Auto-renew subscriptions monthly/yearly
- **Cancellation**: Handle user-initiated cancellations (keep access until period ends)
- **Expiration**: Downgrade to free tier when subscription expires
- **Payment Failures**: Handle failed payments, retry logic, grace periods

#### Payment Integration (Example: Stripe)
```powershell
# Webhook endpoint: POST /api/webhooks/stripe
function Invoke-WebhooksStripe {
    param($Request)
    
    # Verify webhook signature
    $Event = $Request.Body
    
    switch ($Event.type) {
        'customer.subscription.created' {
            # Upgrade user to paid tier
            $CustomerId = $Event.data.object.customer
            $User = Get-UserByStripeCustomerId -CustomerId $CustomerId
            Update-UserTier -UserId $User.UserId -Tier 'pro'
        }
        'customer.subscription.deleted' {
            # Downgrade to free tier
            $CustomerId = $Event.data.object.customer
            $User = Get-UserByStripeCustomerId -CustomerId $CustomerId
            Update-UserTier -UserId $User.UserId -Tier 'free'
        }
        'invoice.payment_failed' {
            # Send notification, update status to past_due
            $CustomerId = $Event.data.object.customer
            $User = Get-UserByStripeCustomerId -CustomerId $CustomerId
            Send-PaymentFailureNotification -User $User
        }
    }
}
```

### 2. Tier Management Functions

Create these helper functions:

```powershell
# Update-UserTier.ps1
function Update-UserTier {
    param(
        [string]$UserId,
        [string]$Tier,
        [string]$SubscriptionId
    )
    
    $Table = Get-LinkToMeTable -TableName 'Users'
    $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$UserId'" | Select-Object -First 1
    
    # Update tier
    $User.Tier = $Tier
    $User.TierStartDate = (Get-Date).ToUniversalTime()
    
    # Update limits based on new tier
    $TierLimits = Get-UserTierLimits -Tier $Tier
    $User.MaxLinks = $TierLimits.MaxLinks
    $User.AnalyticsRetentionDays = $TierLimits.AnalyticsRetentionDays
    $User.ApiRequestLimit = $TierLimits.ApiRequestsPerHour
    
    # Reset API usage counters for new tier
    $User.ApiRequestCount = 0
    $User.ApiUsageResetDate = (Get-Date).ToUniversalTime()
    
    Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
    
    # Log tier change
    Write-SecurityEvent -EventType 'TierChanged' -UserId $UserId -OldTier $User.Tier -NewTier $Tier -SubscriptionId $SubscriptionId
}
```

### 3. Scheduled Tasks

#### Daily Tier Expiration Check
```powershell
# Azure Function Timer Trigger: Run daily at 00:00 UTC
function Check-ExpiredSubscriptions {
    $Table = Get-LinkToMeTable -TableName 'Users'
    $Now = (Get-Date).ToUniversalTime()
    
    # Find users with expired subscriptions
    $ExpiredUsers = Get-LinkToMeAzDataTableEntity @Table -Filter "TierEndDate lt datetime'$($Now.ToString('o'))' and Tier ne 'free'"
    
    foreach ($User in $ExpiredUsers) {
        Update-UserTier -UserId $User.RowKey -Tier 'free'
        Send-SubscriptionExpiredNotification -User $User
    }
}
```

#### Monthly Usage Reports
```powershell
# Generate monthly reports for enterprise customers
function Generate-MonthlyUsageReport {
    param([string]$UserId)
    
    $Table = Get-LinkToMeTable -TableName 'ApiUsageHistory'
    $StartDate = (Get-Date).AddMonths(-1).ToString('yyyy-MM-dd')
    $EndDate = (Get-Date).ToString('yyyy-MM-dd')
    
    $UsageData = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey ge '$UserId-$StartDate' and PartitionKey le '$UserId-$EndDate'"
    
    # Generate report with total requests, top endpoints, error rates, etc.
}
```

### 4. Migration Script

Create a script to add tier fields to existing users:

```powershell
# Tools/Migrate-UsersToTierSystem.ps1
$Table = Get-LinkToMeTable -TableName 'Users'
$Users = Get-LinkToMeAzDataTableEntity @Table

foreach ($User in $Users) {
    # Add tier fields if they don't exist
    if (-not $User.Tier) {
        $User | Add-Member -NotePropertyName 'Tier' -NotePropertyValue 'free'
        $User | Add-Member -NotePropertyName 'TierStartDate' -NotePropertyValue (Get-Date).ToUniversalTime()
        $User | Add-Member -NotePropertyName 'ApiUsageResetDate' -NotePropertyValue (Get-Date).ToUniversalTime()
        $User | Add-Member -NotePropertyName 'ApiRequestCount' -NotePropertyValue 0
        $User | Add-Member -NotePropertyName 'ApiRequestLimit' -NotePropertyValue 100
        $User | Add-Member -NotePropertyName 'MaxLinks' -NotePropertyValue 5
        $User | Add-Member -NotePropertyName 'AnalyticsRetentionDays' -NotePropertyValue 7
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
    }
}
```

---

## Implementation Roadmap

### Phase 1: Database & Core Functions (Week 1)
1. ✅ Add tier fields to Users table schema
2. ✅ Create migration script for existing users
3. ✅ Implement `Get-UserTierLimits` function
4. ✅ Implement `Test-TierAccess` function
5. ✅ Update signup process to set default tier
6. ✅ Test with development data

### Phase 2: Tier Enforcement (Week 2)
1. ✅ Integrate tier checks into request router
2. ✅ Add tier validation to all admin endpoints
3. ✅ Implement feature-level restrictions (link count, analytics retention)
4. ✅ Add rate limit headers to responses
5. ✅ Update error messages with upgrade prompts
6. ✅ Test all endpoints with different tiers

### Phase 3: Subscription Management (Week 3-4)
1. ✅ Create Subscriptions table
2. ✅ Integrate payment processor (Stripe/PayPal)
3. ✅ Implement webhook handlers
4. ✅ Create tier upgrade/downgrade flows
5. ✅ Add subscription management UI endpoints
6. ✅ Test payment flows end-to-end

### Phase 4: Monitoring & Analytics (Week 5)
1. ✅ Create ApiUsageHistory table
2. ✅ Implement usage tracking
3. ✅ Create scheduled tasks (expiration check, reports)
4. ✅ Add monitoring dashboards
5. ✅ Set up alerts for rate limit violations
6. ✅ Test at scale

### Phase 5: Frontend Integration (Week 6)
1. ✅ Update frontend to display tier information
2. ✅ Add upgrade prompts when tier limits hit
3. ✅ Create pricing page
4. ✅ Add subscription management page
5. ✅ Handle 402 Payment Required responses
6. ✅ Final end-to-end testing

---

## Monitoring and Analytics

### Key Metrics to Track

#### Tier Distribution
- Number of users per tier
- Conversion rate (free → pro → enterprise)
- Churn rate by tier
- Average revenue per user (ARPU)

#### API Usage
- Requests per tier (daily/weekly/monthly)
- Most used endpoints per tier
- Rate limit violations by tier
- Average response time by tier

#### Business Metrics
- Monthly recurring revenue (MRR)
- Subscription renewals vs cancellations
- Failed payment rate
- Customer lifetime value (LTV)

### Logging Events

Add these security event types to `Write-SecurityEvent`:

```powershell
# New event types for tier system
Write-SecurityEvent -EventType 'TierAccessDenied'
Write-SecurityEvent -EventType 'TierRateLimitExceeded'
Write-SecurityEvent -EventType 'TierChanged'
Write-SecurityEvent -EventType 'SubscriptionCreated'
Write-SecurityEvent -EventType 'SubscriptionCancelled'
Write-SecurityEvent -EventType 'PaymentFailed'
```

### Azure Monitor Queries

```kusto
// Rate limit violations by tier
SecurityEvents
| where EventType == "TierRateLimitExceeded"
| summarize count() by Tier, bin(Timestamp, 1h)
| render timechart

// Tier access denials (upgrade opportunities)
SecurityEvents
| where EventType == "TierAccessDenied"
| summarize count() by Endpoint, RequiredTier
| order by count_ desc

// API usage by tier
ApiUsageHistory
| summarize RequestCount = count() by Tier, bin(Timestamp, 1d)
| render timechart
```

---

## Security Considerations

### 1. Prevent Tier Bypass
- Always validate tier on the server side (never trust client)
- Check tier before AND during endpoint execution
- Validate subscription status before processing payments

### 2. Secure Subscription Data
- Never expose payment processor customer IDs in API responses
- Store only references to payment processor objects, not full card details
- Verify webhook signatures from payment processors

### 3. Handle Edge Cases
- Grace periods for failed payments (e.g., 3 days)
- Grandfather existing users during tier rollout
- Allow scheduled downgrades (at period end, not immediate)
- Handle partial feature access during transitions

### 4. Rate Limiting
- Implement per-user rate limits (not just per-IP)
- Use exponential backoff for repeated violations
- Consider burst allowances for legitimate spikes
- Log all rate limit violations for monitoring

---

## Testing Strategy

### Unit Tests
```powershell
Describe "Tier Access Tests" {
    It "Should deny free tier access to analytics endpoint" {
        $User = @{ UserId = 'user-1'; Tier = 'free' }
        $Result = Test-TierAccess -User $User -Endpoint 'admin/getAnalytics'
        $Result.Allowed | Should -Be $false
    }
    
    It "Should allow pro tier access to analytics endpoint" {
        $User = @{ UserId = 'user-1'; Tier = 'pro' }
        $Result = Test-TierAccess -User $User -Endpoint 'admin/getAnalytics'
        $Result.Allowed | Should -Be $true
    }
    
    It "Should enforce link count limit for free tier" {
        $TierLimits = Get-UserTierLimits -Tier 'free'
        $TierLimits.MaxLinks | Should -Be 5
    }
}
```

### Integration Tests
- Test tier upgrade flow end-to-end
- Test tier downgrade when subscription expires
- Test rate limiting at tier boundaries
- Test webhook processing

### Load Tests
- Simulate rate limits being hit
- Test with high API usage across all tiers
- Verify performance of tier checks

---

## Frontend Changes Needed

### 1. Display Tier Information
```javascript
// Show current tier in user profile
const userTier = user.tier || 'free';
const tierBadge = <Badge color={tierColors[userTier]}>{userTier.toUpperCase()}</Badge>;
```

### 2. Handle Tier Restrictions
```javascript
// Handle 402 Payment Required responses
try {
  const response = await fetch('/api/admin/getAnalytics', {
    credentials: 'include'
  });
  
  if (response.status === 402) {
    const data = await response.json();
    // Show upgrade prompt
    showUpgradeModal({
      message: data.error,
      currentTier: data.currentTier,
      requiredTier: data.requiredTier,
      upgradeUrl: data.upgradeUrl
    });
    return;
  }
  
  // Process normal response
} catch (error) {
  // Handle error
}
```

### 3. Pricing Page
Create a pricing comparison page showing:
- Feature matrix (Free vs Pro vs Enterprise)
- Monthly/annual pricing toggle
- Clear upgrade buttons
- FAQ section

### 4. Usage Dashboard
Show users their current usage:
- API requests used / limit
- Links created / limit
- Current tier and benefits
- Upgrade CTA if approaching limits

---

## Cost Considerations

### Azure Table Storage
- Minimal cost impact (~$0.045 per 10k transactions)
- New tables: Subscriptions, ApiUsageHistory
- Increased writes for usage tracking

### Azure Functions
- Additional execution time for tier checks (~10-20ms per request)
- New scheduled functions (daily expiration check)
- Webhook endpoint for payment processing

### Payment Processing
- Stripe: 2.9% + $0.30 per transaction
- Refunds, disputes, currency conversion fees
- Consider passing fees to customers

---

## Support & Maintenance

### Customer Support Scenarios
1. **User wants to upgrade**: Direct to pricing page, process payment, upgrade tier
2. **User wants to cancel**: Process cancellation, keep access until period ends
3. **Payment failed**: Send notification, offer retry, grace period
4. **Tier limits hit**: Explain limits, offer upgrade, show usage stats
5. **Billing dispute**: Access subscription history, provide receipts

### Maintenance Tasks
- Monthly: Review tier distribution and conversion rates
- Weekly: Check for failed payments and expired subscriptions
- Daily: Monitor rate limit violations and API usage spikes
- Quarterly: Analyze pricing and adjust tier limits if needed

---

## Conclusion

Implementing tier-based API access restrictions requires:

1. **Database changes**: Add tier and usage tracking fields
2. **Middleware**: Validate tier access before endpoint execution
3. **Payment integration**: Handle subscriptions and billing
4. **Monitoring**: Track usage and business metrics
5. **Frontend updates**: Display tier info and handle restrictions

This system provides a solid foundation for monetizing your API while maintaining a good user experience. Start with Phase 1 (database and core functions) and progressively roll out additional features.

For questions or clarifications about any section, please refer to the existing codebase or create issues in the repository.
