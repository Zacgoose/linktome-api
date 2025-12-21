# Deployment Security Checklist

This checklist ensures that all security measures are properly configured before deploying to production.

## Architecture Overview

**Frontend:** Azure Static Web Apps (https://github.com/Zacgoose/linktome)  
**Backend:** Azure Function App (PowerShell 7.4) - This repository  
**Storage:** Azure Table Storage  
**Authentication:** JWT with Bearer tokens

## Pre-Deployment Checklist

### 1. Environment Variables Configuration

#### Required Environment Variables

Configure these in Azure Function App → Configuration → Application settings:

- [ ] **`JWT_SECRET`** (CRITICAL)
  - Minimum 64 characters (128+ recommended)
  - Use cryptographically secure random string
  - Generate with: 
    - Linux/Mac: `openssl rand -base64 96`
    - Windows PowerShell: `$bytes = New-Object byte[] 96; [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes); [Convert]::ToBase64String($bytes)`
    - Or simpler: `openssl rand -base64 96` (if OpenSSL is installed)
  - Never reuse dev secret in production
  - Store securely (consider Azure Key Vault)

- [ ] **`AzureWebJobsStorage`**
  - Azure Storage connection string
  - Should be automatically configured by Azure
  - Verify it's not using development storage

- [ ] **`AZURE_FUNCTIONS_ENVIRONMENT`**
  - Set to `Production` for production deployments
  - This enables secure error handling and JWT validation

- [ ] **`CORS_ALLOWED_ORIGINS`** (Optional)
  - Only needed if NOT using Azure Static Web Apps
  - Comma-separated list of allowed origins
  - Example: `https://yourdomain.com,https://www.yourdomain.com`

### 2. Azure Static Web Apps Configuration

If using Azure Static Web Apps (recommended):

- [ ] Link Function App as backend API in Static Web App configuration
  - Navigate to: Static Web App → APIs → Link to a Function App
  - Select your Function App from the list
  - CORS will be automatically configured

- [ ] Configure custom domain with HTTPS
  - Static Web Apps automatically provision SSL certificates
  - Enforce HTTPS only

- [ ] Review Static Web App authentication providers if using
  - Can work alongside or instead of custom JWT auth

### 3. Function App Security Settings

Configure in Azure Portal → Function App:

- [ ] **HTTPS Only**: Enabled
  - Configuration → General Settings → HTTPS Only: On

- [ ] **Minimum TLS Version**: 1.2
  - Configuration → General Settings → Minimum TLS Version: 1.2

- [ ] **HTTP Version**: 2.0 (recommended)
  - Configuration → General Settings → HTTP Version: 2.0

- [ ] **Managed Identity**: Enable (recommended)
  - Identity → System assigned → Status: On
  - Allows secure access to Azure resources without credentials

- [ ] **IP Restrictions** (if applicable)
  - Networking → Access Restrictions
  - Configure if you need to limit access by IP

### 4. Application Insights & Monitoring

- [ ] Enable Application Insights
  - Monitoring → Application Insights → Turn on Application Insights

- [ ] Configure alerts for security events
  - Monitor → Alerts → New alert rule
  - Suggested alerts:
    - High rate of 401 Unauthorized responses
    - High rate of 400 Bad Request (possible attack)
    - Function failures
    - High response times

- [ ] Configure log retention
  - Application Insights → Usage and estimated costs
  - Set appropriate retention period (90+ days recommended)

### 5. Azure Table Storage Security

- [ ] Verify connection string is secure
  - Should use HTTPS endpoints
  - Should not be publicly accessible

- [ ] Configure backup/disaster recovery
  - Storage Account → Data protection
  - Enable soft delete for tables (if available)
  - Document backup strategy

- [ ] Enable storage analytics logging
  - Storage Account → Monitoring → Diagnostic settings
  - Log all read, write, and delete operations

### 6. Code Security Verification

- [ ] Verify all endpoints use input validation
  - All public endpoints validate and sanitize inputs
  - All admin endpoints check authentication

- [ ] Test JWT authentication
  - Valid tokens work correctly
  - Expired tokens are rejected
  - Tampered tokens are rejected
  - Missing Authorization header returns 401

- [ ] Verify error handling
  - Production errors don't leak sensitive information
  - Detailed errors are logged server-side only

- [ ] Test rate limiting (once implemented)
  - Authentication endpoints have rate limits
  - Legitimate users aren't blocked

## Deployment Steps

### First-Time Deployment

1. **Create Azure Resources**
   ```bash
   # Create Resource Group
   az group create --name linktome-prod --location eastus
   
   # Create Storage Account
   az storage account create \
     --name linktomestorage \
     --resource-group linktome-prod \
     --location eastus \
     --sku Standard_LRS
   
   # Create Function App
   az functionapp create \
     --name linktome-api \
     --resource-group linktome-prod \
     --storage-account linktomestorage \
     --runtime powershell \
     --runtime-version 7.4 \
     --functions-version 4 \
     --os-type Linux
   ```

2. **Configure Environment Variables**
   ```bash
   # Generate JWT Secret
   JWT_SECRET=$(openssl rand -base64 96)
   
   # Set environment variables
   az functionapp config appsettings set \
     --name linktome-api \
     --resource-group linktome-prod \
     --settings \
       "JWT_SECRET=$JWT_SECRET" \
       "AZURE_FUNCTIONS_ENVIRONMENT=Production"
   ```

3. **Deploy Code**
   ```bash
   # From repository root
   func azure functionapp publish linktome-api
   ```

4. **Link to Static Web App**
   - Navigate to Static Web App in Azure Portal
   - Go to APIs → Link to a Function App
   - Select `linktome-api`

### Subsequent Deployments

1. **Test in staging slot (optional but recommended)**
   ```bash
   # Create staging slot
   az functionapp deployment slot create \
     --name linktome-api \
     --resource-group linktome-prod \
     --slot staging
   
   # Deploy to staging
   func azure functionapp publish linktome-api --slot staging
   
   # Test staging endpoint
   # If tests pass, swap slots
   az functionapp deployment slot swap \
     --name linktome-api \
     --resource-group linktome-prod \
     --slot staging
   ```

2. **Direct deployment**
   ```bash
   func azure functionapp publish linktome-api
   ```

## Post-Deployment Verification

### Functional Tests

- [ ] **Public Endpoints**
  - [ ] POST `/public/signup` - Create new account
  - [ ] POST `/public/login` - Login with credentials
  - [ ] GET `/public/getUserProfile?username=testuser` - Get public profile

- [ ] **Admin Endpoints (with valid JWT)**
  - [ ] GET `/admin/getProfile` - Get authenticated user profile
  - [ ] PUT `/admin/updateProfile` - Update profile
  - [ ] GET `/admin/getLinks` - Get user's links
  - [ ] PUT `/admin/updateLinks` - Update links

### Security Tests

- [ ] **Authentication Tests**
  - [ ] Admin endpoints return 401 without Authorization header
  - [ ] Admin endpoints return 401 with invalid JWT
  - [ ] Admin endpoints return 401 with expired JWT
  - [ ] Admin endpoints work with valid JWT

- [ ] **Input Validation Tests**
  - [ ] Invalid email format is rejected in signup/login
  - [ ] Invalid username format is rejected
  - [ ] Weak password is rejected in signup
  - [ ] Invalid URL is rejected in link creation
  - [ ] Overly long inputs are rejected

- [ ] **Security Headers Tests**
  - [ ] Verify security headers are present in responses:
    ```bash
    curl -I https://linktome-api.azurewebsites.net/api/public/getUserProfile?username=test
    ```
  - [ ] Check for: X-Content-Type-Options, X-Frame-Options, X-XSS-Protection

- [ ] **CORS Tests (if not using Azure Static Web Apps)**
  - [ ] Allowed origins can make requests
  - [ ] Disallowed origins are blocked

### Performance Tests

- [ ] Function cold start time is acceptable (< 10 seconds)
- [ ] Response times are acceptable
  - Public endpoints: < 500ms
  - Admin endpoints: < 1 second

### Monitoring Verification

- [ ] Application Insights is receiving logs
  - Check Azure Portal → Function App → Application Insights
  - Verify recent requests are visible

- [ ] Alerts are configured and working
  - Send test failure to verify alert triggers

## Security Incident Response

If a security issue is discovered:

1. **Immediate Actions**
   - Rotate JWT_SECRET immediately
   - Review recent access logs
   - Disable compromised accounts
   - Document the incident

2. **Investigation**
   - Check Application Insights for suspicious activity
   - Review Azure Activity Log
   - Identify scope of breach

3. **Remediation**
   - Deploy security fixes
   - Force all users to re-authenticate (by rotating JWT_SECRET)
   - Notify affected users if required

4. **Prevention**
   - Update security measures
   - Add monitoring for similar issues
   - Review and update this checklist

## Ongoing Security Maintenance

### Weekly
- [ ] Review Application Insights logs for anomalies
- [ ] Check for failed login attempts
- [ ] Monitor error rates

### Monthly
- [ ] Review access logs
- [ ] Update Azure Function App runtime if needed
- [ ] Review and test disaster recovery procedures

### Quarterly
- [ ] Rotate JWT_SECRET (if possible without service disruption)
- [ ] Security audit of codebase
- [ ] Review and update dependencies
- [ ] Penetration testing (recommended)

### Annually
- [ ] Comprehensive security review
- [ ] Update SSL certificates (automatic with Azure, but verify)
- [ ] Review compliance requirements (GDPR, etc.)

## Rollback Procedure

If issues are discovered after deployment:

1. **Using Deployment Slots (if configured)**
   ```bash
   az functionapp deployment slot swap \
     --name linktome-api \
     --resource-group linktome-prod \
     --slot staging
   ```

2. **Manual Rollback**
   ```bash
   # Get previous deployment
   az functionapp deployment list-publishing-credentials \
     --name linktome-api \
     --resource-group linktome-prod
   
   # Redeploy previous version from source control
   git checkout <previous-commit>
   func azure functionapp publish linktome-api
   ```

## Support & Resources

### Documentation
- [Azure Functions Security](https://docs.microsoft.com/azure/azure-functions/security-concepts)
- [Azure Static Web Apps](https://docs.microsoft.com/azure/static-web-apps/)
- [Security Review Document](./SECURITY_REVIEW.md)
- [Implementation Roadmap](./SECURITY_IMPLEMENTATION_ROADMAP.md)

### Monitoring Dashboards
- Application Insights: https://portal.azure.com → Application Insights
- Function App Logs: https://portal.azure.com → Function App → Monitor

### Emergency Contacts
- Azure Support: https://azure.microsoft.com/support/
- Security Issues: [Document your security contact information here]

---

**Last Updated:** December 21, 2025  
**Next Review Date:** [Schedule next review]
