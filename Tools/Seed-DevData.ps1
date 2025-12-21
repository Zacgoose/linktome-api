# Run this to create test user and links in Azurite
$ScriptRoot = Split-Path -Parent $PSScriptRoot
$ModulesPath = Join-Path $ScriptRoot 'Modules'

Import-Module (Join-Path $ModulesPath 'LinkTomeCore/LinkTomeCore.psd1') -Force
Import-Module (Join-Path $ModulesPath 'AzBobbyTables') -Force

$env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
$env:JWT_SECRET = 'dev-secret-change-in-production-please-make-this-very-long-and-random-at-least-64-characters'

Write-Host "`nCreating test user and links in Azurite..." -ForegroundColor Cyan

# Create test user
$PasswordData = New-PasswordHash -Password 'password123'
$UserId = 'user-' + (New-Guid).ToString()

$UsersTable = Get-LinkToMeTable -TableName 'Users'

$User = @{
    PartitionKey = 'demo@example.com'
    RowKey = $UserId
    Username = 'demo'
    DisplayName = 'Demo User'
    Bio = 'This is a demo account for LinkToMe'
    Avatar = 'https://ui-avatars.com/api/?name=Demo+User&size=200'
    PasswordHash = $PasswordData.Hash
    PasswordSalt = $PasswordData.Salt
    IsActive = $true
}

Write-Host "Creating user: $($User.PartitionKey)" -ForegroundColor Yellow
Add-AzDataTableEntity @UsersTable -Entity $User -Force

# Create test links
$LinksTable = Get-LinkToMeTable -TableName 'Links'

$Links = @(
    @{ Title = 'GitHub'; Url = 'https://github.com'; Order = 1; Active = $true }
    @{ Title = 'Twitter'; Url = 'https://twitter.com'; Order = 2; Active = $true }
    @{ Title = 'LinkedIn'; Url = 'https://linkedin.com'; Order = 3; Active = $true }
    @{ Title = 'Website'; Url = 'https://example.com'; Order = 4; Active = $true }
    @{ Title = 'YouTube'; Url = 'https://youtube.com'; Order = 5; Active = $true }
)

Write-Host "Creating $($Links.Count) links..." -ForegroundColor Yellow
foreach ($Link in $Links) {
    $Entity = @{
        PartitionKey = $UserId
        RowKey = 'link-' + (New-Guid).ToString()
        Title = $Link.Title
        Url = $Link.Url
        Order = $Link.Order
        Active = $Link.Active
    }
    Add-AzDataTableEntity @LinksTable -Entity $Entity -Force
}

Write-Host "`n✅ Test user created successfully!" -ForegroundColor Green
Write-Host "Email: demo@example.com" -ForegroundColor Cyan
Write-Host "Password: password123" -ForegroundColor Cyan
Write-Host "Username: demo" -ForegroundColor Cyan
Write-Host "`n✅ Test links created: $($Links.Count)" -ForegroundColor Green
Write-Host "`nYou can now:" -ForegroundColor White
Write-Host "1. Start the API: func start" -ForegroundColor Gray
Write-Host "2. Test login: POST /api/public/Login" -ForegroundColor Gray
Write-Host "3. View public profile: GET /api/public/GetUserProfile?username=demo" -ForegroundColor Gray