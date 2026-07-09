# orch_clarity_suite.ps1 - NEO 4.0-P4-AUTONOMY C5 clarity/freeze/plan-audit fixture
# suite. ASCII-only (D10). Proves orch_clarity.ps1 fails closed on every dispatch-3.D
# fixture + the START-release notes R-1 (on-disk bundle re-hash authority) and R-2
# (exhaustive non-{GO,NO_GO} disclosure trigger).
#
# STRUCTURALLY INCAPABLE OF A REAL CODEX CALL (C4/notify precedent):
#   (1) the live invoker Invoke-NeoExternalCodex is TRIPWIRED for the WHOLE run -
#       any path reaching it throws + increments a counter asserted ZERO at the end;
#   (2) every plan-audit call goes through ONE helper (Invoke-PlanAuditFix) that
#       ALWAYS injects a stub -InvokerSeam + fixture attestation/credential twins;
#   (3) notify runs ONLY in compose-to-disk TestModeDir mode - the string needle
#       check proves no live-send flag exists anywhere in this file.
#
# LOAD-BEARING GUARDS (neuter-flip discipline): every negative family has a positive
# twin through the SAME code path; the MANDATORY addendum fixture additionally
# neuter-flips the readiness disclosure guard on a SCRATCH COPY of the module and
# proves FAIL-OPEN, then restores the real module and proves BLOCKED again.
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'
$orchDir = Split-Path -Parent $PSScriptRoot
. "$orchDir\orch_clarity.ps1"     # sources orch_external + orch_govmanifest + orch_engine + orch_router + notify
. "$orchDir\orch_loop.ps1"        # FROZEN reuse: Assert-NeoLoopRunSliceUniverse + Add-NeoIterationManifestEntry (completeness carry)

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_clarity_c5_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors the external/govmanifest suite framing) -------------
$script:results = @()
function Record($name, $pass, $detail, $kind = 'negative') {
  $script:results += [pscustomobject]@{ guard = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  $ktag = if ($kind -eq 'negative') { 'GUARD' } elseif ($kind -eq 'skip') { 'SKIP ' } else { 'info ' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $ktag, $name, $detail) -ForegroundColor $col
}
function Expect-Block($name, $codeSubstr, $sb) {
  try { & $sb; Record $name $false 'NO BLOCK (guard did not fire)' 'negative' }
  catch {
    $m = $_.Exception.Message
    if ($m -like 'NEO-BLOCK:*') {
      if ($codeSubstr -and ($m -notlike "*$codeSubstr*")) {
        Record $name $false ("BLOCK but wrong reason (want $codeSubstr): " + $m) 'negative'
      } else { Record $name $true $m 'negative' }
    } else { Record $name $false ('threw non-BLOCK: ' + $m) 'negative' }
  }
}
function Expect-Ok($name, $sb) {
  try { $r = & $sb; Record $name $true "$r" 'positive' }
  catch { Record $name $false ('unexpected block/error: ' + $_.Exception.Message) 'positive' }
}
function Expect-Value($name, $want, $sb) {
  try { $r = & $sb
    if ("$r" -eq "$want") { Record $name $true "= $r" 'positive' }
    else { Record $name $false ("got '$r' want '$want'") 'positive' }
  } catch { Record $name $false ('unexpected error: ' + $_.Exception.Message) 'positive' }
}

# ---- STRUCTURAL TRIPWIRE: the live invoker is unreachable for this whole run ------
$script:liveTrip = 0
${function:Invoke-NeoExternalCodex} = { param($PacketDir, $OutFile, $TimeoutSec) $script:liveTrip++; throw 'TRIPWIRE: live codex invoker reached (structurally forbidden in this suite)' }

# ---- shared fixture plumbing -------------------------------------------------------
$TS = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$index = Get-NeoRunSchemaIndex
$capsDefault = @{ max_fix_rounds_per_slice = 3; max_external_calls = 25; max_wall_clock_hours = 4; max_spend = 100 }
$script:seq = 0
function New-RunRoot([hashtable]$caps = $null) {
  $script:seq++
  if ($null -eq $caps) { $caps = $capsDefault }
  $r = Join-Path $ScratchRoot ("run{0}" -f $script:seq)
  New-Item -ItemType Directory -Force -Path $r | Out-Null
  [void](New-NeoRunManifest -RunRoot $r -Caps $caps -Timestamp $TS)
  return $r
}
function Get-RunId([string]$runRoot) { return [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runRoot) 'run_id') }

# fixture attestation + credential twins (NEVER the live files; C4 precedent).
$attOk = Join-Path $ScratchRoot 'att_ok.md'
Set-Content -LiteralPath $attOk -Value @('# fixture attestation twin', 'STATUS: **APPROVED / IN FORCE (fixture)**') -Encoding Ascii
$credOk = Join-Path $ScratchRoot 'auth_fixture.json'
Set-Content -LiteralPath $credOk -Value '{}' -Encoding Ascii

# live-map/live-schema sources for mirrors (the oracle under test is the LIVE map).
$repoRoot = Resolve-NeoRoot $orchDir
$liveMap = Join-Path $repoRoot '.neo\schema\artifact_classes.json'
$liveGovSchema = Join-Path $repoRoot '.neo\schema\governance_manifest.schema.json'

# governed-root mirror: the FULL 26-rel mandatory floor (the govmanifest-suite
# pattern) so New-NeoClarityGovManifestPin's V1 floor assert passes; negative
# starved cases remove ONE member after building.
$script:mirrorSeq = 0
function New-GovMirror([switch]$StarveClarity) {
  $script:mirrorSeq++
  $root = Join-Path $ScratchRoot ("gov{0}" -f $script:mirrorSeq)
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\schema') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\scripts\orchestrator\harness') | Out-Null
  foreach ($sk in @('NEO_DIRECTOR', 'NEO_BUILDER', 'NEO_AUDITOR')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root ".claude\skills\$sk") | Out-Null
    Set-Content -LiteralPath (Join-Path $root ".claude\skills\$sk\SKILL.md") -Value "# $sk role" -Encoding Ascii
  }
  Copy-Item -LiteralPath $liveMap -Destination (Join-Path $root '.neo\schema\artifact_classes.json') -Force
  Copy-Item -LiteralPath $liveGovSchema -Destination (Join-Path $root '.neo\schema\governance_manifest.schema.json') -Force
  foreach ($orch in @(
      'orch_auditor_stub.ps1', 'orch_clarity.ps1', 'orch_class.ps1', 'orch_diff.ps1', 'orch_enforce.ps1',
      'orch_engine.ps1', 'orch_external.ps1', 'orch_govmanifest.ps1', 'orch_io.ps1', 'orch_loop.ps1',
      'orch_rollover.ps1', 'orch_run.ps1', 'orch_router.ps1', 'orch_schema.ps1', 'orch_supervisor.ps1', 'orchestrator.ps1')) {
    Set-Content -LiteralPath (Join-Path $root ".neo\scripts\orchestrator\$orch") -Value "# $orch" -Encoding Ascii
  }
  Set-Content -LiteralPath (Join-Path $root '.neo\scripts\_neo_root.ps1')        -Value '# _neo_root'        -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\scripts\verify_app_slice.ps1') -Value '# verify_app_slice' -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\NEO_RISK_TIERS.md')            -Value '# risk tiers'       -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\schema\run_manifest.schema.json')          -Value '{"a":1}' -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\schema\attempt_ledger_entry.schema.json')  -Value '{"a":1}' -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\schema\spawn_ledger_entry.schema.json')    -Value '{"a":1}' -Encoding Ascii
  if ($StarveClarity) {
    Remove-Item -LiteralPath (Join-Path $root '.neo\scripts\orchestrator\orch_clarity.ps1') -Force
  }
  return $root
}
# app-root mirror: its own classmap + gov schema (Build-NeoGovManifest works on any
# root carrying them), the app profile (profile_risk by glob - the probed seam), and
# a risk register file (pinned by EXPLICIT hash; no judging glob exists for it).
$script:appSeq = 0
function New-AppMirror([switch]$NoProfile, [switch]$NoRegister) {
  $script:appSeq++
  $root = Join-Path $ScratchRoot ("app{0}" -f $script:appSeq)
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\schema') | Out-Null
  Copy-Item -LiteralPath $liveMap -Destination (Join-Path $root '.neo\schema\artifact_classes.json') -Force
  Copy-Item -LiteralPath $liveGovSchema -Destination (Join-Path $root '.neo\schema\governance_manifest.schema.json') -Force
  if (-not $NoProfile) {
    Set-Content -LiteralPath (Join-Path $root 'NEO_APP_PROFILE.json') -Value '{"fixture":"app profile"}' -Encoding Ascii
  }
  if (-not $NoRegister) {
    Set-Content -LiteralPath (Join-Path $root 'risk_register.json') -Value '{"fixture":"risk register"}' -Encoding Ascii
  }
  return $root
}
$script:worldSeq = 0
function New-World([switch]$StarveGovClarity, [switch]$NoAppProfile, [switch]$NoAppRegister) {
  $script:worldSeq++
  $session = Join-Path $ScratchRoot ("session{0}" -f $script:worldSeq)
  New-Item -ItemType Directory -Force -Path $session | Out-Null
  $notify = Join-Path $ScratchRoot ("notify{0}" -f $script:worldSeq)
  New-Item -ItemType Directory -Force -Path $notify | Out-Null
  return @{
    run = (New-RunRoot); session = $session; notify = $notify
    gov = (New-GovMirror -StarveClarity:$StarveGovClarity)
    app = (New-AppMirror -NoProfile:$NoAppProfile -NoRegister:$NoAppRegister)
  }
}

# ---- default freeze inputs (fresh copies per call - no cross-fixture mutation) -----
function New-DefSlices {
  return @(
    @{ slice_id = 'sA'; approved_paths = @('./app/'); protected_paths = @('./.neo/')
       acceptance_harness_paths = @('harness/sA_fixture_suite.ps1'); risk_row_ref = 'r1' },
    @{ slice_id = 'sB'; approved_paths = @('./app/'); protected_paths = @('./.neo/')
       acceptance_harness_paths = @('harness/sB_fixture_suite.ps1'); risk_row_ref = 'r1' }
  )
}
# ,@(...) keeps the SINGLE-ELEMENT arrays WHOLE through the function-return
# pipeline (a bare @(one) return unrolls to the bare hashtable and the list
# validators correctly refuse it - the engine family's assignment convention).
function New-DefRows { return ,@( @{ row_id = 'r1'; risk_class = 'low' } ) }
function New-DefProfile {
  return @{
    denylist = @{ entries = @( @{ pattern = '.neo/**'; is_glob = $true } ) }
    risk_tokens = @{ auth_tokens = @('auth'); fin_tokens = @('payment') }
  }
}
function New-DefRegister {
  return ,@( @{ item_id = 'amb-1'; surface = 'presentation wording'; classification = 'documented_default'
                documented_default = 'plain ASCII output' } )
}
function New-FreezeArgs($w, [hashtable]$over = @{}) {
  $a = @{
    RunRoot = $w.run; SessionRoot = $w.session
    InstructionDigestRef = ('fixture-instruction#sha256:' + ('a' * 64))
    AmbiguityRegister = (New-DefRegister); SlicePlan = (New-DefSlices); RiskRows = (New-DefRows)
    Profile = (New-DefProfile); AttestedGapRecords = @()
    GovernedRoot = $w.gov; AppRoot = $w.app; RiskRegisterRel = 'risk_register.json'
    StampedBy = 'fixture-supervisor'; Timestamp = $TS; Index = $index
  }
  foreach ($k in @($over.Keys)) { $a[$k] = $over[$k] }
  return $a
}
function Invoke-FreezeFix($w, [hashtable]$over = @{}) {
  $a = New-FreezeArgs $w $over
  return (New-NeoClarityFreezeRecord @a)
}

# ---- counting stub seams + the faithful codex CLI output builder (C4 pattern) ------
$global:NeoClaritySeamCalls = 0
function New-StubSeam([string[]]$OutLines, [bool]$Ok = $true, [string]$Detail = 'stub', [bool]$Throw = $false, [bool]$WriteNothing = $false) {
  $cfg = @{ lines = $OutLines; ok = $Ok; detail = $Detail; thr = $Throw; skip = $WriteNothing }
  return {
    param($io)
    $global:NeoClaritySeamCalls++
    if ($cfg.thr) { throw 'stub invoker exploded (fixture)' }
    if (-not $cfg.skip) { Set-Content -LiteralPath $io.out_file -Value $cfg.lines -Encoding Ascii }
    return @{ ok = $cfg.ok; class = $(if ($cfg.ok) { 'OK' } else { 'CLI_ERROR' }); detail = $cfg.detail }
  }.GetNewClosure()
}
function New-CodexOutput([string]$HeaderModel, [string[]]$BodyLines) {
  $hdr = @('OpenAI Codex v0.142.5', '--------', 'workdir: C:\fixture\packet')
  if ($null -ne $HeaderModel) { $hdr += ('model: ' + $HeaderModel) }
  $hdr += @('provider: openai', 'approval: never', 'sandbox: read-only', 'session id: fixture-0000', '--------')
  $lead = @('user', 'Perform the plan audit per the packet.', 'codex', 'Reading the packet.', 'exec', 'bash -lc "cat packet.txt"', 'exec succeeded')
  $final = @('codex') + $BodyLines
  $tail = @('tokens used', '12,345') + $BodyLines
  return @($hdr + $lead + $final + $tail)
}
$stubGo       = New-StubSeam (New-CodexOutput 'gpt-5.5' @('VERDICT: GO', 'FINDINGS: plan fixture clean'))
$stubNoGo     = New-StubSeam (New-CodexOutput 'gpt-5.5' @('VERDICT: NO-GO', 'FINDINGS: plan fixture defect'))
$stubExitFail = New-StubSeam (New-CodexOutput 'gpt-5.5' @('VERDICT: GO')) -Ok $false -Detail 'nonzero exit code 2 (fixture)'

# THE ONE plan-audit entry point for this suite (STRUCTURAL-SINGLE-PLAN-AUDIT-HELPER
# pins this): ALWAYS a stub seam + fixture attestation/credential twins.
function Invoke-PlanAuditFix($w, $seam, [hashtable]$over = @{}) {
  $a = @{
    RunRoot = $w.run; SessionRoot = $w.session; StampedBy = 'fixture-supervisor'; Timestamp = $TS
    AttestationPath = $attOk; CredentialPath = $credOk; InvokerSeam = $seam; Index = $index
  }
  foreach ($k in @($over.Keys)) { $a[$k] = $over[$k] }
  return (Invoke-NeoClarityPlanAudit @a)
}
function Get-GateLedgerRecords($w) {
  # ASSIGN first: the frozen readers return ,@(...) (one stream object wrapping
  # the array); assignment unrolls the outer wrapper, then the plain return
  # enumerates elements so callers' @(...) collects a FLAT entry array.
  $e = Read-NeoClarityGateRecords -RunRoot $w.run -Index $index
  return @($e)
}

Write-Host ''
Write-Host '=== SECTION A: CLARITY CHECK (3.D.1-4) ===' -ForegroundColor Cyan

Expect-Value 'P-C5-REGISTER-EMPTY-CLEAR' 'CLEAR' {
  (Assert-NeoClarityAmbiguityRegister -Register @()).status
}
Expect-Block 'N-C5-REGISTER-NULL' 'CLARITY_REGISTER_UNREADABLE' {
  Assert-NeoClarityAmbiguityRegister -Register $null | Out-Null
}
Expect-Block 'N-C5-REGISTER-SCALAR' 'CLARITY_REGISTER_UNREADABLE' {
  Assert-NeoClarityAmbiguityRegister -Register 'not a register' | Out-Null
}
# MUST-ASK, one per blocking class: the check names the unresolved item AND the
# freeze refuses to proceed (3.D.1).
$wA = New-World
foreach ($pair in @(
    @('N-C5-MUSTASK-RISK-TIER', 'blocking_risk_tier'),
    @('N-C5-MUSTASK-STATE-SURFACES', 'blocking_state_surfaces'),
    @('N-C5-MUSTASK-GOV-CONTROLS', 'blocking_governance_controls'))) {
  $name = [string]$pair[0]; $cls = [string]$pair[1]
  Expect-Block $name 'CLARITY_MUST_ASK' {
    Invoke-FreezeFix $wA @{ AmbiguityRegister = @(
      @{ item_id = ('open-' + $cls); surface = 'fixture ambiguity'; classification = $cls }) } | Out-Null
  }
}
Expect-Value 'P-C5-MUSTASK-NAMES-QUESTIONS' 'MUST_ASK|open-q1' {
  $r = Assert-NeoClarityAmbiguityRegister -Register @(
    @{ item_id = 'open-q1'; surface = 'fixture'; classification = 'blocking_risk_tier' })
  ($r.status + '|' + (@($r.unresolved_blocking) -join ','))
}
Expect-Value 'P-C5-BLOCKING-RESOLVED-CLEAR' 'CLEAR' {
  (Assert-NeoClarityAmbiguityRegister -Register @(
    @{ item_id = 'amb-r'; surface = 'risk tier'; classification = 'blocking_risk_tier'
       resolution = 'LOW confirmed by Raphael'; resolved_by = 'Raphael'; resolved_date = '2026-07-07' })).status
}
Expect-Block 'N-C5-DEFAULT-MISSING' 'CLARITY_DEFAULT_MISSING' {
  Assert-NeoClarityAmbiguityRegister -Register @(
    @{ item_id = 'amb-d'; surface = 'wording'; classification = 'documented_default' }) | Out-Null
}
Expect-Block 'N-C5-UNCLASSIFIABLE-MISSING' 'CLARITY_UNCLASSIFIED_AMBIGUITY' {
  Assert-NeoClarityAmbiguityRegister -Register @(
    @{ item_id = 'amb-u'; surface = 'fixture' }) | Out-Null
}
Expect-Block 'N-C5-UNCLASSIFIABLE-CASE' 'CLARITY_UNCLASSIFIED_AMBIGUITY' {
  Assert-NeoClarityAmbiguityRegister -Register @(
    @{ item_id = 'amb-c'; surface = 'fixture'; classification = 'Blocking_Risk_Tier' }) | Out-Null
}
# C5-FIX SIBLING SWEEP (item_id): the unresolved_blocking list NAMES the gate's
# questions - a duplicate/case-variant item_id conflates two distinct open
# questions. SAME three-guard distinctness discipline. ordinal-dup:
Expect-Block 'N-C5-AMBIG-DUP-ITEMID' 'CLARITY_UNCLASSIFIED_AMBIGUITY' {
  Assert-NeoClarityAmbiguityRegister -Register @(
    @{ item_id = 'amb-x'; surface = 'w1'; classification = 'documented_default'; documented_default = 'd1' },
    @{ item_id = 'amb-x'; surface = 'w2'; classification = 'documented_default'; documented_default = 'd2' }) | Out-Null
}
# case-variant (OrdinalIgnoreCase) near-duplicate item_id => STOP (the F5 lesson).
Expect-Block 'N-C5-AMBIG-CASEVAR-ITEMID' 'CLARITY_UNCLASSIFIED_AMBIGUITY' {
  Assert-NeoClarityAmbiguityRegister -Register @(
    @{ item_id = 'AmbX'; surface = 'w1'; classification = 'documented_default'; documented_default = 'd1' },
    @{ item_id = 'ambx'; surface = 'w2'; classification = 'documented_default'; documented_default = 'd2' }) | Out-Null
}
# positive control: distinct item_ids (differing beyond case) still pass CLEAR.
Expect-Value 'P-C5-AMBIG-DISTINCT-ITEMIDS-CLEAR' 'CLEAR' {
  (Assert-NeoClarityAmbiguityRegister -Register @(
    @{ item_id = 'AmbX'; surface = 'w1'; classification = 'documented_default'; documented_default = 'd1' },
    @{ item_id = 'AmbY'; surface = 'w2'; classification = 'documented_default'; documented_default = 'd2' })).status
}

Write-Host ''
Write-Host '=== SECTION B: SLICE PLAN (3.D.12) ===' -ForegroundColor Cyan
$wB = New-World
Expect-Block 'N-C5-SLICE-EMPTY-PLAN' 'CLARITY_SLICE_PLAN' {
  Invoke-FreezeFix $wB @{ SlicePlan = @() } | Out-Null
}
Expect-Block 'N-C5-SLICE-DUP' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[1]['slice_id'] = 'sA'
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
# -ceq collision with ORDINAL distinctness needs a culture-colliding pair; build it
# at runtime (source stays ASCII): 'K' vs the Kelvin sign U+212A.
$kelvin = [string][char]0x212A
Expect-Value 'P-C5-CEQ-PAIR-WELLFORMED' 'True' {
  # ordinally distinct AND -ceq-colliding: exactly the class the guard refuses.
  [bool]((-not [System.String]::Equals('sK', ('s' + $kelvin), [System.StringComparison]::Ordinal)) -and ('sK' -ceq ('s' + $kelvin)))
}
Expect-Block 'N-C5-SLICE-CEQ-COLLIDE' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['slice_id'] = 'sK'; $sp[1]['slice_id'] = ('s' + $kelvin)
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
Expect-Block 'N-C5-SLICE-RESERVED-RUN' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['slice_id'] = '__run__'
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
Expect-Block 'N-C5-SLICE-RESERVED-PLAN' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['slice_id'] = '__plan__'
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
# C5-FIX: reserved-id refusals are now CASE-INSENSITIVE (OrdinalIgnoreCase) - a
# case-variant of a reserved id is REFUSED at freeze (the F5 lesson).
Expect-Block 'N-C5-SLICE-RESERVED-RUN-CASEVAR' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['slice_id'] = '__RUN__'
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
Expect-Block 'N-C5-SLICE-RESERVED-PLAN-CASEVAR' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['slice_id'] = '__PLAN__'
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
# C5-FIX: case-variant distinctness (OrdinalIgnoreCase set) - two ids equal
# case-insensitively but ordinally distinct are REFUSED at freeze.
Expect-Block 'N-C5-SLICE-CASEVAR-DUP' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['slice_id'] = 'SliceA'; $sp[1]['slice_id'] = 'slicea'
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
# positive control: distinct ids (differing beyond case) still PASS through the
# case-variant set unchanged - the new guard refuses only near-duplicates.
Expect-Ok 'P-C5-SLICE-DISTINCT-IDS-PASS' {
  $sp = New-DefSlices; $sp[0]['slice_id'] = 'SliceA'; $sp[1]['slice_id'] = 'SliceB'
  $rec = Invoke-FreezeFix $wB @{ SlicePlan = $sp }
  'plan_round=' + [string](Get-NeoProp $rec 'plan_round')
}
# C5-FIX NEUTER-FLIP (load-bearing proof): revert the NEW OrdinalIgnoreCase reserved
# comparison back to the OLD case-EXACT -ceq on a SCRATCH COPY => '__RUN__' must be
# ACCEPTED (fail-open), proving the case-insensitive guard is what blocks it; then
# the REAL module refuses it again. Run against the freeze-point validator directly.
$clarityPathB = Join-Path $orchDir 'orch_clarity.ps1'
$claritySrcB = [System.IO.File]::ReadAllText($clarityPathB)
$ciNeedle = "[string]::Equals([string]`$sid, [string]`$script:NeoRunExternalSliceId, [System.StringComparison]::OrdinalIgnoreCase)"
Expect-Value 'P-C5-SLICE-CI-NEUTER-TARGET-UNIQUE' 'True' {
  $first = $claritySrcB.IndexOf($ciNeedle)
  [bool](($first -ge 0) -and ($claritySrcB.IndexOf($ciNeedle, $first + 1) -lt 0))
}
$neuterPathB = Join-Path $ScratchRoot 'orch_clarity_CI_NEUTERED.ps1'
$neuteredB = $claritySrcB.Replace('$script:NeoClarityDir = $PSScriptRoot', ('$script:NeoClarityDir = ' + "'" + $orchDir + "'"))
$neuteredB = $neuteredB.Replace($ciNeedle, "([string]`$sid -ceq [string]`$script:NeoRunExternalSliceId)")
[System.IO.File]::WriteAllText($neuterPathB, $neuteredB, (New-Object System.Text.UTF8Encoding($false)))
. $neuterPathB
Expect-Value 'NEUTER-C5-SLICE-RESERVED-CI-FAILS-OPEN' 'True' {
  # neutered = case-EXACT: '__RUN__' no longer matches '__run__' => ACCEPTED (fail-open).
  $sp = New-DefSlices; $sp[0]['slice_id'] = '__RUN__'
  [bool](Assert-NeoClaritySlicePlan -SlicePlan $sp)
}
. $clarityPathB   # restore the REAL module (idempotent re-source)
Expect-Block 'P-C5-SLICE-RESERVED-CI-RESTORED' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['slice_id'] = '__RUN__'
  Assert-NeoClaritySlicePlan -SlicePlan $sp | Out-Null
}
Expect-Block 'N-C5-SLICE-NO-APPROVED' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['approved_paths'] = @()
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
Expect-Block 'N-C5-SLICE-PROTECTED-ABSENT' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0].Remove('protected_paths')
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
Expect-Block 'N-C5-SLICE-PROTECTED-EMPTY-UNDECLARED' 'CLARITY_SLICE_PLAN' {
  $sp = New-DefSlices; $sp[0]['protected_paths'] = @()
  Invoke-FreezeFix $wB @{ SlicePlan = $sp } | Out-Null
}
Expect-Ok 'P-C5-SLICE-PROTECTED-EMPTY-DECLARED' {
  $sp = New-DefSlices
  $sp[0]['protected_paths'] = @(); $sp[0]['protected_paths_declared_empty'] = $true
  $rec = Invoke-FreezeFix $wB @{ SlicePlan = $sp }
  'plan_round=' + [string](Get-NeoProp $rec 'plan_round')
}

Write-Host ''
Write-Host '=== SECTION C: RISK ROWS (3.D.5-6) ===' -ForegroundColor Cyan
$wC = New-World
Expect-Block 'N-C5-ROW-DOWNGRADE-NULLVAL' 'explicit_downgrade' {
  Invoke-FreezeFix $wC @{ RiskRows = @( @{ row_id = 'r1'; risk_class = 'low'; explicit_downgrade = $null } ) } | Out-Null
}
Expect-Block 'N-C5-ROW-DOWNGRADE-EMPTYARR' 'explicit_downgrade' {
  Invoke-FreezeFix $wC @{ RiskRows = @( @{ row_id = 'r1'; risk_class = 'low'; explicit_downgrade = @() } ) } | Out-Null
}
Expect-Block 'N-C5-ROW-UNKNOWN-CLASS' 'audit-tier' {
  Invoke-FreezeFix $wC @{ RiskRows = @( @{ row_id = 'r1'; risk_class = 'wat' } ) } | Out-Null
}
Expect-Block 'N-C5-ROW-BLANK-CLASS' 'audit-tier' {
  Invoke-FreezeFix $wC @{ RiskRows = @( @{ row_id = 'r1'; risk_class = '' } ) } | Out-Null
}
Expect-Block 'N-C5-ROW-REF-UNRESOLVED' 'CLARITY_ROW_MAPPING' {
  $sp = New-DefSlices; $sp[0]['risk_row_ref'] = 'rZ'
  Invoke-FreezeFix $wC @{ SlicePlan = $sp } | Out-Null
}
Expect-Value 'P-C5-MAPPING-RECORDED' '2' {
  $rec = Invoke-FreezeFix $wC
  @(Get-NeoClarityList $rec 'boundary_to_row_mapping').Count
}
# C5-FIX SIBLING SWEEP (row_id): the SAME three-guard discipline. ordinal-dup:
$rowsDup = @( @{ row_id = 'r1'; risk_class = 'low' }, @{ row_id = 'r1'; risk_class = 'low' } )
Expect-Block 'N-C5-ROW-DUP-ID' 'CLARITY_ROW_MAPPING' {
  Invoke-FreezeFix $wC @{ RiskRows = $rowsDup } | Out-Null
}
# case-variant (OrdinalIgnoreCase) near-duplicate row_id => STOP (the F5 lesson).
$rowsCase = @( @{ row_id = 'RowA'; risk_class = 'low' }, @{ row_id = 'rowa'; risk_class = 'low' } )
Expect-Block 'N-C5-ROW-CASEVAR-ID' 'CLARITY_ROW_MAPPING' {
  $sp = New-DefSlices; $sp[0]['risk_row_ref'] = 'RowA'; $sp[1]['risk_row_ref'] = 'RowA'
  Invoke-FreezeFix $wC @{ SlicePlan = $sp; RiskRows = $rowsCase } | Out-Null
}

Write-Host ''
Write-Host '=== SECTION D: C1a JUDGING REGISTRATIONS (3.D.13) ===' -ForegroundColor Cyan
$wD = New-World
Expect-Block 'N-C5-REGISTRATION-NON-JUDGING' 'CLARITY_REGISTRATION' {
  $sp = New-DefSlices; $sp[0]['acceptance_harness_paths'] = @('app/main.py')
  Invoke-FreezeFix $wD @{ SlicePlan = $sp } | Out-Null
}
Expect-Value 'P-C5-REGISTRATION-JUDGING-RESOLVED' 'test_harness,test_harness' {
  $rec = Invoke-FreezeFix $wD
  (@(Get-NeoClarityList $rec 'judging_registrations') | ForEach-Object { [string](Get-NeoProp $_ 'resolved_class') }) -join ','
}

Write-Host ''
Write-Host '=== SECTION E: PROFILE GATE / C6 COUPLING (3.D.14) ===' -ForegroundColor Cyan
$wE = New-World
Expect-Block 'N-C5-PROFILE-EMPTY-BOTH' 'router-profile' {
  Invoke-FreezeFix $wE @{ Profile = @{} } | Out-Null
}
Expect-Block 'N-C5-PROFILE-DENYLIST-GAP' 'router-profile' {
  $p = New-DefProfile; $p['denylist'] = @{ entries = @() }
  Invoke-FreezeFix $wE @{ Profile = $p } | Out-Null
}
Expect-Block 'N-C5-PROFILE-TOKENS-GAP' 'router-profile' {
  $p = New-DefProfile; $p['risk_tokens'] = @{ auth_tokens = @(); fin_tokens = @() }
  Invoke-FreezeFix $wE @{ Profile = $p } | Out-Null
}
Expect-Value 'P-C5-PROFILE-GAP-ATTESTED-ARCHIVED' '1' {
  $p = New-DefProfile; $p['denylist'] = @{ entries = @() }
  $rec = Invoke-FreezeFix $wE @{ Profile = $p; AttestedGapRecords = @(
    @{ gap = 'denylist'; attested_by = 'Raphael'; run_scope = 'fixture-run'; attested_date = '2026-07-07' }) }
  @(Get-NeoClarityList $rec 'attestation_records').Count
}

Write-Host ''
Write-Host '=== SECTION F: GOVERNANCE + APP PINS (3.D.15) ===' -ForegroundColor Cyan
$wF = New-World -StarveGovClarity
Expect-Block 'N-C5-GOVFLOOR-STARVED-CLARITY' 'MANDATORY_MEMBER_MISSING' {
  Invoke-FreezeFix $wF | Out-Null
}
$wF2 = New-World
$recF = Invoke-FreezeFix $wF2
Expect-Value 'P-C5-GOV-PIN-REVERIFIES' 'True' {
  $pinRel = [string](Get-NeoProp (Get-NeoProp $recF 'gov_manifest_pin') 'rel')
  $pinFull = Assert-NeoContained $wF2.session $pinRel
  $cur = Build-NeoGovManifest -GovernedRoot $wF2.gov -DerivedAt $TS
  [void](Assert-NeoGovManifestReverify -PinnedPath $pinFull -Current $cur -GovernedRoot $wF2.gov)
  $true
}
Expect-Value 'P-C5-RISKREG-PIN-MATCHES' 'True' {
  $pin = Get-NeoProp $recF 'risk_register_pin'
  ([string](Get-NeoProp $pin 'sha256')) -ceq (Get-NeoSha256File (Join-Path $wF2.app 'risk_register.json'))
}
$wF3 = New-World -NoAppProfile
Expect-Block 'N-C5-APP-PROFILE-MISSING' 'CLARITY_APP_PIN' {
  Invoke-FreezeFix $wF3 | Out-Null
}
$wF4 = New-World -NoAppRegister
Expect-Block 'N-C5-RISKREG-MISSING' 'CLARITY_APP_PIN' {
  Invoke-FreezeFix $wF4 | Out-Null
}

Write-Host ''
Write-Host '=== SECTION G: FREEZE IMMUTABILITY + TAMPER (3.D.11) ===' -ForegroundColor Cyan
$wG = New-World
[void](Invoke-FreezeFix $wG)
Expect-Value 'P-C5-FREEZE-REVISION-INCREMENTS' '2' {
  [string](Get-NeoProp (Invoke-FreezeFix $wG) 'plan_round')
}
# tamper: rewrite the FIRST ledger line's stamped_by, keeping the old record_sha256.
$fzPath = Resolve-NeoRunStatePath $wG.run 'clarity_freeze_ledger.jsonl'
$fzLines = @([System.IO.File]::ReadAllLines($fzPath))
$fzLines[0] = $fzLines[0].Replace('"stamped_by":"fixture-supervisor"', '"stamped_by":"tampered-actor"')
[System.IO.File]::WriteAllLines($fzPath, $fzLines)
Expect-Block 'N-C5-FREEZE-TAMPERED-READER' 'CLARITY_FREEZE_TAMPERED' {
  Read-NeoClarityFreezeRecords -RunRoot $wG.run -Index $index | Out-Null
}
Expect-Value 'N-C5-FREEZE-TAMPERED-READINESS-BLOCKED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wG.run -SessionRoot $wG.session -Index $index).state
}

Write-Host ''
Write-Host '=== SECTION H: PRE-START PLAN AUDIT + GATE (3.D.7-10 + R-1 + R-2) ===' -ForegroundColor Cyan
# ---- H-GO world: archived current-round GO verdict => gate surfaces ----------------
$wGo = New-World
[void](Invoke-FreezeFix $wGo)
$resGo = Invoke-PlanAuditFix $wGo $stubGo
Expect-Value 'P-C5-PLANAUDIT-GO-LANE' 'GO|False' { ([string]$resGo.lane + '|' + [string]$resGo.disclosure_written) }
Expect-Value 'P-C5-PLANAUDIT-VERDICT-IN-FROZEN-LEDGER' '1' {
  $p = Resolve-NeoRunStatePath $wGo.run 'external_verdict_ledger.jsonl'
  $entries = Read-NeoRunLedgerEntries -Path $p -SchemaId 'neo:external_audit_verdict' -Index $index -Label 'external_verdict_ledger' -ExpectedRunId (Get-RunId $wGo.run)
  @($entries | Where-Object { [string](Get-NeoProp $_ 'slice_id') -ceq '__plan__' }).Count
}
Expect-Value 'P-C5-READINESS-GO-READY' 'READY' {
  (Get-NeoClarityGateReadiness -RunRoot $wGo.run -SessionRoot $wGo.session -Index $index).state
}
$pkgGo = Invoke-NeoClarityStartGate -RunRoot $wGo.run -SessionRoot $wGo.session -NotifyTestModeDir $wGo.notify -Index $index
Expect-Value 'P-C5-GATE-GO-SURFACES' 'READY|2|True' {
  ([string]$pkgGo.state + '|' + @($pkgGo.slice_list).Count + '|' + [string]($null -ne $pkgGo.plan_verdict))
}
Expect-Value 'P-C5-GATE-PACKAGE-COVERAGE' 'True' {
  $mc = $pkgGo.manifest_coverage
  [bool](($null -ne $mc.gov_manifest_pin) -and ($null -ne $mc.app_manifest_pin) -and ($null -ne $mc.risk_register_pin) -and (@($pkgGo.risk_rows).Count -ge 1) -and (@($pkgGo.judging_registrations).Count -ge 1))
}
Expect-Value 'P-C5-GATE-NOTIFY-COMPOSED' 'True' {
  [bool](($null -ne $pkgGo.notification) -and ($null -ne $pkgGo.notification.composed_path) -and (Test-Path -LiteralPath ([string]$pkgGo.notification.composed_path)))
}
Expect-Value 'P-C5-GATE-NOTIFY-NEVER-BLOCKS' 'READY' {
  # no notify mode at all => notify REFUSES (status only); the gate still surfaces.
  (Invoke-NeoClarityStartGate -RunRoot $wGo.run -SessionRoot $wGo.session -Index $index).state
}
# ---- R-1: the on-disk bundle is the hash authority ---------------------------------
$bundleGoPath = Assert-NeoContained $wGo.session 'plan_audit/AUDIT_BUNDLE_round_1.json'
$bundleGoBytes = [System.IO.File]::ReadAllBytes($bundleGoPath)
Set-Content -LiteralPath $bundleGoPath -Value '{"swapped":"bundle body"}' -Encoding Ascii
Expect-Value 'N-C5-R1-BUNDLE-SWAPPED-BLOCKED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wGo.run -SessionRoot $wGo.session -Index $index).state
}
[System.IO.File]::WriteAllBytes($bundleGoPath, $bundleGoBytes)
Expect-Value 'P-C5-R1-BUNDLE-RESTORED-READY' 'READY' {
  (Get-NeoClarityGateReadiness -RunRoot $wGo.run -SessionRoot $wGo.session -Index $index).state
}
Remove-Item -LiteralPath $bundleGoPath -Force
Expect-Value 'N-C5-R1-BUNDLE-DELETED-BLOCKED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wGo.run -SessionRoot $wGo.session -Index $index).state
}
[System.IO.File]::WriteAllBytes($bundleGoPath, $bundleGoBytes)

# ---- H-UNAVAIL world: CLI_ERROR end-to-end via the stub seam (3.D.10) --------------
$wUn = New-World
[void](Invoke-FreezeFix $wUn)
$resUn = Invoke-PlanAuditFix $wUn $stubExitFail
Expect-Value 'P-C5-UNAVAIL-DISCLOSURE-WRITTEN' 'MISSING|CLI_ERROR|True' {
  ([string]$resUn.lane + '|' + [string]$resUn.stage + '|' + [string]$resUn.disclosure_written)
}
Expect-Value 'P-C5-UNAVAIL-STAGE-VERBATIM' 'unavailability_disclosure|CLI_ERROR' {
  $g = @(Get-GateLedgerRecords $wUn)
  ([string](Get-NeoProp $g[0] 'kind') + '|' + [string](Get-NeoProp $g[0] 'stage'))
}
Expect-Value 'P-C5-GATE-DISCLOSURE-SURFACES' 'READY_WITH_DISCLOSURE|1' {
  $pkg = Invoke-NeoClarityStartGate -RunRoot $wUn.run -SessionRoot $wUn.session -NotifyTestModeDir $wUn.notify -Index $index
  ([string]$pkg.state + '|' + @($pkg.plan_disclosures).Count)
}
# ---- 3.D.7 THE MANDATORY ADDENDUM FIXTURE ------------------------------------------
# same world, the archived disclosure REMOVED: neither a current-round verdict nor a
# current-round disclosure exists => THE GATE CANNOT SURFACE.
$gatePathUn = Resolve-NeoRunStatePath $wUn.run 'clarity_gate_ledger.jsonl'
$gateBytesUn = [System.IO.File]::ReadAllBytes($gatePathUn)
Remove-Item -LiteralPath $gatePathUn -Force
Expect-Value 'N-C5-GATE-NOTHING-ARCHIVED-BLOCKED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wUn.run -SessionRoot $wUn.session -Index $index).state
}
Expect-Block 'N-C5-GATE-NOTHING-ARCHIVED-CANNOT-SURFACE' 'CLARITY_GATE_NOT_READY' {
  Invoke-NeoClarityStartGate -RunRoot $wUn.run -SessionRoot $wUn.session -NotifyTestModeDir $wUn.notify -Index $index | Out-Null
}
# NEUTER-FLIP (load-bearing proof): neuter the disclosure-existence guard on a
# SCRATCH COPY of the module => the same world must FAIL-OPEN; restore the real
# module => BLOCKED again. This proves the guard is what blocks, not an always-fail.
$clarityPath = Join-Path $orchDir 'orch_clarity.ps1'
$claritySrc = [System.IO.File]::ReadAllText($clarityPath)
$guardNeedle = 'if (@($disclosures).Count -ge 1) {'
Expect-Value 'P-C5-NEUTER-TARGET-UNIQUE' 'True' {
  # the guard needle appears EXACTLY once (a safe, unambiguous neuter target).
  $first = $claritySrc.IndexOf($guardNeedle)
  [bool](($first -ge 0) -and ($claritySrc.IndexOf($guardNeedle, $first + 1) -lt 0))
}
$neuterPath = Join-Path $ScratchRoot 'orch_clarity_NEUTERED.ps1'
$neutered = $claritySrc.Replace('$script:NeoClarityDir = $PSScriptRoot', ('$script:NeoClarityDir = ' + "'" + $orchDir + "'"))
$neutered = $neutered.Replace($guardNeedle, 'if ($true) {')
[System.IO.File]::WriteAllText($neuterPath, $neutered, (New-Object System.Text.UTF8Encoding($false)))
. $neuterPath
Expect-Value 'NEUTER-C5-READINESS-GUARD-FAILS-OPEN' 'READY_WITH_DISCLOSURE' {
  # the neutered readiness treats a MISSING disclosure as present => the gate
  # WOULD surface with nothing archived - proving the real guard is load-bearing.
  (Get-NeoClarityGateReadiness -RunRoot $wUn.run -SessionRoot $wUn.session -Index $index).state
}
. $clarityPath   # restore the REAL module (idempotent re-source)
Expect-Value 'P-C5-READINESS-GUARD-RESTORED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wUn.run -SessionRoot $wUn.session -Index $index).state
}
[System.IO.File]::WriteAllBytes($gatePathUn, $gateBytesUn)   # put the archive back

# ---- 3.D.8 NO_GO + disposition ------------------------------------------------------
$wNg = New-World
[void](Invoke-FreezeFix $wNg)
$resNg = Invoke-PlanAuditFix $wNg $stubNoGo
Expect-Value 'P-C5-PLANAUDIT-NOGO-NO-DISCLOSURE' 'NO_GO|False' {
  ([string]$resNg.lane + '|' + [string]$resNg.disclosure_written)
}
Expect-Value 'N-C5-NOGO-NO-DISPOSITION-BLOCKED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wNg.run -SessionRoot $wNg.session -Index $index).state
}
Expect-Value 'N-C5-DISPOSITION-HASH-MISMATCH-IGNORED' 'BLOCKED' {
  [void](Add-NeoClarityGateRecord -RunRoot $wNg.run -Kind 'directional_disposition' `
    -PlanRound '1' -BundleDiffHash ('f' * 64) -RecordedBy 'session-manager' `
    -DisagreementText 'external NO-GO: conservatism on slice sizing' -Rationale 'directional only; plan is sound' `
    -StampedBy 'fixture-supervisor' -Timestamp $TS -Index $index)
  (Get-NeoClarityGateReadiness -RunRoot $wNg.run -SessionRoot $wNg.session -Index $index).state
}
Expect-Value 'P-C5-NOGO-WITH-DISPOSITION-SURFACES' 'READY_WITH_DISCLOSURE|True|1' {
  [void](Add-NeoClarityGateRecord -RunRoot $wNg.run -Kind 'directional_disposition' `
    -PlanRound ([string]$resNg.plan_round) -BundleDiffHash ([string]$resNg.bundle_diff_hash) `
    -RecordedBy 'session-manager' -DisagreementText 'external NO-GO: conservatism on slice sizing' `
    -Rationale 'directional only; plan is sound' -StampedBy 'fixture-supervisor' -Timestamp $TS -Index $index)
  $pkg = Invoke-NeoClarityStartGate -RunRoot $wNg.run -SessionRoot $wNg.session -NotifyTestModeDir $wNg.notify -Index $index
  ([string]$pkg.state + '|' + [string]($null -ne $pkg.plan_verdict) + '|' + @($pkg.plan_dispositions).Count)
}

# ---- 3.D.9 freeze revision => fresh audit (stale never satisfies) -------------------
$wSt = New-World
[void](Invoke-FreezeFix $wSt)
[void](Invoke-PlanAuditFix $wSt $stubGo)
Expect-Value 'P-C5-STALE-PRECHECK-ROUND1-READY' 'READY' {
  (Get-NeoClarityGateReadiness -RunRoot $wSt.run -SessionRoot $wSt.session -Index $index).state
}
[void](Invoke-FreezeFix $wSt)   # REVISION => plan_round 2
Expect-Value 'N-C5-REVISION-FORCES-FRESH-AUDIT' 'BLOCKED' {
  # no round-2 bundle exists yet: the round-1 GO cannot satisfy round 2.
  (Get-NeoClarityGateReadiness -RunRoot $wSt.run -SessionRoot $wSt.session -Index $index).state
}
[void](Invoke-PlanAuditFix $wSt $stubExitFail)   # round-2 bundle + disclosure land
$gatePathSt = Resolve-NeoRunStatePath $wSt.run 'clarity_gate_ledger.jsonl'
Remove-Item -LiteralPath $gatePathSt -Force       # strip the disclosure: verdict r1 vs tuple r2
Expect-Value 'N-C5-STALE-VERDICT-BLOCKED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wSt.run -SessionRoot $wSt.session -Index $index).state
}

# ---- R-2: EXHAUSTIVE disclosure trigger (crafted/unknown lane) + ADAPTER_THREW ------
$wR2 = New-World
[void](Invoke-FreezeFix $wR2)
$script:origAdapter = ${function:Invoke-NeoExternalAudit}
${function:Invoke-NeoExternalAudit} = { param($RunRoot, $SliceId, $RoundId, $SessionRoot, $BundleRef, $Timestamp, $StampedBy, $AttestationPath, $CredentialPath, $TimeoutSec, $InvokerSeam)
  return @{ lane = 'WEIRD_LANE'; stage = 'CRAFTED_STAGE'; reason = 'crafted non-verdict outcome (fixture)'; verdict = ''; slice_call_seq = 0; post_increment_count = 0 } }
Expect-Value 'P-C5-R2-UNRECOGNIZED-LANE-DISCLOSED' 'WEIRD_LANE|True|CRAFTED_STAGE' {
  $r = Invoke-PlanAuditFix $wR2 $null
  $g = @(Get-GateLedgerRecords $wR2)
  ([string]$r.lane + '|' + [string]$r.disclosure_written + '|' + [string](Get-NeoProp $g[@($g).Count - 1] 'stage'))
}
${function:Invoke-NeoExternalAudit} = { param($RunRoot, $SliceId, $RoundId, $SessionRoot, $BundleRef, $Timestamp, $StampedBy, $AttestationPath, $CredentialPath, $TimeoutSec, $InvokerSeam)
  return @{ lane = 'WEIRD_LANE'; stage = ''; reason = 'no stage at all'; verdict = ''; slice_call_seq = 0; post_increment_count = 0 } }
Expect-Block 'N-C5-R2-BLANK-STAGE-REFUSED' 'CLARITY_PLAN_AUDIT' {
  Invoke-PlanAuditFix $wR2 $null | Out-Null
}
${function:Invoke-NeoExternalAudit} = { param($RunRoot, $SliceId, $RoundId, $SessionRoot, $BundleRef, $Timestamp, $StampedBy, $AttestationPath, $CredentialPath, $TimeoutSec, $InvokerSeam)
  throw 'NEO-BLOCK: fixture caller-contract failure (adapter threw)' }
Expect-Value 'P-C5-ADAPTER-THREW-DISCLOSED' 'MISSING|ADAPTER_THREW|True' {
  $r = Invoke-PlanAuditFix $wR2 $null
  ([string]$r.lane + '|' + [string]$r.stage + '|' + [string]$r.disclosure_written)
}
${function:Invoke-NeoExternalAudit} = $script:origAdapter   # restore the frozen adapter

# ---- honest fail-closed bound: the plan-pseudo-slice sub-cap (<=3) ------------------
$wCap = New-World
[void](Invoke-FreezeFix $wCap)
for ($i = 1; $i -le 3; $i++) { [void](Invoke-PlanAuditFix $wCap $stubExitFail) }
Expect-Value 'P-C5-PLANAUDIT-SUBCAP-DISCLOSED' 'SUBCAP|True' {
  $r = Invoke-PlanAuditFix $wCap $stubExitFail   # 4th attempt: refused, still disclosed
  ([string]$r.stage + '|' + [string]$r.disclosure_written)
}
# ---- post-freeze pin drift is refused BEFORE any call -------------------------------
$wPd = New-World
[void](Invoke-FreezeFix $wPd)
Add-Content -LiteralPath (Assert-NeoContained $wPd.session 'plan_audit/gov_manifest_pin_round_1.json') -Value ' ' -Encoding Ascii
Expect-Block 'N-C5-PIN-DRIFT-BLOCKS' 'CLARITY_PLAN_AUDIT' {
  Invoke-PlanAuditFix $wPd $stubGo | Out-Null
}

Write-Host ''
Write-Host '=== SECTION I: READINESS INPUT HARDENING (3.D.17) ===' -ForegroundColor Cyan
$wI = New-World
Expect-Value 'N-C5-READY-NO-FREEZE-BLOCKED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wI.run -SessionRoot $wI.session -Index $index).state
}
Expect-Block 'N-C5-READY-NO-FREEZE-CANNOT-SURFACE' 'CLARITY_GATE_NOT_READY' {
  Invoke-NeoClarityStartGate -RunRoot $wI.run -SessionRoot $wI.session -NotifyTestModeDir $wI.notify -Index $index | Out-Null
}
# hand-plant a schema-invalid freeze line (malformed plan_round) => BLOCKED, never READY.
$wI2 = New-World
$fzI2 = Join-Path $wI2.run 'clarity_freeze_ledger.jsonl'
$badLine = '{"schema_id":"neo:clarity_freeze_record","run_id":"' + (Get-RunId $wI2.run) + '","plan_round":"0"}'
[System.IO.File]::AppendAllText($fzI2, ($badLine + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Expect-Value 'N-C5-READY-MALFORMED-FREEZE-BLOCKED' 'BLOCKED' {
  (Get-NeoClarityGateReadiness -RunRoot $wI2.run -SessionRoot $wI2.session -Index $index).state
}
Expect-Block 'N-C5-READY-MALFORMED-FREEZE-CANNOT-SURFACE' 'CLARITY_GATE_NOT_READY' {
  Invoke-NeoClarityStartGate -RunRoot $wI2.run -SessionRoot $wI2.session -NotifyTestModeDir $wI2.notify -Index $index | Out-Null
}

Write-Host ''
Write-Host '=== SECTION J: THE S3c COMPLETENESS CARRY (3.D.16) ===' -ForegroundColor Cyan
# iteration-manifest row shape (the loop-suite New-RowFields twin; frozen reader-valid).
function New-RowFields([string]$slice, [int]$round) {
  return @{
    slice_id = $slice; round = $round; attempt_seq = ($round + 1)
    baseline_head_sha = ('a' * 40); baseline_tree_hash = ('b' * 64)
    changed_count = 1; changed_paths_hash = ('c' * 64)
    classification = 'THREE_BRANCH_CLEAN'; findings_summary = 'NONE'
    auditor_slot_status = 'SATISFIED'; auditor_slot_recommendation = 'GO'
    auditor_identity = 'isolated-auditor-cold'; external_lane_status = 'NOT_WIRED'
    effective_seam_tier = 'isolated'; cap_events = @()
    stop_reason_code = 'NONE'; notify_gate_class = 'NONE'
    notify_sent = $false; notify_deduped = $false; notify_refused = $false
    notify_reason = ''; timestamp_utc = $TS
  }
}
# P: plan {sA,sB} == recorded {sA,sB} => the carry passes and returns the universe.
$wJ1 = New-World
[void](Invoke-FreezeFix $wJ1)
[void](Add-NeoIterationManifestEntry -RunRoot $wJ1.run -Fields (New-RowFields 'sA' 0))
[void](Add-NeoIterationManifestEntry -RunRoot $wJ1.run -Fields (New-RowFields 'sB' 0))
Expect-Value 'P-C5-UNIVERSE-OK' '2' {
  @(Assert-NeoClarityPlanSliceUniverse -RunRoot $wJ1.run -ExpectedRunId (Get-RunId $wJ1.run) -Index $index).Count
}
# N: plan {sA,sB}, recorded {sA} => the PLANNED-BUT-NEVER-STARTED slice sB is EXTRA
# (no run evidence) => BLOCK. THE S3c GAP CLOSED: a never-started slice cannot vanish.
$wJ2 = New-World
[void](Invoke-FreezeFix $wJ2)
[void](Add-NeoIterationManifestEntry -RunRoot $wJ2.run -Fields (New-RowFields 'sA' 0))
Expect-Block 'N-C5-UNIVERSE-PLANNED-NEVER-RECORDED' 'LEDGER_FAILURE' {
  Assert-NeoClarityPlanSliceUniverse -RunRoot $wJ2.run -ExpectedRunId (Get-RunId $wJ2.run) -Index $index | Out-Null
}
# N: plan {sA} (single-slice plan), recorded {sA,sZ} => the UNPLANNED recorded slice
# sZ is an OMISSION from the frozen plan => BLOCK (equally a trail defect).
$wJ3 = New-World
$spJ3 = @( @{ slice_id = 'sA'; approved_paths = @('./app/'); protected_paths = @('./.neo/')
              acceptance_harness_paths = @('harness/sA_fixture_suite.ps1'); risk_row_ref = 'r1' } )
[void](Invoke-FreezeFix $wJ3 @{ SlicePlan = $spJ3 })
[void](Add-NeoIterationManifestEntry -RunRoot $wJ3.run -Fields (New-RowFields 'sA' 0))
[void](Add-NeoIterationManifestEntry -RunRoot $wJ3.run -Fields (New-RowFields 'sZ' 0))
Expect-Block 'N-C5-UNIVERSE-UNPLANNED-RECORDED' 'LEDGER_FAILURE' {
  Assert-NeoClarityPlanSliceUniverse -RunRoot $wJ3.run -ExpectedRunId (Get-RunId $wJ3.run) -Index $index | Out-Null
}
# the frozen loop seam is REQUIRED: absent => fail-closed BLOCK, never a skip.
$savedUniverse = ${function:Assert-NeoLoopRunSliceUniverse}
Remove-Item function:Assert-NeoLoopRunSliceUniverse
Expect-Block 'N-C5-UNIVERSE-LOOP-SEAM-ABSENT' 'CLARITY_UNIVERSE' {
  Assert-NeoClarityPlanSliceUniverse -RunRoot $wJ1.run -ExpectedRunId (Get-RunId $wJ1.run) -Index $index | Out-Null
}
${function:Assert-NeoLoopRunSliceUniverse} = $savedUniverse

Write-Host ''
Write-Host '=== SECTION K: GATE-RECORD KIND DISCIPLINE (R1-2/R1-3, writer level) ===' -ForegroundColor Cyan
$wK = New-World
$h64 = ('d' * 64)
Expect-Block 'N-C5-GATEREC-KIND-CASE' 'CLARITY_GATE_RECORD' {
  Add-NeoClarityGateRecord -RunRoot $wK.run -Kind 'Unavailability_Disclosure' -PlanRound '1' -BundleDiffHash $h64 `
    -Stage 'CLI_ERROR' -Reason 'x' -StampedBy 's' -Timestamp $TS -Index $index | Out-Null
}
Expect-Block 'N-C5-GATEREC-DISCLOSURE-WITH-DISPOSITION-FIELD' 'DISJOINT' {
  Add-NeoClarityGateRecord -RunRoot $wK.run -Kind 'unavailability_disclosure' -PlanRound '1' -BundleDiffHash $h64 `
    -Stage 'CLI_ERROR' -Reason 'x' -RecordedBy 'manager' -StampedBy 's' -Timestamp $TS -Index $index | Out-Null
}
Expect-Block 'N-C5-GATEREC-DISPOSITION-WITH-STAGE' 'DISJOINT' {
  Add-NeoClarityGateRecord -RunRoot $wK.run -Kind 'directional_disposition' -PlanRound '1' -BundleDiffHash $h64 `
    -RecordedBy 'manager' -DisagreementText 'd' -Rationale 'r' -Stage 'CLI_ERROR' -StampedBy 's' -Timestamp $TS -Index $index | Out-Null
}
Expect-Block 'N-C5-GATEREC-DISPOSITION-BLANK-RECORDEDBY' 'CLARITY_SHAPE' {
  Add-NeoClarityGateRecord -RunRoot $wK.run -Kind 'directional_disposition' -PlanRound '1' -BundleDiffHash $h64 `
    -DisagreementText 'd' -Rationale 'r' -StampedBy 's' -Timestamp $TS -Index $index | Out-Null
}
Expect-Block 'N-C5-GATEREC-WRONG-BASIS' 'CLARITY_GATE_RECORD' {
  Add-NeoClarityGateRecord -RunRoot $wK.run -Kind 'directional_disposition' -PlanRound '1' -BundleDiffHash $h64 `
    -RecordedBy 'manager' -AuthorityBasis 'because I said so' -DisagreementText 'd' -Rationale 'r' `
    -StampedBy 's' -Timestamp $TS -Index $index | Out-Null
}
Expect-Block 'N-C5-GATEREC-BAD-HASH' 'CLARITY_GATE_RECORD' {
  Add-NeoClarityGateRecord -RunRoot $wK.run -Kind 'unavailability_disclosure' -PlanRound '1' -BundleDiffHash 'FFFF' `
    -Stage 'CLI_ERROR' -Reason 'x' -StampedBy 's' -Timestamp $TS -Index $index | Out-Null
}
# a disposition's stamp is tamper-EVIDENT like every clarity record (NB-4).
[void](Add-NeoClarityGateRecord -RunRoot $wK.run -Kind 'unavailability_disclosure' -PlanRound '1' -BundleDiffHash $h64 `
  -Stage 'CLI_ERROR' -Reason 'fixture reason' -StampedBy 'fixture-supervisor' -Timestamp $TS -Index $index)
$gkPath = Resolve-NeoRunStatePath $wK.run 'clarity_gate_ledger.jsonl'
$gkLines = @([System.IO.File]::ReadAllLines($gkPath))
$gkLines[0] = $gkLines[0].Replace('"reason":"fixture reason"', '"reason":"tampered reason"')
[System.IO.File]::WriteAllLines($gkPath, $gkLines)
Expect-Block 'N-C5-GATEREC-TAMPERED' 'CLARITY_GATE_RECORD_TAMPERED' {
  Read-NeoClarityGateRecords -RunRoot $wK.run -Index $index | Out-Null
}

Write-Host ''
Write-Host '=== SECTION S: STRUCTURAL (live-incapability + seam-only discipline) ===' -ForegroundColor Cyan
Expect-Value 'STRUCTURAL-TRIPWIRE-NEVER-FIRED' '0' { $script:liveTrip }
Expect-Value 'STRUCTURAL-SEAMS-EXERCISED' 'True' { [bool]($global:NeoClaritySeamCalls -gt 0) }
$selfText = [System.IO.File]::ReadAllText($PSCommandPath)
Expect-Value 'STRUCTURAL-SINGLE-PLAN-AUDIT-CALLSITE' 'True' {
  # the raw splat call appears EXACTLY once - inside Invoke-PlanAuditFix (needle
  # built by concatenation so this check never matches itself).
  $needle = ('Invoke-NeoClarityPlanAudit' + ' @')
  $first = $selfText.IndexOf($needle)
  [bool](($first -ge 0) -and ($selfText.IndexOf($needle, $first + 1) -lt 0))
}
Expect-Value 'STRUCTURAL-NO-LIVE-SEND' 'True' {
  # notify runs ONLY compose-to-disk: the live-send flag never appears in this file.
  $needle = ('-Live' + 'Send')
  [bool]($selfText.IndexOf($needle) -lt 0)
}
Expect-Value 'STRUCTURAL-NO-LIVE-CREDENTIAL-PATH' 'True' {
  # the live codex credential location never appears in this file (fixture twins only).
  $needle = ('.co' + 'dex\auth')
  [bool]($selfText.IndexOf($needle) -lt 0)
}

# =============================================================================
# SUMMARY + RESIDUE-CLEAN SECOND PASS
# =============================================================================
$total = @($script:results).Count
$failed = @($script:results | Where-Object { -not $_.pass })
$skips = @($script:results | Where-Object { $_.kind -eq 'skip' })
$passCount = $total - $failed.Count

Write-Host ''
Write-Host ("Results: {0}/{1} PASS ({2} skip-disclosed)" -f $passCount, $total, $skips.Count) -ForegroundColor Cyan

if ($ProofOut) {
  $proof = [pscustomobject]@{
    suite     = 'orch_clarity_suite'
    slice     = '4.0-P4-AUTONOMY-C5-CLARITY'
    total     = $total
    passed    = $passCount
    failed    = $failed.Count
    skipped   = $skips.Count
    results   = $script:results
    generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  $proof | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ProofOut -Encoding Ascii
}

# residue-clean second pass: remove ALL scratch worlds, then PROVE the root is gone.
if (-not $KeepScratch) {
  Remove-Item -Recurse -Force -LiteralPath $ScratchRoot -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $ScratchRoot) {
    Write-Host "RESIDUE: scratch root survived cleanup: $ScratchRoot" -ForegroundColor Red
    $failed = @($failed) + [pscustomobject]@{ guard = 'RESIDUE-CLEAN'; pass = $false }
  } else {
    Write-Host 'residue-clean: scratch + all worlds removed' -ForegroundColor Green
  }
}

if ($failed.Count -gt 0) { exit 1 } else { exit 0 }
