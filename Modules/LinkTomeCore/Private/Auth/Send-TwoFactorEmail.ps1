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
        # Get SMTP configuration from environment variables
        $SmtpServer = $env:SMTP_SERVER
        $SmtpPort = $env:SMTP_PORT
        $SmtpUsername = $env:SMTP_USERNAME
        $SmtpPassword = $env:SMTP_PASSWORD
        $SmtpFrom = $env:SMTP_FROM
        
        if (-not $SmtpServer -or -not $SmtpPort -or -not $SmtpUsername -or -not $SmtpPassword -or -not $SmtpFrom) {
            Write-Error "SMTP configuration missing. Required: SMTP_SERVER, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM"
            return $false
        }
        
        # Create email message
        $Subject = "Your LinkToMe Verification Code"
        $Body = @"
Hello,

Your verification code is: $Code

This code will expire in 10 minutes.

If you didn't request this code, please ignore this email.

Best regards,
LinkToMe Team
"@
        
        # Create secure password
        $SecurePassword = ConvertTo-SecureString $SmtpPassword -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($SmtpUsername, $SecurePassword)
        
        # Send email
        $MailParams = @{
            SmtpServer = $SmtpServer
            Port = [int]$SmtpPort
            UseSsl = $true
            Credential = $Credential
            From = $SmtpFrom
            To = $Email
            Subject = $Subject
            Body = $Body
            Encoding = [System.Text.Encoding]::UTF8
        }
        
        Send-MailMessage @MailParams
        
        Write-Information "2FA email sent to $Email"
        return $true
    }
    catch {
        Write-Error "Failed to send 2FA email: $($_.Exception.Message)"
        return $false
    }
}
