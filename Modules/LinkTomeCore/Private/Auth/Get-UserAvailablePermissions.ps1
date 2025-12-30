function Get-UserAvailablePermissions {
    <#
    .SYNOPSIS
        Get all permissions available to a user (own + from roles)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId
    )
    
    $Table = Get-LinkToMeTable -TableName 'Users'
    $User = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$UserId'" | Select-Object -First 1
    
    if (-not $User) { return @() }
    
    $Permissions = @()
    
    # User's direct permissions
    if ($User.Permissions) {
        try {
            $Permissions += ($User.Permissions | ConvertFrom-Json)
        } catch {}
    }
    
    # Permissions from roles
    if ($User.Roles) {
        try {
            $Roles = $User.Roles | ConvertFrom-Json
            foreach ($Role in $Roles) {
                $RolePermissions = Get-DefaultRolePermissions -Role $Role
                $Permissions += $RolePermissions
            }
        } catch {}
    }
    
    return @($Permissions | Select-Object -Unique)
}