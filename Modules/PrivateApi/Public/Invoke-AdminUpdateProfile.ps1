function Invoke-AdminUpdateProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        User.Profile.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        $UserData = Get-AzDataTableEntity @Table -Filter "RowKey eq '$($User.UserId)'" | Select-Object -First 1
        
        if (-not $UserData) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body = @{ error = "User not found" }
            }
        }
        
        # Update allowed fields
        if ($Body.displayName) { $UserData.DisplayName = $Body.displayName }
        if ($Body.bio) { $UserData.Bio = $Body.bio }
        if ($Body.avatar) { $UserData.Avatar = $Body.avatar }
        
        # Save changes
        Add-AzDataTableEntity @Table -Entity $UserData -Force
        
        $Results = @{
            userId = $UserData.RowKey
            username = $UserData.Username
            email = $UserData.PartitionKey
            displayName = $UserData.DisplayName
            bio = $UserData.Bio
            avatar = $UserData.Avatar
        }
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        Write-Error "Update profile error: $($_.Exception.Message)"
        $Results = @{ error = "Failed to update profile" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}