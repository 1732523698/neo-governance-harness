<#
.SYNOPSIS
  NEO_AMBASSADOR self-check: the END summary is COMPLETE and NOT SANITIZED.
.DESCRIPTION
  Ambassador may summarize, but must not sanitize. This script makes that falsifiable:
  if the machine artifacts (PM / verifier / auditor) carry red or warn signals, the human-facing
  ambassador_end_summary.md MUST acknowledge them. It also checks required fields, the exact
  decision question, and that no secret-shaped value leaked into the human surface.

  A* rules exit non-zero on failure.
.EXAMPLE
  .\ambassador_check.ps1 -SessionPath S:\NEO\NEO_SESSION\2026-06-09_hello-module
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SessionPath
)
$ErrorActionPreference = 'Stop'
function Read-Json($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
  catch { return '__PARSE_ERROR__' }
}
$rules = @()
function Add-Rule($id, $ok, $detail) {
  $status = 'PASS'; if (-not $ok) { $status = 'FAIL' }
  $script:rules += [pscustomobject]@{ Rule = $id; Status = $status; Detail = $detail }
}

$summaryPath = Join-Path $SessionPath 'ambassador_end_summary.md'

# ===== A1 - summary exists =====
if (-not (Test-Path -LiteralPath $summaryPath)) {
  Add-Rule 'A1 end summary exists' $false 'ambassador_end_summary.md not found'
  $script:rules | Format-Table -AutoSize Rule, Status, Detail
  Write-Host "AMBASSADOR-CHECK: FAIL - no end summary." -ForegroundColor Red
  exit 1
}
$txt = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8
$low = $txt.ToLower()

# ===== A2 - required SECTIONS present (10-section structure) =====
$required = @(
  @('status verdict', 'status\b[\s\S]{0,40}?(needs-more|no-go|go)'),
  @('blocking failures section', 'blocking failures'),
  @('warnings section', 'warnings?\b'),
  @('what changed', 'what changed'),
  @('what was tested', 'what was tested'),
  @('what failed/skipped', 'failed or was skipped|failed/skipped|fail[\s\S]{0,20}skip'),
  @('residue status', 'residue'),
  @('budget/scope deviations', 'budget|scope'),
  @('known limitations/unverified', 'known limitation|unverified'),
  @('decision question', 'keep\s*/\s*iterate\s*/\s*toss')
)
$missing = @()
foreach ($r in $required) { if (-not [regex]::IsMatch($low, $r[1])) { $missing += $r[0] } }
Add-Rule 'A2 required sections present' ($missing.Count -eq 0) `
  ($(if ($missing.Count -eq 0) { 'all 10 present' } else { 'missing: ' + ($missing -join ', ') }))

# ===== A3 - NO SANITIZE: STRICT CHECK-ID -> SECTION MAPPING =====
# Collect FAIL and WARN check IDs from the machine artifacts (not just free-text tokens).
$failIDs = @(); $warnIDs = @(); $auditPaths = @()
$audit = Read-Json (Join-Path $SessionPath 'audit_result.json')
if ($audit -and $audit -ne '__PARSE_ERROR__') {
  foreach ($c in @($audit.checks)) { if ($c.Status -eq 'FAIL') { $failIDs += $c.Check } }
}
$pmc = Read-Json (Join-Path $SessionPath 'pm_consistency_report.json')
if ($pmc -and $pmc -ne '__PARSE_ERROR__') {
  foreach ($f in @($pmc.findings)) {
    $id = ($f.Rule -split '\s+')[0]
    if ($f.Status -eq 'FAIL') { $failIDs += $id }
    elseif ($f.Status -eq 'WARN') { $warnIDs += $id }
  }
}
$verSum = Read-Json (Join-Path $SessionPath 'verifier_results\summary.json')
if ($verSum -and $verSum -ne '__PARSE_ERROR__') {
  if ((($verSum.tests_exit -ne 0) -and ($null -ne $verSum.tests_exit)) -or
      (($verSum.typecheck_exit -ne 0) -and ($null -ne $verSum.typecheck_exit)) -or
      ($verSum.cached -eq $true)) {
    if ($failIDs -notcontains 'C6') { $failIDs += 'C6' }
  }
}
$finds = Read-Json (Join-Path $SessionPath 'auditor_findings.json')
if ($finds -and $finds -ne '__PARSE_ERROR__') {
  $findList = $finds.findings; if ($null -eq $findList) { $findList = $finds }  # tolerate bare array
  foreach ($f in @($findList)) { if (@('high', 'critical') -contains $f.severity) { $auditPaths += $f.path } }
}
$failIDs = @($failIDs | Select-Object -Unique)
$warnIDs = @($warnIDs | Select-Object -Unique)
$auditPaths = @($auditPaths | Select-Object -Unique)

# Parse the declared status verdict.
$statusGO = $false
$m = [regex]::Match($low, 'status\b[\s\S]{0,40}?(needs-more|no-go|go)')
if ($m.Success -and $m.Groups[1].Value -eq 'go') { $statusGO = $true }

$hasFail = ($failIDs.Count -gt 0) -or ($auditPaths.Count -gt 0)

# A3a - a FAIL cannot be summarized as overall GO
if ($hasFail) {
  Add-Rule 'A3a status not GO when failures exist' (-not $statusGO) ("failures present; status GO=" + $statusGO)
} else {
  Add-Rule 'A3a status not GO when failures exist' $true 'no failures'
}

# A3b - every FAIL id (and high/critical audit path) appears, with a Blocking failures section
if ($hasFail) {
  $hasBlock = [regex]::IsMatch($low, 'blocking failures')
  $missIDs = @()
  foreach ($id in $failIDs) { if (-not [regex]::IsMatch($low, [regex]::Escape([string]$id).ToLower())) { $missIDs += $id } }
  foreach ($p in $auditPaths) { if ($p -and -not $low.Contains(([string]$p).ToLower())) { $missIDs += $p } }
  Add-Rule 'A3b blocking failures mapped' ($hasBlock -and ($missIDs.Count -eq 0)) `
    ("section=$hasBlock; failIDs=[" + ($failIDs -join ',') + "]" + $(if ($missIDs.Count) { "; MISSING: " + ($missIDs -join ',') } else { '' }))
} else {
  Add-Rule 'A3b blocking failures mapped' $true 'no FAIL ids to map'
}

# A3c - every WARN id appears, with a Warnings section
if ($warnIDs.Count -gt 0) {
  $hasWarn = [regex]::IsMatch($low, 'warnings?\b')
  $missW = @()
  foreach ($id in $warnIDs) { if (-not [regex]::IsMatch($low, [regex]::Escape([string]$id).ToLower())) { $missW += $id } }
  Add-Rule 'A3c warnings mapped' ($hasWarn -and ($missW.Count -eq 0)) `
    ("section=$hasWarn; warnIDs=[" + ($warnIDs -join ',') + "]" + $(if ($missW.Count) { "; MISSING: " + ($missW -join ',') } else { '' }))
} else {
  Add-Rule 'A3c warnings mapped' $true 'no WARN ids to map'
}

# ===== A4 - no secret-shaped value leaked into the human surface =====
$secretPatterns = @(
  'sk-[A-Za-z0-9]{16,}',
  'AKIA[0-9A-Z]{16}',
  '-----BEGIN [A-Z ]*PRIVATE KEY-----',
  '(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*["''][A-Za-z0-9/_+\-]{16,}["'']',
  'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'
)
$leak = @()
foreach ($pat in $secretPatterns) { if ([regex]::IsMatch($txt, $pat)) { $leak += "/$pat/" } }
Add-Rule 'A4 no secret in summary' ($leak.Count -eq 0) `
  ($(if ($leak.Count -eq 0) { 'clean (heuristic)' } else { 'possible secret: ' + ($leak -join ', ') }))

# ---- report ----
Write-Host ""
Write-Host "NEO_AMBASSADOR end-summary check: $summaryPath"
$script:rules | Format-Table -AutoSize Rule, Status, Detail
$fail = @($script:rules | Where-Object { $_.Status -eq 'FAIL' }).Count
Write-Host ""
if ($fail -gt 0) {
  Write-Host "AMBASSADOR-CHECK: FAIL - $fail rule(s) failed." -ForegroundColor Red
  exit 1
} else {
  Write-Host "AMBASSADOR-CHECK: PASS - summary complete and not sanitized." -ForegroundColor Green
  exit 0
}
