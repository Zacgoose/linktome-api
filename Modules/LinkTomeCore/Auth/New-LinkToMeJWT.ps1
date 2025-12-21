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
        [string]$Username
    )
    
    $Secret = Get-JwtSecret | ConvertTo-SecureString -AsPlainText -Force
    
    $Claims = @{
        sub = $UserId
        email = $Email
        username = $Username
        iat = ([DateTimeOffset]::UtcNow).ToUnixTimeSeconds()
        exp = ([DateTimeOffset]::UtcNow.AddHours(24)).ToUnixTimeSeconds()
        iss = 'LinkTome-app'
    }
    
    $Token = New-JsonWebToken -Claims $Claims -HashAlgorithm SHA256 -SecureKey $Secret
    
    return $Token
}