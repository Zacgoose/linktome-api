function Get-SafeErrorResponse {
    <#
    .SYNOPSIS
        Generate safe error response for clients
    .DESCRIPTION
        Returns sanitized error messages to clients while logging full details server-side
    .PARAMETER ErrorRecord
        The error record from a catch block
    .PARAMETER GenericMessage
        Generic message to return to client (default: "An error occurred")
    .EXAMPLE
        catch {
            $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to process request"
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        
        [string]$GenericMessage = "An error occurred processing the request"
    )
    
    # Log detailed error information server-side
    Write-Error "Error Details: $($ErrorRecord.Exception.Message)"
    Write-Error "Error Type: $($ErrorRecord.Exception.GetType().FullName)"
    if ($ErrorRecord.ScriptStackTrace) {
        Write-Error "Stack Trace: $($ErrorRecord.ScriptStackTrace)"
    }
    
    $Response = @{
        error = @{
            code    = 'InternalServerError'
            message = $GenericMessage
        }
    }

    if ($env:AZURE_FUNCTIONS_ENVIRONMENT -eq 'Development') {
        $Response.error.detail = $ErrorRecord.Exception.Message
        $Response.error.type   = $ErrorRecord.Exception.GetType().Name
    }

    return $Response
}
