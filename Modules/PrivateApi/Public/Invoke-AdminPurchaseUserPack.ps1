function Invoke-AdminPurchaseUserPack {
    <#
    .SYNOPSIS
        Purchase or update a user pack for sub-account management
    .DESCRIPTION
        Allows users to purchase or upgrade their user pack to create and manage sub-accounts.
        Automatically upgrades user role to 'agency_admin_user' to grant manage:subaccounts permission.
    .ROLE
        write:subscription
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
        # Get authenticated user ID
        $UserId = $Request.AuthenticatedUser.UserId
        if (-not $UserId) {
            throw 'Authenticated user not found in request.'
        }
        
        # === Validate Required Fields ===
        if (-not $Body.packType) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Pack type is required" }
            }
        }
        
        # Validate pack type
        $ValidPackTypes = @('starter', 'business', 'enterprise', 'none')
        if ($Body.packType -notin $ValidPackTypes) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Invalid pack type. Valid options are: starter, business, enterprise, none" }
            }
        }
        
        # Validate billing cycle is provided for paid packs
        if ($Body.packType -ne 'none' -and -not $Body.billingCycle) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Billing cycle is required for user pack purchases" }
            }
        }
        
        # Validate billing cycle if provided
        if ($Body.billingCycle) {
            $ValidCycles = @('monthly', 'annual')
            if ($Body.billingCycle -notin $ValidCycles) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Invalid billing cycle. Valid options are: monthly, annual" }
                }
            }
        }
        
        # Get users table
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        
        # Get user record
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Prevent sub-accounts from purchasing user packs
        if ($User.PSObject.Properties['IsSubAccount'] -and $User.IsSubAccount -eq $true) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{ error = "Sub-accounts cannot purchase user packs" }
            }
        }
        
        # Get current timestamp
        $Now = (Get-Date).ToUniversalTime()
        $NowString = $Now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        
        # Determine pack limit based on pack type
        $PackLimits = @{
            'none' = 0
            'starter' = 3
            'business' = 10
            'enterprise' = -1  # -1 = unlimited (or custom limit set by admin)
        }
        
        $PackLimit = $PackLimits[$Body.packType]
        
        # For enterprise, allow custom limit
        if ($Body.packType -eq 'enterprise' -and $Body.customLimit) {
            $PackLimit = [int]$Body.customLimit
        }
        
        # If downgrading to 'none', check if user has existing sub-accounts
        if ($Body.packType -eq 'none') {
            $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
            $ExistingSubAccounts = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeUserId'"
            $CurrentCount = ($ExistingSubAccounts | Measure-Object).Count
            
            if ($CurrentCount -gt 0) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ 
                        error = "Cannot cancel user pack while sub-accounts exist. Please delete all sub-accounts first."
                        currentSubAccounts = $CurrentCount
                    }
                }
            }
        }
        
        # Update user pack fields
        if (-not $User.PSObject.Properties['UserPackType']) {
            $User | Add-Member -NotePropertyName 'UserPackType' -NotePropertyValue $Body.packType -Force
        } else {
            $User.UserPackType = $Body.packType
        }
        
        if (-not $User.PSObject.Properties['UserPackLimit']) {
            $User | Add-Member -NotePropertyName 'UserPackLimit' -NotePropertyValue $PackLimit -Force
        } else {
            $User.UserPackLimit = $PackLimit
        }
        
        # Set purchased date if this is a new purchase (upgrading from 'none')
        $CurrentPackType = if ($User.PSObject.Properties['UserPackType']) { $User.UserPackType } else { 'none' }
        if ($CurrentPackType -eq 'none' -and $Body.packType -ne 'none') {
            if (-not $User.PSObject.Properties['UserPackPurchasedAt']) {
                $User | Add-Member -NotePropertyName 'UserPackPurchasedAt' -NotePropertyValue $NowString -Force
            } else {
                $User.UserPackPurchasedAt = $NowString
            }
        }
        
        # Calculate expiration date based on billing cycle
        if ($Body.packType -ne 'none' -and $Body.billingCycle) {
            $ExpiryDate = if ($Body.billingCycle -eq 'annual') {
                $Now.AddYears(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
            } else {
                $Now.AddMonths(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            
            if (-not $User.PSObject.Properties['UserPackExpiresAt']) {
                $User | Add-Member -NotePropertyName 'UserPackExpiresAt' -NotePropertyValue $ExpiryDate -Force
            } else {
                $User.UserPackExpiresAt = $ExpiryDate
            }
        } elseif ($Body.packType -eq 'none') {
            # Clear expiry date when cancelling
            if ($User.PSObject.Properties['UserPackExpiresAt']) {
                $User.UserPackExpiresAt = $null
            }
        }
        
        # === UPDATE USER ROLE ===
        # Upgrade to agency_admin_user if purchasing a pack
        # Downgrade to user if cancelling pack
        if ($Body.packType -ne 'none') {
            # Upgrade to agency_admin_user to grant manage:subaccounts permission
            if (-not $User.PSObject.Properties['Role']) {
                $User | Add-Member -NotePropertyName 'Role' -NotePropertyValue 'agency_admin_user' -Force
            } else {
                # Only upgrade if current role is 'user' or not set
                # Don't change if it's already 'user_manager' or other role
                if (-not $User.Role -or $User.Role -eq 'user') {
                    $User.Role = 'agency_admin_user'
                }
            }
        } else {
            # Downgrade to user when cancelling pack
            if ($User.PSObject.Properties['Role'] -and $User.Role -eq 'agency_admin_user') {
                $User.Role = 'user'
            }
        }
        
        # Update user entity
        Update-LinkToMeAzDataTableEntity @UsersTable -Entity $User | Out-Null
        
        # Write security event
        Write-SecurityEvent -EventType 'UserPackPurchased' -UserId $UserId -AdditionalData @{
            PackType = $Body.packType
            PackLimit = $PackLimit
            BillingCycle = $Body.billingCycle
            Role = $User.Role
            ExpiresAt = if ($User.PSObject.Properties['UserPackExpiresAt']) { $User.UserPackExpiresAt } else { $null }
        }
        
        # Build response
        $Results = @{
            userId = $UserId
            packType = $Body.packType
            packLimit = $PackLimit
            role = $User.Role
            expiresAt = if ($User.PSObject.Properties['UserPackExpiresAt']) { $User.UserPackExpiresAt } else { $null }
            message = if ($Body.packType -eq 'none') {
                "User pack cancelled successfully"
            } else {
                "User pack purchased successfully. You can now create up to $PackLimit sub-accounts."
            }
        }
        
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        Write-Error "Purchase user pack error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to purchase user pack"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
