# LinkTome API

Backend API for LinkTome - a modern Linktree alternative built on Azure.

**Frontend Repository:** [Zacgoose/linktome](https://github.com/Zacgoose/linktome)

> 🚀 **New Feature Planning**: Agency/Multi-Account Profiles - See [Planning Documentation](./MULTI_ACCOUNT_PLANNING_README.md)

## Overview

LinkTome API is an Azure Function App built with PowerShell 7.4 that provides:
- User authentication with JWT tokens
- Profile management
- Link management for personal link-in-bio pages
- Secure Azure Table Storage integration

## Architecture

- **Runtime:** PowerShell 7.4
- **Platform:** Azure Functions v4
- **Storage:** Azure Table Storage
  - `Users` - User accounts and profiles (includes 2FA settings)
  - `Links` - User link collections
  - `ShortLinks` - URL shortener service (slug-based short links)
  - `TwoFactorSessions` - Temporary 2FA verification sessions
  - `RateLimits` - IP-based rate limiting tracking
  - `SecurityEvents` - Security event audit log
  - `Analytics` - Page views, link clicks, and short link redirect tracking
  - `FeatureUsage` - Feature access tracking for tier validation
- **Authentication:** JWT with PBKDF2-SHA256 password hashing
- **Frontend Integration:** Azure Static Web Apps (handles CORS and security headers)
- **Rate Limiting:** IP-based using Azure Table Storage (5 login/min, 3 signup/hour)
- **Logging:** Azure Table Storage for security events and analytics
- **Subscription Tiers:** Free, Premium, and Enterprise tiers with feature-based access control

## Features

### Authentication & Security
- ✅ JWT-based authentication with Bearer tokens
- ✅ Strong password hashing (PBKDF2-SHA256, 100K iterations)
- ✅ Two-Factor Authentication (2FA) support
  - ✅ Email-based 2FA with 6-digit codes (SHA-256 hashed)
  - ✅ TOTP-based 2FA (compatible with Google Authenticator, Authy, etc.)
  - ✅ TOTP secrets encrypted at rest (AES-256)
  - ✅ Support for dual 2FA (both email and TOTP enabled)
  - ✅ Backup codes for account recovery (SHA-256 hashed, single-use)
  - ✅ Secure session management with expiration
  - ✅ 2FA is optional (user opt-in)
- ✅ Input validation and sanitization
- ✅ Protection against NoSQL injection
- ✅ Rate limiting (5 login attempts/min, 3 signups/hour per IP)
- ✅ Security event logging to Azure Table Storage
- ✅ Safe error handling (no information disclosure)
- ✅ Minimum password requirements

### Analytics
- ✅ Automatic page view tracking on profile loads
- ✅ Link click tracking via public endpoint
- ✅ Short link redirect tracking with detailed analytics
- ✅ Server-side analytics storage
- ✅ Tracks IP address, user agent, and referrer
- ✅ Analytics dashboard data via admin endpoint (views, clicks, popular links)
- ✅ Dashboard statistics (total links, views, clicks, unique visitors)
- ✅ Time-series data (views and clicks by day)
- ✅ **Advanced analytics restricted to Pro/Premium/Enterprise tiers**

### URL Shortener
- ✅ Create short links with auto-generated slugs
- ✅ Tier-based limits (Free: not available, Pro: 5, Premium: 20, Enterprise: unlimited)
- ✅ Click tracking and analytics
- ✅ Active/inactive toggle for links
- ✅ Public redirect endpoint
- ✅ Detailed analytics (Pro+ tiers)

### Subscription Tiers & Feature Gating
- ✅ Four-tier system: Free, Pro, Premium, Enterprise
- ✅ Tier-based feature access control
- ✅ Link limits by tier (Free: 10, Pro: 50, Premium: 100, Enterprise: unlimited)
- ✅ Short link limits by tier (Free: not available, Pro: 5, Premium: 20, Enterprise: unlimited)
- ✅ Advanced analytics for Pro/Premium/Enterprise users only
- ✅ Feature usage tracking and analytics
- ✅ Automatic subscription expiration handling
- ✅ Graceful degradation for expired subscriptions
- 📄 See [TIER_SYSTEM.md](./TIER_SYSTEM.md) for complete documentation

### Customization
- ✅ Appearance customization (theme: light/dark)
- ✅ Button style options (rounded, square, pill)
- ✅ Custom colors (background, text, buttons)
- ✅ Settings applied to public profile pages

### API Endpoints

#### Public Endpoints (No Authentication Required)
- `POST /public/signup` - Register new user
- `POST /public/login` - Authenticate user (returns 2FA session if enabled)
- `POST /public/2fatoken?action=verify` - Verify 2FA code and complete authentication
- `POST /public/2fatoken?action=resend` - Resend 2FA email code
- `GET /public/getUserProfile?username={username}` - Get public profile and links (auto-tracks page view)
- `POST /public/trackLinkClick` - Track link click analytics (requires username and linkId)
- `GET /public/l?slug={slug}` - Redirect short link to target URL (auto-tracks redirect analytics)

#### Admin Endpoints (Requires JWT Authentication)
- `GET /admin/getProfile` - Get authenticated user's profile
- `PUT /admin/updateProfile` - Update profile (displayName, bio, avatar)
- `GET /admin/getLinks` - Get user's links
- `PUT /admin/updateLinks` - Create, update, or delete links
- `GET /admin/getShortLinks` - Get user's short links with usage statistics
- `PUT /admin/updateShortLinks` - Create, update, or delete short links
- `GET /admin/getShortLinkAnalytics?slug={slug}` - Get detailed analytics for short links (Pro+ tiers)
- `GET /admin/getAnalytics` - Get analytics data (page views, link clicks, unique visitors, views/clicks by day, most popular links)
- `GET /admin/getDashboardStats` - Get dashboard statistics (total links, views, visitors)
- `GET /admin/getAppearance` - Get appearance settings (theme, colors, button style)
- `PUT /admin/updateAppearance` - Update appearance settings
- `POST /admin/2fatokensetup?action=setup` - Setup 2FA (generates TOTP secret, QR code, backup codes)
- `POST /admin/2fatokensetup?action=enable` - Enable 2FA after verification
- `POST /admin/2fatokensetup?action=disable` - Disable 2FA

## Local Development Setup

### Prerequisites
- [PowerShell 7.4+](https://github.com/PowerShell/PowerShell/releases)
- [Azure Functions Core Tools v4](https://docs.microsoft.com/azure/azure-functions/functions-run-local)
- [Azure Storage Emulator](https://docs.microsoft.com/azure/storage/common/storage-use-emulator) or [Azurite](https://github.com/Azure/Azurite)
- [Visual Studio Code](https://code.visualstudio.com/) (recommended)
- [Azure Functions Extension for VS Code](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azurefunctions) (recommended)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Zacgoose/linktome-api.git
   cd linktome-api
   ```

2. **Configure local settings**
   
   The repository includes `local.settings.json` with development defaults:
   ```json
   {
     "IsEncrypted": false,
     "Values": {
       "FUNCTIONS_WORKER_RUNTIME": "powershell",
       "FUNCTIONS_WORKER_RUNTIME_VERSION": "7.4",
       "AzureWebJobsStorage": "UseDevelopmentStorage=true",
       "JWT_SECRET": "dev-secret-change-in-production-please-make-this-very-long-and-random-at-least-64-characters"
     }
   }
   ```

3. **Start Azure Storage Emulator**
   ```bash
   # Option 1: Azurite (recommended)
   azurite --silent --location ./azurite --debug ./azurite/debug.log
   
   # Option 2: Azure Storage Emulator (Windows only)
   AzureStorageEmulator.exe start
   ```

4. **Start the Function App**
   ```bash
   func start
   ```

5. **Test the API**
   ```bash
   # Health check (get a public profile - will return 404 if no users exist)
   curl http://localhost:7071/api/public/getUserProfile?username=testuser
   
   # Create a test user
   curl -X POST http://localhost:7071/api/public/signup \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","username":"testuser","password":"TestPass123"}'
   ```

### Development Environment Variables

All environment variables are configured in `local.settings.json`:

| Variable | Description | Default |
|----------|-------------|---------|
| `FUNCTIONS_WORKER_RUNTIME` | Runtime for Azure Functions | `powershell` |
| `FUNCTIONS_WORKER_RUNTIME_VERSION` | PowerShell version | `7.4` |
| `AzureWebJobsStorage` | Storage connection string | `UseDevelopmentStorage=true` |
| `JWT_SECRET` | Secret key for JWT signing | Dev secret (64+ chars) |
| `AZURE_FUNCTIONS_ENVIRONMENT` | Environment indicator | `Development` (implicit) |
| `ENCRYPTION_KEY` | AES-256 key for encrypting TOTP secrets | **Exactly 32 characters required** |
| `SMTP_SERVER` | SMTP server for 2FA emails | Required for email 2FA |
| `SMTP_PORT` | SMTP port (usually 587) | Required for email 2FA |
| `SMTP_USERNAME` | SMTP username | Required for email 2FA |
| `SMTP_PASSWORD` | SMTP password | Required for email 2FA |
| `SMTP_FROM` | Sender email address | Required for email 2FA |

## Testing

### Manual Testing with curl

```bash
# Sign up
curl -X POST http://localhost:7071/api/public/signup \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","username":"johndoe","password":"SecurePass123"}'

# Response includes accessToken
# {"user":{"UserId":"...","email":"...","username":"..."},"accessToken":"eyJ..."}

# Login
curl -X POST http://localhost:7071/api/public/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"SecurePass123"}'

# Get profile (authenticated - use token from signup/login)
curl http://localhost:7071/api/admin/getProfile \
  -H "Authorization: Bearer eyJ..."

# Update profile
curl -X PUT http://localhost:7071/api/admin/updateProfile \
  -H "Authorization: Bearer eyJ..." \
  -H "Content-Type: application/json" \
  -d '{"displayName":"John Doe","bio":"My bio","avatar":"https://example.com/avatar.jpg"}'

# Get public profile
curl "http://localhost:7071/api/public/getUserProfile?username=johndoe"
```

### Using Postman

Import the collection (if available) or manually create requests using the endpoints above.

## Project Structure

```
linktome-api/
├── HttpTrigger/              # Azure Function trigger configuration
│   └── function.json         # HTTP trigger binding
├── Modules/
│   ├── LinkTomeCore/         # Core functionality
│   │   ├── Auth/            # JWT and authentication
│   │   ├── Table/           # Azure Table Storage helpers
│   │   ├── Validation/      # Input validation
│   │   ├── Security/        # Security headers and CORS
│   │   └── Error/           # Safe error handling
│   ├── LinkTomeEntrypoints/ # Request routing
│   ├── PublicApi/           # Public endpoint handlers
│   ├── PrivateApi/          # Admin endpoint handlers
│   ├── AzBobbyTables/       # Azure Table Storage wrapper
│   └── PSJsonWebToken/      # JWT library
├── Shared/                   # Shared resources
├── Tools/                    # Development tools
├── host.json                 # Function App configuration
├── local.settings.json       # Local environment variables
├── profile.ps1              # Startup script
├── requirements.psd1         # Module dependencies
└── version_latest.txt        # API version

Documentation:
├── SECURITY_REVIEW.md                    # Comprehensive security analysis
├── SECURITY_IMPLEMENTATION_ROADMAP.md    # Implementation guide
├── DEPLOYMENT_SECURITY_CHECKLIST.md      # Deployment checklist
└── README.md                             # This file
```

## Security

This API implements comprehensive security measures:

- **Input Validation:** All inputs are validated and sanitized
- **Authentication:** JWT tokens with 24-hour expiration
- **Password Security:** PBKDF2-SHA256 with 100,000 iterations
- **Query Protection:** Azure Table Storage queries are sanitized to prevent NoSQL injection
- **Rate Limiting:** IP-based limits on login and signup endpoints
- **Security Event Logging:** Comprehensive audit trail in Azure Table Storage
- **Error Handling:** Safe error messages (no information disclosure in production)
- **Security Headers & CORS:** Handled automatically by Azure Static Web Apps integration

For detailed security information, see:
- [SECURITY_REVIEW.md](./SECURITY_REVIEW.md) - Complete security analysis
- [DEPLOYMENT_SECURITY_CHECKLIST.md](./DEPLOYMENT_SECURITY_CHECKLIST.md) - Production deployment checklist

## Deployment

### Prerequisites
- Azure subscription
- Azure CLI installed and configured
- Azure Functions Core Tools v4

### Production Deployment

See [DEPLOYMENT_SECURITY_CHECKLIST.md](./DEPLOYMENT_SECURITY_CHECKLIST.md) for complete deployment instructions.

**Quick Start:**
```bash
# Deploy to Azure Function App
func azure functionapp publish <function-app-name>
```

**Important:** Before deploying to production:
1. Generate a strong JWT_SECRET (128+ characters)
2. Configure environment variables in Azure Portal
3. Enable HTTPS only
4. Set minimum TLS to 1.2
5. Link with Azure Static Web App for automatic CORS handling

## Environment Variables (Production)

| Variable | Required | Description |
|----------|----------|-------------|
| `JWT_SECRET` | ✅ Yes | JWT signing secret (min 64 chars, 128+ recommended) |
| `AzureWebJobsStorage` | ✅ Yes | Azure Storage connection string (auto-configured) |
| `AZURE_FUNCTIONS_ENVIRONMENT` | ✅ Yes | Set to `Production` |
| `CORS_ALLOWED_ORIGINS` | ⚠️ Optional | Only if NOT using Azure Static Web Apps |
| `ENCRYPTION_KEY` | ⚠️ Optional | AES-256 key for TOTP secrets (**exactly 32 chars**, required for TOTP 2FA) |
| `SMTP_SERVER` | ⚠️ Optional | SMTP server for 2FA emails (required for email 2FA) |
| `SMTP_PORT` | ⚠️ Optional | SMTP port (required for email 2FA) |
| `SMTP_USERNAME` | ⚠️ Optional | SMTP username (required for email 2FA) |
| `SMTP_PASSWORD` | ⚠️ Optional | SMTP password (required for email 2FA) |
| `SMTP_FROM` | ⚠️ Optional | Sender email address (required for email 2FA) |

## API Documentation

### Request/Response Format

All requests and responses use JSON.

### Authentication

Admin endpoints require JWT authentication via Bearer token:
```
Authorization: Bearer <jwt-token>
```

### Error Responses

```json
{
  "error": "Error message"
}
```

### Example: Complete User Flow

1. **Sign Up**
   ```bash
   POST /public/signup
   {
     "email": "user@example.com",
     "username": "johndoe",
     "password": "SecurePass123"
   }
   ```
   Response:
   ```json
   {
     "user": {
       "UserId": "user-abc123",
       "email": "user@example.com",
       "username": "johndoe"
     },
     "accessToken": "eyJhbGciOi..."
   }
   ```

2. **Update Profile**
   ```bash
   PUT /admin/updateProfile
   Authorization: Bearer eyJhbGciOi...
   {
     "displayName": "John Doe",
     "bio": "Software Developer | Tech Enthusiast",
     "avatar": "https://example.com/avatar.jpg"
   }
   ```

3. **Add Links**
   ```bash
   PUT /admin/updateLinks
   Authorization: Bearer eyJhbGciOi...
   {
     "links": [
       {"operation": "add", "title": "GitHub", "url": "https://github.com/johndoe", "order": 1, "active": true},
       {"operation": "add", "title": "Twitter", "url": "https://twitter.com/johndoe", "order": 2, "active": true}
     ]
   }
   ```

4. **View Public Profile**
   ```bash
   GET /public/getUserProfile?username=johndoe
   ```
   Response:
   ```json
   {
     "username": "johndoe",
     "displayName": "John Doe",
     "bio": "Software Developer | Tech Enthusiast",
     "avatar": "https://example.com/avatar.jpg",
     "links": [
       {"id": "link-123", "title": "GitHub", "url": "https://github.com/johndoe", "order": 1},
       {"id": "link-456", "title": "Twitter", "url": "https://twitter.com/johndoe", "order": 2}
     ]
   }
   ```

### Example: URL Shortener Flow

1. **Create Short Link** (Pro tier required)
   ```bash
   PUT /admin/updateShortLinks
   Authorization: Bearer eyJhbGciOi...
   {
     "shortLinks": [
       {
         "operation": "add",
         "targetUrl": "https://github.com/johndoe/awesome-project",
         "title": "My Awesome Project",
         "active": true
       }
     ]
   }
   ```
   Response (includes auto-generated slug):
   ```json
   {
     "success": true,
     "created": [
       {
         "slug": "a3x9k2",
         "targetUrl": "https://github.com/johndoe/awesome-project",
         "title": "My Awesome Project"
       }
     ]
   }
   ```

2. **List Short Links**
   ```bash
   GET /admin/getShortLinks
   Authorization: Bearer eyJhbGciOi...
   ```
   Response:
   ```json
   {
     "shortLinks": [
       {
         "slug": "a3x9k2",
         "targetUrl": "https://github.com/johndoe/awesome-project",
         "title": "My Awesome Project",
         "active": true,
         "clicks": 42,
         "createdAt": "2024-01-15T10:30:00Z",
         "lastClickedAt": "2024-01-20T14:25:00Z"
       }
     ],
     "total": 1
   }
   ```

3. **Public Redirect** (Anyone can access)
   ```bash
   GET /public/l?slug=a3x9k2
   ```
   Response: HTTP 301 Redirect to target URL
   ```
   Location: https://github.com/johndoe/awesome-project
   ```

4. **Get Analytics** (Pro+ tiers only)
   ```bash
   GET /admin/getShortLinkAnalytics?slug=a3x9k2
   Authorization: Bearer eyJhbGciOi...
   ```
   Response:
   ```json
   {
     "summary": {
       "totalRedirects": 42,
       "uniqueVisitors": 28
     },
     "hasAdvancedAnalytics": true,
     "topShortLinks": [
       {
         "slug": "a3x9k2",
         "targetUrl": "https://github.com/johndoe/awesome-project",
         "clicks": 42
       }
     ],
     "redirectsByDay": [
       {"date": "2024-01-15", "clicks": 5},
       {"date": "2024-01-16", "clicks": 12},
       {"date": "2024-01-17", "clicks": 25}
     ],
     "topReferrers": [
       {"referrer": "https://twitter.com", "count": 18},
       {"referrer": "https://reddit.com", "count": 10}
     ]
   }
   ```

### Short Link Request/Response Formats

#### Create/Update Short Link
**Request (Add Operation):**
```json
{
  "shortLinks": [
    {
      "operation": "add",
      "targetUrl": "https://example.com/very/long/url",
      "title": "Optional title",
      "active": true
    }
  ]
}
```

**Response (Add Operation):**
```json
{
  "success": true,
  "created": [
    {
      "slug": "a3x9k2",
      "targetUrl": "https://example.com/very/long/url",
      "title": "Optional title"
    }
  ]
}
```

**Request (Update/Remove Operations):**
```json
{
  "shortLinks": [
    {
      "operation": "update",        // or "remove"
      "slug": "a3x9k2",             // Required: 6-char auto-generated slug
      "targetUrl": "https://...",   // Optional for update
      "title": "Updated title",     // Optional for update
      "active": false               // Optional for update
    }
  ]
}
```

**Validation Rules:**
- `slug`: Auto-generated 6-character string (lowercase letters and numbers)
- 2.18 billion possible combinations (36^6)
- `targetUrl`: Valid http/https URL, max 2048 characters
- `title`: Optional, max 100 characters

**Tier Limits:**
- Free: Not available (upgrade to Pro required)
- Pro: 5 short links
- Premium: 20 short links
- Enterprise: Unlimited short links

**Error Responses:**
```json
{
  "error": "Short links are not available on the Free plan. Upgrade to Pro or higher to create short links.",
  "upgradeRequired": true,
  "currentTier": "free",
  "feature": "shortLinks"
}
```

```json
{
  "error": "Short link limit exceeded. Your Pro plan allows up to 5 short links. You currently have 5 short links.",
  "currentCount": 5,
  "limit": 5
}
```

## Troubleshooting

### Common Issues

**Issue:** "Function not found" error
- **Solution:** Ensure module imports are working. Check `profile.ps1` execution logs.

**Issue:** "JWT_SECRET must be at least 64 characters"
- **Solution:** Generate a strong secret: `openssl rand -base64 96`

**Issue:** "Cannot connect to storage"
- **Solution:** Ensure Azure Storage Emulator or Azurite is running

**Issue:** 401 Unauthorized on admin endpoints
- **Solution:** Verify JWT token is included in Authorization header as `Bearer <token>`

### Viewing Logs

Local development:
```bash
# Logs are displayed in console where `func start` is running
```

Azure:
```bash
# View logs in Azure Portal → Function App → Monitor → Logs
# View security events in Azure Table Storage → SecurityEvents table
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Security Contributions

If you discover a security vulnerability:
1. **DO NOT** open a public issue
2. Email security details to [your-security-email]
3. Include steps to reproduce and potential impact

## License

[Specify your license here]

## Support

- **Issues:** https://github.com/Zacgoose/linktome-api/issues
- **Discussions:** https://github.com/Zacgoose/linktome-api/discussions
- **Frontend:** https://github.com/Zacgoose/linktome

## Acknowledgments

- PowerShell JWT implementation: [PSJsonWebToken](https://www.powershellgallery.com/packages/PSJsonWebToken/)
- Azure Table Storage wrapper: AzBobbyTables (bundled)
- Inspired by Linktree and similar link-in-bio services

---

**Version:** 1.0.0  
**Last Updated:** December 21, 2025
