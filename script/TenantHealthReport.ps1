param(
  [Parameter(Mandatory=$true)] [string]$TenantId,
  [Parameter(Mandatory=$true)] [string]$ClientId,
  [Parameter(Mandatory=$true)] [string]$ClientSecret,
  [int]$TopActionsCount = 20,
  [string]$OutputFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GraphToken {
  param([string]$TenantId,[string]$ClientId,[string]$ClientSecret)

  $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
  $body = @{ 
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "https://graph.microsoft.com/.default"
  }

  (Invoke-RestMethod -Method Post -Uri $tokenUri -Body $body -ContentType "application/x-www-form-urlencoded").access_token
}

function Invoke-Graph {
  param([string]$Token,[string]$Uri)
  $headers = @{ Authorization = "Bearer $Token" }
  Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
}

function Invoke-GraphPaged {
param([string]$Token,[string]$Uri)
$all = @()
$next = $Uri
while ($null -ne $next -and $next -ne "") {
$res = Invoke-Graph -Token $Token -Uri $next
if ($null -ne $res -and $null -ne $res.value) {
  $all += $res.value
}

$prop = $res.PSObject.Properties['@odata.nextLink']
if ($null -ne $prop -and $null -ne $prop.Value -and $prop.Value -ne "") {
  $next = $prop.Value
} else {
  $next = $null
}

}
return $all
}

function HtmlEncode {
  param([string]$s)
  if ($null -eq $s) { return "" }
  [System.Net.WebUtility]::HtmlEncode($s)
}

function KpiClassForServiceHealth {
  param([string]$status)
  if ($null -eq $status) { return "kpi-yellow" }
  if ($status -eq "serviceOperational") { return "kpi-green" }
  return "kpi-red"
}

function ImpactFromMaxScore {
  param([double]$maxScore)
  if ($maxScore -ge 5) { return "High" }
  return "Medium"
}

function BadgeHtml {
  param([string]$kind,[string]$text)
  switch ($kind) {
    "not"     { return "<span class='badge badge-not'>$text</span>" }
    "partial" { return "<span class='badge badge-partial'>$text</span>" }
    "ok"      { return "<span class='badge badge-ok'>$text</span>" }
    "high"    { return "<span class='badge badge-not'>$text</span>" }
    "med"     { return "<span class='badge badge-partial'>$text</span>" }
    default    { return "<span class='badge'>$text</span>" }
  }
}

$token = Get-GraphToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

$tenantLabel = "Tenant"
try {
$org = Invoke-Graph -Token $token -Uri "https://graph.microsoft.com/v1.0/organization?`$select=verifiedDomains,displayName"
if ($null -ne $org.value -and $org.value.Count -gt 0) {
$o = $org.value[0]
$defaultDomain = $null
if ($null -ne $o.verifiedDomains) {
  $defaultDomain = ($o.verifiedDomains | Where-Object { $_.isDefault -eq $true } | Select-Object -First 1).name
}

$dn = [string]$o.displayName

if (-not [string]::IsNullOrWhiteSpace($dn) -and -not [string]::IsNullOrWhiteSpace($defaultDomain)) {
  $tenantLabel = "$dn ($defaultDomain)"
}
elseif (-not [string]::IsNullOrWhiteSpace($defaultDomain)) {
  $tenantLabel = $defaultDomain
}
elseif (-not [string]::IsNullOrWhiteSpace($dn)) {
  $tenantLabel = $dn
}

}
} catch {
$tenantLabel = "Tenant"
}

Write-Host "DEBUG: tenantLabel = '$tenantLabel'"
try {
$org2 = Invoke-Graph -Token $token -Uri "https://graph.microsoft.com/v1.0/organization?`$select=verifiedDomains,displayName"
$o2 = $null
if ($null -ne $org2.value -and $org2.value.Count -gt 0) {
$o2 = $org2.value[0]
}
$vdCount = 0
if ($null -ne $o2 -and $null -ne $o2.verifiedDomains) {
$vdCount = $o2.verifiedDomains.Count
}
$dn = ""
if ($null -ne $o2) {
$dn = [string]$o2.displayName
}
Write-Host "DEBUG: org displayName = '$dn'"
Write-Host "DEBUG: verifiedDomains count = $vdCount"
if ($vdCount -gt 0) {
$def = ($o.verifiedDomains | Where-Object { $_.isDefault -eq $true } | Select-Object -First 1).name
Write-Host "DEBUG: defaultDomain from verifiedDomains = '$def'"
}
}
catch {
Write-Host "ERROR: organization call failed: $($_.Exception.Message)"
}

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
  $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $OutputFile = "TenantHealth_$ts.html"
}
$outPath = Join-Path (Get-Location) $OutputFile

# 1) Service Health
$serviceHealth = @()
try {
  $svcUri = "https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/healthOverviews"
  $serviceHealth = (Invoke-Graph -Token $token -Uri $svcUri).value
} catch { $serviceHealth = @() }

$serviceHealthKpiHtml = ""
foreach ($s in $serviceHealth) {
  $name = HtmlEncode($s.service)
  $status = HtmlEncode($s.status)
  $cls = KpiClassForServiceHealth -status $s.status
  $serviceHealthKpiHtml += "<div class='kpi $cls'><div class='kpi-title'>$name</div><div class='kpi-value'>$status</div></div>" + "`n"
}

# 2) Secure Score (latest)
$secureScore = $null
try {
  $ssUri = "https://graph.microsoft.com/v1.0/security/secureScores?`$top=1"
  $secureScore = (Invoke-Graph -Token $token -Uri $ssUri).value | Select-Object -First 1
} catch { $secureScore = $null }

$currentScore = 0
$maxScore = 0
$percent = 0
$controlScores = @()

if ($secureScore) {
  $currentScore = [double]$secureScore.currentScore
  $maxScore = [double]$secureScore.maxScore
  if ($maxScore -gt 0) { $percent = [Math]::Round(($currentScore / $maxScore) * 100, 0) }
  $controlScores = $secureScore.controlScores
}

Write-Host "DEBUG: controlScores count = $($controlScores.Count)"

# 3) Control Profiles
$profilesById = @{}
try {
  $profUri = "https://graph.microsoft.com/v1.0/security/secureScoreControlProfiles"
  $profiles = Invoke-GraphPaged -Token $token -Uri $profUri
  foreach ($p in $profiles) { $profilesById[$p.id] = $p }
} catch { 
  $profilesById = @{}
  Write-Host "ERROR: secureScoreControlProfiles failed: $($_.Exception.Message)"
}

Write-Host "DEBUG: profilesById count = $($profilesById.Keys.Count)"

# 4) Join controls
$controls = @()
foreach ($c in $controlScores) {
  $id = $c.controlName
  if (-not $profilesById.ContainsKey($id)) { continue }
  $p = $profilesById[$id]

  $scoreVal = 0.0
  if ($null -ne $c.score) { $scoreVal = [double]$c.score }

  $maxVal = 0.0
  if ($null -ne $p.maxScore) { $maxVal = [double]$p.maxScore }

  $status = "Implemented"
  if ($scoreVal -le 0) { $status = "Not" }
  elseif ($maxVal -gt 0 -and $scoreVal -lt $maxVal) { $status = "Partial" }

  $rank = 9999
  if ($null -ne $p.rank) { $rank = [int]$p.rank }

  $impact = ImpactFromMaxScore -maxScore $maxVal

  $controls += [pscustomobject]@{
    rank       = $rank
    title      = [string]$p.title
    status     = $status
    score      = $scoreVal
    max        = $maxVal
    impact     = $impact
    actionUrl  = [string]$p.actionUrl
    remediation= [string]$p.remediation
  }
}

# 5) Top Actions (sorted)
$topActions = $controls |
  Where-Object { $_.status -in @('Not','Partial') } |
  Sort-Object rank |
  Select-Object -First $TopActionsCount

$topActionsRows = ""
foreach ($t in $topActions) {
  $rank = HtmlEncode([string]$t.rank)
  $title = HtmlEncode($t.title)
  $scoreText = HtmlEncode(("{0:0} / {1:0}" -f $t.score, $t.max))
  $url = HtmlEncode($t.actionUrl)

  $statusBadge = if ($t.status -eq "Not") { BadgeHtml -kind "not" -text "Not implemented" } else { BadgeHtml -kind "partial" -text "Partially implemented" }
  $impactBadge = if ($t.impact -eq "High") { BadgeHtml -kind "high" -text "High" } else { BadgeHtml -kind "med" -text "Medium" }

  $topActionsRows += "<tr><td>$rank</td><td>$title</td><td>$statusBadge</td><td>$scoreText</td><td>$impactBadge</td><td class='url'><a href='$url'>Open</a></td></tr>" + "`n"
}

# 6) Not/Partial tables
$notRows = ""
$partialRows = ""

$notControls = $controls | Where-Object { $_.status -eq "Not" } | Sort-Object rank
foreach ($n in $notControls) {
  $title = HtmlEncode($n.title)
  $scoreVal = HtmlEncode(("{0:0}" -f $n.score))
  $maxVal = HtmlEncode(("{0:0}" -f $n.max))
  $rem = $n.remediation

  $notRows += "<tr><td>$title</td><td>$(BadgeHtml -kind 'not' -text 'Not implemented')</td><td>$scoreVal</td><td>$maxVal</td><td><details><summary>Visa mer</summary><div class='small'>$rem</div></details></td></tr>" + "`n"
}

$partialControls = $controls | Where-Object { $_.status -eq "Partial" } | Sort-Object rank
foreach ($p in $partialControls) {
  $title = HtmlEncode($p.title)
  $scoreVal = HtmlEncode(("{0:0}" -f $p.score))
  $maxVal = HtmlEncode(("{0:0}" -f $p.max))
  $rem = $p.remediation

  $partialRows += "<tr><td>$title</td><td>$(BadgeHtml -kind 'partial' -text 'Partially implemented')</td><td>$scoreVal</td><td>$maxVal</td><td><details><summary>Visa mer</summary><div class='small'>$rem</div></details></td></tr>" + "`n"
}

# 7) Alerts counts
$alertsHigh = 0
$alertsMed = 0
try {
  $alertsUri = "https://graph.microsoft.com/v1.0/security/alerts_v2?`$top=200"
  $alerts = Invoke-GraphPaged -Token $token -Uri $alertsUri
  $alertsHigh = ($alerts | Where-Object { $_.severity -eq "high" }).Count
  $alertsMed  = ($alerts | Where-Object { $_.severity -eq "medium" }).Count
} catch {
  $alertsHigh = 0
  $alertsMed = 0
}

# 8) Failed sign-ins last 24h
$failedSignins = 0
try {
  $since = (Get-Date).ToUniversalTime().AddHours(-24).ToString("yyyy-MM-ddTHH:mm:ssZ")
  $signInUri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=createdDateTime ge $since&`$top=1000"
  $signins = Invoke-GraphPaged -Token $token -Uri $signInUri
  $failedSignins = ($signins | Where-Object { $_.status.errorCode -ne 0 }).Count
} catch {
  $failedSignins = 0
}

$generated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$html = @"
<html>
<head>
  <meta charset="utf-8">
  <title>Tenant Health Report</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; background:#f5f6f8; color:#222; padding:20px; }
    .page-header { text-align: left; margin-bottom: 24px; }
    .page-title { color: #0f6cbd; font-size: 32px; font-weight: 800; line-height: 1.1; margin: 0; }
    .page-subtitle { color: #222; font-size: 13px; font-weight: 400; line-height: 1.4; margin-top: 8px;}
    .card { background:#fff; border-radius:6px; box-shadow:0 1px 3px rgba(0,0,0,.08); padding:16px; margin-bottom:20px; }
    .card h2 { margin-top:0; margin-bottom:10px; color:#0f6cbd; }
    .card h3 { margin-top:12px; margin-bottom:10px; }
    .card-content { padding-left:8px; }
    ul, ol { list-style:none; margin:0; padding:0; }
    table { width:100%; border-collapse:collapse; table-layout:fixed; }
    th { background:#0f6cbd; color:#fff; padding:8px; text-align:left; font-size:12px; }
    td { padding:8px; border-bottom:1px solid #e5e5e5; font-size:12px; vertical-align:top; word-break:break-word; line-height:1.4; }
    tr:last-child td { border-bottom:none; }
    table tr:nth-child(even) td { background:#fafafa; }
    table tr:hover td { background:#eef6ff; }
    .small { font-size:11px; color:#555; }
    .kpi-row { display:flex; gap:16px; flex-wrap:wrap; align-items:stretch; margin-top:8px; }
    .kpi { background:#f5f6f8; border-radius:8px; padding:12px 16px; min-width:140px; box-shadow:inset 0 0 0 1px #e5e5e5; flex:0 0 220px; }
    .kpi-title { font-size:11px; color:#666; margin-bottom:4px; font-weight:600; }
    .kpi-value { font-size:18px; font-weight:700; line-height:1.2; }
    .kpi-blue { border-left:4px solid #0f6cbd; }
    .kpi-red { border-left:4px solid #b00020; }
    .kpi-yellow { border-left:4px solid #8a6100; }
    .kpi-green { border-left:4px solid #107c10; }
    .badge { display:inline-block; padding:2px 10px; border-radius:12px; font-size:11px; font-weight:600; white-space:nowrap; }
    .badge-not { background:#fde7e9; color:#b00020; }
    .badge-partial { background:#fff4ce; color:#8a6100; }
    .badge-ok { background:#e6f4ea; color:#107c10; }
    .url a { color:#0f6cbd; text-decoration:none; font-weight:600; }
    .url a:hover { text-decoration:underline; }
    details summary { cursor:pointer; color:#0f6cbd; font-size:11px; margin-top:6px; font-weight:600; }
    details > div { margin-top:6px; font-size:11px; line-height:1.4; }
  </style>
</head>
<body>

  <div class="page-header">
    <div class="page-title">
      Tenant Health Report – $([System.Net.WebUtility]::HtmlEncode($tenantLabel))
    </div>
    <div class="page-subtitle">
      This report provides an overview of the tenant’s security and health posture,
      including Service Health, Secure Score, security alerts, sign-in risk,
      and recommended security actions based on Microsoft Graph data.
    </div>
  </div>

  <div class="card">
    <h2>Service Health</h2>
    <div class="card-content">
      <div class="kpi-row">
        $serviceHealthKpiHtml
      </div>
    </div>
  </div>

  <div class="card">
    <h2>Secure Score</h2>
    <div class="card-content">
      <div class="kpi-row">
        <div class="kpi kpi-blue"><div class="kpi-title">Current score</div><div class="kpi-value">$([Math]::Round($currentScore,0))</div></div>
        <div class="kpi kpi-blue"><div class="kpi-title">Max score</div><div class="kpi-value">$([Math]::Round($maxScore,0))</div></div>
        <div class="kpi kpi-blue"><div class="kpi-title">Completion</div><div class="kpi-value">$percent%</div></div>
      </div>
    </div>
  </div>

  <div class="card">
    <h2>Security Alerts</h2>
    <div class="card-content">
      <div class="kpi-row">
        <div class="kpi kpi-red"><div class="kpi-title">High alerts</div><div class="kpi-value">$alertsHigh</div></div>
        <div class="kpi kpi-yellow"><div class="kpi-title">Medium alerts</div><div class="kpi-value">$alertsMed</div></div>
      </div>
    </div>
  </div>

  <div class="card">
    <h2>Identity / Sign-in risk</h2>
    <div class="card-content">
      <div class="kpi-row">
        <div class="kpi kpi-blue"><div class="kpi-title">Failed sign-ins (24h)</div><div class="kpi-value">$failedSignins</div></div>
      </div>
    </div>
  </div>

  <div class="card">
    <h2>Security Best Practices</h2>
    <h3>Top Actions</h3>
    <div class="card-content">
      <p class="small">Top Actions shows up to $TopActionsCount items (Not + Partial), sorted by rank.</p>
      <table>
        <colgroup>
          <col style="width:60px;">
          <col style="width:45%;">
          <col style="width:110px;">
          <col style="width:120px;">
          <col style="width:110px;">
          <col style="width:90px;">
        </colgroup>
        <tr>
          <th>Rank</th><th>Control</th><th>Status</th><th>Score</th><th>Impact</th><th>Action</th>
        </tr>
        $topActionsRows
      </table>
    </div>
  </div>

  <div class="card">
    <h3>Not Implemented</h3>
    <div class="card-content">
      <table>
        <colgroup>
          <col style="width:40%;">
          <col style="width:160px;">
          <col style="width:90px;">
          <col style="width:90px;">
          <col>
        </colgroup>
        <tr>
          <th>Control</th><th>Status</th><th>Score</th><th>Max</th><th>Remediation</th>
        </tr>
        $notRows
      </table>
    </div>
  </div>

  <div class="card">
    <h3>Partially Implemented</h3>
    <div class="card-content">
      <table>
        <colgroup>
          <col style="width:40%;">
          <col style="width:160px;">
          <col style="width:90px;">
          <col style="width:90px;">
          <col>
        </colgroup>
        <tr>
          <th>Control</th><th>Status</th><th>Score</th><th>Max</th><th>Remediation</th>
        </tr>
        $partialRows
      </table>
    </div>
  </div>

  <div class="small">Generated: $generated</div>

</body>
</html>
"@

[System.IO.File]::WriteAllText($outPath, $html, [System.Text.Encoding]::UTF8)
Write-Host "OK: Wrote $outPath"
