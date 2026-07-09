# orch_supervisor.ps1 - NEO 4.0-P4-AUTONOMY C2 COLD-BUILDER CONTEXT FIREWALL (COORDINATION only).
# ASCII-only (D10). Dot-source; defines functions only, runs nothing on load.
#
# CROWN JEWEL (coordinate-not-validate, mirrors orch_router.ps1): every function here is
# COORDINATION - it ASSEMBLES a firewalled sub-session START packet and re-checks one at
# consume time. NONE writes an AUDIT_RESULT, a GO, or ANYTHING to disk; NONE references or
# invokes the auditor stub. The assembler is a PURE function (returns an object); the
# spawn/write/ledger is C1+C3's, not C2's.
#
# SCOPE C2 (NEO_SELF_ITERATION_DESIGN_v3_1.md section 4, "C2 Cold BUILDER behind a CONTEXT
# FIREWALL", lines 106-108, SHA 0F4C8B81; + section 0 definitions):
#   Context reaches a sub-session ONLY through an ALLOWLIST of on-disk, root-relative, HASHED
#   text files. There is NO free-text prompt channel. The neo:input_packet schema's
#   additionalProperties:false is the STRUCTURAL half of the firewall (it forbids out-of-band
#   prompt keys). This library adds the SEMANTIC half: every allowlist member's role must be
#   one of the PERMITTED context-source classes; any FORBIDDEN source (supervisor
#   chain-of-thought, prior builder transcript, prior-round rationale) - or a blank/unknown
#   role - is a STOP, never a silent drop. "Builder context != auditor context != supervisor
#   context."
#
# DEFERRED to C1+C3 (Option A, Raphael-recorded at START): the ENGINE-SIDE SPAWN LEDGER
# (section 0 lines 19-27: the supervisor records a spawn entry at cold-spawn and the slot seam
# consumes an AUDIT_RESULT only on correlation). C2 builds the firewall SUPPLY - a validated,
# re-checkable builder packet; the loop that spawns + ledgers + correlates is C1+C3.
#
# REUSE (never reimplement): the path validators Assert-NeoSafeRel + Assert-NeoContained (the
# XC1 standing canonical-rel + containment rule), the file hasher Get-NeoSha256File, the
# schema validator Assert-NeoValid, the schema index Get-NeoSchemaIndex, the envelope +
# self-hash helpers New-NeoEnvelope / Set-NeoArtifactHash / Set-NeoPacketSelfHash /
# Assert-NeoPacketSelfHash, and New-NeoBlock. These live in the dot-sourced chain below.
#
# SCHEMA ROOT vs WRITE-BOUNDARY ROOT (C2-FIX F1): the NEO GOVERNANCE SCHEMAS resolve from the
# NEO GOVERNED ROOT (Resolve-NeoRoot from _neo_root.ps1, self-locating from $PSScriptRoot),
# INDEPENDENT of $RepoRoot. $RepoRoot is ONLY the containment / write-boundary root for the
# allowlist + approved/protected paths. This decouples schema resolution so a builder dispatched
# INTO AN APP REPO (whose tree has no .neo\schema) still validates against the NEO schemas.
#
# GOAL / TEST_PLAN are STRUCTURED INSTRUCTION metadata (not a free-text context channel): they
# carry the task instruction + the promised verification, NOT context. To keep the firewall
# closed in autonomous mode (where the SUPERVISOR authors goal/test_plan), they are SCANNED
# FAIL-CLOSED (C2-FIX F2): any $NeoForbiddenContextSources token appearing in them (case-
# insensitive substring) is a STOP, as is exceeding the stated length bounds - so a supervisor
# cannot smuggle forbidden context (supervisor CoT / prior transcript / prior rationale) through
# these fields. The hashed-allowlist remains the ONLY context channel.

. "$PSScriptRoot\..\_neo_root.ps1"   # -> Resolve-NeoRoot (self-locating NEO governed root; DOT-SOURCED, never edited) (C2-FIX F1)
. "$PSScriptRoot\orch_io.ps1"   # -> orch_schema.ps1 (+ orch_class.ps1): the full helper chain

# ---- the firewall vocabulary (frozen literals) ------------------------------
# PERMITTED context-source role-classes: the ONLY roles an allowlist member may carry. These
# are the four sources spec section 4 C2 sanctions: the dispatch, the approved-path artifacts,
# the current audit findings (verbatim), the current artifacts.
$script:NeoPermittedAllowlistRoles = @(
  'dispatch',
  'approved_path_artifact',
  'current_audit_finding',
  'current_artifact'
)

# FORBIDDEN context sources: an allowlist member carrying any of these is the exact leak C2
# exists to STOP (spec section 4 C2: NO supervisor chain-of-thought, NO prior builder
# transcript, NO prior-round rationale).
$script:NeoForbiddenContextSources = @(
  'supervisor_cot',
  'prior_builder_transcript',
  'prior_round_rationale'
)

# risk_class vocabulary - mirrors neo:subsession_start_packet.risk_class + the tier oracle
# (Resolve-NeoAuditTier): UNKNOWN/blank => STOP. No block->HIGH downgrade path.
$script:NeoBuilderRiskClasses = @('high', 'medium', 'low')

# ---- firewall primitives (shared by assembly + consume-side re-check) --------

# The SEMANTIC half of the firewall. STOP (never a silent drop) when a role is forbidden,
# blank, or not in the permitted set - naming the offending role.
function Assert-NeoAllowlistRolePermitted([string]$role) {
  if ([string]::IsNullOrWhiteSpace($role)) {
    New-NeoBlock "firewall: allowlist member has a blank/empty role => BLOCK (context source must be an explicit PERMITTED class)"
  }
  if ($script:NeoForbiddenContextSources -contains $role) {
    New-NeoBlock "firewall: FORBIDDEN context source '$role' in allowlist => BLOCK (spec C2: no supervisor_cot / prior_builder_transcript / prior_round_rationale)"
  }
  if (-not ($script:NeoPermittedAllowlistRoles -contains $role)) {
    New-NeoBlock "firewall: UNKNOWN allowlist role '$role' => BLOCK (permitted: $($script:NeoPermittedAllowlistRoles -join ', '))"
  }
}

# The PATH half of the firewall (XC1). REJECT, never normalize: root-relative canonical spelling
# (Assert-NeoSafeRel) then containment under RepoRoot (Assert-NeoContained). Returns the safe
# absolute path of the contained file. Used for allowlist members AND approved/protected paths.
function Resolve-NeoFirewallPath([string]$RepoRoot, [string]$rel, [string]$What) {
  if ([string]::IsNullOrWhiteSpace($RepoRoot)) { New-NeoBlock "firewall: RepoRoot is required for path containment" }
  Assert-NeoSafeRel $rel                                  # reject rooted/drive/UNC/backslash/../empty
  # C2-FIX F3: Assert-NeoSafeRel TOLERATES a './' prefix (strips '^\./'). Match the C6 router's
  # explicit discipline (orch_router.ps1): a './'-prefixed rel is not canonical repo-relative =>
  # REJECT, never normalize (for allowlist members AND approved/protected scope paths).
  if ($rel.StartsWith('./')) {
    New-NeoBlock "firewall: $What path '$rel' is './'-prefixed - not canonical repo-relative => REJECTED, never normalized (C2-FIX F3; XC1) => BLOCK"
  }
  return (Assert-NeoContained $RepoRoot $rel)             # reject escape; return contained full path
}

# Assert every approved/protected scope path is canonical-rel + contained (no read/hash; scope
# paths are a write-boundary declaration, files need not exist yet).
function Assert-NeoScopePathsSafe([string]$RepoRoot, $Paths, [string]$What) {
  foreach ($p in @($Paths)) {
    [void](Resolve-NeoFirewallPath $RepoRoot ([string]$p) $What)
  }
}

# C2-FIX F2: STRUCTURED-METADATA scan. goal/test_plan are instruction metadata, NOT a context
# channel; scan them fail-closed so a supervisor cannot smuggle forbidden context through them.
# Any $NeoForbiddenContextSources token as a case-insensitive substring => STOP; blank/oversize
# => STOP. Bounds (stated): goal <= 2000 chars; each test_plan line <= 500 chars; <= 40 lines.
$script:NeoGoalMaxChars         = 2000
$script:NeoTestPlanLineMaxChars = 500
$script:NeoTestPlanMaxLines     = 40
function Assert-NeoInstructionTextClean([string]$Text, [string]$What) {
  foreach ($tok in $script:NeoForbiddenContextSources) {
    if ($Text -and ($Text.ToLowerInvariant().Contains($tok.ToLowerInvariant()))) {
      New-NeoBlock "firewall: $What contains FORBIDDEN context token '$tok' => BLOCK (C2-FIX F2: goal/test_plan are structured metadata, not a context channel - no supervisor_cot / prior_builder_transcript / prior_round_rationale)"
    }
  }
}

# ---- (1) ASSEMBLE: New-NeoFirewalledBuilderPacket ----------------------------
# Returns a VALIDATED neo:subsession_start_packet OBJECT, fail-closed. WRITES NOTHING to disk.
# There is deliberately NO free-text prompt parameter: context is ONLY allowlisted hashed files.
# AllowlistItems: each member is an object carrying { rel; role } - `rel` is the root-relative
# './...' path (stored verbatim in the packet), `role` is a PERMITTED context-source class.
function New-NeoFirewalledBuilderPacket {
  param(
    [Parameter(Mandatory=$true)][string]$Goal,
    [Parameter(Mandatory=$true)][string[]]$ApprovedPaths,
    [Parameter(Mandatory=$true)][string[]]$ProtectedPaths,
    [Parameter(Mandatory=$true)][string]$RiskClass,
    [Parameter(Mandatory=$true)]$AllowlistItems,
    [Parameter(Mandatory=$true)][string[]]$TestPlan,
    [Parameter(Mandatory=$true)][string[]]$StopConditions,
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string[]]$DeclaredSurfaces,
    [string]$Timestamp = '2026-07-06T00:00:00Z',
    [string]$PacketId = 'neo-c2-builder-packet'
  )
  if ([string]::IsNullOrWhiteSpace($Goal)) { New-NeoBlock "firewall: goal is required (empty => BLOCK)" }

  # (b-freetext) F2: scan+bound the STRUCTURED-METADATA fields goal/test_plan (fail-closed).
  if ($Goal.Length -gt $script:NeoGoalMaxChars) {
    New-NeoBlock "firewall: goal exceeds bound ($($Goal.Length) > $($script:NeoGoalMaxChars) chars) => BLOCK (C2-FIX F2)"
  }
  Assert-NeoInstructionTextClean $Goal 'goal'
  $tpLines = @($TestPlan)
  if ($tpLines.Count -gt $script:NeoTestPlanMaxLines) {
    New-NeoBlock "firewall: test_plan exceeds bound ($($tpLines.Count) > $($script:NeoTestPlanMaxLines) lines) => BLOCK (C2-FIX F2)"
  }
  foreach ($ln in $tpLines) {
    $lnStr = [string]$ln
    if ($lnStr.Length -gt $script:NeoTestPlanLineMaxChars) {
      New-NeoBlock "firewall: test_plan line exceeds bound ($($lnStr.Length) > $($script:NeoTestPlanLineMaxChars) chars) => BLOCK (C2-FIX F2)"
    }
    Assert-NeoInstructionTextClean $lnStr 'test_plan line'
  }

  # (c) RISK: mirror the oracle vocabulary; UNKNOWN/blank => STOP.
  if ([string]::IsNullOrWhiteSpace($RiskClass) -or -not ($script:NeoBuilderRiskClasses -contains $RiskClass)) {
    New-NeoBlock "firewall: risk_class '$RiskClass' is not one of high|medium|low => BLOCK (UNKNOWN => STOP, A7)"
  }

  # (b-scope) PATHS: approved/protected paths must be canonical-rel + contained (REJECT, not normalize).
  Assert-NeoScopePathsSafe $RepoRoot $ApprovedPaths 'approved_path'
  Assert-NeoScopePathsSafe $RepoRoot $ProtectedPaths 'protected_path'

  # (a) FIREWALL + (b-allowlist) PATHS: per member - role permitted, path safe+contained, hash disk.
  $allow = @()
  foreach ($it in @($AllowlistItems)) {
    # (a-shape) F4: member shape is FAIL-CLOSED - a non-null object whose member-name set is
    # EXACTLY {rel, role}; rel and role each a STRING (never coerced). Stray key / non-string
    # => STOP. Member names are read as the CALLER supplied them: hashtable => .Keys;
    # PSCustomObject/other => PSObject.Properties.Name (NOT a hashtable's own .NET properties).
    if ($null -eq $it) { New-NeoBlock "firewall: allowlist member is null => BLOCK (C2-FIX F4)" }
    if ($it -is [System.Collections.IDictionary]) {
      $keys = @($it.Keys | ForEach-Object { [string]$_ })
    } else {
      $keys = @($it.PSObject.Properties | ForEach-Object { $_.Name })
    }
    foreach ($k in $keys) {
      if ($k -ne 'rel' -and $k -ne 'role') {
        New-NeoBlock "firewall: allowlist member has STRAY key '$k' - shape must be EXACTLY {rel, role} => BLOCK (C2-FIX F4)"
      }
    }
    if (-not ($keys -contains 'rel'))  { New-NeoBlock "firewall: allowlist member missing 'rel' => BLOCK (C2-FIX F4)" }
    if (-not ($keys -contains 'role')) { New-NeoBlock "firewall: allowlist member missing 'role' => BLOCK (C2-FIX F4)" }
    if (-not ($it.rel -is [string]))  { New-NeoBlock "firewall: allowlist member 'rel' is not a STRING => BLOCK, never coerced (C2-FIX F4)" }
    if (-not ($it.role -is [string])) { New-NeoBlock "firewall: allowlist member 'role' is not a STRING => BLOCK, never coerced (C2-FIX F4)" }
    $role = [string]$it.role
    $rel  = [string]$it.rel
    Assert-NeoAllowlistRolePermitted $role                       # semantic half (STOP on forbidden/blank/unknown)
    $full = Resolve-NeoFirewallPath $RepoRoot $rel 'allowlist_member'   # path half (STOP on dodge/escape)
    if (-not (Test-Path -LiteralPath $full)) {
      New-NeoBlock "firewall: allowlist file missing on disk (cannot hash): '$rel' => BLOCK"
    }
    $allow += @{ path = $rel; content_hash = (Get-NeoSha256File $full); role = $role }
  }

  $surfaces = @(); if ($DeclaredSurfaces) { $surfaces = @($DeclaredSurfaces) }

  # (d) ASSEMBLE the input_packet (packet_kind='subsession_start') - mirrors the engine's
  # New-NeoStartPacket construction exactly, then hashes + self-hashes via the reused helpers.
  $env = New-NeoEnvelope -ArtifactId $PacketId -ArtifactClass 'input_packet' `
    -SchemaId 'neo:input_packet' -SchemaVersion '4.0-P4-C2' `
    -ProducerRole 'master-orchestrator' -ProducerClass 'strong_producer' `
    -ValidatorRole 'master-orchestrator' -ValidatorClass 'validator' `
    -Timestamp $Timestamp -DeclaredPaths $ApprovedPaths -DeclaredSurfaces $surfaces `
    -SourcePackets @() -GateRef $null
  $ip = [pscustomobject]@{
    packet_id      = $PacketId
    packet_kind    = 'subsession_start'
    _provenance    = $env
    allowlist      = $allow
    scope_boundary = @{
      approved_paths    = @($ApprovedPaths)
      protected_paths   = @($ProtectedPaths)
      declared_surfaces = @($surfaces)
      risk_tier         = $RiskClass
    }
    referenced_artifacts = @()          # C2 supplies raw allowlisted files only; no semantic refs
    self_hash      = 'UNSET'
  }
  Set-NeoArtifactHash $ip               # stamps _provenance.content_hash (reused)
  Set-NeoPacketSelfHash $ip             # stamps self_hash (reused; AFTER Set-NeoArtifactHash)

  # Assemble + VALIDATE the subsession_start_packet wrapper against the LIVE schema.
  $sp = [pscustomobject]@{
    input_packet    = $ip
    goal            = $Goal
    test_plan       = @($TestPlan)
    stop_conditions = @($StopConditions)
    risk_class      = $RiskClass
  }
  # C2-FIX F1: schema index resolves from the NEO GOVERNED ROOT (Resolve-NeoRoot), NOT $RepoRoot
  # (which may be an app tree lacking .neo\schema). RepoRoot stays the write-boundary root only.
  $neoRoot   = Resolve-NeoRoot $PSScriptRoot
  $schemaDir = Join-Path $neoRoot '.neo\schema'
  $Index = Get-NeoSchemaIndex $schemaDir
  Assert-NeoValid $sp 'neo:subsession_start_packet' $Index 'SUBSESSION_START_PACKET(firewalled)'
  return $sp                            # PURE: nothing written to disk (spawn/write is C1+C3)
}

# ---- (2) CONSUME-SIDE re-check: Test-NeoBuilderPacketFirewall -----------------
# Re-derives the firewall assertions over an ALREADY-ASSEMBLED packet (the check a future
# loop/auditor runs before trusting a packet). Check==use: the SAME role + path rules enforced
# at assembly are re-checkable at consume, PLUS an on-disk re-hash that catches post-assembly
# tamper. Any failure => BLOCK. Returns $true on success.
function Test-NeoBuilderPacketFirewall {
  param(
    [Parameter(Mandatory=$true)]$Packet,
    [Parameter(Mandatory=$true)][string]$RepoRoot
  )
  $ip = Get-NeoProp $Packet 'input_packet'
  if ($null -eq $ip) { New-NeoBlock "firewall re-check: packet has no input_packet => BLOCK" }

  # self_hash integrity (reused consume-side helper).
  Assert-NeoPacketSelfHash $ip 'INPUT_PACKET(firewall re-check)'

  # schema re-validation against the live schema.
  # C2-FIX F1: schema index from the NEO GOVERNED ROOT (Resolve-NeoRoot), NOT $RepoRoot.
  $neoRoot   = Resolve-NeoRoot $PSScriptRoot
  $schemaDir = Join-Path $neoRoot '.neo\schema'
  $Index = Get-NeoSchemaIndex $schemaDir
  Assert-NeoValid $Packet 'neo:subsession_start_packet' $Index 'SUBSESSION_START_PACKET(firewall re-check)'

  # risk_class re-check (defence in depth; the schema enum already gates it).
  $risk = [string](Get-NeoProp $Packet 'risk_class')
  if (-not ($script:NeoBuilderRiskClasses -contains $risk)) {
    New-NeoBlock "firewall re-check: risk_class '$risk' not high|medium|low => BLOCK"
  }

  # C2-FIX-2: goal/test_plan re-scan at CONSUME (check==use parity). The input_packet
  # self_hash above covers ONLY input_packet, NOT the wrapper fields goal/test_plan, so a
  # packet mutated after assembly (or hand-crafted) could smuggle forbidden context through
  # them. Re-enforce the IDENTICAL assembler rules by REUSING the same helper + bounds.
  # (Blank goal is already gated by the schema's minLength:1 at the re-validation above;
  # the explicit blank BLOCK here is stated defence-in-depth parity with the assembler.)
  $goal = [string](Get-NeoProp $Packet 'goal')
  if ([string]::IsNullOrWhiteSpace($goal)) {
    New-NeoBlock "firewall re-check: goal is required (empty => BLOCK) (C2-FIX-2)"
  }
  if ($goal.Length -gt $script:NeoGoalMaxChars) {
    New-NeoBlock "firewall re-check: goal exceeds bound ($($goal.Length) > $($script:NeoGoalMaxChars) chars) => BLOCK (C2-FIX-2)"
  }
  Assert-NeoInstructionTextClean $goal 'goal'
  $tpLines = @(Get-NeoProp $Packet 'test_plan')
  if ($tpLines.Count -gt $script:NeoTestPlanMaxLines) {
    New-NeoBlock "firewall re-check: test_plan exceeds bound ($($tpLines.Count) > $($script:NeoTestPlanMaxLines) lines) => BLOCK (C2-FIX-2)"
  }
  foreach ($ln in $tpLines) {
    $lnStr = [string]$ln
    if ($lnStr.Length -gt $script:NeoTestPlanLineMaxChars) {
      New-NeoBlock "firewall re-check: test_plan line exceeds bound ($($lnStr.Length) > $($script:NeoTestPlanLineMaxChars) chars) => BLOCK (C2-FIX-2)"
    }
    Assert-NeoInstructionTextClean $lnStr 'test_plan line'
  }

  # per allowlist member: role permitted, path safe+contained, hash matches disk.
  $allow = @(Get-NeoProp $ip 'allowlist')
  foreach ($m in $allow) {
    $role = [string](Get-NeoProp $m 'role')
    $rel  = [string](Get-NeoProp $m 'path')
    $stored = [string](Get-NeoProp $m 'content_hash')
    Assert-NeoAllowlistRolePermitted $role
    $full = Resolve-NeoFirewallPath $RepoRoot $rel 'allowlist_member'
    if (-not (Test-Path -LiteralPath $full)) {
      New-NeoBlock "firewall re-check: allowlist file missing on disk: '$rel' => BLOCK"
    }
    $actual = Get-NeoSha256File $full
    if ($stored -cne $actual) {
      New-NeoBlock "firewall re-check: content_hash mismatch for '$rel' (stored=$stored actual=$actual) => BLOCK (post-assembly tamper)"
    }
  }

  # scope paths re-check (canonical-rel + contained).
  $sb = Get-NeoProp $ip 'scope_boundary'
  Assert-NeoScopePathsSafe $RepoRoot (Get-NeoProp $sb 'approved_paths') 'approved_path'
  Assert-NeoScopePathsSafe $RepoRoot (Get-NeoProp $sb 'protected_paths') 'protected_path'
  return $true
}

# =============================================================================
# ---- C1C3-S1: LEDGERS + BREAKER CORE (ADDITIVE, 2026-07-06) ------------------
# =============================================================================
# SCOPE C1C3-S1 (NEO_SELF_ITERATION_DESIGN_v3_1.md SHA 0F4C8B81: section 4 "C3
# Convergence loop + CIRCUIT-BREAKER" lines 110-125 + section 0 spawn-ledger
# correlation lines 19-27 + NB-2 round counting line 310). Everything below is
# ADDITIVE to the frozen C2 firewall above: the two public firewall functions
# and every C2 helper are untouched.
#
# WRITE BOUNDARY: these functions WRITE ONLY under an EXPLICIT caller-supplied
# -RunRoot - never a default path, never outside it. Every path join goes
# through the reused Assert-NeoSafeRel + Assert-NeoContained. Nothing here
# writes into .neo\** at runtime; fixtures use scratch RunRoots.
#
# WRITE-AHEAD ORDERING (spec C3 + NB-2): the ledger write happens BEFORE the
# dispatch it counts. At the cap the LEDGER ENTRY STILL LANDS (append it) and
# the function returns refused=$true - it is the DISPATCH that gets refused,
# never the ledger write. A failed append ABORTS the dispatch (STOP). ROUND
# COUNTING: the initial build dispatch is round 0 (Kind='initial', never
# counted); "max_fix_rounds_per_slice" caps FIX dispatches (rounds 1..cap);
# the (cap+1)-th fix entry lands refused=$true reason CAP_FIX_ROUNDS.
#
# LEDGER FAILURE SEMANTICS (spec I6/N2): ANY ledger read/parse/schema/
# monotonicity failure => STOP + surface, NEVER repair-and-continue; resume
# without a readable ledger (or manifest) => STOP.
#
# SPAWN CORRELATION - HONESTY HEADER (spec sec-0 lines 19-27 + NB-4): the spawn
# ledger + Assert-NeoSpawnCorrelatedSlot are TAMPER-EVIDENT defense-in-depth on
# a shared single-user filesystem (the ledger is supervisor-writable in
# principle), NOT tamper-proof; the spawn ledger is therefore END evidence. The
# gate correlates the ISOLATED auditor's AUDIT_RESULT only - the external lane
# NEVER fills the slot. A supervisor-crafted auditor-labeled AUDIT_RESULT
# without a correlated spawn entry CANNOT fill the slot; stale/replay (same
# identity, different bundle_ref or round) is REFUSED.
#
# MACHINE-READABLE REASON CODES: every STOP/refusal below carries a stable
# 'reason_code=<CODE>' token in the NEO-BLOCK message (or a 'reason' member in
# a refusal return) so the C1C3-S3 loop can map it to the P8 friction classes:
#   CAPS_INVALID / MANIFEST_EXISTS / CAP_FIX_ROUNDS / CAP_EXTERNAL_CALLS /
#   CAP_WALL_CLOCK / LEDGER_FAILURE / ROUND_MISMATCH / SPAWN_INVALID /
#   SPAWN_UNCORRELATED
# (Send-NeoGateNotification is NOT wired here by design decision D4: the
# structural hook is the C1C3-S3 loop choke point.)

# ---- S1 vocabulary (frozen literals) -----------------------------------------
# The four MANDATORY D-CAP members (DEF-P7 attestation in force): required
# config, never defaults - blank/zero/negative/unparseable/missing ANY => STOP.
$script:NeoRunCapNames = @(
  'max_fix_rounds_per_slice',
  'max_external_calls',
  'max_wall_clock_hours',
  'max_spend'
)
$script:NeoRunManifestLeaf       = 'run_manifest.json'
$script:NeoAttemptLedgerLeaf     = 'attempt_ledger.jsonl'
$script:NeoExternalCallLedgerLeaf = 'external_call_ledger.jsonl'
$script:NeoSpawnLedgerLeaf       = 'spawn_ledger.jsonl'
# External calls are RUN-scoped, not slice-scoped: they live in their own file
# under this reserved pseudo-slice id, REUSING neo:attempt_ledger_entry with
# kind='external_call' (the schema-add stays exactly 3 files).
$script:NeoRunExternalSliceId    = '__run__'
$script:NeoRunTimestampPattern   = '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

# ---- S1 primitives -----------------------------------------------------------

# Schema index from the NEO GOVERNED ROOT (Resolve-NeoRoot; C2-FIX F1 pattern):
# a run dispatched into an app tree still validates against the NEO schemas.
function Get-NeoRunSchemaIndex {
  $neoRoot   = Resolve-NeoRoot $PSScriptRoot
  $schemaDir = Join-Path $neoRoot '.neo\schema'
  return (Get-NeoSchemaIndex $schemaDir)
}

# Resolve a run-state file path STRICTLY under the caller-supplied RunRoot.
# RunRoot must be an existing directory (creating run trees is the loop's job);
# the leaf goes through the reused safe-rel + containment validators (XC1).
function Resolve-NeoRunStatePath([string]$RunRoot, [string]$Leaf) {
  if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE run-state: an EXPLICIT -RunRoot is required (never a default path) => STOP"
  }
  if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE run-state: RunRoot '$RunRoot' is not an existing directory => STOP"
  }
  Assert-NeoSafeRel $Leaf
  return (Assert-NeoContained $RunRoot $Leaf)
}

# Strict UTC timestamp gate: exact 'yyyy-MM-ddTHH:mm:ssZ' shape + a real
# calendar instant. Malformed => STOP under the caller-named reason code
# (never "not yet tripped" / never a silent default). Returns the [datetime].
function ConvertFrom-NeoRunTimestamp([string]$Value, [string]$What, [string]$ReasonCode) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    New-NeoBlock "reason_code=$ReasonCode ${What}: timestamp is blank => STOP"
  }
  if ($Value -notmatch $script:NeoRunTimestampPattern) {
    New-NeoBlock "reason_code=$ReasonCode ${What}: timestamp '$Value' is not canonical UTC 'yyyy-MM-ddTHH:mm:ssZ' => STOP"
  }
  try {
    return ([datetime]::ParseExact($Value, "yyyy-MM-dd'T'HH:mm:ss'Z'",
      [System.Globalization.CultureInfo]::InvariantCulture,
      ([System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)))
  } catch {
    New-NeoBlock "reason_code=$ReasonCode ${What}: timestamp '$Value' does not parse as a real UTC instant => STOP"
  }
}

# One cap value -> a strictly-positive [double]. Blank/unparseable/NaN/Inf/
# zero/negative => STOP CAPS_INVALID ("never no-cap-by-default", spec C3).
function ConvertTo-NeoRunCapNumber($Value, [string]$CapName) {
  if ($null -eq $Value -or ($Value -is [bool])) {
    New-NeoBlock "reason_code=CAPS_INVALID cap '$CapName' is missing or non-numeric => STOP (caps are REQUIRED config, never defaults)"
  }
  $num = $null
  if (Test-NeoIsNumber $Value) {
    $num = [double]$Value
  } elseif ($Value -is [string]) {
    $parsed = 0.0
    if ([double]::TryParse($Value, [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
      $num = $parsed
    }
  }
  if ($null -eq $num -or [double]::IsNaN($num) -or [double]::IsInfinity($num)) {
    New-NeoBlock "reason_code=CAPS_INVALID cap '$CapName' value '$Value' is unparseable => STOP (caps are REQUIRED config, never defaults)"
  }
  if ($num -le 0) {
    New-NeoBlock "reason_code=CAPS_INVALID cap '$CapName' value '$num' is not > 0 (zero/negative) => STOP (never no-cap-by-default)"
  }
  return $num
}

# Validate the caps object fail-closed: member-name set EXACTLY the four D-CAP
# names (stray member => STOP, mirrors the F4 shape discipline), each strictly
# positive + parseable. Returns a normalized hashtable of [double]s.
function Assert-NeoRunCapsValid($Caps, [string]$Label) {
  if (-not (Test-NeoIsObject $Caps)) {
    New-NeoBlock "reason_code=CAPS_INVALID ${Label}: caps must be an object carrying ALL FOUR of $($script:NeoRunCapNames -join ', ') => STOP"
  }
  foreach ($k in @(Get-NeoPropNames $Caps)) {
    if (-not ($script:NeoRunCapNames -contains [string]$k)) {
      New-NeoBlock "reason_code=CAPS_INVALID ${Label}: caps has STRAY member '$k' - member set must be EXACTLY the four D-CAP names => STOP"
    }
  }
  $norm = @{}
  foreach ($name in $script:NeoRunCapNames) {
    if (-not (Test-NeoHasProp $Caps $name)) {
      New-NeoBlock "reason_code=CAPS_INVALID ${Label}: cap '$name' is MISSING => STOP (missing any budget => STOP, spec C3)"
    }
    $norm[$name] = (ConvertTo-NeoRunCapNumber (Get-NeoProp $Caps $name) $name)
  }
  return $norm
}

# Strict JSONL raw-line reader: whole-file read, exact line split, at most ONE
# trailing empty line (the final newline); any interior blank line => STOP.
function Read-NeoRunJsonlRawLines([string]$Path, [string]$Label) {
  $raw = $null
  try { $raw = [System.IO.File]::ReadAllText($Path) }
  catch { New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: ledger unreadable at '$Path' => STOP" }
  $lines = @(($raw -replace "`r`n", "`n") -split "`n")
  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
    $lines = @($lines | Select-Object -First ($lines.Count - 1))
  }
  if ($lines.Count -eq 0) {
    New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: ledger file exists but is EMPTY => STOP (never treated-as-absent)"
  }
  $n = 0
  foreach ($ln in $lines) {
    $n++
    if ([string]::IsNullOrWhiteSpace($ln)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: blank line at line $n => STOP (append-only JSONL, never repaired)"
    }
  }
  return ,$lines
}

# Full fail-closed ledger read: every line parseable + schema-valid + run_id
# bound to the manifest. Returns the parsed entries in file order.
function Read-NeoRunLedgerEntries {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$SchemaId,
    [Parameter(Mandatory=$true)]$Index,
    [Parameter(Mandatory=$true)][string]$Label,
    [Parameter(Mandatory=$true)][string]$ExpectedRunId
  )
  $lines = Read-NeoRunJsonlRawLines $Path $Label
  $entries = @()
  $n = 0
  foreach ($ln in $lines) {
    $n++
    $obj = $null
    try { $obj = ($ln | ConvertFrom-Json) }
    catch { New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: line $n is UNPARSEABLE JSON => STOP + surface, never repair-and-continue" }
    if ($null -eq $obj) {
      New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: line $n parsed to null => STOP"
    }
    try { Assert-NeoValid $obj $SchemaId $Index "$Label line $n" }
    catch { New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: line $n schema-invalid: $($_.Exception.Message)" }
    if ([string](Get-NeoProp $obj 'run_id') -cne $ExpectedRunId) {
      New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: line $n run_id '$(Get-NeoProp $obj 'run_id')' does not match the run manifest '$ExpectedRunId' => STOP"
    }
    $entries += $obj
  }
  return ,$entries
}

# Per-slice seq monotonicity: for every slice, its entries appear in file order
# with seq strictly +1 from that slice's last entry (first = 1). Gap AND
# regress both STOP; global line order is thereby intact.
function Assert-NeoRunLedgerMonotone($Entries, [string]$Label) {
  $last = @{}
  $n = 0
  foreach ($e in @($Entries)) {
    $n++
    $sid = [string](Get-NeoProp $e 'slice_id')
    $seq = [int](Get-NeoProp $e 'seq')
    $expected = 1
    if ($last.ContainsKey($sid)) { $expected = [int]$last[$sid] + 1 }
    if ($seq -ne $expected) {
      New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: monotonicity violation at line $n - slice '$sid' seq $seq, expected $expected (gap or regress) => STOP + surface, never repair-and-continue"
    }
    $last[$sid] = $seq
  }
}

# ---- S1-FIX shared boundary guards (2026-07-06, check==use parity) -----------
# C1C3-S1-FIX closes four SC-confirmed fail-opens (external Codex F1-F4 + the
# isolated auditor's LOW). Design principle (C6-fix-2 precedent, adopted): ONE
# shared private helper per input class, called at BOTH the write/add boundary
# and the read/consume boundary - re-validation IS the mechanism.

# S1-FIX F3(a): the attempt ledger admits ONLY kind 'initial'|'fix'. The shared
# neo:attempt_ledger_entry schema's kind enum also carries 'external_call' (it
# serves external_call_ledger.jsonl too), so a hand-crafted external_call line
# in attempt_ledger.jsonl is schema-valid - this guard is what refuses it, and
# it now runs at the ADD-side read AND the public read/resume/END-trail side.
function Assert-NeoAttemptLedgerEntriesKind($Entries) {
  $n = 0
  foreach ($e in @($Entries)) {
    $n++
    $k = [string](Get-NeoProp $e 'kind')
    if (($k -cne 'initial') -and ($k -cne 'fix')) {
      New-NeoBlock "reason_code=LEDGER_FAILURE attempt_ledger: line $n kind '$k' does not belong in the attempt ledger => STOP (S1-FIX F3: enforced at add AND read - external calls live in external_call_ledger.jsonl)"
    }
    # S1-FIX-2 NF1: '__run__' is RESERVED for the external-call ledger. S1-FIX
    # blocked it only at the Add-NeoAttemptLedgerEntry WRITE param; the read side
    # trusted the kind guard alone, so a crafted attempt_ledger.jsonl line with
    # slice_id='__run__' + kind='initial'|'fix' is schema-valid and read clean.
    # Folding the reservation into this SHARED helper makes BOTH the add-side
    # read AND the public read/resume/END-trail side refuse it - one rule, both
    # boundaries (check==use parity, the twin of the kind guard above).
    $sid = [string](Get-NeoProp $e 'slice_id')
    if ($sid -ceq $script:NeoRunExternalSliceId) {
      New-NeoBlock "reason_code=LEDGER_FAILURE attempt_ledger: line $n slice_id '$($script:NeoRunExternalSliceId)' is RESERVED for the external-call ledger => STOP (S1-FIX-2 NF1: reservation symmetric at add AND read, check==use)"
    }
  }
}

# S1-FIX F3(b): the external-call ledger admits ONLY kind 'external_call' under
# the reserved run scope '__run__'. Shared by every read of
# external_call_ledger.jsonl (today: the add-side read; any future standalone
# reader must reuse this same guard).
function Assert-NeoExternalCallLedgerEntriesShape($Entries) {
  $n = 0
  foreach ($e in @($Entries)) {
    $n++
    $k = [string](Get-NeoProp $e 'kind')
    if ($k -cne 'external_call') {
      New-NeoBlock "reason_code=LEDGER_FAILURE external_call_ledger: line $n kind '$k' does not belong in the external-call ledger => STOP (S1-FIX F3: only kind 'external_call')"
    }
    $sid = [string](Get-NeoProp $e 'slice_id')
    if ($sid -cne $script:NeoRunExternalSliceId) {
      New-NeoBlock "reason_code=LEDGER_FAILURE external_call_ledger: line $n slice_id '$sid' is not the reserved run scope '$($script:NeoRunExternalSliceId)' => STOP (S1-FIX F3)"
    }
  }
}

# S1-FIX F1: bundle_ref containment - the SAME Assert-NeoSafeRel rule at the
# WRITE boundary (Add-NeoSpawnLedgerEntry) and the READ/CONSUME boundary
# (Assert-NeoSpawnCorrelatedSlot: the slot's ref AND every ledger-read ref),
# BEFORE any correlation comparison. A rooted/UNC/traversal/backslash-dodge
# bundle_ref => BLOCK. REASON CODE (documented choice, used consistently):
# SPAWN_INVALID = a malformed spawn INGREDIENT (unsafe ref, duplicate id,
# ambiguous ledger state); SPAWN_UNCORRELATED stays reserved for the
# no-match / stale / replay cases.
function Assert-NeoSpawnBundleRefSafe([string]$BundleRef, [string]$What) {
  try { Assert-NeoSafeRel $BundleRef }
  catch { New-NeoBlock "reason_code=SPAWN_INVALID spawn_ledger: $What fails Assert-NeoSafeRel => STOP ($($_.Exception.Message)) (S1-FIX F1: containment enforced at write AND consume, check==use)" }
}

# S1-FIX-2 NF2: spawn_id UNIQUENESS is a ledger INVARIANT, not just a write-time
# precondition. S1-FIX enforced it only inline at the Add-NeoSpawnLedgerEntry
# WRITE boundary; the consume side (Assert-NeoSpawnCorrelatedSlot) trusted a
# well-formed ledger and only checked identity+bundle_ref+round ambiguity, so a
# hand-crafted spawn_ledger.jsonl with two entries sharing a spawn_id (one
# correlating the slot, one not) yielded exactly-one correlated match and the
# gate returned $true on an invariant-violating ledger. This SHARED helper scans
# a spawn-ledger entry set and BLOCKs if ANY spawn_id appears more than once
# (-ceq, case-sensitive, matching the family). Called at BOTH boundaries so the
# rule is defined once and enforced at write AND consume (check==use parity).
function Assert-NeoSpawnLedgerUnique($Entries) {
  # Case-SENSITIVE hashtable (ordinal) so uniqueness is a true -ceq scan, matching
  # the family's case-sensitive spawn_id comparisons.
  $seen = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::Ordinal)
  $n = 0
  foreach ($e in @($Entries)) {
    $n++
    $sid = [string](Get-NeoProp $e 'spawn_id')
    if ($seen.ContainsKey($sid)) {
      New-NeoBlock "reason_code=SPAWN_INVALID spawn_ledger: spawn_id '$sid' appears more than once (lines $($seen[$sid]) and $n) - spawn_id must be UNIQUE => STOP (S1-FIX-2 NF2: uniqueness invariant re-verified at write AND consume, check==use)"
    }
    $seen[$sid] = $n
  }
}

# Append ONE canonical-JSON line (write-ahead), then RE-READ the tail and
# verify it round-trips to the same canonical form (write-then-verify).
# Append failure => STOP: the dispatch this entry counts is ABORTED.
function Add-NeoRunJsonlLine([string]$Path, $Entry, [string]$Label) {
  $line = Get-NeoCanonicalJson $Entry
  $enc = New-Object System.Text.UTF8Encoding($false)
  try { [System.IO.File]::AppendAllText($Path, ($line + "`n"), $enc) }
  catch {
    New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: APPEND FAILED at '$Path' - the dispatch this entry counts is ABORTED => STOP ($($_.Exception.Message))"
  }
  $back = Read-NeoRunJsonlRawLines $Path $Label
  $tail = [string]$back[$back.Count - 1]
  $ok = $false
  try { $ok = ((Get-NeoCanonicalJson ($tail | ConvertFrom-Json)) -ceq $line) } catch { $ok = $false }
  if (-not $ok) {
    New-NeoBlock "reason_code=LEDGER_FAILURE ${Label}: write-then-verify MISMATCH - the just-appended tail does not round-trip to the appended entry => STOP"
  }
  return $line
}

# ---- (S1-1) New-NeoRunManifest ------------------------------------------------
# Creates the run-level manifest (persisted run identity) ONCE. File already
# exists => STOP (resume READS it, never rewrites). started_at_utc is the
# PERSISTED wall-clock origin (crash-safe, not process uptime).
function New-NeoRunManifest {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)]$Caps,
    [Parameter(Mandatory=$true)][string]$Timestamp
  )
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoRunManifestLeaf
  if (Test-Path -LiteralPath $path) {
    New-NeoBlock "reason_code=MANIFEST_EXISTS run_manifest.json already exists under RunRoot - a run manifest is written ONCE; resume READS it, never rewrites => STOP"
  }
  $norm = Assert-NeoRunCapsValid $Caps 'New-NeoRunManifest'
  [void](ConvertFrom-NeoRunTimestamp $Timestamp 'started_at_utc' 'CAP_WALL_CLOCK')
  $manifest = [pscustomobject]@{
    schema_id      = 'neo:run_manifest'
    run_id         = ('neo-run-' + [guid]::NewGuid().ToString('N'))
    started_at_utc = $Timestamp
    caps           = [pscustomobject]@{
      max_fix_rounds_per_slice = $norm['max_fix_rounds_per_slice']
      max_external_calls       = $norm['max_external_calls']
      max_wall_clock_hours     = $norm['max_wall_clock_hours']
      max_spend                = $norm['max_spend']
    }
  }
  $Index = Get-NeoRunSchemaIndex
  Assert-NeoValid $manifest 'neo:run_manifest' $Index 'RUN_MANIFEST(create)'
  Write-NeoJsonFile $path $manifest
  # write-then-verify through the fail-closed reader (check==use parity).
  $back = Read-NeoRunManifest -RunRoot $RunRoot
  if ((Get-NeoCanonicalJson $back) -cne (Get-NeoCanonicalJson $manifest)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE RUN_MANIFEST(create): write-then-verify MISMATCH - persisted manifest does not round-trip => STOP"
  }
  return $back
}

# ---- (S1-2) Read-NeoRunManifest ------------------------------------------------
# Fail-closed read-back: missing/unparseable/schema-invalid/caps-invalid =>
# STOP. Resume path: no readable manifest = no readable run state => STOP
# (mirror of the ledger rule).
function Read-NeoRunManifest {
  param([Parameter(Mandatory=$true)][string]$RunRoot)
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoRunManifestLeaf
  if (-not (Test-Path -LiteralPath $path)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE run manifest MISSING under RunRoot - no readable manifest = no readable run state => STOP (resume mirror of the ledger rule)"
  }
  $manifest = $null
  try { $manifest = ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json) }
  catch { New-NeoBlock "reason_code=LEDGER_FAILURE run manifest at '$path' is UNPARSEABLE => STOP" }
  if ($null -eq $manifest) {
    New-NeoBlock "reason_code=LEDGER_FAILURE run manifest at '$path' parsed to null/empty => STOP"
  }
  $Index = Get-NeoRunSchemaIndex
  try { Assert-NeoValid $manifest 'neo:run_manifest' $Index 'RUN_MANIFEST(read)' }
  catch { New-NeoBlock "reason_code=LEDGER_FAILURE run manifest schema-invalid: $($_.Exception.Message)" }
  [void](Assert-NeoRunCapsValid (Get-NeoProp $manifest 'caps') 'Read-NeoRunManifest')
  [void](ConvertFrom-NeoRunTimestamp ([string](Get-NeoProp $manifest 'started_at_utc')) 'manifest.started_at_utc' 'CAP_WALL_CLOCK')
  return $manifest
}

# ---- (S1-3) Test-NeoRunWallClock ------------------------------------------------
# tripped=$true when NowUtc - started_at_utc exceeds max_wall_clock_hours.
# S1-FIX F4: takes -RunRoot (NOT a caller-supplied manifest object) and reads
# the PERSISTED manifest itself via Read-NeoRunManifest (schema + caps +
# timestamp validated fail-closed) - a forged/arbitrary in-memory manifest can
# never reach the trip computation (spec C3: wall clock from the PERSISTED run
# start). Malformed timestamps (or NowUtc BEFORE the persisted origin) => STOP
# - never "not yet tripped". Trip is a RETURN (the S3 loop maps it), not a throw.
function Test-NeoRunWallClock {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$NowUtc
  )
  # S1-FIX F4: persisted state ONLY - the crafted-object path no longer exists.
  $Manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $start = ConvertFrom-NeoRunTimestamp ([string](Get-NeoProp $Manifest 'started_at_utc')) 'manifest.started_at_utc' 'CAP_WALL_CLOCK'
  $now   = ConvertFrom-NeoRunTimestamp $NowUtc 'NowUtc' 'CAP_WALL_CLOCK'
  $caps  = Get-NeoProp $Manifest 'caps'
  if ($null -eq $caps) {
    New-NeoBlock "reason_code=CAPS_INVALID wall-clock: manifest has no caps => STOP"
  }
  $capHours = ConvertTo-NeoRunCapNumber (Get-NeoProp $caps 'max_wall_clock_hours') 'max_wall_clock_hours'
  $elapsed = ($now - $start).TotalHours
  if ($elapsed -lt 0) {
    New-NeoBlock "reason_code=CAP_WALL_CLOCK wall-clock: NowUtc precedes the persisted started_at_utc (clock malformed/regressed) => STOP (never 'not yet tripped')"
  }
  $tripped = ($elapsed -gt $capHours)
  $reason = 'NONE'
  if ($tripped) { $reason = 'CAP_WALL_CLOCK' }
  return @{ tripped = $tripped; reason = $reason; elapsed_hours = $elapsed; cap_hours = $capHours }
}

# ---- (S1-4) Add-NeoAttemptLedgerEntry (THE WRITE-AHEAD LEDGER) -------------------
# Semantics exactly per spec C3 + NB-2 (see the section header): read ->
# verify monotone -> post-increment count vs cap BEFORE any dispatch ->
# APPEND (the entry lands even at the cap) -> re-read + re-verify the tail.
# Returns @{ refused; reason; post_increment_count; entry }.
function Add-NeoAttemptLedgerEntry {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$SliceId,
    [Parameter(Mandatory=$true)][int]$Round,
    [Parameter(Mandatory=$true)][string]$Kind,
    [Parameter(Mandatory=$true)][string]$Timestamp
  )
  if ([string]::IsNullOrWhiteSpace($SliceId)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE attempt_ledger: SliceId is blank => STOP"
  }
  # S1-FIX F3(c) (the isolated auditor's LOW): '__run__' is RESERVED for the
  # external-call ledger - refused symmetrically at the attempt-ledger WRITE
  # boundary (the read side of the external ledger already enforces it).
  if ($SliceId -ceq $script:NeoRunExternalSliceId) {
    New-NeoBlock "reason_code=LEDGER_FAILURE attempt_ledger: SliceId '$($script:NeoRunExternalSliceId)' is RESERVED for the external-call ledger => STOP (S1-FIX F3: reservation symmetric at the write boundary)"
  }
  if (($Kind -cne 'initial') -and ($Kind -cne 'fix')) {
    New-NeoBlock "reason_code=LEDGER_FAILURE attempt_ledger: Kind '$Kind' is not 'initial'|'fix' => STOP (external calls use Add-NeoRunExternalCallEntry)"
  }
  [void](ConvertFrom-NeoRunTimestamp $Timestamp 'Timestamp' 'LEDGER_FAILURE')
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId    = [string](Get-NeoProp $manifest 'run_id')
  $capFix   = ConvertTo-NeoRunCapNumber (Get-NeoProp (Get-NeoProp $manifest 'caps') 'max_fix_rounds_per_slice') 'max_fix_rounds_per_slice'
  $path  = Resolve-NeoRunStatePath $RunRoot $script:NeoAttemptLedgerLeaf
  $Index = Get-NeoRunSchemaIndex

  # (a)+(b) READ + VERIFY. Absent file = round-0 genesis (trivially no prior
  # entries anywhere); present file is verified IN FULL before anything else.
  $entries = @()
  if (Test-Path -LiteralPath $path) {
    $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:attempt_ledger_entry' -Index $Index -Label 'attempt_ledger' -ExpectedRunId $runId
    # S1-FIX F3(a): the SHARED kind guard (same helper the public read side
    # runs - check==use parity, one rule in one place).
    Assert-NeoAttemptLedgerEntriesKind $entries
    Assert-NeoRunLedgerMonotone $entries 'attempt_ledger'
  }
  $prior    = @($entries | Where-Object { [string](Get-NeoProp $_ 'slice_id') -ceq $SliceId })
  $priorFix = @($prior   | Where-Object { [string](Get-NeoProp $_ 'kind') -ceq 'fix' }).Count
  $lastSeq  = 0
  if ($prior.Count -gt 0) { $lastSeq = [int](Get-NeoProp $prior[$prior.Count - 1] 'seq') }
  if (($Kind -ceq 'initial') -and ($prior.Count -gt 0)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE attempt_ledger: 'initial' (round-0 genesis) is VALID only when slice '$SliceId' has no prior entries anywhere in the ledger => STOP"
  }
  if (($Kind -ceq 'fix') -and ($prior.Count -eq 0)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE attempt_ledger: 'fix' for slice '$SliceId' with no prior 'initial' entry - write-ahead ordering broken => STOP"
  }
  $seq = $lastSeq + 1

  # (c) POST-INCREMENT fix-round count vs cap BEFORE any dispatch (NB-2):
  # Kind='fix' counts; Kind='initial' is round 0 and never counts.
  $post = $priorFix
  if ($Kind -ceq 'fix') { $post = $priorFix + 1 }
  if (($Kind -ceq 'initial') -and ($Round -ne 0)) {
    New-NeoBlock "reason_code=ROUND_MISMATCH attempt_ledger: Kind='initial' requires Round 0 (the initial build dispatch is round 0, NB-2), got $Round => STOP"
  }
  if (($Kind -ceq 'fix') -and ($Round -ne $post)) {
    New-NeoBlock "reason_code=ROUND_MISMATCH attempt_ledger: Kind='fix' Round $Round disagrees with the ledger-computed post-increment fix count $post => STOP"
  }
  $refused = $false
  $reason  = 'NONE'
  if (($Kind -ceq 'fix') -and ($post -gt $capFix)) {
    # At the cap the LEDGER ENTRY STILL LANDS (write-ahead); the DISPATCH is
    # what gets refused, never the ledger write.
    $refused = $true
    $reason  = 'CAP_FIX_ROUNDS'
  }
  $entry = [pscustomobject]@{
    run_id        = $runId
    slice_id      = $SliceId
    seq           = $seq
    round         = $Round
    kind          = $Kind
    timestamp_utc = $Timestamp
    refused       = $refused
    reason        = $reason
  }
  Assert-NeoValid $entry 'neo:attempt_ledger_entry' $Index 'ATTEMPT_LEDGER_ENTRY(append)'
  # (d) APPEND + (e) RE-READ/RE-VERIFY (both inside Add-NeoRunJsonlLine).
  [void](Add-NeoRunJsonlLine $path $entry 'attempt_ledger')
  return @{ refused = $refused; reason = $reason; post_increment_count = $post; entry = $entry }
}

# ---- (S1-5) Read-NeoAttemptLedger -------------------------------------------------
# Fail-closed reader (resume + END-trail assembly in S3). Resume without a
# readable ledger => STOP - absence is NOT genesis here.
function Read-NeoAttemptLedger {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [string]$SliceId
  )
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId    = [string](Get-NeoProp $manifest 'run_id')
  $path     = Resolve-NeoRunStatePath $RunRoot $script:NeoAttemptLedgerLeaf
  if (-not (Test-Path -LiteralPath $path)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE attempt_ledger: resume without a readable ledger => STOP (no attempt_ledger.jsonl under RunRoot)"
  }
  $Index = Get-NeoRunSchemaIndex
  $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:attempt_ledger_entry' -Index $Index -Label 'attempt_ledger' -ExpectedRunId $runId
  # S1-FIX F3(a): check==use - the read/resume/END-trail side enforces the SAME
  # kind rule as the add side (a crafted kind='external_call' line is
  # schema-valid but does NOT belong here => STOP, shared helper).
  Assert-NeoAttemptLedgerEntriesKind $entries
  Assert-NeoRunLedgerMonotone $entries 'attempt_ledger'
  if ($PSBoundParameters.ContainsKey('SliceId') -and -not [string]::IsNullOrWhiteSpace($SliceId)) {
    return ,@($entries | Where-Object { [string](Get-NeoProp $_ 'slice_id') -ceq $SliceId })
  }
  return ,@($entries)
}

# ---- (S1-6) Add-NeoRunExternalCallEntry ---------------------------------------------
# Same write-ahead pattern against max_external_calls (run-scoped, on top of
# the <=3/HIGH-slice rule C4 enforces later). Post-increment count > cap =>
# the entry LANDS, refused=$true, reason CAP_EXTERNAL_CALLS.
function Add-NeoRunExternalCallEntry {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$Timestamp
  )
  [void](ConvertFrom-NeoRunTimestamp $Timestamp 'Timestamp' 'LEDGER_FAILURE')
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId    = [string](Get-NeoProp $manifest 'run_id')
  $capExt   = ConvertTo-NeoRunCapNumber (Get-NeoProp (Get-NeoProp $manifest 'caps') 'max_external_calls') 'max_external_calls'
  $path  = Resolve-NeoRunStatePath $RunRoot $script:NeoExternalCallLedgerLeaf
  $Index = Get-NeoRunSchemaIndex
  $entries = @()
  if (Test-Path -LiteralPath $path) {
    $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:attempt_ledger_entry' -Index $Index -Label 'external_call_ledger' -ExpectedRunId $runId
    # S1-FIX F3(b): the SHARED external-call shape guard (kind='external_call'
    # AND the reserved '__run__' scope; one rule in one place - any future
    # standalone external-call reader reuses this same helper).
    Assert-NeoExternalCallLedgerEntriesShape $entries
    Assert-NeoRunLedgerMonotone $entries 'external_call_ledger'
  }
  $post = $entries.Count + 1
  $refused = ($post -gt $capExt)
  $reason  = 'NONE'
  if ($refused) { $reason = 'CAP_EXTERNAL_CALLS' }
  $entry = [pscustomobject]@{
    run_id        = $runId
    slice_id      = $script:NeoRunExternalSliceId
    seq           = $post
    round         = $post
    kind          = 'external_call'
    timestamp_utc = $Timestamp
    refused       = $refused
    reason        = $reason
  }
  Assert-NeoValid $entry 'neo:attempt_ledger_entry' $Index 'EXTERNAL_CALL_ENTRY(append)'
  [void](Add-NeoRunJsonlLine $path $entry 'external_call_ledger')
  return @{ refused = $refused; reason = $reason; post_increment_count = $post; entry = $entry }
}

# ---- (S1-7) Add-NeoSpawnLedgerEntry ---------------------------------------------------
# THE ENGINE-SIDE SPAWN LEDGER (spec sec-0, deferred from C2): appended AT THE
# MOMENT the supervisor cold-spawns an isolated auditor. Append-only JSONL,
# same fail-closed read/verify/append/re-verify discipline. Tamper-EVIDENT,
# not tamper-proof (see the section honesty header); END evidence.
function Add-NeoSpawnLedgerEntry {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$SpawnId,
    [Parameter(Mandatory=$true)][string]$AuditorIdentity,
    [Parameter(Mandatory=$true)][string]$BundleRef,
    [Parameter(Mandatory=$true)][string]$RoundId,
    [Parameter(Mandatory=$true)][string]$Timestamp
  )
  if ([string]::IsNullOrWhiteSpace($SpawnId))         { New-NeoBlock "reason_code=SPAWN_INVALID spawn_ledger: SpawnId is blank => STOP" }
  if ([string]::IsNullOrWhiteSpace($AuditorIdentity)) { New-NeoBlock "reason_code=SPAWN_INVALID spawn_ledger: AuditorIdentity is blank => STOP" }
  if ([string]::IsNullOrWhiteSpace($RoundId))         { New-NeoBlock "reason_code=SPAWN_INVALID spawn_ledger: RoundId is blank => STOP" }
  # S1-FIX F1: the SHARED containment guard (same helper the consume-side
  # correlation gate runs - check==use parity).
  Assert-NeoSpawnBundleRefSafe $BundleRef 'BundleRef'
  [void](ConvertFrom-NeoRunTimestamp $Timestamp 'Timestamp' 'LEDGER_FAILURE')
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId    = [string](Get-NeoProp $manifest 'run_id')
  $path  = Resolve-NeoRunStatePath $RunRoot $script:NeoSpawnLedgerLeaf
  $Index = Get-NeoRunSchemaIndex
  if (Test-Path -LiteralPath $path) {
    $existing = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:spawn_ledger_entry' -Index $Index -Label 'spawn_ledger' -ExpectedRunId $runId
    # S1-FIX F2(b) / S1-FIX-2 NF2: spawn_id UNIQUENESS at the WRITE boundary,
    # via the SHARED invariant helper (same helper the consume-side correlation
    # gate now runs - check==use parity, one rule in one place). Scanning the
    # EXISTING set plus the candidate SpawnId BLOCKs both a pre-existing
    # duplicate in the on-disk ledger AND a reuse of an already-present spawn_id,
    # so a reused id can never manufacture duplicate/ambiguous ledger state
    # through the sanctioned append path.
    Assert-NeoSpawnLedgerUnique (@($existing) + @([pscustomobject]@{ spawn_id = $SpawnId }))
  }
  $entry = [pscustomobject]@{
    run_id           = $runId
    spawn_id         = $SpawnId
    auditor_identity = $AuditorIdentity
    bundle_ref       = $BundleRef
    round_id         = $RoundId
    timestamp_utc    = $Timestamp
  }
  Assert-NeoValid $entry 'neo:spawn_ledger_entry' $Index 'SPAWN_LEDGER_ENTRY(append)'
  [void](Add-NeoRunJsonlLine $path $entry 'spawn_ledger')
  return @{ entry = $entry }
}

# ---- (S1-8) Assert-NeoSpawnCorrelatedSlot ----------------------------------------------
# THE CORRELATION GATE (slot-forgery fixture's target): the consumed slot's
# auditor_identity + bundle_ref + RoundId must ALL match a single prior
# spawn-ledger entry read back fail-closed. No correlated entry => BLOCK ("a
# supervisor-crafted auditor-labeled AUDIT_RESULT WITHOUT a correlated spawn
# entry CANNOT fill the slot"). Stale/replay (same identity, different
# bundle_ref or round) => BLOCK. Malformed/corrupt spawn ledger => BLOCK, never
# treated-as-empty. Tamper-EVIDENT defense-in-depth, NOT tamper-proof; the
# spawn ledger is END evidence. The external lane NEVER fills the slot: this
# gate correlates the ISOLATED auditor's AUDIT_RESULT only. Supervisor-side by
# design decision D4 - orch_enforce.ps1 stays frozen; the C1C3-S3 loop calls
# this IN ADDITION TO the frozen seam.
function Assert-NeoSpawnCorrelatedSlot {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)]$Slot,
    [Parameter(Mandatory=$true)][string]$RoundId
  )
  if ([string]::IsNullOrWhiteSpace($RoundId)) {
    New-NeoBlock "reason_code=SPAWN_UNCORRELATED correlation gate: RoundId is blank => BLOCK"
  }
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId    = [string](Get-NeoProp $manifest 'run_id')
  $identity = [string](Get-NeoProp $Slot 'auditor_identity')
  $bundle   = [string](Get-NeoProp $Slot 'bundle_ref')
  if ([string]::IsNullOrWhiteSpace($identity)) {
    New-NeoBlock "reason_code=SPAWN_UNCORRELATED correlation gate: slot has no auditor_identity => BLOCK"
  }
  if ([string]::IsNullOrWhiteSpace($bundle)) {
    New-NeoBlock "reason_code=SPAWN_UNCORRELATED correlation gate: slot has no bundle_ref => BLOCK"
  }
  # S1-FIX F1 (consume side, check==use): re-run the SAME containment rule the
  # write boundary enforces on the SLOT's bundle_ref BEFORE any correlation
  # comparison - an unsafe slot ref can never even be compared.
  Assert-NeoSpawnBundleRefSafe $bundle "slot bundle_ref '$bundle'"
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoSpawnLedgerLeaf
  if (-not (Test-Path -LiteralPath $path)) {
    New-NeoBlock "reason_code=SPAWN_UNCORRELATED correlation gate: NO spawn ledger under RunRoot - a supervisor-crafted auditor-labeled AUDIT_RESULT without a correlated spawn entry CANNOT fill the slot => BLOCK"
  }
  $Index = Get-NeoRunSchemaIndex
  # fail-closed read: a malformed/corrupt spawn ledger BLOCKS (LEDGER_FAILURE),
  # never treated-as-empty.
  $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:spawn_ledger_entry' -Index $Index -Label 'spawn_ledger' -ExpectedRunId $runId
  # S1-FIX-2 NF2 (consume side, check==use): re-verify the spawn_id UNIQUENESS
  # INVARIANT the write boundary guarantees, on the ledger AS READ FROM DISK,
  # BEFORE any correlation comparison. A hand-crafted ledger with two entries
  # sharing a spawn_id (one correlating the slot, one not) violates the invariant
  # and BLOCKs here regardless of whether the duplicate correlates - this is an
  # ADDITIONAL invariant on top of the F2(a) ambiguity check below, not a
  # replacement for it (same shared helper the write boundary runs).
  Assert-NeoSpawnLedgerUnique $entries
  # S1-FIX F1 (consume side, check==use): re-run the SAME containment rule on
  # EVERY spawn-ledger entry's bundle_ref AS READ FROM DISK, BEFORE any
  # correlation comparison - a hand-crafted ledger line with a rooted/UNC/
  # traversal/backslash-dodge bundle_ref => BLOCK, never compared.
  $ln = 0
  foreach ($e in $entries) {
    $ln++
    Assert-NeoSpawnBundleRefSafe ([string](Get-NeoProp $e 'bundle_ref')) "ledger entry line $ln bundle_ref"
  }
  # S1-FIX F2(a): EXACTLY-ONE correlation (spec sec-0: "a single prior
  # spawn-ledger entry") - collect ALL matches; more than one is AMBIGUITY =>
  # fail-closed, NEVER first-match-wins.
  $correlated = @($entries | Where-Object {
      ([string](Get-NeoProp $_ 'auditor_identity') -ceq $identity) -and
      ([string](Get-NeoProp $_ 'bundle_ref') -ceq $bundle) -and
      ([string](Get-NeoProp $_ 'round_id') -ceq $RoundId)
    })
  if ($correlated.Count -gt 1) {
    New-NeoBlock "reason_code=SPAWN_INVALID correlation gate: AMBIGUOUS - $($correlated.Count) spawn-ledger entries match identity '$identity' + bundle_ref '$bundle' + round '$RoundId'; spec sec-0 requires a SINGLE prior entry => BLOCK (S1-FIX F2: fail-closed, never first-match-wins)"
  }
  if ($correlated.Count -eq 1) { return $true }
  $sameIdentity = @($entries | Where-Object { [string](Get-NeoProp $_ 'auditor_identity') -ceq $identity })
  if ($sameIdentity.Count -gt 0) {
    New-NeoBlock "reason_code=SPAWN_UNCORRELATED correlation gate: STALE/REPLAY - auditor_identity '$identity' matches a spawn entry recorded with a DIFFERENT bundle_ref or round => BLOCK (refuse the slot)"
  }
  New-NeoBlock "reason_code=SPAWN_UNCORRELATED correlation gate: no correlated spawn-ledger entry for identity '$identity' + bundle_ref '$bundle' + round '$RoundId' - the slot CANNOT be filled => BLOCK"
}
