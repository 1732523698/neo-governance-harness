# authorization_fixture_suite.ps1 - NEO 3.1 P1-S4 (RT4-R1 / section 4.7 gate binding) fixture proof.
# ASCII-only, PowerShell 5.1.
#
# Proves the AS4 PASS-WITH-AUTH relaxation FAILS CLOSED and the AS15 invariant_preserved mode. Builds a
# self-contained fixture app + a FIXTURE-LOCAL app profile + a FIXTURE-LOCAL human-gate ledger (never the
# real .neo/gates ledger), then:
#   POSITIVE  properly-bound UNLOCK_RECORD + matching re-pin + correct class + passing invariant test
#             -> verify exit 0 AND AS4 = PASS-WITH-AUTH AND checker exit 0 (E1/E5/E7 accept the new status)
#   P1 no UNLOCK_RECORD                                  -> AS4 FAIL (unauthorized touch)
#   P2 gate_ref NOT in the human ledger                  -> AS4 FAIL (the self-unlock-backdoor test)
#   P3 ledger authorized_by is a ROLE (NEO_BUILDER)      -> AS4 FAIL (builder-self-issued -> NO PASS)
#   P4 expected_post_sha != on-disk re-pin               -> AS4 FAIL
#   P5 authorization artifact_class != S3 class map      -> AS4 FAIL
#   P6 a second denylisted path touched, not authorized  -> AS4 FAIL (scope guard)
#   P7 malformed UNLOCK_RECORD.json                      -> AS4 FAIL (fail closed)
#   P8 record binding.root_of_trust='host-anchored' vs a 'provisional-dev' ledger (P1-S5 labeling-integrity
#      cross-check)                                       -> AS4 FAIL (a record cannot claim a stronger trust
#      tier than the ledger declares; host-anchored-vs-provisional-dev is fail-closed)
#   INV-NEG invariant_preserved check, prose 'PASS' only -> AS15 FAIL (a bare prose PASS cannot satisfy)
#
# A suite proven only on a happy fixture is not proven. Exit 0 only when ALL cases classify.

param([switch]$KeepArtifacts,[string]$NeoRoot)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$scripts = Join-Path $NeoRoot '.neo\scripts'
$verify  = Join-Path $scripts 'verify_app_slice.ps1'
$checker = Join-Path $scripts 'check_app_end_evidence.ps1'
$base    = Join-Path $NeoRoot 'NEO_SESSION\authz_fixture'
$script:failures = 0
$script:results = New-Object System.Collections.ArrayList

function Report([string]$case,[bool]$ok,[string]$detail){
  $tag = if($ok){'PASS'}else{'FAIL'}
  [void]$script:results.Add(("[{0}] {1,-22} {2}" -f $tag,$case,$detail))
  if(-not $ok){ $script:failures++ }
}
function Get-AsciiSha([string]$s){
  $tmp = [System.IO.Path]::GetTempFileName()
  [System.IO.File]::WriteAllText($tmp, $s, [System.Text.Encoding]::ASCII)
  $h = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
  Remove-Item -LiteralPath $tmp -Force
  return $h
}
function Write-Json($obj,[string]$path){ ($obj | ConvertTo-Json -Depth 8) | Out-File -LiteralPath $path -Encoding ascii }

# Build the fully-VALID (positive) fixture; callers then mutate exactly one artifact per negative.
function New-AuthzFixture([string]$name){
  $root  = Join-Path $base $name
  $app   = Join-Path $root 'app'
  $slice = Join-Path $root 'slice'
  foreach($d in @("$app\src\core", $slice)){ New-Item -ItemType Directory -Force -Path $d | Out-Null }

  $prior = "export const INVARIANT = 42;`r`nexport const helper = () => INVARIANT;`r`n"
  $post  = $prior + "export const addedFeature = () => INVARIANT + 1;`r`n"   # additive; INVARIANT unchanged
  $priorSha = Get-AsciiSha $prior
  $lockedFull = "$app\src\core\locked_invariant.ts"
  [System.IO.File]::WriteAllText($lockedFull, $post, [System.Text.Encoding]::ASCII)   # disk = post-edit
  $postSha = (Get-FileHash -LiteralPath $lockedFull -Algorithm SHA256).Hash.ToLower()

  # slice
  Set-Content -LiteralPath "$slice\CHANGED_FILES.txt" -Value "src/core/locked_invariant.ts" -Encoding ascii
  Set-Content -LiteralPath "$slice\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT3`r`nFAST_LANE: no" -Encoding ascii
  Set-Content -LiteralPath "$slice\invariant_test.log" -Value "invariant test: INVARIANT===42 preserved; exit 0 (fixture artifact)" -Encoding ascii
  $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  $cmdEv = @( @{ name='locked_invariant_preserved'; cmd='node test/invariant.js'; cwd='.'; exit_code=0; timestamp=$ts; output_path='invariant_test.log'; status='pass' } )
  Write-Json $cmdEv "$slice\command_evidence.json"

  # fixture-local profile (its own app_slug + denylist w/ recorded_sha + invariant_preserved custom check)
  $profile = [ordered]@{
    binding = [ordered]@{ profile_schema_id='neo:app_profile'; generated_view_is_authoritative=$false }
    identity = [ordered]@{ app_slug='authz-fixture-app'; app_name='Authorization Fixture App' }
    boundary_approval = [ordered]@{ boundary_approved=$false }
    denylist = [ordered]@{ entries=@(
      [ordered]@{ pattern='src/core/locked_invariant.ts'; is_glob=$false; recorded_sha=$priorSha; note='fixture locked file' },
      [ordered]@{ pattern='src/core/locked_second.ts'; is_glob=$false; note='second locked file (for scope-guard P6)' }
    ) }
    residue_tokens = @()
    charset = [ordered]@{ ascii_globs=@() }
    migrations = [ordered]@{ migrations_dir=$null }
    dependencies = [ordered]@{ dep_files=@() }
    risk_tokens = [ordered]@{ auth_tokens=@(); fin_tokens=@() }
    commands = [ordered]@{ named=@() }
    custom_checks = @( [ordered]@{ id='locked_invariant_preserved'; mode='invariant_preserved'; invariant='exported INVARIANT constant unchanged'; test_id='locked_invariant_preserved'; requires_additive_diff=$true } )
    scoped_deny_imports = @()
  }
  $profilePath = "$root\NEO_APP_PROFILE.json"
  Write-Json $profile $profilePath

  # fixture-local human-gate ledger (a VALID human end-keep gate)
  $ledger = [ordered]@{
    human_gate_ledger_schema_id='neo:human_gate_ledger'
    root_of_trust='provisional-dev'
    note='FIXTURE self-test ledger (never the real .neo/gates ledger)'
    entries=@( [ordered]@{ gate_ref='2026-07-01-P1-S4-FIXTURE-SELFTEST'; gate_kind='human_end_keep'; authorized_by='Raphael'; recorded_at='2026-07-01'; app_slug='authz-fixture-app'; authorized_paths=@('src/core/locked_invariant.ts'); decision_log_ref='fixture'; note='self-test authorization' } )
  }
  $ledgerPath = "$root\HUMAN_GATE_LEDGER.json"
  Write-Json $ledger $ledgerPath

  # valid UNLOCK_RECORD in the slice
  $rec = [ordered]@{
    unlock_record_schema_id='neo:unlock_record'
    gate_ref='2026-07-01-P1-S4-FIXTURE-SELFTEST'
    authorized_by='Raphael'
    issued_by_gate='human_end_keep'
    app_slug='authz-fixture-app'
    invariant_test_id='locked_invariant_preserved'
    authorizations=@( [ordered]@{ path='src/core/locked_invariant.ts'; artifact_class='implementation'; expected_prior_sha=$priorSha; expected_post_sha=$postSha } )
    binding=[ordered]@{ root_of_trust='provisional-dev'; prod_gate='RT4-R1 PASS-WITH-AUTH is NOT trusted in PROD until section 4.9 (S5) anchors the ledger + Option A (S6) ACLs it.' }
  }
  $recPath = "$slice\UNLOCK_RECORD.json"
  Write-Json $rec $recPath

  return @{ root=$root; app=$app; slice=$slice; profile=$profilePath; ledger=$ledgerPath; rec=$recPath; locked=$lockedFull; priorSha=$priorSha; postSha=$postSha }
}

function Run-Verify($fx){
  $ev = Join-Path $fx.root 'APP_END_EVIDENCE.json'
  $out = (& $verify -AppRoot $fx.app -Profile $fx.profile -SliceDir $fx.slice -EvidenceOut $ev -Mode fixture -HumanGateLedger $fx.ledger *>&1 | Out-String)
  return @{ code=$LASTEXITCODE; out=$out; ev=$ev }
}
function Expect-Fail([string]$case,$fx,[string]$checkId){
  $r = Run-Verify $fx
  $hit = $r.out -match ('\[' + $checkId + '\s*\]\s*FAIL')
  Report $case (($r.code -eq 1) -and $hit) "expect exit1 + $checkId FAIL; got exit=$($r.code), ${checkId}FailSeen=$hit"
}

if(Test-Path -LiteralPath $base){ Remove-Item -LiteralPath $base -Recurse -Force }
New-Item -ItemType Directory -Force -Path $base | Out-Null
Write-Host "=== authorization_fixture_suite (P1-S4 RT4-R1) NeoRoot=$NeoRoot ==="

# ---------- POSITIVE ----------
$fx = New-AuthzFixture 'positive'
$r = Run-Verify $fx
$auth = $r.out -match '\[AS4\s*\]\s*PASS-WITH-AUTH'
Report 'POSITIVE-verify' (($r.code -eq 0) -and $auth) "expect exit0 + AS4 PASS-WITH-AUTH; got exit=$($r.code), authSeen=$auth"
if($r.code -eq 0){
  $c = (& $checker -Evidence $r.ev -Profile $fx.profile -SliceDir $fx.slice *>&1 | Out-String)
  Report 'POSITIVE-checker' ($LASTEXITCODE -eq 0) "expect checker exit0 (E1/E5/E7 accept new status/key); got $LASTEXITCODE"
} else { Report 'POSITIVE-checker' $false 'skipped: positive verify did not pass'; Write-Host $r.out }

# ---------- P1 no UNLOCK_RECORD ----------
$fx = New-AuthzFixture 'p1_norecord'
Remove-Item -LiteralPath $fx.rec -Force
Expect-Fail 'P1-no_record' $fx 'AS4'

# ---------- P2 gate_ref not in the human ledger (self-unlock backdoor) ----------
$fx = New-AuthzFixture 'p2_gate_unbound'
$rec = Get-Content -LiteralPath $fx.rec -Raw | ConvertFrom-Json
$rec.gate_ref = 'FORGED-GATE-NOT-IN-LEDGER'
Write-Json $rec $fx.rec
Expect-Fail 'P2-gate_not_bound' $fx 'AS4'

# ---------- P3 ledger authority is a ROLE (builder-self-issued) ----------
$fx = New-AuthzFixture 'p3_self_issued'
$led = Get-Content -LiteralPath $fx.ledger -Raw | ConvertFrom-Json
$led.entries[0].authorized_by = 'NEO_BUILDER'
$rec = Get-Content -LiteralPath $fx.rec -Raw | ConvertFrom-Json
$rec.authorized_by = 'NEO_BUILDER'   # keep record<->ledger consistent so the ROLE check is what bites
Write-Json $led $fx.ledger
Write-Json $rec $fx.rec
Expect-Fail 'P3-self_issued_role' $fx 'AS4'

# ---------- P4 expected_post_sha mismatch ----------
$fx = New-AuthzFixture 'p4_sha_mismatch'
$rec = Get-Content -LiteralPath $fx.rec -Raw | ConvertFrom-Json
$rec.authorizations[0].expected_post_sha = ('0' * 64)
Write-Json $rec $fx.rec
Expect-Fail 'P4-post_sha_mismatch' $fx 'AS4'

# ---------- P5 wrong artifact_class ----------
$fx = New-AuthzFixture 'p5_wrong_class'
$rec = Get-Content -LiteralPath $fx.rec -Raw | ConvertFrom-Json
$rec.authorizations[0].artifact_class = 'constraint'   # class map resolves the path to 'implementation'
Write-Json $rec $fx.rec
Expect-Fail 'P5-wrong_class' $fx 'AS4'

# ---------- P6 second denylisted path touched but not authorized (scope guard) ----------
$fx = New-AuthzFixture 'p6_scope'
Set-Content -LiteralPath "$($fx.app)\src\core\locked_second.ts" -Value "export const SECOND = 1;`r`n" -Encoding ascii
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "src/core/locked_second.ts"
Expect-Fail 'P6-uncovered_path' $fx 'AS4'

# ---------- P7 malformed UNLOCK_RECORD ----------
$fx = New-AuthzFixture 'p7_malformed'
Set-Content -LiteralPath $fx.rec -Value '{ this is not json' -Encoding ascii
Expect-Fail 'P7-malformed_record' $fx 'AS4'

# ---------- P8 host-anchored-labeled record vs a provisional-dev ledger (P1-S5 labeling-integrity cross-check) ----------
# The positive fixture ledger is root_of_trust='provisional-dev'; here the RECORD claims binding.root_of_trust=
# 'host-anchored'. The ADD-only AS4 cross-check (rec.binding.root_of_trust MUST EQUAL ledger.root_of_trust) must
# reject it fail-closed: a dev record cannot self-declare the ledger host-anchored past its own custody label.
$fx = New-AuthzFixture 'p8_rot_mismatch'
$rec = Get-Content -LiteralPath $fx.rec -Raw | ConvertFrom-Json
$rec.binding.root_of_trust = 'host-anchored'
Write-Json $rec $fx.rec
Expect-Fail 'P8-rot_label_mismatch' $fx 'AS4'

# ---------- INV-NEG invariant_preserved satisfied by prose only (no deny touch; isolates AS15) ----------
$fx = New-AuthzFixture 'invneg'
# retarget the slice to a NON-locked file so AS4 passes and AS15 is the sole gate
New-Item -ItemType Directory -Force -Path "$($fx.app)\src\feature" | Out-Null
Set-Content -LiteralPath "$($fx.app)\src\feature\thing.ts" -Value "export const t = 1;`r`n" -Encoding ascii
Set-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "src/feature/thing.ts" -Encoding ascii
Remove-Item -LiteralPath $fx.rec -Force                                   # no deny touch -> no record needed
Remove-Item -LiteralPath "$($fx.slice)\command_evidence.json" -Force      # remove the passing invariant test
Set-Content -LiteralPath "$($fx.slice)\CUSTOM_CHECKS.md" -Value "locked_invariant_preserved: PASS (prose only - must NOT satisfy invariant_preserved)" -Encoding ascii
$r = Run-Verify $fx
$as15 = $r.out -match '\[AS15\s*\]\s*FAIL'
$as4pass = $r.out -match '\[AS4\s*\]\s*PASS\b'
Report 'INVNEG-prose_insufficient' (($r.code -eq 1) -and $as15 -and $as4pass) "expect exit1 + AS15 FAIL + AS4 PASS(no deny touch); got exit=$($r.code), AS15Fail=$as15, AS4pass=$as4pass"

# ---------- summary + cleanup ----------
Write-Host ""
foreach($line in $script:results){ Write-Host $line }
Write-Host ""
if(-not $KeepArtifacts){ Remove-Item -LiteralPath $base -Recurse -Force; Write-Host "Fixtures removed. Use -KeepArtifacts to inspect." }
if($script:failures -gt 0){ Write-Host "=== authorization_fixture_suite: RED - $($script:failures) case(s) misclassified ==="; exit 1 }
Write-Host "=== authorization_fixture_suite: PASS (POSITIVE + checker + 8 fail-closed negatives + invariant-mode negative all classify) ==="
exit 0
