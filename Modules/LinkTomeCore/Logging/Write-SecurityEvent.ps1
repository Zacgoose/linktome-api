function Write-SecurityEvent {
    <#
    .SYNOPSIS
        Log security events for monitoring and auditing
    .DESCRIPTION
        Logs security events to Azure Table Storage for auditing
    .PARAMETER EventType
        Type of security event (e.g., 'LoginSuccess', 'LoginFailed', 'TokenRefreshed', 'RoleAssigned'). Accepts any string to allow flexibility for future event types.
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
    .EXAMPLE
        Write-SecurityEvent -EventType 'LoginSuccess' -UserId $User.UserId -Email $User.Email -IpAddress $ClientIP
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventType,
        
        [string]$UserId = 'unknown',
        
        [string]$Email,
        
        [string]$Username,
        
        [string]$IpAddress,
        
        [string]$Endpoint,

        [object]$Metadata
    )
    
    try {
        # Redact email for privacy (keep first 3 chars and domain)
        $RedactedEmail = ''
        if ($Email) {
            $EmailParts = $Email -split '@'
            if ($EmailParts.Count -eq 2) {
                $LocalPart = $EmailParts[0]
                $PrefixLength = [Math]::Min(3, $LocalPart.Length)
                $RedactedEmail = $LocalPart.Substring(0, $PrefixLength) + '***@' + $EmailParts[1]
            } else {
                $RedactedEmail = '***'
            }
        }
        
        # Store all security events in Azure Table Storage for auditing
        try {
            $Table = Get-LinkToMeTable -TableName 'SecurityEvents'
            $EventRecord = @{
                PartitionKey   = $EventType
                RowKey         = [DateTimeOffset]::UtcNow.Ticks.ToString() + '-' + (New-Guid).ToString().Substring(0, 8)
                EventTimestamp = [DateTimeOffset]::UtcNow
                UserId         = $UserId
                Email          = $RedactedEmail
                Username       = $Username
                IpAddress      = $IpAddress
                Endpoint       = $Endpoint
            }

            if ($Metadata) {
                $EventRecord['Metadata'] = $Metadata | ConvertTo-Json -Depth 10 -Compress
            }

            Add-LinkToMeAzDataTableEntity @Table -Entity $EventRecord -Force | Out-Null
        } catch {
            Write-Warning "Failed to store security event in table storage: $($_.Exception.Message)"
        }
        
    } catch {
        Write-Warning "Failed to log security event: $($_.Exception.Message)"
    }
}
