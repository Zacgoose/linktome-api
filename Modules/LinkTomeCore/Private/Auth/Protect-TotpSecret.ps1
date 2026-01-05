function Protect-TotpSecret {
    <#
    .SYNOPSIS
        Encrypt a TOTP secret
    .DESCRIPTION
        Encrypts a TOTP secret using AES-256 encryption with a key from environment
    .PARAMETER PlainText
        The plain text TOTP secret to encrypt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PlainText
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
        
        # Create AES encryption object
        $Aes = [System.Security.Cryptography.Aes]::Create()
        try {
            $Aes.Key = $KeyBytes
            $Aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $Aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $Aes.GenerateIV()
            
            # Encrypt the data
            $Encryptor = $Aes.CreateEncryptor()
            try {
                $PlainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
                $EncryptedBytes = $Encryptor.TransformFinalBlock($PlainBytes, 0, $PlainBytes.Length)
                
                # Combine IV and encrypted data
                $Result = $Aes.IV + $EncryptedBytes
                
                # Return as Base64 string
                return [Convert]::ToBase64String($Result)
            }
            finally {
                $Encryptor.Dispose()
            }
        }
        finally {
            $Aes.Dispose()
        }
    }
    catch {
        Write-Error "Failed to encrypt TOTP secret: $($_.Exception.Message)"
        throw
    }
}
