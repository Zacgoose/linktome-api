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
        
        # Parse stored codes
        $StoredCodes = $User.BackupCodes | ConvertFrom-Json
        
        if (-not $StoredCodes -or $StoredCodes.Count -eq 0) {
            return $false
        }
        
        # Hash the submitted code
        $SubmittedHash = Get-StringHash -InputString $SubmittedCode
        
        # Check if it matches any stored code
        $MatchFound = $false
        $RemainingCodes = @()
        
        foreach ($HashedCode in $StoredCodes) {
            if ($HashedCode -eq $SubmittedHash -and -not $MatchFound) {
                # Match found - don't add to remaining codes (single-use)
                $MatchFound = $true
                Write-Information "Backup code verified for user $UserId"
            }
            else {
                # Not a match - keep in remaining codes
                $RemainingCodes += $HashedCode
            }
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
