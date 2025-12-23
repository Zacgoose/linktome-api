function Invoke-AdminGetCompany {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        read:company
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Table = Get-LinkToMeTable -TableName 'Company'
        $companyId = $Request.Query.companyId
        if (-not $companyId) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Missing companyId parameter" }
            }
        }

        # Permission check is now handled in the entrypoint (router)
        $User = $Request.AuthenticatedUser

        $filter = "PartitionKey eq '$companyId'"
        $entities = Get-LinkToMeAzDataTableEntity @Table -Filter $filter
        $Company = $entities | Select-Object -First 1
        if (-not $Company) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "Company not found" }
            }
        }
        $Results = @{
            name = $Company.CompanyName
            logo = $Company.Logo
            description = $Company.Description
            integrations = $Company.Integrations
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to get company properties"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}
