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
        
        # Get user pack limits
        $UserPackType = if ($ParentUser.PSObject.Properties['UserPackType'] -and $ParentUser.UserPackType) {
            $ParentUser.UserPackType
        } else {
            'none'
        }
        
        $UserPackLimit = if ($ParentUser.PSObject.Properties['UserPackLimit'] -and $ParentUser.UserPackLimit) {
            [int]$ParentUser.UserPackLimit
        } else {
            0
        }
        
        # Check if user pack is expired
        $UserPackExpired = $false
        if ($ParentUser.PSObject.Properties['UserPackExpiresAt'] -and $ParentUser.UserPackExpiresAt) {
            try {
                $ExpiryDate = [DateTime]::Parse($ParentUser.UserPackExpiresAt, [System.Globalization.CultureInfo]::InvariantCulture)
                $Now = (Get-Date).ToUniversalTime()
                if ($ExpiryDate -lt $Now) {
                    $UserPackExpired = $true
                }
            } catch {
                Write-Warning "Failed to parse UserPackExpiresAt date"
            }
        }
        
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
                $SubAccountsList += [PSCustomObject]@{
                    userId = $SubAccountUser.RowKey
                    username = $SubAccountUser.Username
                    email = $SubAccountUser.PartitionKey
                    displayName = $SubAccountUser.DisplayName
                    type = if ($relationship.PSObject.Properties['Type'] -and $relationship.Type) { $relationship.Type } else { 'client' }
                    status = if ($relationship.PSObject.Properties['Status'] -and $relationship.Status) { $relationship.Status } else { 'active' }
                    createdAt = if ($relationship.PSObject.Properties['CreatedAt'] -and $relationship.CreatedAt) { $relationship.CreatedAt } else { $relationship.Timestamp }
                }
            }
        }
        
        # Calculate quota
        $usedSubAccounts = $SubAccountsList.Count
        $maxSubAccounts = if ($UserPackExpired) { 0 } else { $UserPackLimit }
        $remainingSubAccounts = [Math]::Max(0, $maxSubAccounts - $usedSubAccounts)
        
        # Build response
        $Results = @{
            subAccounts = @($SubAccountsList)
            total = $usedSubAccounts
            limits = @{
                maxSubAccounts = $maxSubAccounts
                usedSubAccounts = $usedSubAccounts
                remainingSubAccounts = $remainingSubAccounts
                userPackType = $UserPackType
                userPackExpired = $UserPackExpired
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
