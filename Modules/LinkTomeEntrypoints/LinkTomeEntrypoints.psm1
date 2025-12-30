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

Export-ModuleMember -Function @('Receive-LinkTomeHttpTrigger', 'New-LinkTomeCoreRequest')
