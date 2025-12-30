function New-ApiKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter()]
        [string[]]$Permissions = @()
    )
    
    # Character set: a-z, 0-9 (36 chars) - URL safe, case-insensitive
    $Alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789'
    
    function Get-RandomString {
        param([int]$Length)
        $Bytes = [byte[]]::new($Length)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($Bytes)
        $Result = -join ($Bytes | ForEach-Object { $Alphabet[$_ % $Alphabet.Length] })
        return $Result
    }
    
    $Table = Get-LinkToMeTable -TableName 'ApiKeys'
    
    # Generate unique key ID with collision check
    $KeyId = $null
    $MaxAttempts = 5
    $Attempt = 0
    
    while (-not $KeyId -and $Attempt -lt $MaxAttempts) {
        $Attempt++
        $CandidateId = 'k' + (Get-RandomString -Length 7)
        
        # Check if this ID already exists
        $Existing = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$CandidateId'" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if (-not $Existing) {
            $KeyId = $CandidateId
            Write-Verbose "Generated unique key ID: $KeyId (attempt $Attempt)"
        } else {
            Write-Warning "Key ID collision detected: $CandidateId (attempt $Attempt)"
        }
    }
    
    if (-not $KeyId) {
        throw "Failed to generate unique key ID after $MaxAttempts attempts"
    }
    
    # Generate secret (32 chars)
    $Secret = Get-RandomString -Length 32
    
    # Full key
    $FullKey = "ltm_${KeyId}_${Secret}"
    
    # Hash secret for storage
    $SecretHash = Get-StringHash -InputString $Secret
    
    # Store
    $PermissionsJson = if ($Permissions.Count -eq 0) { '[]' } else { $Permissions | ConvertTo-Json -Compress }
    
    $KeyRecord = @{
        PartitionKey = $UserId
        RowKey       = $KeyId
        SecretHash   = $SecretHash
        Name         = $Name
        Permissions  = [string]$PermissionsJson
        CreatedAt    = [datetime]::UtcNow
    }
    
    Add-LinkToMeAzDataTableEntity @Table -Entity $KeyRecord -Force
    
    return @{
        keyId       = $KeyId
        key         = $FullKey
        name        = $Name
        permissions = $Permissions
        createdAt   = $KeyRecord.CreatedAt
    }
}