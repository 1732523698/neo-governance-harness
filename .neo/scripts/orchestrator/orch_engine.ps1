# orch_engine.ps1 - NEO 4.0-P3-B (B1) minimal SERIAL master-orchestrator engine.
# ASCII-only (D10). Dot-source; defines functions only.
#
# CROWN JEWEL (coordinate-not-validate, v4 5.1): this library contains NO code
# path that writes an AUDIT_RESULT or a GO. It ASSEMBLES the audit bundle and
# CONSUMES an AUDIT_RESULT produced by a SEPARATE isolated auditor step
# (orch_auditor_stub.ps1, outside this library). Consume-NeoAuditResult BLOCKS
# when the auditor identity equals the master/builder identity, so the engine
# is architecturally incapable of self-approval.
. "$PSScriptRoot\orch_io.ps1"
# B2a wiring (W1): the enforcement layer (E1 tier / E2 gate / E3 routing). Still
# coordination only - it writes NO AUDIT_RESULT/GO (crown jewel preserved).
. "$PSScriptRoot\orch_enforce.ps1"
# B2b wiring (W4/W5): the lifecycle layer (E4 rollback/dependent-continuation / E5 rollover
# HANDOFF). Also coordination only - it writes NO AUDIT_RESULT/GO. (Idempotently re-sources
# orch_enforce -> orch_io -> orch_schema/orch_class beneath it; functions are simply redefined.)
. "$PSScriptRoot\orch_rollover.ps1"

$script:NeoMasterVersion = '4.0-P3-B'

function Get-NeoArtifactRef($obj) {
  $prov = Get-NeoProp $obj '_provenance'
  $ch = Get-NeoProp $prov 'content_hash'
  return @{ artifact_id = (Get-NeoProp $prov 'artifact_id'); content_hash = (Get-NeoProp $ch 'value') }
}

# ---- serial-only guard (crown jewel #2; A5) ---------------------------------
# 'concurrent' has NO enabled path: refused in code AND rejected by the enum in
# neo:master_checkpoint. Two independent fail-closed layers.
function Assert-NeoSerialMode([string]$Mode) {
  if ($Mode -cne 'serial') {
    New-NeoBlock "orchestration_mode '$Mode' refused - concurrent orchestration is designed-but-disabled (A5); only 'serial' has an enabled path"
  }
}

# ---- S0-S4: INIT a master run -----------------------------------------------
# Consumes 4 schema-valid program inputs from ProgramRoot; produces + writes
# MASTER_CHECKPOINT and SUBSESSION_INDEX to their exact <NAME>.json homes.
function Invoke-NeoInit {
  param(
    [string]$ProgramRoot, $Index, [string]$MasterId, [string]$SessionId,
    [string]$Timestamp, [string]$SnapshotDir, [string]$OrchestrationMode = 'serial'
  )
  if ([string]::IsNullOrEmpty($Timestamp)) { New-NeoBlock "Invoke-NeoInit requires a caller-supplied Timestamp" }
  Assert-NeoSerialMode $OrchestrationMode

  $spec       = Read-NeoProgramArtifact $ProgramRoot 'PROJECT_SPEC'       $Index
  $constraint = Read-NeoProgramArtifact $ProgramRoot 'CONSTRAINT_PACKAGE' $Index
  $arch       = Read-NeoProgramArtifact $ProgramRoot 'ARCHITECTURE'       $Index
  $risk       = Read-NeoProgramArtifact $ProgramRoot 'RISK_REGISTER'      $Index

  $sessionCheckpoint = [pscustomobject]@{
    session_id              = $SessionId
    current_task            = 'orchestrator-init'
    progress                = 'master run initialized from schema-valid spec/constraint/architecture/risk'
    next_step               = 'dispatch first sub-session'
    model_map               = @{}
    spend_so_far            = @{ unit = 'output_tokens'; amount = 0; is_estimate = $true }
    changed_files_baseline  = @()
    updated_at              = $Timestamp
  }

  $env = New-NeoEnvelope -ArtifactId $MasterId -ArtifactClass 'master_checkpoint' `
    -SchemaId 'neo:master_checkpoint' -SchemaVersion $script:NeoMasterVersion `
    -ProducerRole 'master-orchestrator' -ProducerClass 'strong_producer' `
    -ValidatorRole 'master-orchestrator' -ValidatorClass 'validator' `
    -Timestamp $Timestamp -DeclaredPaths @('./program/') -DeclaredSurfaces @('filesystem') `
    -SourcePackets @() -GateRef $null

  $mc = [pscustomobject]@{
    master_id             = $MasterId
    master_version        = $script:NeoMasterVersion
    session_checkpoint    = $sessionCheckpoint
    spec_ref              = (Get-NeoArtifactRef $spec)
    constraint_package_ref = (Get-NeoArtifactRef $constraint)
    risk_register_ref     = (Get-NeoArtifactRef $risk)
    subsession_index_ref  = @{ artifact_id = "$MasterId-index"; content_hash = 'UNSET' }
    open_deferrals        = @()
    orchestration_mode    = $OrchestrationMode
    _provenance           = $env
  }

  # SUBSESSION_INDEX (empty, append-only ledger)
  $ienv = New-NeoEnvelope -ArtifactId "$MasterId-index" -ArtifactClass 'evidence' `
    -SchemaId 'neo:subsession_index' -SchemaVersion $script:NeoMasterVersion `
    -ProducerRole 'master-orchestrator' -ProducerClass 'strong_producer' `
    -ValidatorRole 'master-orchestrator' -ValidatorClass 'validator' `
    -Timestamp $Timestamp -DeclaredPaths @('./program/') -DeclaredSurfaces @('filesystem') `
    -SourcePackets @() -GateRef $null
  $si = [pscustomobject]@{
    index_id      = "$MasterId-index"
    index_version = $script:NeoMasterVersion
    records       = @()
    _provenance   = $ienv
  }
  Set-NeoArtifactHash $si
  $siPath = Write-NeoProgramArtifact -ProgramRoot $ProgramRoot -Name 'SUBSESSION_INDEX' -Obj $si -Index $Index -SnapshotDir $SnapshotDir

  # bind the index ref (id + hash) into the checkpoint, then hash + write it
  $mc.subsession_index_ref.content_hash = (Get-NeoProp (Get-NeoProp $si '_provenance') 'content_hash').value
  Set-NeoArtifactHash $mc
  $mcPath = Write-NeoProgramArtifact -ProgramRoot $ProgramRoot -Name 'MASTER_CHECKPOINT' -Obj $mc -Index $Index -SnapshotDir $SnapshotDir

  return @{ master_checkpoint = $mc; subsession_index = $si; mc_path = $mcPath; si_path = $siPath }
}

# ---- serial DISPATCH: emit the sub-session START packet ----------------------
# INPUT_PACKET (allowlist + per-file content_hash + scope_boundary) wrapped in a
# SUBSESSION_START_PACKET. Every allowlisted file is hashed at build time.
function New-NeoStartPacket {
  param(
    [string]$PacketId, [string]$Goal, [string[]]$TestPlan, [string[]]$StopConditions,
    [string]$RiskClass, $AllowlistItems, [string[]]$ApprovedPaths, [string[]]$ProtectedPaths,
    [string[]]$Surfaces, $ReferencedArtifacts, [string]$Timestamp, $Index
  )
  if ([string]::IsNullOrEmpty($RiskClass)) { New-NeoBlock "start packet risk_class is required (UNKNOWN => BLOCK, A7)" }
  $allow = @()
  foreach ($it in @($AllowlistItems)) {
    $path = [string]$it.path
    if (-not (Test-Path -LiteralPath $path)) { New-NeoBlock "allowlist file missing (cannot hash): $path" }
    $allow += @{ path = $it.rel; content_hash = (Get-NeoSha256File $path); role = [string]$it.role }
  }
  $env = New-NeoEnvelope -ArtifactId $PacketId -ArtifactClass 'input_packet' `
    -SchemaId 'neo:input_packet' -SchemaVersion $script:NeoMasterVersion `
    -ProducerRole 'master-orchestrator' -ProducerClass 'strong_producer' `
    -ValidatorRole 'master-orchestrator' -ValidatorClass 'validator' `
    -Timestamp $Timestamp -DeclaredPaths $ApprovedPaths -DeclaredSurfaces $Surfaces `
    -SourcePackets @() -GateRef $null
  $ip = [pscustomobject]@{
    packet_id      = $PacketId
    packet_kind    = 'subsession_start'
    _provenance    = $env
    allowlist      = $allow
    scope_boundary = @{
      approved_paths    = @($ApprovedPaths)
      protected_paths   = @($ProtectedPaths)
      declared_surfaces = @($Surfaces)
      risk_tier         = $RiskClass
    }
    referenced_artifacts = @($ReferencedArtifacts)
    self_hash      = 'UNSET'
  }
  Set-NeoArtifactHash $ip
  Set-NeoPacketSelfHash $ip
  Assert-NeoValid $ip 'neo:input_packet' $Index 'INPUT_PACKET(subsession_start)'

  $sp = [pscustomobject]@{
    input_packet    = $ip
    goal            = $Goal
    test_plan       = @($TestPlan)
    stop_conditions = @($StopConditions)
    risk_class      = $RiskClass
  }
  Assert-NeoValid $sp 'neo:subsession_start_packet' $Index 'SUBSESSION_START_PACKET'
  return $sp
}

# ---- B2a GOVERNED DISPATCH (W2): the fail-closed loop entry --------------------
# Runs the enforcement precondition (E2 gate -> E3 routing -> E1 tier) BEFORE building
# the START packet. Any BLOCK aborts dispatch. This is the wiring the B1 loop deferred;
# New-NeoStartPacket stays the low-level packet builder (unchanged, so the B1 harness is
# a valid regression). Returns the packet PLUS the selected audit_tier the END must satisfy.
# This function performs COORDINATION only - it writes no AUDIT_RESULT/GO.
function Invoke-NeoGovernedDispatch {
  param(
    # governance inputs (fail-closed):
    $RiskRow, $ClassMap, $Ledger,
    [string]$GateRef, [string]$AppSlug, [string[]]$ScopePaths, [switch]$Batched,
    [string]$AsOf, [int]$MaxAgeDays = 0, $ProposedEdits, [switch]$IsDevProdRelease,
    # B2b E4 inputs (fail-closed dependent-continuation; OPTIONAL - a dispatch with no declared
    # dependency omits them, so DependsOn is empty and E4 is a no-op: B1/B2a callers unchanged):
    $SubIndex, [string[]]$DependsOn,
    # start-packet inputs (forwarded to New-NeoStartPacket):
    [string]$PacketId, [string]$Goal, [string[]]$TestPlan, [string[]]$StopConditions,
    [string]$RiskClass, $AllowlistItems, [string[]]$ApprovedPaths, [string[]]$ProtectedPaths,
    [string[]]$Surfaces, $ReferencedArtifacts, [string]$Timestamp, $Index
  )
  # E4 PRECONDITION (B2b W4) - runs FIRST, before E2 -> E3 -> E1. The master CANNOT continue past
  # a failed HIGH-risk (or any not-provably-safe) dependency without a valid rollback/human-accept
  # resolution (D8 2 / v4 5.6). Blocks before any packet is emitted. No-op when DependsOn is empty.
  [void](Assert-NeoDependentContinuationAllowed -SubIndex $SubIndex -DependsOn $DependsOn -Ledger $Ledger -Index $Index -AsOf $AsOf -MaxAgeDays $MaxAgeDays)

  # PRECONDITION - blocks before any packet is emitted.
  $decision = Assert-NeoDispatchAllowed -RiskRow $RiskRow -ClassMap $ClassMap -Ledger $Ledger `
    -GateRef $GateRef -AppSlug $AppSlug -ScopePaths $ScopePaths -Batched:$Batched `
    -AsOf $AsOf -MaxAgeDays $MaxAgeDays -ProposedEdits $ProposedEdits -IsDevProdRelease:$IsDevProdRelease

  # Cross-check: the dispatched risk_class must match the risk register row (no split-brain).
  $rowClass = [string](Get-NeoProp $RiskRow 'risk_class')
  if ($RiskClass -and ($RiskClass -cne $rowClass)) {
    New-NeoBlock "dispatch: start-packet risk_class '$RiskClass' != RISK_REGISTER row risk_class '$rowClass' => BLOCK (A7)"
  }

  $sp = New-NeoStartPacket -PacketId $PacketId -Goal $Goal -TestPlan $TestPlan -StopConditions $StopConditions `
    -RiskClass $RiskClass -AllowlistItems $AllowlistItems -ApprovedPaths $ApprovedPaths -ProtectedPaths $ProtectedPaths `
    -Surfaces $Surfaces -ReferencedArtifacts $ReferencedArtifacts -Timestamp $Timestamp -Index $Index

  return @{ start_packet = $sp; audit_tier = $decision.audit_tier; gate = $decision.gate }
}

# ---- ingest the builder's SUBSESSION_END_REPORT ------------------------------
function Read-NeoEndReport {
  param([string]$Path, $Index)
  $er = Read-NeoJsonFile $Path
  Assert-NeoValid $er 'neo:subsession_end_report' $Index 'SUBSESSION_END_REPORT'
  Assert-NeoArtifactHash $er 'SUBSESSION_END_REPORT'
  return $er
}

# ---- (e) ASSEMBLE the isolated-audit bundle (D3) -----------------------------
# Produces an INPUT_PACKET (packet_kind=audit_bundle_feed). This is COORDINATION,
# not validation: it packages allowlisted+hashed members for a SEPARATE auditor.
# It writes AUDIT_BUNDLE.json - never AUDIT_RESULT.
function New-NeoAuditBundle {
  param(
    [string]$BundleId, $MemberItems, [string[]]$ApprovedPaths, [string[]]$ProtectedPaths,
    [string[]]$Surfaces, [string]$RiskTier, [string]$Timestamp, $Index, [string]$OutPath
  )
  $allow = @()
  foreach ($m in @($MemberItems)) {
    $path = [string]$m.path
    $rel = [string]$m.rel
    Assert-NeoSafeRel $rel   # F2: reject rooted/drive/UNC/backslash/../empty BEFORE storing
    if (-not (Test-Path -LiteralPath $path)) { New-NeoBlock "audit-bundle member missing (cannot hash): $path" }
    $allow += @{ path = $rel; content_hash = (Get-NeoSha256File $path); role = [string]$m.role }
  }
  $env = New-NeoEnvelope -ArtifactId $BundleId -ArtifactClass 'audit_bundle' `
    -SchemaId 'neo:input_packet' -SchemaVersion $script:NeoMasterVersion `
    -ProducerRole 'master-assembler' -ProducerClass 'strong_producer' `
    -ValidatorRole 'master-assembler' -ValidatorClass 'validator' `
    -Timestamp $Timestamp -DeclaredPaths $ApprovedPaths -DeclaredSurfaces $Surfaces `
    -SourcePackets @() -GateRef $null
  $bundle = [pscustomobject]@{
    packet_id      = $BundleId
    packet_kind    = 'audit_bundle_feed'
    _provenance    = $env
    allowlist      = $allow
    scope_boundary = @{
      approved_paths    = @($ApprovedPaths)
      protected_paths   = @($ProtectedPaths)
      declared_surfaces = @($Surfaces)
      risk_tier         = $RiskTier
    }
    referenced_artifacts = @()
    self_hash      = 'UNSET'
  }
  Set-NeoArtifactHash $bundle
  Set-NeoPacketSelfHash $bundle
  Assert-NeoValid $bundle 'neo:input_packet' $Index 'AUDIT_BUNDLE(audit_bundle_feed)'
  if ($OutPath) { Write-NeoJsonFile $OutPath $bundle }
  return $bundle
}

# ---- (f) CONSUME an AUDIT_RESULT from the SEPARATE auditor --------------------
# READS ONLY. Validates the result, re-hashes the bundle members INDEPENDENTLY,
# enforces the fail-closed prose rules that the schema cannot express, and
# enforces auditor/master separation. Returns the (untrusted-source, now-checked)
# recommendation. There is deliberately NO write of an AUDIT_RESULT anywhere here.
function Read-NeoAuditResult {
  param(
    [string]$AuditResultPath, $Bundle, [string]$BundleDir,
    [string]$MasterIdentity, [string]$BuilderIdentity, $Index,
    [string]$RequiredTier   # B2a (W3): 'isolated'|'full_isolated' => an auditor-class result is MANDATORY
  )
  $ar = Read-NeoJsonFile $AuditResultPath
  Assert-NeoValid $ar 'neo:audit_result' $Index 'AUDIT_RESULT'
  Assert-NeoArtifactHash $ar 'AUDIT_RESULT'

  # F3 fail-closed: a NON-EMPTY -RequiredTier MUST be a known tier. A typo'd/crafted tier
  # (e.g. 'isolate', 'high', 'Isolated') must NOT be silently treated as no-tier and skip the
  # auditor mandate in block (0). Case-EXACT (the tier vocabulary is lowercase); empty legitimately
  # skips (B1 consume path passes no tier). This BLOCK precedes block (0) so no unknown tier slips through.
  if ($RequiredTier -and (@('lightweight', 'isolated', 'full_isolated') -cnotcontains $RequiredTier)) {
    New-NeoBlock "Read-NeoAuditResult: unknown -RequiredTier '$RequiredTier' (not lightweight|isolated|full_isolated) => BLOCK (D4/A7)"
  }

  # (0) B2a E1 tier binding (W3): where the selected tier demands an ISOLATED audit, the
  # consumed result MUST come from an auditor-class producer. A lightweight/validator-class
  # artifact check is NOT sufficient for an isolated tier. This makes the isolated
  # AUDIT_RESULT mandatory where the tier demands it (still coordination; no GO written).
  if (($RequiredTier -eq 'isolated') -or ($RequiredTier -eq 'full_isolated')) {
    $prodClass = [string](Get-NeoProp (Get-NeoProp (Get-NeoProp $ar '_provenance') 'producer_identity') 'model_class')
    if ($prodClass -cne 'auditor') {
      New-NeoBlock "AUDIT_RESULT producer model_class '$prodClass' is not 'auditor' but required audit_tier='$RequiredTier' demands an isolated auditor => BLOCK (D4/A7)"
    }
  }

  # (1) architectural separation: the auditor cannot be the master or the builder.
  $auditorId = [string]$ar.auditor_identity
  if ($auditorId -ceq $MasterIdentity) { New-NeoBlock "auditor_identity == master identity => self-approval BLOCKED (v4 5.1)" }
  if ($BuilderIdentity -and ($auditorId -ceq $BuilderIdentity)) { New-NeoBlock "auditor_identity == builder identity => self-approval BLOCKED (v4 5.1)" }
  $prodRole = [string](Get-NeoProp (Get-NeoProp $ar '_provenance') 'producer_identity').role
  if (($prodRole -like '*master*') -or ($prodRole -like '*orchestrator*')) {
    New-NeoBlock "AUDIT_RESULT producer role '$prodRole' is a master/orchestrator role => self-approval BLOCKED (v4 5.1)"
  }

  # (2) schema-prose (engine-enforced): all_members_matched=false MUST be NO-GO.
  $rc = Get-NeoProp $ar 'rehash_check'
  $claimedMatched = [bool](Get-NeoProp $rc 'all_members_matched')
  $rec = [string]$ar.recommendation
  if ((-not $claimedMatched) -and ($rec -cne 'NO-GO')) {
    New-NeoBlock "AUDIT_RESULT: all_members_matched=false but recommendation='$rec' (must be NO-GO) => BLOCK (A7)"
  }

  # (3) INDEPENDENT re-hash of every bundle member; the engine does not trust the
  #     auditor's claim. Any mismatch => the only acceptable verdict is NO-GO.
  $engineMismatches = @()
  foreach ($m in @($Bundle.allowlist)) {
    $relRaw = [string]$m.path
    Assert-NeoSafeRel $relRaw                        # F2: reject traversal BEFORE any join/read
    $mp = Assert-NeoContained $BundleDir $relRaw      # F2: resolve + assert contained under root
    if (-not (Test-Path -LiteralPath $mp)) { $engineMismatches += ($relRaw + ' (missing)'); continue }
    $actual = Get-NeoSha256File $mp
    if ($actual -cne ([string]$m.content_hash)) { $engineMismatches += $relRaw }
  }
  if ($engineMismatches.Count -gt 0) {
    if ($claimedMatched) { New-NeoBlock "bundle rehash mismatch on [$($engineMismatches -join ', ')] but AUDIT_RESULT claims all_members_matched=true => BLOCK (A7)" }
    if ($rec -cne 'NO-GO') { New-NeoBlock "bundle rehash mismatch on [$($engineMismatches -join ', ')] => recommendation must be NO-GO, got '$rec' => BLOCK (A7)" }
  }

  return @{ recommendation = $rec; auditor_identity = $auditorId; engine_rehash_mismatches = $engineMismatches }
}
