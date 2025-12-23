function Invoke-AdminGetUserRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:users
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
        $TargetUser = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
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

        # Get the actual user role from the Users table
        $ActualUserRole = 'user'
        if ($TargetUser.Roles) {
            if ($TargetUser.Roles -is [string] -and $TargetUser.Roles.StartsWith('[')) {
                $RolesArr = $TargetUser.Roles | ConvertFrom-Json
                if ($RolesArr.Count -ge 1) { $ActualUserRole = $RolesArr[0] }
            } elseif ($TargetUser.Roles -is [array]) {
                if ($TargetUser.Roles.Count -ge 1) { $ActualUserRole = $TargetUser.Roles[0] }
            } elseif ($TargetUser.Roles) {
                $ActualUserRole = $TargetUser.Roles
            }
        }

        # Use the actual user role for roles/permissions
        $Roles = @($ActualUserRole)
        $Permissions = Get-DefaultRolePermissions -Role $ActualUserRole

        # Lookup company memberships for this user
        $CompanyMemberships = @()
        $CompanyUsersTable = Get-LinkToMeTable -TableName 'CompanyUsers'
        $CompanyUserEntities = Get-LinkToMeAzDataTableEntity @CompanyUsersTable -Filter "RowKey eq '$($TargetUser.RowKey)'"
        foreach ($cu in $CompanyUserEntities) {
            $CompanyMemberships += @{
                companyId = $cu.PartitionKey
                companyRole = $cu.Role
            }
        }

        $Results = @{
            success = $true
            userId = $TargetUser.RowKey
            username = $TargetUser.Username
            email = $TargetUser.PartitionKey
            userRole = $ActualUserRole
            roles = $Roles
            permissions = $Permissions
            companyMemberships = $CompanyMemberships
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
