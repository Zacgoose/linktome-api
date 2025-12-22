function Test-UserRole {
    <#
    .SYNOPSIS
        Check if user has required role
    .DESCRIPTION
        Validates that a user has at least one of the required roles from their JWT token claims
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,
        
        [Parameter(Mandatory)]
        [string[]]$RequiredRoles
    )
    
    # Extract roles from user object
    $UserRoles = $User.Roles
    
    if (-not $UserRoles -or $UserRoles.Count -eq 0) {
        return $false
    }
    
    # Check if user has any of the required roles
    foreach ($Role in $RequiredRoles) {
        if ($UserRoles -contains $Role) {
            return $true
        }
    }
    
    return $false
}
