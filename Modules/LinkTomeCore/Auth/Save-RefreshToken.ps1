function Save-RefreshToken {
    <#
    .SYNOPSIS
        Save refresh token to Azure Table Storage
    .DESCRIPTION
        Stores a refresh token with expiration in the RefreshTokens table
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Token,
        
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [datetime]$ExpiresAt
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'RefreshTokens'
        
        # Use token as PartitionKey for direct lookup, UserId as RowKey for user-based queries
        $TokenEntity = @{
            PartitionKey = $Token
            RowKey = (New-Guid).ToString()
            UserId = $UserId
            ExpiresAt = $ExpiresAt
            CreatedAt = (Get-Date).ToUniversalTime()
            IsValid = $true
        }
        
        Add-AzDataTableEntity @Table -Entity $TokenEntity -Force
        
        return $true
    } catch {
        Write-Error "Failed to save refresh token: $($_.Exception.Message)"
        return $false
    }
}
