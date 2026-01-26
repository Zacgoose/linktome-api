function Get-UserApiKeys {
    <#
    .SYNOPSIS
        Get all API keys for a user (without secrets)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'ApiKeys'
        $Keys = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$UserId'" -ErrorAction SilentlyContinue
        
        # Handle null/empty results
        if (-not $Keys) {
            return @()
        }
        
        # Ensure we're working with an array
        $KeysArray = @($Keys)
        
        if ($KeysArray.Count -eq 0) {
            return @()
        }
        
        return @($KeysArray | ForEach-Object {
            @{
                keyId          = $_.RowKey
                name           = $_.Name
                permissions    = @(($_.Permissions | ConvertFrom-Json -ErrorAction SilentlyContinue) ?? @())
                active         = if ($_.PSObject.Properties['Active']) { [bool]$_.Active } else { $true }
                disabledReason = if ($_.PSObject.Properties['DisabledReason']) { $_.DisabledReason } else { $null }
                createdAt      = $_.CreatedAt
                lastUsedAt     = $_.LastUsedAt
                lastUsedIP     = $_.LastUsedIP
            }
        })
    }
    catch {
        Write-Warning "Failed to get API keys: $($_.Exception.Message)"
        return @()
    }
}