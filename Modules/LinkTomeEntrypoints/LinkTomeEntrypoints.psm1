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
    <#
    .SYNOPSIS
        Central request router (CIPP-style)
    .DESCRIPTION
        Routes requests to appropriate handlers based on endpoint using dynamic function resolution
    #>
    param(
        $Request,
        $TriggerMetadata
    )

    $Endpoint = $Request.Params.Endpoint
    Write-Information "Processing endpoint: $Endpoint"

    # Build function name from endpoint (e.g., 'public/GetUserProfile' -> 'Invoke-PublicGetUserProfile')
    $Parts = $Endpoint -split '/'
    $CapitalizedParts = $Parts | ForEach-Object { 
        $_.Substring(0, 1).ToUpper() + $_.Substring(1)
    }
    $FunctionName = 'Invoke-{0}' -f ($CapitalizedParts -join '')
    
    Write-Information "Resolved: $Endpoint -> $FunctionName"

    # Check if function exists
    if (-not (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue)) {
        Write-Warning "Function not found: $FunctionName"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::NotFound
            Body = @{ error = "Endpoint not found: $Endpoint" }
        }
    }

    try {
        # Apply rate limiting for authentication endpoints
        if ($Endpoint -match '^public/(login|signup|refreshToken)$') {
            # Get client IP from headers
            $ClientIP = Get-ClientIPAddress -Request $Request

            # === Bot Detection ===
            $Suspicion = Get-RequestSuspicionScore -Request $Request
            
            # Log for analysis (helps tune thresholds over time)
            Write-Information "Auth request | IP: $ClientIP | Endpoint: $Endpoint | Score: $($Suspicion.Score) | Flags: $($Suspicion.Flags -join ', ')"
            
            # Block obvious bots before they even hit rate limiting
            if ($Suspicion.IsLikelyBot) {
                Write-SecurityEvent -EventType 'BotBlocked' -IpAddress $ClientIP -Endpoint $Endpoint -Reason "Suspicion score: $($Suspicion.Score), Flags: $($Suspicion.Flags -join ', ')"
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Request validation failed" }
                }
            }
            
            # === Rate Limiting (stricter for suspicious requests) ===
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
                    Normal     = @{ MaxRequests = 10; WindowSeconds = 60 }
                    Suspicious = @{ MaxRequests = 1; WindowSeconds = 60 }
                }
            }
            
            $Config = $RateLimitConfig[$Endpoint]
            if ($Config) {
                $Limits = if ($Suspicion.IsSuspicious) { $Config.Suspicious } else { $Config.Normal }
                $RateLimitIdentifier = if ($Suspicion.IsSuspicious) { "suspicious:$ClientIP" } else { $ClientIP }
                
                $RateCheck = Test-RateLimit -Identifier $RateLimitIdentifier -Endpoint $Endpoint `
                    -MaxRequests $Limits.MaxRequests -WindowSeconds $Limits.WindowSeconds
                
                if (-not $RateCheck.Allowed) {
                    Write-Warning "Rate limit exceeded for $Endpoint from $ClientIP (suspicious: $($Suspicion.IsSuspicious))"
                    
                    Write-SecurityEvent -EventType 'RateLimitExceeded' -IpAddress $ClientIP -Endpoint $Endpoint -Reason (ConvertTo-Json @{
                        RequestCount  = $RateCheck.RequestCount
                        MaxRequests   = $RateCheck.MaxRequests
                        WasSuspicious = $Suspicion.IsSuspicious
                        SuspicionFlags = $Suspicion.Flags
                    })
                    
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::TooManyRequests
                        Headers = @{
                            'Retry-After' = $RateCheck.RetryAfter.ToString()
                        }
                        Body = @{ 
                            error = "Too many requests. Please try again in $($RateCheck.RetryAfter) seconds."
                            retryAfter = $RateCheck.RetryAfter
                        }
                    }
                }
            }
            
            # Only require Turnstile for login/signup, NOT refresh
            $Request | Add-Member -NotePropertyName 'RequiresTurnstile' -NotePropertyValue ($Endpoint -ne 'public/refreshToken') -Force
            $Request | Add-Member -NotePropertyName 'SuspicionScore' -NotePropertyValue $Suspicion.Score -Force
            $Request | Add-Member -NotePropertyName 'SuspicionFlags' -NotePropertyValue $Suspicion.Flags -Force
        }
        
        # Check authentication for admin endpoints
        if ($Endpoint -match '^admin/') {
            $User = Get-UserFromRequest -Request $Request
            if (-not $User) {
                # Log failed authentication attempt
                $ClientIP = Get-ClientIPAddress -Request $Request
                Write-SecurityEvent -EventType 'AuthFailed' -Endpoint $Endpoint -IpAddress $ClientIP
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Unauthorized
                    Body = @{ error = "Unauthorized: Invalid or expired token" }
                }
            }

            # Check permissions for the endpoint (context-aware)

            $RequiredPermissions = Get-EndpointPermissions -Endpoint $Endpoint
            $UserId = $Request.Query.UserId
            Write-Information "[Entrypoint] Permission check context:"
            Write-Information "[Entrypoint] UserId: $UserId"
            Write-Information "[Entrypoint] RequiredPermissions: $($RequiredPermissions -join ', ')"
            Write-Information "[Entrypoint] User object: $($User | ConvertTo-Json -Depth 10)"
            
            # If endpoint has no defined permissions (null), deny access by default (secure by default)
            # Empty array means no permissions required (intentional), null means not configured (deny)
            if ($null -eq $RequiredPermissions) {
                Write-Warning "[Entrypoint] No permissions defined for endpoint: $Endpoint - denying access"
                $ClientIP = Get-ClientIPAddress -Request $Request
                Write-SecurityEvent -EventType 'PermissionDenied' -UserId $User.UserId -Endpoint $Endpoint -IpAddress $ClientIP -Reason "Endpoint has no defined permissions (secure by default)."
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ error = "Access denied" }
                }
            }
            
            if ($RequiredPermissions.Count -gt 0) {
                $HasPermission = Test-ContextAwarePermission -User $User -RequiredPermissions $RequiredPermissions -UserId $UserId
                Write-Information "[Entrypoint] Test-ContextAwarePermission result: $HasPermission"
                if (-not $HasPermission) {
                    # Log permission denied attempt
                    $ClientIP = Get-ClientIPAddress -Request $Request
                    $userContext = if ($UserId) { "UserId=$UserId" } else { "Global" }
                    Write-SecurityEvent -EventType 'PermissionDenied' -UserId $User.UserId -Endpoint $Endpoint -IpAddress $ClientIP -RequiredPermissions ($RequiredPermissions -join ', ') -UserPermissions ($User.Permissions -join ', ') -Context $userContext -Reason "User attempted to access endpoint without required permissions."
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body = @{ error = "Forbidden: Insufficient permissions" }
                    }
                }
            }

            # Set context properties for downstream handlers
            # Set context-aware properties for downstream handlers using Add-Member
            if ($UserId) {
                $Request | Add-Member -NotePropertyName 'UserId' -NotePropertyValue $UserId -Force
                $Request | Add-Member -NotePropertyName 'ContextUserId' -NotePropertyValue $UserId -Force
            }

            # Add authenticated user to request
            $Request | Add-Member -MemberType NoteProperty -Name 'AuthenticatedUser' -Value $User -Force
            write-Information "Authenticated user: $($User.UserId) with roles: $($User.Roles -join ', ')"
        }

        # Invoke the function dynamically
        Write-Information "Invoking function: $FunctionName"
        $HttpTrigger = @{
            Request         = $Request
            TriggerMetadata = $TriggerMetadata
        }
        
        $Response = & $FunctionName @HttpTrigger
        
        # Return response
        if ($Response.StatusCode) {
            return $Response
        } else {
            # Fallback if function doesn't return proper HttpResponseContext
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body = $Response
            }
        }
        
    } catch {
        Write-Warning "Exception occurred on HTTP trigger ($FunctionName): $($_.Exception.Message)"
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{ error = $_.Exception.Message }
        }
    }
}

Export-ModuleMember -Function @('Receive-LinkTomeHttpTrigger', 'New-LinkTomeCoreRequest')
