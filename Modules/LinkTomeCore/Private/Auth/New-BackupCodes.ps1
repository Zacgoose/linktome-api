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
        
        for ($i = 0; $i -lt $Count; $i++) {
            # Generate 8-character code directly from random selection
            $Code = ""
            $Bytes = New-Object byte[] 8
            $Random.GetBytes($Bytes)
            
            foreach ($Byte in $Bytes) {
                # Map byte to character index
                $Index = $Byte % $Chars.Length
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
