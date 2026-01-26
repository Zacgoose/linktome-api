function Get-ApiKeyFromRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Request
    )
    
    # Extract key from headers
    $ApiKey = $null
    
    $AuthHeader = $Request.Headers.Authorization
    if ($AuthHeader -and $AuthHeader -match '^Bearer\s+(ltm_.+)$') {
        $ApiKey = $Matches[1]
    }
    
    if (-not $ApiKey -and $Request.Headers.'X-API-Key') {
        $ApiKey = $Request.Headers.'X-API-Key'
    }
    
    if (-not $ApiKey) {
        return @{ Valid = $false; Error = 'API key required' }
    }
    
    # Parse key format: ltm_<keyid>_<secret>
    if ($ApiKey -notmatch '^ltm_([a-z0-9]{8})_([a-z0-9]{32})$') {
        return @{ Valid = $false; Error = 'Invalid API key format' }
    }
    
    $KeyId = $Matches[1]
    $Secret = $Matches[2]
    
    # Direct lookup by KeyId
    $Table = Get-LinkToMeTable -TableName 'ApiKeys'
    $KeyRecord = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$KeyId'" | Select-Object -First 1
    
    if (-not $KeyRecord) {
        return @{ Valid = $false; Error = 'Invalid API key' }
    }
    
    # Validate secret
    $ProvidedHash = Get-StringHash -InputString $Secret
    if ($ProvidedHash -ne $KeyRecord.SecretHash) {
        return @{ Valid = $false; Error = 'Invalid API key' }
    }
    
    # Check if key is active
    if ($KeyRecord.PSObject.Properties['Active'] -and $KeyRecord.Active -eq $false) {
        $Reason = if ($KeyRecord.PSObject.Properties['DisabledReason']) { $KeyRecord.DisabledReason } else { 'API key is disabled' }
        return @{ Valid = $false; Error = $Reason }
    }
    
    # Get user
    $UserTable = Get-LinkToMeTable -TableName 'Users'
    $User = Get-LinkToMeAzDataTableEntity @UserTable -Filter "RowKey eq '$($KeyRecord.PartitionKey)'" | Select-Object -First 1
    
    if (-not $User -or -not $User.IsActive) {
        return @{ Valid = $false; Error = 'User account is disabled' }
    }
    
    # Get user managements (users this person manages)
    # Uses same logic as Get-UserAuthContext
    $UserManagements = @()
    try {
        if ($User.IsUserManager) {
            $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'
            $UsersTable = Get-LinkToMeTable -TableName 'Users'
            
            # PartitionKey = manager's UserId, RowKey = managed user's UserId
            $Managees = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$($User.RowKey)' and State eq 'accepted'" -ErrorAction SilentlyContinue
            
            if ($Managees) {
                foreach ($um in $Managees) {
                    $ManagedUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$($um.RowKey)'" -ErrorAction SilentlyContinue | Select-Object -First 1
                    $ManageePermissions = Get-DefaultRolePermissions -Role $um.Role
                    
                    $UserManagements += @{
                        UserId      = $um.RowKey
                        DisplayName = if ($ManagedUser) { $ManagedUser.DisplayName } else { '' }
                        Email       = if ($ManagedUser) { $ManagedUser.PartitionKey } else { '' }
                        role        = $um.Role
                        state       = $um.State
                        direction   = 'manager'
                        permissions = $ManageePermissions
                    }
                }
            }
        }
    } catch {
        Write-Warning "Failed to load user managements: $($_.Exception.Message)"
    }
    
    # Update last used
    $ClientIP = Get-ClientIPAddress -Request $Request
    
    $UpdateEntity = @{
        PartitionKey = [string]$KeyRecord.PartitionKey
        RowKey       = [string]$KeyRecord.RowKey
        SecretHash   = [string]$KeyRecord.SecretHash
        Name         = [string]$KeyRecord.Name
        Permissions  = [string]$KeyRecord.Permissions
        CreatedAt    = $KeyRecord.CreatedAt
        LastUsedAt   = [datetime]::UtcNow
        LastUsedIP   = [string]$ClientIP
    }
    
    try {
        Add-LinkToMeAzDataTableEntity @Table -Entity $UpdateEntity -Force
    } catch {
        Write-Warning "Failed to update API key last used: $($_.Exception.Message)"
    }
    
    # Parse stored data
    $KeyPermissions = @()
    if ($KeyRecord.Permissions) {
        try { $KeyPermissions = $KeyRecord.Permissions | ConvertFrom-Json } catch {}
    }
    
    $UserRoles = @('user')
    try {
        if ($User.Roles) { $UserRoles = $User.Roles | ConvertFrom-Json }
    } catch {}
    
    $Tier = if ($User.SubscriptionTier) { $User.SubscriptionTier } else { 'free' }
    
    return @{
        Valid           = $true
        KeyId           = $KeyId
        UserId          = $KeyRecord.PartitionKey
        KeyPermissions  = $KeyPermissions
        UserRoles       = $UserRoles
        UserManagements = $UserManagements
        Tier            = $Tier
        User            = $User
    }
}