function Update-ApiKeyPermissions {
    <#
    .SYNOPSIS
        Update permissions on an API key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [string]$KeyId,
        
        [Parameter(Mandatory)]
        [string[]]$Permissions
    )
    
    $Table = Get-LinkToMeTable -TableName 'ApiKeys'
    $Key = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$UserId' and RowKey eq '$KeyId'" | Select-Object -First 1
    
    if (-not $Key) {
        return @{ Success = $false; Error = 'Key not found' }
    }
    
    $Key.Permissions = [string]($Permissions | ConvertTo-Json -Compress)
    Add-LinkToMeAzDataTableEntity @Table -Entity $Key -Force
    
    return @{ Success = $true }
}