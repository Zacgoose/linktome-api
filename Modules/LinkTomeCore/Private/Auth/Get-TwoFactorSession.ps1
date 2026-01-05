function Get-TwoFactorSession {
    <#
    .SYNOPSIS
        Get a 2FA session by session ID
    .DESCRIPTION
        Retrieves a 2FA session from the TwoFactorSessions table
    .PARAMETER SessionId
        The session ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'TwoFactorSessions'
        
        $SafeSessionId = Protect-TableQueryValue -Value $SessionId
        $Session = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeSessionId'" | Select-Object -First 1
        
        if (-not $Session) {
            return $null
        }
        
        # Check if session has expired
        $Now = (Get-Date).ToUniversalTime()
        if ($Session.ExpiresAt -lt $Now) {
            return $null
        }
        
        return $Session
    }
    catch {
        Write-Error "Failed to get 2FA session: $($_.Exception.Message)"
        return $null
    }
}
