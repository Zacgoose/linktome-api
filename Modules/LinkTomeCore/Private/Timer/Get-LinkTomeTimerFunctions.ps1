function Get-LinkTomeTimerFunctions {
    <#
    .SYNOPSIS
        Get timer functions from LinkTomeTimers.json configuration
    .DESCRIPTION
        Reads and parses the LinkTomeTimers.json file to return scheduled timer functions.
        Uses NCrontab library for accurate schedule calculation with window-based evaluation.
        Mimics CIPP-API's Get-CIPPTimerFunctions implementation.
    .PARAMETER ListAllTasks
        If specified, returns all tasks regardless of schedule
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [switch]$ListAllTasks
    )

    try {
        # Load NCrontab.Advanced library if not already loaded
        if (!('NCronTab.Advanced.CrontabSchedule' -as [type])) {
            try {
                $LinkTomeCoreModuleRoot = Get-Module -Name LinkTomeCore | Select-Object -ExpandProperty ModuleBase
                $NCronTab = Join-Path -Path $LinkTomeCoreModuleRoot -ChildPath 'lib\NCrontab.Advanced.dll'
                if (Test-Path $NCronTab) {
                    Add-Type -Path $NCronTab
                    Write-Information "Loaded NCrontab.Advanced library from: $NCronTab"
                } else {
                    Write-Warning "NCrontab.Advanced.dll not found at: $NCronTab. Timer scheduling may not work correctly."
                    Write-Warning "Please ensure NCrontab.Advanced.dll is placed in Modules/LinkTomeCore/lib/"
                }
            } catch {
                Write-Warning "Failed to load NCrontab.Advanced library: $($_.Exception.Message)"
            }
        }

        # Navigate from Modules/LinkTomeCore/Private/Timer to root
        $TimersJsonPath = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName 'LinkTomeTimers.json'
        
        if (-not (Test-Path $TimersJsonPath)) {
            Write-Warning "LinkTomeTimers.json not found at: $TimersJsonPath"
            return @()
        }

        $Timers = Get-Content -Path $TimersJsonPath -Raw | ConvertFrom-Json
        
        # Get status table
        $Table = Get-LinkToMeTable -TableName 'LinkTomeTimers'
        $TimerStatus = Get-LinkToMeAzDataTableEntity @Table
        
        # Clean up stale status entries with invalid GUIDs
        $TimerStatus | Where-Object { $_.RowKey -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' } | Select-Object ETag, PartitionKey, RowKey | ForEach-Object {
            Remove-LinkToMeAzDataTableEntity @Table -Entity $_ -Force
        }
        
        $Results = foreach ($Timer in $Timers) {
            # Validate required properties
            if (-not $Timer.Id -or -not $Timer.Command -or -not $Timer.Cron) {
                Write-Warning "Timer missing required properties (Id, Command, or Cron): $($Timer | ConvertTo-Json -Compress)"
                continue
            }
            
            # Verify command exists
            if (!(Get-Command -Name $Timer.Command -Module LinkTomeCore -ErrorAction SilentlyContinue)) {
                Write-Warning "Timer command does not exist: $($Timer.Command)"
                $Status = $TimerStatus | Where-Object { $_.RowKey -eq $Timer.Id }
                if ($Status) {
                    Remove-LinkToMeAzDataTableEntity @Table -Entity $Status
                }
                continue
            }
            
            $Status = $TimerStatus | Where-Object { $_.RowKey -eq $Timer.Id }
            $CronString = $Timer.Cron
            
            # Parse cron expression
            $CronCount = ($CronString -split ' ' | Measure-Object).Count
            try {
                if ($CronCount -eq 5) {
                    $Cron = [Ncrontab.Advanced.CrontabSchedule]::Parse($CronString)
                } elseif ($CronCount -eq 6) {
                    $Cron = [Ncrontab.Advanced.CrontabSchedule]::Parse($CronString, [Ncrontab.Advanced.Enumerations.CronStringFormat]::WithSeconds)
                } else {
                    Write-Warning "Invalid cron expression for $($Timer.Command): $CronString (expected 5 or 6 fields)"
                    continue
                }
            } catch {
                Write-Warning "Failed to parse cron expression for $($Timer.Command): $CronString - $($_.Exception.Message)"
                continue
            }
            
            $Now = Get-Date
            
            if ($ListAllTasks.IsPresent) {
                # Just get next occurrence for listing
                $NextOccurrence = [datetime]$Cron.GetNextOccurrence($Now)
            } else {
                # Get occurrences in a 30-minute window (-15 to +15 minutes)
                $NextOccurrences = $Cron.GetNextOccurrences($Now.AddMinutes(-15), $Now.AddMinutes(15))
                
                if (!$Status -or $Status.LastOccurrence -eq 'Never' -or !$Status.LastOccurrence) {
                    # First run - find first occurrence before or at current time
                    $NextOccurrence = $NextOccurrences | Where-Object { $_ -le (Get-Date) } | Select-Object -First 1
                } else {
                    # Find next occurrence after last run but before/at current time
                    $LastOccurrenceDateTime = if ($Status.LastOccurrence -is [DateTimeOffset]) {
                        $Status.LastOccurrence.DateTime.ToLocalTime()
                    } else {
                        ([datetime]$Status.LastOccurrence).ToLocalTime()
                    }
                    $NextOccurrence = $NextOccurrences | Where-Object { $_ -gt $LastOccurrenceDateTime -and $_ -le (Get-Date) } | Select-Object -First 1
                }
            }
            
            # Only return timers that have a valid next occurrence (or if listing all)
            if ($NextOccurrence -or $ListAllTasks.IsPresent) {
                if (!$Status) {
                    # Create new status entry
                    $Status = [pscustomobject]@{
                        PartitionKey       = 'Timer'
                        RowKey             = $Timer.Id
                        Command            = $Timer.Command
                        Cron               = $CronString
                        LastOccurrence     = 'Never'
                        NextOccurrence     = $NextOccurrence.ToUniversalTime()
                        Status             = 'Not Scheduled'
                        OrchestratorId     = ''
                        RunOnProcessor     = if ($null -ne $Timer.RunOnProcessor) { $Timer.RunOnProcessor } else { $true }
                        IsSystem           = if ($null -ne $Timer.IsSystem) { $Timer.IsSystem } else { $false }
                        PreferredProcessor = $Timer.PreferredProcessor ?? ''
                    }
                    Add-LinkToMeAzDataTableEntity @Table -Entity $Status -Force | Out-Null
                } else {
                    # Update existing status - use Add-Member to safely update properties
                    $Status | Add-Member -MemberType NoteProperty -Name 'Command' -Value $Timer.Command -Force
                    $Status | Add-Member -MemberType NoteProperty -Name 'Cron' -Value $CronString -Force
                    $Status | Add-Member -MemberType NoteProperty -Name 'NextOccurrence' -Value $NextOccurrence.ToUniversalTime() -Force
                    $PreferredProcessor = $Timer.PreferredProcessor ?? ''
                    $Status | Add-Member -MemberType NoteProperty -Name 'PreferredProcessor' -Value $PreferredProcessor -Force
                    Add-LinkToMeAzDataTableEntity @Table -Entity $Status -Force | Out-Null
                }
                
                [PSCustomObject]@{
                    Id                 = $Timer.Id
                    Priority           = if ($null -ne $Timer.Priority) { $Timer.Priority } else { 99 }
                    Command            = $Timer.Command
                    Parameters         = $Timer.Parameters ?? @{}
                    Cron               = $CronString
                    NextOccurrence     = $NextOccurrence.ToUniversalTime()
                    LastOccurrence     = $Status.LastOccurrence
                    Status             = $Status.Status
                    OrchestratorId     = $Status.OrchestratorId
                    RunOnProcessor     = if ($null -ne $Timer.RunOnProcessor) { $Timer.RunOnProcessor } else { $true }
                    IsSystem           = if ($null -ne $Timer.IsSystem) { $Timer.IsSystem } else { $false }
                    PreferredProcessor = $Timer.PreferredProcessor ?? ''
                    ErrorMsg           = $Status.ErrorMsg ?? ''
                }
            }
        }
        
        # Clean up stale status entries not in config
        foreach ($StaleStatus in $TimerStatus) {
            if ($Timers.Id -notcontains $StaleStatus.RowKey) {
                Write-Warning "Removing stale timer function entry: $($StaleStatus.RowKey)"
                Remove-LinkToMeAzDataTableEntity @Table -Entity $StaleStatus
            }
        }
        
        $ResultsArray = @($Results | Where-Object { $null -ne $_ } | Sort-Object Priority)
        Write-Information "Loaded $($ResultsArray.Count) timer functions ready to execute"
        return $ResultsArray
        
    } catch {
        Write-Warning "Error in Get-LinkTomeTimerFunctions: $($_.Exception.Message)"
        Write-Warning "Stack trace: $($_.ScriptStackTrace)"
        return @()
    }
}
