function Test-LinkToMeJWT {
    <#
    .SYNOPSIS
        Validate and decode a JWT token
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )
    
    $Secret = Get-JwtSecret | ConvertTo-SecureString -AsPlainText -Force
    
    try {
        $IsValid = Test-JsonWebToken -JsonWebToken $Token -HashAlgorithm SHA256 -SecureKey $Secret
        
        if (-not $IsValid) {
            Write-SecurityEvent -EventType 'TokenValidationFailed' -Metadata @{
                Reason = 'InvalidSignature'
            }
            return $null
        }
        
        $Decoded = $Token | ConvertFrom-EncodedJsonWebToken
        $Payload = $Decoded.Payload | ConvertFrom-Json

        return @{
            Valid = $true
            UserId = $Payload.sub
            Email = $Payload.email
            Username = $Payload.username
        }
    } catch {
        Write-Warning "Token validation failed: $($_.Exception.Message)"
        Write-SecurityEvent -EventType 'TokenValidationFailed' -Metadata @{
            Reason = 'Exception'
            Error = $_.Exception.Message
        }
        return $null
    }
}