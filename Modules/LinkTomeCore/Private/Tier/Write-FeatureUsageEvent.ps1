function Write-FeatureUsageEvent {
    <#
    .SYNOPSIS
        Track feature usage events for analytics and compliance
    .DESCRIPTION
        Records when users attempt to access features, including both successful and blocked access
    .PARAMETER UserId
        User ID attempting to access the feature
    .PARAMETER Feature
        Feature identifier being accessed
    .PARAMETER Allowed
        Whether access was granted (true) or denied (false)
    .PARAMETER Tier
        User's subscription tier at time of access
    .PARAMETER IpAddress
        Client IP address (optional)
    .PARAMETER Endpoint
        API endpoint being accessed (optional)
    .EXAMPLE
        Write-FeatureUsageEvent -UserId $User.RowKey -Feature 'advanced_analytics' -Allowed $true -Tier 'premium'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,
        
        [Parameter(Mandatory)]
        [string]$Feature,
        
        [Parameter(Mandatory)]
        [bool]$Allowed,
        
        [Parameter(Mandatory)]
        [string]$Tier,
        
        [string]$IpAddress,
        
        [string]$Endpoint
    )
    
    try {
        # Store feature usage event in Azure Table Storage
        $Table = Get-LinkToMeTable -TableName 'FeatureUsage'
        
        # Use UserId as PartitionKey for efficient querying per user
        # Use timestamp + random ID for unique RowKey
        $UsageRecord = @{
            PartitionKey = $UserId
            RowKey = [DateTimeOffset]::UtcNow.Ticks.ToString() + '-' + (New-Guid).ToString().Substring(0, 8)
            EventTimestamp = [DateTimeOffset]::UtcNow
            Feature = $Feature
            Allowed = $Allowed
            Tier = $Tier
        }
        
        # Add optional fields if provided
        if ($IpAddress) {
            $UsageRecord.IpAddress = $IpAddress
        }
        if ($Endpoint) {
            $UsageRecord.Endpoint = $Endpoint
        }
        
        Add-LinkToMeAzDataTableEntity @Table -Entity $UsageRecord -Force | Out-Null
        
    } catch {
        # Don't fail the request if feature usage tracking fails
        Write-Warning "Failed to track feature usage event: $($_.Exception.Message)"
    }
}
