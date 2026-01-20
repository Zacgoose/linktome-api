function Send-TwoFactorEmail {
    <#
    .SYNOPSIS
        Send a 2FA email code
    .DESCRIPTION
        Sends a 2FA verification code via SMTP email
    .PARAMETER Email
        The recipient email address
    .PARAMETER Code
        The 6-digit verification code
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email,
        
        [Parameter(Mandatory = $true)]
        [string]$Code
    )
    
    try {
        # Use the New-EmailMessage helper for 2FA
        New-EmailMessage -To $Email -Template '2FA' -TemplateParams @{ Code = $Code }
        return $true
    }
    catch {
        Write-Error "Failed to send 2FA email: $($_.Exception.Message)"
        return $false
    }
}
