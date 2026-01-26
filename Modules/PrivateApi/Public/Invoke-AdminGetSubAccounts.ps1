function Invoke-AdminGetSubAccounts {
    <#
    .SYNOPSIS
        List all sub-accounts for the authenticated parent user.
    .DESCRIPTION
        Returns a list of all sub-accounts created by the parent account,
        including statistics and quota information.
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
    
    try {
        # Get authenticated user ID (parent account)
        $ParentUserId = $Request.AuthenticatedUser.UserId
        if (-not $ParentUserId) {
            throw 'Authenticated user not found in request.'
        }
        
        # Get SubAccounts table
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        
        # Get parent user to check user pack limits
        $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
        $ParentUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeParentId'" | Select-Object -First 1
        
        if (-not $ParentUser) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Parent user not found" }
            }
        }
        
        $ParentSubscription = Get-UserSubscription -User $ParentUser
        $SubAccountLimit = $ParentSubscription.SubAccountLimit
        $HasAccess = $ParentSubscription.HasAccess
        
        # Get all sub-accounts for this parent (PartitionKey = ParentUserId)
        $SubAccountRelationships = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId'"
        
        # Build sub-account list with details
        $SubAccountsList = @()
        foreach ($relationship in $SubAccountRelationships) {
            $SubAccountId = $relationship.RowKey
            $SafeSubId = Protect-TableQueryValue -Value $SubAccountId
            
            # Get sub-account user details
            $SubAccountUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeSubId'" -ErrorAction SilentlyContinue | Select-Object -First 1
            
            if ($SubAccountUser) {
                $subAccountObj = [PSCustomObject]@{
                    userId = $SubAccountUser.RowKey
                    username = $SubAccountUser.Username
                    displayName = $SubAccountUser.DisplayName
                    type = if ($relationship.PSObject.Properties['Type'] -and $relationship.Type) { $relationship.Type } else { 'client' }
                    status = if ($relationship.PSObject.Properties['Status'] -and $relationship.Status) { $relationship.Status } else { 'active' }
                    createdAt = if ($relationship.PSObject.Properties['CreatedAt'] -and $relationship.CreatedAt) { $relationship.CreatedAt } else { $relationship.Timestamp }
                }
                
                # Add disabled flag if present
                if ($SubAccountUser.PSObject.Properties['Disabled']) {
                    $subAccountObj | Add-Member -NotePropertyName 'disabled' -NotePropertyValue ([bool]$SubAccountUser.Disabled) -Force
                }
                
                # Add disabled reason if present
                if ($SubAccountUser.PSObject.Properties['DisabledReason'] -and $SubAccountUser.DisabledReason) {
                    $subAccountObj | Add-Member -NotePropertyName 'disabledReason' -NotePropertyValue $SubAccountUser.DisabledReason -Force
                }
                
                $SubAccountsList += $subAccountObj
            }
        }
        
        # Calculate quota
        $usedSubAccounts = $SubAccountsList.Count
        $maxSubAccounts = if ($HasAccess) { $SubAccountLimit } else { 0 }
        $remainingSubAccounts = [Math]::Max(0, $maxSubAccounts - $usedSubAccounts)
        
        # Build response
        $Results = @{
            subAccounts = @($SubAccountsList)
            total = $usedSubAccounts
            limits = @{
                maxSubAccounts = $maxSubAccounts
                usedSubAccounts = $usedSubAccounts
                remainingSubAccounts = $remainingSubAccounts
                subscriptionQuantity = $ParentSubscription.SubscriptionQuantity
                hasAccess = $HasAccess
            }
        }
        
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        Write-Error "Get sub-accounts error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get sub-accounts"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
