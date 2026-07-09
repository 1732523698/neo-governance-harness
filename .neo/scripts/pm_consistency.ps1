<#
.SYNOPSIS
  NEO_PM contract-integrity check: cross-field SEMANTIC consistency of session_contract.json.
.DESCRIPTION
  verify_session.ps1 checks that required fields are PRESENT. This script checks that the
  contract is internally CONSISTENT and safe to start a session from. It is the falsifiable
  backbone of NEO_PM: PM does not "judge" by vibe; it runs these rules.

  HARD rules exit non-zero on failure. WARN rules report but do not fail.
  Emits pm_consistency_report.json into the session folder.
.EXAMPLE
  .\pm_consistency.ps1 -SessionPath S:\NEO\NEO_SESSION\2026-06-09_hello-module
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SessionPath
)
$ErrorActionPreference = 'Stop'
$contractPath = Join-Path $SessionPath 'session_contract.json'
if (-not (Test-Path -LiteralPath $contractPath)) { throw "session_contract.json not found at $contractPath" }
try { $c = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "session_contract.json is not valid JSON" }

$findings = @()
function Add-Finding($rule, $level, $ok, $detail) {
  $status = 'PASS'
  if (-not $ok) { if ($level -eq 'HARD') { $status = 'FAIL' } else { $status = 'WARN' } }
  $script:findings += [pscustomobject]@{ Rule = $rule; Level = $level; Status = $status; Detail = $detail }
}
function Test-HasKey($obj, $key) { if ($null -eq $obj) { return $false }; return (@($obj.PSObject.Properties.Name) -contains $key) }

# Gather a flat list of string values to scan for leftover REPLACE_ME placeholders.
$allText = @()
$allText += [string]$c.goal
$allText += @($c.approved_paths)
$allText += @($c.test_plan)
$placeholder = ($allText | Where-Object { $_ -and ($_ -match 'REPLACE_ME') })

# P1 - no leftover template placeholders
Add-Finding 'P1 no REPLACE_ME placeholders' 'HARD' ($placeholder.Count -eq 0) `
  ($(if ($placeholder.Count -eq 0) { 'none' } else { "found in: " + ($placeholder -join ' | ') }))

# P2 - approved_paths non-empty
Add-Finding 'P2 approved_paths non-empty' 'HARD' (@($c.approved_paths).Count -gt 0) `
  ("count=" + @($c.approved_paths).Count)

# P3 - governance dirs are protected (sandbox cannot edit its own controls)
$prot = @($c.protected_paths)
$neoProt = ($prot | Where-Object { $_ -like '.neo*' }).Count -gt 0
$claudeProt = ($prot | Where-Object { $_ -like '.claude*' }).Count -gt 0
Add-Finding 'P3 .neo protected' 'HARD' $neoProt 'governance scripts/schemas must be never-touch'
Add-Finding 'P3 .claude protected' 'HARD' $claudeProt 'skill definitions must be never-touch'

# P4 - approved/protected do not overlap
$overlap = @()
foreach ($a in @($c.approved_paths)) { if ($prot -contains $a) { $overlap += $a } }
Add-Finding 'P4 approved/protected disjoint' 'HARD' ($overlap.Count -eq 0) `
  ($(if ($overlap.Count -eq 0) { 'disjoint' } else { "overlap: " + ($overlap -join ', ') }))

# P5 - state_surfaces non-empty
Add-Finding 'P5 state_surfaces non-empty' 'HARD' (@($c.state_surfaces).Count -gt 0) `
  ("surfaces=[" + (@($c.state_surfaces) -join ',') + "]")

# P6 - external accounts => external_account surface declared (mirror of C5 guard, at contract level)
$extReg = @($c.external_accounts_registry)
$extDeclared = (@($c.state_surfaces) -contains 'external_account')
Add-Finding 'P6 external use declared as surface' 'HARD' (($extReg.Count -eq 0) -or $extDeclared) `
  ("external_accounts=" + $extReg.Count + "; external_account in surfaces=" + $extDeclared)

# P7 - every external account is sandbox-only by EXPLICIT HUMAN ATTESTATION + spend cap.
#      Sandbox status is NEVER inferred from the account name (a real 'sandbox-prod' must not pass).
$prodMarkers = '(?i)\b(prod|production|live|real|main)\b'
$badAccts = @()
foreach ($a in $extReg) {
  $who = $a.provider
  if ($a.environment -ne 'sandbox') { $badAccts += "${who}: environment != 'sandbox'" }
  if (-not $a.human_attested_sandbox_only) { $badAccts += "${who}: human_attested_sandbox_only != true" }
  if (-not $a.forbidden_real_data) { $badAccts += "${who}: forbidden_real_data != true" }
  if (-not $a.spend_cap_configured) { $badAccts += "${who}: spend_cap_configured=false" }
  if (-not $a.account_label) { $badAccts += "${who}: account_label missing" }
  if ($null -eq $a.allowed_domains) { $badAccts += "${who}: allowed_domains missing" }
  if ($a.account_label -match $prodMarkers -or $a.provider -match $prodMarkers) {
    $badAccts += "${who}: production/real marker in label/provider"
  }
}
Add-Finding 'P7 external accounts attested sandbox+capped' 'HARD' ($badAccts.Count -eq 0) `
  ($(if ($badAccts.Count -eq 0) { 'ok / none' } else { ($badAccts -join '; ') }))

# P8 - test_plan present (a promised command exists) when fresh_audit requires end_gate tests
Add-Finding 'P8 test_plan present' 'HARD' (@($c.test_plan).Count -gt 0) `
  ("count=" + @($c.test_plan).Count)

# P9 (WARN) - budget unset
$limit = 0; if (Test-HasKey $c 'budget') { $limit = [double]$c.budget.limit }
Add-Finding 'P9 budget limit set' 'WARN' ($limit -gt 0) ("budget.limit=" + $limit)

# P10 (WARN) - provider spend cap must be true before any UNATTENDED run
$cap = $false; if (Test-HasKey $c 'budget') { $cap = [bool]$c.budget.provider_spend_cap_configured }
Add-Finding 'P10 provider spend cap configured' 'WARN' $cap `
  ("provider_spend_cap_configured=" + $cap + " (MUST be true before unattended runs)")

# P11 - residue_keep_paths legality (only enforced if any are declared)
function Get-GlobBase($glob) { return ((($glob -replace '\\', '/') -split '\*')[0]).TrimEnd('/') }
$keep = @($c.residue_keep_paths)
$badKeep = @()
foreach ($k in $keep) {
  $kb = Get-GlobBase $k
  $inApproved = ($kb -like 'NEO_SESSION*')
  if (-not $inApproved) {
    foreach ($a in @($c.approved_paths)) { $ab = Get-GlobBase $a; if ($ab -and ($kb -like "$ab*")) { $inApproved = $true; break } }
  }
  if (-not $inApproved) { $badKeep += "${k}: not inside approved_paths or NEO_SESSION" }
  foreach ($p in @($c.protected_paths)) {
    $pb = Get-GlobBase $p
    if ($pb -and (($kb -like "$pb*") -or ($pb -like "$kb*"))) { $badKeep += "${k}: overlaps protected '$p'" }
  }
}
Add-Finding 'P11 residue_keep_paths legal' 'HARD' ($badKeep.Count -eq 0) `
  ($(if ($keep.Count -eq 0) { 'none declared' } elseif ($badKeep.Count -eq 0) { "$($keep.Count) legal" } else { ($badKeep -join '; ') }))

# ---- emit ----
$report = [pscustomobject]@{
  session_id = $c.session_id
  generated_for = $contractPath
  findings = $findings
}
$reportPath = Join-Path $SessionPath 'pm_consistency_report.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ""
Write-Host "NEO_PM contract-integrity: $contractPath"
$findings | Format-Table -AutoSize Rule, Level, Status, Detail
$hardFail = @($findings | Where-Object { $_.Status -eq 'FAIL' }).Count
$warn = @($findings | Where-Object { $_.Status -eq 'WARN' }).Count
Write-Host ""
Write-Host "Report written: $reportPath"
if ($hardFail -gt 0) {
  Write-Host "PM-INTEGRITY: FAIL - $hardFail hard rule(s) failed ($warn warning(s))." -ForegroundColor Red
  exit 1
} else {
  Write-Host "PM-INTEGRITY: PASS - 0 hard failures ($warn warning(s))." -ForegroundColor Green
  exit 0
}
