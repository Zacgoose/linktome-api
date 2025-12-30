function Test-ApiKeyContextPermission {
    <#
    .SYNOPSIS
        Checks if an API key has required permissions, including context-aware checks
    .DESCRIPTION
        For API key requests:
        - If no UserId context: API key must have the required permissions
        - If UserId context: API key must have permission AND user management must have permission
    .PARAMETER ApiKeyResult
        The result from Get-ApiKeyFromRequest
    .PARAMETER RequiredPermissions
        Array of required permissions
    .PARAMETER ContextUserId
        Optional UserId to check context-aware permissions for
    .OUTPUTS
        Hashtable with Allowed (bool) and Reason (string if denied)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ApiKeyResult,
        
        [Parameter(Mandatory)]
        [string[]]$RequiredPermissions,
        
        [Parameter()]
        [string]$ContextUserId
    )
    
    $KeyPermissions = $ApiKeyResult.KeyPermissions
    
    # First: Check API key has required permissions
    foreach ($Permission in $RequiredPermissions) {
        if ($Permission -notin $KeyPermissions) {
            Write-Warning "[ApiAuth] API key missing permission: $Permission"
            return @{
                Allowed = $false
                Reason  = "API key lacks permission: $Permission"
            }
        }
    }
    
    # If no context UserId, we're done
    if (-not $ContextUserId) {
        Write-Verbose "[ApiAuth] No context UserId, API key permissions sufficient"
        return @{ Allowed = $true }
    }
    
    # If ContextUserId is the key owner, allow (operating on own data)
    if ($ContextUserId -eq $ApiKeyResult.UserId) {
        Write-Verbose "[ApiAuth] ContextUserId matches key owner, allowed"
        return @{ Allowed = $true }
    }
    
    # Context UserId provided - check user management relationship
    Write-Verbose "[ApiAuth] Checking user management context for UserId: $ContextUserId"
    
    $UserManagements = $ApiKeyResult.UserManagements
    if (-not $UserManagements -or $UserManagements.Count -eq 0) {
        Write-Warning "[ApiAuth] No user managements found"
        return @{
            Allowed = $false
            Reason  = "No management relationship with user: $ContextUserId"
        }
    }
    
    # Find the management relationship
    $Management = $UserManagements | Where-Object { $_.UserId -eq $ContextUserId } | Select-Object -First 1
    
    if (-not $Management) {
        Write-Warning "[ApiAuth] No management relationship found for UserId: $ContextUserId"
        return @{
            Allowed = $false
            Reason  = "No management relationship with user: $ContextUserId"
        }
    }
    
    # Check management has required permissions
    $MgmtPermissions = $Management.permissions
    if ($MgmtPermissions -is [string]) {
        $MgmtPermissions = $MgmtPermissions -split ' '
    }
    
    foreach ($Permission in $RequiredPermissions) {
        # API key already checked above, now check management
        if ($Permission -notin $MgmtPermissions) {
            Write-Warning "[ApiAuth] Management relationship missing permission: $Permission"
            return @{
                Allowed = $false
                Reason  = "Management relationship lacks permission: $Permission for user $ContextUserId"
            }
        }
    }
    
    Write-Verbose "[ApiAuth] All permissions validated for context user $ContextUserId"
    return @{ Allowed = $true }
}