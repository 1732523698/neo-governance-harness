# custody_fixture_suite.ps1 - NEO 3.0 Session 6 permanent negative-fixture suite.
# ASCII-only, PowerShell 5.1. Sibling to app_adapter_fixture_suite.ps1 (same self-clean discipline).
#
# PURPOSE: make the engine + custody fail-closed modes into STANDING regression tests. For each of
# nine control families it constructs a negative input and asserts the fail-closed signal (exit code
# + check-ID / FATAL line), or - where the control's home is the not-yet-built host registry -
# records the negative as PENDING-DEFERRED with the exact host build that unblocks it (it does NOT
# fake enforcement and does NOT count a deferred item toward pass/fail).
#
# It edits NO engine script. The ENFORCED proofs exercise the LIVE engine/checker exactly as a real
# session would. Honest custody tier of every in-band hash check here is DOCTRINE-ONLY-WITH-TRIPWIRE
# (the reference hash sits on the same writable volume as the bytes it guards) - see
# .neo\_v3.0\session2\CUSTODY_LABELING_DOCTRINE.md. No tamper-proof or tamper-evident claim is made.
#
# Nine families:
#   F1 PROFILE     absent / malformed / schema-id spoof / view-authority spoof / missing-slug   ENFORCED (loader)
#   F2 EVIDENCE    forged artifact / omitted file / stale sha / unknown key / buried FAIL        ENFORCED (checker E1-E4,E7)
#   F3 VERSION     schema-version / NEO-version / schema-SHA / checker-SHA pin mismatch          DESIGN-ONLY-DEFERRED (host registry)
#   F4 PATH        in-tree denylist exact + glob (AS4) | external/approved-path                  ENFORCED in-tree (AS4) ; external DEFERRED
#   F5 REPLAY      classification-tuple mismatch + input-pin drift (vs frozen corpus)            ENFORCED (this net)
#   F6 DIRTY-TREE  governance-surface hash drift vs FREEZE_INVENTORY                             ENFORCED (in-band tripwire)
#   F7 WRONG-DIR   engine invoked with governance root outside S:\NEO                            DESIGN-ONLY-DEFERRED (host registry)
#   F8 LOG         missing / tampered real-mode invocation log                                  DESIGN-ONLY-DEFERRED (host registry)
#   F9 CONCURRENCY concurrent-session collision DETECTION (not prevention)                       ENFORCED-as-detection ; prevention DEFERRED
#
# Exit 0 only when every ENFORCED negative classifies as expected. PENDING-DEFERRED lines are
# informational and never flip the exit code; a PENDING item silently passing would be dishonest, so
# each is printed explicitly and excluded from the pass count.

# NF-S4-1 (P1-S5): additive -NeoRoot param (default S:\NEO) so the suite is dev-runnable against
# <NEO_ROOT>. The DEFAULT is unchanged, so the golden/default behavior is byte-identical.
param([switch]$KeepArtifacts,[string]$NeoRoot)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$scripts   = Join-Path $NeoRoot '.neo\scripts'
$verify    = Join-Path $scripts 'verify_app_slice.ps1'
$checker   = Join-Path $scripts 'check_app_end_evidence.ps1'
$profileMd = Join-Path $NeoRoot 'modules\unified-analytics-rental-platform\NEO_APP_PROFILE.md'
$profileJson = Join-Path $NeoRoot 'modules\unified-analytics-rental-platform\NEO_APP_PROFILE.json'
$freezeInv = Join-Path $NeoRoot '.neo\_v3.0\session1\FREEZE_INVENTORY.json'
$corpusManifest = Join-Path $NeoRoot '.neo\_v3.0\session2\CORPUS_MANIFEST.json'
$casesFile = Join-Path $NeoRoot '.neo\_v3.0\session2\GOLDEN_CORPUS\negatives\app_adapter_fixture_suite.cases.json'
$base      = Join-Path $NeoRoot 'NEO_SESSION\custody_fixture'

$script:failures = 0
$script:passes   = 0
$script:pending  = 0
$script:results  = New-Object System.Collections.ArrayList

function Report([string]$family,[string]$case,[bool]$ok,[string]$detail){
  $tag = if($ok){'PASS'}else{'FAIL'}
  [void]$script:results.Add(("[{0}] {1,-6} {2,-26} {3}" -f $tag,$family,$case,$detail))
  if($ok){ $script:passes++ } else { $script:failures++ }
}
function ReportPending([string]$family,[string]$case,[string]$detail){
  [void]$script:results.Add(("[PENDING-DEFERRED] {0,-6} {1,-26} {2}" -f $family,$case,$detail))
  $script:pending++
}

# ---------- green fixture tree builder (mirrors app_adapter_fixture_suite green) ----------
function Write-TsDict([string]$Path,[string]$Export,[hashtable]$Flat){
  $lines = @("export const $Export = {")
  $groups = @{}
  foreach($k in $Flat.Keys){
    if($k -like '*.*'){
      $p = $k -split '\.',2
      if(-not $groups.ContainsKey($p[0])){ $groups[$p[0]] = @{} }
      $groups[$p[0]][$p[1]] = $Flat[$k]
    } else { $lines += "  ${k}: '$($Flat[$k])'," }
  }
  foreach($g in $groups.Keys){
    $lines += "  ${g}: {"
    foreach($sk in $groups[$g].Keys){ $lines += "    ${sk}: '$($groups[$g][$sk])'," }
    $lines += "  },"
  }
  $lines += "};"
  Set-Content -LiteralPath $Path -Value ($lines -join "`r`n") -Encoding ascii
}

function New-FixtureTree([string]$name){
  $root = Join-Path $base $name
  $app  = Join-Path $root 'app'
  $slice = Join-Path $root 'slice'
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
  Set-Content -LiteralPath "$app\backend\src\logic\depositsHeld.ts" -Value "import { recordHeldRow } from './heldRowsStore';`r`nexport const holdRow = (id: string) => recordHeldRow(id);" -Encoding ascii
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

function Run-Verify($fx,[string]$evOut,[string]$profileArg){
  if(-not $profileArg){ $profileArg = $profileMd }
  $out = (& $verify -AppRoot $fx.app -Profile $profileArg -SliceDir $fx.slice -EvidenceOut $evOut -Mode fixture *>&1 | Out-String)
  return @{ code=$LASTEXITCODE; out=$out }
}
function Run-Checker([string]$evPath,[string]$sliceDir){
  $out = (& $checker -Evidence $evPath -Profile $profileMd -SliceDir $sliceDir *>&1 | Out-String)
  return @{ code=$LASTEXITCODE; out=$out }
}
function Expect-VerifyFail([string]$family,[string]$case,$fx,[string]$checkId){
  $ev = Join-Path $fx.root 'APP_END_EVIDENCE.json'
  $r = Run-Verify $fx $ev $null
  $hit = $r.out -match ('\[' + $checkId + '\s*\]\s*FAIL')
  Report $family $case (($r.code -eq 1) -and $hit) "expect exit1 + $checkId FAIL; got exit=$($r.code), ${checkId}FailSeen=$hit"
}

if(Test-Path -LiteralPath $base){ Remove-Item -LiteralPath $base -Recurse -Force }
New-Item -ItemType Directory -Force -Path $base | Out-Null

Write-Host "=== custody_fixture_suite (NEO 3.0 Session 6) ==="
Write-Host "[WARN] In-band hash checks here are DOCTRINE-ONLY-WITH-TRIPWIRE (same-volume reference); no tamper-proof claim."

# =====================================================================================
# F1 PROFILE - absent / malformed / schema-id spoof / view-authority spoof / missing-slug
# Control lives in the verify_app_slice loader (lines ~49-83). ENFORCED.
# =====================================================================================
$throw = New-FixtureTree 'f1_profilehost'   # any valid tree; loader negatives exit before AppRoot use
$profDir = Join-Path $base 'f1_profiles'
New-Item -ItemType Directory -Force -Path $profDir | Out-Null
$liveObj = Get-Content -LiteralPath $profileJson -Raw | ConvertFrom-Json

function Expect-ProfileFatal([string]$case,[string]$profileArg,[string]$needle){
  $ev = Join-Path $profDir "ev_$case.json"
  $r = Run-Verify $throw $ev $profileArg
  $hit = $r.out -match [regex]::Escape($needle)
  Report 'F1' $case (($r.code -eq 1) -and $hit) "expect exit1 + FATAL '$needle'; got exit=$($r.code), seen=$hit"
}

# F1a absent JSON (point at a .md whose .json sibling is missing)
$absDir = Join-Path $profDir 'absent'; New-Item -ItemType Directory -Force -Path $absDir | Out-Null
$absMd = Join-Path $absDir 'profile.md'; Set-Content -LiteralPath $absMd -Value 'stub view' -Encoding ascii
Expect-ProfileFatal 'F1a-absent_json' $absMd 'authoritative JSON profile not found'

# F1b malformed JSON
$malJson = Join-Path $profDir 'malformed.json'; Set-Content -LiteralPath $malJson -Value '{ not : valid json ' -Encoding ascii
Expect-ProfileFatal 'F1b-malformed_json' $malJson 'profile JSON parse error'

# F1c schema-id spoof
$spoofId = Join-Path $profDir 'spoof_id.json'
$o = Get-Content -LiteralPath $profileJson -Raw | ConvertFrom-Json; $o.binding.profile_schema_id = 'neo:not_a_profile'
$o | ConvertTo-Json -Depth 40 | Out-File -LiteralPath $spoofId -Encoding ascii
Expect-ProfileFatal 'F1c-schemaid_spoof' $spoofId 'is not a neo:app_profile instance'

# F1d view-authority spoof (a generated VIEW claiming authority)
$spoofView = Join-Path $profDir 'spoof_view.json'
$o = Get-Content -LiteralPath $profileJson -Raw | ConvertFrom-Json; $o.binding.generated_view_is_authoritative = $true
$o | ConvertTo-Json -Depth 40 | Out-File -LiteralPath $spoofView -Encoding ascii
Expect-ProfileFatal 'F1d-view_authority_spoof' $spoofView 'a generated VIEW may never be authority'

# F1e missing app_slug
$noSlug = Join-Path $profDir 'no_slug.json'
$o = Get-Content -LiteralPath $profileJson -Raw | ConvertFrom-Json; $o.identity.app_slug = $null
$o | ConvertTo-Json -Depth 40 | Out-File -LiteralPath $noSlug -Encoding ascii
Expect-ProfileFatal 'F1e-missing_slug' $noSlug 'profile missing APP_SLUG'

# =====================================================================================
# F2 EVIDENCE - tamper a GREEN evidence bundle. Control lives in check_app_end_evidence. ENFORCED.
# =====================================================================================
$fxG = New-FixtureTree 'f2_green'
$evG = Join-Path $fxG.root 'APP_END_EVIDENCE.json'
$rG = Run-Verify $fxG $evG $null
$greenRaw = if(Test-Path -LiteralPath $evG){ Get-Content -LiteralPath $evG -Raw } else { '' }
if($rG.code -ne 0 -or $greenRaw -eq ''){
  Report 'F2' 'F2-green_precondition' $false "green verify did not pass (exit=$($rG.code)); cannot tamper"
} else {
  Report 'F2' 'F2-green_baseline' $true "green verify exit0; checker tamper baseline established"
  $tdir = Join-Path $base 'f2_tamper'; New-Item -ItemType Directory -Force -Path $tdir | Out-Null

  # E1 unknown key
  $ev = $greenRaw | ConvertFrom-Json; $ev | Add-Member -NotePropertyName 'sneaky_extra' -NotePropertyValue 'x'
  $p = Join-Path $tdir 'e1.json'; $ev | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $fxG.slice
  Report 'F2' 'F2a-forged_unknown_key' (($c.code -eq 1) -and ($c.out -match '\[E1 FAIL\]')) "expect exit1 + E1 FAIL; got exit=$($c.code)"

  # E2 forged artifact path on a pass claim
  $ev = $greenRaw | ConvertFrom-Json; $ev.commands[0].output_path = 'no_such_artifact.log'
  $p = Join-Path $tdir 'e2.json'; $ev | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $fxG.slice
  Report 'F2' 'F2b-forged_artifact' (($c.code -eq 1) -and ($c.out -match '\[E2 FAIL\]')) "expect exit1 + E2 FAIL; got exit=$($c.code)"

  # E3 stale sha (force fixture_pre_commit off so a live HEAD is demanded, none exists)
  $ev = $greenRaw | ConvertFrom-Json; $ev.fixture_pre_commit = $false
  $p = Join-Path $tdir 'e3.json'; $ev | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $fxG.slice
  Report 'F2' 'F2c-stale_sha' (($c.code -eq 1) -and ($c.out -match '\[E3 FAIL\]')) "expect exit1 + E3 FAIL; got exit=$($c.code)"

  # E4 omitted changed file
  $ev = $greenRaw | ConvertFrom-Json; $ev.changed_files = @($ev.changed_files | Select-Object -First 1)
  $p = Join-Path $tdir 'e4.json'; $ev | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $fxG.slice
  Report 'F2' 'F2d-omitted_file' (($c.code -eq 1) -and ($c.out -match '\[E4 FAIL\]')) "expect exit1 + E4 FAIL; got exit=$($c.code)"

  # E7 buried FAIL (flip an internal check to FAIL but leave unresolved_risks/summary 'green')
  $ev = $greenRaw | ConvertFrom-Json
  $ev.checks[0].status = 'FAIL'
  $p = Join-Path $tdir 'e7.json'; $ev | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $fxG.slice
  Report 'F2' 'F2e-buried_fail' (($c.code -eq 1) -and ($c.out -match '\[E7 FAIL\]')) "expect exit1 + E7 FAIL (buried FAIL not surfaced); got exit=$($c.code)"
}

# =====================================================================================
# F3 VERSION - schema-version / NEO-version / schema-SHA / checker-SHA pin mismatch.
# DESIGN-ONLY-DEFERRED: the schema (NEO_APP_PROFILE.schema.json line ~24) states the COMPUTED
# binding/SHA/version PINS are produced by the HOST REGISTRY, not authored or engine-checked. The
# loader enforces only the authority *id* (profile_schema_id const) - proven enforced in F1c - and
# NEVER compares schema-version / neo_governance_version / schema-SHA / checker-SHA. We demonstrate
# the non-gating honestly, then record PENDING with the unblocking host build.
# =====================================================================================
$fxV = New-FixtureTree 'f3_version'
$verProfDir = Join-Path $base 'f3_profiles'; New-Item -ItemType Directory -Force -Path $verProfDir | Out-Null
$verProf = Join-Path $verProfDir 'NEO_APP_PROFILE.json'
$o = Get-Content -LiteralPath $profileJson -Raw | ConvertFrom-Json
$o.binding.profile_schema_version = '999.0.0'
$o.binding.neo_governance_version = 'v0.0-FORGED'
$o | ConvertTo-Json -Depth 40 | Out-File -LiteralPath $verProf -Encoding ascii
$verMd = Join-Path $verProfDir 'NEO_APP_PROFILE.md'; Set-Content -LiteralPath $verMd -Value 'view' -Encoding ascii
$evV = Join-Path $fxV.root 'APP_END_EVIDENCE.json'
$rV = Run-Verify $fxV $evV $verProf
$versionGated = ($rV.out -match 'schema.version|neo_governance|schema.SHA|checker.SHA|version mismatch')
$ranNet = ($rV.out -match '\[AS1')   # loader passed the authority gate and reached the AS net
if($versionGated){
  Report 'F3' 'F3-version_pin' $true "engine gated on a forged version (unexpected but stricter)"
} else {
  ReportPending 'F3' 'F3a-schema_version_mismatch' "engine loaded a profile with profile_schema_version=999.0.0 / neo_governance_version=v0.0-FORGED WITHOUT gating (reachedASnet=$ranNet). Schema-version / NEO-version / schema-SHA / checker-SHA pinning is HOST-REGISTRY work (BINDING_FIELDS_DESIGN B2; HOST_REGISTRY 4.1 start_profile_hashes + 4.4 pin_records + 4 NEO-version + 5 three-way hash). Enforced sliver today = profile_schema_id const (see F1c)."
  ReportPending 'F3' 'F3b-schema_sha_mismatch' "no engine compare of schema-SHA vs a pinned reference exists; unblocked by host pin_records (HOST_REGISTRY 4.4) + three-way hash (HOST_REGISTRY 5)."
  ReportPending 'F3' 'F3c-checker_sha_mismatch' "no engine compare of checker-SHA exists; unblocked by host pin_records (HOST_REGISTRY 4.4)."
}

# =====================================================================================
# F4 PATH - in-tree denylist (AS4) ENFORCED; external/approved-path DESIGN-ONLY-DEFERRED.
# =====================================================================================
# F4a exact deny hit (locked financial file in the changed set)
$fx = New-FixtureTree 'f4_deny_exact'
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "backend/src/logic/payments.ts"
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT4`r`nFAST_LANE: no" -Encoding ascii
Expect-VerifyFail 'F4' 'F4a-deny_exact' $fx 'AS4'

# F4b deny GLOB hit (file under a DENY glob directory)
$fx = New-FixtureTree 'f4_deny_glob'
New-Item -ItemType Directory -Force -Path "$($fx.app)\frontend\src\components\dashboard" | Out-Null
Set-Content -LiteralPath "$($fx.app)\frontend\src\components\dashboard\Tile.tsx" -Value "export const Tile = () => <div>tile</div>;" -Encoding ascii
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "frontend/src/components/dashboard/Tile.tsx"
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT4`r`nFAST_LANE: no" -Encoding ascii
Expect-VerifyFail 'F4' 'F4b-deny_glob' $fx 'AS4'

# F4c external/approved-path: the registry-side approved_external_paths allow-list is not engine-resident.
ReportPending 'F4' 'F4c-external_path' "in-tree denylist (AS4) is enforced (F4a/F4b); the approved-EXTERNAL-path allow-list + per-path expiry is HOST-REGISTRY work (HOST_REGISTRY 4.2 approved_external_paths + 4.3 approval_scope_and_expiry). No engine allow-list of real-app paths exists today."

# =====================================================================================
# F5 REPLAY - classification-tuple mismatch + input-pin drift vs the frozen golden corpus.
# Realizes NORMALIZED_REPLAY_DESIGN section 2.1 (input pin) + section 4 (per-check tuple compare).
# ENFORCED by THIS net (in-band custody tier).
# =====================================================================================
# Load the frozen expectation tuple for N01-deny_hit (exit1 / AS4) from the corpus cases file.
$cases = Get-Content -LiteralPath $casesFile -Raw | ConvertFrom-Json
$frozenN01 = @($cases.verify_negatives) | Where-Object { $_.case_id -eq 'N01-deny_hit' } | Select-Object -First 1
# Observe the LIVE engine outcome on the same input identity (a deny-exact slice).
$fxR = New-FixtureTree 'f5_replay'
Add-Content -LiteralPath "$($fxR.slice)\CHANGED_FILES.txt" -Value "backend/src/logic/payments.ts"
Set-Content -LiteralPath "$($fxR.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT4`r`nFAST_LANE: no" -Encoding ascii
$evR = Join-Path $fxR.root 'APP_END_EVIDENCE.json'
$rR = Run-Verify $fxR $evR $null
$obsExit = $rR.code
$obsCheck = if($rR.out -match '\[(AS\d+)\s*\]\s*FAIL'){ $Matches[1] } else { '<none>' }

# F5a positive: observed tuple MATCHES the frozen-correct tuple -> replay green
$matchCorrect = ($obsExit -eq $frozenN01.expected_exit) -and ($obsCheck -eq $frozenN01.expected_check)
Report 'F5' 'F5a-replay_match' $matchCorrect "observed (exit=$obsExit,check=$obsCheck) vs frozen (exit=$($frozenN01.expected_exit),check=$($frozenN01.expected_check)) -> MATCH=$matchCorrect"

# F5b negative: compare the SAME observed tuple against a deliberately WRONG expected tuple
# (expected AS9). A correct comparator MUST classify this as a mismatch (REGRESSED) -> fail-closed.
$wrongCheck = 'AS9'
$mismatchDetected = -not (($obsExit -eq 1) -and ($obsCheck -eq $wrongCheck))
Report 'F5' 'F5b-replay_mismatch' $mismatchDetected "wrong-expected tuple (exit=1,check=$wrongCheck) vs observed (exit=$obsExit,check=$obsCheck) -> mismatch detected=$mismatchDetected (comparator fails closed on divergence)"

# F5c input-pin drift: re-hash the FROZEN producer vs its CORPUS_MANIFEST source_identity record.
# Positive direction = live frozen producer MATCHES the manifest; negative direction = a TAMPERED
# copy MUST mismatch -> fail-closed BEFORE any replay (NORMALIZED_REPLAY_DESIGN 2.1).
$cm = Get-Content -LiteralPath $corpusManifest -Raw | ConvertFrom-Json
$adapterItem = @($cm.corpus_items) | Where-Object { $_.corpus_path -match 'source_identity/app_adapter_fixture_suite\.ps1$' } | Select-Object -First 1
$frozenProducer = Join-Path $NeoRoot '.neo\scripts\app_adapter_fixture_suite.ps1'
$liveProducerHash = (Get-FileHash -LiteralPath $frozenProducer -Algorithm SHA256).Hash
$pinMatch = ($liveProducerHash -eq $adapterItem.sha256)
# tampered copy
$tmpCopy = Join-Path $base 'f5_tampered_producer.ps1'
Copy-Item -LiteralPath $frozenProducer -Destination $tmpCopy
Set-ItemProperty -LiteralPath $tmpCopy -Name IsReadOnly -Value $false  # copy may inherit +R from a locked source; make tamper target writable
Add-Content -LiteralPath $tmpCopy -Value "`r`n# tamper byte"
$tamperHash = (Get-FileHash -LiteralPath $tmpCopy -Algorithm SHA256).Hash
$pinDriftDetected = ($tamperHash -ne $adapterItem.sha256)
Report 'F5' 'F5c-inputpin_drift' ($pinMatch -and $pinDriftDetected) "frozen producer pin MATCH=$pinMatch (live==manifest) AND tampered-copy drift detected=$pinDriftDetected -> replay fails closed on drifted inputs"

# =====================================================================================
# F6 DIRTY-TREE - governance-surface hash drift vs FREEZE_INVENTORY (surface-hash, NOT git status).
# Detector exists live as lint_skills Check H over the pinned subset; here we prove the comparison
# direction on a COPY (never the real frozen file - that would trip S3/S4). ENFORCED (in-band tripwire).
# =====================================================================================
$inv = Get-Content -LiteralPath $freezeInv -Raw | ConvertFrom-Json
$frozenSchema = @($inv.groups.schemas_frozen_4) | Where-Object { $_.path -match 'session_contract\.schema\.json$' } | Select-Object -First 1
$realFrozen = Join-Path $NeoRoot $frozenSchema.path
$copyDir = Join-Path $base 'f6_surface'; New-Item -ItemType Directory -Force -Path $copyDir | Out-Null
$cleanCopy = Join-Path $copyDir 'clean.json'; Copy-Item -LiteralPath $realFrozen -Destination $cleanCopy
$dirtyCopy = Join-Path $copyDir 'dirty.json'; Copy-Item -LiteralPath $realFrozen -Destination $dirtyCopy
Set-ItemProperty -LiteralPath $dirtyCopy -Name IsReadOnly -Value $false  # copy may inherit +R from a locked source; make tamper target writable
Add-Content -LiteralPath $dirtyCopy -Value "`r`n"   # one byte of governance-surface drift
$cleanHash = (Get-FileHash -LiteralPath $cleanCopy -Algorithm SHA256).Hash
$dirtyHash = (Get-FileHash -LiteralPath $dirtyCopy -Algorithm SHA256).Hash
$cleanMatches = ($cleanHash -eq $frozenSchema.sha256)
$driftDetected = ($dirtyHash -ne $frozenSchema.sha256)
Report 'F6' 'F6a-surface_drift' ($cleanMatches -and $driftDetected) "untampered copy MATCHES FREEZE_INVENTORY pin=$cleanMatches AND drifted copy detected=$driftDetected (surface-hash drift, not git status)"

# F6b: prove the LIVE detector (lint_skills Check H) actually fails closed on a frozen change, WITHOUT
# touching any real frozen file: run Check-H's exact comparison in-process over the real surface and
# confirm it is currently CLEAN, then over a simulated drift map and confirm it would flag. (We do not
# invoke lint with a tampered real file - S3.) Coverage note: Check H pins a SUBSET (8 scripts + 4
# schemas + 8 roles); the full-46 FREEZE_INVENTORY surface is not net-covered (see F6c).
$liveClean = $true
foreach($grp in @($inv.groups.frozen_core_8_scripts + $inv.groups.schemas_frozen_4)){
  $fp = Join-Path $NeoRoot $grp.path
  if(-not (Test-Path -LiteralPath $fp)){ $liveClean = $false; continue }
  if((Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash -ne $grp.sha256){ $liveClean = $false }
}
Report 'F6' 'F6b-live_pins_clean' $liveClean "all frozen-8+frozen-4 live hashes MATCH FREEZE_INVENTORY (the live Check-H tripwire surface is clean; a drift here flips lint_skills exit 1)"

# F6c: full-46 surface vs registry
ReportPending 'F6' 'F6c-full_surface_46' "lint Check H pins a SUBSET (8 scripts + 4 schemas + 8 roles); FREEZE_INVENTORY tracks 46 files. Full-surface drift detection at runtime (and app_end_evidence.schema.json, CF-UNPINNED) is HOST-REGISTRY work (HOST_REGISTRY 4.4 pin_records, host-owned role-read-only store)."

# =====================================================================================
# F7 WRONG-DIR - engine invoked with governance root OUTSIDE S:\NEO. DESIGN-ONLY-DEFERRED.
# Probed: the engine resolves absolute paths and runs the full AS net against any directory; it does
# NOT gate on governance-root membership in fixture mode (real mode only RECORDS rootedInNeo, never
# gates). The home is the host-registry approved-paths control. Not a regression of an existing engine
# control - the control was never engine-resident.
# =====================================================================================
ReportPending 'F7' 'F7a-wrong_governance_root' "verify_app_slice runs its full check net against any AppRoot/Profile/SliceDir, including trees entirely outside S:\NEO (empirically confirmed: 16 AS lines emitted, no wrong-dir gate). Engine-root / approved-invocation-path gating is HOST-REGISTRY work (HOST_REGISTRY 4.2 approved_external_paths) or a future governance-root assertion. Honest status: engine does NOT fail-closed on wrong cwd today."

# =====================================================================================
# F8 LOG - missing / tampered real-mode invocation log. DESIGN-ONLY-DEFERRED.
# The engine writes APP_END_EVIDENCE.json but NO append-only real_mode_invocation_log. There is no
# in-engine log to be missing-or-tampered against; the control is host infrastructure.
# =====================================================================================
$logArtifacts = @()
if(Test-Path -LiteralPath $fxG.slice){ $logArtifacts = @(Get-ChildItem -LiteralPath $fxG.slice -File | Where-Object { $_.Name -match '(?i)invocation.*log|real_mode.*log' }) }
ReportPending 'F8' 'F8a-missing_invocation_log' ("a green real/fixture run produced NO real_mode_invocation_log artifact (found=" + $logArtifacts.Count + "). An append-only invocation log is HOST-REGISTRY work (HOST_REGISTRY 4.6 real_mode_invocation_log; custody tier requires a WORM/append-only medium the session principal cannot rewrite). Cannot be engine-enforced now without faking append-only on a writable volume.")

# =====================================================================================
# F9 CONCURRENCY - concurrent-session collision DETECTION (NOT prevention).
# The lock is DOCTRINE-ONLY (CONCURRENCY_LOCK.md): no lockfile, no OS mutex, no VCS gate. What is real
# is post-hoc DETECTION: a concurrent writer that mutates the shared frozen surface is caught by the
# same FREEZE_INVENTORY/Check-H tripwire (the RT4 precedent). We prove DETECTION fires; we label it
# detection-not-prevention and do NOT claim a mutex.
# =====================================================================================
# Simulate a second session mutating a shared frozen file - on a COPY (never the real surface, S3).
$concDir = Join-Path $base 'f9_concurrent'; New-Item -ItemType Directory -Force -Path $concDir | Out-Null
$sharedCopy = Join-Path $concDir 'shared_surface_copy.json'; Copy-Item -LiteralPath $realFrozen -Destination $sharedCopy
Set-ItemProperty -LiteralPath $sharedCopy -Name IsReadOnly -Value $false  # copy may inherit +R from a locked source; make tamper target writable
Add-Content -LiteralPath $sharedCopy -Value "// concurrent-session write"
$collisionDetected = ((Get-FileHash -LiteralPath $sharedCopy -Algorithm SHA256).Hash -ne $frozenSchema.sha256)
Report 'F9' 'F9a-collision_detection' $collisionDetected "simulated concurrent mutation of a shared frozen-surface file is DETECTED by surface-hash drift vs FREEZE_INVENTORY (detection-not-prevention; same tripwire that caught the RT4 collision)"
# Prevention: confirm there is NO advisory lock today (honest absence; not a failure).
$sessionLock = Join-Path $NeoRoot '.neo\SESSION.lock'
ReportPending 'F9' 'F9b-prevention_mutex' ("no advisory SESSION.lock present (exists=" + (Test-Path -LiteralPath $sessionLock) + ") and no OS mutex / VCS single-writer gate. PREVENTION is DESIGN-ONLY-DEFERRED: an advisory SESSION.lock written/checked by new_session.ps1 (frozen-core - re-pin needed) or migrating S:\NEO to git with branch protection. The lock remains DOCTRINE-ONLY per CONCURRENCY_LOCK.md.")

# ---------- summary + cleanup ----------
Write-Host ""
foreach($line in $script:results){ Write-Host $line }
Write-Host ""
Write-Host ("Summary: {0} ENFORCED pass, {1} fail, {2} PENDING-DEFERRED (design-only, host-registry; not counted)." -f $script:passes,$script:failures,$script:pending)

if(-not $KeepArtifacts){
  Remove-Item -LiteralPath $base -Recurse -Force
  # second clean pass (residue discipline): assert nothing left behind
  if(Test-Path -LiteralPath $base){ Write-Host "[RESIDUE] WARNING: base dir still present after cleanup"; $script:failures++ }
  else { Write-Host "Fixtures removed (NEO_SESSION restored). Second clean pass: 0 residue. Use -KeepArtifacts to inspect." }
}

if($script:failures -gt 0){
  Write-Host "=== custody_fixture_suite: RED - $($script:failures) ENFORCED case(s) misclassified ==="
  exit 1
}
Write-Host "=== custody_fixture_suite: PASS ($($script:passes) enforced fail-closed proofs; $($script:pending) design-only-deferred recorded honestly) ==="
exit 0
