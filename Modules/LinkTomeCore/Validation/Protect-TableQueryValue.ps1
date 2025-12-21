function Protect-TableQueryValue {
    <#
    .SYNOPSIS
        Sanitize value for use in Azure Table Storage query filter
    .DESCRIPTION
        Escapes single quotes in values to prevent query injection attacks.
        Azure Table Storage uses OData-style queries where single quotes delimit string values.
    .PARAMETER Value
        The value to sanitize for use in a filter query
    .EXAMPLE
        $SafeEmail = Protect-TableQueryValue -Value $UserInput
        $Filter = "PartitionKey eq '$SafeEmail'"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )
    
    # Escape single quotes by doubling them (OData standard)
    # This prevents breaking out of string literals in queries
    $SanitizedValue = $Value -replace "'", "''"
    
    return $SanitizedValue
}
