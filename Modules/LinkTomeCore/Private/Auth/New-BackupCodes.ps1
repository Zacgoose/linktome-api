function New-BackupCodes {
    <#
    .SYNOPSIS
        Generate backup codes for 2FA recovery
    .DESCRIPTION
        Generates a set of single-use backup codes for 2FA account recovery
    .PARAMETER Count
        Number of backup codes to generate (default: 10)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Count = 10
    )
    
    $Codes = @()
    $Random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    
    try {
        # Alphanumeric characters for codes (excluding ambiguous characters)
        $Chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Removed I, O, 0, 1 to avoid confusion
        $CharsLength = $Chars.Length
        $MaxByteValue = 256  # Maximum value for a byte (0-255)
        
        for ($i = 0; $i -lt $Count; $i++) {
            # Generate 8-character code with uniform distribution (rejection sampling)
            $Code = ""
            
            for ($j = 0; $j -lt 8; $j++) {
                # Use rejection sampling to avoid modulo bias
                $MaxValidValue = $MaxByteValue - ($MaxByteValue % $CharsLength)
                
                do {
                    $Bytes = New-Object byte[] 1
                    $Random.GetBytes($Bytes)
                    $Value = $Bytes[0]
                } while ($Value -ge $MaxValidValue)
                
                # Now we can safely use modulo
                $Index = $Value % $CharsLength
                $Code += $Chars[$Index]
            }
            
            $Codes += $Code
        }
        
        return $Codes
    }
    finally {
        $Random.Dispose()
    }
}
