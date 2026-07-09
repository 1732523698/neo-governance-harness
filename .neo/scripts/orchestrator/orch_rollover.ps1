# orch_rollover.ps1 - NEO 4.0-P3-B2b lifecycle layer (COORDINATION only).
# ASCII-only (D10). Dot-source; defines functions only.
#
# CROWN JEWEL (coordinate-not-validate, v4 5.1): every function here is COORDINATION -
# decide whether a dependent sub-session may continue past a terminal dependency (E4), and
# emit / resume a rollover HANDOFF_PACKET (E5). NONE writes an AUDIT_RESULT or a GO. The
# audit itself stays the SEPARATE isolated auditor (a different file, never referenced here).
# This library contains NO 'rehash_check' result literal and never references/invokes the
# separate auditor writer (structural guards G3c/G3d extended to it by the B2b suite).
#
# SCOPE B2b: E4 rollback / dependent-continuation (D8 / v4 5.6) + E5 rollover / HANDOFF (D7 /
# v4 5.8). Concurrency stays DISABLED: ownership_lease is referenced READ-ONLY only (never a
# concurrent path); orchestration_mode stays 'serial' (Assert-NeoSerialMode, orch_engine.ps1).
. "$PSScriptRoot\orch_enforce.ps1"

# ============================================================================
# E4 - ROLLBACK / DEPENDENT-CONTINUATION (D8 / neo:subsession_index / neo:human_gate_ledger)
# ============================================================================
# The HARD RULE (v4 5.6 / D8 2): the master CANNOT continue past a failed HIGH-risk sub-session
# without either (a) rollback to the snapshot, or (b) explicit human acceptance of the failed
# state. A6 hardening: this applies to ANY dependent continuation. Machine-carried from the
# index alone (P0.1/F2,F3): each record carries depends_on + dependent_continuation_blocked_until
# + a structured resolution{mode,rollback_ref,gate_ref,dependency_impact}.

# Find a SUBSESSION_INDEX record by slug (append-only ledger). $null if absent.
function Get-NeoIndexRecord($SubIndex, [string]$Slug) {
  if ($null -eq $SubIndex) { return $null }
  foreach ($r in @($SubIndex.records)) {
    if ([string](Get-NeoProp $r 'slug') -ceq $Slug) { return $r }
  }
  return $null
}

# A terminal resolution is VALID iff, per mode, it carries the machine-representable proof the
# schema demands AND (for human acceptance) the gate_ref actually BINDS in the ledger - the
# cross-check the SCHEMA CANNOT express. Fail-closed: null resolution => BLOCK; unknown mode =>
# BLOCK; rolled_back w/o rollback_ref => BLOCK (E4c); human_accepted_fail w/o a ledger-bound
# gate_ref => BLOCK (E4b). $Ledger/$Index are only needed for the human_accepted_fail bind.
function Assert-NeoResolutionValid {
  param($Rec, $Ledger, $Index, [string]$AsOf, [int]$MaxAgeDays = 0)
  $res = Get-NeoProp $Rec 'resolution'
  if ($null -eq $res) { New-NeoBlock "resolution: terminal record '$([string](Get-NeoProp $Rec 'slug'))' carries no resolution => BLOCK (A7, D8)" }
  $mode = [string](Get-NeoProp $res 'mode')
  switch -c ($mode) {
    'rolled_back' {
      $rb = [string](Get-NeoProp $res 'rollback_ref')
      # E4c (engine defense-in-depth; the schema also requires this, but this line is the
      # load-bearing engine guard exercised by a direct call that bypasses schema validation).
      if ([string]::IsNullOrWhiteSpace($rb)) { New-NeoBlock "resolution: mode='rolled_back' with no rollback_ref (snapshot restore point) => BLOCK (E4c, D8)" }
    }
    'human_accepted_fail' {
      $gr = [string](Get-NeoProp $res 'gate_ref')
      if ([string]::IsNullOrWhiteSpace($gr)) { New-NeoBlock "resolution: mode='human_accepted_fail' with no gate_ref => BLOCK (E4b, D8)" }
      if ($null -eq $Ledger) { New-NeoBlock "resolution: mode='human_accepted_fail' but no HUMAN_GATE_LEDGER supplied to bind gate_ref '$gr' => BLOCK (A7, D8)" }
      # E4b LOAD-BEARING ledger cross-check (what the schema CANNOT do): the gate_ref must name a
      # real ledger entry. Mirrors Resolve-NeoGate's missing/unmatched barrier. The reuse of
      # Resolve-NeoGate below runs ONLY when the entry exists, so neutering THIS line lets a ghost
      # gate_ref slip through to a fail-open (the reuse is skipped because $match stays $null).
      $match = $null
      foreach ($e in @($Ledger.entries)) { if ([string](Get-NeoProp $e 'gate_ref') -ceq $gr) { $match = $e; break } }
      if ($null -eq $match) { New-NeoBlock "resolution: human_accepted_fail gate_ref '$gr' does not bind in HUMAN_GATE_LEDGER => BLOCK (E4b ledger cross-check, D8)" }
      # Defence-in-depth: reuse B2a Resolve-NeoGate to fully validate the bound acceptance gate
      # (app/expiry/self-coverage) against its own authorized_paths. Reached only for a real entry.
      if ($null -ne $match) { [void](Resolve-NeoGate -Ledger $Ledger -GateRef $gr -ScopePaths @(Get-NeoProp $match 'authorized_paths') -AsOf $AsOf -MaxAgeDays $MaxAgeDays) }
    }
    default { New-NeoBlock "resolution: unknown mode '$mode' (not rolled_back|human_accepted_fail) => BLOCK (A7, D8)" }
  }
  return $true
}

# A1 (fail-closed default-case): the COMPLETE dependency-status decision table. EVERY status is
# given an EXPLICIT allow-or-BLOCK verdict; nothing falls through to "allowed" implicitly. Only a
# provably-safe state proceeds: ended_pass; rolled_back w/ a rollback_ref; human_accepted_fail w/
# a ledger-bound gate_ref. Everything else - ended_fail, in_progress, dispatched, unknown/blank -
# BLOCKS dependent continuation.
#
#   status                | verdict                                              | guard
#   ----------------------+------------------------------------------------------+--------------------
#   (record missing)      | BLOCK (declared dependency absent from index)        | missing-record
#   blocked_until != null | BLOCK (marker still set; not yet resolved)           | marker guard
#   ended_pass            | ALLOW                                                | (safe)
#   rolled_back           | ALLOW iff resolution.rollback_ref present            | Assert-NeoResolutionValid (E4c)
#   human_accepted_fail   | ALLOW iff resolution.gate_ref binds in the ledger    | Assert-NeoResolutionValid (E4b)
#   ended_fail            | BLOCK (unresolved failure; incl. HIGH-risk, E4a)     | ended_fail guard
#   in_progress           | BLOCK (non-terminal)                                 | non-terminal guard
#   dispatched            | BLOCK (non-terminal)                                 | non-terminal guard
#   unknown/blank/other   | BLOCK (A7 fail-closed default)                       | default guard
#
# DependsOn empty => nothing to check => ALLOW (this is NOT fail-open: no declared dependency is
# a provably-safe state; it is the B1/B2a dispatch case, depends_on=@()). DependsOn non-empty but
# SubIndex null => BLOCK (cannot verify a declared dependency => UNKNOWN => A7).
function Assert-NeoDependentContinuationAllowed {
  param($SubIndex, [string[]]$DependsOn, $Ledger, $Index, [string]$AsOf, [int]$MaxAgeDays = 0)
  $deps = @($DependsOn | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($deps.Count -eq 0) { return $true }   # no declared dependency: nothing gates this continuation
  if ($null -eq $SubIndex) { New-NeoBlock "dependent-continuation: depends_on declared but no SUBSESSION_INDEX supplied to verify => BLOCK (A7, D8)" }

  foreach ($slug in $deps) {
    $rec = Get-NeoIndexRecord $SubIndex $slug
    if ($null -eq $rec) { New-NeoBlock "dependent-continuation: declared dependency '$slug' has no SUBSESSION_INDEX record => BLOCK (A7, D8)" }

    # Marker guard (independent, load-bearing): a non-null dependent_continuation_blocked_until means
    # the dependency's failure still blocks dependents; it clears to null ONLY on transition to
    # rolled_back / human_accepted_fail. Fail-closed even against an inconsistent record (e.g. a
    # marker left set on an otherwise-passing status).
    $blockedUntil = Get-NeoProp $rec 'dependent_continuation_blocked_until'
    if (-not [string]::IsNullOrWhiteSpace([string]$blockedUntil)) { New-NeoBlock "dependent-continuation: dependency '$slug' has dependent_continuation_blocked_until='$blockedUntil' set => BLOCK (D8 marker not cleared)" }

    $status = [string](Get-NeoProp $rec 'status')
    switch -c ($status) {
      'ended_pass'          { }   # provably safe
      'rolled_back'         { [void](Assert-NeoResolutionValid -Rec $rec -Ledger $Ledger -Index $Index -AsOf $AsOf -MaxAgeDays $MaxAgeDays) }
      'human_accepted_fail' { [void](Assert-NeoResolutionValid -Rec $rec -Ledger $Ledger -Index $Index -AsOf $AsOf -MaxAgeDays $MaxAgeDays) }
      'ended_fail'          { New-NeoBlock "dependent-continuation: dependency '$slug' status='ended_fail' (unresolved failure; no rollback/human-acceptance) => BLOCK (E4a, D8 2)" }
      'in_progress'         { New-NeoBlock "dependent-continuation: dependency '$slug' status='in_progress' (non-terminal) => BLOCK (A1 fail-closed, D8)" }
      'dispatched'          { New-NeoBlock "dependent-continuation: dependency '$slug' status='dispatched' (non-terminal) => BLOCK (A1 fail-closed, D8)" }
      default               { New-NeoBlock "dependent-continuation: dependency '$slug' status='$status' unknown/blank => BLOCK (A7 fail-closed default-case, D8)" }
    }
  }
  return $true
}

# ============================================================================
# E5 - ROLLOVER / HANDOFF (D7 / neo:handoff_packet)
# ============================================================================
# A fresh master resumes from the HANDOFF_PACKET ALONE. Carried by REFERENCE + HASH (never a
# bulky embed, A6). A stale / partial / ambiguous / hash-mismatched packet is REJECTED (fail-
# closed). packet_self_hash is computed over the packet body with integrity.packet_self_hash
# neutralized to the fixed sentinel 'UNSET' (so it excludes only itself), INCLUDING _provenance.

$script:NeoHandoffSelfSentinel = 'UNSET'

# Map each program *_ref to its exact <NAME>.json home for independent re-hashing (D7 4.2).
$script:NeoHandoffRefHomes = @{
  'spec_ref'              = 'PROJECT_SPEC'
  'constraint_package_ref' = 'CONSTRAINT_PACKAGE'
  'risk_register_ref'     = 'RISK_REGISTER'
  'subsession_index_ref'  = 'SUBSESSION_INDEX'
}

# Compute + stamp integrity.packet_self_hash (body incl _provenance, self-hash slot = sentinel).
function Set-NeoHandoffSelfHash($Packet) {
  $integ = Get-NeoProp $Packet 'integrity'
  if ($null -eq $integ) { New-NeoBlock "handoff self-hash: packet has no integrity block => BLOCK" }
  if ($integ -is [hashtable]) { $integ['packet_self_hash'] = $script:NeoHandoffSelfSentinel } else { $integ.packet_self_hash = $script:NeoHandoffSelfSentinel }
  $h = Get-NeoBodyHash $Packet @()
  if ($integ -is [hashtable]) { $integ['packet_self_hash'] = $h } else { $integ.packet_self_hash = $h }
}

# Shared build-order neutralization (B2b-FIX F2): hash the packet body with
# integrity.packet_self_hash temporarily set to the 'UNSET' sentinel, then RESTORE the recorded
# value. This reproduces EXACTLY the state New-NeoHandoffPacket was in when each hash was computed
# (content_hash first, packet_self_hash stamped after), so both the self-hash recompute (ExcludeKeys
# @()) and the envelope content_hash recompute (ExcludeKeys {_provenance,self_hash}) are false-reject
# free on a valid packet. Non-destructive: the slot is always restored before return.
function Get-NeoHandoffBodyHashNeutralized($Packet, [string[]]$ExcludeKeys) {
  $integ = Get-NeoProp $Packet 'integrity'
  if ($null -eq $integ) { New-NeoBlock "handoff hash: packet has no integrity block => BLOCK" }
  $stored = [string](Get-NeoProp $integ 'packet_self_hash')
  if ($integ -is [hashtable]) { $integ['packet_self_hash'] = $script:NeoHandoffSelfSentinel } else { $integ.packet_self_hash = $script:NeoHandoffSelfSentinel }
  $h = Get-NeoBodyHash $Packet $ExcludeKeys
  if ($integ -is [hashtable]) { $integ['packet_self_hash'] = $stored } else { $integ.packet_self_hash = $stored }
  return $h
}

# Recompute the packet_self_hash the same way (slot -> sentinel), restoring the recorded value.
function Get-NeoHandoffSelfHashActual($Packet) {
  return (Get-NeoHandoffBodyHashNeutralized $Packet @())
}

# B2b-FIX F2: verify the packet's OWN envelope content_hash on resume (every other artifact read
# calls Assert-NeoArtifactHash; the handoff packet did not). The content_hash was computed at BUILD
# time over the body excl {_provenance,self_hash} while integrity.packet_self_hash was still the
# 'UNSET' sentinel, so we MUST neutralize that slot before recomputing or a valid packet would
# false-reject. A stale/tampered _provenance.content_hash => REJECT (even if packet_self_hash was
# re-stamped self-consistent, this guard is the load-bearing one for that tamper).
function Assert-NeoHandoffEnvelopeHash($Packet) {
  $prov = Get-NeoProp $Packet '_provenance'
  if ($null -eq $prov) { New-NeoBlock "handoff: packet has no _provenance to verify => REJECT (A7)" }
  $stored = [string](Get-NeoProp (Get-NeoProp $prov 'content_hash') 'value')
  $actual = Get-NeoHandoffBodyHashNeutralized $Packet $script:NeoHashExclude
  if ($stored -cne $actual) { New-NeoBlock "handoff: _provenance.content_hash mismatch (stored=$stored actual=$actual) => REJECT (stale/tampered provenance, A6/A7)" }
  return $true
}

# E5 EMIT: build a schema-valid HANDOFF_PACKET on any mandatory rollover trigger (context
# threshold | unresolved ambiguity | high-risk transition | failed sub-session | master drift -
# the trigger is the caller's; this builds the artifact). refs are {artifact_id,content_hash};
# last_green_state is {proof_ref,content_hash,summary}. NotStale flags are the caller's honest
# assertions (a rollover built while a failure is unresolved MUST pass no_partial_subsession=false
# and be rejected on resume - D8 4).
function New-NeoHandoffPacket {
  param(
    [string]$PacketId, $SpecRef, $ConstraintRef, $RiskRef, $IndexRef,
    $OpenDeferrals, $LastGreenState, [string]$NextDecision,
    [bool]$AllRefsHashed, [bool]$NoOpenAmbiguity, [bool]$NoPartialSubsession,
    [string]$Timestamp, $Index
  )
  if ([string]::IsNullOrEmpty($Timestamp)) { New-NeoBlock "New-NeoHandoffPacket requires a caller-supplied Timestamp" }
  $env = New-NeoEnvelope -ArtifactId $PacketId -ArtifactClass 'evidence' `
    -SchemaId 'neo:handoff_packet' -SchemaVersion '4.0-P3-B' `
    -ProducerRole 'master-orchestrator' -ProducerClass 'strong_producer' `
    -ValidatorRole 'master-orchestrator' -ValidatorClass 'validator' `
    -Timestamp $Timestamp -DeclaredPaths @('./program/') -DeclaredSurfaces @('filesystem') `
    -SourcePackets @() -GateRef $null

  $packet = [pscustomobject]@{
    packet_id              = $PacketId
    packet_version         = '4.0-P3-B'
    spec_ref               = $SpecRef
    constraint_package_ref = $ConstraintRef
    risk_register_ref      = $RiskRef
    subsession_index_ref   = $IndexRef
    open_deferrals         = @($OpenDeferrals)
    last_green_state       = $LastGreenState
    next_decision          = $NextDecision
    integrity = @{
      packet_self_hash    = $script:NeoHandoffSelfSentinel
      built_at            = $Timestamp
      not_stale_assertion = @{
        all_refs_hashed      = $AllRefsHashed
        no_open_ambiguity    = $NoOpenAmbiguity
        no_partial_subsession = $NoPartialSubsession
      }
    }
    _provenance            = $env
  }
  # Envelope content_hash first (self-hash slot is the sentinel at this point), then the packet
  # self-hash over the whole body incl the finalized _provenance. Mirrors the input_packet order,
  # so the two hashes are not mutually circular.
  Set-NeoArtifactHash $packet
  Set-NeoHandoffSelfHash $packet
  Assert-NeoValid $packet 'neo:handoff_packet' $Index 'HANDOFF_PACKET'
  return $packet
}

# A2 (fail-closed default-case): the not_stale gate. A MISSING/NULL flag REJECTS - never a bare
# ==false test (in PS 5.1 '$null -eq $false' is $false, so a missing flag would slip a ==false
# test). Guard G1 catches null/non-bool FIRST; guard G2 then handles a real $false. G2's ==false
# is safe precisely because G1 already excluded null/non-bool before it - and it keeps the two
# guards INDEPENDENT (neutering G1 lets a null flag reach G2, where '$null -eq $false' is $false
# => fail-open; neutering G2 lets a real $false through => fail-open). Callable directly (tests
# bypass schema to prove each guard is load-bearing).
function Assert-NeoNotStaleComplete($Integ) {
  if ($null -eq $Integ) { New-NeoBlock "handoff: integrity block missing/null => REJECT (A2 fail-closed)" }
  $ps = Get-NeoProp $Integ 'packet_self_hash'
  if ([string]::IsNullOrWhiteSpace([string]$ps)) { New-NeoBlock "handoff: integrity.packet_self_hash missing/blank => REJECT (A2 fail-closed)" }
  $nsa = Get-NeoProp $Integ 'not_stale_assertion'
  if ($null -eq $nsa) { New-NeoBlock "handoff: integrity.not_stale_assertion missing/null => REJECT (A2 fail-closed)" }
  foreach ($f in @('all_refs_hashed', 'no_open_ambiguity', 'no_partial_subsession')) {
    $v = Get-NeoProp $nsa $f
    if (($null -eq $v) -or ($v -isnot [bool])) { New-NeoBlock "handoff: not_stale_assertion.$f missing/null/non-bool => REJECT (A2 fail-closed default-case)" }
    if ($v -eq $false) { New-NeoBlock "handoff: not_stale_assertion.$f = false => REJECT (E5a stale / E5b partial, D7 3)" }
  }
  return $true
}

# E5 RESUME: validate a HANDOFF_PACKET well enough to resume from it ALONE. Fail-closed order:
# schema-valid; integrity/self-hash present + not-stale (A2); packet_self_hash recompute; every
# program *_ref re-hashed against its <NAME>.json home; last_green_state.proof_ref re-hashed. Any
# mismatch / any false / any missing => REJECT (D7 3, A6/A7). ProgramRoot resolves the *_ref homes
# and the root-relative proof_ref.
function Assert-NeoPacketResumable {
  param($Packet, [string]$ProgramRoot, $Index)
  Assert-NeoValid $Packet 'neo:handoff_packet' $Index 'HANDOFF_PACKET(resume)'

  # A2 integrity + not-stale gate (missing integrity / missing packet_self_hash / any false-or-
  # missing not_stale flag => REJECT). Schema already requires these; this is the code-layer
  # defence-in-depth A2 mandates.
  $integ = Get-NeoProp $Packet 'integrity'
  [void](Assert-NeoNotStaleComplete $integ)

  # F2: verify the packet's OWN envelope content_hash (build-order neutralized). Wired AFTER the
  # not-stale gate so integrity is present. A stale/tampered _provenance.content_hash => REJECT.
  [void](Assert-NeoHandoffEnvelopeHash $Packet)

  # E5c: packet_self_hash recompute (tamper on ANY body field, incl _provenance, is caught here).
  $storedSelf = [string](Get-NeoProp $integ 'packet_self_hash')
  $actualSelf = Get-NeoHandoffSelfHashActual $Packet
  if ($storedSelf -cne $actualSelf) { New-NeoBlock "handoff: packet_self_hash mismatch (stored=$storedSelf actual=$actualSelf) => REJECT (E5c hash-mismatch, A6/A7)" }

  # E5c (*_ref variant): independently re-hash each program *_ref against its exact <NAME>.json home.
  foreach ($refName in $script:NeoHandoffRefHomes.Keys) {
    $ref = Get-NeoProp $Packet $refName
    $recorded = [string](Get-NeoProp $ref 'content_hash')
    $refHome = $script:NeoHandoffRefHomes[$refName]
    $p = Join-Path $ProgramRoot ("$refHome.json")
    if (-not (Test-Path -LiteralPath $p)) { New-NeoBlock "handoff: *_ref '$refName' home '$p' missing (cannot re-hash) => REJECT (A7)" }
    $obj = Read-NeoJsonFile $p
    $actual = Get-NeoBodyHash $obj $script:NeoHashExclude
    if ($actual -cne $recorded) { New-NeoBlock "handoff: *_ref '$refName' content_hash mismatch (recorded=$recorded actual=$actual) => REJECT (E5c hash-mismatch, A6)" }
  }

  # last_green_state.proof_ref re-hash (root-relative path -> file sha256).
  $lgs = Get-NeoProp $Packet 'last_green_state'
  $proofRel = [string](Get-NeoProp $lgs 'proof_ref')
  $proofHash = [string](Get-NeoProp $lgs 'content_hash')
  # F1: proof_ref is attacker-influenceable. Reject rooted/drive/UNC/backslash/'..'/empty, then
  # resolve + assert the path stays UNDER ProgramRoot (reuses the orch_schema path helpers). Without
  # this a proof_ref like '../../outside.txt' would resolve outside the program root and resume.
  Assert-NeoSafeRel $proofRel
  $proofPath = Assert-NeoContained $ProgramRoot $proofRel
  if (-not (Test-Path -LiteralPath $proofPath)) { New-NeoBlock "handoff: last_green_state.proof_ref '$proofRel' missing (cannot re-hash) => REJECT (A7)" }
  $proofActual = Get-NeoSha256File $proofPath
  if ($proofActual -cne $proofHash) { New-NeoBlock "handoff: last_green_state.proof_ref hash mismatch (recorded=$proofHash actual=$proofActual) => REJECT (E5c hash-mismatch, A6)" }

  return @{ resumable = $true; next_decision = [string](Get-NeoProp $Packet 'next_decision') }
}
