function Get-SafeErrorResponse {
    <#
    .SYNOPSIS
        Generate safe error response for clients
    .DESCRIPTION
        Returns sanitized error messages to clients while logging full details server-side.
        Conforms to standard error format: { "error": "message" }
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
    
    # Log detailed error information server-side (using Write-Warning to avoid stopping execution)
    Write-Warning "Error Details: $($ErrorRecord.Exception.Message)"
    Write-Warning "Error Type: $($ErrorRecord.Exception.GetType().FullName)"
    if ($ErrorRecord.ScriptStackTrace) {
        Write-Warning "Stack Trace: $($ErrorRecord.ScriptStackTrace)"
    }
    
    # Standard error format: { "error": "message" }
    $Response = @{
        error = $GenericMessage
    }

    return $Response
}
