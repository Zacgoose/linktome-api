function Update-LinkToMeAzDataTableEntity {
    <#
    .SYNOPSIS
        Wrapper for Update-AzDataTableEntity that handles array serialization
    .DESCRIPTION
        Converts array properties to JSON strings before updating in Azure Table Storage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Context,
        
        [Parameter(Mandatory)]
        $Entity,
        
        [switch]$Force
    )
    
    # Clone the entity to avoid modifying the original
    if ($Entity -is [hashtable]) {
        $ProcessedEntity = $Entity.Clone()
    } else {
        $ProcessedEntity = @{}
        foreach ($prop in $Entity.PSObject.Properties) {
            $ProcessedEntity[$prop.Name] = $prop.Value
        }
    }
    
    # Convert arrays to JSON strings for Azure Table Storage compatibility
    foreach ($key in @($ProcessedEntity.Keys)) {
        if ($ProcessedEntity[$key] -is [array]) {
            $ProcessedEntity[$key] = $ProcessedEntity[$key] | ConvertTo-Json -Compress -Depth 10
        }
    }
    
    # Call the underlying Update-AzDataTableEntity
    $Parameters = @{
        Context = $Context
        Entity = $ProcessedEntity
    }
    
    if ($Force) {
        $Parameters.Force = $true
    }
    
    Update-AzDataTableEntity @Parameters
}
