function New-TwoFactorCode {
    <#
    .SYNOPSIS
        Generate a 6-digit 2FA code
    .DESCRIPTION
        Generates a cryptographically secure 6-digit code for 2FA email verification
    #>
    [CmdletBinding()]
    param()
    
    # Generate a random 6-digit code using cryptographically secure random
    $Random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $Bytes = New-Object byte[] 4
    $Random.GetBytes($Bytes)
    $Number = [System.BitConverter]::ToUInt32($Bytes, 0)
    
    # Convert to 6-digit code (000000-999999)
    $Code = ($Number % 1000000).ToString('D6')
    
    return $Code
}
