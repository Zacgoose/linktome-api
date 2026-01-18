# Site Admin API

Site administrator API endpoints for managing timer functions and system operations.

## Authentication

All site admin endpoints require:
1. **Valid JWT authentication** - User must be logged in
2. **Site admin privileges** - User's email must be in the `SITE_ADMIN_EMAILS` environment variable

### Environment Variable Setup

Set the `SITE_ADMIN_EMAILS` environment variable with comma-separated admin emails:

```
SITE_ADMIN_EMAILS=admin@example.com,superadmin@example.com
```

## Endpoints

### List Timers

Get a list of all configured timer functions with their current status.

**Endpoint:** `GET /siteadmin/timers`

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
      "manuallyTriggeredAt": null
    }
  ],
  "count": 13
}
```

### Run Timer Manually

Manually trigger a timer function to run immediately, bypassing the cron schedule.

**Endpoint:** `POST /siteadmin/runtimer`

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
  "executedBy": "admin@example.com"
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

**Error Response - Unauthorized (403):**
```json
{
  "error": "Forbidden",
  "message": "This endpoint requires site administrator privileges"
}
```

## Features

### Manual Timer Execution
- Run any timer function immediately without waiting for the cron schedule
- Prevents duplicate execution if an orchestrator is already running
- Tracks who triggered the timer and when (audit trail)
- Updates timer status with execution results

### Status Tracking
- View all timers with their current status (Completed, Failed, Running, etc.)
- See last and next occurrence times
- View error messages for failed timers
- Track manual vs. automatic executions

### Security
- Requires site administrator privileges (email whitelist)
- All access attempts logged with user information
- Unauthorized access attempts trigger security warnings

## Use Cases

1. **Test Timer Functions** - Trigger timers manually during development/testing
2. **Force Aggregation** - Run analytics aggregation immediately after data changes
3. **Maintenance Tasks** - Run cleanup timers on-demand
4. **Troubleshooting** - Re-run failed timers immediately
5. **Emergency Operations** - Trigger system tasks outside normal schedule

## Implementation Notes

- Inspired by CIPP-API's scheduler functionality
- Uses same timer infrastructure as automatic cron scheduling
- Integrates with existing LinkTomeTimers.json configuration
- Maintains all timer status tracking and orchestrator management
- Safe to use - includes duplicate run prevention
