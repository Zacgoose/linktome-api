# Site Admin API

Site administrator API endpoints for managing timer functions and system operations.

## Authentication & Authorization

All site admin endpoints require:
1. **Valid JWT authentication** - User must be logged in
2. **Site super admin role** - User must have the `site_super_admin` role
3. **Appropriate permissions**:
   - `read:siteadmin` - Required for viewing timer status
   - `write:siteadmin` - Required for manually triggering timers

### Role Setup

Users with the `site_super_admin` role automatically receive these permissions:
- All standard user permissions (pages, links, analytics, etc.)
- `read:siteadmin` - View system timer status and configuration
- `write:siteadmin` - Manually trigger timer functions

To grant a user site super admin access:
1. Update the user's role in the Users table
2. Set `Role` or `Roles` field to `site_super_admin`
3. The user will gain all site admin permissions on next authentication

## Endpoints

### List Timers

Get a list of all configured timer functions with their current status.

**Endpoint:** `GET /siteadmin/timers`

**Required Permission:** `read:siteadmin`

**Response:**
```json
{
  "success": true,
  "timers": [
    {
      "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
      "command": "Start-AnalyticsAggregation",
      "description": "Timer to aggregate and summarize analytics data",
      "cron": "0 0 3 * * *",
      "priority": 2,
      "runOnProcessor": true,
      "isSystem": true,
      "status": "Completed",
      "lastOccurrence": "2026-01-18T03:00:00.000Z",
      "nextOccurrence": "2026-01-19T03:00:00.000Z",
      "orchestratorId": null,
      "errorMsg": null,
      "manuallyTriggered": false,
      "manuallyTriggeredBy": null,
      "manuallyTriggeredByRole": null,
      "manuallyTriggeredAt": null
    }
  ],
  "count": 13
}
```

### Run Timer Manually

Manually trigger a timer function to run immediately, bypassing the cron schedule.

**Endpoint:** `POST /siteadmin/runtimer`

**Required Permission:** `write:siteadmin`

**Request Body:**
```json
{
  "timerId": "c3d4e5f6-a7b8-9012-cdef-123456789012"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "message": "Timer Start-AnalyticsAggregation executed successfully",
  "timerId": "c3d4e5f6-a7b8-9012-cdef-123456789012",
  "command": "Start-AnalyticsAggregation",
  "status": "Completed",
  "orchestratorId": null,
  "executedAt": "2026-01-18T13:45:00.000Z",
  "executedBy": "admin@example.com",
  "executedByRole": "site_super_admin"
}
```

**Error Response - Already Running (409):**
```json
{
  "error": "Timer already running",
  "message": "Timer Start-AnalyticsAggregation has an orchestrator still running: abc123...",
  "orchestratorId": "abc123-def456-...",
  "status": "Running"
}
```

**Error Response - Not Found (404):**
```json
{
  "error": "Timer not found",
  "message": "No timer found with ID: invalid-id"
}
```

**Error Response - Forbidden (403):**
```json
{
  "error": "Forbidden",
  "message": "This endpoint requires write:siteadmin permission (site_super_admin role)",
  "requiredPermission": "write:siteadmin",
  "requiredRole": "site_super_admin"
}
```

## Features

### Role-Based Access Control
- Uses existing permission system with `site_super_admin` role
- Granular permissions: `read:siteadmin` and `write:siteadmin`
- Integrates with user authentication context
- Prevents privilege escalation

### Manual Timer Execution
- Run any timer function immediately without waiting for the cron schedule
- Prevents duplicate execution if an orchestrator is already running
- Tracks who triggered the timer, their role, and when (audit trail)
- Updates timer status with execution results

### Status Tracking
- View all timers with their current status (Completed, Failed, Running, etc.)
- See last and next occurrence times
- View error messages for failed timers
- Track manual vs. automatic executions
- Audit trail includes user role information

### Security
- Requires site super admin role (`site_super_admin`)
- Permission-based authorization (`read:siteadmin`, `write:siteadmin`)
- All access attempts logged with user and role information
- Unauthorized access attempts trigger security warnings
- Integrates with existing JWT authentication

## Use Cases

1. **Test Timer Functions** - Trigger timers manually during development/testing
2. **Force Aggregation** - Run analytics aggregation immediately after data changes
3. **Maintenance Tasks** - Run cleanup timers on-demand
4. **Troubleshooting** - Re-run failed timers immediately
5. **Emergency Operations** - Trigger system tasks outside normal schedule
6. **System Monitoring** - View real-time timer status and health

## Implementation Notes

- Built on existing role/permission infrastructure
- Uses same timer infrastructure as automatic cron scheduling
- Integrates with existing LinkTomeTimers.json configuration
- Maintains all timer status tracking and orchestrator management
- Safe to use - includes duplicate run prevention
- Full audit trail with user and role tracking
- No environment variables needed - uses database roles
