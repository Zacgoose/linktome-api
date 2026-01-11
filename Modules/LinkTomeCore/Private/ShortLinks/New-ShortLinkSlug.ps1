function New-ShortLinkSlug {
    <#
    .SYNOPSIS
        Generate a unique random slug for a short link
    .DESCRIPTION
        Generates a random 6-character slug using lowercase letters and numbers (a-z, 0-9).
        Checks for uniqueness and retries if collision occurs.
        With 36^6 = 2.18 billion combinations, collisions are rare.
    .PARAMETER MaxRetries
        Maximum number of retry attempts if slug already exists (default: 10)
    #>
    [CmdletBinding()]
    param(
        [int]$MaxRetries = 10
    )
    
    $Characters = 'abcdefghijklmnopqrstuvwxyz0123456789'
    $SlugLength = 6
    $Table = Get-LinkToMeTable -TableName 'ShortLinks'
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        # Generate random 6-character slug
        $Slug = -join (1..$SlugLength | ForEach-Object { $Characters[(Get-Random -Minimum 0 -Maximum $Characters.Length)] })
        
        # Check if slug already exists
        $SafeSlug = Protect-TableQueryValue -Value $Slug
        $ExistingSlug = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeSlug'" | Select-Object -First 1
        
        if (-not $ExistingSlug) {
            return $Slug
        }
        
        Write-Debug "Slug collision detected: $Slug (attempt $attempt/$MaxRetries)"
    }
    
    # If we couldn't find a unique slug after max retries, throw error
    throw "Failed to generate unique slug after $MaxRetries attempts"
}
