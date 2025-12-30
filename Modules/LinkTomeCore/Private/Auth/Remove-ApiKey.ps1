function Remove-ApiKey {
    <#
    .SYNOPSIS
        Delete an API key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [string]$KeyId
    )
    
    $Table = Get-LinkToMeTable -TableName 'ApiKeys'
    $Key = Get-LinkToMeAzDataTableEntity @Table -Filter "PartitionKey eq '$UserId' and RowKey eq '$KeyId'" | Select-Object -First 1
    
    if (-not $Key) {
        return @{ Success = $false; Error = 'Key not found' }
    }
    
    Remove-AzDataTableEntity @Table -Entity $Key
    
    return @{ Success = $true }
}