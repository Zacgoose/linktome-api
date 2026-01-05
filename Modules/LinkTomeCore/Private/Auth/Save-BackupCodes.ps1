function Save-BackupCodes {
    <#
    .SYNOPSIS
        Save hashed backup codes to user record
    .DESCRIPTION
        Hashes and saves backup codes to a user's record in the database
    .PARAMETER UserId
        The user ID
    .PARAMETER PlainTextCodes
        Array of plain text backup codes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $true)]
        [array]$PlainTextCodes
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get user
        $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$UserId'" | Select-Object -First 1
        
        if (-not $User) {
            Write-Error "User not found: $UserId"
            return $false
        }
        
        # Validate input codes
        foreach ($Code in $PlainTextCodes) {
            if (-not ($Code -is [string]) -or [string]::IsNullOrWhiteSpace($Code)) {
                Write-Error "All backup codes must be non-empty strings"
                return $false
            }
        }
        
        # Hash each code
        $HashedCodes = $PlainTextCodes | ForEach-Object {
            Get-StringHash -InputString $_
        }
        
        # Store as JSON array
        if (-not $User.PSObject.Properties['BackupCodes']) {
            $User | Add-Member -NotePropertyName BackupCodes -NotePropertyValue [string]($HashedCodes | ConvertTo-Json -Compress) -Force
        } else {
            $User.BackupCodes = [string]($HashedCodes | ConvertTo-Json -Compress)
        }
        
        # Update user
        Add-LinkToMeAzDataTableEntity @Table -Entity $User -Force
        
        Write-Information "Saved $($HashedCodes.Count) backup codes for user $UserId"
        return $true
    }
    catch {
        Write-Error "Failed to save backup codes: $($_.Exception.Message)"
        return $false
    }
}
