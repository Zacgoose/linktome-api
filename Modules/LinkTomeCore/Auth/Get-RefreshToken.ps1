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
        $Filter = "PartitionKey eq '$SafeToken' and IsValid eq 'true'"
        
        $TokenRecord = Get-LinkToMeAzDataTableEntity @Table -Filter $Filter | Select-Object -First 1
        
        if (-not $TokenRecord) {
            return $null
        }
        
        # Check if token has expired
        # Convert ISO 8601 string back to DateTime for comparison
        $Now = (Get-Date).ToUniversalTime()
        $ExpiresAt = [DateTime]::Parse($TokenRecord.ExpiresAt)
        if ($ExpiresAt -lt $Now) {
            return $null
        }
        
        return $TokenRecord
    } catch {
        Write-Error "Failed to retrieve refresh token: $($_.Exception.Message)"
        return $null
    }
}
