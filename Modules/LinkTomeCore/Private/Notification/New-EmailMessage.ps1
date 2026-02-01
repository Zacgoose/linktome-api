function New-EmailMessage {
    <#
    .SYNOPSIS
        Create a new email message object with specified parameters and send using Send-MailMessage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$To,

        [Parameter(Mandatory)]
        [ValidateSet('2FA','PasswordReset','Notification','PasswordResetConfirm')]
        [string]$Template,

        [Parameter()]
        [hashtable]$TemplateParams
    )

    # Define templates
    $templates = @{
        '2FA' = @{
            Subject = 'Your 2FA Code'
            Body    = "Hello,`n`nYour two-factor authentication code is: {Code}`n`nIf you did not request this, please ignore this email."
        }
        'PasswordReset' = @{
            Subject = 'Password Reset Code'
            Body    = "Hello,`n`nYour password reset code is: {ResetCode}`n`nThis code will expire in 1 hour. If you did not request this, please ignore this email."
        }
        'Notification' = @{
            Subject = 'Notification from LinkToMe'
            Body    = "Hello,`n`n{Message}`n`nThank you,`nLinkToMe Team"
        }
        'PasswordResetConfirm' = @{
            Subject = 'Your LinkToMe Password Was Changed'
            Body    = "Hello,`n`nYour LinkToMe password was successfully changed. If you did not perform this action, please contact support immediately.`n`nThank you,`nLinkToMe Team"
        }
    }

    # Select template
    $selectedTemplate = $templates[$Template]
    $emailSubject = $selectedTemplate.Subject
    $emailBody = $selectedTemplate.Body

    # Replace placeholders with TemplateParams
    if ($TemplateParams) {
        foreach ($key in $TemplateParams.Keys) {
            $emailBody = $emailBody -replace "\{$key\}", [string]$TemplateParams[$key]
        }
    }

    # Pull SMTP config from environment variables
    $smtpServer   = $env:SMTP_SERVER
    $smtpPort     = $env:SMTP_PORT
    $smtpUser     = $env:SMTP_USERNAME
    $smtpPassword = $env:SMTP_PASSWORD
    $smtpFrom     = $env:SMTP_FROM

    if (-not $smtpServer -or -not $smtpPort -or -not $smtpUser -or -not $smtpPassword -or -not $smtpFrom) {
        throw "SMTP configuration environment variables are missing. Please set SMTP_SERVER, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, and SMTP_FROM."
    }

    $securePassword = ConvertTo-SecureString $smtpPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($smtpUser, $securePassword)

    Send-MailMessage -To $To -From $smtpFrom -Subject $emailSubject -Body $emailBody -BodyAsHtml:$false -SmtpServer $smtpServer -Port $smtpPort -Credential $credential -UseSsl
}