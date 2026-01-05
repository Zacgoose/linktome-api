function Remove-TwoFactorSession {
    <#
    .SYNOPSIS
        Remove a 2FA session
    .DESCRIPTION
        Removes a 2FA session from the TwoFactorSessions table
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
        
        if ($Session) {
            Remove-AzDataTableEntity -Entity $Session -Context $Table.Context
        }
    }
    catch {
        Write-Error "Failed to remove 2FA session: $($_.Exception.Message)"
    }
}
