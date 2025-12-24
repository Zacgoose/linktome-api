function Invoke-AdminUserManagerList {
    <#
    .SYNOPSIS
        List user management relationships for the current user.
    .DESCRIPTION
        Lists all users the current user manages and all users who manage the current user, including invite state and roles.
    .EXAMPLE
        Invoke-AdminUserManagerList
    .ROLE
        list:user_manager
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata
    )
    try {
        $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
        if (-not $UserId) {
            throw 'Authenticated user not found in request.'
        }

        $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'

        # Users who manage me (RowKey = my UserId)
        $managers = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "RowKey eq '$UserId'"

        # Users I manage (PartitionKey = my UserId)
        $managees = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$UserId'"

        $Results = @{
            managers = @($managers | ForEach-Object {
                [PSCustomObject]@{
                    UserId  = $_.PartitionKey
                    role    = $_.Role
                    state   = $_.State
                    created = $_.Created
                    updated = $_.Updated
                }
            })
            managees = @($managees | ForEach-Object {
                [PSCustomObject]@{
                    UserId  = $_.RowKey
                    role    = $_.Role
                    state   = $_.State
                    created = $_.Created
                    updated = $_.Updated
                }
            })
        }
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to list user management relationships"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Results
    }
}
