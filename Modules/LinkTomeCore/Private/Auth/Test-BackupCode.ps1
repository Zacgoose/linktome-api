function Test-BackupCode {
    <#
    .SYNOPSIS
        Verify and consume a backup code
    .DESCRIPTION
        Verifies a backup code and removes it from the user's record if valid (single-use)
    .PARAMETER UserId
        The user ID
    .PARAMETER SubmittedCode
        The backup code submitted by the user
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $true)]
        [string]$SubmittedCode
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get user
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$UserId'" | Select-Object -First 1
        
        if (-not $User) {
            Write-Error "User not found: $UserId"
            return $false
        }
        
        # Check if user has backup codes
        if (-not $User.BackupCodes) {
            return $false
        }
        
        # Parse stored codes with error handling
        try {
            $StoredCodes = $User.BackupCodes | ConvertFrom-Json
        }
        catch {
            Write-Warning "Invalid backup codes JSON for user $UserId"
            return $false
        }
        
        if (-not $StoredCodes -or $StoredCodes.Count -eq 0) {
            return $false
        }
        
        # Hash the submitted code
        $SubmittedHash = Get-StringHash -InputString $SubmittedCode
        Write-Information "Submitted code: '$SubmittedCode' -> Hash: '$SubmittedHash'"
        Write-Information "Number of stored codes: $($StoredCodes.Count)"
        
        # Check if it matches any stored code
        $MatchFound = $false
        $RemainingCodes = @()
        $CodeIndex = 0
        
        foreach ($HashedCode in $StoredCodes) {
            Write-Information "  Comparing with stored code #$CodeIndex : '$HashedCode'"
            if ($HashedCode -eq $SubmittedHash -and -not $MatchFound) {
                # Match found - don't add to remaining codes (single-use)
                $MatchFound = $true
                Write-Information "Backup code verified for user $UserId (matched code #$CodeIndex)"
                # Continue to process remaining codes for storage
            }
            else {
                # Not a match - keep in remaining codes
                $RemainingCodes += $HashedCode
            }
            $CodeIndex++
        }
        
        if ($MatchFound) {
            # Update user with remaining codes
            $User.BackupCodes = ($RemainingCodes | ConvertTo-Json -Compress)
            Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
            
            return $true
        }
        
        return $false
    }
    catch {
        Write-Error "Failed to verify backup code: $($_.Exception.Message)"
        return $false
    }
}
