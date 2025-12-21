function Invoke-AdminGetUserRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Admin.UserManagement
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $AuthUser = $Request.AuthenticatedUser
    
    # Get userId from query parameter
    $UserId = $Request.Query.userId
    
    if (-not $UserId) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "userId query parameter is required" 
            }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get the target user
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        $TargetUser = Get-AzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
        if (-not $TargetUser) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ 
                    success = $false
                    error = "User not found" 
                }
            }
        }

        # Check if company_owner is trying to view user from different company
        if ($AuthUser.Roles -contains 'company_owner' -and $AuthUser.Roles -notcontains 'admin') {
            if ($AuthUser.CompanyId -and $TargetUser.CompanyId -ne $AuthUser.CompanyId) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ 
                        success = $false
                        error = "Company owners can only view users in their own company" 
                    }
                }
            }
        }

        # Get roles and permissions
        $Roles = if ($TargetUser.Roles) {
            if ($TargetUser.Roles -is [array]) { $TargetUser.Roles } else { @($TargetUser.Roles) }
        } else {
            @('user')
        }
        
        $Permissions = if ($TargetUser.Permissions) {
            if ($TargetUser.Permissions -is [array]) { $TargetUser.Permissions } else { @($TargetUser.Permissions) }
        } else {
            Get-DefaultRolePermissions -Role $Roles[0]
        }
        
        $Results = @{
            success = $true
            userId = $TargetUser.RowKey
            username = $TargetUser.Username
            email = $TargetUser.PartitionKey
            roles = $Roles
            permissions = $Permissions
            companyId = $TargetUser.CompanyId
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Get user roles error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get user roles"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
