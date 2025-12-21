function Get-RefreshToken {
    <#
    .SYNOPSIS
        Retrieve refresh token from Azure Table Storage
    .DESCRIPTION
        Looks up a refresh token and validates it hasn't expired
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'RefreshTokens'
        
        # Sanitize token for query
        $SafeToken = Protect-TableQueryValue -Value $Token
        $Filter = "PartitionKey eq '$SafeToken' and IsValid eq true"
        
        $TokenRecord = Get-AzDataTableEntity @Table -Filter $Filter | Select-Object -First 1
        
        if (-not $TokenRecord) {
            return $null
        }
        
        # Check if token has expired
        $Now = (Get-Date).ToUniversalTime()
        if ($TokenRecord.ExpiresAt -lt $Now) {
            return $null
        }
        
        return $TokenRecord
    } catch {
        Write-Error "Failed to retrieve refresh token: $($_.Exception.Message)"
        return $null
    }
}
