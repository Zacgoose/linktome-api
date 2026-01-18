function Invoke-SiteAdminRunTimer {
    <#
    .SYNOPSIS
        Manually trigger a timer function to run immediately (site admin only)
    
    .DESCRIPTION
        Allows site administrators to manually trigger any timer function configured in LinkTomeTimers.json.
        This bypasses the normal cron schedule and runs the timer immediately.
        Inspired by CIPP-API's manual scheduler functionality.
    
    .PARAMETER Request
        The HTTP request object containing the timer ID to run
    
    .PARAMETER TriggerMetadata
        Azure Functions trigger metadata
    
    .EXAMPLE
        POST /siteadmin/runtimer
        Body: { "timerId": "c3d4e5f6-a7b8-9012-cdef-123456789012" }
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata
    )

    try {
        # Validate site admin permission
        $AuthContext = $Request.Context.AuthContext
        if (-not $AuthContext) {
            return Send-ApiResponse -StatusCode 401 -Body @{
                error = 'Authentication required'
                message = 'You must be authenticated to access this endpoint'
            }
        }

        # Check if user is a site admin (this would be a special role/flag in the Users table)
        # For now, we'll use an environment variable for site admin emails
        $SiteAdminEmails = ($env:SITE_ADMIN_EMAILS -split ',').Trim()
        if (-not ($SiteAdminEmails -contains $AuthContext.Email)) {
            Write-Warning "Unauthorized site admin access attempt by: $($AuthContext.Email)"
            return Send-ApiResponse -StatusCode 403 -Body @{
                error = 'Forbidden'
                message = 'This endpoint requires site administrator privileges'
            }
        }

        # Parse request body
        $Body = $Request.Body | ConvertFrom-Json -ErrorAction Stop
        
        if (-not $Body.timerId) {
            return Send-ApiResponse -StatusCode 400 -Body @{
                error = 'Missing required field'
                message = 'timerId is required'
            }
        }

        $TimerId = $Body.timerId

        # Load timer configuration
        $TimersJsonPath = Join-Path $PSScriptRoot '../../../LinkTomeTimers.json'
        if (-not (Test-Path $TimersJsonPath)) {
            throw "LinkTomeTimers.json not found at: $TimersJsonPath"
        }

        $Timers = Get-Content $TimersJsonPath -Raw | ConvertFrom-Json
        $Timer = $Timers | Where-Object { $_.Id -eq $TimerId } | Select-Object -First 1

        if (-not $Timer) {
            return Send-ApiResponse -StatusCode 404 -Body @{
                error = 'Timer not found'
                message = "No timer found with ID: $TimerId"
            }
        }

        # Check if the command function exists
        $CommandExists = Get-Command -Name $Timer.Command -ErrorAction SilentlyContinue
        if (-not $CommandExists) {
            return Send-ApiResponse -StatusCode 400 -Body @{
                error = 'Invalid timer configuration'
                message = "Timer command not found: $($Timer.Command)"
            }
        }

        Write-Information "Site admin $($AuthContext.Email) manually triggering timer: $($Timer.Command)"

        # Get timer status table
        $Table = Get-LinkToMeTable -TableName 'LinkTomeTimers'
        $FunctionStatus = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$TimerId'" | Select-Object -First 1

        # Check if orchestrator is still running
        if ($FunctionStatus -and $FunctionStatus.OrchestratorId) {
            $FunctionName = $env:WEBSITE_SITE_NAME
            $InstancesTable = Get-LinkToMeTable -TableName ('{0}Instances' -f ($FunctionName -replace '-', ''))
            $Instance = Get-LinkToMeAzDataTableEntity @InstancesTable -Filter "PartitionKey eq '$($FunctionStatus.OrchestratorId)'" -Property PartitionKey, RowKey, RuntimeStatus | Select-Object -First 1
            
            if ($Instance -and $Instance.RuntimeStatus -eq 'Running') {
                return Send-ApiResponse -StatusCode 409 -Body @{
                    error = 'Timer already running'
                    message = "Timer $($Timer.Command) has an orchestrator still running: $($FunctionStatus.OrchestratorId)"
                    orchestratorId = $FunctionStatus.OrchestratorId
                    status = 'Running'
                }
            }
        }

        # Execute the timer function
        try {
            $Parameters = @{}
            if ($Timer.PSObject.Properties['Parameters'] -and $Timer.Parameters) {
                $Parameters = $Timer.Parameters
            }

            Write-Information "Manually executing timer: $($Timer.Command)"
            $Results = & $Timer.Command @Parameters

            # Check if result is an orchestrator ID (GUID)
            $OrchestratorId = $null
            if ($Results -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                $OrchestratorId = $Results
                $Status = 'Started'
                Write-Information "Timer started orchestrator: $OrchestratorId"
            } else {
                $Status = 'Completed'
                Write-Information "Timer completed successfully"
            }

            # Update timer status
            $UtcNow = (Get-Date).ToUniversalTime()
            if ($FunctionStatus) {
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'LastOccurrence' -Value $UtcNow -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'Status' -Value $Status -Force
                if ($OrchestratorId) {
                    $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'OrchestratorId' -Value $OrchestratorId -Force
                }
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'ErrorMsg' -Value '' -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'ManuallyTriggered' -Value $true -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'ManuallyTriggeredBy' -Value $AuthContext.Email -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'ManuallyTriggeredAt' -Value $UtcNow -Force
                
                Add-LinkToMeAzDataTableEntity @Table -Entity $FunctionStatus -Force | Out-Null
            }

            return Send-ApiResponse -StatusCode 200 -Body @{
                success = $true
                message = "Timer $($Timer.Command) executed successfully"
                timerId = $TimerId
                command = $Timer.Command
                status = $Status
                orchestratorId = $OrchestratorId
                executedAt = $UtcNow.ToString('o')
                executedBy = $AuthContext.Email
            }

        } catch {
            $ErrorMsg = $_.Exception.Message
            Write-Warning "Error executing timer $($Timer.Command): $ErrorMsg"
            Write-Warning "Stack trace: $($_.ScriptStackTrace)"

            # Update timer status with error
            if ($FunctionStatus) {
                $UtcNow = (Get-Date).ToUniversalTime()
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'LastOccurrence' -Value $UtcNow -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'Status' -Value 'Failed' -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'ErrorMsg' -Value $ErrorMsg -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'ManuallyTriggered' -Value $true -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'ManuallyTriggeredBy' -Value $AuthContext.Email -Force
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name 'ManuallyTriggeredAt' -Value $UtcNow -Force
                
                Add-LinkToMeAzDataTableEntity @Table -Entity $FunctionStatus -Force | Out-Null
            }

            return Send-ApiResponse -StatusCode 500 -Body @{
                error = 'Timer execution failed'
                message = $ErrorMsg
                timerId = $TimerId
                command = $Timer.Command
            }
        }

    } catch {
        Write-Error "Error in Invoke-SiteAdminRunTimer: $($_.Exception.Message)"
        Write-Error "Stack trace: $($_.ScriptStackTrace)"
        
        return Send-ApiResponse -StatusCode 500 -Body @{
            error = 'Internal server error'
            message = $_.Exception.Message
        }
    }
}
