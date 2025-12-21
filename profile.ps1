Write-Information '#### LinkToMe API Start ####'

$Timings = @{}
$TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Import modules
$SwModules = [System.Diagnostics.Stopwatch]::StartNew()
$ModulesPath = Join-Path $PSScriptRoot 'Modules'
$Modules = @('LinkTomeCore', 'AzBobbyTables', 'PrivateApi', 'PublicApi', 'PSJsonWebToken')
foreach ($Module in $Modules) {
    $SwModule = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Import-Module -Name (Join-Path $ModulesPath $Module) -ErrorAction Stop
        $SwModule.Stop()
        $Timings["Module_$Module"] = $SwModule.Elapsed.TotalMilliseconds
    } catch {
        $SwModule.Stop()
        $Timings["Module_$Module"] = $SwModule.Elapsed.TotalMilliseconds
        Write-Error "Failed to import module - $Module : $($_.Exception.Message)"
    }
}
$SwModules.Stop()
$Timings['AllModules'] = $SwModules.Elapsed.TotalMilliseconds

$SwVersion = [System.Diagnostics.Stopwatch]::StartNew()
$CurrentVersion = (Get-Content -Path (Join-Path $PSScriptRoot 'version_latest.txt') -Raw -ErrorAction SilentlyContinue).Trim()
if (-not $CurrentVersion) { $CurrentVersion = '1.0.0' }
Write-Information "Function App: $($env:WEBSITE_SITE_NAME ?? 'Local') | API Version: $CurrentVersion | PS Version: $($PSVersionTable.PSVersion)"
$global:LinkToMeVersion = $CurrentVersion
$SwVersion.Stop()
$Timings['VersionCheck'] = $SwVersion.Elapsed.TotalMilliseconds

$TotalStopwatch.Stop()
$Timings['Total'] = $TotalStopwatch.Elapsed.TotalMilliseconds

# Output timing summary
$TimingsRounded = [ordered]@{}
foreach ($Key in ($Timings.Keys | Sort-Object)) {
    $TimingsRounded[$Key] = [math]::Round($Timings[$Key], 2)
}
Write-Information "Profile Load Timings: $($TimingsRounded | ConvertTo-Json -Compress)"