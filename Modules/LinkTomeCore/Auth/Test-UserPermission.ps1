function Test-UserPermission {
    <#
    .SYNOPSIS
        Check if user has required permissions
    .DESCRIPTION
        Validates that a user has all required permissions from their JWT token claims
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,
        
        [Parameter(Mandatory)]
        [string[]]$RequiredPermissions
    )
    
    # Extract permissions from user object
    $UserPermissions = $User.Permissions
    
    if (-not $UserPermissions -or $UserPermissions.Count -eq 0) {
        return $false
    }
    
    # Check if user has all required permissions
    foreach ($Permission in $RequiredPermissions) {
        if ($UserPermissions -notcontains $Permission) {
            return $false
        }
    }
    
    return $true
}
