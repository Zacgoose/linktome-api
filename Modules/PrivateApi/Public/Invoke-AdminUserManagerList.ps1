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
        $UserId = $Request.AuthenticatedUser.UserId
        if (-not $UserId) {
            throw 'Authenticated user not found in request.'
        }

        $UserManagersTable = Get-LinkToMeTable -TableName 'UserManagers'

        # Users who manage me (PartitionKey = my userId)
        $managers = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$UserId'"

        # Users I manage (RowKey = my userId)
        $managees = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "RowKey eq '$UserId'"

        $Results = @{
            managers = @($managers | ForEach-Object {
                [PSCustomObject]@{
                    userId  = $_.RowKey
                    role    = $_.Role
                    state   = $_.State
                    created = $_.Created
                    updated = $_.Updated
                }
            })
            managees = @($managees | ForEach-Object {
                [PSCustomObject]@{
                    userId  = $_.PartitionKey
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
