# orch_pilot_run.ps1 - NEO 4.0-P3-C THROWAWAY PILOT runner (integrated end-to-end).
# ASCII-only (D10). Dot-sources and CALLS the REAL installed engine (orch_engine.ps1 ->
# enforce/rollover/io/schema/class) + the REAL orch_auditor_stub.ps1; reimplements NO
# orchestration logic. Drives a disposable synthetic multi-sub-session app through the WHOLE
# loop (P1..P7, happy + unhappy), validates every produced artifact against the INSTALLED
# .neo/schema spine, asserts each enforcement FIRES, and proves the pilot is LOAD-BEARING via
# neuter-on-copy negative variants (E1 tier / E2 gate / E3 routing / E4 dep / E5 rollover).
# Serial only. Fixture-local ledger. Sandbox program root (./program stays placeholder-only).
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [string]$SliceCapture,
  [switch]$KeepScratch,
  [string]$Timestamp = '2026-07-03T00:00:00Z'
)
$ErrorActionPreference = 'Stop'

$script:orchDir = Split-Path -Parent $PSScriptRoot           # ...\.neo\scripts\orchestrator
. "$script:orchDir\..\_neo_root.ps1"
$script:NeoRoot = Resolve-NeoRoot $script:orchDir
. "$script:orchDir\orch_engine.ps1"                          # the REAL engine chain
. "$PSScriptRoot\orch_pilot.ps1"                             # pilot fixture/artifact builders

$script:schemaDir = Join-Path $script:NeoRoot '.neo\schema'
$script:index = Get-NeoSchemaIndex $script:schemaDir         # the INSTALLED 25-schema spine
$script:map   = Get-NeoClassMap (Join-Path $script:schemaDir 'artifact_classes.json')
$script:stub  = Join-Path $script:orchDir 'orch_auditor_stub.ps1'
$script:TS    = $Timestamp

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_orch_p3c_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null
$script:sandbox  = $ScratchRoot
$script:progRoot = Join-Path $ScratchRoot 'program'

# ---- result plumbing --------------------------------------------------------
# kind: 'stage'    -> happy-path step (must SUCCEED)
#       'guard'    -> an enforcement that must FIRE (BLOCK) on bad input
#       'neuter'   -> load-bearing proof: neutering the guard on a COPY must FLIP to fail-open
#       'evidence' -> a produced artifact must be schema-valid vs the installed spine
#       'struct'   -> a coordinate-not-validate structural fact (must hold)
$script:results = @()
$script:artifacts = @()
$script:goCount = 0
$script:seamHigh = @()   # slugs whose close traversed the auditor-slot seam with required=true (slice-2)
function Record($name, $pass, $detail, $kind) {
  $script:results += [pscustomobject]@{ check = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $kind, $name, $detail) -ForegroundColor $col
}
function Expect-Block($name, $sb) {
  try { & $sb; Record $name $false 'NO BLOCK (guard did not fire)' 'guard' }
  catch {
    if ($_.Exception.Message -like 'NEO-BLOCK:*') { Record $name $true $_.Exception.Message 'guard' }
    else { Record $name $false ('threw non-BLOCK: ' + $_.Exception.Message) 'guard' }
  }
}
function Expect-Ok($name, $sb) {
  try { $r = & $sb; Record $name $true "$r" 'stage' }
  catch { Record $name $false ('unexpected block/error: ' + $_.Exception.Message) 'stage' }
}
function Add-Artifact($path, $schema, $label) { $script:artifacts += [pscustomobject]@{ path = $path; schema = $schema; label = $label } }

# NEUTER-ON-COPY (twin of the frozen suites): copy the whole engine .ps1 chain to scratch,
# patch the ONE guard line on the COPY, dot-source the neutered chain, re-run the SAME fixture,
# then RESTORE the real engine. Load-bearing iff the neutered version FLIPS BLOCK -> pass.
# (Only *.ps1 directly in orchDir are copied; the pilot builders under pilot\ are NOT neutered.)
function Expect-NeuterFlip($name, $file, $find, $replace, $fixture) {
  # F2 (isolated-auditor tightening): a load-bearing proof requires BOTH halves - the guard must
  # BLOCK on the PRISTINE engine AND fail-open after the neuter. Asserting only the flip-after would
  # let a fixture that silently stopped blocking pre-neuter degrade undetected. So we FIRST run the
  # fixture against the already-loaded REAL engine and require a BLOCK; a fixture that does NOT block
  # pre-neuter FAILS the variant (no silent pass). All six neuter fixtures are pure in-memory /
  # read-only calls, so running them twice (pre + post) is side-effect-free and idempotent.
  $blockedBefore = $true
  try { & $fixture; $blockedBefore = $false } catch { $blockedBefore = $true }
  if (-not $blockedBefore) { Record $name $false 'guard did NOT block on the pristine engine (fixture degraded / not load-bearing)' 'neuter'; return }

  $neuterDir = Join-Path $script:sandbox ('neuter_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $neuterDir | Out-Null
  Get-ChildItem -LiteralPath $script:orchDir -Filter *.ps1 -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $neuterDir $_.Name) -Force }
  $tgt = Join-Path $neuterDir $file
  $txt = Get-Content -LiteralPath $tgt -Raw
  if (-not $txt.Contains($find)) { Record $name $false "neuter target string not present in $file (fixture/guard drift)" 'neuter'; return }
  $patched = $txt.Replace($find, $replace)
  if ($patched -ceq $txt) { Record $name $false "neuter replace was a no-op in $file" 'neuter'; return }
  Set-Content -LiteralPath $tgt -Value $patched -Encoding UTF8 -NoNewline
  $blockedAfter = $true
  try {
    . (Join-Path $neuterDir 'orch_engine.ps1')     # load NEUTERED chain (functions redefined)
    try { & $fixture; $blockedAfter = $false } catch { $blockedAfter = $true }
  } finally {
    . "$script:orchDir\orch_engine.ps1"             # RESTORE the real functions
  }
  # Load-bearing iff BOTH: blocked-before (asserted above) AND fail-open-after.
  $verdict = if (-not $blockedAfter) { 'FAIL-OPEN (guard was load-bearing)' } else { 'still blocked (NOT load-bearing / drift)' }
  Record $name (-not $blockedAfter) ("blocked-before + neuter removed the guard => pilot assertion " + $verdict) 'neuter'
}

# lightweight index/record helpers for the E4 neuter fixture (bypass schema to hit the engine guard)
function Rec($slug, $status, $risk, $resolution, $blockedUntil, $dependsOn) {
  [pscustomobject]@{ slug = $slug; risk_class = $risk; status = $status; resolution = $resolution; dependent_continuation_blocked_until = $blockedUntil; depends_on = @($dependsOn) }
}
function Idx($records) { [pscustomobject]@{ index_id = 'ix'; index_version = 'v'; records = @($records) } }
function New-PilotHandoff([bool]$NoPartial) {
  New-NeoHandoffPacket -PacketId 'hp-nv' -SpecRef $script:specRef -ConstraintRef $script:conRef -RiskRef $script:riskRef -IndexRef $script:idxRef `
    -OpenDeferrals @() -LastGreenState $script:goodLGS -NextDecision 'resume' -AllRefsHashed $true -NoOpenAmbiguity $true -NoPartialSubsession $NoPartial `
    -Timestamp $script:TS -Index $script:index
}

# common sub-session audit: write start/end, ingest, assemble bundle, honest stub GO, consume,
# fill the slot OUTSIDE the engine from the consumed verdict, then run the engine-side fail-closed
# auditor-slot seam (slice-2). This is the SINGLE shared close path: every audited subsession
# structurally traverses the seam; there is no per-subsession bypass.
function Invoke-PilotAudit {
  param([string]$Slug, [string]$SlugDir, $StartPacket, $EndReportObj, [string]$Tier, $RiskRow, [switch]$ProveIsolatedRejectsValidator)
  New-Item -ItemType Directory -Force -Path $SlugDir | Out-Null
  $spPath = Join-Path $SlugDir 'SUBSESSION_START_PACKET.json'
  Write-NeoJsonFile $spPath $StartPacket
  Assert-NeoValid $StartPacket 'neo:subsession_start_packet' $script:index 'SUBSESSION_START_PACKET'
  Add-Artifact $spPath 'neo:subsession_start_packet' "start:$Slug"

  $erPath = Join-Path $SlugDir 'SUBSESSION_END_REPORT.json'
  Write-NeoJsonFile $erPath $EndReportObj
  Read-NeoEndReport $erPath $script:index | Out-Null
  Add-Artifact $erPath 'neo:subsession_end_report' "end:$Slug"

  # a RUNNABLE proof (exit 0) so the cold auditor's NON-CACHED re-run genuinely verifies it.
  $proofP = Join-Path $SlugDir 'proof.ps1'; Set-Content -LiteralPath $proofP -Value 'exit 0' -Encoding UTF8
  $auditDir = Join-Path $SlugDir 'audit'
  # IMMUTABLE audit-time END copy: the bundle freezes THIS copy by hash, so the LIVE END can
  # receive the slot post-audit without invalidating the bundle's member re-hash (slice-2).
  New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
  $endAudited = Join-Path $auditDir 'END_audited.json'
  Copy-Item -LiteralPath $erPath -Destination $endAudited -Force
  $specP = Get-NeoProgramPath $script:progRoot 'PROJECT_SPEC'
  $members = @(
    @{ path = $specP;  rel = './program/PROJECT_SPEC.json'; role = 'spec' },
    @{ path = $spPath; rel = "./NEO_SESSION/$Slug/SUBSESSION_START_PACKET.json"; role = 'start_packet' },
    @{ path = $endAudited; rel = "./NEO_SESSION/$Slug/audit/END_audited.json"; role = 'end_report' },
    @{ path = $proofP; rel = "./NEO_SESSION/$Slug/proof.ps1"; role = 'proof' }
  )
  $bundlePath = Join-Path $auditDir 'AUDIT_BUNDLE.json'
  $bundle = New-NeoAuditBundle -BundleId "bundle-$Slug" -MemberItems $members -ApprovedPaths @('./app/') -ProtectedPaths @('./.neo/') `
    -Surfaces @('filesystem') -RiskTier 'high' -Timestamp $script:TS -Index $script:index -OutPath $bundlePath
  Add-Artifact $bundlePath 'neo:input_packet' "bundle:$Slug"

  if ($ProveIsolatedRejectsValidator) {
    # W3: an isolated tier MUST reject a non-auditor-class AUDIT_RESULT (adversarial fixture).
    $advPath = Join-Path $auditDir 'AUDIT_RESULT_adversarial.json'
    New-PilotAdversarialAuditResult -Path $advPath -BundleDir $script:sandbox -Bundle $bundle -ProducerClass 'validator' -Recommendation 'GO' -AuditorId 'isolated-auditor-x' -TS $script:TS -Index $script:index | Out-Null
    Expect-Block "P3-W3-isolated-rejects-validator-class" {
      Read-NeoAuditResult -AuditResultPath $advPath -Bundle $bundle -BundleDir $script:sandbox -MasterIdentity 'pilot-master' -BuilderIdentity "builder-$Slug" -Index $script:index -RequiredTier 'isolated' | Out-Null
    }
  }

  $arPath = Join-Path $auditDir 'AUDIT_RESULT.json'
  & $script:stub -BundlePath $bundlePath -BundleDir $script:sandbox -OutPath $arPath -Timestamp $script:TS -AuditorIdentity 'isolated-auditor-cold' | Out-Null
  Add-Artifact $arPath 'neo:audit_result' "audit_result:$Slug"
  $consumed = Read-NeoAuditResult -AuditResultPath $arPath -Bundle $bundle -BundleDir $script:sandbox -MasterIdentity 'pilot-master' -BuilderIdentity ("builder-$Slug") -Index $script:index -RequiredTier $Tier
  if ($consumed.recommendation -eq 'GO') { $script:goCount++ }

  # slice-2 CLOSE STEP: an isolated/full_isolated tier gets its slot filled OUTSIDE the engine
  # from the CONSUMED verdict (master action, Set-PilotAuditorSlot); a lightweight tier leaves it
  # null. EITHER WAY the engine-side seam then runs - it is the un-skippable shared close gate.
  $bundleRel = "./NEO_SESSION/$Slug/audit/AUDIT_BUNDLE.json"
  if (($Tier -ceq 'isolated') -or ($Tier -ceq 'full_isolated')) {
    Set-PilotAuditorSlot -ErPath $erPath -Consumed $consumed -BundleRel $bundleRel | Out-Null
  }
  $endLive = Read-NeoEndReport $erPath $script:index
  $slotCheck = Assert-NeoAuditorSlotSatisfied -RiskRow $RiskRow -EndReport $endLive -SessionRoot $script:sandbox `
    -MasterIdentity 'pilot-master' -BuilderIdentity ("builder-$Slug") -Index $script:index
  if (-not $slotCheck.satisfied) { throw "auditor-slot seam not satisfied for $Slug" }
  if ($slotCheck.required) { $script:seamHigh += $Slug }
  return @{ consumed = $consumed; bundle = $bundle; bundlePath = $bundlePath; arPath = $arPath; slot = $slotCheck }
}

Write-Host "NEO 4.0-P3-C throwaway pilot (P1..P7 end-to-end; genuine, load-bearing)" -ForegroundColor Cyan
Write-Host "sandbox: $script:sandbox"

# fixture-local ledger: one START gate for security, one for deploy, one accept-fail gate.
$SEC_GATE = '2026-07-03-P3C-SEC-START'
$FAIL_GATE = '2026-07-03-P3C-DEPLOY-START'
$ACCEPT_GATE = '2026-07-03-P3C-ACCEPT-FAIL'
$ledPath = Write-PilotLedger (Join-Path $script:sandbox 'HGL_fixture.json') @(
  [pscustomobject]@{ gate_ref = $SEC_GATE;    gate_kind = 'human_start_approval'; authorized_by = 'Raphael'; recorded_at = '2026-07-03'; app_slug = 'pilot-app'; authorized_paths = @('./x/', './app/') }
  [pscustomobject]@{ gate_ref = $FAIL_GATE;   gate_kind = 'human_start_approval'; authorized_by = 'Raphael'; recorded_at = '2026-07-03'; app_slug = 'pilot-app'; authorized_paths = @('./app/') }
  [pscustomobject]@{ gate_ref = $ACCEPT_GATE; gate_kind = 'human_end_keep';       authorized_by = 'Raphael'; recorded_at = '2026-07-03'; app_slug = 'pilot-app'; authorized_paths = @('./app/') }
)
$pilotLed = Read-NeoGateLedger $ledPath $script:index

# =========================== P1 INIT ========================================
Expect-Ok 'P1-init-serial' {
  Build-PilotProgram $script:progRoot $script:TS $script:index
  $init = Invoke-NeoInit -ProgramRoot $script:progRoot -Index $script:index -MasterId 'pilot-master' -SessionId 'p3c-0' -Timestamp $script:TS -SnapshotDir (Join-Path $script:sandbox 'snapshots')
  $mc = Read-NeoProgramArtifact $script:progRoot 'MASTER_CHECKPOINT' $script:index
  Read-NeoProgramArtifact $script:progRoot 'SUBSESSION_INDEX' $script:index | Out-Null
  if ($mc.orchestration_mode -ne 'serial') { throw "mode=$($mc.orchestration_mode)" }
  $script:si = $init.subsession_index
  "MASTER_CHECKPOINT + SUBSESSION_INDEX written; orchestration_mode=serial"
}
# A-serial: concurrent orchestration is refused (code + schema enum).
Expect-Block 'P1-concurrent-init-refused' { Invoke-NeoInit -ProgramRoot $script:progRoot -Index $script:index -MasterId 'pilot-master' -SessionId 'p3c-0' -Timestamp $script:TS -OrchestrationMode 'concurrent' | Out-Null }

$risk = Read-NeoProgramArtifact $script:progRoot 'RISK_REGISTER' $script:index
$mc   = Read-NeoProgramArtifact $script:progRoot 'MASTER_CHECKPOINT' $script:index
$mcRef = Get-NeoArtifactRef $mc
$specP = Get-NeoProgramPath $script:progRoot 'PROJECT_SPEC'
$allowSpec = @(@{ path = $specP; rel = './program/PROJECT_SPEC.json'; role = 'project_spec' })

# =========================== P2 LOW (batchable + lightweight) ================
Expect-Ok 'P2-low-batchable-lightweight-GO' {
  $lowRow = Get-PilotRiskRow $risk 'r-low'
  $disp = Invoke-NeoGovernedDispatch -RiskRow $lowRow -ClassMap $script:map -Ledger $pilotLed -Batched `
    -PacketId 'pkt-low' -Goal 'low-risk batchable feature' -TestPlan @('run tests') -StopConditions @('scope_breach') `
    -RiskClass 'low' -AllowlistItems $allowSpec -ApprovedPaths @('./app/') -ProtectedPaths @('./.neo/') `
    -Surfaces @('filesystem') -ReferencedArtifacts @($mcRef) -Timestamp $script:TS -Index $script:index
  if ($disp.audit_tier -ne 'lightweight') { throw "tier=$($disp.audit_tier)" }
  if ($null -ne $disp.gate) { throw 'batched general_feature should bind no gate' }
  $er = New-PilotEndReport 'ss-low' './app/low.ps1' 'create' 0 $script:TS
  $r = Invoke-PilotAudit -Slug 'ss-low' -SlugDir (Join-Path $script:sandbox 'NEO_SESSION\ss-low') -StartPacket $disp.start_packet -EndReportObj $er -Tier $disp.audit_tier -RiskRow $lowRow
  if ($r.consumed.recommendation -ne 'GO') { throw "got $($r.consumed.recommendation)" }
  $script:p2 = $r
  $rec = [pscustomobject][ordered]@{
    slug = 'ss-low'; start_packet_ref = @{ packet_id = 'pkt-low'; content_hash = (Get-NeoProp (Get-NeoProp $disp.start_packet.input_packet '_provenance') 'content_hash').value }
    risk_class = 'low'; status = 'ended_pass'; end_report_ref = @{ artifact_id = 'er-ss-low'; content_hash = (Get-NeoProp (Get-NeoProp $er '_provenance') 'content_hash').value }
    audit_tier_applied = $disp.audit_tier; last_green = @{ proof_ref = './NEO_SESSION/ss-low/proof.ps1'; content_hash = ('0' * 64); summary = 'low slice green' }; depends_on = @()
  }
  Add-NeoIndexRecord -SubIndex $script:si -Record $rec -Index $script:index -Timestamp $script:TS | Out-Null
  "tier=lightweight, batched+logged (no gate), consume GO, index=ended_pass"
}
# A-cnv: the engine CANNOT self-approve - auditor_identity == master identity is BLOCKED.
Expect-Block 'A-cnv-auditor-eq-master-blocked' {
  Read-NeoAuditResult -AuditResultPath $script:p2.arPath -Bundle $script:p2.bundle -BundleDir $script:sandbox -MasterIdentity 'isolated-auditor-cold' -BuilderIdentity 'b' -Index $script:index | Out-Null
}

# =========================== P3 MEDIUM (isolated; no silent fall-through; W3) =
# A-tier: MEDIUM defaults ISOLATED; a MEDIUM+lightweight row with NO explicit_downgrade BLOCKS.
Expect-Ok 'P3-medium-defaults-isolated' {
  $t = Resolve-NeoAuditTier -RiskRow (Get-PilotRiskRow $risk 'r-med'); if ($t -ne 'isolated') { throw "tier=$t" }; "medium default tier=$t"
}
Expect-Block 'P3-medium-lightweight-no-downgrade-blocked' {
  Resolve-NeoAuditTier -RiskRow ([pscustomobject]@{ id = 'r-med2'; area = 'general_feature'; risk_class = 'medium'; never_batchable = $false; audit_tier = 'lightweight' }) | Out-Null
}
Expect-Ok 'P3-medium-isolated-W3-GO' {
  $medRow = Get-PilotRiskRow $risk 'r-med'
  $disp = Invoke-NeoGovernedDispatch -RiskRow $medRow -ClassMap $script:map -Ledger $pilotLed -Batched `
    -PacketId 'pkt-med' -Goal 'medium-risk feature' -TestPlan @('run tests') -StopConditions @('scope_breach') `
    -RiskClass 'medium' -AllowlistItems $allowSpec -ApprovedPaths @('./app/') -ProtectedPaths @('./.neo/') `
    -Surfaces @('filesystem') -ReferencedArtifacts @($mcRef) -Timestamp $script:TS -Index $script:index
  if ($disp.audit_tier -ne 'isolated') { throw "tier=$($disp.audit_tier)" }
  $er = New-PilotEndReport 'ss-med' './app/med.ps1' 'edit' 0 $script:TS
  $r = Invoke-PilotAudit -Slug 'ss-med' -SlugDir (Join-Path $script:sandbox 'NEO_SESSION\ss-med') -StartPacket $disp.start_packet -EndReportObj $er -Tier $disp.audit_tier -RiskRow $medRow -ProveIsolatedRejectsValidator
  if ($r.consumed.recommendation -ne 'GO') { throw "got $($r.consumed.recommendation)" }
  $rec = [pscustomobject][ordered]@{
    slug = 'ss-med'; start_packet_ref = @{ packet_id = 'pkt-med'; content_hash = (Get-NeoProp (Get-NeoProp $disp.start_packet.input_packet '_provenance') 'content_hash').value }
    risk_class = 'medium'; status = 'ended_pass'; end_report_ref = @{ artifact_id = 'er-ss-med'; content_hash = (Get-NeoProp (Get-NeoProp $er '_provenance') 'content_hash').value }
    audit_tier_applied = $disp.audit_tier; last_green = @{ proof_ref = './NEO_SESSION/ss-med/proof.ps1'; content_hash = ('0' * 64); summary = 'med slice green' }; depends_on = @()
  }
  Add-NeoIndexRecord -SubIndex $script:si -Record $rec -Index $script:index -Timestamp $script:TS | Out-Null
  "tier=isolated (no fall-through), validator-class REJECTED / auditor-class GO, index=ended_pass"
}

# =========================== P4 SENSITIVE/HIGH (gate + routing fire) =========
$secRow = Get-PilotRiskRow $risk 'r-sec'
Expect-Block 'P4-E2-ghost-gate-blocked'     { Assert-NeoGateBound -RiskRow $secRow -GateRef 'ghost-gate' -Ledger $pilotLed | Out-Null }
Expect-Ok    'P4-E2-bound-gate-binds'       { $g = Assert-NeoGateBound -RiskRow $secRow -GateRef $SEC_GATE -Ledger $pilotLed -AppSlug 'pilot-app' -ScopePaths @('./x/rubric.schema.json'); if ($null -eq $g) { throw 'no gate bound' }; 'bound' }
Expect-Block 'P4-E3-cheap-judging-blocked'  { Assert-NeoRouteEdit -ClassMap $script:map -TargetPath './x/rubric.schema.json' -ProducerClass 'cheap_producer' -TaskRisk 'low' -RoutingEntry (New-PilotRoutingEntry 'cheap_producer' 'auditor' 'auditor reviews rubric') | Out-Null }
Expect-Ok    'P4-E3-strong-auditor-passes'  { $x = Assert-NeoRouteEdit -ClassMap $script:map -TargetPath './x/rubric.schema.json' -ProducerClass 'strong_producer' -TaskRisk 'high' -RoutingEntry (New-PilotRoutingEntry 'strong_producer' 'auditor' 'auditor validates judging-class edit' 'high'); "class=$($x.class)" }
Expect-Ok 'P4-sensitive-high-gated-routed-GO' {
  $edits = @(@{ path = './x/rubric.schema.json'; producer_class = 'strong_producer'; task_risk = 'high'; routing_entry = (New-PilotRoutingEntry 'strong_producer' 'auditor' 'auditor validates a high-risk judging edit' 'high') })
  $disp = Invoke-NeoGovernedDispatch -RiskRow $secRow -ClassMap $script:map -Ledger $pilotLed `
    -GateRef $SEC_GATE -AppSlug 'pilot-app' -ScopePaths @('./x/rubric.schema.json') -ProposedEdits $edits `
    -PacketId 'pkt-sec' -Goal 'harden a judging rubric' -TestPlan @('run tests') -StopConditions @('scope_breach') `
    -RiskClass 'high' -AllowlistItems $allowSpec -ApprovedPaths @('./x/') -ProtectedPaths @('./.neo/') `
    -Surfaces @('filesystem') -ReferencedArtifacts @($mcRef) -Timestamp $script:TS -Index $script:index
  if ($disp.audit_tier -ne 'isolated') { throw "tier=$($disp.audit_tier)" }
  if ($null -eq $disp.gate) { throw 'expected a bound gate' }
  $er = New-PilotEndReport 'ss-sec' './x/rubric.schema.json' 'edit' 0 $script:TS
  $r = Invoke-PilotAudit -Slug 'ss-sec' -SlugDir (Join-Path $script:sandbox 'NEO_SESSION\ss-sec') -StartPacket $disp.start_packet -EndReportObj $er -Tier $disp.audit_tier -RiskRow $secRow
  if ($r.consumed.recommendation -ne 'GO') { throw "got $($r.consumed.recommendation)" }
  $rec = [pscustomobject][ordered]@{
    slug = 'ss-sec'; start_packet_ref = @{ packet_id = 'pkt-sec'; content_hash = (Get-NeoProp (Get-NeoProp $disp.start_packet.input_packet '_provenance') 'content_hash').value }
    risk_class = 'high'; status = 'ended_pass'; end_report_ref = @{ artifact_id = 'er-ss-sec'; content_hash = (Get-NeoProp (Get-NeoProp $er '_provenance') 'content_hash').value }
    audit_tier_applied = $disp.audit_tier; last_green = @{ proof_ref = './NEO_SESSION/ss-sec/proof.ps1'; content_hash = ('0' * 64); summary = 'sec slice green' }; depends_on = @()
  }
  Add-NeoIndexRecord -SubIndex $script:si -Record $rec -Index $script:index -Timestamp $script:TS | Out-Null
  "gate bound + routed(strong+auditor) + tier=isolated -> consume GO, index=ended_pass"
}

# =========================== P5 FAILED HIGH + DEPENDENT =====================
Expect-Ok 'P5a-failed-high-recorded' {
  $failRow = Get-PilotRiskRow $risk 'r-fail'
  $disp = Invoke-NeoGovernedDispatch -RiskRow $failRow -ClassMap $script:map -Ledger $pilotLed `
    -GateRef $FAIL_GATE -AppSlug 'pilot-app' -ScopePaths @('./app/deploy.ps1') `
    -PacketId 'pkt-fail' -Goal 'risky deploy step' -TestPlan @('run tests') -StopConditions @('scope_breach') `
    -RiskClass 'high' -AllowlistItems $allowSpec -ApprovedPaths @('./app/') -ProtectedPaths @('./.neo/') `
    -Surfaces @('filesystem') -ReferencedArtifacts @($mcRef) -Timestamp $script:TS -Index $script:index
  $slugDir = Join-Path $script:sandbox 'NEO_SESSION\ss-fail'; New-Item -ItemType Directory -Force -Path $slugDir | Out-Null
  $spPath = Join-Path $slugDir 'SUBSESSION_START_PACKET.json'; Write-NeoJsonFile $spPath $disp.start_packet
  Add-Artifact $spPath 'neo:subsession_start_packet' 'start:ss-fail'
  $er = New-PilotEndReport 'ss-fail' './app/deploy.ps1' 'edit' 1 $script:TS   # exit=1 => failed session
  $erPath = Join-Path $slugDir 'SUBSESSION_END_REPORT.json'; Write-NeoJsonFile $erPath $er
  Read-NeoEndReport $erPath $script:index | Out-Null
  Add-Artifact $erPath 'neo:subsession_end_report' 'end:ss-fail'
  $rec = [pscustomobject][ordered]@{
    slug = 'ss-fail'; start_packet_ref = @{ packet_id = 'pkt-fail'; content_hash = (Get-NeoProp (Get-NeoProp $disp.start_packet.input_packet '_provenance') 'content_hash').value }
    risk_class = 'high'; status = 'ended_fail'; end_report_ref = @{ artifact_id = 'er-ss-fail'; content_hash = (Get-NeoProp (Get-NeoProp $er '_provenance') 'content_hash').value }
    audit_tier_applied = $disp.audit_tier; last_green = $null; depends_on = @()
    dependent_continuation_blocked_until = 'resolution:rolled_back|human_accepted_fail of ss-fail'; resolution = $null
  }
  Add-NeoIndexRecord -SubIndex $script:si -Record $rec -Index $script:index -Timestamp $script:TS | Out-Null
  "ss-fail dispatched (gated) + ended_fail recorded with blocked_until marker"
}
$depRow = Get-PilotRiskRow $risk 'r-low'
function Invoke-DepDispatch {
  Invoke-NeoGovernedDispatch -RiskRow $depRow -ClassMap $script:map -Ledger $pilotLed -Batched -SubIndex $script:si -DependsOn @('ss-fail') `
    -PacketId 'pkt-dep' -Goal 'work that depends on ss-fail' -TestPlan @('run tests') -StopConditions @('scope_breach') `
    -RiskClass 'low' -AllowlistItems $allowSpec -ApprovedPaths @('./app/') -ProtectedPaths @('./.neo/') `
    -Surfaces @('filesystem') -ReferencedArtifacts @($mcRef) -Timestamp $script:TS -Index $script:index
}
Expect-Block 'P5b-dependent-blocked-while-unresolved' { Invoke-DepDispatch | Out-Null }
# resolve ss-fail in place: rolled_back w/ rollback_ref, clear the blocked_until marker.
Expect-Ok 'P5c-resolve-rolled_back' {
  $fr = @($script:si.records | Where-Object { $_.slug -eq 'ss-fail' })[0]
  $fr.status = 'rolled_back'
  $fr.resolution = [pscustomobject]@{ mode = 'rolled_back'; rollback_ref = './NEO_SESSION/ss-fail/snapshots/pre.snap'; gate_ref = $null; dependency_impact = 'ss-dep may proceed on the rolled-back baseline' }
  $fr.dependent_continuation_blocked_until = $null
  Set-NeoArtifactHash $script:si
  Assert-NeoValid $script:si 'neo:subsession_index' $script:index 'SUBSESSION_INDEX(resolved)'
  'ss-fail resolved: status=rolled_back, rollback_ref set, marker cleared'
}
Expect-Ok 'P5d-dependent-proceeds-after-resolve' {
  $disp = Invoke-DepDispatch
  $er = New-PilotEndReport 'ss-dep' './app/dependent.ps1' 'edit' 0 $script:TS
  $r = Invoke-PilotAudit -Slug 'ss-dep' -SlugDir (Join-Path $script:sandbox 'NEO_SESSION\ss-dep') -StartPacket $disp.start_packet -EndReportObj $er -Tier $disp.audit_tier -RiskRow $depRow
  if ($r.consumed.recommendation -ne 'GO') { throw "got $($r.consumed.recommendation)" }
  $rec = [pscustomobject][ordered]@{
    slug = 'ss-dep'; start_packet_ref = @{ packet_id = 'pkt-dep'; content_hash = (Get-NeoProp (Get-NeoProp $disp.start_packet.input_packet '_provenance') 'content_hash').value }
    risk_class = 'low'; status = 'ended_pass'; end_report_ref = @{ artifact_id = 'er-ss-dep'; content_hash = (Get-NeoProp (Get-NeoProp $er '_provenance') 'content_hash').value }
    audit_tier_applied = $disp.audit_tier; last_green = @{ proof_ref = './NEO_SESSION/ss-dep/proof.ps1'; content_hash = ('0' * 64); summary = 'dependent slice green' }; depends_on = @('ss-fail')
  }
  Add-NeoIndexRecord -SubIndex $script:si -Record $rec -Index $script:index -Timestamp $script:TS | Out-Null
  'dependent unblocked after resolution -> consume GO, index=ended_pass'
}
# second resolution mode covered as a positive: human_accepted_fail with a ledger-bound gate ALLOWS.
Expect-Ok 'P5e-human_accepted_fail-bound-allows' {
  $idxHA = Idx @(Rec 'hf' 'human_accepted_fail' 'high' ([pscustomobject]@{ mode = 'human_accepted_fail'; rollback_ref = $null; gate_ref = $ACCEPT_GATE; dependency_impact = 'accepted' }) $null @())
  Assert-NeoDependentContinuationAllowed -SubIndex $idxHA -DependsOn @('hf') -Ledger $pilotLed -Index $script:index | Out-Null
  'human_accepted_fail w/ ledger-bound gate => allowed'
}

# persist the final SUBSESSION_INDEX (append-only ledger) to the sandbox program root.
Write-NeoProgramArtifact -ProgramRoot $script:progRoot -Name 'SUBSESSION_INDEX' -Obj $script:si -Index $script:index | Out-Null

# =========================== P6 ROLLOVER (emit -> resume; stale/tamper reject) =
$script:specRef = Get-NeoArtifactRef (Read-NeoProgramArtifact $script:progRoot 'PROJECT_SPEC' $script:index)
$script:conRef  = Get-NeoArtifactRef (Read-NeoProgramArtifact $script:progRoot 'CONSTRAINT_PACKAGE' $script:index)
$script:riskRef = Get-NeoArtifactRef (Read-NeoProgramArtifact $script:progRoot 'RISK_REGISTER' $script:index)
$script:idxRef  = Get-NeoArtifactRef (Read-NeoProgramArtifact $script:progRoot 'SUBSESSION_INDEX' $script:index)
$proofP = Join-Path $script:progRoot 'proof.txt'; Set-Content -LiteralPath $proofP -Value 'exit=0' -Encoding UTF8
$script:goodLGS = @{ proof_ref = './proof.txt'; content_hash = (Get-NeoSha256File $proofP); summary = 'pilot terminal green state' }
$hpPath = Get-NeoProgramPath $script:progRoot 'HANDOFF_PACKET'
Expect-Ok 'P6a-rollover-emit' {
  $pkt = New-NeoHandoffPacket -PacketId 'hp-p3c' -SpecRef $script:specRef -ConstraintRef $script:conRef -RiskRef $script:riskRef -IndexRef $script:idxRef `
    -OpenDeferrals @() -LastGreenState $script:goodLGS -NextDecision 'continue to terminal GO' -AllRefsHashed $true -NoOpenAmbiguity $true -NoPartialSubsession $true `
    -Timestamp $script:TS -Index $script:index
  Write-NeoJsonFile $hpPath $pkt
  Add-Artifact $hpPath 'neo:handoff_packet' 'handoff'
  'HANDOFF_PACKET emitted (refs by id+hash)'
}
Expect-Ok 'P6b-fresh-master-resumes-from-packet-alone' {
  $re = Read-NeoJsonFile $hpPath
  $r = Assert-NeoPacketResumable -Packet $re -ProgramRoot $script:progRoot -Index $script:index
  if (-not $r.resumable) { throw 'not resumable' }
  if ($r.next_decision -ne 'continue to terminal GO') { throw "nd=$($r.next_decision)" }
  'fresh master resumed from the packet ALONE (schema + self-hash + not-stale + all *_ref re-hash pass)'
}
Expect-Block 'P6c-stale-packet-rejected'        { Assert-NeoPacketResumable -Packet (New-PilotHandoff $false) -ProgramRoot $script:progRoot -Index $script:index | Out-Null }
Expect-Block 'P6d-self-hash-tampered-rejected'  { $t = New-PilotHandoff $true; $t.integrity.packet_self_hash = ('d' * 64); Assert-NeoPacketResumable -Packet $t -ProgramRoot $script:progRoot -Index $script:index | Out-Null }

# =========================== P7 TERMINAL (coherent GO) ======================
Expect-Ok 'P7-terminal-coherent-GO' {
  $mc = Read-NeoProgramArtifact $script:progRoot 'MASTER_CHECKPOINT' $script:index
  $mc.subsession_index_ref.content_hash = (Get-NeoProp (Get-NeoProp $script:si '_provenance') 'content_hash').value
  Set-NeoArtifactHash $mc
  Write-NeoProgramArtifact -ProgramRoot $script:progRoot -Name 'MASTER_CHECKPOINT' -Obj $mc -Index $script:index | Out-Null
  Add-Artifact (Get-NeoProgramPath $script:progRoot 'MASTER_CHECKPOINT') 'neo:master_checkpoint' 'master_checkpoint'
  Add-Artifact (Get-NeoProgramPath $script:progRoot 'SUBSESSION_INDEX')  'neo:subsession_index'  'subsession_index'
  $mc2 = Read-NeoProgramArtifact $script:progRoot 'MASTER_CHECKPOINT' $script:index
  $si2 = Read-NeoProgramArtifact $script:progRoot 'SUBSESSION_INDEX'  $script:index
  if ($mc2.orchestration_mode -ne 'serial') { throw 'mode not serial' }
  if ($mc2.subsession_index_ref.content_hash -cne (Get-NeoProp (Get-NeoProp $si2 '_provenance') 'content_hash').value) { throw 'MC index ref stale => incoherent' }
  $slugs = @($si2.records | ForEach-Object { $_.slug })
  foreach ($need in @('ss-low', 'ss-med', 'ss-sec', 'ss-fail', 'ss-dep')) { if ($slugs -notcontains $need) { throw "index missing $need" } }
  if ($script:goCount -lt 4) { throw "happy GO count $($script:goCount) < 4" }
  # slice-2 STRUCT assertion (folded here to keep the pilot count stable): EVERY high-risk
  # ended_pass record must have traversed the auditor-slot seam with required=true. A high-risk
  # subsession that closed around the seam is a terminal incoherence.
  $highPass = @($si2.records | Where-Object { ([string]$_.risk_class -ceq 'high') -and ([string]$_.status -ceq 'ended_pass') } | ForEach-Object { $_.slug })
  if ($highPass.Count -lt 1) { throw 'expected at least one high-risk ended_pass record' }
  foreach ($h in $highPass) { if ($script:seamHigh -notcontains $h) { throw "high-risk ended_pass '$h' did not traverse the auditor-slot seam" } }
  "terminal coherent (mode=serial, MC<->INDEX bound, GO count=$($script:goCount)); slugs: $($slugs -join ','); high-pass seam-verified: $($highPass -join ',')"
}

# =========================== NEGATIVE VARIANTS (load-bearing proof) ==========
# Six variants. Each neuters ONE guard on a COPY of the engine chain (the real engine is never
# modified); Expect-NeuterFlip requires BOTH halves - the guard BLOCKS on the pristine engine AND
# fails-open after the neuter (F2). E4 is split into TWO variants that each match what they claim:
#   NV4-marker - proves the E4 MARKER barrier (dependent_continuation_blocked_until) is load-bearing.
#                This is the SAME barrier the live P5b block fires on. Fixture ISOLATES the marker:
#                a record with the marker SET but an otherwise-SAFE status (ended_pass), so the marker
#                is the SOLE blocker and neutering it flips to fail-open (the status barrier cannot
#                mask the flip). Honest nuance: P5b's LIVE record is ended_fail+marker, where the
#                marker guard fires FIRST (before the status switch is reached); NV4-marker uses
#                ended_pass+marker only to isolate that exact marker guard.
#   NV4-status - proves the E4 ended_fail STATUS barrier is load-bearing (marker=null; status blocks).
Expect-NeuterFlip 'NV1-tier(E1)' 'orch_enforce.ps1' 'if (-not (Test-NeoDowngradeComplete $dg))' 'if ($false)' `
  { Resolve-NeoAuditTier -RiskRow ([pscustomobject]@{ id = 'x'; area = 'general_feature'; risk_class = 'medium'; never_batchable = $false; audit_tier = 'lightweight' }) | Out-Null }
Expect-NeuterFlip 'NV2-gate(E2)' 'orch_enforce.ps1' 'if ($null -eq $match) { New-NeoBlock "gate-binding: gate_ref' 'if ($false) { New-NeoBlock "gate-binding: gate_ref' `
  { Assert-NeoGateBound -RiskRow $secRow -GateRef 'ghost-gate' -Ledger $pilotLed | Out-Null }
Expect-NeuterFlip 'NV3-routing(E3)' 'orch_enforce.ps1' "if (`$judging -and (`$ProducerClass -eq 'cheap_producer')) {" 'if ($false) {' `
  { Assert-NeoRouteEdit -ClassMap $script:map -TargetPath './x/rubric.schema.json' -ProducerClass 'cheap_producer' -TaskRisk 'low' -RoutingEntry (New-PilotRoutingEntry 'cheap_producer' 'auditor' 'auditor reviews rubric') | Out-Null }
# NV4-marker: neuter the MARKER guard; fixture = marker SET + SAFE status (ended_pass) => marker is sole blocker => flips.
Expect-NeuterFlip 'NV4-marker(E4)' 'orch_rollover.ps1' `
  "New-NeoBlock ""dependent-continuation: dependency '`$slug' has dependent_continuation_blocked_until='`$blockedUntil' set => BLOCK (D8 marker not cleared)""" '$true' `
  { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'dM' 'ended_pass' 'high' $null 'resolution:rolled_back|human_accepted_fail of dM' @())) -DependsOn @('dM') -Ledger $pilotLed -Index $script:index | Out-Null }
# NV4-status: neuter the ended_fail STATUS guard; fixture = marker null + status ended_fail => status is sole blocker => flips.
Expect-NeuterFlip 'NV4-status(E4)' 'orch_rollover.ps1' `
  "New-NeoBlock ""dependent-continuation: dependency '`$slug' status='ended_fail' (unresolved failure; no rollback/human-acceptance) => BLOCK (E4a, D8 2)""" '$true' `
  { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'dA' 'ended_fail' 'high' $null $null @())) -DependsOn @('dA') -Ledger $pilotLed -Index $script:index | Out-Null }
Expect-NeuterFlip 'NV5-rollover(E5)' 'orch_rollover.ps1' `
  'if ($v -eq $false) { New-NeoBlock "handoff: not_stale_assertion.$f = false' 'if ($false) { New-NeoBlock "handoff: not_stale_assertion.$f = false' `
  { Assert-NeoPacketResumable -Packet (New-PilotHandoff $false) -ProgramRoot $script:progRoot -Index $script:index | Out-Null }

# =========================== STRUCTURAL (coordinate-not-validate) ============
$libFiles = @('orch_schema.ps1', 'orch_class.ps1', 'orch_io.ps1', 'orch_enforce.ps1', 'orch_rollover.ps1', 'orch_engine.ps1', 'orchestrator.ps1')
$noStubRef = $true
foreach ($f in $libFiles) { $code = @(Get-Content -LiteralPath (Join-Path $script:orchDir $f) | Where-Object { $_ -notmatch '^\s*#' }); if (($code -join "`n") -match 'auditor_stub') { $noStubRef = $false } }
Record 'A-cnv-engine-never-invokes-auditor' $noStubRef 'no engine CODE line references/invokes the separate auditor writer' 'struct'
$engineHasLiteral = $false
foreach ($f in $libFiles) { if ((Get-Content -Raw -LiteralPath (Join-Path $script:orchDir $f)) -match 'rehash_check\s*=') { $engineHasLiteral = $true } }
$stubHasLiteral = ((Get-Content -Raw -LiteralPath $script:stub) -match 'rehash_check\s*=')
Record 'A-cnv-result-literal-only-in-stub' ((-not $engineHasLiteral) -and $stubHasLiteral) 'AUDIT_RESULT rehash_check literal exists only in the separate stub' 'struct'

# =========================== EVIDENCE VALIDATION vs INSTALLED SPINE ==========
foreach ($a in $script:artifacts) {
  $ok = $true; $msg = 'schema-valid vs installed spine'
  try { $obj = Read-NeoJsonFile $a.path; Assert-NeoValid $obj $a.schema $script:index $a.label }
  catch { $ok = $false; $msg = $_.Exception.Message }
  Record ("EV:" + $a.label) $ok ("$($a.schema) : $msg") 'evidence'
}

# ---- summary ----------------------------------------------------------------
$byKind = @{}
foreach ($k in @('stage', 'guard', 'neuter', 'evidence', 'struct')) {
  $set = @($script:results | Where-Object { $_.kind -eq $k })
  $f = @($set | Where-Object { -not $_.pass }).Count
  $byKind[$k] = @{ total = $set.Count; fail = $f }
}
$fail = @($script:results | Where-Object { -not $_.pass }).Count
Write-Host ""
foreach ($k in @('stage', 'guard', 'neuter', 'evidence', 'struct')) {
  Write-Host ("{0,-9}: {1}/{2} pass" -f $k, ($byKind[$k].total - $byKind[$k].fail), $byKind[$k].total) -ForegroundColor $(if ($byKind[$k].fail -eq 0) { 'Green' } else { 'Red' })
}
Write-Host ("RESULT: {0} pass / {1} fail (of {2})" -f ($script:results.Count - $fail), $fail, $script:results.Count) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

if ($ProofOut) {
  $report = [pscustomobject]@{
    suite = 'NEO-4.0-P3-C-PILOT'; timestamp = $script:TS
    stages = $byKind['stage']; guards = $byKind['guard']; neuters = $byKind['neuter']; evidence = $byKind['evidence']; struct = $byKind['struct']
    happy_go_count = $script:goCount; fail = $fail; results = $script:results
  }
  $od = Split-Path -Parent $ProofOut; if ($od -and -not (Test-Path -LiteralPath $od)) { New-Item -ItemType Directory -Force -Path $od | Out-Null }
  ($report | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $ProofOut -Encoding UTF8
  Write-Host "proof written: $ProofOut"
}

# capture the produced pilot evidence into the slice folder BEFORE residue-clean.
if ($SliceCapture) {
  if (-not (Test-Path -LiteralPath $SliceCapture)) { New-Item -ItemType Directory -Force -Path $SliceCapture | Out-Null }
  Copy-Item -LiteralPath $script:progRoot -Destination (Join-Path $SliceCapture 'program') -Recurse -Force
  $ns = Join-Path $script:sandbox 'NEO_SESSION'
  if (Test-Path -LiteralPath $ns) { Copy-Item -LiteralPath $ns -Destination (Join-Path $SliceCapture 'NEO_SESSION') -Recurse -Force }
  Copy-Item -LiteralPath $ledPath -Destination (Join-Path $SliceCapture 'HGL_fixture.json') -Force
  Write-Host "evidence captured: $SliceCapture"
}

$residueClean = $true
if (-not $KeepScratch) {
  Remove-Item -Recurse -Force -LiteralPath $script:sandbox
  $residueClean = -not (Test-Path -LiteralPath $script:sandbox)
  Write-Host ("residue-clean: {0} (sandbox removed)" -f $residueClean)
}

if ($fail -eq 0 -and $residueClean) { exit 0 } else { exit 1 }
