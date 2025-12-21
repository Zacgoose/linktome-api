function Test-EmailFormat {
    <#
    .SYNOPSIS
        Validate email format
    .DESCRIPTION
        Validates that an email address follows a proper format and is within acceptable length
    .PARAMETER Email
        The email address to validate
    .EXAMPLE
        Test-EmailFormat -Email "user@example.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Email
    )
    
    # Check length (RFC 5321 max is 254)
    if ($Email.Length -gt 254 -or $Email.Length -eq 0) {
        return $false
    }
    
    # Basic email regex validation
    # Matches: local-part@domain.tld
    $EmailRegex = '^[\w\.\-\+]+@[\w\.\-]+\.\w{2,}$'
    
    return $Email -match $EmailRegex
}
