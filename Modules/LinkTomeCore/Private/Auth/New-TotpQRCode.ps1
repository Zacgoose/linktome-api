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
        # URL-encode the parameters
        $EncodedIssuer = [System.Web.HttpUtility]::UrlEncode($Issuer)
        $EncodedAccount = [System.Web.HttpUtility]::UrlEncode($AccountName)
        
        # Build TOTP URI according to RFC 6238
        # Format: otpauth://totp/ISSUER:ACCOUNT?secret=SECRET&issuer=ISSUER
        $OtpUri = "otpauth://totp/${EncodedIssuer}:${EncodedAccount}?secret=${Secret}&issuer=${EncodedIssuer}"
        
        # Generate QR code using a simple ASCII art approach for PowerShell
        # For production, you'd want to use a proper QR code library or generate on frontend
        # This returns the URI that the frontend can use to generate the QR code
        
        return @{
            uri = $OtpUri
            secret = $Secret
            issuer = $Issuer
            accountName = $AccountName
            # Frontend can use libraries like 'qrcode' (npm) to generate the actual QR image
            # Example: QRCode.toDataURL(uri) in JavaScript
        }
    }
    catch {
        Write-Error "Failed to generate TOTP QR code: $($_.Exception.Message)"
        throw
    }
}
