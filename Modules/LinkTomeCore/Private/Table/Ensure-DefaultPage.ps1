function Ensure-DefaultPage {
    <#
    .SYNOPSIS
        Ensure a user has a default page, creating one if needed
    .DESCRIPTION
        Checks if a user has any pages. If not, creates a default page named "Main Links"
        with slug "main" and migrates existing links, groups, and appearance to it.
    .PARAMETER UserId
        The user's unique identifier
    .RETURNS
        The default page object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId
    )
    
    try {
        $PagesTable = Get-LinkToMeTable -TableName 'Pages'
        $SafeUserId = Protect-TableQueryValue -Value $UserId
        
        # Check if user has any pages
        $Pages = Get-LinkToMeAzDataTableEntity @PagesTable -Filter "PartitionKey eq '$SafeUserId'"
        
        if ($Pages -and $Pages.Count -gt 0) {
            # User already has pages, return the default one
            $DefaultPage = $Pages | Where-Object { [bool]$_.IsDefault } | Select-Object -First 1
            if ($DefaultPage) {
                return $DefaultPage
            }
            # If no default is set, make the first one default
            $FirstPage = $Pages | Select-Object -First 1
            $FirstPage.IsDefault = $true
            Add-LinkToMeAzDataTableEntity @PagesTable -Entity $FirstPage -Force
            return $FirstPage
        }
        
        # Create default page
        $PageId = [guid]::NewGuid().ToString()
        $DefaultPage = @{
            PartitionKey = $UserId
            RowKey = $PageId
            Slug = 'main'
            Name = 'Main Links'
            IsDefault = $true
            CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
            UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
        
        Add-LinkToMeAzDataTableEntity @PagesTable -Entity $DefaultPage -Force
        
        # Migrate existing links to the new page
        $LinksTable = Get-LinkToMeTable -TableName 'Links'
        $Links = Get-LinkToMeAzDataTableEntity @LinksTable -Filter "PartitionKey eq '$SafeUserId'"
        if ($Links) {
            foreach ($Link in $Links) {
                if (-not $Link.PageId) {
                    if ($Link.PSObject.Properties.Match('PageId').Count -eq 0) {
                        $Link | Add-Member -MemberType NoteProperty -Name 'PageId' -Value $PageId -Force
                    } else {
                        $Link.PageId = $PageId
                    }
                    Add-LinkToMeAzDataTableEntity @LinksTable -Entity $Link -Force
                }
            }
        }
        
        # Migrate existing link groups to the new page
        $GroupsTable = Get-LinkToMeTable -TableName 'LinkGroups'
        $Groups = Get-LinkToMeAzDataTableEntity @GroupsTable -Filter "PartitionKey eq '$SafeUserId'"
        if ($Groups) {
            foreach ($Group in $Groups) {
                if (-not $Group.PageId) {
                    if ($Group.PSObject.Properties.Match('PageId').Count -eq 0) {
                        $Group | Add-Member -MemberType NoteProperty -Name 'PageId' -Value $PageId -Force
                    } else {
                        $Group.PageId = $PageId
                    }
                    Add-LinkToMeAzDataTableEntity @GroupsTable -Entity $Group -Force
                }
            }
        }
        
        return $DefaultPage
        
    } catch {
        Write-Error "Failed to ensure default page: $($_.Exception.Message)"
        throw
    }
}
