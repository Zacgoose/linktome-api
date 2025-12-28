function New-LinkToMeJWT {
    <#
    .SYNOPSIS
        Create a new JWT token with user authentication context
    .DESCRIPTION
        Can create JWT either from a User object (which fetches all context) or from explicit parameters
    #>
    param(
        [Parameter(Mandatory, ParameterSetName='FromUser')]
        [object]$User,
        
        [Parameter(Mandatory, ParameterSetName='Explicit')]
        [string]$UserId,
    
        [Parameter(Mandatory, ParameterSetName='Explicit')]
        [string]$Email,
    
        [Parameter(Mandatory, ParameterSetName='Explicit')]
        [string]$Username,
    
        [Parameter(ParameterSetName='Explicit')]
        [string[]]$Roles = @('user'),
    
        [Parameter(ParameterSetName='Explicit')]
        [string[]]$Permissions = @(),
        
        [Parameter(ParameterSetName='Explicit')]
        [object[]]$UserManagements = $null
    )
    
    # If User object provided, get all context from it
    if ($PSCmdlet.ParameterSetName -eq 'FromUser') {
        $authContext = Get-UserAuthContext -User $User
        $UserId = $authContext.UserId
        $Email = $authContext.Email
        $Username = $authContext.Username
        $Roles = $authContext.Roles
        $Permissions = $authContext.Permissions
        $UserManagements = $authContext.UserManagements
    }
    
    $Secret = Get-JwtSecret | ConvertTo-SecureString -AsPlainText -Force
    
    # Get token expiration time in minutes (default 15 minutes)
    $ExpirationMinutes = if ($env:JWT_EXPIRATION_MINUTES) { 
        [int]$env:JWT_EXPIRATION_MINUTES 
    } else { 
        15 
    }
    
    $Claims = @{
        sub = $UserId
        email = $Email
        username = $Username
        roles = $Roles
        permissions = $Permissions
        iat = ([DateTimeOffset]::UtcNow).ToUnixTimeSeconds()
        exp = ([DateTimeOffset]::UtcNow.AddMinutes($ExpirationMinutes)).ToUnixTimeSeconds()
        iss = 'LinkTome-app'
    }
    
    # Add userManagements if provided
    if ($UserManagements -and $UserManagements.Count -gt 0) {
        $Claims['userManagements'] = $UserManagements
    }
    
    $Token = New-JsonWebToken -Claims $Claims -HashAlgorithm SHA256 -SecureKey $Secret -TimeToLive ($ExpirationMinutes * 60)
    return $Token
}