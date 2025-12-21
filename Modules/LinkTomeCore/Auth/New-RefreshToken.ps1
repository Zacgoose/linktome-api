function New-RefreshToken {
    <#
    .SYNOPSIS
        Generate a new refresh token
    .DESCRIPTION
        Creates a secure random refresh token string
    #>
    
    # Generate a secure random token
    $TokenBytes = New-Object byte[] 64
    $RNG = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $RNG.GetBytes($TokenBytes)
    $RNG.Dispose()
    
    $Token = [Convert]::ToBase64String($TokenBytes)
    
    return $Token
}
