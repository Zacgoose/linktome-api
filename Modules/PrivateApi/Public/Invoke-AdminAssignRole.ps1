function Invoke-AdminAssignRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Admin.UserManagement
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
    $AllowedRoles = @('user', 'admin', 'company_owner')
    if ($Body.role -notin $AllowedRoles) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "Invalid role. Allowed roles: user, admin, company_owner" 
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

        # Get default permissions for the role
        $DefaultPermissions = Get-DefaultRolePermissions -Role $Body.role

        # Update user with new role and permissions
        $TargetUser.Roles = @($Body.role)
        $TargetUser.Permissions = $DefaultPermissions
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $TargetUser -Force
        
        # Log role assignment
        $ClientIP = Get-ClientIPAddress -Request $Request
        Write-SecurityEvent -EventType 'RoleAssigned' -UserId $AuthUser.UserId -Endpoint 'admin/assignRole' -IpAddress $ClientIP -Metadata @{
            TargetUserId = $Body.userId
            AssignedRole = $Body.role
            AssignedBy = $AuthUser.UserId
        }
        
        $Results = @{
            success = $true
            userId = $TargetUser.RowKey
            role = $Body.role
            permissions = $DefaultPermissions
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
