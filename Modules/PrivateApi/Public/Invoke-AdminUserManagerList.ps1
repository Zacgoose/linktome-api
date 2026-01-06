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
        $UsersTable = Get-LinkToMeTable -TableName 'Users'

        # Users who manage me (RowKey = my UserId)
        $managers = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "RowKey eq '$UserId'"

        # Users I manage (PartitionKey = my UserId)
        $managees = Get-LinkToMeAzDataTableEntity @UserManagersTable -Filter "PartitionKey eq '$UserId'"

        # Collect all unique UserIds to fetch user details (avoiding duplicate queries)
        $allUserIds = @()
        $allUserIds += $managers | ForEach-Object { $_.PartitionKey }
        $allUserIds += $managees | ForEach-Object { $_.RowKey }
        $uniqueUserIds = $allUserIds | Select-Object -Unique

        # Fetch all user details in advance and cache them
        $userDetailsCache = @{}
        foreach ($targetUserId in $uniqueUserIds) {
            $SafeUserId = Protect-TableQueryValue -Value $targetUserId
            $UserData = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($UserData) {
                $userDetailsCache[$targetUserId] = @{
                    username = $UserData.Username
                    email = $UserData.PartitionKey
                }
            } else {
                $userDetailsCache[$targetUserId] = @{
                    username = $null
                    email = $null
                }
            }
        }

        $Results = @{
            managers = @($managers | ForEach-Object {
                $userDetails = $userDetailsCache[$_.PartitionKey]
                [PSCustomObject]@{
                    UserId   = $_.PartitionKey
                    username = $userDetails.username
                    email    = $userDetails.email
                    role     = $_.Role
                    state    = $_.State
                    created  = $_.Created
                    updated  = $_.Updated
                }
            })
            managees = @($managees | ForEach-Object {
                $userDetails = $userDetailsCache[$_.RowKey]
                [PSCustomObject]@{
                    UserId   = $_.RowKey
                    username = $userDetails.username
                    email    = $userDetails.email
                    role     = $_.Role
                    state    = $_.State
                    created  = $_.Created
                    updated  = $_.Updated
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
