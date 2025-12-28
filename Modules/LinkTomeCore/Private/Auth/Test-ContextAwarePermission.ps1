function Test-ContextAwarePermission {
    <#
    .SYNOPSIS
        Checks if a user has the required permissions, using JWT/global permissions first, then user context if UserId is present.
    .DESCRIPTION
        Always checks JWT/global permissions. If a UserId is provided, checks user management context permissions.
    .PARAMETER User
        The authenticated user object (from JWT).
    .PARAMETER RequiredPermissions
        Array of required permissions for the endpoint.
    .PARAMETER UserId
        (Optional) The UserId context to check for user-to-user management. If not provided, only checks global permissions.
    .OUTPUTS
        [bool] True if the user has all required permissions, otherwise false.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,
        [Parameter(Mandatory)]
        [string[]]$RequiredPermissions,
        [string]$CompanyId,
        [string]$UserId
    )

    if ($UserId) {
        Write-Verbose "[Auth] Checking user management context permissions for UserId: $UserId"
        $userManagements = $User.userManagements
        if (-not $userManagements) {
            Write-Warning "[Auth] No userManagements found for user."
            return $false
        }
        $management = $userManagements | Where-Object { $_.UserId -eq $UserId } | Select-Object -First 1
        if (-not $management) {
            Write-Warning "[Auth] No management found for UserId: $UserId"
            return $false
        }
        $userPermissions = $management.permissions
        if ($userPermissions -is [string]) {
            $userPermissions = $userPermissions -split ' '
        }
        Write-Verbose "[Auth] RequiredPermissions: $($RequiredPermissions -join ', ')"
        Write-Verbose "[Auth] User's userPermissions: $($userPermissions -join ', ')"
        foreach ($Permission in $RequiredPermissions) {
            if ($userPermissions -notcontains $Permission) {
                Write-Warning "[Auth] Missing user management permission: $Permission"
                return $false
            }
        }
        Write-Verbose "[Auth] All required user management permissions present."
        return $true
    }

    # Only check global permissions if no UserId
    Write-Verbose "[Auth] Checking global permissions."
    $UserPermissions = $User.Permissions
    if (-not $UserPermissions -or $UserPermissions.Count -eq 0) {
        Write-Warning "[Auth] No global permissions found for user."
        return $false
    }
    Write-Verbose "[Auth] RequiredPermissions: $($RequiredPermissions -join ', ')"
    Write-Verbose "[Auth] User's global permissions: $($UserPermissions -join ', ')"
    foreach ($Permission in $RequiredPermissions) {
        if ($UserPermissions -notcontains $Permission) {
            Write-Warning "[Auth] Missing global permission: $Permission"
            return $false
        }
    }
    Write-Verbose "[Auth] All required global permissions present."
    return $true
}
