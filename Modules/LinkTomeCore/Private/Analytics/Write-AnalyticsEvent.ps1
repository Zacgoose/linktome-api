function Write-AnalyticsEvent {
    <#
    .SYNOPSIS
        Track analytics events for user profiles
    .DESCRIPTION
        Records analytics events (page views, link clicks) to Azure Table Storage
    .PARAMETER EventType
        Type of analytics event (e.g., 'PageView', 'LinkClick')
    .PARAMETER UserId
        User ID whose profile/link was accessed
    .PARAMETER Username
        Username of the profile accessed
    .PARAMETER IpAddress
        Client IP address
    .PARAMETER UserAgent
        User agent string from the request
    .PARAMETER Referrer
        Referrer URL if available
    .PARAMETER LinkId
        Link ID for LinkClick events
    .PARAMETER LinkTitle
        Link title for LinkClick events
    .PARAMETER LinkUrl
        Link URL for LinkClick events
    .EXAMPLE
        Write-AnalyticsEvent -EventType 'PageView' -UserId $User.RowKey -Username $User.Username -IpAddress $ClientIP
    .EXAMPLE
        Write-AnalyticsEvent -EventType 'LinkClick' -UserId $User.RowKey -Username $User.Username -IpAddress $ClientIP -LinkId $LinkId -LinkTitle $LinkTitle -LinkUrl $LinkUrl
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('PageView', 'LinkClick')]
        [string]$EventType,
        
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [string]$Username,
        
        [string]$IpAddress,
        
        [string]$UserAgent,
        
        [string]$Referrer,
        
        [string]$LinkId,
        
        [string]$LinkTitle,
        
        [string]$LinkUrl
    )
    
    try {
        # Store analytics event in Azure Table Storage
        $Table = Get-LinkToMeTable -TableName 'Analytics'
        
        # Use UserId as PartitionKey for efficient querying per user
        # Use timestamp + random ID for unique RowKey
        $EventRecord = @{
            PartitionKey = $UserId
            RowKey = [DateTimeOffset]::UtcNow.Ticks.ToString() + '-' + (New-Guid).ToString().Substring(0, 8)
            EventTimestamp = [DateTimeOffset]::UtcNow
            EventType = $EventType
            Username = $Username
            IpAddress = $IpAddress
            UserAgent = $UserAgent
            Referrer = $Referrer
        }
        
        # Add link-specific properties if provided
        if ($LinkId) {
            $EventRecord.LinkId = $LinkId
        }
        if ($LinkTitle) {
            $EventRecord.LinkTitle = $LinkTitle
        }
        if ($LinkUrl) {
            $EventRecord.LinkUrl = $LinkUrl
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $EventRecord -Force | Out-Null
        
    } catch {
        # Don't fail the request if analytics tracking fails
        Write-Warning "Failed to track analytics event: $($_.Exception.Message)"
    }
}
