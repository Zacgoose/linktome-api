function Get-LinkTomeTimerFunctions {
    <#
    .SYNOPSIS
        Get timer functions from LinkTomeTimers.json configuration
    .DESCRIPTION
        Reads and parses the LinkTomeTimers.json file to return scheduled timer functions
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    try {
        # Navigate from Modules/LinkTomeCore/Private/Timer to root
        $TimersJsonPath = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.Parent.FullName 'LinkTomeTimers.json'
        
        if (-not (Test-Path $TimersJsonPath)) {
            Write-Warning "LinkTomeTimers.json not found at: $TimersJsonPath"
            return @()
        }

        $TimersJson = Get-Content -Path $TimersJsonPath -Raw | ConvertFrom-Json
        
        # Validate cron expressions and convert to objects
        $ValidTimers = $TimersJson | ForEach-Object {
            $Timer = $_
            
            # Validate required properties
            if (-not $Timer.Id -or -not $Timer.Command -or -not $Timer.Cron) {
                Write-Warning "Timer missing required properties (Id, Command, or Cron): $($Timer | ConvertTo-Json -Compress)"
                return
            }
            
            # Parse cron expression to determine if it should run now
            # For now, we return all timers and let the Azure timer trigger handle scheduling
            # The cron expression in function.json (0 0/15 * * * *) controls the trigger frequency
            [PSCustomObject]@{
                Id               = $Timer.Id
                Command          = $Timer.Command
                Description      = $Timer.Description
                Cron             = $Timer.Cron
                Priority         = if ($null -ne $Timer.Priority) { $Timer.Priority } else { 99 }
                RunOnProcessor   = if ($null -ne $Timer.RunOnProcessor) { $Timer.RunOnProcessor } else { $true }
                PreferredProcessor = $Timer.PreferredProcessor
                IsSystem         = if ($null -ne $Timer.IsSystem) { $Timer.IsSystem } else { $false }
                Parameters       = $Timer.Parameters
            }
        } | Where-Object { $null -ne $_ } | Sort-Object Priority

        Write-Information "Loaded $($ValidTimers.Count) timer functions from configuration"
        return $ValidTimers
        
    } catch {
        Write-Warning "Error loading LinkTomeTimers.json: $($_.Exception.Message)"
        return @()
    }
}
