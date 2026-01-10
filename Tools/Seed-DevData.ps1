# Run this to create test users and links in Azurite
$ScriptRoot = Split-Path -Parent $PSScriptRoot
$ModulesPath = Join-Path $ScriptRoot 'Modules'

Import-Module (Join-Path $ModulesPath 'LinkTomeCore/LinkTomeCore.psd1') -Force
Import-Module (Join-Path $ModulesPath 'AzBobbyTables') -Force

$env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
$env:JWT_SECRET = 'dev-secret-change-in-production-please-make-this-very-long-and-random-at-least-64-characters'

Write-Host "`nCreating test users and links in Azurite..." -ForegroundColor Cyan
Write-Host "This will create 2 test users with role 'user'." -ForegroundColor Cyan

$UsersTable = Get-LinkToMeTable -TableName 'Users'

# Define test users
$TestUsers = @(
    @{
        Email = 'demo@example.com'
        Username = 'demo'
        DisplayName = 'Demo User'
        Bio = 'This is a demo account for LinkToMe'
        Role = 'user'
        Password = 'password123'
    }
    @{
        Email = 'test@example.com'
        Username = 'test'
        DisplayName = 'Test User'
        Bio = 'This is a test account for LinkToMe'
        Role = 'user'
        Password = 'test123'
    }
)

$CreatedUsers = @()

foreach ($TestUser in $TestUsers) {
    $PasswordData = New-PasswordHash -Password $TestUser.Password
    $UserId = 'user-' + (New-Guid).ToString()

    $User = @{
        PartitionKey = [string]$TestUser.Email
        RowKey = [string]$UserId
        Username = [string]$TestUser.Username
        DisplayName = [string]$TestUser.DisplayName
        Bio = [string]$TestUser.Bio
        Avatar = [string]"https://ui-avatars.com/api/?name=$($TestUser.DisplayName -replace ' ', '+')&size=200"
        PasswordHash = [string]$PasswordData.Hash
        PasswordSalt = [string]$PasswordData.Salt
        IsActive = [bool]$true
        Roles = '["user"]'
        SubscriptionTier = [string]'free'
        SubscriptionStatus = [string]'active'
    }

    Write-Host "Creating user: $($User.PartitionKey) (Role: $($TestUser.Role))" -ForegroundColor Yellow
    Add-LinkToMeAzDataTableEntity @UsersTable -Entity $User -Force

    $CreatedUsers += @{
        UserId = $UserId
        Username = $TestUser.Username
        Role = $TestUser.Role
    }
}


# Create test links for the demo user
$LinksTable = Get-LinkToMeTable -TableName 'Links'
$DemoUser = $CreatedUsers | Where-Object { $_.Username -eq 'demo' }

# Create pages for demo user
$PagesTable = Get-LinkToMeTable -TableName 'Pages'

Write-Host "`nCreating pages for demo user..." -ForegroundColor Yellow

# Create main page (default)
$MainPageId = 'page-' + (New-Guid).ToString()
$MainPage = @{
    PartitionKey = $DemoUser.UserId
    RowKey = $MainPageId
    Slug = 'main'
    Name = 'Main Links'
    IsDefault = $true
    CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
    UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
}
Add-LinkToMeAzDataTableEntity @PagesTable -Entity $MainPage -Force
Write-Host "  ✓ Created default page: main" -ForegroundColor Green

# Create additional page for demo
$SocialPageId = 'page-' + (New-Guid).ToString()
$SocialPage = @{
    PartitionKey = $DemoUser.UserId
    RowKey = $SocialPageId
    Slug = 'social'
    Name = 'Social Media'
    IsDefault = $false
    CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
    UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
}
Add-LinkToMeAzDataTableEntity @PagesTable -Entity $SocialPage -Force
Write-Host "  ✓ Created page: social" -ForegroundColor Green

# Create pages for test user
$TestUser = $CreatedUsers | Where-Object { $_.Username -eq 'test' }

Write-Host "`nCreating pages for test user..." -ForegroundColor Yellow

$TestMainPageId = 'page-' + (New-Guid).ToString()
$TestMainPage = @{
    PartitionKey = $TestUser.UserId
    RowKey = $TestMainPageId
    Slug = 'main'
    Name = 'Main Links'
    IsDefault = $true
    CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
    UpdatedAt = (Get-Date).ToUniversalTime().ToString('o')
}
Add-LinkToMeAzDataTableEntity @PagesTable -Entity $TestMainPage -Force
Write-Host "  ✓ Created default page: main" -ForegroundColor Green

$Links = @(
    @{ Title = 'GitHub'; Url = 'https://github.com'; Order = 1; Active = $true }
    @{ Title = 'Twitter'; Url = 'https://twitter.com'; Order = 2; Active = $true }
    @{ Title = 'LinkedIn'; Url = 'https://linkedin.com'; Order = 3; Active = $true }
    @{ Title = 'Website'; Url = 'https://example.com'; Order = 4; Active = $true }
    @{ Title = 'YouTube'; Url = 'https://youtube.com'; Order = 5; Active = $true }
)

Write-Host "`nCreating $($Links.Count) links for demo user..." -ForegroundColor Yellow
foreach ($Link in $Links) {
    $Entity = @{
        PartitionKey = $DemoUser.UserId
        RowKey = 'link-' + (New-Guid).ToString()
        PageId = $MainPageId
        Title = $Link.Title
        Url = $Link.Url
        Order = $Link.Order
        Active = $Link.Active
    }
    Add-LinkToMeAzDataTableEntity @LinksTable -Entity $Entity -Force
}

# Create some links for the social page
$SocialLinks = @(
    @{ Title = 'Instagram'; Url = 'https://instagram.com'; Order = 1; Active = $true }
    @{ Title = 'Facebook'; Url = 'https://facebook.com'; Order = 2; Active = $true }
    @{ Title = 'TikTok'; Url = 'https://tiktok.com'; Order = 3; Active = $true }
)

Write-Host "Creating $($SocialLinks.Count) links for demo user's social page..." -ForegroundColor Yellow
foreach ($Link in $SocialLinks) {
    $Entity = @{
        PartitionKey = $DemoUser.UserId
        RowKey = 'link-' + (New-Guid).ToString()
        PageId = $SocialPageId
        Title = $Link.Title
        Url = $Link.Url
        Order = $Link.Order
        Active = $Link.Active
    }
    Add-LinkToMeAzDataTableEntity @LinksTable -Entity $Entity -Force
}

Write-Host "`n✅ Test users created successfully!" -ForegroundColor Green
Write-Host "`n✅ Test pages created: 3 total (demo: 2 pages, test: 1 page)" -ForegroundColor Green
Write-Host "`n✅ Test links created: $($Links.Count + $SocialLinks.Count) total (demo main: $($Links.Count), demo social: $($SocialLinks.Count))" -ForegroundColor Green

Write-Host "`n📋 User Accounts:" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray


Write-Host "`n1️⃣  Demo User Account:" -ForegroundColor Cyan
Write-Host "   Email:    demo@example.com" -ForegroundColor White
Write-Host "   Password: password123" -ForegroundColor White
Write-Host "   Username: demo" -ForegroundColor White
Write-Host "   Role:     user" -ForegroundColor Yellow
Write-Host "   Pages:    main (default), social" -ForegroundColor Gray

Write-Host "`n2️⃣  Test User Account:" -ForegroundColor Cyan
Write-Host "   Email:    test@example.com" -ForegroundColor White
Write-Host "   Password: test123" -ForegroundColor White
Write-Host "   Username: test" -ForegroundColor White
Write-Host "   Role:     user" -ForegroundColor Yellow
Write-Host "   Pages:    main (default)" -ForegroundColor Gray

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "`n🚀 You can now:" -ForegroundColor White
Write-Host "1. Start the API: func start" -ForegroundColor Gray
Write-Host "2. Test login: POST /api/public/login" -ForegroundColor Gray
Write-Host "3. View public profile (main): GET /api/public/getUserProfile?username=demo" -ForegroundColor Gray
Write-Host "4. View public profile (social): GET /api/public/getUserProfile?username=demo&slug=social" -ForegroundColor Gray
Write-Host "5. List pages: GET /api/admin/getPages (requires auth)" -ForegroundColor Gray