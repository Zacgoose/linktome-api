# LinkTome API

Backend API for LinkTome - a modern Linktree alternative built on Azure.

**Frontend Repository:** [Zacgoose/linktome](https://github.com/Zacgoose/linktome)

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
- **Authentication:** JWT with PBKDF2-SHA256 password hashing
- **Frontend Integration:** Azure Static Web Apps

## Features

### Authentication & Security
- ✅ JWT-based authentication with Bearer tokens
- ✅ Strong password hashing (PBKDF2-SHA256, 100K iterations)
- ✅ Input validation and sanitization
- ✅ Protection against NoSQL injection
- ✅ Security headers on all responses
- ✅ Safe error handling (no information disclosure)
- ✅ Minimum password requirements

### API Endpoints

#### Public Endpoints (No Authentication Required)
- `POST /public/signup` - Register new user
- `POST /public/login` - Authenticate user
- `GET /public/getUserProfile?username={username}` - Get public profile and links

#### Admin Endpoints (Requires JWT Authentication)
- `GET /admin/getProfile` - Get authenticated user's profile
- `PUT /admin/updateProfile` - Update profile (displayName, bio, avatar)
- `GET /admin/getLinks` - Get user's links
- `PUT /admin/updateLinks` - Create, update, or delete links

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

## Testing

### Manual Testing with curl

```bash
# Sign up
curl -X POST http://localhost:7071/api/public/signup \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","username":"johndoe","password":"SecurePass123"}'

# Response includes accessToken
# {"user":{"userId":"...","email":"...","username":"..."},"accessToken":"eyJ..."}

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
- **Query Protection:** Azure Table Storage queries are sanitized
- **Error Handling:** Safe error messages (no information disclosure in production)
- **Security Headers:** X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, etc.

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
       "userId": "user-abc123",
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
       {"title": "GitHub", "url": "https://github.com/johndoe", "order": 1, "active": true},
       {"title": "Twitter", "url": "https://twitter.com/johndoe", "order": 2, "active": true}
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

Azure (Application Insights):
```bash
# View logs in Azure Portal → Function App → Monitor → Logs
# Or use Application Insights queries
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
