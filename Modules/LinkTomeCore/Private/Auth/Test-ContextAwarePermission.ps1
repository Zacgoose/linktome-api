function Test-ContextAwarePermission {
    <#
    .SYNOPSIS
        Checks if a user has the required permissions, using JWT/global permissions first, then company or user context if companyId or userId is present.
    .DESCRIPTION
        Always checks JWT/global permissions. If a companyId is provided, also checks company context permissions. If a userId is provided, checks user management context permissions.
    .PARAMETER User
        The authenticated user object (from JWT).
    .PARAMETER RequiredPermissions
        Array of required permissions for the endpoint.
    .PARAMETER CompanyId
        (Optional) The companyId context to check. If not provided, only checks global permissions.
    .PARAMETER UserId
        (Optional) The userId context to check for user-to-user management. If not provided, only checks global/company permissions.
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

    if ($CompanyId) {
        Write-Verbose "[Auth] Checking company context permissions for CompanyId: $CompanyId"
        $companyMemberships = $User.companyMemberships
        if (-not $companyMemberships) {
            Write-Warning "[Auth] No companyMemberships found for user."
            return $false
        }
        $membership = $companyMemberships | Where-Object { $_.companyId -eq $CompanyId } | Select-Object -First 1
        if (-not $membership) {
            Write-Warning "[Auth] No membership found for CompanyId: $CompanyId"
            return $false
        }
        $companyPermissions = $membership.permissions
        if ($companyPermissions -is [string]) {
            $companyPermissions = $companyPermissions -split ' '
        }
        Write-Verbose "[Auth] RequiredPermissions: $($RequiredPermissions -join ', ')"
        Write-Verbose "[Auth] User's companyPermissions: $($companyPermissions -join ', ')"
        foreach ($Permission in $RequiredPermissions) {
            if ($companyPermissions -notcontains $Permission) {
                Write-Warning "[Auth] Missing company permission: $Permission"
                return $false
            }
        }
        Write-Verbose "[Auth] All required company permissions present."
        return $true
    }

    if ($UserId) {
        Write-Verbose "[Auth] Checking user management context permissions for UserId: $UserId"
        $userManagements = $User.userManagements
        if (-not $userManagements) {
            Write-Warning "[Auth] No userManagements found for user."
            return $false
        }
        $management = $userManagements | Where-Object { $_.userId -eq $UserId } | Select-Object -First 1
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

    # Only check global permissions if no companyId or userId
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
