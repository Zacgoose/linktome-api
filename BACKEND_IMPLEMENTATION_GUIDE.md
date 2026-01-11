# Backend Implementation Guide: Agency/Multi-Account Profiles (Ultra-Simplified)

## Overview

This document provides detailed technical specifications for backend developers implementing the agency/multi-account profiles feature. 

**Key Simplification**: Sub-accounts are regular users in the Users table with `AuthDisabled = true` and `IsSubAccount = true`. They use existing tier, permission, and context systems. No special handling needed beyond:
1. Block auth for accounts with `AuthDisabled = true`
2. Create new role type with limited permissions
3. Track parent-child relationship in SubAccounts table

---

## Database Schema Changes (Ultra-Simplified)

### Option A: SubAccounts Table (Recommended)

**Purpose**: Only for tracking parent-child relationships. Sub-accounts are normal users otherwise.

Create a new table to track sub-account relationships:

```powershell
Table: SubAccounts
PartitionKey: ParentAccountId (parent user's UserId)
RowKey: SubAccountId (sub-account user's UserId)

Fields:
- ParentAccountId (string) - Parent user ID
- SubAccountId (string) - Sub-account user ID  
- SubAccountType (string) - 'agency_client', 'brand', 'project', 'other'
- Status (string) - 'active', 'suspended', 'deleted'
- CreatedAt (datetime) - ISO 8601 format
- CreatedByUserId (string) - Who created this (for audit)
```

**Rationale**: 
- Clean separation - relationship tracking only
- Sub-accounts are full users with all normal fields
- Easy to query relationships both ways
- Doesn't clutter Users table

### Update Users Table

Add minimal flags to Users table:

```powershell
Users Table (additions):
- IsSubAccount (boolean, default: false)
  - Marks this as a sub-account
  
- AuthDisabled (boolean, default: false)
  - When true, blocks ALL authentication
  - Enforced in login endpoint and API key validation
```

**Note**: Sub-accounts have their own tier, features, pages, links, etc. They're normal users.

### Query Patterns

```powershell
# Get all sub-accounts for a parent
$SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
$SafeParentId = Protect-TableQueryValue -Value $ParentUserId
$SubAccounts = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId' and Status eq 'active'"

# Get parent for a sub-account
$SafeSubAccountId = Protect-TableQueryValue -Value $SubAccountId
$Relationship = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "RowKey eq '$SafeSubAccountId'" | Select-Object -First 1
$ParentAccountId = $Relationship.PartitionKey

# Check if user is a sub-account
$UsersTable = Get-LinkToMeTable -TableName 'Users'
$SafeUserId = Protect-TableQueryValue -Value $UserId
$User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
if ($User.IsSubAccount) {
    # Get parent
    $Parent = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "RowKey eq '$UserId'" | Select-Object -First 1
}
```

---

## New Helper Functions

### 1. Get-SubAccountOwner.ps1

**Location**: `Modules/LinkTomeCore/Private/SubAccount/Get-SubAccountOwner.ps1`

```powershell
function Get-SubAccountOwner {
    <#
    .SYNOPSIS
        Get the parent account for a sub-account
    .DESCRIPTION
        Looks up the parent account ID for a given sub-account.
        Returns null if the user is not a sub-account.
    .PARAMETER SubAccountId
        The sub-account user ID
    .OUTPUTS
        String - Parent account user ID, or $null if not a sub-account
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubAccountId
    )
    
    try {
        # Check Users table first
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeSubAccountId = Protect-TableQueryValue -Value $SubAccountId
        $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeSubAccountId'" | Select-Object -First 1
        
        if (-not $User) {
            Write-Warning "User not found: $SubAccountId"
            return $null
        }
        
        if (-not $User.IsSubAccount) {
            # Not a sub-account, no parent
            return $null
        }
        
        # Look up relationship in SubAccounts table
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        $Relationship = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "RowKey eq '$SafeSubAccountId' and Status eq 'active'" | Select-Object -First 1
        
        if (-not $Relationship) {
            Write-Warning "No active parent relationship found for sub-account: $SubAccountId"
            return $null
        }
        
        return $Relationship.PartitionKey
    } catch {
        Write-Error "Error getting sub-account owner: $($_.Exception.Message)"
        return $null
    }
}
```

### 2. Test-SubAccountOwnership.ps1

**Location**: `Modules/LinkTomeCore/Private/SubAccount/Test-SubAccountOwnership.ps1`

```powershell
function Test-SubAccountOwnership {
    <#
    .SYNOPSIS
        Verify that a user owns a sub-account
    .DESCRIPTION
        Checks if the specified parent user ID owns the given sub-account.
        Used for authorization checks.
    .PARAMETER ParentUserId
        The parent account user ID
    .PARAMETER SubAccountId
        The sub-account user ID to verify
    .OUTPUTS
        Boolean - $true if parent owns sub-account, $false otherwise
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ParentUserId,
        
        [Parameter(Mandatory)]
        [string]$SubAccountId
    )
    
    try {
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
        $SafeSubAccountId = Protect-TableQueryValue -Value $SubAccountId
        
        # Query for this specific relationship
        $Relationship = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId' and RowKey eq '$SafeSubAccountId' and Status eq 'active'"
        
        return ($Relationship.Count -gt 0)
    } catch {
        Write-Error "Error testing sub-account ownership: $($_.Exception.Message)"
        return $false
    }
}
```

### 3. Get-SubAccountList.ps1

**Location**: `Modules/LinkTomeCore/Private/SubAccount/Get-SubAccountList.ps1`

```powershell
function Get-SubAccountList {
    <#
    .SYNOPSIS
        Get all sub-accounts for a parent user
    .DESCRIPTION
        Returns list of sub-accounts with user details and statistics
    .PARAMETER ParentUserId
        The parent account user ID
    .PARAMETER IncludeStats
        Include page/link counts (slower query)
    .OUTPUTS
        Array of sub-account objects
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ParentUserId,
        
        [Parameter()]
        [bool]$IncludeStats = $false
    )
    
    try {
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        
        $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
        
        # Get all active sub-account relationships
        $Relationships = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId' and Status eq 'active'"
        
        $SubAccounts = @()
        
        foreach ($Relationship in $Relationships) {
            $SubAccountId = $Relationship.RowKey
            $SafeSubAccountId = Protect-TableQueryValue -Value $SubAccountId
            
            # Get user details
            $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeSubAccountId'" | Select-Object -First 1
            
            if (-not $User) {
                Write-Warning "Sub-account user not found: $SubAccountId"
                continue
            }
            
            $SubAccount = @{
                userId = $SubAccountId
                username = $User.Username
                displayName = $User.DisplayName
                email = $User.PartitionKey
                type = $Relationship.SubAccountType
                status = $Relationship.Status
                createdAt = $Relationship.CreatedAt
            }
            
            # Add statistics if requested
            if ($IncludeStats) {
                $PagesTable = Get-LinkToMeTable -TableName 'Pages'
                $LinksTable = Get-LinkToMeTable -TableName 'Links'
                
                $Pages = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeSubAccountId'"
                $SubAccount.pagesCount = $Pages.Count
                
                $Links = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeSubAccountId'"
                $SubAccount.linksCount = $Links.Count
            }
            
            $SubAccounts += $SubAccount
        }
        
        return $SubAccounts
    } catch {
        Write-Error "Error getting sub-account list: $($_.Exception.Message)"
        return @()
    }
}
```

### 4. Get-UserPackLimit.ps1

**Location**: `Modules/LinkTomeCore/Private/SubAccount/Get-UserPackLimit.ps1`

```powershell
function Get-UserPackLimit {
    <#
    .SYNOPSIS
        Get sub-account limit based on user's purchased user pack
    .DESCRIPTION
        Returns the maximum number of sub-accounts allowed based on the user's purchased user pack.
        This is separate from tier features and must be purchased as an add-on.
    .PARAMETER User
        The user object
    .OUTPUTS
        Integer - Max sub-accounts allowed (-1 for unlimited)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$User
    )
    
    # Get user pack type from user object
    $UserPackType = if ($User.PSObject.Properties['UserPackType'] -and $User.UserPackType) { 
        $User.UserPackType 
    } else { 
        $null 
    }
    
    # Check if user pack is expired
    if ($User.PSObject.Properties['UserPackExpiresAt'] -and $User.UserPackExpiresAt) {
        $ExpiryDate = [DateTime]::Parse($User.UserPackExpiresAt, [System.Globalization.CultureInfo]::InvariantCulture)
        $Now = (Get-Date).ToUniversalTime()
        if ($ExpiryDate -lt $Now) {
            Write-Warning "User pack expired for user: $($User.RowKey)"
            return 0
        }
    }
    
    # Define pack limits
    $PackLimits = @{
        $null = 0           # No pack purchased
        'starter' = 3       # Starter pack: 3 sub-accounts
        'business' = 10     # Business pack: 10 sub-accounts
        'enterprise' = -1   # Enterprise pack: Unlimited
    }
    
    return $PackLimits[$UserPackType]
}
```

---

## Update Users Table for User Packs

Add user pack fields to Users table:

```powershell
# In Users table schema
Users Table (additional fields):
- UserPackType (string, nullable)
  - Values: null, 'starter', 'business', 'enterprise'
  - NULL = no pack purchased, cannot create sub-accounts

- UserPackLimit (integer, default: 0)
  - Maximum sub-accounts based on pack: 0, 3, 10, -1 (unlimited)
  - Redundant but useful for quick checks

- UserPackPurchasedAt (datetime, nullable)
  - When the user pack was first purchased

- UserPackExpiresAt (datetime, nullable)
  - Expiration date for the user pack (monthly/annual billing)
  - Check this before allowing sub-account creation
```

**Note**: User packs are independent of base subscription tiers. A Free tier user can purchase a user pack to create sub-accounts.

---

## Update Get-UserSubscription.ps1

Add sub-account tier inheritance logic:

```powershell
# In Modules/LinkTomeCore/Private/Subscription/Get-UserSubscription.ps1

# Add after line 17 (after parameter validation):

# Check if this is a sub-account - if so, get parent's subscription
if ($User.IsSubAccount -eq $true) {
    $ParentUserId = Get-SubAccountOwner -SubAccountId $User.RowKey
    
    if ($ParentUserId) {
        # Get parent user
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
        $ParentUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeParentId'" | Select-Object -First 1
        
        if ($ParentUser) {
            # Recursively get parent's subscription
            # This handles nested sub-accounts if we ever support that
            $ParentSubscription = Get-UserSubscription -User $ParentUser
            
            # Add flag to indicate this is inherited
            $ParentSubscription.IsInherited = $true
            $ParentSubscription.InheritedFromUserId = $ParentUserId
            
            return $ParentSubscription
        } else {
            Write-Warning "Parent user not found for sub-account: $($User.RowKey)"
        }
    } else {
        Write-Warning "No parent found for sub-account: $($User.RowKey)"
    }
}

# Continue with normal subscription logic for non-sub-accounts...
```

---

## Update Authentication System (Simplified)

### 1. Block Authentication for AuthDisabled Accounts

Simple check in login and API key validation:

```powershell
# In Modules/PublicApi/Public/Invoke-PublicLogin.ps1

# After fetching user but before password validation:

if ($UserData.AuthDisabled -eq $true) {
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Body = @{
            error = "Authentication is disabled for this account"
            code = "AUTH_DISABLED"
        }
    }
}
```

```powershell
# In API key validation (Get-ApiKeyFromRequest.ps1 or similar)

# After fetching user by API key:

if ($User.AuthDisabled -eq $true) {
    return @{
        IsValid = $false
        Error = "Authentication is disabled for this account"
    }
}
```

**That's it**: One check blocks all auth methods (login, API keys, password reset, etc.)

### 2. Use Existing Context Mechanism

**No changes needed** to JWT or context switching. The codebase already has:
- `Get-UserAuthContext.ps1` - Gets user context
- Context switching between users
- Permission validation per user

**Just leverage it**:
1. Parent switches to sub-account user (existing mechanism)
2. Sub-account user has limited permissions (new role type)
3. Sub-account cannot auth directly (`AuthDisabled = true`)

---

# Context fields
$IsSubAccountContext = $Claims.isSubAccountContext -eq $true
$ContextUserId = if ($IsSubAccountContext) { $Claims.contextUserId } else { $UserId }
$ContextUsername = if ($IsSubAccountContext) { $Claims.contextUsername } else { $Username }

# Return user object with context
return @{
    UserId = $UserId                      # Parent user (for authentication)
    Email = $Email
    Username = $Username
    ContextUserId = $ContextUserId        # Sub-account (for operations)
    ContextUsername = $ContextUsername
    IsSubAccountContext = $IsSubAccountContext
    # ... other fields ...
}
```

### 3. Block Sub-Account Login

Update login endpoint to reject sub-account logins:

```powershell
# In Modules/PublicApi/Public/Invoke-PublicLogin.ps1

# After fetching user but before password validation:

if ($UserData.IsSubAccount -eq $true) {
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Body = @{
            error = "This account cannot login directly. Please login to the parent account and switch context."
            code = "SUB_ACCOUNT_LOGIN_BLOCKED"
        }
    }
}
```

---

## New API Endpoints

### 1. Invoke-AdminGetSubAccounts.ps1

**Location**: `Modules/PrivateApi/Public/Invoke-AdminGetSubAccounts.ps1`

```powershell
function Invoke-AdminGetSubAccounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:subaccounts
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    
    try {
        # Get user to check tier
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Get subscription to check tier
        $Subscription = Get-UserSubscription -User $User
        
        # Check if tier supports sub-accounts
        $TierFeatures = Get-TierFeatures -Tier $Subscription.EffectiveTier
        if ($TierFeatures.limits.maxSubAccounts -eq 0) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{
                    error = "Sub-accounts are not available on your current plan. Upgrade to Pro or higher."
                    upgradeRequired = $true
                    currentTier = $Subscription.EffectiveTier
                    feature = "subAccounts"
                }
            }
        }
        
        # Get sub-accounts
        $SubAccounts = Get-SubAccountList -ParentUserId $UserId -IncludeStats $true
        
        $Results = @{
            subAccounts = $SubAccounts
            total = $SubAccounts.Count
            limit = $TierFeatures.limits.maxSubAccounts
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get sub-accounts error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get sub-accounts"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
```

### 2. Invoke-AdminCreateSubAccount.ps1

**Location**: `Modules/PrivateApi/Public/Invoke-AdminCreateSubAccount.ps1`

```powershell
function Invoke-AdminCreateSubAccount {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:subaccounts
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $ParentUserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    
    try {
        # Parse request body
        $Username = $Request.Body.username
        $Email = $Request.Body.email
        $DisplayName = $Request.Body.displayName
        $Bio = $Request.Body.bio
        $SubAccountType = $Request.Body.type
        
        # Validation
        if (-not $Username -or -not $Email -or -not $DisplayName -or -not $SubAccountType) {
            throw "Missing required fields: username, email, displayName, type"
        }
        
        # Validate username format
        if (-not ($Username -match '^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$')) {
            throw "Invalid username format. Use 3-30 lowercase letters, numbers, hyphens. Cannot start/end with hyphen."
        }
        
        # Validate email
        if (-not ($Email -match '^[\w\.-]+@[\w\.-]+\.\w+$')) {
            throw "Invalid email format"
        }
        
        # Validate type
        $ValidTypes = @('agency_client', 'brand', 'project', 'other')
        if ($ValidTypes -notcontains $SubAccountType) {
            throw "Invalid type. Must be one of: $($ValidTypes -join ', ')"
        }
        
        # Get parent user
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
        $ParentUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeParentId'" | Select-Object -First 1
        
        if (-not $ParentUser) {
            throw "Parent user not found"
        }
        
        # Check user pack and limits
        $UserPackLimit = Get-UserPackLimit -User $ParentUser
        
        if ($UserPackLimit -eq 0) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{
                    error = "You need to purchase a user pack to create sub-accounts. Available packs: Starter (3 users), Business (10 users), Enterprise (custom)."
                    upgradeRequired = $true
                    feature = "subAccounts"
                    userPackRequired = $true
                }
            }
        }
        
        # Check current count against pack limit
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        $CurrentSubAccounts = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId' and Status eq 'active'"
        
        if ($UserPackLimit -ne -1 -and $CurrentSubAccounts.Count ->= $UserPackLimit) {
            $PackName = switch ($ParentUser.UserPackType) {
                'starter' { 'Starter' }
                'business' { 'Business' }
                'enterprise' { 'Enterprise' }
                default { 'current' }
            }
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{
                    error = "Sub-account limit reached. Your $PackName pack allows up to $UserPackLimit sub-accounts."
                    currentCount = $CurrentSubAccounts.Count
                    limit = $UserPackLimit
                    userPack = $ParentUser.UserPackType
                }
            }
        }
        
        # Check username uniqueness
        $ExistingUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "Username eq '$Username'"
        if ($ExistingUser.Count -gt 0) {
            throw "Username already taken"
        }
        
        # Create sub-account user (as a normal user with flags)
        $SubAccountId = 'user-' + (New-Guid).ToString()
        $EmailLower = $Email.ToLower()
        
        $SubAccountUser = @{
            PartitionKey = $EmailLower
            RowKey = $SubAccountId
            Username = $Username
            DisplayName = $DisplayName
            Bio = if ($Bio) { $Bio } else { '' }
            Avatar = "https://ui-avatars.com/api/?name=$([uri]::EscapeDataString($DisplayName))&size=200"
            IsActive = $true
            
            # Sub-account specific flags
            IsSubAccount = $true
            AuthDisabled = $true
            
            # Normal user fields (sub-account has its own tier, features, etc.)
            Roles = '["sub_account_user"]'  # New role with limited permissions
            SubscriptionTier = 'free'       # Or inherit from parent
            SubscriptionStatus = 'active'
            
            # No password fields - auth is disabled
        }
        
        Add-LinkToMeAzDataTableEntity @UsersTable -Entity $SubAccountUser
        
        # Create relationship in SubAccounts table
        $Now = (Get-Date).ToUniversalTime().ToString('o')
        $Relationship = @{
            PartitionKey = $ParentUserId
            RowKey = $SubAccountId
            ParentAccountId = $ParentUserId
            SubAccountId = $SubAccountId
            SubAccountType = $SubAccountType
            Status = 'active'
            CreatedAt = $Now
            CreatedByUserId = $ParentUserId
        }
        
        Add-LinkToMeAzDataTableEntity @SubAccountsTable -Entity $Relationship
        
        # Log security event
        Write-SecurityEvent -EventType 'SubAccountCreated' -UserId $ParentUserId -Details @{
            subAccountId = $SubAccountId
            username = $Username
            type = $SubAccountType
        }
        
        $Results = @{
            message = "Sub-account created successfully"
            subAccount = @{
                userId = $SubAccountId
                username = $Username
                email = $EmailLower
                displayName = $DisplayName
                type = $SubAccountType
            }
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Create sub-account error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to create sub-account"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
```

### 3. Invoke-AdminSwitchContext.ps1

**Location**: `Modules/PrivateApi/Public/Invoke-AdminSwitchContext.ps1`

```powershell
function Invoke-AdminSwitchContext {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        switch:subaccounts
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $ParentUserId = $Request.AuthenticatedUser.UserId
    $TargetUserId = $Request.Body.userId
    
    try {
        # Get parent user
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
        $ParentUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeParentId'" | Select-Object -First 1
        
        if (-not $ParentUser) {
            throw "User not found"
        }
        
        # If target is null or empty, switch back to parent
        if (-not $TargetUserId -or $TargetUserId -eq $ParentUserId) {
            # Generate standard JWT for parent
            $Token = New-LinkToMeJWT -User $ParentUser
            
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body = @{
                    accessToken = $Token
                    context = @{
                        parentUserId = $ParentUserId
                        contextUserId = $ParentUserId
                        contextUsername = $ParentUser.Username
                        isSubAccountContext = $false
                    }
                }
            }
        }
        
        # Verify ownership
        $IsOwner = Test-SubAccountOwnership -ParentUserId $ParentUserId -SubAccountId $TargetUserId
        if (-not $IsOwner) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{
                    error = "You do not have permission to manage this sub-account"
                    code = "FORBIDDEN"
                }
            }
        }
        
        # Get sub-account user
        $SafeTargetId = Protect-TableQueryValue -Value $TargetUserId
        $SubAccountUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeTargetId'" | Select-Object -First 1
        
        if (-not $SubAccountUser) {
            throw "Sub-account not found"
        }
        
        # Check if sub-account is active
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        $Relationship = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId' and RowKey eq '$SafeTargetId'" | Select-Object -First 1
        
        if ($Relationship.Status -ne 'active') {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{
                    error = "This sub-account is not active"
                    status = $Relationship.Status
                }
            }
        }
        
        # Generate context JWT
        $Token = New-LinkToMeJWT -User $ParentUser -ContextUserId $TargetUserId -ContextUsername $SubAccountUser.Username
        
        # Log security event
        Write-SecurityEvent -EventType 'ContextSwitch' -UserId $ParentUserId -Details @{
            targetUserId = $TargetUserId
            targetUsername = $SubAccountUser.Username
        }
        
        $Results = @{
            accessToken = $Token
            context = @{
                parentUserId = $ParentUserId
                contextUserId = $TargetUserId
                contextUsername = $SubAccountUser.Username
                isSubAccountContext = $true
            }
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Switch context error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to switch context"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
```

---

## Update Existing Endpoints

### Pattern for Context-Aware Endpoints

All admin endpoints that manage user data should use `ContextUserId` instead of `UserId`:

```powershell
# OLD (before context support):
$UserId = $Request.AuthenticatedUser.UserId

# NEW (with context support):
$UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
```

**Affected Endpoints**:
- Invoke-AdminGetProfile.ps1
- Invoke-AdminUpdateProfile.ps1
- Invoke-AdminGetLinks.ps1
- Invoke-AdminUpdateLinks.ps1
- Invoke-AdminGetPages.ps1
- Invoke-AdminCreatePage.ps1
- Invoke-AdminUpdatePage.ps1
- Invoke-AdminDeletePage.ps1
- Invoke-AdminGetAppearance.ps1
- Invoke-AdminUpdateAppearance.ps1
- Invoke-AdminGetAnalytics.ps1
- Invoke-AdminGetShortLinks.ps1
- Invoke-AdminUpdateShortLinks.ps1

### Endpoints to Block in Sub-Account Context

These endpoints should return 403 Forbidden when `IsSubAccountContext = true`:

```powershell
# Add at start of function:
if ($Request.AuthenticatedUser.IsSubAccountContext) {
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Body = @{
            error = "This operation is not available in sub-account context. Switch to parent account."
            code = "CONTEXT_RESTRICTED"
        }
    }
}
```

**Affected Endpoints**:
- Invoke-Admin2fatokensetup.ps1 (all 2FA operations)
- Invoke-AdminApikeysCreate.ps1
- Invoke-AdminApikeysList.ps1
- Invoke-AdminApikeysDelete.ps1
- Invoke-AdminUpdatePassword.ps1
- Invoke-AdminUpdateEmail.ps1
- Invoke-AdminUpdatePhone.ps1
- Invoke-AdminGetSubscription.ps1
- Invoke-AdminUpgradeSubscription.ps1
- Invoke-AdminCancelSubscription.ps1
- Invoke-AdminUserManagerInvite.ps1
- Invoke-AdminUserManagerList.ps1
- Invoke-AdminUserManagerRespond.ps1

---

## Permission System Updates (Simplified)

### Understanding Existing Permission System

The codebase uses `.ROLE` annotations in each endpoint to specify required permissions. For example:

```powershell
function Invoke-AdminApikeysCreate {
    <#
    .ROLE
        create:apiauth
    #>
    # ...
}
```

The system checks these permissions via the existing `Get-DefaultRolePermissions.ps1` function.

### Current Permission Mapping

**Existing permissions fall into categories:**

**Auth Management** (should be restricted for sub-accounts):
- `write:2fauth` - Manage 2FA setup
- `read:apiauth`, `create:apiauth`, `update:apiauth`, `delete:apiauth` - Manage API keys
- `write:password`, `write:email`, `write:phone` - Change credentials

**Billing Management** (should be restricted for sub-accounts):
- `read:subscription`, `write:subscription` - View/manage subscription

**User Management** (should be restricted for sub-accounts):
- `manage:users` - Manage users
- `invite:user_manager`, `list:user_manager`, `remove:user_manager`, `respond:user_manager` - User manager operations

**Content Management** (should be allowed for sub-accounts):
- `read:dashboard` - View dashboard
- `read:profile`, `write:profile` - Manage profile
- `read:links`, `write:links` - Manage links
- `read:pages`, `write:pages` - Manage pages
- `read:appearance`, `write:appearance` - Manage appearance
- `read:analytics` - View analytics
- `read:shortlinks`, `write:shortlinks` - Manage short links

### Add New Role Type with Limited Permissions

Update `Get-DefaultRolePermissions.ps1` to add new role:

```powershell
function Get-DefaultRolePermissions {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('user', 'user_manager', 'sub_account_user')]  # Add sub_account_user
        [string]$Role
    )
    
    $RolePermissions = @{
        'user' = @(
            # All existing permissions (unchanged)
            'read:dashboard',
            'write:2fauth',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:pages',
            'write:pages',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:users',
            'manage:users',
            'invite:user_manager',
            'list:user_manager',
            'remove:user_manager',
            'respond:user_manager',
            'read:apiauth',
            'create:apiauth',
            'update:apiauth',
            'delete:apiauth',
            'write:password',
            'write:email',
            'write:phone',
            'read:subscription',
            'write:subscription',
            'read:usersettings',
            'read:shortlinks',
            'write:shortlinks'
        )
        
        'user_manager' = @(
            # Existing limited permissions (unchanged)
            'read:dashboard',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:pages',
            'write:pages',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:shortlinks',
            'write:shortlinks'
        )
        
        'sub_account_user' = @(
            # Content management ONLY (same as user_manager but for sub-accounts)
            'read:dashboard',
            'read:profile',
            'write:profile',
            'read:links',
            'write:links',
            'read:pages',
            'write:pages',
            'read:appearance',
            'write:appearance',
            'read:analytics',
            'read:shortlinks',
            'write:shortlinks'
            
            # EXCLUDED permissions (sub-accounts cannot):
            # - write:2fauth (manage 2FA)
            # - read/create/update/delete:apiauth (manage API keys)
            # - write:password, write:email, write:phone (change credentials)
            # - read/write:subscription (manage subscription)
            # - manage:users, invite/list/remove/respond:user_manager (user management)
        )
    }
    
    return $RolePermissions[$Role]
}
```

### Endpoints Automatically Restricted for Sub-Accounts

Because `sub_account_user` role lacks these permissions, these endpoints will automatically be blocked by existing permission validation:

**Auth Management Endpoints** (require permissions sub-accounts don't have):
- `/admin/2fatokensetup` - Requires `write:2fauth`
- `/admin/apikeys/*` - Require `read/create/update/delete:apiauth`
- `/admin/updatePassword` - Requires `write:password`
- `/admin/updateEmail` - Requires `write:email`
- `/admin/updatePhone` - Requires `write:phone`

**Billing Management Endpoints** (require permissions sub-accounts don't have):
- `/admin/getSubscription` - Requires `read:subscription`
- `/admin/upgradeSubscription` - Requires `write:subscription`
- `/admin/cancelSubscription` - Requires `write:subscription`

**User Management Endpoints** (require permissions sub-accounts don't have):
- `/admin/userManagerInvite` - Requires `invite:user_manager`
- `/admin/userManagerList` - Requires `list:user_manager`
- `/admin/userManagerRemove` - Requires `remove:user_manager`
- `/admin/userManagerRespond` - Requires `respond:user_manager`

### No Code Changes to Endpoints Needed

**Key Point**: The existing permission validation system automatically blocks sub-accounts from restricted endpoints. No changes to individual endpoint code needed - just add the new role to `Get-DefaultRolePermissions.ps1`.

The system already validates permissions before executing endpoint logic, so sub-accounts will receive 403 Forbidden responses when attempting to access restricted endpoints.

**Location**: `Modules/LinkTomeCore/Private/Auth/Test-SubAccountContextPermission.ps1`

```powershell
function Test-SubAccountContextPermission {
    <#
    .SYNOPSIS
        Test if an operation is allowed in sub-account context
    .DESCRIPTION
        Some operations are restricted when in sub-account context
    #>
    param(
        [Parameter(Mandatory)]
        [bool]$IsSubAccountContext,
        
        [Parameter(Mandatory)]
        [string]$Operation
    )
    
    # Operations that are blocked in sub-account context
    $RestrictedOperations = @(
        'write:2fauth',
        'read:apiauth',
        'create:apiauth',
        'update:apiauth',
        'delete:apiauth',
        'write:password',
        'write:email',
        'write:phone',
        'read:subscription',
        'write:subscription',
        'invite:user_manager',
        'list:user_manager',
        'remove:user_manager',
        'respond:user_manager'
    )
    
    if ($IsSubAccountContext -and $RestrictedOperations -contains $Operation) {
        return $false
    }
    
    return $true
}
```

---

## Security Event Logging

Add new event types to `Write-SecurityEvent`:

```powershell
# New event types:
- 'SubAccountCreated'
- 'SubAccountUpdated'
- 'SubAccountDeleted'
- 'SubAccountSuspended'
- 'ContextSwitch'
- 'SubAccountLoginAttempt' (blocked)
```

Example:

```powershell
Write-SecurityEvent -EventType 'SubAccountCreated' -UserId $ParentUserId -Details @{
    subAccountId = $SubAccountId
    username = $Username
    type = $SubAccountType
}

Write-SecurityEvent -EventType 'ContextSwitch' -UserId $ParentUserId -Details @{
    fromContext = 'parent'
    toContext = $TargetUserId
    targetUsername = $SubAccountUsername
}
```

---

## Testing Strategy

### Unit Tests

Create test files:
- `Get-SubAccountOwner.Tests.ps1`
- `Test-SubAccountOwnership.Tests.ps1`
- `Get-SubAccountLimit.Tests.ps1`
- `Get-UserSubscription.Tests.ps1` (update)

### Integration Tests

Test scenarios:
1. Create sub-account successfully
2. Create sub-account beyond limit
3. Switch context and create pages
4. Attempt restricted operations in context
5. Tier inheritance
6. Login blocking for sub-accounts

### Test Data Setup

Update `Tools/Seed-DevData.ps1`:

```powershell
# Add after creating test users:

# Upgrade demo user to Pro tier
$DemoUser.SubscriptionTier = 'pro'
$DemoUser.SubscriptionStatus = 'active'
Add-LinkToMeAzDataTableEntity @UsersTable -Entity $DemoUser -Force

# Create sub-accounts for demo user
$SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'

$SubAccount1Id = 'user-' + (New-Guid).ToString()
$SubAccount1 = @{
    PartitionKey = 'client1@demo.com'
    RowKey = $SubAccount1Id
    Username = 'democlient1'
    DisplayName = 'Demo Client 1'
    Bio = 'First demo client sub-account'
    Avatar = 'https://ui-avatars.com/api/?name=Demo+Client+1&size=200'
    IsActive = $true
    IsSubAccount = $true
    SubAccountCanLogin = $false
    Roles = '["user"]'
}

Add-LinkToMeAzDataTableEntity @UsersTable -Entity $SubAccount1

$Relationship1 = @{
    PartitionKey = $DemoUser.UserId
    RowKey = $SubAccount1Id
    ParentAccountId = $DemoUser.UserId
    SubAccountId = $SubAccount1Id
    SubAccountType = 'agency_client'
    Status = 'active'
    CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
    CreatedByUserId = $DemoUser.UserId
}

Add-LinkToMeAzDataTableEntity @SubAccountsTable -Entity $Relationship1
```

---

## Migration Steps

### Phase 1: Database Setup
1. Create `SubAccounts` table in Azure Table Storage
2. Add `IsSubAccount` field to existing Users (default: false)
3. Run migration script to ensure all existing users have field

### Phase 2: Core Functions
1. Implement helper functions
2. Update `Get-UserSubscription.ps1`
3. Update `Get-TierFeatures.ps1`
4. Update JWT generation

### Phase 3: New Endpoints
1. Implement create/list/update/delete endpoints
2. Implement context switching endpoint
3. Add permission checks

### Phase 4: Endpoint Updates
1. Update all admin endpoints for context support
2. Add restrictions to blocked endpoints
3. Update login endpoint

### Phase 5: Testing
1. Unit tests
2. Integration tests
3. Manual testing
4. Security testing

---

## Security Checklist

- [ ] Sub-accounts cannot login (validated in login endpoint)
- [ ] Ownership verified on all sub-account operations
- [ ] Context validated on every request
- [ ] JWT signature verified
- [ ] Restricted operations blocked in context
- [ ] Tier limits enforced server-side
- [ ] All operations logged to security events
- [ ] Input validation on all fields
- [ ] SQL injection prevention (table query protection)
- [ ] Rate limiting applied
- [ ] Parent deletion requires sub-account deletion first

---

## Performance Considerations

### Optimize Queries

1. **Use Indexes**:
   - PartitionKey queries are fast
   - RowKey queries are fast
   - Avoid filter-only queries when possible

2. **Cache Sub-Account List**:
   - Cache for duration of JWT (24 hours)
   - Invalidate on create/delete

3. **Lazy Load Statistics**:
   - Don't fetch page/link counts by default
   - Only when explicitly requested

4. **Batch Operations**:
   - Consider batch read for multiple sub-accounts
   - Use async queries where possible

---

## Open Issues for Discussion

1. **Nested Sub-Accounts**: Should we support sub-accounts of sub-accounts?
   - Recommendation: No for MVP
   
2. **Username Changes**: Allow username changes for sub-accounts?
   - Recommendation: Yes, with cooldown period
   
3. **Email Notifications**: Where to send?
   - Recommendation: Parent's email with sub-account context

4. **Analytics Aggregation**: Separate or combined?
   - Recommendation: Separate with optional aggregate view

5. **API Key Context**: Can parent's API keys operate in sub-account context?
   - Recommendation: No, must use JWT and switchContext

---

## Next Steps

1. **Review this guide** with backend team
2. **Create database migration script**
3. **Implement Phase 1** (helper functions)
4. **Implement Phase 2** (new endpoints)
5. **Coordinate with frontend team** on API contracts
6. **Begin testing** as each phase completes

---

**Document Version**: 1.0  
**Date**: January 11, 2026  
**Audience**: Backend Development Team  
**Related**: `AGENCY_MULTI_ACCOUNT_PLANNING.md`, `FRONTEND_COORDINATION_MULTI_ACCOUNT.md`
