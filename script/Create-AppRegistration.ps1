param(
  [string]$AppName = "TenantHealthReport-App"
)

Connect-MgGraph -Scopes "Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All","Directory.Read.All"

# Create app
$app = New-MgApplication -DisplayName $AppName

# Create service principal
$sp = New-MgServicePrincipal -AppId $app.AppId

# Add Graph permissions
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

$requiredPermissions = @(
  "Organization.Read.All",
  "Directory.Read.All",
  "SecurityEvents.Read.All",
  "AuditLog.Read.All"
)

$resourceAccess = @()
foreach ($perm in $requiredPermissions) {
  $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $perm }
  $resourceAccess += @{
    Id   = $role.Id
    Type = "Role"
  }
}

Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess @(
  @{
    ResourceAppId  = $graphSp.AppId
    ResourceAccess = $resourceAccess
  }
)

# Grant admin consent
foreach ($role in $resourceAccess) {
  New-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $sp.Id `
    -PrincipalId $sp.Id `
    -ResourceId $graphSp.Id `
    -AppRoleId $role.Id
}

# Create client secret
$secret = Add-MgApplicationPassword -ApplicationId $app.Id -DisplayName "TenantHealthReportSecret"

Write-Host ""
Write-Host "==== APP REGISTRATION KLAR ===="
Write-Host "TenantId     : $(Get-MgContext).TenantId"
Write-Host "ClientId     : $($app.AppId)"
Write-Host "ClientSecret : $($secret.SecretText)"
Write-Host "================================"