# API Specification: Tier Restriction Flags

This document describes the tier restriction flags returned by admin endpoints when features exceed the user's subscription tier limits.

## Overview

When a user's subscription is downgraded or expires, features that exceed the new tier's limits are **flagged but preserved**. Admin endpoints return these flags so the frontend can:
- Display upgrade prompts
- Show which features are restricted
- Highlight features that need attention
- Provide clear user feedback

**All flags are optional fields** - they are only included when the restriction applies.

---

## Admin Endpoints

### 1. GET /admin/getPages

**Description:** Returns all pages for the authenticated user with tier restriction flags.

**Endpoint:** `GET /admin/getPages`

**Authentication:** Required (Bearer token or API key)

**Query Parameters:** None

**Response:**
```json
{
  "pages": [
    {
      "id": "page-uuid",
      "userId": "user-uuid",
      "slug": "my-page",
      "name": "My Page",
      "isDefault": true,
      "createdAt": "2024-01-15T10:30:00Z",
      "updatedAt": "2024-01-20T14:22:00Z",
      "exceedsTierLimit": false  // ⚠️ OPTIONAL: Only present when page exceeds tier limit
    },
    {
      "id": "page-uuid-2",
      "userId": "user-uuid",
      "slug": "second-page",
      "name": "Second Page",
      "isDefault": false,
      "createdAt": "2024-01-16T11:00:00Z",
      "updatedAt": "2024-01-20T15:00:00Z",
      "exceedsTierLimit": true   // ⚠️ This page exceeds tier limit (user downgraded)
    }
  ]
}
```

**Tier Restriction Flag:**
- `exceedsTierLimit` (boolean, optional)
  - `true` = This page exceeds the user's current tier limit
  - `false` or absent = Page is within tier limits
  - When `true`, frontend should:
    - Show warning icon/badge on the page
    - Display "Upgrade to access this page" message
    - Disable editing or viewing in public profile
    - Show upgrade CTA

**Tier Limits:**
- Free: 1 page
- Pro: 3 pages
- Premium: 10 pages
- Enterprise: Unlimited

---

### 2. GET /admin/getAppearance

**Description:** Returns appearance settings for a page with tier restriction flags.

**Endpoint:** `GET /admin/getAppearance?pageId={pageId}`

**Authentication:** Required

**Query Parameters:**
- `pageId` (optional) - If omitted, returns appearance for default page

**Response:**
```json
{
  "pageId": "page-uuid",
  "theme": "agate",
  "customTheme": true,
  "header": {
    "profileImageLayout": "classic",
    "titleStyle": "text",
    "displayName": "@username",
    "bio": "My bio",
    "logoUrl": "https://..."
  },
  "profileImageUrl": "https://...",
  "socialIcons": [...],
  "wallpaper": {
    "type": "video",
    "color": "#ffffff",
    "videoUrl": "https://...",
    "blur": 0,
    "opacity": 1.0
  },
  "buttons": {...},
  "text": {...},
  "hideFooter": true,
  "exceedsTierLimit": true,        // ⚠️ OPTIONAL: Custom theme exceeds tier
  "videoExceedsTierLimit": true    // ⚠️ OPTIONAL: Video background exceeds tier
}
```

**Tier Restriction Flags:**
- `exceedsTierLimit` (boolean, optional)
  - `true` = Custom theme or premium theme exceeds tier
  - When `true`, frontend should:
    - Show "Custom themes require Pro tier" message
    - Disable theme customization
    - Show upgrade CTA

- `videoExceedsTierLimit` (boolean, optional)
  - `true` = Video background exceeds tier
  - When `true`, frontend should:
    - Show "Video backgrounds require Premium tier" message
    - Disable video upload/selection
    - Show upgrade CTA

**Tier Limits:**
- Custom themes: Pro+ (Free tier gets default only)
- Video backgrounds: Premium+ (Free/Pro not allowed)
- Premium themes (agate, astrid, aura, bloom, breeze): Pro+

---

### 3. GET /admin/getLinks

**Description:** Returns links for a page with individual feature tier restriction flags.

**Endpoint:** `GET /admin/getLinks?pageId={pageId}`

**Authentication:** Required

**Query Parameters:**
- `pageId` (optional) - If omitted, returns links for default page

**Response:**
```json
{
  "links": [
    {
      "id": "link-uuid",
      "title": "My Website",
      "url": "https://example.com",
      "order": 0,
      "active": true,
      "icon": "🌐",
      "thumbnail": "https://...",
      "thumbnailType": "image",
      "layout": "featured",
      "animation": "pulse",
      "groupId": "group-uuid",
      "clicks": 150,
      "schedule": {
        "enabled": true,
        "startDate": "2024-01-01T00:00:00Z",
        "endDate": "2024-12-31T23:59:59Z",
        "timezone": "America/New_York"
      },
      "lock": {
        "enabled": true,
        "type": "code",
        "code": "1234",
        "message": "Enter code to access"
      },
      "layoutExceedsTier": false,      // ⚠️ OPTIONAL: Custom layout restriction
      "animationExceedsTier": false,   // ⚠️ OPTIONAL: Animation restriction
      "scheduleExceedsTier": true,     // ⚠️ OPTIONAL: Scheduling restriction
      "lockExceedsTier": false         // ⚠️ OPTIONAL: Lock restriction
    }
  ],
  "groups": [...]
}
```

**Tier Restriction Flags (per link):**

- `layoutExceedsTier` (boolean, optional)
  - `true` = Custom layout (featured, thumbnail-left, thumbnail-right) exceeds tier
  - When `true`, frontend should:
    - Show "Custom layouts require Pro tier" on this link
    - Disable layout selection dropdown
    - Show upgrade prompt

- `animationExceedsTier` (boolean, optional)
  - `true` = Link animation (shake, pulse, bounce, glow) exceeds tier
  - When `true`, frontend should:
    - Show "Animations require Pro tier" on this link
    - Disable animation selection
    - Show upgrade prompt

- `scheduleExceedsTier` (boolean, optional)
  - `true` = Link scheduling exceeds tier
  - When `true`, frontend should:
    - Show "Scheduling requires Pro tier" on this link
    - Disable schedule controls
    - Show upgrade prompt

- `lockExceedsTier` (boolean, optional)
  - `true` = Link locking (code, age verification) exceeds tier
  - When `true`, frontend should:
    - Show "Link locking requires Pro tier" on this link
    - Disable lock controls
    - Show upgrade prompt

**Tier Limits:**
- Custom layouts: Pro+ (Free tier gets 'classic' only)
- Link animations: Pro+ (Free tier gets 'none' only)
- Link scheduling: Pro+
- Link locking: Pro+

**Important Notes:**
- Multiple flags can be `true` on a single link
- The link data is preserved - only the feature is restricted
- When user upgrades, flags are automatically removed
- Public API will strip these features if flags are present

---

### 4. GET /admin/getShortLinks

**Description:** Returns short links with tier restriction flags.

**Endpoint:** `GET /admin/getShortLinks`

**Authentication:** Required

**Query Parameters:** None

**Response:**
```json
{
  "shortLinks": [
    {
      "slug": "my-link",
      "targetUrl": "https://example.com/very/long/url",
      "title": "My Short Link",
      "active": true,
      "clicks": 523,
      "createdAt": "2024-01-10T10:00:00.000Z",
      "lastClickedAt": "2024-01-20T15:30:00.000Z",
      "exceedsTierLimit": false  // ⚠️ OPTIONAL: Only present when exceeds limit
    },
    {
      "slug": "extra-link",
      "targetUrl": "https://example.com/another/url",
      "title": "Extra Link",
      "active": true,
      "clicks": 42,
      "createdAt": "2024-01-15T12:00:00.000Z",
      "lastClickedAt": "2024-01-19T09:15:00.000Z",
      "exceedsTierLimit": true   // ⚠️ This short link exceeds tier limit
    }
  ],
  "total": 2
}
```

**Tier Restriction Flag:**
- `exceedsTierLimit` (boolean, optional)
  - `true` = This short link exceeds the user's current tier limit
  - When `true`, frontend should:
    - Show warning icon/badge on the short link
    - Display "Upgrade to keep this short link active" message
    - Mark as "Will be disabled" in the list
    - Show upgrade CTA

**Tier Limits:**
- Free: 0 short links (feature not available)
- Pro: 5 short links
- Premium: 20 short links
- Enterprise: Unlimited

---

## Public API Behavior

### GET /public/getUserProfile

**Description:** Public profile endpoint with automatic tier enforcement.

**Endpoint:** `GET /public/getUserProfile?username={username}&slug={slug}`

**Authentication:** None (public)

**Tier Enforcement (Backend):**

1. **Pages:**
   - Returns 403 Forbidden if accessing page with `ExceedsTierLimit = true`

2. **Themes:**
   - Returns `theme: 'default'` if custom theme has `ExceedsTierLimit = true`

3. **Video backgrounds:**
   - Omits `videoUrl` if has `VideoExceedsTierLimit = true`
   - Changes `wallpaper.type` from 'video' to 'fill'

4. **Links:**
   - For links with `LayoutExceedsTier = true`: Returns `layout: 'classic'`
   - For links with `AnimationExceedsTier = true`: Returns `animation: 'none'`
   - For links with `ScheduleExceedsTier = true`: Ignores schedule (link always visible)
   - For links with `LockExceedsTier = true`: Omits lock info (link behaves as unlocked)

5. **Short links:**
   - Returns 403 Forbidden if accessing short link with `ExceedsTierLimit = true`

**Note:** Public API automatically enforces restrictions - no flags are exposed publicly.

---

## Frontend Implementation Guide

### Recommended UI Patterns

#### 1. Warning Badges
When `exceedsTierLimit` or any feature flag is `true`:
```
┌─────────────────────────────┐
│ 📄 My Second Page      ⚠️   │
│ Requires Pro Tier           │
└─────────────────────────────┘
```

#### 2. Feature-Specific Warnings
For link features:
```
┌─────────────────────────────┐
│ 🔗 My Link                  │
│ ├─ Layout: Featured    ⚠️   │
│ ├─ Animation: Pulse    ⚠️   │
│ ├─ Schedule: Enabled   ✅   │
│ └─ Lock: Code          ⚠️   │
└─────────────────────────────┘
```

#### 3. Upgrade Prompts
```
╔═════════════════════════════════╗
║  ⚠️ Premium Features Detected   ║
║                                 ║
║  • 2 pages exceed tier limit    ║
║  • Custom theme unavailable     ║
║  • 3 links with premium features║
║                                 ║
║  [Upgrade to Pro →]             ║
╚═════════════════════════════════╝
```

#### 4. Inline Warnings
When editing restricted features:
```
Layout: [Dropdown ▼]
⚠️ Custom layouts require Pro tier
[Upgrade to unlock →]
```

### Frontend Logic Example

```javascript
// Check if page exceeds tier
if (page.exceedsTierLimit) {
  showWarningBadge(page);
  disablePageAccess(page);
  showUpgradePrompt();
}

// Check link features
if (link.layoutExceedsTier) {
  disableLayoutSelector();
  showInlineWarning('Custom layouts require Pro tier');
}

if (link.animationExceedsTier) {
  disableAnimationSelector();
  showInlineWarning('Animations require Pro tier');
}

// Count total restrictions
const totalRestrictions = 
  pages.filter(p => p.exceedsTierLimit).length +
  links.filter(l => l.layoutExceedsTier || l.animationExceedsTier || 
                     l.scheduleExceedsTier || l.lockExceedsTier).length;

if (totalRestrictions > 0) {
  showGlobalUpgradePrompt(totalRestrictions);
}
```

---

## Data Preservation & Restoration

### Key Principles

1. **All data is preserved** - Nothing is deleted on downgrade
2. **Flags control access** - Restrictions are enforced via flags
3. **Instant restoration** - Flags removed automatically on upgrade
4. **No re-creation needed** - Original settings restored immediately

### Restoration Flow

```
User downgrades: Pro → Free
├─ Invoke-FeatureCleanup runs
├─ Flags set: ExceedsTierLimit = true on pages 2-3
├─ User data preserved in database
└─ Public API enforces restrictions

User upgrades: Free → Pro
├─ Invoke-FeatureCleanup runs with new tier
├─ Flags cleared: ExceedsTierLimit = false
├─ Features immediately accessible
└─ No data loss, no re-configuration needed
```

---

## HTTP Status Codes

- **200 OK** - Success, flags included in response
- **403 Forbidden** - Public API access denied (page/short link exceeds tier)
- **404 Not Found** - Resource doesn't exist
- **500 Internal Server Error** - Server error

---

## Version History

- **v1.0** (2024-01-22) - Initial tier flag implementation
  - Added page, appearance, link, and short link flags
  - Individual link feature flags (layout, animation, schedule, lock)
  - Backend enforcement in public APIs
  - Admin API transparency

---

## Questions?

Contact the backend team for:
- Additional flag types
- Custom enforcement logic
- Tier limit adjustments
- Integration support
