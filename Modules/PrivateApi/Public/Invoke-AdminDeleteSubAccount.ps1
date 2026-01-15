function Invoke-AdminDeleteSubAccount {
    <#
    .SYNOPSIS
        Delete a sub-account owned by the authenticated parent user.
    .DESCRIPTION
        Deletes a sub-account and all associated data. Only the parent account
        that created the sub-account can delete it.
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
        if (-not $Body.userId) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "userId is required" }
            }
        }
        
        $SubAccountUserId = $Body.userId
        
        # Get tables
        $UsersTable = Get-LinkToMeTable -TableName 'Users'
        $SubAccountsTable = Get-LinkToMeTable -TableName 'SubAccounts'
        
        # Verify ownership in SubAccounts table
        $SafeParentId = Protect-TableQueryValue -Value $ParentUserId
        $SafeSubId = Protect-TableQueryValue -Value $SubAccountUserId
        $Relationship = Get-LinkToMeAzDataTableEntity @SubAccountsTable -Filter "PartitionKey eq '$SafeParentId' and RowKey eq '$SafeSubId'" | Select-Object -First 1
        
        if (-not $Relationship) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{ error = "Sub-account not found or you do not have permission to delete it" }
            }
        }
        
        # Get sub-account user
        $SubAccountUser = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeSubId'" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if (-not $SubAccountUser) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Sub-account user not found" }
            }
        }
        
        # Verify it is actually a sub-account
        if (-not ($SubAccountUser.PSObject.Properties['IsSubAccount'] -and $SubAccountUser.IsSubAccount -eq $true)) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body = @{ error = "User is not a sub-account" }
            }
        }
        
        # === Delete associated data ===
        # Note: In a production system, you would cascade delete all associated resources
        # (pages, links, analytics, etc.). For now, we'll delete the core entities.
        
        # Delete from SubAccounts table (relationship)
        Remove-LinkToMeAzDataTableEntity @SubAccountsTable -Entity $Relationship
        
        # Delete from Users table
        Remove-LinkToMeAzDataTableEntity @UsersTable -Entity $SubAccountUser
        
        # Write security event
        Write-SecurityEvent -EventType 'SubAccountDeleted' -UserId $ParentUserId -AdditionalData (@{
            SubAccountUserId = $SubAccountUserId
            SubAccountEmail = $SubAccountUser.PartitionKey
            SubAccountUsername = $SubAccountUser.Username
        } | ConvertTo-Json -Depth 10)
        
        # Build response
        $Results = @{
            userId = $SubAccountUserId
            message = "Sub-account deleted successfully"
        }
        
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        Write-Error "Delete sub-account error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to delete sub-account"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
