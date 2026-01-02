function Invoke-AdminUpdateLinks {
    <#
    .SYNOPSIS
        Update, add, or remove user links and groups in bulk.
    .DESCRIPTION
        Accepts an array of link objects and/or group objects, each with an operation property ("add", "update", "remove").
        Performs the requested operation for each item. Maximum 50 links per user.
    .PARAMETER links
        Array of link objects. Each object must include an "operation" property with one of: "add", "update", "remove".
        For "add" and "update": can include title, url, order, active, icon, thumbnail, thumbnailType, layout, 
        animation, schedule, lock, groupId. For "update" and "remove": must include id.
    .PARAMETER groups
        Array of group objects. Each object must include an "operation" property with one of: "add", "update", "remove".
        For "add": must include title. For "update" and "remove": must include id.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        write:links
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $UserId = if ($Request.ContextUserId) { $Request.ContextUserId } else { $Request.AuthenticatedUser.UserId }
    $Body = $Request.Body

    try {
        $LinksTable = Get-LinkToMeTable -TableName 'Links'
        $GroupsTable = Get-LinkToMeTable -TableName 'LinkGroups'
        
        # Sanitize UserId for query
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        
        # Valid enum values for validation
        $validThumbnailTypes = @('icon', 'image', 'emoji')
        $validLayouts = @('classic', 'featured', 'thumbnail-left', 'thumbnail-right')
        $validAnimations = @('none', 'shake', 'pulse', 'bounce', 'glow')
        $validLockTypes = @('code', 'age', 'sensitive')
        $validGroupLayouts = @('stack', 'grid', 'carousel')
        
        # Helper function to safely set property
        function Set-EntityProperty {
            param($Entity, $PropertyName, $Value)
            if ($Entity.PSObject.Properties.Match($PropertyName).Count -eq 0) {
                $Entity | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $Value -Force
            } else {
                $Entity.$PropertyName = $Value
            }
        }
        
        # === Process Links ===
        if ($Body.links) {
            # Get user object to check tier limits
            $UsersTable = Get-LinkToMeTable -TableName 'Users'
            $User = Get-LinkToMeAzDataTableEntity @UsersTable -Filter "RowKey eq '$SafeUserId'" | Select-Object -First 1
            
            if (-not $User) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body = @{ error = "User not found" }
                }
            }
            
            # Get tier features to check link limit
            $UserTier = if ($User.SubscriptionTier) { $User.SubscriptionTier } else { 'free' }
            $TierInfo = Get-TierFeatures -Tier $UserTier
            $MaxLinks = $TierInfo.limits.maxLinks
            
            # Get existing links to check total count
            $ExistingLinks = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId'"
            
            # Count adds vs removes to determine final count
            $addsCount = ($Body.links | Where-Object { $_.operation -eq 'add' }).Count
            $removesCount = ($Body.links | Where-Object { $_.operation -eq 'remove' }).Count
            $projectedTotal = $ExistingLinks.Count + $addsCount - $removesCount
            
            # Check against tier limit
            if ($projectedTotal -gt $MaxLinks) {
                # Track feature usage for blocked attempt
                $ClientIP = Get-ClientIPAddress -Request $Request
                Write-FeatureUsageEvent -UserId $UserId -Feature 'link_limit_exceeded' -Allowed $false -Tier $UserTier -IpAddress $ClientIP -Endpoint 'admin/updateLinks'
                
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body = @{ 
                        error = "Link limit exceeded. Your $($TierInfo.tierName) plan allows up to $MaxLinks links. You currently have $($ExistingLinks.Count) links."
                        currentTier = $UserTier
                        maxLinks = $MaxLinks
                        currentLinks = $ExistingLinks.Count
                        upgradeRequired = $true
                    }
                }
            }
            
            # Validate max number of links in single request (excluding removes)
            $addOrUpdateCount = ($Body.links | Where-Object { $_.operation -in @('add','update') }).Count
            if ($addOrUpdateCount -gt 50) {
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body = @{ error = "Maximum 50 links allowed per request" }
                }
            }

            foreach ($Link in $Body.links) {
                $op = ($Link.operation ?? '').ToLower()
                switch ($op) {
                    'add' {
                        # Validate required fields
                        if (-not $Link.title) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Link title is required for add" }
                            }
                        }
                        if (-not $Link.url) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Link URL is required for add" }
                            }
                        }
                        $TitleCheck = Test-InputLength -Value $Link.title -MaxLength 100 -FieldName "Link title"
                        if (-not $TitleCheck.Valid) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = $TitleCheck.Message }
                            }
                        }
                        $UrlCheck = Test-InputLength -Value $Link.url -MaxLength 2048 -FieldName "Link URL"
                        if (-not $UrlCheck.Valid) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = $UrlCheck.Message }
                            }
                        }
                        if (-not (Test-UrlFormat -Url $Link.url)) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Link URL must be a valid http or https URL: $($Link.title)" }
                            }
                        }
                        
                        $NewLink = @{
                            PartitionKey = $UserId
                            RowKey = 'link-' + (New-Guid).ToString()
                            Title = $Link.title
                            Url = $Link.url
                            Order = if ($null -ne $Link.order) { [int]$Link.order } else { 0 }
                            Active = if ($null -ne $Link.active) { [bool]$Link.active } else { $true }
                        }
                        
                        # Optional fields
                        if ($Link.icon) {
                            $IconCheck = Test-InputLength -Value $Link.icon -MaxLength 500 -FieldName "Link icon"
                            if (-not $IconCheck.Valid) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = $IconCheck.Message }
                                }
                            }
                            $NewLink.Icon = $Link.icon
                        }
                        if ($Link.thumbnail) { $NewLink.Thumbnail = $Link.thumbnail }
                        if ($Link.thumbnailType) {
                            if ($Link.thumbnailType -notin $validThumbnailTypes) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Thumbnail type must be 'icon', 'image', or 'emoji'" }
                                }
                            }
                            $NewLink.ThumbnailType = $Link.thumbnailType
                        }
                        if ($Link.layout) {
                            if ($Link.layout -notin $validLayouts) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Layout must be 'classic', 'featured', 'thumbnail-left', or 'thumbnail-right'" }
                                }
                            }
                            $NewLink.Layout = $Link.layout
                        }
                        if ($Link.animation) {
                            if ($Link.animation -notin $validAnimations) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Animation must be 'none', 'shake', 'pulse', 'bounce', or 'glow'" }
                                }
                            }
                            $NewLink.Animation = $Link.animation
                        }
                        if ($Link.groupId) { $NewLink.GroupId = $Link.groupId }
                        
                        # Schedule settings
                        if ($Link.schedule) {
                            $NewLink.ScheduleEnabled = [bool]$Link.schedule.enabled
                            if ($Link.schedule.startDate) { $NewLink.ScheduleStartDate = $Link.schedule.startDate }
                            if ($Link.schedule.endDate) { $NewLink.ScheduleEndDate = $Link.schedule.endDate }
                            if ($Link.schedule.timezone) { $NewLink.ScheduleTimezone = $Link.schedule.timezone }
                        }
                        
                        # Lock settings
                        if ($Link.lock) {
                            $NewLink.LockEnabled = [bool]$Link.lock.enabled
                            if ($Link.lock.type) {
                                if ($Link.lock.type -notin $validLockTypes) {
                                    return [HttpResponseContext]@{
                                        StatusCode = [HttpStatusCode]::BadRequest
                                        Body = @{ error = "Lock type must be 'code', 'age', or 'sensitive'" }
                                    }
                                }
                                $NewLink.LockType = $Link.lock.type
                            }
                            if ($Link.lock.code) { $NewLink.LockCode = $Link.lock.code }
                            if ($Link.lock.message) { $NewLink.LockMessage = $Link.lock.message }
                        }
                        
                        Add-LinkToMeAzDataTableEntity @LinksTable -Entity $NewLink -Force
                    }
                    'update' {
                        if (-not $Link.id) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Link id is required for update" }
                            }
                        }
                        $ExistingLink = $ExistingLinks | Where-Object { $_.RowKey -eq $Link.id } | Select-Object -First 1
                        if (-not $ExistingLink) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::NotFound
                                Body = @{ error = "Link not found for update: $($Link.id)" }
                            }
                        }
                        
                        # Update basic fields
                        if ($Link.title) {
                            $TitleCheck = Test-InputLength -Value $Link.title -MaxLength 100 -FieldName "Link title"
                            if (-not $TitleCheck.Valid) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = $TitleCheck.Message }
                                }
                            }
                            $ExistingLink.Title = $Link.title
                        }
                        if ($Link.url) {
                            $UrlCheck = Test-InputLength -Value $Link.url -MaxLength 2048 -FieldName "Link URL"
                            if (-not $UrlCheck.Valid) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = $UrlCheck.Message }
                                }
                            }
                            if (-not (Test-UrlFormat -Url $Link.url)) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Link URL must be a valid http or https URL: $($Link.title)" }
                                }
                            }
                            $ExistingLink.Url = $Link.url
                        }
                        if ($Link.PSObject.Properties.Match('order').Count -gt 0) { $ExistingLink.Order = [int]$Link.order }
                        if ($Link.PSObject.Properties.Match('active').Count -gt 0) { $ExistingLink.Active = [bool]$Link.active }
                        
                        # Update optional fields
                        if ($Link.PSObject.Properties.Match('icon').Count -gt 0) {
                            if ($Link.icon) {
                                $IconCheck = Test-InputLength -Value $Link.icon -MaxLength 500 -FieldName "Link icon"
                                if (-not $IconCheck.Valid) {
                                    return [HttpResponseContext]@{
                                        StatusCode = [HttpStatusCode]::BadRequest
                                        Body = @{ error = $IconCheck.Message }
                                    }
                                }
                            }
                            Set-EntityProperty -Entity $ExistingLink -PropertyName 'Icon' -Value $Link.icon
                        }
                        if ($Link.PSObject.Properties.Match('thumbnail').Count -gt 0) {
                            Set-EntityProperty -Entity $ExistingLink -PropertyName 'Thumbnail' -Value $Link.thumbnail
                        }
                        if ($Link.PSObject.Properties.Match('thumbnailType').Count -gt 0) {
                            if ($Link.thumbnailType -and $Link.thumbnailType -notin $validThumbnailTypes) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Thumbnail type must be 'icon', 'image', or 'emoji'" }
                                }
                            }
                            Set-EntityProperty -Entity $ExistingLink -PropertyName 'ThumbnailType' -Value $Link.thumbnailType
                        }
                        if ($Link.PSObject.Properties.Match('layout').Count -gt 0) {
                            if ($Link.layout -and $Link.layout -notin $validLayouts) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Layout must be 'classic', 'featured', 'thumbnail-left', or 'thumbnail-right'" }
                                }
                            }
                            Set-EntityProperty -Entity $ExistingLink -PropertyName 'Layout' -Value $Link.layout
                        }
                        if ($Link.PSObject.Properties.Match('animation').Count -gt 0) {
                            if ($Link.animation -and $Link.animation -notin $validAnimations) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Animation must be 'none', 'shake', 'pulse', 'bounce', or 'glow'" }
                                }
                            }
                            Set-EntityProperty -Entity $ExistingLink -PropertyName 'Animation' -Value $Link.animation
                        }
                        if ($Link.PSObject.Properties.Match('groupId').Count -gt 0) {
                            Set-EntityProperty -Entity $ExistingLink -PropertyName 'GroupId' -Value $Link.groupId
                        }
                        
                        # Update schedule settings
                        if ($Link.schedule) {
                            Set-EntityProperty -Entity $ExistingLink -PropertyName 'ScheduleEnabled' -Value ([bool]$Link.schedule.enabled)
                            if ($Link.schedule.PSObject.Properties.Match('startDate').Count -gt 0) {
                                Set-EntityProperty -Entity $ExistingLink -PropertyName 'ScheduleStartDate' -Value $Link.schedule.startDate
                            }
                            if ($Link.schedule.PSObject.Properties.Match('endDate').Count -gt 0) {
                                Set-EntityProperty -Entity $ExistingLink -PropertyName 'ScheduleEndDate' -Value $Link.schedule.endDate
                            }
                            if ($Link.schedule.PSObject.Properties.Match('timezone').Count -gt 0) {
                                Set-EntityProperty -Entity $ExistingLink -PropertyName 'ScheduleTimezone' -Value $Link.schedule.timezone
                            }
                        }
                        
                        # Update lock settings
                        if ($Link.lock) {
                            Set-EntityProperty -Entity $ExistingLink -PropertyName 'LockEnabled' -Value ([bool]$Link.lock.enabled)
                            if ($Link.lock.PSObject.Properties.Match('type').Count -gt 0) {
                                if ($Link.lock.type -and $Link.lock.type -notin $validLockTypes) {
                                    return [HttpResponseContext]@{
                                        StatusCode = [HttpStatusCode]::BadRequest
                                        Body = @{ error = "Lock type must be 'code', 'age', or 'sensitive'" }
                                    }
                                }
                                Set-EntityProperty -Entity $ExistingLink -PropertyName 'LockType' -Value $Link.lock.type
                            }
                            if ($Link.lock.PSObject.Properties.Match('code').Count -gt 0) {
                                Set-EntityProperty -Entity $ExistingLink -PropertyName 'LockCode' -Value $Link.lock.code
                            }
                            if ($Link.lock.PSObject.Properties.Match('message').Count -gt 0) {
                                Set-EntityProperty -Entity $ExistingLink -PropertyName 'LockMessage' -Value $Link.lock.message
                            }
                        }
                        
                        Add-LinkToMeAzDataTableEntity @LinksTable -Entity $ExistingLink -Force
                    }
                    'remove' {
                        if (-not $Link.id) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Link id is required for remove" }
                            }
                        }
                        $ExistingLink = $ExistingLinks | Where-Object { $_.RowKey -eq $Link.id } | Select-Object -First 1
                        if ($ExistingLink) {
                            Remove-AzDataTableEntity -Entity $ExistingLink -Context $LinksTable.Context
                        }
                    }
                    default {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Invalid link operation: $op. Must be add, update, or remove." }
                        }
                    }
                }
            }
        }
        
        # === Process Groups ===
        if ($Body.groups) {
            $ExistingGroups = Get-LinkToMeAzDataTableEntity @GroupsTable -Filter "PartitionKey eq '$SafeUserId'"
            
            foreach ($Group in $Body.groups) {
                $op = ($Group.operation ?? '').ToLower()
                switch ($op) {
                    'add' {
                        if (-not $Group.title) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Group title is required for add" }
                            }
                        }
                        $TitleCheck = Test-InputLength -Value $Group.title -MaxLength 100 -FieldName "Group title"
                        if (-not $TitleCheck.Valid) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = $TitleCheck.Message }
                            }
                        }
                        
                        $NewGroup = @{
                            PartitionKey = $UserId
                            RowKey = 'group-' + (New-Guid).ToString()
                            Title = $Group.title
                            Order = if ($null -ne $Group.order) { [int]$Group.order } else { 0 }
                            Active = if ($null -ne $Group.active) { [bool]$Group.active } else { $true }
                        }
                        
                        if ($Group.layout) {
                            if ($Group.layout -notin $validGroupLayouts) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Group layout must be 'stack', 'grid', or 'carousel'" }
                                }
                            }
                            $NewGroup.Layout = $Group.layout
                        }
                        if ($null -ne $Group.collapsed) { $NewGroup.Collapsed = [bool]$Group.collapsed }
                        
                        Add-LinkToMeAzDataTableEntity @GroupsTable -Entity $NewGroup -Force
                    }
                    'update' {
                        if (-not $Group.id) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Group id is required for update" }
                            }
                        }
                        $ExistingGroup = $ExistingGroups | Where-Object { $_.RowKey -eq $Group.id } | Select-Object -First 1
                        if (-not $ExistingGroup) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::NotFound
                                Body = @{ error = "Group not found for update: $($Group.id)" }
                            }
                        }
                        
                        if ($Group.title) {
                            $TitleCheck = Test-InputLength -Value $Group.title -MaxLength 100 -FieldName "Group title"
                            if (-not $TitleCheck.Valid) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = $TitleCheck.Message }
                                }
                            }
                            $ExistingGroup.Title = $Group.title
                        }
                        if ($Group.PSObject.Properties.Match('order').Count -gt 0) { $ExistingGroup.Order = [int]$Group.order }
                        if ($Group.PSObject.Properties.Match('active').Count -gt 0) { $ExistingGroup.Active = [bool]$Group.active }
                        if ($Group.PSObject.Properties.Match('layout').Count -gt 0) {
                            if ($Group.layout -and $Group.layout -notin $validGroupLayouts) {
                                return [HttpResponseContext]@{
                                    StatusCode = [HttpStatusCode]::BadRequest
                                    Body = @{ error = "Group layout must be 'stack', 'grid', or 'carousel'" }
                                }
                            }
                            Set-EntityProperty -Entity $ExistingGroup -PropertyName 'Layout' -Value $Group.layout
                        }
                        if ($Group.PSObject.Properties.Match('collapsed').Count -gt 0) {
                            Set-EntityProperty -Entity $ExistingGroup -PropertyName 'Collapsed' -Value ([bool]$Group.collapsed)
                        }
                        
                        Add-LinkToMeAzDataTableEntity @GroupsTable -Entity $ExistingGroup -Force
                    }
                    'remove' {
                        if (-not $Group.id) {
                            return [HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body = @{ error = "Group id is required for remove" }
                            }
                        }
                        $ExistingGroup = $ExistingGroups | Where-Object { $_.RowKey -eq $Group.id } | Select-Object -First 1
                        if ($ExistingGroup) {
                            # Also unassign any links from this group
                            $LinksInGroup = $ExistingLinks | Where-Object { $_.GroupId -eq $Group.id }
                            foreach ($LinkInGroup in $LinksInGroup) {
                                Set-EntityProperty -Entity $LinkInGroup -PropertyName 'GroupId' -Value $null
                                Add-LinkToMeAzDataTableEntity @LinksTable -Entity $LinkInGroup -Force
                            }
                            Remove-AzDataTableEntity -Entity $ExistingGroup -Context $GroupsTable.Context
                        }
                    }
                    default {
                        return [HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body = @{ error = "Invalid group operation: $op. Must be add, update, or remove." }
                        }
                    }
                }
            }
        }

        $Results = @{ success = $true }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        Write-Error "Update links error: $($_.Exception.Message)"
        $Results = Get-SafeErrorResponse -ErrorRecord $_ -GenericMessage "Failed to update links"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = $Results
    }
}