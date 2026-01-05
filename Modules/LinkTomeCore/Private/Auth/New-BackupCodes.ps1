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
        for ($i = 0; $i -lt $Count; $i++) {
            # Generate 8 random bytes
            $Bytes = New-Object byte[] 8
            $Random.GetBytes($Bytes)
            
            # Convert to alphanumeric code (8 characters)
            $Code = [Convert]::ToBase64String($Bytes) -replace '[^a-zA-Z0-9]', ''
            $Code = $Code.Substring(0, 8).ToUpper()
            
            $Codes += $Code
        }
        
        return $Codes
    }
    finally {
        $Random.Dispose()
    }
}
