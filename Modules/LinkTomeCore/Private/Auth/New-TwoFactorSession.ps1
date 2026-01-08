function New-TwoFactorSession {
    <#
    .SYNOPSIS
        Create a new 2FA session
    .DESCRIPTION
        Creates a new 2FA session in the TwoFactorSessions table
    .PARAMETER UserId
        The user ID
    .PARAMETER Method
        The 2FA method(s): 'email', 'totp', or 'both'
    .PARAMETER EmailCode
        The email code (optional, only for email method)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('email', 'totp', 'both')]
        [string]$Method,
        
        [Parameter(Mandatory = $false)]
        [string]$EmailCode
    )
    
    try {
        $Table = Get-LinkToMeTable -TableName 'TwoFactorSessions'
        
        # Generate unique session ID
        $SessionId = 'tfa-' + (New-Guid).ToString()
        
        # Calculate expiration (10 minutes from now)
        $ExpiresAt = (Get-Date).ToUniversalTime().AddMinutes(10)
        
        # Hash the email code if provided
        $HashedCode = $null
        if ($EmailCode) {
            $HashedCode = Get-StringHash -InputString $EmailCode
        }
        
        # Determine available methods
        $AvailableMethods = switch ($Method) {
            'email' { '["email"]' }
            'totp' { '["totp"]' }
            'both' { '["email","totp"]' }
        }
        
        $Session = @{
            PartitionKey = [string]$SessionId
            RowKey = [string]$UserId
            Method = [string]$Method
            AvailableMethods = [string]$AvailableMethods
            EmailCodeHash = if ($HashedCode) { [string]$HashedCode } else { [string]'' }
            AttemptsRemaining = [int]5
            CreatedAt = [datetime](Get-Date).ToUniversalTime()
            ExpiresAt = [datetime]$ExpiresAt
            LastResendAt = [datetime](Get-Date).ToUniversalTime()
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $Session -Force
        
        return @{
            SessionId = $SessionId
            ExpiresAt = $ExpiresAt
        }
    }
    catch {
        Write-Error "Failed to create 2FA session: $($_.Exception.Message)"
        throw
    }
}
