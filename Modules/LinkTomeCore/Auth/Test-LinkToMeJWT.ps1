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
            Write-SecurityEvent -EventType 'TokenValidationFailed' -Reason 'InvalidSignature'
            return $null
        }
        
        $Decoded = $Token | ConvertFrom-EncodedJsonWebToken
        $Payload = $Decoded.Payload | ConvertFrom-Json

        # Extract roles and permissions (handle both array and single values)
        $Roles = if ($Payload.roles) {
            if ($Payload.roles -is [array]) { $Payload.roles } else { @($Payload.roles) }
        } else {
            @('user')
        }
        
        $Permissions = if ($Payload.permissions) {
            if ($Payload.permissions -is [array]) { $Payload.permissions } else { @($Payload.permissions) }
        } else {
            @()
        }

        return @{
            Valid = $true
            UserId = $Payload.sub
            Email = $Payload.email
            Username = $Payload.username
            Roles = $Roles
            Permissions = $Permissions
            CompanyId = $Payload.companyId
        }
    } catch {
        Write-Warning "Token validation failed: $($_.Exception.Message)"
        Write-SecurityEvent -EventType 'TokenValidationFailed' -Reason 'Exception'
        return $null
    }
}