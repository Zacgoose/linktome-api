function Get-UserFromRequest {
    <#
    .SYNOPSIS
        Extract and validate user from request cookie
    .DESCRIPTION
        Reads accessToken from HTTP-only cookie
    #>
    param(
        [Parameter(Mandatory)]
        $Request
    )
    
    # Get token from cookie
    $Token = $Request.Cookies.accessToken
    
    if (-not $Token) {
        return $null
    }
    
    # Validate JWT token
    $User = Test-LinkTomeJWT -Token $Token
    
    return $User
}