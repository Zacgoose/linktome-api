function Test-CronSchedule {
    <#
    .SYNOPSIS
        Tests if a cron schedule should run at the current time
    .DESCRIPTION
        Evaluates a 6-field cron expression (seconds minutes hours day month dayofweek)
        against the current time and last occurrence to determine if it should run.
        
        Azure Functions uses 6-field cron expressions:
        {second} {minute} {hour} {day} {month} {day of the week}
        
        Examples:
        "0 */5 * * * *"      - Every 5 minutes
        "0 0 * * * *"        - Every hour at minute 0
        "0 0 2 * * *"        - Every day at 2:00 AM
        "0 */15 * * * *"     - Every 15 minutes
    .PARAMETER CronExpression
        The 6-field cron expression to evaluate
    .PARAMETER LastOccurrence
        The last time this cron job ran
    .PARAMETER CurrentTime
        The current time to check against (defaults to UTC now)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CronExpression,
        
        [Parameter()]
        [datetime]$LastOccurrence,
        
        [Parameter()]
        [datetime]$CurrentTime = [datetime]::UtcNow
    )
    
    try {
        # Parse the cron expression (6 fields for Azure Functions)
        $Parts = $CronExpression -split '\s+'
        
        if ($Parts.Count -ne 6) {
            Write-Warning "Invalid cron expression: $CronExpression (expected 6 fields)"
            return $false
        }
        
        $CronSecond = $Parts[0]
        $CronMinute = $Parts[1]
        $CronHour = $Parts[2]
        $CronDay = $Parts[3]
        $CronMonth = $Parts[4]
        $CronDayOfWeek = $Parts[5]
        
        # If we have a last occurrence, check if enough time has passed
        if ($LastOccurrence) {
            # Calculate the minimum interval based on the cron expression
            $MinIntervalSeconds = Get-CronMinimumInterval -CronExpression $CronExpression
            
            $TimeSinceLastRun = ($CurrentTime - $LastOccurrence).TotalSeconds
            
            # If not enough time has passed, don't run
            if ($TimeSinceLastRun -lt $MinIntervalSeconds) {
                Write-Information "Timer not ready: Only $([math]::Round($TimeSinceLastRun, 0))s since last run, need $MinIntervalSeconds s"
                return $false
            }
        }
        
        # Check if current time matches the cron expression
        $Matches = @(
            (Test-CronField -Value $CurrentTime.Second -Field $CronSecond -Min 0 -Max 59),
            (Test-CronField -Value $CurrentTime.Minute -Field $CronMinute -Min 0 -Max 59),
            (Test-CronField -Value $CurrentTime.Hour -Field $CronHour -Min 0 -Max 23),
            (Test-CronField -Value $CurrentTime.Day -Field $CronDay -Min 1 -Max 31),
            (Test-CronField -Value $CurrentTime.Month -Field $CronMonth -Min 1 -Max 12),
            (Test-CronField -Value ([int]$CurrentTime.DayOfWeek) -Field $CronDayOfWeek -Min 0 -Max 6)
        )
        
        # All fields must match
        return ($Matches -notcontains $false)
        
    } catch {
        Write-Warning "Error evaluating cron expression '$CronExpression': $($_.Exception.Message)"
        return $false
    }
}

function Test-CronField {
    <#
    .SYNOPSIS
        Tests if a value matches a cron field
    #>
    param(
        [int]$Value,
        [string]$Field,
        [int]$Min,
        [int]$Max
    )
    
    # Wildcard matches everything
    if ($Field -eq '*') {
        return $true
    }
    
    # Handle step values (e.g., */5, 0/15)
    if ($Field -match '^(\*|(\d+))/(\d+)$') {
        $Start = if ($Matches[2]) { [int]$Matches[2] } else { $Min }
        $Step = [int]$Matches[3]
        
        # Check if value is at a step interval from start
        return (($Value - $Start) % $Step -eq 0 -and $Value -ge $Start)
    }
    
    # Handle ranges (e.g., 1-5)
    if ($Field -match '^(\d+)-(\d+)$') {
        $RangeStart = [int]$Matches[1]
        $RangeEnd = [int]$Matches[2]
        return ($Value -ge $RangeStart -and $Value -le $RangeEnd)
    }
    
    # Handle lists (e.g., 1,3,5)
    if ($Field -match ',') {
        $Values = $Field -split ',' | ForEach-Object { [int]$_ }
        return ($Values -contains $Value)
    }
    
    # Handle specific value
    if ($Field -match '^\d+$') {
        return ([int]$Field -eq $Value)
    }
    
    # Unknown format, treat as wildcard
    return $true
}

function Get-CronMinimumInterval {
    <#
    .SYNOPSIS
        Gets the minimum interval in seconds for a cron expression
    #>
    param(
        [string]$CronExpression
    )
    
    $Parts = $CronExpression -split '\s+'
    
    if ($Parts.Count -ne 6) {
        return 60  # Default to 60 seconds
    }
    
    $CronSecond = $Parts[0]
    $CronMinute = $Parts[1]
    $CronHour = $Parts[2]
    
    # Check seconds field
    if ($CronSecond -match '^\*/(\d+)$') {
        return [int]$Matches[1]
    }
    
    if ($CronSecond -match '^(\d+)/(\d+)$') {
        return [int]$Matches[2]
    }
    
    # Check minutes field
    if ($CronMinute -match '^\*/(\d+)$') {
        return [int]$Matches[1] * 60
    }
    
    if ($CronMinute -match '^(\d+)/(\d+)$') {
        return [int]$Matches[2] * 60
    }
    
    # Check hours field
    if ($CronHour -match '^\*/(\d+)$') {
        return [int]$Matches[1] * 3600
    }
    
    if ($CronHour -match '^(\d+)/(\d+)$') {
        return [int]$Matches[2] * 3600
    }
    
    # If specific values, assume daily
    if ($CronHour -match '^\d+$' -and $CronMinute -match '^\d+$') {
        return 86400  # Daily
    }
    
    # Default to 60 seconds
    return 60
}
