# Create or update Company table with company metadata
$CompanyTable = Get-LinkToMeTable -TableName 'Company'
$CompanyEntity = @{
    PartitionKey = $CompanyId
    RowKey = $CompanyId
    CompanyName = 'Acme Corp'
    Created = (Get-Date).ToString('o')
    Description = 'Demo company for LinkToMe'
    Logo = 'https://example.com/logo.png'
    Integrations = 'Slack, Zapier'
}
Write-Host "Creating company entity: $($CompanyEntity.CompanyName) ($CompanyId)" -ForegroundColor Yellow
Add-LinkToMeAzDataTableEntity @CompanyTable -Entity $CompanyEntity -Force
# Run this to create test users and links in Azurite
$ScriptRoot = Split-Path -Parent $PSScriptRoot
$ModulesPath = Join-Path $ScriptRoot 'Modules'

Import-Module (Join-Path $ModulesPath 'LinkTomeCore/LinkTomeCore.psd1') -Force
Import-Module (Join-Path $ModulesPath 'AzBobbyTables') -Force

$env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
$env:JWT_SECRET = 'dev-secret-change-in-production-please-make-this-very-long-and-random-at-least-64-characters'

Write-Host "`nCreating test users and links in Azurite..." -ForegroundColor Cyan
Write-Host "This will create 3 users (all with role 'user'), and company membership/roles are managed in CompanyUsers table." -ForegroundColor Cyan

$UsersTable = Get-LinkToMeTable -TableName 'Users'

# Define test users with different roles
$TestUsers = @(
    @{
        Email = 'demo@example.com'
        Username = 'demo'
        DisplayName = 'Demo User'
        Bio = 'This is a demo account for LinkToMe (regular user)'
        Role = 'user'
        Password = 'password123'
    }
    @{
        Email = 'admin@example.com'
        Username = 'admin'
        DisplayName = 'Admin User'
        Bio = 'This is a company admin account for LinkToMe'
        Role = 'company_admin'
        Password = 'admin123'
    }
    @{
        Email = 'owner@example.com'
        Username = 'companyowner'
        DisplayName = 'Company Owner'
        Bio = 'This is a company owner account for LinkToMe'
        Role = 'company_owner'
        Password = 'owner123'
    }
)

$CreatedUsers = @()


# Create test users and company-user associations
$CompanyUsersTable = Get-LinkToMeTable -TableName 'CompanyUsers'
$CompanyId = 'company-1'

foreach ($TestUser in $TestUsers) {
    $PasswordData = New-PasswordHash -Password $TestUser.Password
    $UserId = 'user-' + (New-Guid).ToString()
    $DefaultPermissions = Get-DefaultRolePermissions -Role $TestUser.Role

    # Convert arrays to JSON strings for Azure Table Storage compatibility
    $RolesJson = [string](@($TestUser.Role) | ConvertTo-Json -Compress)
    $PermissionsJson = [string]($DefaultPermissions | ConvertTo-Json -Compress)

    $IsCompanyMember = $TestUser.Role -ne 'user'
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
        Permissions = ([string](Get-DefaultRolePermissions -Role 'user' | ConvertTo-Json -Compress))
        CompanyMember = [bool]$IsCompanyMember
    }

    Write-Host "Creating user: $($User.PartitionKey) (Role: $($TestUser.Role))" -ForegroundColor Yellow
    Add-LinkToMeAzDataTableEntity @UsersTable -Entity $User -Force


    if ($IsCompanyMember) {
        # Add company-user association only for company members
        $CompanyUser = @{
            PartitionKey = $CompanyId
            RowKey = $UserId
            Role = $TestUser.Role
            CompanyEmail = $TestUser.Email
            CompanyDisplayName = $TestUser.DisplayName
            Username = $TestUser.Username
        }
        Write-Host "Creating company-user: $($CompanyUser.Username) in $CompanyId as $($CompanyUser.Role)" -ForegroundColor Yellow
        Add-LinkToMeAzDataTableEntity @CompanyUsersTable -Entity $CompanyUser -Force
    }

    $CreatedUsers += @{
        UserId = $UserId
        Username = $TestUser.Username
        Role = $TestUser.Role
    }
}


# Create test links for the demo user (regular user)
$LinksTable = Get-LinkToMeTable -TableName 'Links'
$DemoUser = $CreatedUsers | Where-Object { $_.Username -eq 'demo' }

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
        Title = $Link.Title
        Url = $Link.Url
        Order = $Link.Order
        Active = $Link.Active
    }
    Add-LinkToMeAzDataTableEntity @LinksTable -Entity $Entity -Force
}

Write-Host "`n✅ Test users created successfully!" -ForegroundColor Green
Write-Host "`n📋 User Accounts:" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray


Write-Host "`n1️⃣  Regular User Account:" -ForegroundColor Cyan
Write-Host "   Email:    demo@example.com" -ForegroundColor White
Write-Host "   Password: password123" -ForegroundColor White
Write-Host "   Username: demo" -ForegroundColor White
Write-Host "   Role:     user (not a company member)" -ForegroundColor Yellow

Write-Host "`n2️⃣  Company Admin Account:" -ForegroundColor Cyan
Write-Host "   Email:    admin@example.com" -ForegroundColor White
Write-Host "   Password: admin123" -ForegroundColor White
Write-Host "   Username: admin" -ForegroundColor White
Write-Host "   Role:     user (company_admin in CompanyUsers)" -ForegroundColor Yellow

Write-Host "`n3️⃣  Company Owner Account:" -ForegroundColor Cyan
Write-Host "   Email:    owner@example.com" -ForegroundColor White
Write-Host "   Password: owner123" -ForegroundColor White
Write-Host "   Username: companyowner" -ForegroundColor White
Write-Host "   Role:     user (company_owner in CompanyUsers)" -ForegroundColor Yellow
Write-Host "`n🏢 Company Table Created:" -ForegroundColor Cyan
Write-Host "   CompanyId: $CompanyId" -ForegroundColor White
Write-Host "   Name:      Acme Corp" -ForegroundColor White
Write-Host "   Description: Demo company for LinkToMe" -ForegroundColor White

Write-Host "`n✅ Test links created: $($Links.Count) (for demo user)" -ForegroundColor Green

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "`n🚀 You can now:" -ForegroundColor White
Write-Host "1. Start the API: func start" -ForegroundColor Gray
Write-Host "2. Test login: POST /api/public/login" -ForegroundColor Gray
Write-Host "3. View public profile: GET /api/public/getUserProfile?username=demo" -ForegroundColor Gray
Write-Host "4. Test role management: PUT /api/admin/assignRole (admin/owner only)" -ForegroundColor Gray
Write-Host "5. Test permissions: GET /api/admin/getUserRoles (admin/owner only)" -ForegroundColor Gray