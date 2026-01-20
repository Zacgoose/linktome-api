function Handle-InvoiceFinalized {
    param([Parameter(Mandatory)][object]$Invoice)
    Write-Information "Stub: Handle-InvoiceFinalized called for invoice $($Invoice.id)"
    return $true
}