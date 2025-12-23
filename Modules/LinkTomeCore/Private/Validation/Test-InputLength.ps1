function Test-InputLength {
    <#
    .SYNOPSIS
        Validate input length against maximum allowed
    .DESCRIPTION
        Checks if a string input is within the acceptable length range
    .PARAMETER Value
        The value to check
    .PARAMETER MaxLength
        Maximum allowed length
    .PARAMETER FieldName
        Name of the field (for error messages)
    .EXAMPLE
        Test-InputLength -Value $Bio -MaxLength 500 -FieldName "Bio"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,
        
        [Parameter(Mandatory)]
        [int]$MaxLength,
        
        [Parameter(Mandatory)]
        [string]$FieldName
    )
    
    $Result = @{
        Valid = $true
        Message = ''
    }
    
    if ($Value.Length -gt $MaxLength) {
        $Result.Valid = $false
        $Result.Message = "$FieldName must be $MaxLength characters or less (current: $($Value.Length))"
        return $Result
    }
    
    $Result.Message = "$FieldName length is valid"
    return $Result
}
