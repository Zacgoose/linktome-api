# LinkTome Timer and Orchestrator Infrastructure

## Overview

This document describes the timer and orchestrator infrastructure for the LinkTome API, which enables scheduled tasks, background processing, and orchestrated workflows using Azure Durable Functions.

## Architecture

The timer infrastructure is based on the CIPP-API pattern and consists of:

1. **LinkTomeTimers.json** - Configuration file defining all scheduled timer tasks
2. **LinkTomeTimer/** - Azure Function with timer trigger (runs every 15 minutes)
3. **LinkTomeOrchestrator/** - Azure Function for durable orchestrations
4. **LinkTomeActivity/** - Azure Function for activity tasks within orchestrations
5. **Timer Command Functions** - PowerShell functions implementing timer logic

## Components

### 1. LinkTomeTimers.json

Configuration file at the root of the repository that defines scheduled timer tasks:

```json
{
  "Id": "unique-guid",
  "Command": "Start-FunctionName",
  "Description": "Human-readable description",
  "Cron": "0 */15 * * * *",
  "Priority": 0,
  "RunOnProcessor": true,
  "IsSystem": true,
  "Parameters": {}
}
```

**Properties:**
- `Id` - Unique identifier (GUID)
- `Command` - PowerShell function name to execute
- `Description` - Human-readable description of the timer
- `Cron` - Cron expression for scheduling
- `Priority` - Execution priority (0 = highest)
- `RunOnProcessor` - Whether to run on processor instances
- `IsSystem` - Whether this is a system timer
- `Parameters` - Optional parameters to pass to the function

### 2. Timer Trigger Function

**Location:** `LinkTomeTimer/function.json`

Runs every 15 minutes and processes all configured timers from LinkTomeTimers.json.

**Bindings:**
- Timer trigger: `0 0/15 * * * *` (every 15 minutes)
- Durable client: For starting orchestrations

**Entry Point:** `Receive-LinkTomeTimerTrigger` in LinkTomeEntrypoints.psm1

### 3. Orchestrator Function

**Location:** `LinkTomeOrchestrator/function.json`

Handles durable orchestrations for complex, multi-step workflows.

**Bindings:**
- Orchestration trigger

**Entry Point:** `Receive-LinkTomeOrchestrationTrigger` in LinkTomeEntrypoints.psm1

**Durable Modes:**
- `FanOut` - Parallel execution (default)
- `Sequence` - Sequential execution
- `NoScaling` - No scaling, simple execution

### 4. Activity Function

**Location:** `LinkTomeActivity/function.json`

Executes individual activity tasks within orchestrations.

**Bindings:**
- Activity trigger

**Entry Point:** `Receive-LinkTomeActivityTrigger` in LinkTomeEntrypoints.psm1

## Configured Timer Tasks

The following timer tasks are configured in LinkTomeTimers.json:

### System Timers

1. **Start-DurableCleanup** (Priority 0)
   - Runs every 15 minutes
   - Cleans up durable function instances and orchestrations
   - System timer

2. **Start-SecurityEventCleanup** (Priority 4)
   - Runs daily at 1 AM
   - Removes old security events based on retention policy
   - System timer

3. **Start-RateLimitCleanup** (Priority 5)
   - Runs every 30 minutes
   - Removes expired rate limit tracking entries
   - System timer

4. **Start-TwoFactorSessionCleanup** (Priority 6)
   - Runs every 15 minutes
   - Removes expired 2FA sessions
   - System timer

5. **Start-FeatureUsageCleanup** (Priority 10)
   - Runs daily at 11 PM
   - Removes old feature usage tracking data
   - System timer

6. **Start-HealthCheckOrchestrator** (Priority 9)
   - Runs hourly
   - Performs comprehensive system health checks
   - System timer

### Business Logic Timers

7. **Start-SubscriptionCleanup** (Priority 1)
   - Runs daily at 2 AM
   - Processes expired subscriptions and downgrades accounts

8. **Start-AnalyticsAggregation** (Priority 2)
   - Runs daily at 3 AM
   - Aggregates and summarizes analytics data

9. **Start-BillingOrchestrator** (Priority 3)
   - Runs daily at midnight
   - Processes billing and subscription renewals

10. **Start-ScheduledTaskOrchestrator** (Priority 7)
    - Runs every 15 minutes
    - Processes user-defined scheduled tasks

11. **Start-BackupOrchestrator** (Priority 8)
    - Runs daily at 4 AM
    - Backs up critical system data

12. **Start-InactiveAccountCleanup** (Priority 11)
    - Runs weekly on Sunday at 5 AM
    - Identifies and processes inactive accounts

## File Structure

```
linktome-api/
├── LinkTomeTimers.json              # Timer configuration
├── LinkTomeTimer/
│   └── function.json                # Timer trigger function
├── LinkTomeOrchestrator/
│   └── function.json                # Orchestrator function
├── LinkTomeActivity/
│   └── function.json                # Activity function
└── Modules/
    ├── LinkTomeEntrypoints/
    │   └── LinkTomeEntrypoints.psm1 # Entry point functions
    └── LinkTomeCore/
        ├── Private/
        │   └── Timer/
        │       └── Get-LinkTomeTimerFunctions.ps1  # Timer loader
        └── Public/
            └── Timers/
                ├── Start-DurableCleanup.ps1
                ├── Start-SubscriptionCleanup.ps1
                ├── Start-AnalyticsAggregation.ps1
                ├── Start-BillingOrchestrator.ps1
                ├── Start-SecurityEventCleanup.ps1
                ├── Start-RateLimitCleanup.ps1
                ├── Start-TwoFactorSessionCleanup.ps1
                ├── Start-ScheduledTaskOrchestrator.ps1
                ├── Start-BackupOrchestrator.ps1
                ├── Start-HealthCheckOrchestrator.ps1
                ├── Start-FeatureUsageCleanup.ps1
                └── Start-InactiveAccountCleanup.ps1
```

## Adding a New Timer

To add a new timer task:

1. **Add configuration to LinkTomeTimers.json:**
   ```json
   {
     "Id": "new-unique-guid",
     "Command": "Start-MyNewTimer",
     "Description": "Description of what the timer does",
     "Cron": "0 0 * * * *",
     "Priority": 15,
     "RunOnProcessor": true,
     "IsSystem": false
   }
   ```

2. **Create the timer function in Modules/LinkTomeCore/Public/Timers:**
   ```powershell
   function Start-MyNewTimer {
       [CmdletBinding()]
       param()
       
       try {
           Write-Information "Starting my new timer"
           # Implementation here
           Write-Information "My new timer completed"
           return @{
               Status = "Success"
               Message = "Timer completed"
           }
       } catch {
           Write-Warning "My new timer failed: $($_.Exception.Message)"
           throw
       }
   }
   ```

3. **Test the timer:**
   - The function will be automatically loaded by the LinkTomeCore module
   - The timer trigger will pick it up from LinkTomeTimers.json

## Testing

Run the integration test to verify the timer infrastructure:

```powershell
# From the repository root
pwsh -File tests/Test-TimerInfrastructure.ps1
```

Or test individual components:

```powershell
# Load modules
Import-Module ./Modules/LinkTomeCore/LinkTomeCore.psm1
Import-Module ./Modules/LinkTomeEntrypoints/LinkTomeEntrypoints.psm1

# Test timer loader
$Timers = Get-LinkTomeTimerFunctions
$Timers | Format-Table Command, Priority, Cron

# Test a timer function
Start-DurableCleanup
```

### Automatic Initialization

The timer infrastructure automatically creates status tracking entities on first run. You do not need to manually create the LinkTomeTimers table or populate it with entities - the timer trigger will:

1. Create status entities for any timer that doesn't have one yet
2. Gracefully handle empty tables or missing entities
3. Continue execution even if status tracking fails

This ensures the timer system works "out of the box" without manual setup.

## Implementation Status

All timer functions are currently **stubs** with TODO comments indicating the logic that needs to be implemented. Each function returns a success status but does not perform actual work yet.

To implement a timer:
1. Open the corresponding .ps1 file in `Modules/LinkTomeCore/Public/Timers/`
2. Replace the TODO comments with actual implementation
3. Use LinkTomeCore functions for database access (Get-LinkToMeTable, Get-LinkToMeAzDataTableEntity, etc.)
4. Test the function thoroughly before deploying

## Next Steps

1. Implement the actual logic for each timer function based on business requirements
2. Add proper error handling and retry logic (error handling infrastructure already in place)
3. Deploy to Azure Functions and verify timer triggers work correctly
4. Add monitoring and alerting for failed timer executions

**Note**: The LinkTomeTimers table is automatically created and populated on first run - no manual initialization required!

## References

- Based on [CIPP-API timer infrastructure](https://github.com/Zacgoose/CIPP-API)
- [Azure Durable Functions documentation](https://learn.microsoft.com/azure/azure-functions/durable/)
- [Azure Functions timer trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-timer)
