function Test-PasswordHash {
    <#
    .SYNOPSIS
        Verify a password against stored hash and salt
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Password,
        
        [Parameter(Mandatory)]
        [string]$StoredHash,
        
        [Parameter(Mandatory)]
        [string]$StoredSalt
    )
    
    $SaltBytes = [Convert]::FromBase64String($StoredSalt)
    
    $Pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $Password,
        $SaltBytes,
        100000,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    
    $ComputedHash = [Convert]::ToBase64String($Pbkdf2.GetBytes(32))
    
    return $ComputedHash -eq $StoredHash
}