function New-TotpSecret {
    <#
    .SYNOPSIS
        Generate a new TOTP secret
    .DESCRIPTION
        Generates a new BASE32-encoded secret for TOTP authentication
    #>
    [CmdletBinding()]
    param()
    
    # Generate 20 random bytes (160 bits)
    $Random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $Bytes = New-Object byte[] 20
        $Random.GetBytes($Bytes)
        
        # Convert to BASE32 (RFC 4648)
        $Base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        $Result = ""
        
        $BitBuffer = 0
        $BitsInBuffer = 0
        
        foreach ($Byte in $Bytes) {
            $BitBuffer = ($BitBuffer -shl 8) -bor $Byte
            $BitsInBuffer += 8
            
            while ($BitsInBuffer -ge 5) {
                $Index = ($BitBuffer -shr ($BitsInBuffer - 5)) -band 0x1F
                $Result += $Base32Chars[$Index]
                $BitsInBuffer -= 5
            }
        }
        
        if ($BitsInBuffer -gt 0) {
            $Index = ($BitBuffer -shl (5 - $BitsInBuffer)) -band 0x1F
            $Result += $Base32Chars[$Index]
        }
        
        return $Result
    }
    finally {
        $Random.Dispose()
    }
}
