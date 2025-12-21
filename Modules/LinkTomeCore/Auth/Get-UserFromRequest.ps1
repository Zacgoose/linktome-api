function Get-UserFromRequest {
    <#
    .SYNOPSIS
        Extract and validate user from request Authorization header
    #>
    param(
        [Parameter(Mandatory)]
        $Request
    )
    
    $AuthHeader = $Request.Headers.Authorization
    
    if (-not $AuthHeader) {
        return $null
    }
    
    if ($AuthHeader -notmatch '^Bearer (.+)$') {
        return $null
    }
    
    $Token = $Matches[1]
    $User = Test-LinkTomeJWT -Token $Token
    
    return $User
}