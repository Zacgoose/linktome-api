function Test-PasswordStrength {
    <#
    .SYNOPSIS
        Validate password strength
    .DESCRIPTION
        Validates that a password meets minimum security requirements
    .PARAMETER Password
        The password to validate
    .EXAMPLE
        Test-PasswordStrength -Password "MySecurePass123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Password
    )
    
    $Result = @{
        Valid = $true
        Message = ''
    }
    
    # Minimum length check
    if ($Password.Length -lt 8) {
        $Result.Valid = $false
        $Result.Message = 'Password must be at least 8 characters long'
        return $Result
    }
    
    # Maximum length check (prevent DoS)
    if ($Password.Length -gt 128) {
        $Result.Valid = $false
        $Result.Message = 'Password must be 128 characters or less'
        return $Result
    }
    
    # Check for common weak passwords
    $CommonPasswords = @(
        'password', '12345678', 'qwerty', 'abc123', 'password123',
        'admin', 'letmein', 'welcome', '123456789', 'password1'
    )
    
    if ($Password.ToLower() -in $CommonPasswords) {
        $Result.Valid = $false
        $Result.Message = 'Password is too common. Please choose a stronger password'
        return $Result
    }
    
    $Result.Message = 'Password meets requirements'
    return $Result
}
