function Invoke-AdminGetUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:users
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        $entities = Get-LinkToMeAzDataTableEntity @Table

        # Get current companyId from request context (customize as needed)
        $CompanyId = $Request.CompanyId
        if (-not $CompanyId) {
            $CompanyId = $Request.AuthenticatedUser.CompanyId
        }

        # Permission check is now handled in the entrypoint (router)
        $User = $Request.AuthenticatedUser

        # Filter users by CompanyIds array
        $Users = $entities | Where-Object {
            $userCompanyIds = $_.CompanyIds
            if ($userCompanyIds -is [string]) {
                $userCompanyIds = ConvertFrom-Json $userCompanyIds
            }
            $userCompanyIds -contains $CompanyId
        } | ForEach-Object {
            [PSCustomObject]@{
                userId = $_.RowKey
                username = $_.Username
                email = $_.PartitionKey
                displayName = $_.DisplayName
                role = $_.Roles
                companyIds = $_.CompanyIds
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Results = @{ users = $Users }
    } catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get users"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
