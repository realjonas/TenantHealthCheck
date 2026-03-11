# Tenant Health Report – HowTo

## Overview

This runbook describes how to use the **TenantHealthReport.ps1** script to generate an HTML-based Microsoft 365 Tenant Health report using Microsoft Graph with app-only authentication.

The report includes:
- Tenant header: **DisplayName (defaultDomain)**
- Service Health (KPI)
- Secure Score (KPI)
- Security Alerts
- Sign-in risk
- Top Actions
- Not Implemented / Partially Implemented controls

The script is intended as a replacement for Power Automate flows when cross-tenant export is required.

---

## Prerequisites

### PowerShell
- PowerShell 7.x (recommended)
- Windows PowerShell 5.1 also works

Check version:
```powershell
$PSVersionTable.PSVersion
```

---

### Required Azure AD / Entra ID roles

You must be able to:
- Create App registrations **or**
- Grant admin consent to Microsoft Graph Application permissions

One of the following roles is required:
- Application Administrator
- Global Administrator

---

## Required Microsoft Graph permissions (Application)

The report script uses **app-only** authentication.

| Permission | Purpose |
|----------|---------|
| Organization.Read.All | Read displayName and verifiedDomains |
| Directory.Read.All | Fallback directory access |
| SecurityEvents.Read.All | Secure Score + control profiles |
| AuditLog.Read.All | Sign-in risk |

All permissions require **Admin consent**.

---

## Create App Registration automatically (recommended)

Save the following script as **Create-AppRegistration.ps1**.

```powershell
param(
  [string]$AppName = "TenantHealthReport-App"
)

Connect-MgGraph -Scopes "Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All","Directory.Read.All"

$app = New-MgApplication -DisplayName $AppName
$sp  = New-MgServicePrincipal -AppId $app.AppId

$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

$permissions = @(
  "Organization.Read.All",
  "Directory.Read.All",
  "SecurityEvents.Read.All",
  "AuditLog.Read.All"
)

$resourceAccess = @()
foreach ($perm in $permissions) {
  $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $perm }
  $resourceAccess += @{ Id = $role.Id; Type = "Role" }
}

Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess @(
  @{ ResourceAppId = $graphSp.AppId; ResourceAccess = $resourceAccess }
)

foreach ($role in $resourceAccess) {
  New-MgServicePrincipalAppRoleAssignment     -ServicePrincipalId $sp.Id     -PrincipalId $sp.Id     -ResourceId $graphSp.Id     -AppRoleId $role.Id
}

$secret = Add-MgApplicationPassword -ApplicationId $app.Id -DisplayName "TenantHealthReportSecret"

Write-Host "TenantId     : $(Get-MgContext).TenantId"
Write-Host "ClientId     : $($app.AppId)"
Write-Host "ClientSecret : $($secret.SecretText)"
```

Run:
```powershell
./Create-AppRegistration.ps1
```

Save the output values:
- TenantId
- ClientId
- ClientSecret

---

## Running the Tenant Health Report

Place the following files in the same directory:
- TenantHealthReport.ps1
- HowTo.md

Run the report:
```powershell
./TenantHealthReport.ps1   -TenantId "<TENANT-ID>"   -ClientId "<CLIENT-ID>"   -ClientSecret "<CLIENT-SECRET>"
```

---

## Output

The script generates an HTML file in the current directory:

```
TenantHealth_YYYYMMDD_HHMMSS.html
```

Open the file in any modern browser.

---

## Tenant name logic

The report header is generated as:

```
Tenant Health Report – DisplayName (defaultDomain)
```

Example:
```
Tenant Health Report – EVRY ONE BORAS AB (syslabnu.onmicrosoft.com)
```

Logic order:
1. organization.displayName
2. organization.verifiedDomains where isDefault = true
3. Combined label

Fallback:
- "Tenant" if Graph access fails

---

## Common issues

### Tenant name shows as "Tenant"

Cause:
- Missing Organization.Read.All permission

Fix:
- Add permission
- Grant admin consent
- Wait 2–5 minutes

---

### Top Actions / Not Implemented empty

Cause:
- Missing SecurityEvents.Read.All

Fix:
- Add permission
- Grant admin consent

---

## Security considerations

- App uses read-only permissions
- No data is written back to tenant
- Client secret should be stored securely

---

## Optional improvements

- Run as Azure Automation Runbook
- Schedule execution
- Upload HTML to SharePoint
- Send report by email

---

## End

This runbook documents a tenant-agnostic, reusable reporting solution suitable for cross-tenant use.
