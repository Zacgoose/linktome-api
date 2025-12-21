function Test-UrlFormat {
    <#
    .SYNOPSIS
        Validate URL format
    .DESCRIPTION
        Validates that a URL uses http/https protocol and follows proper format.
        Prevents javascript:, data:, and other potentially dangerous protocols.
    .PARAMETER Url
        The URL to validate
    .EXAMPLE
        Test-UrlFormat -Url "https://example.com/page"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url
    )
    
    # Check length (RFC 2616 recommends 2048 max)
    if ($Url.Length -gt 2048 -or $Url.Length -eq 0) {
        return $false
    }
    
    # Only allow http and https protocols
    # Must have protocol, domain, and TLD
    $UrlRegex = '^https?:\/\/[a-zA-Z0-9][-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b[-a-zA-Z0-9()@:%_\+.~#?&\/=]*$'
    
    return $Url -match $UrlRegex
}
