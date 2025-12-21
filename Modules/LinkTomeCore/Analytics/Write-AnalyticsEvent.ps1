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
    .PARAMETER Metadata
        Additional metadata as hashtable
    .EXAMPLE
        Write-AnalyticsEvent -EventType 'PageView' -UserId $User.RowKey -Username $User.Username -IpAddress $ClientIP
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
        
        [hashtable]$Metadata = @{}
    )
    
    try {
        # Store analytics event in Azure Table Storage
        $Table = Get-LinkToMeTable -TableName 'Analytics'
        
        # Use UserId as PartitionKey for efficient querying per user
        # Use timestamp + random ID for unique RowKey
        $EventRecord = @{
            PartitionKey = $UserId
            RowKey = [DateTime]::UtcNow.Ticks.ToString() + '-' + (New-Guid).ToString().Substring(0, 8)
            Timestamp = [DateTime]::UtcNow
            EventType = $EventType
            Username = $Username
            IpAddress = $IpAddress
            UserAgent = $UserAgent
            Referrer = $Referrer
            MetadataJson = ($Metadata | ConvertTo-Json -Compress)
        }
        
        Add-AzDataTableEntity @Table -Entity $EventRecord -Force | Out-Null
        
    } catch {
        # Don't fail the request if analytics tracking fails
        Write-Warning "Failed to track analytics event: $($_.Exception.Message)"
    }
}
