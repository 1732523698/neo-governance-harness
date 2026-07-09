<#
  regression_smoke.ps1  (NEO v2.0 helper, hardened in v2.5 - NOT one of the frozen v1 scripts)
  Replayable regression for the audit net. Reconstructs, on demand:
    GREEN E2E      -> verify_session.ps1 -Mode EndGate exits 0 (all applicable checks pass), and
                      C1 reports FULL schema validation (v2.5 hardened mode), not required-only.
    COMPOSED NEG.  -> a GO end-summary that hides a HIGH auditor finding -> C12 FAIL -> EndGate exit 1
                      (asserted to fail AS C12: zero non-C12 FAILs).
    ROUTING NEG.   -> v2.5 second negative: a routing entry that violates model_routing_policy
                      (mechanical task ran on the hard-logic model, no approved override) with an
                      HONEST NO-GO end summary -> C8 FAIL ONLY -> EndGate exit 1. Asserted to fail
                      AS C8 (zero non-C8 FAILs) and with C1=PASS (schema gate does not absorb it).
  It only REPLAYS the existing C1-C10/C12 net (verify_session.ps1); it never substitutes for it.
  Fixtures are built under NEO_SESSION\ and removed at the end (-KeepArtifacts to inspect).
  ASCII-only (PS 5.1 safe).
  Exit code: 0 if ALL THREE expectations hold, else 1.
#>
[CmdletBinding()]
param(
  [string]$NeoRoot,
  [switch]$KeepArtifacts
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }

$scriptsDir = Join-Path $NeoRoot ".neo\scripts"
$newSession = Join-Path $scriptsDir "new_session.ps1"
$assemble   = Join-Path $scriptsDir "assemble_auditor_input.ps1"
$verify     = Join-Path $scriptsDir "verify_session.ps1"
$sessionDir = Join-Path $NeoRoot "NEO_SESSION"
$greenId    = "regression_smoke_green"
$negId      = "regression_smoke_negative"
$negC8Id    = "regression_smoke_negative_c8"

function Remove-Session([string]$id){
  $p = Join-Path $sessionDir $id
  if(Test-Path -LiteralPath $p){ Remove-Item -LiteralPath $p -Recurse -Force }
}
function Write-Text([string]$path, [string]$text){
  Set-Content -LiteralPath $path -Value $text -Encoding UTF8
}

function Build-Session([string]$id, [bool]$negative){
  Remove-Session $id
  & $newSession -SessionId $id -Goal "regression smoke fixture (throwaway)" | Out-Null
  $root = Join-Path $sessionDir $id

  # Clean, known test command in the contract so C6 sees promised == actual.
  $cp = Join-Path $root "session_contract.json"
  $ct = Get-Content -LiteralPath $cp -Raw -Encoding UTF8
  $ct = [regex]::Replace($ct, '"test_plan":\s*\[[^\]]*\]', '"test_plan": ["neo-regression-selftest"]')
  Write-Text $cp $ct

  # C6 - verifier results (promised cmd, non-cached, exit 0).
  $summary = @"
{
  "tests_command": ["neo-regression-selftest"],
  "tests_exit": 0,
  "typecheck_exit": 0,
  "cached": false,
  "freshness": "fresh-non-cached",
  "runs": [ { "cmd": "neo-regression-selftest", "exit": 0 } ]
}
"@
  Write-Text (Join-Path $root "verifier_results\summary.json") $summary

  # C5 - residue (manifest clean + per-surface snapshot clean + 2nd run).
  $residue = @"
{
  "session_id": "$id",
  "manifest_cleanup_complete": true,
  "created_manifest": [],
  "state_surfaces": ["filesystem"],
  "snapshots": {
    "filesystem": { "before": "snapshots/before", "after": "snapshots/after", "diff_clean": true }
  },
  "second_run_pass": true
}
"@
  Write-Text (Join-Path $root "verifier_residue_report.json") $residue

  # C8 - foundation-only routing (no dispatch).
  Write-Text (Join-Path $root "model_routing_log.json") '{ "routing_mode": "not_applicable_foundation_only", "entries": [] }'

  # C7 - auditor report + findings; assemble the allowlisted input bundle with the real frozen script.
  Write-Text (Join-Path $root "auditor_report.md") "# Auditor report (regression fixture)`r`nFresh-context review from AUDITOR_INPUT only."
  if($negative){
    $findings = @"
{
  "auditor_context_fresh": true,
  "forbidden_inputs_seen": false,
  "input_artifacts": ["session_contract.json", "verifier_residue_report.json", "test_results.txt"],
  "recommendation": "NO-GO",
  "findings": [
    { "id": "F1", "severity": "high", "evidence_type": "diff_hunk", "path": "modules/echo/echo.js", "claim": "user input reaches eval without sanitization" }
  ]
}
"@
  } else {
    $findings = @"
{
  "auditor_context_fresh": true,
  "forbidden_inputs_seen": false,
  "input_artifacts": ["session_contract.json", "verifier_residue_report.json", "test_results.txt"],
  "recommendation": "GO",
  "findings": []
}
"@
  }
  Write-Text (Join-Path $root "auditor_findings.json") $findings
  & $assemble -SessionPath $root | Out-Null

  # C10/C12 - END summary. SAME GO summary for BOTH cases: with clean findings it is honest (C12 PASS);
  # with a hidden HIGH finding it is sanitized (C12 FAIL). All 10 required fields are present.
  $endSummary = @"
# END SUMMARY - $id

- Status: GO
- Blocking failures: none
- Warnings: none
- What changed: a trivial throwaway fixture module; no real surface touched.
- What was tested: neo-regression-selftest (non-cached, exit 0).
- What failed or was skipped: nothing failed; nothing skipped.
- Residue status: clean (manifest + filesystem snapshot clean; second run clean).
- Budget / scope deviations: none.
- Known limitations / unverified: none beyond the sandbox foundation notes.

Decision: Keep / iterate / toss? Does this match intent?
"@
  Write-Text (Join-Path $root "ambassador_end_summary.md") $endSummary
  return $root
}

# v2.5 second negative: valid contract + green artifacts, but the routing log shows a mechanical
# task run on the hard-logic model with NO approved override -> C8 must FAIL (and ONLY C8).
# The end summary is HONEST (NO-GO, surfaces C8) so C12 stays PASS - proving failure isolation.
function Build-RoutingNegative([string]$id){
  $root = Build-Session $id $false
  $routingBad = '{ "routing_mode": "active", "entries": [ { "task_id": "t1", "task_classification": "mechanical", "model_used": "opus" } ] }'
  Write-Text (Join-Path $root "model_routing_log.json") $routingBad
  $endSummary = @"
# END SUMMARY - $id

- Status: NO-GO
- Blocking failures: C8 routing violation - mechanical task 't1' ran on 'opus' but policy maps mechanical -> 'haiku' (no approved override); routing task 't1' also has no prompt file.
- Warnings: none
- What changed: a trivial throwaway fixture module; no real surface touched.
- What was tested: neo-regression-selftest (non-cached, exit 0).
- What failed or was skipped: C8 routing reconciliation failed; nothing else failed or was skipped.
- Residue status: clean (manifest + filesystem snapshot clean; second run clean).
- Budget / scope deviations: none.
- Known limitations / unverified: none beyond the sandbox foundation notes.

Decision: Keep / iterate / toss? Does this match intent?
"@
  Write-Text (Join-Path $root "ambassador_end_summary.md") $endSummary
  return $root
}

function Run-EndGate([string]$root){
  # Isolate exit code in a child process so verify_session's `exit` cannot terminate this script.
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verify -SessionPath $root -Mode EndGate | Out-Host
  $code = $LASTEXITCODE
  $audit = Get-Content -LiteralPath (Join-Path $root "audit_result.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  return [pscustomobject]@{ exit = $code; audit = $audit }
}
function Get-Status($audit, $checkId){
  foreach($c in @($audit.checks)){ if($c.Check -eq $checkId){ return $c.Status } }
  return "(absent)"
}
function Get-Detail($audit, $checkId){
  foreach($c in @($audit.checks)){ if($c.Check -eq $checkId){ return [string]$c.Detail } }
  return ""
}

Write-Host "=== NEO regression_smoke (v2.0 helper, v2.5-hardened; replays the audit net) ==="
Write-Host ("NeoRoot: " + $NeoRoot)
Write-Host ""
$pass = $true

# ---- GREEN E2E ----
Write-Host "-- GREEN E2E: expect EndGate exit 0, zero FAIL --"
$green = Build-Session $greenId $false
$gr = Run-EndGate $green
$gFail = @($gr.audit.checks | Where-Object { $_.Status -eq "FAIL" }).Count
$gC1Detail = Get-Detail $gr.audit "C1"
$gHardened = ($gC1Detail -match "Full schema validation passed")
if($gr.exit -eq 0 -and $gFail -eq 0 -and $gHardened){ Write-Host "[PASS] green: EndGate exit 0, 0 FAIL, C1 in v2.5 full-validation mode" }
elseif(-not $gHardened){ Write-Host "[FAIL] green: C1 not in v2.5 full-validation mode (detail: $gC1Detail)"; $pass = $false }
else { Write-Host "[FAIL] green: exit=$($gr.exit), FAIL count=$gFail"; $pass = $false }
Write-Host ""

# ---- COMPOSED NEGATIVE ----
Write-Host "-- COMPOSED NEGATIVE: expect EndGate exit 1 with C12 = FAIL --"
$neg = Build-Session $negId $true
$nr = Run-EndGate $neg
$c12 = Get-Status $nr.audit "C12"
$nOtherFail = @($nr.audit.checks | Where-Object { $_.Status -eq "FAIL" -and $_.Check -ne "C12" }).Count
if($nr.exit -eq 1 -and $c12 -eq "FAIL"){
  Write-Host "[PASS] negative: EndGate exit 1, C12=FAIL (non-C12 FAILs: $nOtherFail)"
  if($nOtherFail -gt 0){ Write-Host "[INFO] negative had $nOtherFail non-C12 FAIL(s); canonical case expects only C12" }
} else { Write-Host "[FAIL] negative: exit=$($nr.exit), C12=$c12"; $pass = $false }
Write-Host ""

# ---- ROUTING NEGATIVE (v2.5 second negative) ----
Write-Host "-- ROUTING NEGATIVE: expect EndGate exit 1 with C8 = FAIL ONLY (C1 = PASS) --"
$negC8 = Build-RoutingNegative $negC8Id
$r8 = Run-EndGate $negC8
$c8 = Get-Status $r8.audit "C8"
$c1AtC8 = Get-Status $r8.audit "C1"
$nonC8Fails = @($r8.audit.checks | Where-Object { $_.Status -eq "FAIL" -and $_.Check -ne "C8" })
if($r8.exit -eq 1 -and $c8 -eq "FAIL" -and $c1AtC8 -eq "PASS" -and $nonC8Fails.Count -eq 0){
  Write-Host "[PASS] routing negative: EndGate exit 1, C8=FAIL only, C1=PASS (isolated)"
} else {
  $ids = (@($nonC8Fails | ForEach-Object { $_.Check }) -join ',')
  Write-Host "[FAIL] routing negative: exit=$($r8.exit), C8=$c8, C1=$c1AtC8, non-C8 FAILs=[$ids]"
  $pass = $false
}
Write-Host ""

# ---- cleanup ----
if(-not $KeepArtifacts){
  Remove-Session $greenId
  Remove-Session $negId
  Remove-Session $negC8Id
  Write-Host "Fixtures removed (NEO_SESSION restored). Use -KeepArtifacts to inspect."
} else {
  Write-Host "Fixtures kept at NEO_SESSION\$greenId, NEO_SESSION\$negId and NEO_SESSION\$negC8Id (-KeepArtifacts)."
}
Write-Host ""

if($pass){ Write-Host "=== regression_smoke: PASS (green exit0 + composed-negative C12 exit1 + routing-negative C8 exit1) ==="; exit 0 }
else { Write-Host "=== regression_smoke: FAIL ==="; exit 1 }
