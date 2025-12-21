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
    
    $Claims = @{
        sub = $UserId
        email = $Email
        username = $Username
        roles = $Roles
        permissions = $Permissions
        iat = ([DateTimeOffset]::UtcNow).ToUnixTimeSeconds()
        exp = ([DateTimeOffset]::UtcNow.AddMinutes(15)).ToUnixTimeSeconds()  # 15 minutes
        iss = 'LinkTome-app'
    }
    
    # Add companyId if provided
    if ($CompanyId) {
        $Claims['companyId'] = $CompanyId
    }
    
    $Token = New-JsonWebToken -Claims $Claims -HashAlgorithm SHA256 -SecureKey $Secret
    
    return $Token
}