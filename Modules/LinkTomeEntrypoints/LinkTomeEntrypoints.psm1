using namespace System.Net

function Receive-LinkTomeHttpTrigger {
    <#
    .SYNOPSIS
        Execute HTTP trigger function
    .DESCRIPTION
        Execute HTTP trigger function from azure function app
    .PARAMETER Request
        The request object from the function app
    .PARAMETER TriggerMetadata
        The trigger metadata object from the function app
    .FUNCTIONALITY
        Entrypoint
    #>
    param(
        $Request,
        $TriggerMetadata
    )

    if ($Request.Headers.'x-ms-coldstart' -eq 1) {
        Write-Information '** Function app cold start detected **'
    }

    # Convert the request to a PSCustomObject because the httpContext is case sensitive since 7.3
    $Request = $Request | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName

    # Process request through central router
    $Response = New-LinkTomeCoreRequest -Request $Request -TriggerMetadata $TriggerMetadata
    
    if ($Response -is [System.Array]) {
        # Array responses can happen via pipeline; pick first element with a non-null StatusCode, otherwise null to trigger fallback
        $FirstValid = $null
        foreach ($item in $Response) {
            if ($null -eq $item) { continue }
            if ($item.PSObject.Properties['StatusCode'] -and $null -ne $item.StatusCode) {
                $FirstValid = $item
                break
            }
        }
        $Response = $FirstValid
        # If no element matches, $Response will be $null and the fallback block below will run
    }

    if ($null -ne $Response -and $null -ne $Response.StatusCode) {
        if ($Response.Body -is [PSCustomObject]) {
            $Response.Body = $Response.Body | ConvertTo-Json -Depth 20 -Compress
        }
        
        # Always use HttpResponseContext for consistent handling
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]$Response)
    } else {
        # Fallback error response
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                error = @{
                    code    = 'InternalServerError'
                    message = 'An error occurred processing the request'
                }
            }
        })
    }
    return
}

function New-LinkTomeCoreRequest {
    param(
        $Request,
        $TriggerMetadata
    )

    $Endpoint = $Request.Params.Endpoint
    Write-Information "Processing endpoint: $Endpoint"

    # ============================================================
    # FUNCTION NAME RESOLUTION
    # v1/* maps to Admin* functions (same logic, different auth)
    # ============================================================
    $FunctionEndpoint = $Endpoint
    $IsApiRoute = $false
    
    if ($Endpoint -match '^v1/(.+)$') {
        $IsApiRoute = $true
        # Map v1/getLinks → admin/getLinks for function resolution
        $FunctionEndpoint = "admin/$($Matches[1])"
    }
    
    $Parts = $FunctionEndpoint -split '/'
    $CapitalizedParts = $Parts | ForEach-Object { 
        $_.Substring(0, 1).ToUpper() + $_.Substring(1)
    }
    $FunctionName = 'Invoke-{0}' -f ($CapitalizedParts -join '')
    
    Write-Information "Resolved: $Endpoint -> $FunctionName"

    if (-not (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::NotFound
            Body = @{ error = "Endpoint not found: $Endpoint" }
        }
    }

    try {
        $ClientIP = Get-ClientIPAddress -Request $Request

        # ============================================================
        # API v1 ENDPOINTS - API Key auth
        # ============================================================
        if ($IsApiRoute) {
            
            $ApiKeyResult = Get-ApiKeyFromRequest -Request $Request
            
            if (-not $ApiKeyResult.Valid) {
                Write-SecurityEvent -EventType 'ApiAuthFailed' -IpAddress $ClientIP -Endpoint $Endpoint -Reason $ApiKeyResult.Error
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Unauthorized
                    Headers = @{ 'WWW-Authenticate' = 'Bearer realm="api"' }
                    Body = @{ error = $ApiKeyResult.Error }
                }
            }
            
            # Rate limit check
            $RateLimit = Test-ApiRateLimit -KeyId $ApiKeyResult.KeyId -UserId $ApiKeyResult.UserId -Tier $ApiKeyResult.Tier
            
            if (-not $RateLimit.Allowed) {
                Write-SecurityEvent -EventType 'ApiRateLimited' -UserId $ApiKeyResult.UserId -IpAddress $ClientIP `
                    -Endpoint $Endpoint -Reason "Limit: $($RateLimit.LimitType)"
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::TooManyRequests
                    Headers = @{
                        'Retry-After'           = $RateLimit.RetryAfter.ToString()
                        'X-RateLimit-Limit'     = $RateLimit.Limit.ToString()
                        'X-RateLimit-Remaining' = '0'
                    }
                    Body = @{ 
                        error      = "Rate limit exceeded ($($RateLimit.LimitType))"
                        retryAfter = $RateLimit.RetryAfter
                    }
                }
            }
            
            # Permission check (uses the mapped admin endpoint for permission lookup)
            $RequiredPermissions = Get-EndpointPermissions -Endpoint $FunctionEndpoint
            
            if ($null -eq $RequiredPermissions) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ error = "Access denied" }
                }
            }
            
            if ($RequiredPermissions.Count -gt 0) {
                $ContextUserId = $Request.Query.UserId
                
                $HasPermission = Test-ApiKeyContextPermission `
                    -ApiKeyResult $ApiKeyResult `
                    -RequiredPermissions $RequiredPermissions `
                    -ContextUserId $ContextUserId
                
                if (-not $HasPermission.Allowed) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body = @{ error = $HasPermission.Reason }
                    }
                }
            }
            
            # Set context for downstream
            if ($Request.Query.UserId) {
                $Request | Add-Member -NotePropertyName 'ContextUserId' -NotePropertyValue $Request.Query.UserId -Force
            }
            
            $Request | Add-Member -NotePropertyName 'AuthMethod' -NotePropertyValue 'apikey' -Force
            $Request | Add-Member -NotePropertyName 'ApiKeyId' -NotePropertyValue $ApiKeyResult.KeyId -Force
            $Request | Add-Member -NotePropertyName 'RateLimitInfo' -NotePropertyValue $RateLimit -Force
            $Request | Add-Member -NotePropertyName 'AuthenticatedUser' -NotePropertyValue @{
                UserId          = $ApiKeyResult.UserId
                Email           = $ApiKeyResult.User.PartitionKey
                Username        = $ApiKeyResult.User.Username
                Roles           = $ApiKeyResult.UserRoles
                Permissions     = $ApiKeyResult.KeyPermissions
                userManagements = $ApiKeyResult.UserManagements
            } -Force
            
            Write-Information "API auth | Key: $($ApiKeyResult.KeyId) | User: $($ApiKeyResult.UserId) | Tier: $($ApiKeyResult.Tier)"
        }
        
        # ============================================================
        # PUBLIC AUTH ENDPOINTS - Turnstile + Header validation
        # ============================================================
        elseif ($Endpoint -match '^public/(login|signup|refreshToken)$') {
            $Suspicion = Get-RequestSuspicionScore -Request $Request
            Write-Information "Auth request | IP: $ClientIP | Score: $($Suspicion.Score)"
            
            if ($Suspicion.IsLikelyBot) {
                Write-SecurityEvent -EventType 'BotBlocked' -IpAddress $ClientIP -Endpoint $Endpoint
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Request validation failed" }
                }
            }
            
            $RateLimitConfig = @{
                'public/login'  = @{
                    Normal     = @{ MaxRequests = 5; WindowSeconds = 60 }
                    Suspicious = @{ MaxRequests = 2; WindowSeconds = 60 }
                }
                'public/signup' = @{
                    Normal     = @{ MaxRequests = 3; WindowSeconds = 300 }
                    Suspicious = @{ MaxRequests = 1; WindowSeconds = 300 }
                }
                'public/refreshToken' = @{
                    Normal     = @{ MaxRequests = 3; WindowSeconds = 60 }
                    Suspicious = @{ MaxRequests = 1; WindowSeconds = 60 }
                }
            }
            
            $Config = $RateLimitConfig[$Endpoint]
            if ($Config) {
                $Limits = if ($Suspicion.IsSuspicious) { $Config.Suspicious } else { $Config.Normal }
                $RateLimitId = if ($Suspicion.IsSuspicious) { "suspicious:$ClientIP" } else { $ClientIP }
                
                $RateCheck = Test-RateLimit -Identifier $RateLimitId -Endpoint $Endpoint `
                    -MaxRequests $Limits.MaxRequests -WindowSeconds $Limits.WindowSeconds
                
                if (-not $RateCheck.Allowed) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::TooManyRequests
                        Headers = @{ 'Retry-After' = $RateCheck.RetryAfter.ToString() }
                        Body = @{ error = "Too many requests" }
                    }
                }
            }
            
            $Request | Add-Member -NotePropertyName 'AuthMethod' -NotePropertyValue 'public' -Force
            $Request | Add-Member -NotePropertyName 'SuspicionScore' -NotePropertyValue $Suspicion.Score -Force
        }
        
        # ============================================================
        # OTHER PUBLIC ENDPOINTS
        # ============================================================
        elseif ($Endpoint -match '^public/') {
            $RateCheck = Test-RateLimit -Identifier $ClientIP -Endpoint $Endpoint -MaxRequests 30 -WindowSeconds 60
            if (-not $RateCheck.Allowed) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::TooManyRequests
                    Body = @{ error = "Too many requests" }
                }
            }
            $Request | Add-Member -NotePropertyName 'AuthMethod' -NotePropertyValue 'public' -Force
        }
        
        # ============================================================
        # ADMIN ENDPOINTS - Cookie/JWT auth
        # ============================================================
        elseif ($Endpoint -match '^admin/') {
            $User = Get-UserFromRequest -Request $Request
            if (-not $User) {
                Write-SecurityEvent -EventType 'AuthFailed' -Endpoint $Endpoint -IpAddress $ClientIP
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Unauthorized
                    Body = @{ error = "Unauthorized" }
                }
            }

            # Rate limit check
            $RateLimit = Test-RateLimit -Identifier $User.UserId -Endpoint $Endpoint -MaxRequests 30 -WindowSeconds 30
            if (-not $RateLimit.Allowed) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::TooManyRequests
                    Body = @{ error = "Too many requests" }
                }
            }

            $RequiredPermissions = Get-EndpointPermissions -Endpoint $Endpoint
            
            if ($null -eq $RequiredPermissions) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ error = "Access denied" }
                }
            }
            
            if ($RequiredPermissions.Count -gt 0) {
                $UserId = $Request.Query.UserId
                $HasPermission = Test-ContextAwarePermission -User $User -RequiredPermissions $RequiredPermissions -UserId $UserId
                if (-not $HasPermission) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body = @{ error = "Insufficient permissions" }
                    }
                }
            }

            if ($Request.Query.UserId) {
                $Request | Add-Member -NotePropertyName 'ContextUserId' -NotePropertyValue $Request.Query.UserId -Force
            }
            
            $Request | Add-Member -NotePropertyName 'AuthMethod' -NotePropertyValue 'session' -Force
            $Request | Add-Member -NotePropertyName 'AuthenticatedUser' -NotePropertyValue $User -Force
        }

        # Invoke function
        $Response = & $FunctionName -Request $Request -TriggerMetadata $TriggerMetadata
        
        # Add rate limit headers for v1 responses
        if ($IsApiRoute -and $Request.RateLimitInfo -and $Response.StatusCode -lt 400) {
            $RL = $Request.RateLimitInfo
            if (-not $Response.Headers) { $Response.Headers = @{} }
            $Response.Headers['X-RateLimit-Limit-Minute'] = $RL.MinuteLimit.ToString()
            $Response.Headers['X-RateLimit-Remaining-Minute'] = $RL.MinuteRemaining.ToString()
            $Response.Headers['X-RateLimit-Limit-Day'] = $RL.DayLimit.ToString()
            $Response.Headers['X-RateLimit-Remaining-Day'] = $RL.DayRemaining.ToString()
        }
        
        return $Response
        
    } catch {
        Write-Warning "Exception on $FunctionName : $($_.Exception.Message)"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{ error = $_.Exception.Message }
        }
    }
}

function Receive-LinkTomeOrchestrationTrigger {
    <#
    .SYNOPSIS
        Execute durable orchestrator function
    .DESCRIPTION
        Execute orchestrator from azure function app
    .PARAMETER Context
        The context object from the function app
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Context)
    Write-Debug "LINKTOME_ACTION=Orchestrator"
    try {
        if (Test-Json -Json $Context.Input) {
            $OrchestratorInput = $Context.Input | ConvertFrom-Json
        } else {
            $OrchestratorInput = $Context.Input
        }
        Write-Information "Orchestrator started $($OrchestratorInput.OrchestratorName)"
        Set-DurableCustomStatus -CustomStatus $OrchestratorInput.OrchestratorName
        $DurableRetryOptions = @{
            FirstRetryInterval  = (New-TimeSpan -Seconds 5)
            MaxNumberOfAttempts = if ($OrchestratorInput.MaxAttempts) { $OrchestratorInput.MaxAttempts } else { 1 }
            BackoffCoefficient  = 2
        }

        switch ($OrchestratorInput.DurableMode) {
            'FanOut' {
                $DurableMode = 'FanOut'
                $NoWait = $true
            }
            'Sequence' {
                $DurableMode = 'Sequence'
                $NoWait = $false
            }
            'NoScaling' {
                $DurableMode = 'NoScaling'
                $NoWait = $false
            }
            default {
                $DurableMode = 'FanOut (Default)'
                $NoWait = $true
            }
        }
        Write-Information "Durable Mode: $DurableMode"

        $RetryOptions = New-DurableRetryOptions @DurableRetryOptions
        if (!$OrchestratorInput.Batch -or ($OrchestratorInput.Batch | Measure-Object).Count -eq 0) {
            $Batch = (Invoke-ActivityFunction -FunctionName 'LinkTomeActivityFunction' -Input $OrchestratorInput.QueueFunction -ErrorAction Stop) | Where-Object { $null -ne $_.FunctionName }
        } else {
            $Batch = $OrchestratorInput.Batch | Where-Object { $null -ne $_.FunctionName }
        }

        if (($Batch | Measure-Object).Count -gt 0) {
            Write-Information "Batch Count: $($Batch.Count)"
            $Output = foreach ($Item in $Batch) {
                if ($DurableMode -eq 'NoScaling') {
                    $Activity = @{
                        FunctionName = 'LinkTomeActivityFunction'
                        Input        = $Item
                        ErrorAction  = 'Stop'
                    }
                    Invoke-ActivityFunction @Activity
                } else {
                    $DurableActivity = @{
                        FunctionName = 'LinkTomeActivityFunction'
                        Input        = $Item
                        NoWait       = $NoWait
                        RetryOptions = $RetryOptions
                        ErrorAction  = 'Stop'
                    }
                    Invoke-DurableActivity @DurableActivity
                }
            }

            if ($NoWait -and $Output) {
                $Output = $Output | Where-Object { $_.GetType().Name -eq 'ActivityInvocationTask' }
                if (($Output | Measure-Object).Count -gt 0) {
                    Write-Information "Waiting for ($($Output.Count)) activity functions to complete..."
                    $Results = foreach ($Task in $Output) {
                        try {
                            Wait-ActivityFunction -Task $Task
                        } catch {}
                    }
                } else {
                    $Results = @()
                }
            } else {
                $Results = $Output
            }
        }

        if ($Results -and $OrchestratorInput.PostExecution) {
            Write-Information "Running post execution function $($OrchestratorInput.PostExecution.FunctionName)"
            $PostExecParams = @{
                FunctionName = $OrchestratorInput.PostExecution.FunctionName
                Parameters   = $OrchestratorInput.PostExecution.Parameters
                Results      = @($Results)
            }
            if ($null -ne $PostExecParams.FunctionName) {
                $null = Invoke-ActivityFunction -FunctionName LinkTomeActivityFunction -Input $PostExecParams
                Write-Information "Post execution function $($OrchestratorInput.PostExecution.FunctionName) completed"
            } else {
                Write-Information 'No post execution function name provided'
                Write-Information ($PostExecParams | ConvertTo-Json -Depth 10)
            }
        }
    } catch {
        Write-Information "Orchestrator error $($_.Exception.Message) line $($_.InvocationInfo.ScriptLineNumber)"
    }
    return $true
}

function Receive-LinkTomeActivityTrigger {
    <#
    .SYNOPSIS
        Execute durable activity function
    .DESCRIPTION
        Execute durable activity function from an orchestrator
    .PARAMETER Item
        The item to process
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)
    $DebugAction = if ($Item.Command) { $Item.Command } else { $Item.FunctionName }
    Write-Debug "LINKTOME_ACTION=$DebugAction"
    Write-Information "Activity function running: $($Item | ConvertTo-Json -Depth 10 -Compress)"
    try {
        $Output = $null
        Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName
        
        $metric = @{
            Kind         = 'LinkTomeCommandStart'
            InvocationId = "$($ExecutionContext.InvocationId)"
            Command      = $Item.Command
            TaskName     = $Item.TaskName
            JSONData     = ($Item | ConvertTo-Json -Depth 10 -Compress)
        } | ConvertTo-Json -Depth 10 -Compress

        Write-Information -MessageData $metric -Tag 'LinkTomeCommandStart'

        if ($Item.FunctionName) {
            $FunctionName = 'Push-{0}' -f $Item.FunctionName

            try {
                Write-Verbose "Activity starting Function: $FunctionName."
                Invoke-Command -ScriptBlock { & $FunctionName -Item $Item }
                $Status = 'Completed'
                Write-Verbose "Activity completed Function: $FunctionName."
            } catch {
                $Status = 'Failed'
                Write-Warning "Activity error Function: $FunctionName - $($_.Exception.Message)"
                throw
            }
        } elseif ($Item.Command) {
            try {
                Write-Verbose "Activity running Command: $($Item.Command)"
                if ($Item.Parameters) {
                    $Parameters = $Item.Parameters
                } else {
                    $Parameters = @{}
                }
                $Output = Invoke-Command -ScriptBlock { & $Item.Command @Parameters }
                $Status = 'Completed'
                Write-Verbose "Activity completed Command: $($Item.Command)"
            } catch {
                $Status = 'Failed'
                Write-Warning "Activity error Command: $($Item.Command) - $($_.Exception.Message)"
                throw
            }
        } else {
            Write-Warning 'Activity function called with no FunctionName or Command'
            $Status = 'Failed'
        }

        $metric = @{
            Kind         = 'LinkTomeCommandEnd'
            InvocationId = "$($ExecutionContext.InvocationId)"
            Command      = $Item.Command
            Status       = $Status
        } | ConvertTo-Json -Depth 10 -Compress

        Write-Information -MessageData $metric -Tag 'LinkTomeCommandEnd'
    } catch {
        Write-Warning "Activity function error: $($_.Exception.Message)"
        throw
    }

    if ($null -ne $Output -and $Output -ne '') {
        return $Output
    } else {
        return "Activity function ended with status $($Status)."
    }
}

function Receive-LinkTomeTimerTrigger {
    <#
    .SYNOPSIS
        This function is used to execute timer functions based on the cron schedule.
    .DESCRIPTION
        This function is used to execute timer functions based on the cron schedule.
    .PARAMETER Timer
        The timer trigger object from the function app
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Timer)

    $UtcNow = (Get-Date).ToUniversalTime()
    $Functions = Get-LinkTomeTimerFunctions
    $Table = Get-LinkToMeTable -tablename LinkTomeTimers
    $Statuses = Get-LinkToMeAzDataTableEntity @Table
    $FunctionName = $env:WEBSITE_SITE_NAME

    foreach ($Function in $Functions) {
        Write-Information "LinkTomeTimer: Evaluating $($Function.Command) - $($Function.Cron)"
        $FunctionStatus = $Statuses | Where-Object { $_.RowKey -eq $Function.Id }
        
        # Create a new status entity if it doesn't exist
        if (-not $FunctionStatus) {
            Write-Information "Creating new status entry for timer: $($Function.Id)"
            $FunctionStatus = @{
                PartitionKey = 'Timer'
                RowKey = $Function.Id
                LastOccurrence = $null
                Status = 'Pending'
                OrchestratorId = $null
            }
        }
        
        # Check if this timer should run based on cron schedule and last occurrence
        $LastOccurrence = if ($FunctionStatus.LastOccurrence) { 
            # Convert DateTimeOffset to DateTime for cron evaluation
            if ($FunctionStatus.LastOccurrence -is [DateTimeOffset]) {
                $FunctionStatus.LastOccurrence.DateTime
            } else {
                [datetime]$FunctionStatus.LastOccurrence
            }
        } else { 
            $null 
        }
        
        $ShouldRun = Test-CronSchedule -CronExpression $Function.Cron -LastOccurrence $LastOccurrence -CurrentTime $UtcNow
        
        if (-not $ShouldRun) {
            Write-Information "Skipping $($Function.Command) - not scheduled to run at this time"
            continue
        }
        
        Write-Information "Executing timer: $($Function.Command) - $($Function.Cron)"
        
        if ($FunctionStatus.OrchestratorId) {
            $FunctionName = $env:WEBSITE_SITE_NAME
            $InstancesTable = Get-LinkToMeTable -TableName ('{0}Instances' -f ($FunctionName -replace '-', ''))
            $Instance = Get-LinkToMeAzDataTableEntity @InstancesTable -Filter "PartitionKey eq '$($FunctionStatus.OrchestratorId)'" -Property PartitionKey, RowKey, RuntimeStatus
            if ($Instance.RuntimeStatus -eq 'Running') {
                Write-Warning "LinkTome Timer: $($Function.Command) - $($FunctionStatus.OrchestratorId) is still running, skipping execution"
                continue
            }
        }
        
        try {
            if ($FunctionStatus -is [hashtable]) {
                # For hashtables, we can directly set values
                if ($FunctionStatus.ContainsKey('ErrorMsg')) {
                    $FunctionStatus['ErrorMsg'] = ''
                }
            } elseif ($FunctionStatus.PSObject.Properties.Name -contains 'ErrorMsg') {
                $FunctionStatus.ErrorMsg = ''
            }

            $Parameters = @{}
            if ($Function.Parameters) {
                $Parameters = $Function.Parameters | ConvertTo-Json | ConvertFrom-Json -AsHashtable
            }

            $metadata = @{
                Command     = $Function.Command
                Cron        = $Function.Cron
                FunctionId  = $Function.Id
                TriggerType = 'Timer'
            }

            if ($Parameters.Count -gt 0) {
                $metadata['ParameterCount'] = $Parameters.Count
                Write-Information "LINKTOME TIMER PARAMETERS: $($Parameters | ConvertTo-Json -Depth 10 -Compress)"
            }

            $Results = Invoke-Command -ScriptBlock { & $Function.Command @Parameters }

            if ($Results -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                if ($FunctionStatus -is [hashtable]) {
                    $FunctionStatus['OrchestratorId'] = $Results -join ','
                } else {
                    $FunctionStatus.OrchestratorId = $Results -join ','
                }
                $Status = 'Started'
            } else {
                $Status = 'Completed'
            }
        } catch {
            $Status = 'Failed'
            $ErrorMsg = $_.Exception.Message
            if ($FunctionStatus -is [hashtable]) {
                $FunctionStatus['ErrorMsg'] = $ErrorMsg
            } elseif ($FunctionStatus.PSObject.Properties.Name -contains 'ErrorMsg') {
                $FunctionStatus.ErrorMsg = $ErrorMsg
            } else {
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name ErrorMsg -Value $ErrorMsg
            }
            Write-Information "Error in LinkTomeTimer for $($Function.Command): $($_.Exception.Message)"
        }
        
        # Update status properties
        if ($FunctionStatus -is [hashtable]) {
            $FunctionStatus['LastOccurrence'] = $UtcNow
            $FunctionStatus['Status'] = $Status
        } else {
            $FunctionStatus.LastOccurrence = $UtcNow
            $FunctionStatus.Status = $Status
        }

        # Only save if entity is valid
        try {
            Add-LinkToMeAzDataTableEntity @Table -Entity $FunctionStatus -Force
        } catch {
            Write-Warning "Failed to save timer status for $($Function.Command): $($_.Exception.Message)"
        }
    }
    return $true
}

Export-ModuleMember -Function @('Receive-LinkTomeHttpTrigger', 'New-LinkTomeCoreRequest', 'Receive-LinkTomeOrchestrationTrigger', 'Receive-LinkTomeActivityTrigger', 'Receive-LinkTomeTimerTrigger')
