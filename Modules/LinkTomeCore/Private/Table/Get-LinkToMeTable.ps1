function Get-LinkToMeTable {
    <#
    .SYNOPSIS
        Get Azure Table Storage context for LinkToMe
    #>
    [CmdletBinding()]
    param (
        $tablename
    )
    $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage -TableName $tablename
    New-AzDataTable -Context $Context | Out-Null

    @{
        Context = $Context
    }
}