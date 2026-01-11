# Backend Implementation Guide: Agency/Multi-Account Profiles

## Overview

This document provides detailed technical specifications for backend developers implementing the agency/multi-account profiles feature. It covers database schema, new endpoints, authentication changes, and security requirements.

---

## Database Schema Changes

### Option A: SubAccounts Table (Recommended)

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
- Notes (string, optional) - Additional notes
```

**Rationale**: 
- Clean separation of concerns
- Easy to query all sub-accounts for a parent: Filter by PartitionKey
- Easy to find parent for a sub-account: Filter by RowKey
- Doesn't clutter Users table
- Easier to add metadata specific to sub-account relationships

### Update Users Table

Add minimal marker fields to Users table:

```powershell
Users Table (additions):
- IsSubAccount (boolean, default: false)
- SubAccountCanLogin (boolean, default: false) - Future proofing
```

**Note**: `ParentAccountId` is stored in SubAccounts table, not Users table.

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

### 4. Get-SubAccountLimit.ps1

**Location**: `Modules/LinkTomeCore/Private/SubAccount/Get-SubAccountLimit.ps1`

```powershell
function Get-SubAccountLimit {
    <#
    .SYNOPSIS
        Get sub-account limit for a user's tier
    .DESCRIPTION
        Returns the maximum number of sub-accounts allowed for a given tier
    .PARAMETER Tier
        The subscription tier
    .OUTPUTS
        Integer - Max sub-accounts allowed (-1 for unlimited)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('free', 'pro', 'premium', 'enterprise')]
        [string]$Tier
    )
    
    $Limits = @{
        'free' = 0
        'pro' = 3
        'premium' = 10
        'enterprise' = -1  # Unlimited
    }
    
    return $Limits[$Tier]
}
```

---

## Update Get-TierFeatures.ps1

Add sub-account limits to tier features:

```powershell
# In Modules/LinkTomeCore/Private/Tier/Get-TierFeatures.ps1

# Add to each tier's limits hash:
'free' = @{
    # ... existing fields ...
    
    # Sub-account features
    maxSubAccounts = 0
    subAccountManagement = $false
}

'pro' = @{
    # ... existing fields ...
    
    # Sub-account features
    maxSubAccounts = 3
    subAccountManagement = $true
}

'premium' = @{
    # ... existing fields ...
    
    # Sub-account features
    maxSubAccounts = 10
    subAccountManagement = $true
}

'enterprise' = @{
    # ... existing fields ...
    
    # Sub-account features
    maxSubAccounts = -1  # Unlimited
    subAccountManagement = $true
}
```

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

## Update Authentication System

### 1. Update New-LinkToMeJWT.ps1

Modify JWT generation to support context:

```powershell
# In Modules/LinkTomeCore/Private/Auth/New-LinkToMeJWT.ps1

function New-LinkToMeJWT {
    param(
        [Parameter(Mandatory)]
        [object]$User,
        
        [Parameter()]
        [string]$ContextUserId = $null,
        
        [Parameter()]
        [string]$ContextUsername = $null
    )
    
    # ... existing code ...
    
    # Build payload
    $Payload = @{
        userId = $User.RowKey
        email = $User.PartitionKey
        username = $User.Username
        tier = $Subscription.EffectiveTier
        exp = $ExpirationTime
    }
    
    # Add context information if provided
    if ($ContextUserId -and $ContextUsername) {
        $Payload.contextUserId = $ContextUserId
        $Payload.contextUsername = $ContextUsername
        $Payload.isSubAccountContext = $true
    } else {
        $Payload.isSubAccountContext = $false
    }
    
    # ... rest of JWT generation ...
}
```

### 2. Update Get-UserFromRequest.ps1

Modify to extract context from JWT:

```powershell
# In Modules/LinkTomeCore/Private/Auth/Get-UserFromRequest.ps1

# After JWT validation, extract claims:

$Claims = $JwtPayload

# Standard fields
$UserId = $Claims.userId
$Email = $Claims.email
$Username = $Claims.username

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
        
        # Check tier and limits
        $Subscription = Get-UserSubscription -User $ParentUser
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
        
        # Check current count
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        $CurrentSubAccounts = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId' and Status eq 'active'"
        
        if ($TierFeatures.limits.maxSubAccounts -ne -1 -and $CurrentSubAccounts.Count -ge $TierFeatures.limits.maxSubAccounts) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{
                    error = "Sub-account limit reached. Your $($Subscription.EffectiveTier) plan allows up to $($TierFeatures.limits.maxSubAccounts) sub-accounts."
                    currentCount = $CurrentSubAccounts.Count
                    limit = $TierFeatures.limits.maxSubAccounts
                }
            }
        }
        
        # Check username uniqueness
        $ExistingUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "Username eq '$Username'"
        if ($ExistingUser.Count -gt 0) {
            throw "Username already taken"
        }
        
        # Create sub-account user
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
            IsSubAccount = $true
            SubAccountCanLogin = $false
            Roles = '["user"]'  # Sub-accounts get user role for permissions but can't login
            # No password fields - cannot login
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

## Permission System Updates

### Update Get-DefaultRolePermissions.ps1

Add new permissions:

```powershell
'user' = @(
    # ... existing permissions ...
    'read:subaccounts',
    'write:subaccounts',
    'delete:subaccounts',
    'switch:subaccounts'
)

# user_manager role should NOT have sub-account permissions
```

### New Permission Check Function

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
