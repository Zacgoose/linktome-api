function Invoke-AdminUpdateProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:profile
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $User = $Request.AuthenticatedUser
    $Body = $Request.Body

    # Validate input lengths
    if ($Body.displayName) {
        $LengthCheck = Test-InputLength -Value $Body.displayName -MaxLength 100 -FieldName "Display name"
        if (-not $LengthCheck.Valid) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = $LengthCheck.Message }
            }
        }
    }

    if ($Body.bio) {
        $LengthCheck = Test-InputLength -Value $Body.bio -MaxLength 500 -FieldName "Bio"
        if (-not $LengthCheck.Valid) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = $LengthCheck.Message }
            }
        }
    }

    if ($Body.avatar) {
        $LengthCheck = Test-InputLength -Value $Body.avatar -MaxLength 2048 -FieldName "Avatar URL"
        if (-not $LengthCheck.Valid) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = $LengthCheck.Message }
            }
        }
        
        # Validate avatar URL format
        if (-not (Test-UrlFormat -Url $Body.avatar)) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body = @{ error = "Avatar must be a valid http or https URL" }
            }
        }
    }

    try {
        $Table = Get-LinkToMeTable -TableName 'Users'
        
        # Sanitize userId for query
        $SafeUserId = Protect-TableQueryValue -Value $User.UserId
        $UserData = Get-LinkToMeAzDataTableEntity @Table -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
        
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
        Add-LinkToMeAzDataTableEntity @Table -Entity $UserData -Force
        
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
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update profile"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}