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
        # Convert DateTime to ISO 8601 string for Azure Table Storage compatibility
        # Cast ALL properties to ensure proper type (CIPP-API pattern)
        $TokenEntity = @{
            PartitionKey = [string]$Token
            RowKey = [string](New-Guid).ToString()
            UserId = [string]$UserId
            ExpiresAt = [string]$ExpiresAt.ToString('o')  # ISO 8601 format
            CreatedAt = [string](Get-Date).ToUniversalTime().ToString('o')  # ISO 8601 format
            IsValid = [bool]$true
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $TokenEntity -Force
        
        return $true
    } catch {
        Write-Error "Failed to save refresh token: $($_.Exception.Message)"
        return $false
    }
}
