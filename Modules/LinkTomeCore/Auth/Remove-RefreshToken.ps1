function Remove-RefreshToken {
    <#
    .SYNOPSIS
        Invalidate a refresh token
    .DESCRIPTION
        Marks a refresh token as invalid in Azure Table Storage
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'RefreshTokens'
        
        # Sanitize token for query
        $SafeToken = Protect-TableQueryValue -Value $Token
        $Filter = "PartitionKey eq '$SafeToken'"
        
        $TokenRecords = Get-LinkToMeAzDataTableEntity @Table -Filter $Filter
        
        foreach ($TokenRecord in $TokenRecords) {
            $TokenRecord.IsValid = [string]'false'
            Add-LinkToMeAzDataTableEntity @Table -Entity $TokenRecord -Force
        }
        
        return $true
    } catch {
        Write-Error "Failed to remove refresh token: $($_.Exception.Message)"
        return $false
    }
}
