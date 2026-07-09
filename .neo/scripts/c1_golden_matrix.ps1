# c1_golden_matrix.ps1  (NEO v2.5 helper - NOT one of the frozen v1 scripts)
# PERMANENT golden valid/invalid contract matrix for the v2.5-hardened C1 in verify_session.ps1.
# Promoted from session scratch at v2.5 closeout (Raphael-approved 2026-06-10). Replayable proof
# that C1 full schema validation classifies exactly: 2 valid fixtures PASS, 8 invalid fixtures
# FAIL AS C1 (zero non-C1 FAILs). Each fixture: build NEO_SESSION\c1_golden_<name>\
# session_contract.json, run verify_session -Mode Fresh in a child process, read
# audit_result.json, assert C1 status + detail pattern + isolation. Fixtures are removed
# afterwards (-KeepArtifacts to inspect). ASCII-only (PS 5.1 safe).
# Exit code: 0 if all 10 classify as expected, else 1.
[CmdletBinding()]
param([string]$NeoRoot, [switch]$KeepArtifacts)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$verify = Join-Path $NeoRoot '.neo\scripts\verify_session.ps1'
$template = Join-Path $NeoRoot '.neo\templates\session_contract.template.json'
$sessionDir = Join-Path $NeoRoot 'NEO_SESSION'

function New-BaseContract {
  return (Get-Content -LiteralPath $template -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Run-Fixture([string]$name, $contractTextOrObj, [string]$expectC1, [string]$expectDetailPattern) {
  $root = Join-Path $sessionDir ("c1_golden_" + $name)
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
  New-Item -ItemType Directory -Path $root | Out-Null
  $cp = Join-Path $root 'session_contract.json'
  if ($contractTextOrObj -is [string]) {
    Set-Content -LiteralPath $cp -Value $contractTextOrObj -Encoding UTF8
  } else {
    $contractTextOrObj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cp -Encoding UTF8
  }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verify -SessionPath $root -Mode Fresh | Out-Null
  $audit = Get-Content -LiteralPath (Join-Path $root 'audit_result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $c1 = $null; $detail = ''
  foreach ($c in @($audit.checks)) { if ($c.Check -eq 'C1') { $c1 = $c.Status; $detail = [string]$c.Detail } }
  $otherFails = @($audit.checks | Where-Object { $_.Status -eq 'FAIL' -and $_.Check -ne 'C1' })
  $ok = ($c1 -eq $expectC1)
  if ($ok -and $expectDetailPattern) { $ok = ($detail -match $expectDetailPattern) }
  # Isolation is asserted for NEGATIVE fixtures only: an invalid contract must fail AS C1.
  # PASS fixtures may legitimately FAIL later checks (e.g. C5/C13) when their artifacts are
  # absent - that is correct non-masking behavior, not a C1 defect.
  $isolated = $true
  if ($expectC1 -eq 'FAIL') { $isolated = ($otherFails.Count -eq 0) }
  if (-not $KeepArtifacts) { Remove-Item -LiteralPath $root -Recurse -Force }
  return [pscustomobject]@{
    Fixture = $name; ExpectC1 = $expectC1; ActualC1 = $c1
    DetailOK = [bool]$ok; Isolated = $isolated
    NonC1Fails = (@($otherFails | ForEach-Object { $_.Check }) -join ',')
    Detail = $detail
  }
}

$results = @()

# 1 valid minimal: template minus optional keys (residue_keep_paths, snapshot_limits)
$c = New-BaseContract
$c.PSObject.Properties.Remove('residue_keep_paths')
$c.PSObject.Properties.Remove('snapshot_limits')
$results += Run-Fixture 'valid_minimal' $c 'PASS' 'Full schema validation passed'

# 2 valid full: template + optional na_justifications + populated external account + graduation_target string
$c = New-BaseContract
$c | Add-Member -NotePropertyName 'na_justifications' -NotePropertyValue ([pscustomobject]@{ C5 = 'fixture: no state mutated' })
$acct = [pscustomobject]@{
  provider = 'exampleprov'; account_label = 'neo-sandbox-example'; environment = 'sandbox'
  human_attested_sandbox_only = $true; spend_cap_configured = $true; spend_cap_amount = 5
  allowed_domains = @('api.example.com'); forbidden_real_data = $true
  attested_by = 'raphael'; attested_at = '2026-06-10'
}
$c.external_accounts_registry = @($acct)
$c.state_surfaces = @('filesystem', 'external_account')
$c.graduation_target = 'modules/example'
$results += Run-Fixture 'valid_full' $c 'PASS' 'Full schema validation passed'

# 3 missing required top-level field (goal)
$c = New-BaseContract
$c.PSObject.Properties.Remove('goal')
$results += Run-Fixture 'missing_top_required' $c 'FAIL' "missing required key 'goal'"

# 4 missing required nested field (budget.limit)
$c = New-BaseContract
$c.budget.PSObject.Properties.Remove('limit')
$results += Run-Fixture 'missing_nested_required' $c 'FAIL' "contract\.budget: missing required key 'limit'"

# 5 invalid enum (tier T9)
$c = New-BaseContract
$c.tier = 'T9'
$results += Run-Fixture 'invalid_enum' $c 'FAIL' "contract\.tier: value 'T9' not in enum"

# 6 invalid type (budget.limit as string)
$c = New-BaseContract
$c.budget.limit = 'five'
$results += Run-Fixture 'invalid_type' $c 'FAIL' 'contract\.budget\.limit: type mismatch'

# 7 invalid range (budget.limit below minimum 0)
$c = New-BaseContract
$c.budget.limit = -1
$results += Run-Fixture 'invalid_range' $c 'FAIL' 'contract\.budget\.limit: value -1 below minimum 0'

# 8 unknown top-level key
$c = New-BaseContract
$c | Add-Member -NotePropertyName 'mystery_key' -NotePropertyValue $true
$results += Run-Fixture 'unknown_top_key' $c 'FAIL' 'contract\.mystery_key: unknown key'

# 9 unknown nested key (inside budget)
$c = New-BaseContract
$c.budget | Add-Member -NotePropertyName 'sneaky' -NotePropertyValue 1
$results += Run-Fixture 'unknown_nested_key' $c 'FAIL' 'contract\.budget\.sneaky: unknown key'

# 10 malformed JSON
$results += Run-Fixture 'malformed_json' '{ this is not json' 'FAIL' 'not valid JSON'

$results | Format-Table -AutoSize Fixture, ExpectC1, ActualC1, DetailOK, Isolated, NonC1Fails
$bad = @($results | Where-Object { (-not $_.DetailOK) -or ($_.ActualC1 -ne $_.ExpectC1) -or (-not $_.Isolated) })
if ($bad.Count -eq 0) { Write-Host 'C1 GOLDEN MATRIX: ALL 10 CLASSIFY AS EXPECTED (and isolated to C1)'; exit 0 }
else {
  Write-Host ('C1 GOLDEN MATRIX: ' + $bad.Count + ' MISCLASSIFIED:')
  $bad | Format-List
  exit 1
}
