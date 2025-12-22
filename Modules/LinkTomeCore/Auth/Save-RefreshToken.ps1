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
        # Per CIPP-API Add-CIPPScheduledTask: cast most to [string], booleans to [bool], but leave one string uncast
        # (CIPP has Results = 'Planned' without cast, all others are [string] or [bool])
        $TokenEntity = @{
            PartitionKey = [string]$Token
            RowKey = [string](New-Guid).Guid
            UserId = [string]$UserId
            ExpiresAt = [string]$ExpiresAt.ToString('o')  # ISO 8601 format
            CreatedAt = [string](Get-Date).ToUniversalTime().ToString('o')  # ISO 8601 format
            IsValid = [bool]$true
            TokenType = 'RefreshToken'  # Uncast string like CIPP's Results property
        }
        
        Write-Information "DEBUG: TokenEntity properties:"
        Write-Information "  PartitionKey type: $($TokenEntity.PartitionKey.GetType().FullName)"
        Write-Information "  RowKey type: $($TokenEntity.RowKey.GetType().FullName)"
        Write-Information "  UserId type: $($TokenEntity.UserId.GetType().FullName)"
        Write-Information "  ExpiresAt type: $($TokenEntity.ExpiresAt.GetType().FullName)"
        Write-Information "  CreatedAt type: $($TokenEntity.CreatedAt.GetType().FullName)"
        Write-Information "  IsValid type: $($TokenEntity.IsValid.GetType().FullName), value: $($TokenEntity.IsValid)"
        Write-Information "  TokenType type: $($TokenEntity.TokenType.GetType().FullName), value: $($TokenEntity.TokenType)"
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $TokenEntity -Force
        
        return $true
    } catch {
        Write-Error "Failed to save refresh token: $($_.Exception.Message)"
        return $false
    }
}
