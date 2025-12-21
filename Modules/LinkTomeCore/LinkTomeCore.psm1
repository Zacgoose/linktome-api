# Import all functions from subdirectories
$Subdirectories = @('Auth', 'Table', 'Validation', 'Error', 'RateLimit', 'Logging')
$AllFunctions = @()

foreach ($Subdir in $Subdirectories) {
    $Path = Join-Path $PSScriptRoot $Subdir
    if (Test-Path $Path) {
        $Functions = @(Get-ChildItem -Path (Join-Path $Path '*.ps1') -Recurse -ErrorAction SilentlyContinue)
        foreach ($import in @($Functions)) {
            try {
                . $import.FullName
                $AllFunctions += $import
            } catch {
                Write-Error -Message "Failed to import function $($import.FullName): $_"
            }
        }
    }
}

# Export all functions
Export-ModuleMember -Function $AllFunctions.BaseName