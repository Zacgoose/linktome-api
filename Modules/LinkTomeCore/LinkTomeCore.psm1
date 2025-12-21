# Import all functions from subdirectories
if (Test-Path (Join-Path $PSScriptRoot 'Auth')) {
    $Auth = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Auth\*.ps1') -Recurse -ErrorAction SilentlyContinue)
    foreach ($import in @($Auth)) {
        try {
            . $import.FullName
        } catch {
            Write-Error -Message "Failed to import function $($import.FullName): $_"
        }
    }
}

if (Test-Path (Join-Path $PSScriptRoot 'Table')) {
    $Table = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Table\*.ps1') -Recurse -ErrorAction SilentlyContinue)
    foreach ($import in @($Table)) {
        try {
            . $import.FullName
        } catch {
            Write-Error -Message "Failed to import function $($import.FullName): $_"
        }
    }
}

# Export all functions
$AllFunctions = @($Auth) + @($Table)
Export-ModuleMember -Function $AllFunctions.BaseName