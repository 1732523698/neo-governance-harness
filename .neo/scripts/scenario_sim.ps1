<#
  scenario_sim.ps1  (NEO v2.5 helper - NOT one of the frozen v1 scripts)
  Dummy-app governance simulation. Replays the RT1-RT4 app-risk flows from
  .neo\NEO_RISK_TIERS.md and .neo\NEO_RELEASE_DISCIPLINE.md against the FAKE app described in
  .neo\examples\DUMMY_APP.md. Everything is fixture-based: no real app code, no installs, no
  network, no environment. Fixtures are built under NEO_SESSION\ and removed at the end
  (-KeepArtifacts to inspect). ASCII-only (PS 5.1 safe). This script encodes the tier gates as
  CHECKS; the prose source of truth stays in the two governance artifacts (referenced, not
  restated).

  Scenarios and expectations (C gate):
    RT1  compliant docs fix            -> ALLOWED with ZERO app artifacts
    RT2  compliant frontend change     -> ALLOWED with app-memory update ONLY
    RT2v dep change disguised as RT2   -> BLOCKED (DEP-GUARD escalation to RT3+ enforced)
    RT3n dep change, no approval       -> BLOCKED (DEP-GUARD fail-closed: no install before approval)
    RT3  dep change, full evidence     -> ALLOWED (all 8 DEP-GUARD items + approval BEFORE install)
    RT4n prod-sim change, no verified  -> BLOCKED (fail-closed on missing rollback verification)
         rollback
    RT4  prod-sim change, full pack    -> ALLOWED (approval + backup-first + verified rollback +
                                          exact command list + environment-identity proof)
  Also asserts DUMMY_APP.md itself is byte-identical after the run (simulations copy it; they
  never mutate the example). Exit 0 iff ALL expectations hold AND fixtures clean up.
#>
[CmdletBinding()]
param(
  [string]$NeoRoot,
  [switch]$KeepArtifacts
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }

$exampleApp = Join-Path $NeoRoot ".neo\examples\DUMMY_APP.md"
$tiersDoc   = Join-Path $NeoRoot ".neo\NEO_RISK_TIERS.md"
$releaseDoc = Join-Path $NeoRoot ".neo\NEO_RELEASE_DISCIPLINE.md"
$sessionDir = Join-Path $NeoRoot "NEO_SESSION"
foreach($req in @($exampleApp,$tiersDoc,$releaseDoc)){
  if(-not (Test-Path -LiteralPath $req)){ Write-Host "[FAIL] required artifact missing: $req"; exit 1 }
}
$appShaBefore = (Get-FileHash -LiteralPath $exampleApp -Algorithm SHA256).Hash

$depGuardItems = @("manifest_before_after","lockfile_before_after","why_needed",
                   "alternatives_considered","runtime_vs_dev","sandbox_install_evidence",
                   "rollback_command","human_approval")
$rt4Items = @("human_approval","backup_before_change","rollback_verified",
              "approved_command_list","environment_identity_proof")

# Governance evaluation: encodes the RT gates as fail-closed checks. Source of truth for the
# RULES is NEO_RISK_TIERS.md + NEO_RELEASE_DISCIPLINE.md; this function only enforces them.
function Test-Governance($s){
  $reasons = @()
  # DEP-GUARD escalation: ANY dep/lockfile change is RT3 minimum (RT4 if sensitive domain).
  if($s.dep_change){
    if(@("RT1","RT2") -contains $s.tier){
      $reasons += "DEP-GUARD: dependency/lockfile change claimed as $($s.tier); minimum tier is RT3 (see NEO_RELEASE_DISCIPLINE.md ANCHOR:DEP-GUARD)"
    }
    if($s.dep_sensitive_domain -and $s.tier -ne "RT4"){
      $reasons += "DEP-GUARD: dependency touches a sensitive domain (auth/payment/db/crypto/email/deploy/build/prod) -> RT4 required"
    }
    foreach($item in $depGuardItems){
      if(@($s.evidence) -notcontains $item){ $reasons += "DEP-GUARD: missing evidence item '$item'" }
    }
    if($s.install_ran_before_approval){
      $reasons += "DEP-GUARD: install/lockfile mutation ran BEFORE human approval (approval must precede install)"
    }
  }
  # Prod / destructive / security / payment surface forces RT4.
  if($s.prod_touch -and $s.tier -ne "RT4"){
    $reasons += "tier: production-surface work claimed as $($s.tier); RT4 required (see NEO_RISK_TIERS.md ANCHOR:RT4)"
  }
  # Artifact-surface rules per tier.
  switch($s.tier){
    "RT1" {
      if(@($s.artifacts_produced).Count -gt 0){
        $reasons += "RT1: produced app artifacts [$(@($s.artifacts_produced) -join ',')] - RT1 requires none"
      }
    }
    "RT2" {
      $extra = @(@($s.artifacts_produced) | Where-Object { $_ -ne "app_memory_update" })
      if($extra.Count -gt 0){
        $reasons += "RT2: produced non-app-memory artifacts [$($extra -join ',')] - RT2 allows app-memory update only"
      }
    }
    "RT4" {
      foreach($item in $rt4Items){
        if(@($s.evidence) -notcontains $item){ $reasons += "RT4: missing required item '$item'" }
      }
      if($s.backup_after_change){
        $reasons += "RT4: backup taken AFTER the change - backup+rollback must be verified FIRST"
      }
    }
  }
  if($reasons.Count -gt 0){ return [pscustomobject]@{ verdict = "BLOCKED"; reasons = $reasons } }
  return [pscustomobject]@{ verdict = "ALLOWED"; reasons = @() }
}

function Run-Scenario([string]$id, $scenario, [string]$expect){
  $root = Join-Path $sessionDir ("scenario_sim_" + $id)
  if(Test-Path -LiteralPath $root){ Remove-Item -LiteralPath $root -Recurse -Force }
  New-Item -ItemType Directory -Path $root | Out-Null
  # Each scenario works on a COPY of the dummy app memory; the example file is never mutated.
  Copy-Item -LiteralPath $exampleApp -Destination (Join-Path $root "APP_MEMORY.md")
  $scenario | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root "scenario.json") -Encoding UTF8
  $result = Test-Governance $scenario
  $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root "governance_result.json") -Encoding UTF8
  $ok = ($result.verdict -eq $expect)
  $tag = "[FAIL]"; if($ok){ $tag = "[PASS]" }
  Write-Host ("$tag $id ($($scenario.tier)): expect $expect, got $($result.verdict)")
  if(-not $ok -and $result.reasons.Count -gt 0){ foreach($r in $result.reasons){ Write-Host ("       reason: " + $r) } }
  if($ok -and $result.verdict -eq "BLOCKED"){ Write-Host ("       blocked for: " + ($result.reasons -join " | ")) }
  if(-not $KeepArtifacts){ Remove-Item -LiteralPath $root -Recurse -Force }
  return $ok
}

Write-Host "=== NEO scenario_sim (v2.5; dummy-app RT1-RT4 governance simulation) ==="
Write-Host ("NeoRoot: " + $NeoRoot)
Write-Host ""
$pass = $true

# RT1 - compliant docs fix: fully reversible, no app artifacts.
$pass = (Run-Scenario "rt1_docs_fix" ([pscustomobject]@{
  tier = "RT1"; description = "fix a typo in LemonLedger README (fake)"
  dep_change = $false; dep_sensitive_domain = $false; prod_touch = $false
  install_ran_before_approval = $false; backup_after_change = $false
  artifacts_produced = @(); evidence = @()
}) "ALLOWED") -and $pass

# RT2 - compliant frontend-only change: app-memory update only.
$pass = (Run-Scenario "rt2_frontend" ([pscustomobject]@{
  tier = "RT2"; description = "adjust LemonLedger daily-total display (fake frontend-only)"
  dep_change = $false; dep_sensitive_domain = $false; prod_touch = $false
  install_ran_before_approval = $false; backup_after_change = $false
  artifacts_produced = @("app_memory_update"); evidence = @()
}) "ALLOWED") -and $pass

# RT2 violation - dependency change disguised as RT2: must be BLOCKED (escalation).
$pass = (Run-Scenario "rt2_dep_disguise" ([pscustomobject]@{
  tier = "RT2"; description = "bump csv-parser-sim 'just a small frontend tweak' (fake)"
  dep_change = $true; dep_sensitive_domain = $false; prod_touch = $false
  install_ran_before_approval = $false; backup_after_change = $false
  artifacts_produced = @("app_memory_update"); evidence = @()
}) "BLOCKED") -and $pass

# RT3 negative - dep change with NO approval (and install attempted first): DEP-GUARD fail-closed.
$pass = (Run-Scenario "rt3_dep_no_approval" ([pscustomobject]@{
  tier = "RT3"; description = "bump csv-parser-sim, evidence pack incomplete, install ran first (fake)"
  dep_change = $true; dep_sensitive_domain = $false; prod_touch = $false
  install_ran_before_approval = $true; backup_after_change = $false
  artifacts_produced = @("app_memory_update","release_evidence")
  evidence = @("manifest_before_after","lockfile_before_after","why_needed")
}) "BLOCKED") -and $pass

# RT3 - dep change with the FULL 8-item DEP-GUARD evidence pack, approval before install.
$pass = (Run-Scenario "rt3_dep_full_pack" ([pscustomobject]@{
  tier = "RT3"; description = "bump csv-parser-sim with complete DEP-GUARD evidence (fake)"
  dep_change = $true; dep_sensitive_domain = $false; prod_touch = $false
  install_ran_before_approval = $false; backup_after_change = $false
  artifacts_produced = @("app_memory_update","release_evidence")
  evidence = $depGuardItems
}) "ALLOWED") -and $pass

# RT4 negative - prod-sim deploy without a VERIFIED rollback: fail-closed.
$pass = (Run-Scenario "rt4_no_rollback" ([pscustomobject]@{
  tier = "RT4"; description = "deploy LemonLedger to prod-sim, rollback not drilled (fake)"
  dep_change = $false; dep_sensitive_domain = $false; prod_touch = $true
  install_ran_before_approval = $false; backup_after_change = $false
  artifacts_produced = @("app_memory_update","release_evidence")
  evidence = @("human_approval","backup_before_change","approved_command_list","environment_identity_proof")
}) "BLOCKED") -and $pass

# RT4 - prod-sim deploy with the full pack: approval + backup-first + verified rollback +
# exact command list + environment-identity proof (marker file, never the name).
$pass = (Run-Scenario "rt4_full_pack" ([pscustomobject]@{
  tier = "RT4"; description = "deploy LemonLedger to prod-sim with full RT4 pack (fake)"
  dep_change = $false; dep_sensitive_domain = $false; prod_touch = $true
  install_ran_before_approval = $false; backup_after_change = $false
  artifacts_produced = @("app_memory_update","release_evidence")
  evidence = $rt4Items
}) "ALLOWED") -and $pass

Write-Host ""
# The example app memory must be byte-identical after the run.
$appShaAfter = (Get-FileHash -LiteralPath $exampleApp -Algorithm SHA256).Hash
if($appShaAfter -eq $appShaBefore){ Write-Host "[PASS] DUMMY_APP.md unchanged (simulations copy, never mutate)" }
else { Write-Host "[FAIL] DUMMY_APP.md was MUTATED by the simulation"; $pass = $false }

# Fixture cleanup proof.
$residue = @(Get-ChildItem -LiteralPath $sessionDir -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -like "scenario_sim_*" })
if($KeepArtifacts){ Write-Host ("[INFO] fixtures kept (-KeepArtifacts): " + $residue.Count) }
elseif($residue.Count -eq 0){ Write-Host "[PASS] all scenario fixtures removed (NEO_SESSION restored)" }
else { Write-Host "[FAIL] scenario fixtures left behind: $($residue.Count)"; $pass = $false }

Write-Host ""
if($pass){ Write-Host "=== scenario_sim: PASS (RT1 no-artifacts / RT2 app-memory-only / RT3 DEP-GUARD / RT4 approval+rollback, incl. fail-closed negatives) ==="; exit 0 }
else { Write-Host "=== scenario_sim: FAIL ==="; exit 1 }
