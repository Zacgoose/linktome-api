function Write-SecurityEvent {
    <#
    .SYNOPSIS
        Log security events for monitoring and auditing
    .DESCRIPTION
        Logs security events to Application Insights and Azure Table Storage for auditing
    .PARAMETER EventType
        Type of security event (e.g., 'LoginSuccess', 'LoginFailed', 'SignupSuccess', 'SignupFailed', 'AuthFailed', 'RateLimitExceeded')
    .PARAMETER UserId
        User ID if available (may be 'unknown' for failed auth)
    .PARAMETER Email
        Email address (partially redacted for privacy)
    .PARAMETER Username
        Username if available
    .PARAMETER IpAddress
        Client IP address
    .PARAMETER Endpoint
        The endpoint being accessed
    .PARAMETER Metadata
        Additional metadata as hashtable
    .EXAMPLE
        Write-SecurityEvent -EventType 'LoginSuccess' -UserId $User.UserId -Email $User.Email -IpAddress $ClientIP
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('LoginSuccess', 'LoginFailed', 'SignupSuccess', 'SignupFailed', 'AuthFailed', 'RateLimitExceeded', 'TokenValidationFailed', 'InputValidationFailed')]
        [string]$EventType,
        
        [string]$UserId = 'unknown',
        
        [string]$Email,
        
        [string]$Username,
        
        [string]$IpAddress,
        
        [string]$Endpoint,
        
        [hashtable]$Metadata = @{}
    )
    
    try {
        # Redact email for privacy (keep first 3 chars and domain)
        $RedactedEmail = ''
        if ($Email) {
            if ($Email.Length -gt 3) {
                $EmailParts = $Email -split '@'
                if ($EmailParts.Count -eq 2) {
                    $RedactedEmail = $EmailParts[0].Substring(0, [Math]::Min(3, $EmailParts[0].Length)) + '***@' + $EmailParts[1]
                } else {
                    $RedactedEmail = $Email.Substring(0, 3) + '***'
                }
            } else {
                $RedactedEmail = '***'
            }
        }
        
        # Create structured log event
        $Event = @{
            Timestamp = [DateTime]::UtcNow.ToString('o')
            EventType = $EventType
            UserId = $UserId
            Email = $RedactedEmail
            Username = $Username
            IpAddress = $IpAddress
            Endpoint = $Endpoint
            Metadata = $Metadata
        }
        
        # Log to Information stream (will appear in Application Insights)
        $EventJson = $Event | ConvertTo-Json -Compress
        Write-Information "SECURITY_EVENT: $EventJson"
        
        # Also store critical events in Azure Table Storage for auditing
        if ($EventType -in @('LoginFailed', 'SignupFailed', 'AuthFailed', 'RateLimitExceeded', 'TokenValidationFailed')) {
            try {
                $Table = Get-LinkToMeTable -TableName 'SecurityEvents'
                
                $EventRecord = @{
                    PartitionKey = $EventType
                    RowKey = [DateTime]::UtcNow.Ticks.ToString() + '-' + (New-Guid).ToString().Substring(0, 8)
                    Timestamp = [DateTime]::UtcNow
                    UserId = $UserId
                    Email = $RedactedEmail
                    Username = $Username
                    IpAddress = $IpAddress
                    Endpoint = $Endpoint
                    MetadataJson = ($Metadata | ConvertTo-Json -Compress)
                }
                
                Add-AzDataTableEntity @Table -Entity $EventRecord -Force | Out-Null
            } catch {
                Write-Warning "Failed to store security event in table storage: $($_.Exception.Message)"
            }
        }
        
    } catch {
        Write-Warning "Failed to log security event: $($_.Exception.Message)"
    }
}
