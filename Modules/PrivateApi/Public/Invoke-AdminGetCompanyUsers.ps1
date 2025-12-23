function Invoke-AdminGetCompanyUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:users
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        # Get current companyId from request context
        $CompanyId = $Request.Query.companyId
        if (-not $CompanyId) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Missing CompanyId in request context" }
            }
        }

        # Context-aware permission check
        $User = $Request.AuthenticatedUser
            # Permission check is now handled in the entrypoint (router)
            $RequiredPermission = 'read:users'

        $Table = Get-LinkToMeTable -TableName 'CompanyUsers'
        $filter = "PartitionKey eq '$CompanyId'"
        $entities = Get-LinkToMeAzDataTableEntity @Table -Filter $filter

        $Users = $entities | ForEach-Object {
            [PSCustomObject]@{
                userId = $_.RowKey
                companyRole = $_.Role
                companyEmail = $_.CompanyEmail
                companyDisplayName = $_.CompanyDisplayName
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Results = @{ users = $Users }
    } catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get company users"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
