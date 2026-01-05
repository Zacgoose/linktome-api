function Test-TotpToken {
    <#
    .SYNOPSIS
        Verify a TOTP token
    .DESCRIPTION
        Verifies a TOTP token against a secret key using RFC 6238 algorithm
    .PARAMETER Token
        The 6-digit TOTP token to verify
    .PARAMETER Secret
        The BASE32-encoded secret key
    .PARAMETER TimeWindow
        Number of 30-second windows to check before and after current time (default: 1)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,
        
        [Parameter(Mandatory = $true)]
        [string]$Secret,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeWindow = 1
    )
    
    try {
        # Decode BASE32 secret
        $Base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        $SecretUpper = $Secret.ToUpper() -replace '[^A-Z2-7]', ''
        
        $BitBuffer = 0
        $BitsInBuffer = 0
        $Result = @()
        
        foreach ($Char in $SecretUpper.ToCharArray()) {
            $Index = $Base32Chars.IndexOf($Char)
            if ($Index -lt 0) { continue }
            
            $BitBuffer = ($BitBuffer -shl 5) -bor $Index
            $BitsInBuffer += 5
            
            if ($BitsInBuffer -ge 8) {
                $Result += ($BitBuffer -shr ($BitsInBuffer - 8)) -band 0xFF
                $BitsInBuffer -= 8
            }
        }
        
        $SecretBytes = [byte[]]$Result
        
        # Get current Unix time in 30-second intervals
        $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
        $UnixTime = [int]((Get-Date).ToUniversalTime() - $Epoch).TotalSeconds
        $TimeStep = [Math]::Floor($UnixTime / 30)
        
        # Check current time and ±TimeWindow
        Write-Information "Testing TOTP: TimeStep=$TimeStep, Window=±$TimeWindow, Token=$Token"
        
        $Hmac = New-Object System.Security.Cryptography.HMACSHA1
        try {
            $Hmac.Key = $SecretBytes
            
            for ($i = -$TimeWindow; $i -le $TimeWindow; $i++) {
                $Counter = $TimeStep + $i
                
                # Convert counter to 8-byte array (big-endian)
                $CounterBytes = [byte[]]::new(8)
                $CounterValue = $Counter  # Use a copy to avoid modifying $Counter
                for ($j = 7; $j -ge 0; $j--) {
                    $CounterBytes[$j] = $CounterValue -band 0xFF
                    $CounterValue = $CounterValue -shr 8
                }
                
                # HMAC-SHA1
                $Hash = $Hmac.ComputeHash($CounterBytes)
                
                # Dynamic truncation
                $Offset = $Hash[$Hash.Length - 1] -band 0x0F
                $Code = (($Hash[$Offset] -band 0x7F) -shl 24) -bor `
                        ($Hash[$Offset + 1] -shl 16) -bor `
                        ($Hash[$Offset + 2] -shl 8) -bor `
                        $Hash[$Offset + 3]
                
                # Generate 6-digit code
                $Otp = ($Code % 1000000).ToString('D6')
                
                Write-Information "  Window $i (counter=$Counter): Generated OTP=$Otp"
                
                if ($Otp -eq $Token) {
                    Write-Information "  Match found at window $i!"
                    return $true
                }
            }
            
            Write-Warning "No TOTP match found in any time window"
        }
        finally {
            $Hmac.Dispose()
        }
        
        return $false
    }
    catch {
        Write-Error "TOTP verification failed: $($_.Exception.Message)"
        return $false
    }
}
