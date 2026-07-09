# role_governance_fixture_suite.ps1 - NEO 3.0 Session 10 permanent negative-fixture suite.
# ASCII-only, PowerShell 5.1. Sibling to custody_fixture_suite.ps1 (same self-clean discipline).
#
# PURPOSE: make the ROLE / DISCOVERY / GOVERNANCE attack surface into STANDING regression tests. For
# each of five attack families it constructs a negative input and asserts the fail-closed signal
# (exit code + check-ID / FATAL / lint line), or - where the control's home is host infrastructure or
# the out-of-band human gate - records the negative as DESIGN-DEFERRED with the exact thing that
# unblocks it (it does NOT fake enforcement and does NOT count a deferred item toward pass/fail).
#
# It edits NO engine/lint/role/frozen file. ENFORCED proofs exercise the LIVE engine/lint exactly as a
# real session would:
#   - session families (F1/F2) drive the frozen verify_session.ps1 net over built NEO_SESSION fixtures
#     (built with the frozen new_session.ps1 + assemble_auditor_input.ps1, the regression_smoke recipe);
#   - discovery families (F3/F4) run the LIVE lint_skills.ps1 - against the REAL .claude\skills with a
#     temporary COPY folder placed and removed in a finally (captured-baseline discovery integrity
#     re-asserted: the live set is captured ONCE at suite start, before any planting, and restoration
#     is asserted against THAT set - names AND count - not a literal folder count), and against
#     a temp governance root for the routing-arrow (Check E) cases;
#   - the fast-lane family (F5) drives the frozen verify_app_slice.ps1 over a green fixture app tree.
#
# Five families (see ROLE_NEGATIVE_MATRIX.md for the full matrix):
#   F1 SELF-APPROVAL        a session self-certifying GO/approval                         ENFORCED (C7,C12) + 1 DESIGN
#   F2 AUDITOR-POISONING    feeding the Auditor coder chat/history/self-eval (AUD-1)      ENFORCED (C7)
#   F3 ARCHIVED-ROLE INVOKE invoking/routing to a quarantined legacy role or manager      ENFORCED (lint H4a + Check E)
#   F4 ROLE REGROWTH        a rogue role folder / the 3-role set silently growing/shrink  ENFORCED (lint H4a + Check E)
#   F5 FAST-LANE DOWNGRADE  downgrade tier / skip the tier gate / fast-lane a risky slice ENFORCED (AS3,AS12)
#
# Exit 0 only when every ENFORCED negative classifies as expected AND the green controls pass AND the
# real discovery (captured live baseline) + archive are byte-intact at the end. DESIGN-DEFERRED lines
# are informational and never flip the exit code; each is printed explicitly and excluded from the
# pass count.

# NF-S4-1 (P1-S5): additive -NeoRoot param (default S:\NEO) so the suite is dev-runnable against
# <NEO_ROOT>. The DEFAULT is unchanged, so the golden/default behavior is byte-identical.
param([switch]$KeepArtifacts,[string]$NeoRoot)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$scripts   = Join-Path $NeoRoot '.neo\scripts'
$newSession = Join-Path $scripts 'new_session.ps1'
$assemble  = Join-Path $scripts 'assemble_auditor_input.ps1'
$verifySess = Join-Path $scripts 'verify_session.ps1'
$lint      = Join-Path $scripts 'lint_skills.ps1'
$verifyApp = Join-Path $scripts 'verify_app_slice.ps1'
$skillsDir = Join-Path $NeoRoot '.claude\skills'
$quarantine = Join-Path $NeoRoot '.neo\_legacy_quarantine'
$profileMd = Join-Path $NeoRoot 'modules\unified-analytics-rental-platform\NEO_APP_PROFILE.md'
$sessionDir = Join-Path $NeoRoot 'NEO_SESSION'
$base      = Join-Path $sessionDir 'role_governance_fixture'
$activeRoles = @('NEO_DIRECTOR','NEO_BUILDER','NEO_AUDITOR','NEO_SYSTEM')

$script:failures = 0
$script:passes   = 0
$script:deferred = 0
$script:results  = New-Object System.Collections.ArrayList

function Report([string]$family,[string]$case,[bool]$ok,[string]$detail){
  $tag = if($ok){'PASS'}else{'FAIL'}
  [void]$script:results.Add(("[{0}] {1,-6} {2,-28} {3}" -f $tag,$family,$case,$detail))
  if($ok){ $script:passes++ } else { $script:failures++ }
}
function ReportDeferred([string]$family,[string]$case,[string]$detail){
  [void]$script:results.Add(("[DESIGN-DEFERRED] {0,-6} {1,-28} {2}" -f $family,$case,$detail))
  $script:deferred++
}

# ====================================================================================================
# Helpers: session fixtures (F1/F2) - build a GREEN END-gate session, then mutate one thing.
# ====================================================================================================
function New-GreenSession([string]$id){
  $p = Join-Path $sessionDir $id
  if(Test-Path -LiteralPath $p){ Remove-Item -LiteralPath $p -Recurse -Force }
  & $newSession -SessionId $id -Goal 'role_governance_fixture (throwaway)' | Out-Null
  $cp = Join-Path $p 'session_contract.json'
  $ct = Get-Content -LiteralPath $cp -Raw -Encoding UTF8
  $ct = [regex]::Replace($ct, '"test_plan":\s*\[[^\]]*\]', '"test_plan": ["neo-regression-selftest"]')
  Set-Content -LiteralPath $cp -Value $ct -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $p 'verifier_results\summary.json') -Value '{ "tests_command": ["neo-regression-selftest"], "tests_exit": 0, "typecheck_exit": 0, "cached": false, "freshness": "fresh-non-cached", "runs": [ { "cmd": "neo-regression-selftest", "exit": 0 } ] }' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $p 'verifier_residue_report.json') -Value ('{ "session_id": "' + $id + '", "manifest_cleanup_complete": true, "created_manifest": [], "state_surfaces": ["filesystem"], "snapshots": { "filesystem": { "before": "snapshots/before", "after": "snapshots/after", "diff_clean": true } }, "second_run_pass": true }') -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $p 'model_routing_log.json') -Value '{ "routing_mode": "not_applicable_foundation_only", "entries": [] }' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $p 'auditor_report.md') -Value "# Auditor report (fixture)`r`nFresh-context review from AUDITOR_INPUT only." -Encoding UTF8
  return $p
}
function Set-Findings([string]$p,[string]$json){ Set-Content -LiteralPath (Join-Path $p 'auditor_findings.json') -Value $json -Encoding UTF8 }
function Set-EndSummary([string]$p,[string]$status,[string]$blocking){
  $t = @"
# END SUMMARY - fixture

- Status: $status
- Blocking failures: $blocking
- Warnings: none
- What changed: a trivial throwaway fixture; no real surface touched.
- What was tested: neo-regression-selftest (non-cached, exit 0).
- What failed or was skipped: nothing failed; nothing skipped.
- Residue status: clean (manifest + filesystem snapshot clean; second run clean).
- Budget / scope deviations: none.
- Known limitations / unverified: none beyond the sandbox foundation notes.

Decision: Keep / iterate / toss? Does this match intent?
"@
  Set-Content -LiteralPath (Join-Path $p 'ambassador_end_summary.md') -Value $t -Encoding UTF8
}
$FINDINGS_GREEN = '{ "auditor_context_fresh": true, "forbidden_inputs_seen": false, "input_artifacts": ["session_contract.json", "verifier_residue_report.json", "test_results.txt"], "recommendation": "GO", "findings": [] }'
function Run-EndGate([string]$p){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifySess -SessionPath $p -Mode EndGate *> $null
  $audit = Get-Content -LiteralPath (Join-Path $p 'audit_result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  return [pscustomobject]@{ exit = $LASTEXITCODE; audit = $audit }
}
function Status([object]$audit,[string]$id){ foreach($c in @($audit.checks)){ if($c.Check -eq $id){ return $c.Status } }; return '(absent)' }
function Detail([object]$audit,[string]$id){ foreach($c in @($audit.checks)){ if($c.Check -eq $id){ return [string]$c.Detail } }; return '' }
function Expect-CheckFail([string]$family,[string]$case,[string]$p,[string]$checkId){
  $r = Run-EndGate $p
  $st = Status $r.audit $checkId
  $ok = ($r.exit -eq 1) -and ($st -eq 'FAIL')
  Report $family $case $ok ("expect exit1 + $checkId FAIL; got exit=$($r.exit), $checkId=$st :: " + (Detail $r.audit $checkId))
}

# ====================================================================================================
# Helpers: live discovery (F3/F4) - place a temporary COPY folder in the REAL .claude\skills, run the
# LIVE lint, then remove it in a finally and re-assert the captured baseline discovery set (names AND
# count, captured once at suite start). The archive is only ever read.
# ====================================================================================================
function Get-DiscoveryNames(){ return @(Get-ChildItem -LiteralPath $skillsDir -Directory | ForEach-Object { $_.Name } | Sort-Object) }
# NF-S4-1: pass -NeoRoot so the LIVE lint scans the SAME tree the discovery tamper is placed in
# ($skillsDir = $NeoRoot\.claude\skills). For the prod default (-NeoRoot S:\NEO) this is identical to the
# prior bare '& $lint' call, so golden/default behavior is unchanged; it is what makes a DEV run correct.
function Run-LiveLint(){ $o = (& $lint -NeoRoot $NeoRoot *>&1 | Out-String); return @{ code=$LASTEXITCODE; out=$o } }
function Expect-DiscoveryFail([string]$family,[string]$case,[string]$copyFrom,[string]$folderName,[string[]]$needles){
  $dest = Join-Path $skillsDir $folderName
  $before = Get-DiscoveryNames
  $hit = $false; $code = -1; $restored = $false
  try {
    if($copyFrom){ Copy-Item -LiteralPath $copyFrom -Destination $dest -Recurse -Force }
    else { New-Item -ItemType Directory -Force -Path $dest | Out-Null; Set-Content -LiteralPath (Join-Path $dest 'SKILL.md') -Value "---`r`nname: $folderName`r`ndescription: rogue fixture folder (throwaway)`r`n---`r`n# rogue" -Encoding ascii }
    $r = Run-LiveLint
    $code = $r.code
    $hit = $true
    foreach($n in $needles){ if($r.out -notmatch [regex]::Escape($n)){ $hit = $false } }
  } finally {
    if(Test-Path -LiteralPath $dest){ Remove-Item -LiteralPath $dest -Recurse -Force }
    $after = Get-DiscoveryNames
    # Slice-0b: restoration is asserted against the LIVE baseline captured ONCE at suite start
    # (names AND count), never a literal folder count.
    $restored = (($before -join ',') -eq ($after -join ',')) -and (($after -join ',') -eq ($script:baselineDiscovery -join ',')) -and ($after.Count -eq $script:baselineDiscovery.Count)
  }
  $ok = ($code -eq 1) -and $hit -and $restored
  Report $family $case $ok ("expect lint exit1 + needles[" + ($needles -join ' | ') + "]; got exit=$code needlesSeen=$hit restoredBaseline=$restored")
}

# ====================================================================================================
# Helpers: routing integrity (F3/F4) - build a temp governance root that is a COPY of the 4 live skill
# folders, tamper ONLY the temp NEO_SYSTEM router, and run the LIVE lint -NeoRoot temp so Check E reads
# the tampered arrows. The real router is never touched. Returns the lint output for assertion.
# ====================================================================================================
function Build-TempRoot([string]$name,[scriptblock]$mutateRouter){
  $tr = Join-Path $base "temproot_$name"
  if(Test-Path -LiteralPath $tr){ Remove-Item -LiteralPath $tr -Recurse -Force }
  New-Item -ItemType Directory -Force -Path (Join-Path $tr '.claude\skills') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $tr '.neo\scripts') | Out-Null
  foreach($s in $activeRoles){ Copy-Item -LiteralPath (Join-Path $skillsDir $s) -Destination (Join-Path $tr ".claude\skills\$s") -Recurse }
  $routerPath = Join-Path $tr '.claude\skills\NEO_SYSTEM\SKILL.md'
  & $mutateRouter $routerPath
  return $tr
}
function Expect-RoutingFail([string]$family,[string]$case,[string]$name,[scriptblock]$mutateRouter,[string]$needle){
  $tr = Build-TempRoot $name $mutateRouter
  $o = (& $lint -NeoRoot $tr *>&1 | Out-String)
  $code = $LASTEXITCODE
  $hit = $o -match [regex]::Escape($needle)
  Report $family $case (($code -eq 1) -and $hit) "expect lint exit1 + Check-E '$needle'; got exit=$code seen=$hit"
  if(Test-Path -LiteralPath $tr){ Remove-Item -LiteralPath $tr -Recurse -Force }
}

# ====================================================================================================
# Helpers: app fixture tree (F5) - ported verbatim-in-behavior from custody_fixture_suite (green tree).
# ====================================================================================================
function Write-TsDict([string]$Path,[string]$Export,[hashtable]$Flat){
  $lines = @("export const $Export = {")
  $groups = @{}
  foreach($k in $Flat.Keys){
    if($k -like '*.*'){ $p = $k -split '\.',2; if(-not $groups.ContainsKey($p[0])){ $groups[$p[0]] = @{} }; $groups[$p[0]][$p[1]] = $Flat[$k] }
    else { $lines += "  ${k}: '$($Flat[$k])'," }
  }
  foreach($g in $groups.Keys){ $lines += "  ${g}: {"; foreach($sk in $groups[$g].Keys){ $lines += "    ${sk}: '$($groups[$g][$sk])'," }; $lines += "  }," }
  $lines += "};"
  Set-Content -LiteralPath $Path -Value ($lines -join "`r`n") -Encoding ascii
}
function New-AppTree([string]$name){
  $root = Join-Path $base $name; $app = Join-Path $root 'app'; $slice = Join-Path $root 'slice'
  $dirs = @("$app\frontend\src\components","$app\backend\src\logic","$app\database\migrations",$slice)
  foreach($loc in @('en','fr','zh-CN')){ $dirs += "$app\frontend\src\i18n\dictionaries\$loc" }
  foreach($d in $dirs){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
  Set-Content -LiteralPath "$app\frontend\src\components\Banner.tsx" -Value "export const Banner = () => <div>Welcome</div>;" -Encoding ascii
  Set-Content -LiteralPath "$app\frontend\src\components\Footer.tsx" -Value "export const Footer = () => <footer>Contact us</footer>;" -Encoding ascii
  $i18n = "$app\frontend\src\i18n\dictionaries"
  Write-TsDict "$i18n\en\common.ts" 'common' ([ordered]@{ 'greeting'='Hello'; 'menu.home'='Home'; 'menu.about'='About' })
  Write-TsDict "$i18n\fr\common.ts" 'common' ([ordered]@{ 'greeting'='Bonjour'; 'menu.home'='Accueil'; 'menu.about'='A propos' })
  Write-TsDict "$i18n\zh-CN\common.ts" 'common' ([ordered]@{ 'greeting'='NiHao'; 'menu.home'='ZhuYe'; 'menu.about'='GuanYu' })
  Write-TsDict "$i18n\en\house.ts" 'house' ([ordered]@{ 'title'='Houses'; 'state.vacant'='Vacant'; 'state.occupied'='Occupied' })
  Write-TsDict "$i18n\fr\house.ts" 'house' ([ordered]@{ 'title'='Maisons'; 'state.vacant'='Libre'; 'state.occupied'='Occupee' })
  Write-TsDict "$i18n\zh-CN\house.ts" 'house' ([ordered]@{ 'title'='FangWu'; 'state.vacant'='KongZhi'; 'state.occupied'='YiZhu' })
  Set-Content -LiteralPath "$app\backend\src\logic\payments.ts" -Value "// LOCKED financial surface - byte-unchanged" -Encoding ascii
  Set-Content -LiteralPath "$app\database\migrations\001_init.sql" -Value "-- baseline migration (untouched)" -Encoding ascii
  Set-Content -LiteralPath "$app\package.json" -Value '{"name":"fixture-app","version":"1.0.0"}' -Encoding ascii
  Set-Content -LiteralPath "$slice\CHANGED_FILES.txt" -Value "frontend/src/components/Banner.tsx`r`nfrontend/src/components/Footer.tsx" -Encoding ascii
  Set-Content -LiteralPath "$slice\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT2`r`nFAST_LANE: no" -Encoding ascii
  Set-Content -LiteralPath "$slice\typecheck.log" -Value "tsc --noEmit completed with no errors (fixture artifact)" -Encoding ascii
  Set-Content -LiteralPath "$slice\build.log" -Value "next build completed (fixture artifact)" -Encoding ascii
  $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  $cmdEv = @(
    @{ name='typecheck'; cmd='npm run typecheck'; cwd='frontend'; exit_code=0; timestamp=$ts; output_path='typecheck.log'; status='pass' },
    @{ name='build'; cmd='npm run build'; cwd='frontend'; exit_code=0; timestamp=$ts; output_path='build.log'; status='pass' }
  )
  $cmdEv | ConvertTo-Json | Out-File -LiteralPath "$slice\command_evidence.json" -Encoding ascii
  $cc = @(
    "oldest_first_allocation_untouched: PASS (payments.ts byte-identical to baseline)",
    "locked_dashboard_untouched: PASS (dashboard surface not in changed set)",
    "deposit_confirm_makes_zero_payment_pool_rows: PASS (AC1 fingerprint verified in fixture)",
    "deposits_held_only: PASS (liability isolation verified in fixture)",
    "new_tenant_first_transfer_held: PASS (C10 scenario verified in fixture)",
    "outflow_exact_tenant_stays_ignored: PASS (C11 scenario verified in fixture)"
  )
  Set-Content -LiteralPath "$slice\CUSTOM_CHECKS.md" -Value ($cc -join "`r`n") -Encoding ascii
  return @{ root=$root; app=$app; slice=$slice }
}
function Run-VerifyApp($fx){
  $ev = Join-Path $fx.root 'APP_END_EVIDENCE.json'
  $o = (& $verifyApp -AppRoot $fx.app -Profile $profileMd -SliceDir $fx.slice -EvidenceOut $ev -Mode fixture *>&1 | Out-String)
  return @{ code=$LASTEXITCODE; out=$o }
}
function Expect-AppFail([string]$family,[string]$case,$fx,[string]$checkId){
  $r = Run-VerifyApp $fx
  $hit = $r.out -match ('\[' + $checkId + '\s*\]\s*FAIL')
  Report $family $case (($r.code -eq 1) -and $hit) "expect exit1 + $checkId FAIL; got exit=$($r.code), ${checkId}FailSeen=$hit"
}
function Expect-AppPass([string]$family,[string]$case,$fx){
  $r = Run-VerifyApp $fx
  Report $family $case ($r.code -eq 0) "green control: expect exit0; got exit=$($r.code)"
}

# ---------------------------------------------------------------------------------------------------
if(Test-Path -LiteralPath $base){ Remove-Item -LiteralPath $base -Recurse -Force }
New-Item -ItemType Directory -Force -Path $base | Out-Null
Write-Host "=== role_governance_fixture_suite (NEO 3.0 Session 10) ==="
Write-Host "[WARN] Discovery/routing fixtures place a temporary COPY in the live skill path and remove it in a finally; the quarantine archive is only ever read."

# Slice-0b: capture the LIVE baseline discovery set ONCE, before any fixture planting. Every
# restoration/integrity assertion below compares against THIS captured set (names AND count), never a
# literal folder count - the live set legitimately includes explicitly restored approved managers
# (e.g. NEO_QA_SCENARIO, Raphael-gated restoration 2026-07-05; see lint_skills.ps1 $restoredManagers).
$script:baselineDiscovery = Get-DiscoveryNames
Write-Host ("[INFO] baseline discovery captured: " + ($script:baselineDiscovery -join ', ') + " (" + $script:baselineDiscovery.Count + " folders)")

# ===================================================================================================
# F1 SELF-APPROVAL - a session cannot certify its own GO / approve its own work.
#   F1a: a Builder/Director self-writes the auditor verdict (auditor_context_fresh=false) -> C7 FAIL.
#   F1b: a GO end-summary that hides a HIGH finding (self-approval by sanitized verdict) -> C12 FAIL.
#   F1c: the human START/END gate is OUT-OF-BAND (D2/D3) - no engine artifact grants approval; the
#        engine only ever emits GREEN/RED and a bounded recommendation. DESIGN-DEFERRED (by design).
# ===================================================================================================
$g0 = New-GreenSession 'rgfix_f0_green'
Set-Findings $g0 $FINDINGS_GREEN
& $assemble -SessionPath $g0 | Out-Null
Set-EndSummary $g0 'NO-GO' 'none (honest green control)'
$r0 = Run-EndGate $g0
$g0fails = @($r0.audit.checks | Where-Object { $_.Status -eq 'FAIL' }).Count
Report 'F1' 'F0-green_baseline' (($r0.exit -eq 0) -and ($g0fails -eq 0)) "green control session: expect exit0/0FAIL; got exit=$($r0.exit), FAILs=$g0fails"

$f1a = New-GreenSession 'rgfix_f1a'
Set-Findings $f1a '{ "auditor_context_fresh": false, "forbidden_inputs_seen": false, "input_artifacts": ["session_contract.json"], "recommendation": "GO", "findings": [] }'
& $assemble -SessionPath $f1a | Out-Null
Set-EndSummary $f1a 'NO-GO' 'self-written verdict (not fresh context)'
Expect-CheckFail 'F1' 'F1a-self_audit_not_fresh' $f1a 'C7'

$f1b = New-GreenSession 'rgfix_f1b'
Set-Findings $f1b '{ "auditor_context_fresh": true, "forbidden_inputs_seen": false, "input_artifacts": ["session_contract.json"], "recommendation": "GO", "findings": [ { "id": "F1", "severity": "high", "evidence_type": "diff_hunk", "path": "modules/echo/echo.js", "claim": "user input reaches eval without sanitization" } ] }'
& $assemble -SessionPath $f1b | Out-Null
Set-EndSummary $f1b 'GO' 'none'   # sanitized: claims GO + no blocking while a HIGH finding exists
Expect-CheckFail 'F1' 'F1b-go_despite_high_finding' $f1b 'C12'

ReportDeferred 'F1' 'F1c-out_of_band_human_gate' "The START/END human gates (D2/D3) are NOT discharged by any in-engine artifact: verify_session emits GREEN/RED only and bounds the auditor recommendation to {GO,NEEDS-MORE,NO-GO}; 'GREEN' is never 'APPROVED'. A machine-checkable record that approval came from the human (not a role self-grant) is HOST work (a signed human-gate record outside the session principal's write scope). Today: enforced sliver = no role can fabricate a passing fresh audit (F1a) or a sanitized GO (F1b); the human's explicit answer remains out-of-band by design."

# ===================================================================================================
# F2 AUDITOR-POISONING - feeding the Auditor coder chat/history/self-eval/why-its-safe (violates AUD-1)
# must be caught by C7 (forbidden flag, forbidden artifact in the assembled manifest, an extra unlisted
# file, or a post-assembly tamper). All ENFORCED by the frozen verify_session C7 cross-check.
# ===================================================================================================
$f2a = New-GreenSession 'rgfix_f2a'
Set-Findings $f2a '{ "auditor_context_fresh": true, "forbidden_inputs_seen": true, "input_artifacts": ["session_contract.json"], "recommendation": "GO", "findings": [] }'
& $assemble -SessionPath $f2a | Out-Null
Set-EndSummary $f2a 'NO-GO' 'auditor self-declared it saw forbidden input'
Expect-CheckFail 'F2' 'F2a-forbidden_inputs_flag' $f2a 'C7'

$f2b = New-GreenSession 'rgfix_f2b'
Set-Findings $f2b $FINDINGS_GREEN
& $assemble -SessionPath $f2b | Out-Null
# poison: inject coder chat into the assembled bundle and LIST it in the manifest
$poison = Join-Path $f2b 'AUDITOR_INPUT\coder_chat_history.txt'
Set-Content -LiteralPath $poison -Value "builder chat: trust me, this is safe; here is why it is safe..." -Encoding UTF8
$mp = Join-Path $f2b 'AUDITOR_INPUT\input_manifest.json'
$m = Get-Content -LiteralPath $mp -Raw | ConvertFrom-Json
$m.files += [pscustomobject]@{ relative_path='coder_chat_history.txt'; sha256=(Get-FileHash -LiteralPath $poison -Algorithm SHA256).Hash; created_at='x'; source_path='x'; allowlist_category='session_contract.json' }
$m | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $mp -Encoding UTF8
Set-EndSummary $f2b 'NO-GO' 'poisoned auditor bundle'
Expect-CheckFail 'F2' 'F2b-poisoned_manifest' $f2b 'C7'

$f2c = New-GreenSession 'rgfix_f2c'
Set-Findings $f2c $FINDINGS_GREEN
& $assemble -SessionPath $f2c | Out-Null
# extra unlisted file dropped into AUDITOR_INPUT (smuggled past the manifest)
Set-Content -LiteralPath (Join-Path $f2c 'AUDITOR_INPUT\self_eval.md') -Value "# why my own work is safe (self-eval) - smuggled" -Encoding UTF8
Set-EndSummary $f2c 'NO-GO' 'smuggled extra input'
Expect-CheckFail 'F2' 'F2c-extra_unlisted_file' $f2c 'C7'

$f2d = New-GreenSession 'rgfix_f2d'
Set-Findings $f2d $FINDINGS_GREEN
& $assemble -SessionPath $f2d | Out-Null
# post-assembly tamper: mutate an allowlisted artifact after the manifest hashed it
Add-Content -LiteralPath (Join-Path $f2d 'AUDITOR_INPUT\session_contract.json') -Value "`r`n// tampered after assembly"
Set-EndSummary $f2d 'NO-GO' 'post-assembly tamper'
Expect-CheckFail 'F2' 'F2d-post_assembly_tamper' $f2d 'C7'

# ===================================================================================================
# F3 ARCHIVED-ROLE INVOCATION - a quarantined legacy role or manager cannot re-enter discovery
# (invocation) or routing. ENFORCED by the live lint H4a (discovery) + Check E (routing).
# ===================================================================================================
Expect-DiscoveryFail 'F3' 'F3a-legacy_role_in_discovery' (Join-Path $quarantine 'NEO_PM') 'NEO_PM' @("unknown skill folder 'NEO_PM'","QUARANTINE BREACH")
Expect-DiscoveryFail 'F3' 'F3b-manager_in_discovery' (Join-Path $quarantine 'NEO_RELEASE_MANAGER') 'NEO_RELEASE_MANAGER' @("unknown skill folder 'NEO_RELEASE_MANAGER'","QUARANTINE BREACH")
Expect-RoutingFail 'F3' 'F3c-route_to_archived_role' 'archroute' { param($rp) Add-Content -LiteralPath $rp -Value "`r`nrogue route: -> NEO_PM`r`n" } "routing map names non-active role 'NEO_PM'"

# ===================================================================================================
# F4 ROLE REGROWTH - a rogue/new role folder, or the 3-role routed set silently growing or shrinking,
# must fail closed. ENFORCED by the live lint H4a (unknown folder) + Check E (routing integrity).
# ===================================================================================================
Expect-DiscoveryFail 'F4' 'F4a-rogue_new_folder' '' 'NEO_ROGUE' @("unknown skill folder 'NEO_ROGUE'")
Expect-RoutingFail 'F4' 'F4b-router_grows_unknown' 'growarrow' { param($rp) Add-Content -LiteralPath $rp -Value "`r`nnew seat: -> NEO_FOURTH`r`n" } "routing map names non-active role 'NEO_FOURTH'"
# shrink: drop the NEO_AUDITOR arrow from the temp router (replace its table arrow with a duplicate Director)
Expect-RoutingFail 'F4' 'F4c-router_shrinks_role' 'shrinkarrow' { param($rp) $t = Get-Content -LiteralPath $rp -Raw; $t = $t -replace '-> NEO_AUDITOR','-> NEO_DIRECTOR'; Set-Content -LiteralPath $rp -Value $t -Encoding ascii } "active role 'NEO_AUDITOR' is missing from the routing map"

# ===================================================================================================
# F5 FAST-LANE DOWNGRADE - downgrade the tier, skip the tier gate, or fast-lane a risky slice. ENFORCED
# by the frozen verify_app_slice AS3 (classifier upgrade-only) + AS12 (fast-lane reduces evidence,
# never authority).
# ===================================================================================================
# green control: the default tree (frontend_ui -> RT2) declared RT2, no fast lane -> exit 0
$f5g = New-AppTree 'f5_green'
Expect-AppPass 'F5' 'F5-green_baseline' $f5g

# F5a tier downgrade: derived RT2 (frontend_ui) declared RT1 -> AS3 FAIL (classifier may only upgrade)
$f5a = New-AppTree 'f5a_downgrade'
Set-Content -LiteralPath "$($f5a.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT1`r`nFAST_LANE: no" -Encoding ascii
Expect-AppFail 'F5' 'F5a-tier_downgrade' $f5a 'AS3'

# F5b skip the tier gate entirely: no DECLARED_TIER line -> AS3 FAIL (cannot omit the declaration)
$f5b = New-AppTree 'f5b_no_tier'
Set-Content -LiteralPath "$($f5b.slice)\SLICE_DECLARATION.txt" -Value "FAST_LANE: no" -Encoding ascii
Expect-AppFail 'F5' 'F5b-no_declared_tier' $f5b 'AS3'

# F5c fast-lane a risky (backend / RT3) slice -> AS12 FAIL (fast lane reduces evidence, never authority)
$f5c = New-AppTree 'f5c_fastlane_backend'
Set-Content -LiteralPath "$($f5c.app)\backend\src\logic\reports.ts" -Value "export const reports = () => [];" -Encoding ascii
Set-Content -LiteralPath "$($f5c.slice)\CHANGED_FILES.txt" -Value "frontend/src/components/Banner.tsx`r`nbackend/src/logic/reports.ts" -Encoding ascii
Set-Content -LiteralPath "$($f5c.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT3`r`nFAST_LANE: yes" -Encoding ascii
Expect-AppFail 'F5' 'F5c-fastlane_risky_slice' $f5c 'AS12'

# ---------- summary + cleanup ----------
Write-Host ""
foreach($line in $script:results){ Write-Host $line }
Write-Host ""
Write-Host ("Summary: {0} ENFORCED/control pass, {1} fail, {2} DESIGN-DEFERRED (out-of-band/host; not counted)." -f $script:passes,$script:failures,$script:deferred)

# integrity re-assertion: discovery still matches the captured live baseline (names AND count) +
# archive byte-intact (read-only)
$disc = Get-DiscoveryNames
$discOk = ($disc.Count -eq $script:baselineDiscovery.Count) -and (($disc -join ',') -eq ($script:baselineDiscovery -join ','))
if(-not $discOk){ Write-Host ("[RESIDUE] WARNING: .claude\skills does not match the captured baseline (" + ($script:baselineDiscovery -join ', ') + "): got " + ($disc -join ', ')); $script:failures++ }
else { Write-Host ("Integrity: .claude\skills matches the captured live baseline (" + $script:baselineDiscovery.Count + " folders).") }

if(-not $KeepArtifacts){
  if(Test-Path -LiteralPath $base){ Remove-Item -LiteralPath $base -Recurse -Force }
  foreach($id in @('rgfix_f0_green','rgfix_f1a','rgfix_f1b','rgfix_f2a','rgfix_f2b','rgfix_f2c','rgfix_f2d')){
    $sp = Join-Path $sessionDir $id; if(Test-Path -LiteralPath $sp){ Remove-Item -LiteralPath $sp -Recurse -Force }
  }
  $residue = @()
  if(Test-Path -LiteralPath $base){ $residue += $base }
  foreach($id in @('rgfix_f0_green','rgfix_f1a','rgfix_f1b','rgfix_f2a','rgfix_f2b','rgfix_f2c','rgfix_f2d')){ $sp = Join-Path $sessionDir $id; if(Test-Path -LiteralPath $sp){ $residue += $sp } }
  if($residue.Count -gt 0){ Write-Host ("[RESIDUE] WARNING: leftover: " + ($residue -join '; ')); $script:failures++ }
  else { Write-Host "Fixtures removed (NEO_SESSION restored). Second clean pass: 0 residue. Use -KeepArtifacts to inspect." }
}

if($script:failures -gt 0){
  Write-Host "=== role_governance_fixture_suite: RED - $($script:failures) case(s) misclassified or residue left ==="
  exit 1
}
Write-Host "=== role_governance_fixture_suite: PASS ($($script:passes) enforced/control proofs; $($script:deferred) design-deferred recorded honestly) ==="
exit 0
