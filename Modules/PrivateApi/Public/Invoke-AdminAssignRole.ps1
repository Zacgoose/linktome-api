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
    $AuthUserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }

    # Validate required fields
    if (-not $Body.UserId -or -not $Body.role) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "UserId and role are required" 
            }
        }
    }

    # Validate role is one of the allowed values
    $AllowedRoles = @('user', 'company_admin', 'company_owner', 'user_manager')
    if ($Body.role -notin $AllowedRoles) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = @{ 
                success = $false
                error = "Invalid role. Allowed roles: user, company_admin, company_owner, user_manager" 
            }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Get the target user
        $SafeUserId = Protect-TableQueryValue -Value $Body.UserId
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
        Write-SecurityEvent -EventType 'RoleAssigned' -UserId $AuthUserId -Endpoint 'admin/assignRole' -IpAddress $ClientIP -Reason "Assigned role '$($Body.role)' to user '$($Body.UserId)' by '$AuthUserId'"

        $Results = @{
            success = $true
            UserId = $TargetUser.RowKey
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
