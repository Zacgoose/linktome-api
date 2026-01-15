function Invoke-AdminCreateSubAccount {
    <#
    .SYNOPSIS
        Create a new sub-account under the authenticated parent user.
    .DESCRIPTION
        Creates a new sub-account with limited permissions. The sub-account
        will inherit the parent's subscription tier but cannot login or manage
        sensitive settings.
    .ROLE
        manage:subaccounts
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata
    )
    
    $Body = $Request.Body
    
    try {
        # Get authenticated user ID (parent account)
        $ParentUserId = $Request.AuthenticatedUser.UserId
        if (-not $ParentUserId) {
            throw 'Authenticated user not found in request.'
        }
        
        # === Validate Required Fields ===
        if (-not $Body.email -or -not $Body.username) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Email and username are required" }
            }
        }
        
        if (-not (Test-EmailFormat -Email $Body.email)) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid email format" }
            }
        }
        
        if (-not (Test-UsernameFormat -Username $Body.username)) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid username format. Must be 3-30 characters, alphanumeric with hyphens and underscores." }
            }
        }
        
        # Get tables
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        
        # Get parent user to check user pack limits
        $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
        $ParentUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeParentId'" | Select-Object -First 1
        
        if (-not $ParentUser) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Parent user not found" }
            }
        }
        
        # Check user pack limit
        $UserPackLimit = if ($ParentUser.PSObject.Properties['UserPackLimit'] -and $ParentUser.UserPackLimit) {
            [int]$ParentUser.UserPackLimit
        } else {
            0
        }
        
        # Check if user pack is expired
        if ($ParentUser.PSObject.Properties['UserPackExpiresAt'] -and $ParentUser.UserPackExpiresAt) {
            try {
                $ExpiryDate = [DateTime]::Parse($ParentUser.UserPackExpiresAt, [System.Globalization.CultureInfo]::InvariantCulture)
                $Now = (Get-Date).ToUniversalTime()
                if ($ExpiryDate -lt $Now) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body = @{ error = "User pack has expired. Please renew to create sub-accounts." }
                    }
                }
            } catch {
                Write-Warning "Failed to parse UserPackExpiresAt date"
            }
        }
        
        if ($UserPackLimit -le 0) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{ error = "No user pack available. Please purchase a user pack to create sub-accounts." }
            }
        }
        
        # Count existing sub-accounts
        $ExistingSubAccounts = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId'"
        $CurrentCount = ($ExistingSubAccounts | Measure-Object).Count
        
        if ($CurrentCount -ge $UserPackLimit) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{ 
                    error = "Sub-account limit reached. Current: $CurrentCount, Max: $UserPackLimit"
                    currentCount = $CurrentCount
                    maxAllowed = $UserPackLimit
                }
            }
        }
        
        # Check if email already exists
        $SafeEmail = Protect-TableQueryValue -Value $Body.email.ToLower()
        $ExistingUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "PartitionKey eq '$SafeEmail'" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($ExistingUser) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Conflict
                Body = @{ error = "Email already exists" }
            }
        }
        
        # Check if username already exists
        $SafeUsername = Protect-TableQueryValue -Value $Body.username.ToLower()
        $ExistingUsername = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "Username eq '$SafeUsername'" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($ExistingUsername) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Conflict
                Body = @{ error = "Username already exists" }
            }
        }
        
        # Generate sub-account user ID
        $SubAccountUserId = New-Guid
        
        # Get parent subscription for inheritance
        $ParentSubscription = Get-UserSubscription -User $ParentUser
        
        # Create sub-account user entity
        $SubAccountUser = @{
            PartitionKey = $Body.email.ToLower()
            RowKey = $SubAccountUserId
            Username = $Body.username
            DisplayName = if ($Body.displayName) { $Body.displayName } else { $Body.username }
            Role = 'sub_account_user'
            IsSubAccount = $true
            AuthDisabled = $true
            SubscriptionTier = $ParentSubscription.EffectiveTier
            SubscriptionStatus = 'active'
            PasswordHash = ''  # No password for sub-accounts
            PasswordSalt = ''
        }
        
        # Add optional fields
        if ($Body.bio) { $SubAccountUser.Bio = $Body.bio }
        
        # Create user entity
        $NewUser = Add-LinkToMeAzDataTableEntity @UsersTable -Entity $SubAccountUser
        
        # Create relationship in SubAccounts table
        $Relationship = @{
            PartitionKey = $ParentUserId
            RowKey = $SubAccountUserId
            Type = if ($Body.type) { $Body.type } else { 'client' }
            Status = 'active'
            CreatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        
        Add-LinkToMeAzDataTableEntity @SubAccountsTable -Entity $Relationship | Out-Null
        
        # Write security event
        Write-SecurityEvent -EventType 'SubAccountCreated' -UserId $ParentUserId -AdditionalData (@{
            SubAccountUserId = $SubAccountUserId
            SubAccountEmail = $Body.email
            SubAccountUsername = $Body.username
        } | ConvertTo-Json -Depth 10)
        
        # Build response
        $Results = @{
            userId = $SubAccountUserId
            username = $NewUser.Username
            email = $NewUser.PartitionKey
            displayName = $NewUser.DisplayName
            isSubAccount = $true
            authDisabled = $true
            tier = $NewUser.SubscriptionTier
            createdAt = $Relationship.CreatedAt
            message = "Sub-account created successfully"
        }
        
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        Write-Error "Create sub-account error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to create sub-account"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
