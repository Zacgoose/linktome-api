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
    
    # Base64URL encode to avoid Azure Table Storage PartitionKey invalid characters (+, /, =)
    $Token = [Convert]::ToBase64String($TokenBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    
    return $Token
}
