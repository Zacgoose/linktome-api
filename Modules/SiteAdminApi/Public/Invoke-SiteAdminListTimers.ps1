function Invoke-SiteAdminListTimers {
    <#
    .SYNOPSIS
        List all configured timer functions with their status (site admin only)
    
    .DESCRIPTION
        Returns a list of all timer functions configured in LinkTomeTimers.json along with
        their current status, last occurrence, next scheduled occurrence, and any error messages.
        Requires read:siteadmin permission (site_super_admin role).
    
    .PARAMETER Request
        The HTTP request object
    
    .PARAMETER TriggerMetadata
        Azure Functions trigger metadata
    
    .EXAMPLE
        GET /siteadmin/timers
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata
    )

    try {
        # Auth is handled by the entrypoint - just use the authenticated user
        $User = $Request.AuthenticatedUser
        
        # Load timer configuration
        $TimersJsonPath = Join-Path $PSScriptRoot '../../../LinkTomeTimers.json'
        if (-not (Test-Path $TimersJsonPath)) {
            throw "LinkTomeTimers.json not found at: $TimersJsonPath"
        }

        $Timers = Get-Content $TimersJsonPath -Raw | ConvertFrom-Json

        # Get timer status from table
        $Table = Get-LinkToMeTable -TableName 'LinkTomeTimers'
        $TimerStatuses = Get-LinkToMeAzDataTableEntity @Table

        # Build response with timer configuration and status
        $TimerList = @()
        foreach ($Timer in $Timers) {
            $Status = $TimerStatuses | Where-Object { $_.RowKey -eq $Timer.Id } | Select-Object -First 1

            $TimerInfo = @{
                id = $Timer.Id
                command = $Timer.Command
                description = $Timer.Description
                cron = $Timer.Cron
                priority = $Timer.Priority
                runOnProcessor = $Timer.RunOnProcessor
                isSystem = if ($Timer.PSObject.Properties['IsSystem']) { $Timer.IsSystem } else { $false }
            }

            if ($Status) {
                $TimerInfo.status = if ($Status.PSObject.Properties['Status']) { $Status.Status } else { 'Unknown' }
                $TimerInfo.lastOccurrence = if ($Status.PSObject.Properties['LastOccurrence']) { 
                    $Status.LastOccurrence.ToString('o') 
                } else { 
                    $null 
                }
                $TimerInfo.nextOccurrence = if ($Status.PSObject.Properties['NextOccurrence']) { 
                    $Status.NextOccurrence.ToString('o') 
                } else { 
                    $null 
                }
                $TimerInfo.orchestratorId = if ($Status.PSObject.Properties['OrchestratorId']) { 
                    $Status.OrchestratorId 
                } else { 
                    $null 
                }
                $TimerInfo.errorMsg = if ($Status.PSObject.Properties['ErrorMsg']) { 
                    $Status.ErrorMsg 
                } else { 
                    $null 
                }
                $TimerInfo.manuallyTriggered = if ($Status.PSObject.Properties['ManuallyTriggered']) { 
                    $Status.ManuallyTriggered 
                } else { 
                    $false 
                }
                $TimerInfo.manuallyTriggeredBy = if ($Status.PSObject.Properties['ManuallyTriggeredBy']) { 
                    $Status.ManuallyTriggeredBy 
                } else { 
                    $null 
                }
                $TimerInfo.manuallyTriggeredByRole = if ($Status.PSObject.Properties['ManuallyTriggeredByRole']) { 
                    $Status.ManuallyTriggeredByRole 
                } else { 
                    $null 
                }
                $TimerInfo.manuallyTriggeredAt = if ($Status.PSObject.Properties['ManuallyTriggeredAt']) { 
                    $Status.ManuallyTriggeredAt.ToString('o') 
                } else { 
                    $null 
                }
            } else {
                $TimerInfo.status = 'Not yet run'
                $TimerInfo.lastOccurrence = $null
                $TimerInfo.nextOccurrence = $null
                $TimerInfo.orchestratorId = $null
                $TimerInfo.errorMsg = $null
                $TimerInfo.manuallyTriggered = $false
                $TimerInfo.manuallyTriggeredBy = $null
                $TimerInfo.manuallyTriggeredByRole = $null
                $TimerInfo.manuallyTriggeredAt = $null
            }

            $TimerList += $TimerInfo
        }

        return Send-ApiResponse -StatusCode 200 -Body @{
            success = $true
            timers = $TimerList
            count = $TimerList.Count
        }

    } catch {
        Write-Error "Error in Invoke-SiteAdminListTimers: $($_.Exception.Message)"
        Write-Error "Stack trace: $($_.ScriptStackTrace)"
        
        return Send-ApiResponse -StatusCode 500 -Body @{
            error = 'Internal server error'
            message = $_.Exception.Message
        }
    }
}
