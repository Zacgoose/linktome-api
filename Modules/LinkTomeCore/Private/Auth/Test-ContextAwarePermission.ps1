function Test-ContextAwarePermission {
    <#
    .SYNOPSIS
        Checks if a user has the required permissions, using JWT/global permissions first, then company context if companyId is present.
    .DESCRIPTION
        Always checks JWT/global permissions. If a companyId is provided, also checks company context permissions for each required permission.
    .PARAMETER User
        The authenticated user object (from JWT).
    .PARAMETER RequiredPermissions
        Array of required permissions for the endpoint.
    .PARAMETER CompanyId
        (Optional) The companyId context to check. If not provided, only checks global permissions.
    .OUTPUTS
        [bool] True if the user has all required permissions, otherwise false.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,
        [Parameter(Mandatory)]
        [string[]]$RequiredPermissions,
        [string]$CompanyId
    )

    Write-Information "[DEBUG] Test-ContextAwarePermission: CompanyId=$CompanyId, RequiredPermissions=$($RequiredPermissions -join ', ')"
    if ($CompanyId) {
        $companyMemberships = $User.companyMemberships
        Write-Information "[DEBUG] JWT companyMemberships: $($companyMemberships | ConvertTo-Json -Compress)"
        if (-not $companyMemberships) {
            Write-Information "[DEBUG] No companyMemberships found in JWT."
            return $false
        }
        $membership = $companyMemberships | Where-Object { $_.companyId -eq $CompanyId } | Select-Object -First 1
        if (-not $membership) {
            Write-Information "[DEBUG] No company membership found for companyId $CompanyId."
            return $false
        }
        $companyPermissions = $membership.permissions
        # Fix: If permissions is a string, split it into an array
        if ($companyPermissions -is [string]) {
            $companyPermissions = $companyPermissions -split ' '
        }
        Write-Information "[DEBUG] Company permissions for companyId $CompanyId : $($companyPermissions -join ', ')"
        foreach ($Permission in $RequiredPermissions) {
            if ($companyPermissions -notcontains $Permission) {
                Write-Information "[DEBUG] User missing company permission: $Permission"
                return $false
            }
        }
        Write-Information "[DEBUG] All required company permissions granted."
        return $true
    }
    # Only check global permissions if no companyId
    $UserPermissions = $User.Permissions
    Write-Information "[DEBUG] User global permissions: $($UserPermissions -join ', ')"
    if (-not $UserPermissions -or $UserPermissions.Count -eq 0) {
        Write-Information "[DEBUG] No global permissions found on user."
        return $false
    }
    foreach ($Permission in $RequiredPermissions) {
        if ($UserPermissions -notcontains $Permission) {
            Write-Information "[DEBUG] User missing global permission: $Permission"
            return $false
        }
    }
    Write-Information "[DEBUG] All required global permissions granted."
    return $true
}
