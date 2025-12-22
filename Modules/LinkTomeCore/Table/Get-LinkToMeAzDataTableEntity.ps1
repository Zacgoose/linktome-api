function Get-LinkToMeAzDataTableEntity {
    <#
    .SYNOPSIS
        Wrapper for Get-AzDataTableEntity that handles array deserialization
    .DESCRIPTION
        Converts JSON string properties back to arrays when retrieving from Azure Table Storage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Context,
        
        [Parameter()]
        $Filter,
        
        [Parameter()]
        $Property,
        
        [Parameter()]
        $First,
        
        [Parameter()]
        $Skip
    )
    
    # Build parameters for underlying call
    $Parameters = @{
        Context = $Context
    }
    
    if ($Filter) { $Parameters.Filter = $Filter }
    if ($Property) { $Parameters.Property = $Property }
    if ($First) { $Parameters.First = $First }
    if ($Skip) { $Parameters.Skip = $Skip }
    
    # Get entities from table
    $Results = Get-AzDataTableEntity @Parameters
    
    # Process each entity to deserialize JSON strings back to arrays
    foreach ($entity in $Results) {
        # Check known array properties and deserialize if they're JSON strings
        $arrayProperties = @('Roles', 'Permissions')
        
        foreach ($propName in $arrayProperties) {
            if ($entity.PSObject.Properties[$propName] -and 
                $entity.$propName -is [string] -and 
                $entity.$propName.StartsWith('[')) {
                try {
                    $entity.$propName = $entity.$propName | ConvertFrom-Json
                } catch {
                    Write-Warning "Failed to deserialize $propName for entity $($entity.RowKey): $($_.Exception.Message)"
                }
            }
        }
    }
    
    return $Results
}
