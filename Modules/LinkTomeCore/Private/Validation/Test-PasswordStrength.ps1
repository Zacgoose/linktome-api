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

    # Check for common weak passwords (expand list)
    $CommonPasswords = @(
        'password', '12345678', 'qwerty', 'abc123', 'password123',
        'admin', 'letmein', 'welcome', '123456789', 'password1',
        'iloveyou', 'sunshine', 'princess', 'football', 'monkey',
        'charlie', 'aa123456', 'donald', 'qwerty123', '1q2w3e4r',
        'zaq12wsx', 'dragon', 'baseball', '11111111', 'superman',
        'michael', 'shadow', 'master', 'jennifer', 'asdfgh',
        'hannah', 'jordan', 'hunter', '2000', 'harley', '123123',
        '654321', 'qwertyuiop', 'maggie', 'starwars', 'flower',
        'passw0rd', 'lovely', 'cheese', 'computer', 'whatever',
        'trustno1', 'hello', 'freedom', 'secret', 'qazwsx', 'ninja',
        'mustang', 'thomas', 'password!', 'welcome1', 'batman',
        'zaq1zaq1', 'q1w2e3r4', 'pokemon', 'qwerty1', '123qwe'
    )
    if ($Password.ToLower() -in $CommonPasswords) {
        $Result.Valid = $false
        $Result.Message = 'Password is too common. Please choose a stronger password'
        return $Result
    }

    # Require at least one uppercase, one lowercase, one digit, one special character (ASCII only)
    if ($Password -notmatch '[A-Z]') {
        $Result.Valid = $false
        $Result.Message = 'Password must contain at least one uppercase letter'
        return $Result
    }
    if ($Password -notmatch '[a-z]') {
        $Result.Valid = $false
        $Result.Message = 'Password must contain at least one lowercase letter'
        return $Result
    }
    if ($Password -notmatch '\d') {
        $Result.Valid = $false
        $Result.Message = 'Password must contain at least one digit'
        return $Result
    }
    # Only allow standard ASCII special characters
    # Use single quotes for regex, escape only necessary characters, and include @
    if ($Password -notmatch '[!"#$%&''()*+,\-./:;<=>?@[\\\]^_`{|}~@]') {
        $Result.Valid = $false
        $Result.Message = 'Password must contain at least one standard special character (!"#$%&''()*+,-./:;<=>?@[\\]^_`{|}~@)'
        return $Result
    }
    # Disallow any non-ASCII character (including emoji)
    if ($Password -match '[^\x20-\x7E]') {
        $Result.Valid = $false
        $Result.Message = 'Password can only contain standard ASCII characters (no emoji or non-standard symbols)'
        return $Result
    }

    # Check for repeated characters (e.g., aaaa, 1111)
    if ($Password -match '(.)\1{3,}') {
        $Result.Valid = $false
        $Result.Message = 'Password must not contain 4 or more repeated characters in a row'
        return $Result
    }

    # Check for sequential characters (e.g., abcd, 1234)
    $sequences = @('abcdefghijklmnopqrstuvwxyz', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm', '0123456789')
    foreach ($seq in $sequences) {
        for ($i = 0; $i -le $seq.Length - 4; $i++) {
            $sub = $seq.Substring($i, 4)
            if ($Password.ToLower().Contains($sub)) {
                $Result.Valid = $false
                $Result.Message = 'Password must not contain 4 or more sequential characters'
                return $Result
            }
        }
    }

    $Result.Message = 'Password meets requirements'
    return $Result
}
