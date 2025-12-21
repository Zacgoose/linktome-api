function New-LinkToMeJWT {
    <#
    .SYNOPSIS
        Create a new JWT token
    #>
    param(
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [string]$Email,
        
        [Parameter(Mandatory)]
        [string]$Username,
        
        [Parameter()]
        [string[]]$Roles = @('user'),
        
        [Parameter()]
        [string[]]$Permissions = @(),
        
        [Parameter()]
        [string]$CompanyId = $null
    )
    
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
    
    # Add companyId if provided
    if ($CompanyId) {
        $Claims['companyId'] = $CompanyId
    }
    
    $Token = New-JsonWebToken -Claims $Claims -HashAlgorithm SHA256 -SecureKey $Secret
    
    return $Token
}