function Test-SlugFormat {
    <#
    .SYNOPSIS
        Validate slug format for pages
    .DESCRIPTION
        Validates that a slug meets requirements:
        - 3-30 characters
        - Lowercase letters, numbers, hyphens only
        - Cannot start/end with hyphen
        - Cannot contain consecutive hyphens
        - Not a reserved slug
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Slug
    )
    
    # Reserved slugs
    $ReservedSlugs = @('admin', 'api', 'public', 'login', 'signup', 'settings', 'v1')
    
    # Check if reserved
    if ($Slug.ToLower() -in $ReservedSlugs) {
        return $false
    }
    
    # Check length
    if ($Slug.Length -lt 3 -or $Slug.Length -gt 30) {
        return $false
    }
    
    # Check format: lowercase letters, numbers, hyphens only
    if ($Slug -notmatch '^[a-z0-9-]+$') {
        return $false
    }
    
    # Cannot start/end with hyphen
    if ($Slug.StartsWith('-') -or $Slug.EndsWith('-')) {
        return $false
    }
    
    # Cannot contain consecutive hyphens
    if ($Slug -match '--') {
        return $false
    }
    
    return $true
}
