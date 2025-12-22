function New-PasswordHash {
    <#
    .SYNOPSIS
        Hash password using PBKDF2
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Password
    )
    
    # Generate salt
    $SaltBytes = [byte[]]::new(32)
    $RNG = [RandomNumberGenerator]::Create()
    $RNG.GetBytes($SaltBytes)
    $Salt = [Convert]::ToBase64String($SaltBytes)
    
    # Hash password
    $PBKDF2 = [Rfc2898DeriveBytes]::new($Password, $SaltBytes, 100000, [HashAlgorithmName]::SHA256)
    $HashBytes = $PBKDF2.GetBytes(32)
    $Hash = [Convert]::ToBase64String($HashBytes)
    
    return @{
        Hash = $Hash
        Salt = $Salt
    }
}