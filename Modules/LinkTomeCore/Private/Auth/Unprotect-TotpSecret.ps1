function Unprotect-TotpSecret {
    <#
    .SYNOPSIS
        Decrypt a TOTP secret
    .DESCRIPTION
        Decrypts a TOTP secret using AES-256 decryption with a key from environment
    .PARAMETER EncryptedText
        The encrypted TOTP secret (Base64 encoded)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncryptedText
    )
    
    try {
        # Get encryption key from environment variable
        $EncryptionKey = $env:ENCRYPTION_KEY
        
        if (-not $EncryptionKey) {
            Write-Error "ENCRYPTION_KEY environment variable not set"
            throw "Encryption key not configured"
        }
        
        # Ensure key is 32 bytes (256 bits) for AES-256
        $KeyBytes = [System.Text.Encoding]::UTF8.GetBytes($EncryptionKey.PadRight(32).Substring(0, 32))
        
        # Decode from Base64
        $EncryptedData = [Convert]::FromBase64String($EncryptedText)
        
        # Create AES decryption object
        $Aes = [System.Security.Cryptography.Aes]::Create()
        try {
            $Aes.Key = $KeyBytes
            $Aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $Aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            
            # Extract IV (first 16 bytes) and encrypted data
            $IV = $EncryptedData[0..15]
            $CipherBytes = $EncryptedData[16..($EncryptedData.Length - 1)]
            $Aes.IV = $IV
            
            # Decrypt the data
            $Decryptor = $Aes.CreateDecryptor()
            try {
                $DecryptedBytes = $Decryptor.TransformFinalBlock($CipherBytes, 0, $CipherBytes.Length)
                
                # Return as string
                return [System.Text.Encoding]::UTF8.GetString($DecryptedBytes)
            }
            finally {
                $Decryptor.Dispose()
            }
        }
        finally {
            $Aes.Dispose()
        }
    }
    catch {
        Write-Error "Failed to decrypt TOTP secret: $($_.Exception.Message)"
        throw
    }
}
