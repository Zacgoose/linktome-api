# 2FA Implementation Summary

## Overview

This document summarizes the Two-Factor Authentication (2FA) implementation for the LinkToMe API, based on the frontend team's requirements document.

## Implementation Details

### New Features

1. **Email-based 2FA**
   - 6-digit cryptographically secure codes
   - 10-minute expiration
   - Rate limiting: max 5 verification attempts per session
   - Rate limiting: 60-second cooldown between resend requests
   - Codes are hashed before storage using SHA-256

2. **TOTP-based 2FA**
   - RFC 6238 compliant implementation
   - Compatible with Google Authenticator, Authy, 1Password, etc.
   - BASE32-encoded secrets
   - Secrets encrypted at rest using AES-256
   - 30-second time step
   - Accepts tokens from ±1 time window (90 seconds total)

3. **Backup Codes**
   - 10 single-use backup codes generated per user
   - Hashed before storage using SHA-256
   - Can be used when primary 2FA method is unavailable
   - Automatically removed after use

4. **Dual 2FA Support**
   - Users can enable both email and TOTP
   - Either method can be used for verification
   - Email code sent automatically on login
   - Frontend can present choice to user

5. **Optional 2FA**
   - 2FA is disabled by default for all users
   - Users must opt-in to enable 2FA
   - Only enforced for users who have enabled it

### API Endpoints

#### POST /api/public/2fatoken?action=verify
Verify a 2FA code and complete authentication. Accepts email codes, TOTP codes, or backup codes.

**Request:**
```json
{
  "sessionId": "tfa-12345-...",
  "token": "123456",  // Email code, TOTP code, or backup code
  "method": "email"  // optional, informational only
}
```

**Success Response (200):**
```json
{
  "user": {
    "UserId": "user-...",
    "email": "user@example.com",
    "username": "johndoe",
    // ... other user fields
  }
}
```

**Error Responses:**
- 401: Session expired or invalid
- 400: Invalid verification code
- 401: Maximum attempts exceeded

**Note:** Backup codes are automatically detected and validated if email/TOTP verification fails.

#### POST /api/public/2fatoken?action=resend
Resend email 2FA code (only for email method).

**Request:**
```json
{
  "sessionId": "tfa-12345-..."
}
```

**Success Response (200):**
```json
{
  "message": "Code resent successfully"
}
```

**Error Responses:**
- 401: Session expired or invalid
- 400: Not an email 2FA session
- 429: Rate limit exceeded (60s cooldown)

#### POST /api/public/2fatoken?action=setup (Requires Authentication)
Setup 2FA for the authenticated user. Generates TOTP secret, QR code, and backup codes.

**Request:**
```json
{
  "type": "totp"  // "email", "totp", or "both"
}
```

**Success Response (200):**
```json
{
  "message": "2FA setup initiated",
  "type": "totp",
  "data": {
    "totp": {
      "secret": "BASE32SECRET...",
      "qrCodeUri": "otpauth://totp/LinkToMe:user@example.com?secret=...",
      "backupCodes": ["CODE1234", "CODE5678", ...],
      "issuer": "LinkToMe",
      "accountName": "user@example.com"
    }
  },
  "note": "Please verify TOTP code before enabling. Use action=enable to complete setup."
}
```

**Error Responses:**
- 401: Authentication required
- 500: Setup failed

#### POST /api/public/2fatoken?action=enable (Requires Authentication)
Enable 2FA after verifying it works. Requires a valid TOTP token for verification.

**Request:**
```json
{
  "type": "totp",  // "email", "totp", or "both"
  "token": "123456"  // Required for TOTP, not needed for email only
}
```

**Success Response (200):**
```json
{
  "message": "Two-factor authentication enabled successfully",
  "type": "totp",
  "emailEnabled": false,
  "totpEnabled": true
}
```

**Error Responses:**
- 401: Authentication required
- 400: Invalid verification code
- 400: TOTP not set up (need to call setup first)

#### POST /api/public/2fatoken?action=disable (Requires Authentication)
Disable 2FA for the authenticated user.

**Success Response (200):**
```json
{
  "message": "Two-factor authentication disabled successfully",
  "emailEnabled": false,
  "totpEnabled": false
}
```

**Error Responses:**
- 401: Authentication required

### Modified Endpoints

#### POST /api/public/login
Now checks for 2FA and returns session ID if enabled.

**With 2FA Enabled Response (200):**
```json
{
  "requiresTwoFactor": true,
  "sessionId": "tfa-12345-...",
  "twoFactorMethod": "both",  // "email", "totp", or "both"
  "availableMethods": ["email", "totp"]
}
```

**Without 2FA Response (200):**
```json
{
  "user": {
    // ... user fields as before
  }
}
```

#### POST /api/public/signup
New users now include 2FA fields (default: disabled).

### Database Schema Changes

#### Users Table
Added fields:
- `TwoFactorEmailEnabled` (boolean) - Email 2FA enabled
- `TwoFactorTotpEnabled` (boolean) - TOTP 2FA enabled
- `TotpSecret` (string) - Encrypted TOTP secret (AES-256, BASE32)
- `BackupCodes` (string) - JSON array of hashed backup codes (SHA-256)

#### TwoFactorSessions Table (New)
Fields:
- `PartitionKey` (string) - Session ID
- `RowKey` (string) - User ID
- `Method` (string) - "email", "totp", or "both"
- `AvailableMethods` (string) - JSON array of available methods
- `EmailCodeHash` (string) - SHA-256 hash of email code
- `AttemptsRemaining` (int) - Verification attempts left
- `CreatedAt` (datetime) - Session creation time
- `ExpiresAt` (datetime) - Session expiration (10 minutes)
- `LastResendAt` (datetime) - Last resend timestamp

### Environment Variables

#### Required for TOTP 2FA
- `ENCRYPTION_KEY` - AES-256 encryption key (minimum 32 characters)

#### Required for Email 2FA
- `SMTP_SERVER` - SMTP server hostname
- `SMTP_PORT` - SMTP port (usually 587)
- `SMTP_USERNAME` - SMTP authentication username
- `SMTP_PASSWORD` - SMTP authentication password
- `SMTP_FROM` - Sender email address

#### Example Configuration
See `local.settings.json.example` for a complete example.

### Security Features

1. **Cryptographic Security**
   - Uses `RandomNumberGenerator` for secure random generation
   - Proper resource disposal for all crypto objects
   - Email codes hashed before storage (SHA-256)
   - TOTP secrets encrypted at rest (AES-256)
   - Backup codes hashed before storage (SHA-256)

2. **Session Management**
   - 10-minute session expiration
   - Sessions invalidated after successful verification
   - Session cleanup on verification failure

3. **Rate Limiting**
   - Maximum 5 verification attempts per session
   - 60-second cooldown between email resend requests
   - Existing IP-based rate limits still apply

4. **Security Event Logging**
   - All 2FA events logged to SecurityEvents table
   - Events: 2FAVerifySuccess, 2FAVerifyFailed, 2FACodeResent, LoginRequires2FA
   - No sensitive data (codes, secrets) logged

5. **Backup Code Security**
   - Single-use codes automatically removed after validation
   - Hashed using SHA-256 (same as email codes)
   - Can be used when primary 2FA method is unavailable
   - 8-character alphanumeric codes (excluding ambiguous characters)

6. **TOTP QR Code Generation**
   - Helper function to generate otpauth:// URI
   - Compatible with RFC 6238 standard
   - Frontend can use this URI to generate QR code images
   - Supports issuer and account name customization

7. **Complete Setup Flow** ✅ NEW
   - Setup endpoint generates TOTP secret, QR code, and backup codes
   - Enable endpoint verifies and activates 2FA
   - Disable endpoint turns off 2FA
   - All integrated into single endpoint with action parameter


### Implementation Status

All core features are now implemented:

✅ **POST /api/public/2fatoken?action=setup** - Generate TOTP secret, QR code, and backup codes
✅ **POST /api/public/2fatoken?action=enable** - Verify and enable 2FA (email, TOTP, or both)
✅ **POST /api/public/2fatoken?action=disable** - Disable 2FA for user
✅ **POST /api/public/2fatoken?action=verify** - Verify 2FA code during login
✅ **POST /api/public/2fatoken?action=resend** - Resend email 2FA code

All endpoints use the same `/api/public/2fatoken` path with different `action` query parameters.

## Testing Recommendations

### Manual Testing

1. **Email 2FA Flow**
   - Create user with email 2FA enabled
   - Attempt login
   - Verify session ID returned
   - Submit correct code
   - Verify authentication succeeds

2. **TOTP 2FA Flow**
   - Create user with TOTP enabled and secret
   - Attempt login
   - Generate TOTP code using authenticator app
   - Submit code
   - Verify authentication succeeds

3. **Dual 2FA Flow**
   - Create user with both methods enabled
   - Test verification with email code
   - Test verification with TOTP code
   - Verify either works independently

4. **Rate Limiting**
   - Test 5 failed attempts (should block)
   - Test resend cooldown (should enforce 60s)

5. **Session Expiration**
   - Wait 10+ minutes after login
   - Attempt verification
   - Verify session expired error

6. **Backup Codes**
   - Test backup code generation
   - Test backup code verification
   - Verify single-use (code removed after use)
   - Test backup code with both email and TOTP enabled

### Security Testing

1. **Code Reuse**
   - Verify codes cannot be reused after successful verification
   - Verify session is deleted after use
   - Verify backup codes are single-use

2. **Timing Attacks**
   - TOTP accepts ±1 time window (90 seconds total)
   - Verify codes outside window are rejected

3. **Brute Force Protection**
   - Verify 5-attempt limit is enforced
   - Verify session is deleted after max attempts

4. **Encryption**
   - Verify TOTP secrets are encrypted at rest
   - Test encryption/decryption with various keys
   - Verify secrets cannot be read without decryption

## Known Limitations

1. **SMTP Configuration Required**
   - Email 2FA requires SMTP server configuration
   - No email will be sent if SMTP is not configured
   - Users should be warned during 2FA setup

2. **Encryption Key Management**
   - Encryption key stored in environment variable (not Azure Key Vault)
   - Key rotation not implemented
   - Consider moving to Key Vault for production

3. **No QR Code Generation**
   - TOTP setup endpoint not implemented
   - Users must manually enter secret in authenticator app
   - Should be added in future enhancement

## Production Deployment Checklist

- [ ] Generate strong ENCRYPTION_KEY (32+ characters)
- [ ] Configure ENCRYPTION_KEY in Azure App Settings
- [ ] Configure SMTP credentials in Azure App Settings
- [ ] Test email delivery in production environment
- [ ] Ensure TwoFactorSessions table is created
- [ ] Monitor SecurityEvents for 2FA-related events
- [ ] Set up alerts for failed 2FA attempts
- [ ] Document 2FA setup process for users
- [ ] Test backup code generation and usage
- [ ] Consider implementing QR code generation
- [ ] Consider migrating ENCRYPTION_KEY to Azure Key Vault

## Questions for Product Owner

1. ~~Should we implement backup codes before production?~~ **Implemented**
2. What should the account recovery process be if a user loses all backup codes?
3. ~~Should 2FA be optional or mandatory for all users?~~ **Optional (already implemented)**
4. Should admins be able to disable 2FA for users who are locked out?
5. Do we need to support SMS-based 2FA in the future?
6. Should we implement key rotation for ENCRYPTION_KEY?

## Additional Notes

- The implementation follows the RFC 6238 standard for TOTP
- TOTP secrets are encrypted at rest using AES-256 (key stored in environment)
- Email codes are hashed before storage using SHA-256 (secure)
- Backup codes are hashed before storage using SHA-256 (secure)
- All cryptographic objects properly disposed to prevent memory leaks
- Implementation is compatible with standard authenticator apps
- Backup codes provide recovery mechanism if primary 2FA method is lost
