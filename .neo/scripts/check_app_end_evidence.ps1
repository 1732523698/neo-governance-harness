# check_app_end_evidence.ps1 - NEO v2.6 app-END evidence checker (SEPARATE from frozen
# ambassador_check.ps1 by explicit A3 decision; the frozen core stays byte-identical).
# ASCII-only, PowerShell 5.1.
#
# MANDATORY-INVOCATION RULE: this checker MUST run whenever a session declares an app_slug,
# app profile, app slice, real_app/fixture_app type, produces APP_END_EVIDENCE.json, or changes
# files under modules\<app_slug>\. "Adapter exists but END forgot to run it" is the named
# false-green this rule blocks. END flow for app sessions = verify_session.ps1 PASS AND this
# checker PASS.
#
# Checks:
#   E1  schema validation (required keys, types, enums, unknown-key reject) vs
#       .neo\schema\app_end_evidence.schema.json field rules (validated structurally here)
#   E2  self-claim guard: every pass claim backed by cmd+cwd+exit_code 0+timestamp+artifact
#   E3  stale-evidence guard: head_sha equals -ExpectHeadSha / live git HEAD, unless
#       mode=fixture AND fixture_pre_commit=true (explicit controlled exception)
#   E4  changed-files omission guard: evidence set == on-disk declared set (CHANGED_FILES.txt
#       or git), no silent subset
#   E5  custom-check omission guard: every CUSTOM_CHECK in the profile appears in evidence
#   E6  classifier no-downgrade guard: declared_tier >= derived_tier; risky buckets cannot be
#       cosmetic; overrides only via unresolved_risks/human_acceptance
#   E7  internal consistency: forbidden_paths_touched false; migrations=>rollback proof;
#       deps=>DEP-GUARD proof; secret_scan pass; no FAIL check buried under a green claim;
#       degraded client evidence => human acceptance
#   E8  fixture-boundary: mode=fixture emits the visible non-certification warning
#
# Exit 0 only when all gating checks pass.

param(
  [Parameter(Mandatory=$true)][string]$Evidence,
  [Parameter(Mandatory=$true)][string]$Profile,
  [string]$SliceDir = '',
  [string]$ExpectHeadSha = ''
)

$ErrorActionPreference = 'Stop'
$script:fails = 0
function Say-Pass([string]$id,[string]$m){ Write-Host "[$id PASS] $m" }
function Say-Fail([string]$id,[string]$m){ Write-Host "[$id FAIL] $m"; $script:fails++ }

if(-not (Test-Path -LiteralPath $Evidence)){ Write-Host "[E1 FAIL] evidence file not found: $Evidence"; exit 1 }
if(-not (Test-Path -LiteralPath $Profile)){ Write-Host "[E1 FAIL] profile not found: $Profile"; exit 1 }
try { $ev = Get-Content -LiteralPath $Evidence -Raw | ConvertFrom-Json }
catch { Write-Host "[E1 FAIL] evidence is not valid JSON: $($_.Exception.Message)"; exit 1 }

# ---------- E1 schema validation ----------
$requiredTop = @('app_slug','app_name','app_root','mode','head_sha','branch','changed_files','classification','forbidden_paths_touched','migrations','dependency_changes','commands','i18n_parity','secret_scan','smoke','checks','unresolved_risks','human_acceptance','auditor_findings','generated_at','generator')
$allowedTop = $requiredTop + @('fixture_pre_commit','client_verification','authorized_exceptions')
$e1 = @()
$topNames = @($ev.PSObject.Properties | ForEach-Object { $_.Name })
foreach($r in $requiredTop){ if($topNames -notcontains $r){ $e1 += "missing required key '$r'" } }
foreach($n in $topNames){ if($allowedTop -notcontains $n){ $e1 += "unknown key '$n' (additionalProperties: false)" } }
if($ev.mode -and $ev.mode -notin @('fixture','real')){ $e1 += "mode '$($ev.mode)' not in enum [fixture,real]" }
if($ev.i18n_parity -and $ev.i18n_parity -notin @('pass','fail','not_applicable')){ $e1 += "i18n_parity invalid enum" }
if($ev.secret_scan -and $ev.secret_scan -notin @('pass','fail')){ $e1 += "secret_scan invalid enum" }
if($ev.classification){
  $cl = $ev.classification
  foreach($r in @('buckets','derived_tier','declared_tier','fast_lane_requested','fast_lane_eligible')){
    if($null -eq $cl.PSObject.Properties[$r]){ $e1 += "classification missing '$r'" }
  }
  foreach($t in @($cl.derived_tier,$cl.declared_tier)){ if($t -and $t -notin @('RT1','RT2','RT3','RT4')){ $e1 += "tier '$t' not RT1-RT4" } }
  $validBuckets = @('docs_only','frontend_ui','client_logic','backend_api','schema_migration','auth_permission','dependency_config','locked_shared','financial_logic')
  foreach($b in @($cl.buckets)){ if($b -notin $validBuckets){ $e1 += "unknown bucket '$b'" } }
}
foreach($c in @($ev.checks)){
  foreach($r in @('id','name','status','detail')){ if($null -eq $c.PSObject.Properties[$r]){ $e1 += "check entry missing '$r'" } }
  if($c.status -and $c.status -notin @('PASS','FAIL','NA','PASS-WITH-AUTH')){ $e1 += "check '$($c.id)' status '$($c.status)' invalid" }
}
foreach($cmd in @($ev.commands)){
  foreach($r in @('name','cmd','cwd','exit_code','timestamp','output_path','status')){ if($null -eq $cmd.PSObject.Properties[$r]){ $e1 += "command entry '$($cmd.name)' missing '$r'" } }
  if($cmd.status -and $cmd.status -notin @('pass','fail','skipped')){ $e1 += "command '$($cmd.name)' status invalid" }
}
if($e1.Count -gt 0){ Say-Fail 'E1' ("schema validation: " + ($e1 -join '; ')) } else { Say-Pass 'E1' 'schema validation: required keys, enums, no unknown keys' }

# ---------- E2 self-claim guard ----------
$e2 = @()
foreach($cmd in @($ev.commands)){
  if($cmd.status -eq 'pass'){
    if($cmd.exit_code -ne 0){ $e2 += "'$($cmd.name)' claims pass with exit_code=$($cmd.exit_code)" }
    foreach($f in @('cmd','cwd','timestamp','output_path')){
      $v = $cmd.PSObject.Properties[$f]
      if($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v.Value)){ $e2 += "'$($cmd.name)' pass claim missing $f" }
    }
    if($cmd.output_path -and $SliceDir){
      $op = $cmd.output_path
      if(-not (Test-Path -LiteralPath $op)){
        $op2 = Join-Path $SliceDir $cmd.output_path
        if(-not (Test-Path -LiteralPath $op2)){ $e2 += "'$($cmd.name)' output artifact missing on disk: $($cmd.output_path)" }
      }
    }
  }
}
if($e2.Count -gt 0){ Say-Fail 'E2' ("self-claim guard: " + ($e2 -join '; ')) } else { Say-Pass 'E2' 'every pass claim backed by exit_code 0 + cmd + cwd + timestamp + artifact' }

# ---------- E3 stale-evidence guard ----------
$fixtureException = ($ev.mode -eq 'fixture' -and $ev.fixture_pre_commit -eq $true)
if($fixtureException){
  Say-Pass 'E3' 'stale-evidence guard: fixture_pre_commit controlled exception (mode=fixture, no git) - explicit, not silent'
} else {
  $liveSha = $ExpectHeadSha
  if(-not $liveSha -and $ev.app_root -and (Test-Path -LiteralPath (Join-Path $ev.app_root '.git'))){
    Push-Location $ev.app_root; try { $liveSha = (& git rev-parse HEAD 2>$null).Trim() } finally { Pop-Location }
  }
  if(-not $liveSha){ Say-Fail 'E3' 'stale-evidence guard: cannot establish live HEAD (no -ExpectHeadSha, no git) and not a declared fixture_pre_commit exception' }
  elseif($ev.head_sha -ne $liveSha){ Say-Fail 'E3' "stale-evidence guard: evidence head_sha $($ev.head_sha) != live HEAD $liveSha - evidence predates final state" }
  else { Say-Pass 'E3' "stale-evidence guard: head_sha matches live HEAD ($liveSha)" }
}

# ---------- E4 changed-files omission guard ----------
$declared = $null
if($SliceDir -and (Test-Path -LiteralPath (Join-Path $SliceDir 'CHANGED_FILES.txt'))){
  $declared = @(Get-Content -LiteralPath (Join-Path $SliceDir 'CHANGED_FILES.txt') | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
} elseif($ev.app_root -and (Test-Path -LiteralPath (Join-Path $ev.app_root '.git'))){
  Push-Location $ev.app_root
  try { $declared = @(& git status --porcelain | ForEach-Object { $c=$_.Substring(0,2); $p=$_.Substring(3).Trim(); if($c -match 'D'){"DELETED:$p"}else{$p} }) } finally { Pop-Location }
}
if($null -eq $declared){ Say-Fail 'E4' 'changed-files guard: no independent changed-set source (CHANGED_FILES.txt or git) to reconcile against' }
else {
  $evSet = @($ev.changed_files)
  $missing = @($declared | Where-Object { $evSet -notcontains $_ })
  $extra   = @($evSet | Where-Object { $declared -notcontains $_ })
  if($missing.Count -gt 0 -or $extra.Count -gt 0){
    Say-Fail 'E4' ("changed-files guard: evidence omits [" + ($missing -join ', ') + "] / lists unknown [" + ($extra -join ', ') + "]")
  } else { Say-Pass 'E4' "changed-files guard: evidence set matches declared set ($($evSet.Count) files, no omission)" }
}

# ---------- E5 custom-check omission guard ----------
# 3.0 port (Session 5): custom_checks now come from the validated JSON spine (the SOLE authority);
# the legacy Markdown profile is a generated, non-authoritative view. Resolve the JSON sibling of
# -Profile. Only this ingestion changed; the E5 presence/omission logic below is untouched.
if([System.IO.Path]::GetExtension($Profile) -ieq '.json'){ $profileJson = $Profile } else { $profileJson = [System.IO.Path]::ChangeExtension($Profile, '.json') }
$profCustom = @()
$e5LoadOk = $false
if(-not (Test-Path -LiteralPath $profileJson)){ Say-Fail 'E5' "authoritative JSON profile not found: $profileJson" }
else { try { $PJ = Get-Content -LiteralPath $profileJson -Raw | ConvertFrom-Json; $profCustom = @($PJ.custom_checks); $e5LoadOk = $true } catch { Say-Fail 'E5' "profile JSON parse error ($profileJson): $($_.Exception.Message)" } }
$e5 = @()
foreach($cc in $profCustom){
  # 3.1-C (P1-S4): custom_checks item may be a string (legacy) or an object {id,mode,test_id,...}.
  if($cc -is [string]){ $ccId = $cc; $ccTestId = $cc } else { $ccId = [string]$cc.id; $ccTestId = if($cc.test_id){ [string]$cc.test_id } else { $ccId } }
  $inCmd = @($ev.commands) | Where-Object { $_.name -eq $ccId -or $_.name -eq $ccTestId }
  $inChecks = @($ev.checks) | Where-Object { $_.detail -match [regex]::Escape($ccId) -or $_.name -match [regex]::Escape($ccId) }
  if(-not ($inCmd -or $inChecks)){ $e5 += $ccId }
}
if($e5.Count -gt 0){ Say-Fail 'E5' ("custom-check guard: profile-required checks absent from evidence: " + ($e5 -join ', ')) }
elseif($e5LoadOk){ Say-Pass 'E5' "custom-check guard: all $($profCustom.Count) profile custom checks present in evidence" }

# ---------- E6 classifier no-downgrade guard ----------
$tierRank = @{ 'RT1'=1; 'RT2'=2; 'RT3'=3; 'RT4'=4 }
$cl = $ev.classification
$riskyBuckets = @('locked_shared','schema_migration','dependency_config','backend_api','auth_permission','financial_logic')
$riskyPresent = @(@($cl.buckets) | Where-Object { $riskyBuckets -contains $_ })
$e6 = @()
if($cl.declared_tier -and $cl.derived_tier -and $tierRank[$cl.declared_tier] -lt $tierRank[$cl.derived_tier]){
  $e6 += "declared_tier $($cl.declared_tier) below derived_tier $($cl.derived_tier) - downgrade forbidden"
}
if($riskyPresent.Count -gt 0 -and $cl.declared_tier -in @('RT1','RT2')){
  $e6 += ("risky buckets (" + ($riskyPresent -join ',') + ") cannot carry a cosmetic RT1/RT2 declaration")
}
if($riskyPresent.Count -gt 0 -and $cl.fast_lane_requested -eq $true -and $cl.fast_lane_eligible -eq $true){
  $e6 += 'fast_lane_eligible=true despite risky buckets - classifier must block, not permit'
}
if($e6.Count -gt 0){ Say-Fail 'E6' ("no-downgrade guard: " + ($e6 -join '; ')) }
else { Say-Pass 'E6' 'no-downgrade guard: declared >= derived; risky surfaces not downgraded; fast lane consistent' }

# ---------- E7 internal consistency ----------
$e7 = @()
if($ev.forbidden_paths_touched -eq $true){ $e7 += 'forbidden_paths_touched=true (locked surface contacted)' }
if($ev.migrations.present -eq $true -and [string]::IsNullOrWhiteSpace($ev.migrations.rollback_proof)){ $e7 += 'migrations present without rollback proof' }
if($ev.dependency_changes.present -eq $true -and [string]::IsNullOrWhiteSpace($ev.dependency_changes.dep_guard_proof)){ $e7 += 'dependency change without DEP-GUARD proof' }
if($ev.secret_scan -eq 'fail'){ $e7 += 'secret scan failed' }
if($ev.i18n_parity -eq 'fail'){ $e7 += 'i18n parity failed' }
if($ev.smoke.result -eq 'fail'){ $e7 += 'smoke recorded as failing' }
$failedChecks = @(@($ev.checks) | Where-Object { $_.status -eq 'FAIL' })
foreach($fc in $failedChecks){
  $surfaced = @($ev.unresolved_risks) | Where-Object { $_ -match [regex]::Escape($fc.id) }
  if(-not $surfaced){ $e7 += "check $($fc.id) FAILed but is not surfaced in unresolved_risks (sanitized summary)" }
}
if($ev.client_verification -and $ev.client_verification.degraded -eq $true){
  $acc = @($ev.human_acceptance) | Where-Object { $_ -match 'CLIENT_DEGRADED_ACCEPTED' }
  if(-not $acc){ $e7 += 'degraded client-verification evidence without explicit human acceptance' }
}
# 3.1-C (P1-S4): RT4-R1 authorized-exception consistency (no silent green). A PASS-WITH-AUTH check must be
# accounted for by a non-empty authorized_exceptions block, and vice-versa; each exception must carry its
# human gate_ref. forbidden_paths_touched stays FALSE for an authorized touch (the exception is the record).
$authChecks = @(@($ev.checks) | Where-Object { $_.status -eq 'PASS-WITH-AUTH' })
$authEx = @($ev.authorized_exceptions)
if($authChecks.Count -gt 0 -and $authEx.Count -eq 0){ $e7 += 'a check is PASS-WITH-AUTH but authorized_exceptions is empty (unaccounted authorized locked touch)' }
if($authEx.Count -gt 0 -and $authChecks.Count -eq 0){ $e7 += 'authorized_exceptions present but no PASS-WITH-AUTH check (inconsistent)' }
foreach($ax in $authEx){
  if([string]::IsNullOrWhiteSpace([string]$ax.gate_ref)){ $e7 += 'an authorized_exception is missing its human gate_ref' }
  if([string]::IsNullOrWhiteSpace([string]$ax.expected_post_sha)){ $e7 += "authorized_exception for '$($ax.path)' missing expected_post_sha (re-pin)" }
}
if($failedChecks.Count -gt 0){ $e7 += "$($failedChecks.Count) internal check(s) FAIL - bundle is not green" }
if($e7.Count -gt 0){ Say-Fail 'E7' ("consistency: " + ($e7 -join '; ')) }
else { Say-Pass 'E7' 'consistency: no forbidden contact; migration/dep proofs present where required; no buried FAIL; no unaccepted degraded evidence' }

# ---------- E8 fixture boundary ----------
if($ev.mode -eq 'fixture'){
  Write-Host '[E8 WARN] Fixture PASS validates adapter mechanics only. It does not certify external app execution.'
  Say-Pass 'E8' 'fixture-boundary warning emitted (fixture proof is not production proof)'
} else {
  Say-Pass 'E8' 'real mode bundle (boundary sign-off was checked at generation time by AS1)'
}

Write-Host ""
if($script:fails -gt 0){ Write-Host "check_app_end_evidence: RED - $($script:fails) FAIL."; exit 1 }
Write-Host "check_app_end_evidence: GREEN - evidence bundle is internally consistent and fully backed."
exit 0
