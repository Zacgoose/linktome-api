
function Get-StringHash {
    param([string]$InputString)
    
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $Hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return [Convert]::ToBase64String($Hash)
}