function Test-UsernameFormat {
    <#
    .SYNOPSIS
        Validate username format
    .DESCRIPTION
        Validates that a username contains only allowed characters and is within length limits
    .PARAMETER Username
        The username to validate
    .EXAMPLE
        Test-UsernameFormat -Username "john_doe"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Username
    )
    
    # Username requirements:
    # - 3-30 characters
    # - Alphanumeric, underscore, hyphen only
    # - Must start with alphanumeric
    $UsernameRegex = '^[a-zA-Z0-9][a-zA-Z0-9_-]{2,29}$'
    
    return $Username -match $UsernameRegex
}
