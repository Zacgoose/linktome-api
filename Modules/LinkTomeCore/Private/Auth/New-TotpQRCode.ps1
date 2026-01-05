function New-TotpQRCode {
    <#
    .SYNOPSIS
        Generate a TOTP QR code data URI
    .DESCRIPTION
        Generates a QR code data URI for TOTP setup in authenticator apps
    .PARAMETER Secret
        The BASE32-encoded TOTP secret
    .PARAMETER Issuer
        The issuer name (e.g., "LinkToMe")
    .PARAMETER AccountName
        The account name (usually email or username)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Secret,
        
        [Parameter(Mandatory = $false)]
        [string]$Issuer = "LinkToMe",
        
        [Parameter(Mandatory = $true)]
        [string]$AccountName
    )
    
    try {
        # URL-encode the parameters (using built-in Uri escape)
        $EncodedIssuer = [System.Uri]::EscapeDataString($Issuer)
        $EncodedAccount = [System.Uri]::EscapeDataString($AccountName)
        
        # Build TOTP URI according to RFC 6238
        # Format: otpauth://totp/ISSUER:ACCOUNT?secret=SECRET&issuer=ISSUER
        $OtpUri = "otpauth://totp/${EncodedIssuer}:${EncodedAccount}?secret=${Secret}&issuer=${EncodedIssuer}"
        
        # Return URI data that frontend can use to generate QR code
        # Frontend can use libraries like 'qrcode' (npm) to convert URI to QR image
        # Example: QRCode.toDataURL(uri) in JavaScript
        
        return @{
            uri = $OtpUri
            secret = $Secret
            issuer = $Issuer
            accountName = $AccountName
        }
    }
    catch {
        Write-Error "Failed to generate TOTP QR code: $($_.Exception.Message)"
        throw
    }
}
