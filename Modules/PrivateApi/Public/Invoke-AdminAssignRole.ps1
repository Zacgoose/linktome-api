function Invoke-AdminAssignRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        manage:users
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Body = $Request.Body
    $AuthUser = $Request.AuthenticatedUser

    # Validate required fields
    if (-not $Body.userId -or -not $Body.role) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "userId and role are required" 
            }
        }
    }

    # Validate role is one of the allowed values
    $AllowedRoles = @('user', 'company_admin', 'company_owner')
    if ($Body.role -notin $AllowedRoles) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "Invalid role. Allowed roles: user, company_admin, company_owner" 
            }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get the target user
        $SafeUserId = Protect-TableQueryValue -Value $Body.userId
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

        # Check if company_owner is trying to manage user from different company
        if ($AuthUser.Roles -contains 'company_owner' -and $AuthUser.Roles -notcontains 'admin') {
            if ($AuthUser.CompanyId -and $TargetUser.CompanyId -ne $AuthUser.CompanyId) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ 
                        success = $false
                        error = "Company owners can only manage users in their own company" 
                    }
                }
            }
        }

        if ($Body.role -eq 'user') {
            # Only update Users table for 'user' role
            $DefaultPermissions = Get-DefaultRolePermissions -Role 'user'
            $TargetUser.Roles = '["user"]'
            $TargetUser.Permissions = [string]($DefaultPermissions | ConvertTo-Json -Compress)
            Add-LinkToMeAzDataTableEntity @Table -Entity $TargetUser -Force
        } else {
            # For company_admin/company_owner, update or insert into CompanyUsers table
            $CompanyId = $Body.companyId
            if (-not $CompanyId) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ success = $false; error = "companyId is required for company roles" }
                }
            }
            $CompanyUsersTable = Get-LinkToMeTable -TableName 'CompanyUsers'
            $CompanyUserEntity = Get-LinkToMeAzDataTableEntity @CompanyUsersTable -Filter "PartitionKey eq '$CompanyId' and RowKey eq '$($TargetUser.RowKey)'" | Select-Object -First 1
            if ($CompanyUserEntity) {
                $CompanyUserEntity.Role = $Body.role
                Add-LinkToMeAzDataTableEntity @CompanyUsersTable -Entity $CompanyUserEntity -Force
            } else {
                $CompanyUserEntity = @{
                    PartitionKey = $CompanyId
                    RowKey = $TargetUser.RowKey
                    Role = $Body.role
                    CompanyEmail = $TargetUser.PartitionKey
                    CompanyDisplayName = $TargetUser.DisplayName
                    Username = $TargetUser.Username
                }
                Add-LinkToMeAzDataTableEntity @CompanyUsersTable -Entity $CompanyUserEntity -Force
            }
            # Always keep Users table role as 'user'
            $TargetUser.Roles = '["user"]'
            $TargetUser.Permissions = [string](Get-DefaultRolePermissions -Role 'user' | ConvertTo-Json -Compress)
            Add-LinkToMeAzDataTableEntity @Table -Entity $TargetUser -Force
        }

        # Log role assignment
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'RoleAssigned' -UserId $AuthUser.UserId -Endpoint 'admin/assignRole' -IpAddress $ClientIP -Reason "Assigned role '$($Body.role)' to user '$($Body.userId)' by '$($AuthUser.UserId)'"

        $Results = @{
            success = $true
            userId = $TargetUser.RowKey
            role = $Body.role
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Assign role error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to assign role"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
