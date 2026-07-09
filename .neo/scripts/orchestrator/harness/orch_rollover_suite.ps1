# orch_rollover_suite.ps1 - NEO 4.0-P3-B2b INDEPENDENT lifecycle harness (v4 5.7).
# ASCII-only (D10). Kept SEPARATE from the engine it tests.
#
# Proves E4 (rollback / dependent-continuation, D8) and E5 (rollover / HANDOFF, D7) each FAIL
# CLOSED, and that each guard is LOAD-BEARING: neutering the single guard line on a COPY flips
# the fixture from BLOCK/REJECT to fail-open (pass). Includes the A1 complete dependency-status
# decision table (every status -> explicit verdict) and the A2 missing/null not_stale defence.
# Ends with the RESUME-E2E: a HANDOFF_PACKET is emitted, then a fresh master resumes from the
# packet ALONE (schema + self-hash + not-stale + every *_ref re-hash all pass). Writes NO
# AUDIT_RESULT from the engine (coordinate-not-validate; G3c/G3d extended to orch_rollover.ps1).
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'

$orchDir = Split-Path -Parent $PSScriptRoot   # ...\.neo\scripts\orchestrator
. "$orchDir\..\_neo_root.ps1"
$NeoRoot = Resolve-NeoRoot $orchDir
. "$orchDir\orch_engine.ps1"

$schemaDir = Join-Path $NeoRoot '.neo\schema'
$index = Get-NeoSchemaIndex $schemaDir
$TS = '2026-07-03T00:00:00Z'

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_orch_b2b_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors the B2a suite framing) ------------------------
$script:results = @()
function Record($name, $pass, $detail, $kind = 'negative') {
  $script:results += [pscustomobject]@{ guard = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  $ktag = if ($kind -eq 'negative') { 'GUARD' } else { 'info ' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $ktag, $name, $detail) -ForegroundColor $col
}
function Expect-Block($name, $sb) {
  try { & $sb; Record $name $false 'NO BLOCK (guard did not fire)' 'negative' }
  catch {
    if ($_.Exception.Message -like 'NEO-BLOCK:*') { Record $name $true $_.Exception.Message 'negative' }
    else { Record $name $false ('threw non-BLOCK: ' + $_.Exception.Message) 'negative' }
  }
}
function Expect-Ok($name, $sb) {
  try { $r = & $sb; Record $name $true "$r" 'positive' }
  catch { Record $name $false ('unexpected block/error: ' + $_.Exception.Message) 'positive' }
}
# NEUTER-ON-COPY: copy the whole orchestrator .ps1 chain, patch the ONE guard line on the copy,
# dot-source the neutered chain, re-run the SAME fixture, then RESTORE the real functions.
# Load-bearing iff the neutered version does NOT block (flips to fail-open).
function Expect-NeuterFlip($name, $file, $find, $replace, $fixture) {
  $neuterDir = Join-Path $ScratchRoot ('neuter_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $neuterDir | Out-Null
  Get-ChildItem -LiteralPath $orchDir -Filter *.ps1 -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $neuterDir $_.Name) -Force }
  $tgt = Join-Path $neuterDir $file
  $txt = Get-Content -LiteralPath $tgt -Raw
  if (-not $txt.Contains($find)) { Record $name $false "neuter target string not present in $file (fixture/guard drift)" 'negative'; return }
  $patched = $txt.Replace($find, $replace)
  if ($patched -ceq $txt) { Record $name $false "neuter replace was a no-op in $file" 'negative'; return }
  Set-Content -LiteralPath $tgt -Value $patched -Encoding UTF8 -NoNewline

  $blockedAfter = $true
  try {
    . (Join-Path $neuterDir 'orch_engine.ps1')     # load NEUTERED chain (functions redefined)
    try { & $fixture; $blockedAfter = $false } catch { $blockedAfter = $true }
  } finally {
    . "$orchDir\orch_engine.ps1"                    # RESTORE the real functions
  }
  $verdict = if (-not $blockedAfter) { 'FAIL-OPEN (guard was load-bearing)' } else { 'still blocked (another guard caught it / not load-bearing)' }
  Record $name (-not $blockedAfter) ("neuter removed the guard => fixture " + $verdict) 'negative'
}

# ---- fixture builders -------------------------------------------------------
function New-Env($id, $class, $schemaId, $prole, $pclass, $vclass) {
  New-NeoEnvelope -ArtifactId $id -ArtifactClass $class -SchemaId $schemaId -SchemaVersion '4.0-P3-B' `
    -ProducerRole $prole -ProducerClass $pclass -ValidatorRole $prole -ValidatorClass $vclass `
    -Timestamp $TS -DeclaredPaths @('./program/') -DeclaredSurfaces @('filesystem') -SourcePackets @() -GateRef $null
}
# A SUBSESSION_INDEX record (only the fields E4 reads; built lightweight so tests can bypass schema
# to exercise the ENGINE guards directly, e.g. an invalid rolled_back record with no rollback_ref).
function Rec($slug, $status, $risk, $resolution, $blockedUntil, $dependsOn) {
  [pscustomobject]@{
    slug = $slug; risk_class = $risk; status = $status
    resolution = $resolution
    dependent_continuation_blocked_until = $blockedUntil
    depends_on = @($dependsOn)
  }
}
function Idx($records) { [pscustomobject]@{ index_id = 'ix'; index_version = 'v'; records = @($records) } }
function ResRB($ref)  { [pscustomobject]@{ mode = 'rolled_back'; rollback_ref = $ref; gate_ref = $null; dependency_impact = 'x' } }
function ResHA($gate) { [pscustomobject]@{ mode = 'human_accepted_fail'; rollback_ref = $null; gate_ref = $gate; dependency_impact = 'x' } }
function Write-FixtureLedger($path, $entries) {
  $led = [pscustomobject]@{
    human_gate_ledger_schema_id = 'neo:human_gate_ledger'
    root_of_trust               = 'provisional-dev'
    note                        = 'FIXTURE-LOCAL ledger for the B2b rollover suite. NEVER the live governed-gates ledger.'
    entries                     = @($entries)
  }
  Write-NeoJsonFile $path $led
  return $path
}

Write-Host "NEO 4.0-P3-B2b rollover suite (E4 rollback/dependent-continuation / E5 rollover HANDOFF)" -ForegroundColor Cyan
Write-Host "scratch: $ScratchRoot"

# Shared fixture ledger: one bound acceptance gate.
$ledPath = Write-FixtureLedger (Join-Path $ScratchRoot 'HGL_fixture.json') @(
  [pscustomobject]@{ gate_ref = '2026-07-03-B2B-ACCEPT-FAIL'; gate_kind = 'human_end_keep'; authorized_by = 'Raphael'; recorded_at = '2026-07-03'; app_slug = 'demo-app'; authorized_paths = @('./app/') }
)
$led = Read-NeoGateLedger $ledPath $index    # residual-(c): index-gated validate-on-load

# ---- Residual (c): a MALFORMED ledger fails as a CLEAN NEO-BLOCK (not a raw crash) ----
# An entry missing a required key => clean BLOCK when the caller passes -Index (the E4b bind path).
# (The null-entry guard is a separate independent barrier; here the key guard is load-bearing.)
$badLedPath = Join-Path $ScratchRoot 'HGL_malformed.json'
Write-NeoJsonFile $badLedPath ([pscustomobject]@{ human_gate_ledger_schema_id = 'neo:human_gate_ledger'; root_of_trust = 'provisional-dev'; entries = @([pscustomobject]@{ gate_kind = 'human_end_keep'; authorized_by = 'Raphael'; recorded_at = '2026-07-03'; app_slug = 'a'; authorized_paths = @('./') }) })
Expect-Block 'RC-malformed-ledger-clean-block' { Read-NeoGateLedger $badLedPath $index | Out-Null }
Expect-NeuterFlip 'RC-malformed-ledger-neuter-flip' 'orch_enforce.ps1' `
  'if (-not (Test-NeoHasProp $e $k)) { New-NeoBlock "gate-binding: ledger entry missing required' `
  'if ($false) { New-NeoBlock "gate-binding: ledger entry missing required' `
  { Read-NeoGateLedger $badLedPath $index | Out-Null }

# ============================ E4 DEPENDENT-CONTINUATION (D8) =================
# E4a: dependent continuation past an UNRESOLVED failed HIGH-risk dependency => BLOCK (+neuter-flip).
# Fixture: failed HIGH, resolution=null, marker=null (so the STATUS guard - not the marker - is the
# load-bearing barrier; a failed record must block even if the marker was never set).
$idxE4a = Idx @(Rec 'dA' 'ended_fail' 'high' $null $null @())
Expect-Block 'E4a-continue-past-unresolved-failed-high' { Assert-NeoDependentContinuationAllowed -SubIndex $idxE4a -DependsOn @('dA') -Ledger $led -Index $index | Out-Null }
Expect-NeuterFlip 'E4a-neuter-flip' 'orch_rollover.ps1' `
  "New-NeoBlock ""dependent-continuation: dependency '`$slug' status='ended_fail' (unresolved failure; no rollback/human-acceptance) => BLOCK (E4a, D8 2)""" '$true' `
  { Assert-NeoDependentContinuationAllowed -SubIndex $idxE4a -DependsOn @('dA') -Ledger $led -Index $index | Out-Null }

# E4-marker: a non-null dependent_continuation_blocked_until BLOCKS even on an otherwise-passing
# status (fail-closed against an inconsistent record). Independent load-bearing marker guard.
$idxMark = Idx @(Rec 'dM' 'ended_pass' 'high' $null 'resolution:rolled_back|human_accepted_fail of dM' @())
Expect-Block 'E4-marker-still-set' { Assert-NeoDependentContinuationAllowed -SubIndex $idxMark -DependsOn @('dM') -Ledger $led -Index $index | Out-Null }
Expect-NeuterFlip 'E4-marker-neuter-flip' 'orch_rollover.ps1' `
  "New-NeoBlock ""dependent-continuation: dependency '`$slug' has dependent_continuation_blocked_until='`$blockedUntil' set => BLOCK (D8 marker not cleared)""" '$true' `
  { Assert-NeoDependentContinuationAllowed -SubIndex $idxMark -DependsOn @('dM') -Ledger $led -Index $index | Out-Null }

# E4b: human_accepted_fail with a gate_ref that does NOT bind in the ledger => BLOCK (+neuter-flip).
# This is the ledger cross-check the SCHEMA CANNOT do (gate_ref is present + minLength 1, yet ghost).
$idxE4b = Idx @(Rec 'dB' 'human_accepted_fail' 'high' (ResHA 'ghost-gate') $null @())
Expect-Block 'E4b-human_accept-ghost-gate' { Assert-NeoDependentContinuationAllowed -SubIndex $idxE4b -DependsOn @('dB') -Ledger $led -Index $index | Out-Null }
Expect-NeuterFlip 'E4b-neuter-flip' 'orch_rollover.ps1' `
  "if (`$null -eq `$match) { New-NeoBlock ""resolution: human_accepted_fail gate_ref" `
  "if (`$false) { New-NeoBlock ""resolution: human_accepted_fail gate_ref" `
  { Assert-NeoDependentContinuationAllowed -SubIndex $idxE4b -DependsOn @('dB') -Ledger $led -Index $index | Out-Null }

# E4c: rolled_back with no rollback_ref => BLOCK (+neuter-flip). Direct call bypasses schema so the
# ENGINE guard (defence-in-depth over the schema conditional) is what fires and is load-bearing.
$recE4c = Rec 'dC' 'rolled_back' 'high' (ResRB '') $null @()
Expect-Block 'E4c-rolled_back-no-rollback_ref' { Assert-NeoResolutionValid -Rec $recE4c -Ledger $led -Index $index | Out-Null }
Expect-NeuterFlip 'E4c-neuter-flip' 'orch_rollover.ps1' `
  "if ([string]::IsNullOrWhiteSpace(`$rb)) { New-NeoBlock ""resolution: mode='rolled_back'" `
  "if (`$false) { New-NeoBlock ""resolution: mode='rolled_back'" `
  { Assert-NeoResolutionValid -Rec $recE4c -Ledger $led -Index $index | Out-Null }

# ---- A1 COMPLETE STATUS TABLE: every non-safe status BLOCKS (no implicit allow) ----
Expect-Block 'A1-in_progress-blocks'   { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'd1' 'in_progress'  'medium' $null $null @())) -DependsOn @('d1') -Ledger $led -Index $index | Out-Null }
Expect-Block 'A1-dispatched-blocks'    { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'd2' 'dispatched'   'low'    $null $null @())) -DependsOn @('d2') -Ledger $led -Index $index | Out-Null }
Expect-Block 'A1-unknown-status-blocks'{ Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'd3' 'weird_status' 'high'   $null $null @())) -DependsOn @('d3') -Ledger $led -Index $index | Out-Null }
Expect-Block 'A1-blank-status-blocks'  { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'd4' ''             'high'   $null $null @())) -DependsOn @('d4') -Ledger $led -Index $index | Out-Null }
Expect-Block 'A1-low-ended_fail-blocks'{ Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'd5' 'ended_fail'   'low'    $null $null @())) -DependsOn @('d5') -Ledger $led -Index $index | Out-Null }
Expect-Block 'A1-missing-dep-record'   { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'dX' 'ended_pass'   'low'    $null $null @())) -DependsOn @('ghost') -Ledger $led -Index $index | Out-Null }
Expect-Block 'A1-depends_on-but-null-index' { Assert-NeoDependentContinuationAllowed -SubIndex $null -DependsOn @('dZ') -Ledger $led -Index $index | Out-Null }

# ---- E4 POSITIVES: only provably-safe states proceed ----
Expect-Ok 'E4-pos-no-dependency'        { Assert-NeoDependentContinuationAllowed -SubIndex $null -DependsOn @() -Ledger $led -Index $index; 'no declared dependency => allowed' }
Expect-Ok 'E4-pos-ended_pass'           { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'p1' 'ended_pass' 'high' $null $null @())) -DependsOn @('p1') -Ledger $led -Index $index; 'ended_pass => allowed' }
Expect-Ok 'E4-pos-rolled_back-valid'    { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'p2' 'rolled_back' 'high' (ResRB './snapshots/pre.snap') $null @())) -DependsOn @('p2') -Ledger $led -Index $index; 'rolled_back w/ rollback_ref => allowed' }
Expect-Ok 'E4-pos-human_accept-bound'   { Assert-NeoDependentContinuationAllowed -SubIndex (Idx @(Rec 'p3' 'human_accepted_fail' 'high' (ResHA '2026-07-03-B2B-ACCEPT-FAIL') $null @())) -DependsOn @('p3') -Ledger $led -Index $index; 'human_accepted_fail w/ ledger-bound gate => allowed' }

# ============================ E5 ROLLOVER / HANDOFF (D7) =====================
# Build ONE pristine program dir with schema-valid spec/constraint/risk/index + a proof file, then
# reference each by {artifact_id, content_hash}. Bad-hash fixtures pass a WRONG ref/proof hash at
# BUILD time so the packet stays self-consistent (self-hash matches) yet fails the independent
# re-hash on resume - no file tampering, no cross-contamination.
$prog = Join-Path $ScratchRoot 'program'
New-Item -ItemType Directory -Force -Path $prog | Out-Null
$spec = [pscustomobject][ordered]@{ spec_id = 'spec-1'; spec_version = '1.0'; intent = 'demo'; in_scope = @('f'); out_of_scope = @('n'); acceptance_criteria = @(@{ id = 'AC1'; statement = 'x'; verifiable_by = 'harness:x' }) }
$spec | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'spec-1' 'evidence' 'neo:project_spec' 'spec-author' 'strong_producer' 'strong_producer'); Set-NeoArtifactHash $spec
$con = [pscustomobject][ordered]@{ package_id = 'cp-1'; package_version = '1.0'; constraints = @(@{ id = 'C1'; statement = 'x'; kind = 'functional'; severity = 'high' }); test_harness_ref = @{ artifact_id = 'th'; content_hash = 'h' }; profile_risk_ref = @{ artifact_id = 'pr'; content_hash = 'h' } }
$con | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'cp-1' 'constraint' 'neo:constraint_package' 'constraint-editor' 'strong_producer' 'strong_producer'); Set-NeoArtifactHash $con
$risk = [pscustomobject][ordered]@{ register_id = 'rr-1'; register_version = '1.0'; risks = @(@{ id = 'r1'; area = 'general_feature'; risk_class = 'low'; never_batchable = $false; audit_tier = 'lightweight' }) }
$risk | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'rr-1' 'profile_risk' 'neo:risk_register' 'risk-author' 'strong_producer' 'strong_producer'); Set-NeoArtifactHash $risk
$si = [pscustomobject][ordered]@{ index_id = 'm1-index'; index_version = '4.0-P3-B'; records = @() }
$si | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'm1-index' 'evidence' 'neo:subsession_index' 'master-orchestrator' 'strong_producer' 'validator'); Set-NeoArtifactHash $si
Write-NeoJsonFile (Get-NeoProgramPath $prog 'PROJECT_SPEC') $spec
Write-NeoJsonFile (Get-NeoProgramPath $prog 'CONSTRAINT_PACKAGE') $con
Write-NeoJsonFile (Get-NeoProgramPath $prog 'RISK_REGISTER') $risk
Write-NeoJsonFile (Get-NeoProgramPath $prog 'SUBSESSION_INDEX') $si
$proofP = Join-Path $prog 'proof.txt'; Set-Content -LiteralPath $proofP -Value 'exit=0' -Encoding UTF8
$proofHash = Get-NeoSha256File $proofP

$specRef = Get-NeoArtifactRef $spec
$conRef  = Get-NeoArtifactRef $con
$riskRef = Get-NeoArtifactRef $risk
$idxRef  = Get-NeoArtifactRef $si
$goodLGS = @{ proof_ref = './proof.txt'; content_hash = $proofHash; summary = 'pristine green state' }

function New-TestPacket {
  param(
    $RiskRefOverride = $null, $LGSOverride = $null,
    [bool]$AllRefsHashed = $true, [bool]$NoOpenAmbiguity = $true, [bool]$NoPartialSubsession = $true
  )
  $rr = if ($null -ne $RiskRefOverride) { $RiskRefOverride } else { $riskRef }
  $lg = if ($null -ne $LGSOverride) { $LGSOverride } else { $goodLGS }
  New-NeoHandoffPacket -PacketId 'hp-1' -SpecRef $specRef -ConstraintRef $conRef -RiskRef $rr -IndexRef $idxRef `
    -OpenDeferrals @() -LastGreenState $lg -NextDecision 'dispatch ss-002' `
    -AllRefsHashed $AllRefsHashed -NoOpenAmbiguity $NoOpenAmbiguity -NoPartialSubsession $NoPartialSubsession `
    -Timestamp $TS -Index $index
}

# E5-pos / RESUME-E2E: emit a packet, write it, and resume from the packet ALONE (round-tripped).
Expect-Ok 'E5-pos-resume-e2e' {
  $pkt = New-TestPacket
  $hpPath = Join-Path $prog 'HANDOFF_PACKET.json'; Write-NeoJsonFile $hpPath $pkt
  $reread = Read-NeoJsonFile $hpPath
  $r = Assert-NeoPacketResumable -Packet $reread -ProgramRoot $prog -Index $index
  if (-not $r.resumable) { throw 'not resumable' }
  if ($r.next_decision -ne 'dispatch ss-002') { throw "next_decision=$($r.next_decision)" }
  'fresh master resumed from packet ALONE (schema+self-hash+not-stale+all *_ref re-hash pass)'
}

# E5a stale (no_open_ambiguity=false) => REJECT (+neuter-flip on the ==false guard).
Expect-Block 'E5a-stale-ambiguity' { Assert-NeoPacketResumable -Packet (New-TestPacket -NoOpenAmbiguity $false) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5a-neuter-flip' 'orch_rollover.ps1' `
  'if ($v -eq $false) { New-NeoBlock "handoff: not_stale_assertion.$f = false' `
  'if ($false) { New-NeoBlock "handoff: not_stale_assertion.$f = false' `
  { Assert-NeoPacketResumable -Packet (New-TestPacket -NoOpenAmbiguity $false) -ProgramRoot $prog -Index $index | Out-Null }

# E5b partial (all_refs_hashed=false) => REJECT (same G2 guard, distinct fixture + neuter-flip).
Expect-Block 'E5b-partial-refs' { Assert-NeoPacketResumable -Packet (New-TestPacket -AllRefsHashed $false) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5b-neuter-flip' 'orch_rollover.ps1' `
  'if ($v -eq $false) { New-NeoBlock "handoff: not_stale_assertion.$f = false' `
  'if ($false) { New-NeoBlock "handoff: not_stale_assertion.$f = false' `
  { Assert-NeoPacketResumable -Packet (New-TestPacket -AllRefsHashed $false) -ProgramRoot $prog -Index $index | Out-Null }

# A2 (default-case): a MISSING/NULL not_stale flag must REJECT via the G1 null/non-bool guard - NOT
# the ==false test (which would slip null since '$null -eq $false' is $false). Direct call bypasses
# schema so the CODE-layer guard is exercised; neutering G1 lets the null flag reach G2 => fail-open.
$integNull = @{ packet_self_hash = 'x'; built_at = $TS; not_stale_assertion = @{ all_refs_hashed = $true; no_open_ambiguity = $null; no_partial_subsession = $true } }
Expect-Block 'A2-null-flag-code-reject' { Assert-NeoNotStaleComplete $integNull | Out-Null }
Expect-NeuterFlip 'A2-null-flag-neuter-flip' 'orch_rollover.ps1' `
  'if (($null -eq $v) -or ($v -isnot [bool])) { New-NeoBlock "handoff: not_stale_assertion.$f missing/null/non-bool' `
  'if ($false) { New-NeoBlock "handoff: not_stale_assertion.$f missing/null/non-bool' `
  { Assert-NeoNotStaleComplete $integNull | Out-Null }

# A2 schema layer: neo:handoff_packet REQUIRES not_stale_assertion + all 3 subfields, and integrity
# + packet_self_hash - so a missing flag / missing integrity is a clean schema BLOCK (load-bearing).
Expect-Block 'A2-schema-missing-not_stale-flag' {
  $bad = [pscustomobject]@{ packet_id = 'hp-bad'; packet_version = 'v'; spec_ref = $specRef; constraint_package_ref = $conRef; risk_register_ref = $riskRef; subsession_index_ref = $idxRef; open_deferrals = @(); last_green_state = $goodLGS; next_decision = 'x'; integrity = @{ packet_self_hash = 'x'; built_at = $TS; not_stale_assertion = @{ all_refs_hashed = $true; no_open_ambiguity = $true } }; _provenance = (New-Env 'hp-bad' 'evidence' 'neo:handoff_packet' 'master-orchestrator' 'strong_producer' 'validator') }
  Assert-NeoValid $bad 'neo:handoff_packet' $index 'HANDOFF_PACKET(missing-flag)'
}
Expect-Block 'A2-schema-missing-integrity' {
  $bad = [pscustomobject]@{ packet_id = 'hp-bad2'; packet_version = 'v'; spec_ref = $specRef; constraint_package_ref = $conRef; risk_register_ref = $riskRef; subsession_index_ref = $idxRef; open_deferrals = @(); last_green_state = $goodLGS; next_decision = 'x'; _provenance = (New-Env 'hp-bad2' 'evidence' 'neo:handoff_packet' 'master-orchestrator' 'strong_producer' 'validator') }
  Assert-NeoValid $bad 'neo:handoff_packet' $index 'HANDOFF_PACKET(missing-integrity)'
}

# E5c hash-mismatch (packet_self_hash tampered) => REJECT (+neuter-flip on the self-hash compare).
function New-SelfTamperedPacket { $p = New-TestPacket; $p.integrity.packet_self_hash = ('d' * 64); return $p }
Expect-Block 'E5c-self-hash-mismatch' { Assert-NeoPacketResumable -Packet (New-SelfTamperedPacket) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5c-self-neuter-flip' 'orch_rollover.ps1' `
  'if ($storedSelf -cne $actualSelf) { New-NeoBlock "handoff: packet_self_hash mismatch' `
  'if ($false) { New-NeoBlock "handoff: packet_self_hash mismatch' `
  { Assert-NeoPacketResumable -Packet (New-SelfTamperedPacket) -ProgramRoot $prog -Index $index | Out-Null }

# E5c hash-mismatch (*_ref content_hash) => REJECT (+neuter-flip on the *_ref compare). Packet built
# with a WRONG risk_register_ref hash => self-consistent packet, mismatch on independent re-hash.
$badRiskRef = @{ artifact_id = $riskRef.artifact_id; content_hash = ('b' * 64) }
Expect-Block 'E5c-ref-hash-mismatch' { Assert-NeoPacketResumable -Packet (New-TestPacket -RiskRefOverride $badRiskRef) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5c-ref-neuter-flip' 'orch_rollover.ps1' `
  "if (`$actual -cne `$recorded) { New-NeoBlock ""handoff: *_ref '`$refName' content_hash mismatch" `
  "if (`$false) { New-NeoBlock ""handoff: *_ref '`$refName' content_hash mismatch" `
  { Assert-NeoPacketResumable -Packet (New-TestPacket -RiskRefOverride $badRiskRef) -ProgramRoot $prog -Index $index | Out-Null }

# E5-proof: last_green_state.proof_ref re-hash mismatch => REJECT (+neuter-flip on the proof compare).
$badLGS = @{ proof_ref = './proof.txt'; content_hash = ('c' * 64); summary = 'x' }
Expect-Block 'E5-proof-hash-mismatch' { Assert-NeoPacketResumable -Packet (New-TestPacket -LGSOverride $badLGS) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5-proof-neuter-flip' 'orch_rollover.ps1' `
  'if ($proofActual -cne $proofHash) { New-NeoBlock "handoff: last_green_state.proof_ref hash mismatch' `
  'if ($false) { New-NeoBlock "handoff: last_green_state.proof_ref hash mismatch' `
  { Assert-NeoPacketResumable -Packet (New-TestPacket -LGSOverride $badLGS) -ProgramRoot $prog -Index $index | Out-Null }

# ============================ B2b-FIX F1: proof_ref path traversal ==========
# proof_ref is attacker-influenceable. rooted/drive/UNC/backslash/'..'/empty => REJECT, and the
# resolved path must stay UNDER ProgramRoot. Load-bearing guard = Assert-NeoSafeRel; Assert-NeoContained
# is defense-in-depth. Each neuter-flip plants a matching file at the location the neutered path would
# resolve to, so removing the guard actually RESUMES (fail-open) - proving the guard is load-bearing.
function New-ProofPacket($proofRel, $proofContentHash) {
  New-TestPacket -LGSOverride @{ proof_ref = $proofRel; content_hash = $proofContentHash; summary = 'x' }
}
# rooted '/x' -> Assert-NeoContained resolves under root to <root>\x; plant it so a neutered SafeRel flips.
$rootedTarget = Join-Path $prog 'x'; Set-Content -LiteralPath $rootedTarget -Value 'rooted-bait' -Encoding UTF8
$rootedHash = Get-NeoSha256File $rootedTarget
Expect-Block 'E5-proof-rooted' { Assert-NeoPacketResumable -Packet (New-ProofPacket '/x' $rootedHash) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5-proof-rooted-neuter-flip' 'orch_rollover.ps1' `
  'Assert-NeoSafeRel $proofRel' '$null = $proofRel' `
  { Assert-NeoPacketResumable -Packet (New-ProofPacket '/x' $rootedHash) -ProgramRoot $prog -Index $index | Out-Null }
# backslash 'a\..\b' -> resolves under root to <root>\b; plant it (isolates SafeRel's backslash rule).
$bsTarget = Join-Path $prog 'b'; Set-Content -LiteralPath $bsTarget -Value 'backslash-bait' -Encoding UTF8
$bsHash = Get-NeoSha256File $bsTarget
Expect-Block 'E5-proof-backslash' { Assert-NeoPacketResumable -Packet (New-ProofPacket 'a\..\b' $bsHash) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5-proof-backslash-neuter-flip' 'orch_rollover.ps1' `
  'Assert-NeoSafeRel $proofRel' '$null = $proofRel' `
  { Assert-NeoPacketResumable -Packet (New-ProofPacket 'a\..\b' $bsHash) -ProgramRoot $prog -Index $index | Out-Null }
# true parent traversal '../escape' -> caught by SafeRel AND (defense-in-depth) Contained, so it flips
# only when the WHOLE containment is removed (both guards) reverting to the old vulnerable Join-Path;
# plant the bait OUTSIDE root at <scratch>\escape (parent of program root).
$escapeTarget = Join-Path $ScratchRoot 'escape'; Set-Content -LiteralPath $escapeTarget -Value 'outside-root-bait' -Encoding UTF8
$escapeHash = Get-NeoSha256File $escapeTarget
Expect-Block 'E5-proof-dotdot' { Assert-NeoPacketResumable -Packet (New-ProofPacket '../escape' $escapeHash) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5-proof-dotdot-neuter-flip' 'orch_rollover.ps1' `
  "  Assert-NeoSafeRel `$proofRel`n  `$proofPath = Assert-NeoContained `$ProgramRoot `$proofRel" `
  "  `$proofPath = Join-Path `$ProgramRoot (`$proofRel -replace '^\./', '')" `
  { Assert-NeoPacketResumable -Packet (New-ProofPacket '../escape' $escapeHash) -ProgramRoot $prog -Index $index | Out-Null }

# ============================ B2b-FIX F2: envelope content_hash on resume ====
# A stale/tampered _provenance.content_hash => REJECT, even when packet_self_hash is re-stamped
# self-consistent (so the self-hash guard does NOT mask it - the envelope guard is load-bearing).
function New-StaleProvenancePacket {
  $p = New-TestPacket
  $p._provenance.content_hash.value = ('e' * 64)   # tamper the envelope body hash
  Set-NeoHandoffSelfHash $p                          # re-stamp self-hash => self-consistent packet
  return $p
}
Expect-Block 'E5-stale-provenance' { Assert-NeoPacketResumable -Packet (New-StaleProvenancePacket) -ProgramRoot $prog -Index $index | Out-Null }
Expect-NeuterFlip 'E5-stale-provenance-neuter-flip' 'orch_rollover.ps1' `
  'if ($stored -cne $actual) { New-NeoBlock "handoff: _provenance.content_hash mismatch' `
  'if ($false) { New-NeoBlock "handoff: _provenance.content_hash mismatch' `
  { Assert-NeoPacketResumable -Packet (New-StaleProvenancePacket) -ProgramRoot $prog -Index $index | Out-Null }
# F2 POSITIVE (no false-reject): a VALID packet still resumes clean through the new envelope+proof guards.
Expect-Ok 'E5-pos-valid-no-false-reject' {
  $r = Assert-NeoPacketResumable -Packet (New-TestPacket) -ProgramRoot $prog -Index $index
  if (-not $r.resumable) { throw 'valid packet false-rejected' }
  'valid packet resumes clean through envelope+proof guards (F2 no false-reject; F1 accepts ./proof.txt)'
}

# ============================ STRUCTURAL (coordinate-not-validate) ==========
# G3c/G3d extended to orch_rollover.ps1: no auditor-writer reference; no AUDIT_RESULT rehash_check literal.
$rollNoComment = @(Get-Content -LiteralPath (Join-Path $orchDir 'orch_rollover.ps1') | Where-Object { $_ -notmatch '^\s*#' })
Record 'S1-rollover-no-auditor-writer-ref' (-not (($rollNoComment -join "`n") -match ('audi' + 'tor_stub'))) 'orch_rollover.ps1 has no separate-auditor-writer code reference'
Record 'S1-rollover-no-rehash_check-literal' (-not ((Get-Content -Raw -LiteralPath (Join-Path $orchDir 'orch_rollover.ps1')) -match 'rehash_check\s*=')) 'orch_rollover.ps1 writes no AUDIT_RESULT rehash_check literal'
# No enabled concurrent path: orch_rollover.ps1 declares no concurrent orchestration mode.
Record 'S2-rollover-no-concurrent-path' (-not ((Get-Content -Raw -LiteralPath (Join-Path $orchDir 'orch_rollover.ps1')) -match "orchestration_mode\s*=\s*'concurrent'")) 'orch_rollover.ps1 enables no concurrent orchestration path (serial-only)'

# ---- summary + residue-clean ------------------------------------------------
$neg = @($script:results | Where-Object { $_.kind -eq 'negative' })
$pos = @($script:results | Where-Object { $_.kind -eq 'positive' })
$negFail = @($neg | Where-Object { -not $_.pass }).Count
$posFail = @($pos | Where-Object { -not $_.pass }).Count
$fail = $negFail + $posFail
Write-Host ""
Write-Host ("NEGATIVE fail-closed GUARDS (load-bearing): {0}/{1} pass" -f ($neg.Count - $negFail), $neg.Count) -ForegroundColor $(if ($negFail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("POSITIVE / info checks (no-regression):     {0}/{1} pass" -f ($pos.Count - $posFail), $pos.Count) -ForegroundColor $(if ($posFail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("RESULT: {0} pass / {1} fail (of {2})" -f ($script:results.Count - $fail), $fail, $script:results.Count) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

if ($ProofOut) {
  $report = [pscustomobject]@{
    suite = 'NEO-4.0-P3-B2b-ROLLOVER'; timestamp = $TS
    negative_guards = $neg.Count; negative_pass = ($neg.Count - $negFail)
    positive_checks = $pos.Count; positive_pass = ($pos.Count - $posFail)
    fail = $fail; results = $script:results
  }
  ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ProofOut -Encoding UTF8
  Write-Host "proof written: $ProofOut"
}

$residueClean = $true
if (-not $KeepScratch) {
  Remove-Item -Recurse -Force -LiteralPath $ScratchRoot
  $residueClean = -not (Test-Path -LiteralPath $ScratchRoot)
  Write-Host ("residue-clean: {0} (scratch removed)" -f $residueClean)
}

if ($fail -eq 0 -and $residueClean) { exit 0 } else { exit 1 }
