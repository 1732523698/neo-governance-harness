# orch_loop.ps1 - NEO 4.0-P4-AUTONOMY C1C3-S3a LOOP ROUND-CORE (single-round pipeline)
# + C1C3-S3b MULTI-ROUND CONVERGENCE WRAPPER (Invoke-NeoLoopConverge, at the bottom).
# ASCII-only (D10). Dot-source; defines functions only. COORDINATION-only crown jewel:
# this module COORDINATES one loop round - it wires the FROZEN enforcement, router,
# supervisor and notify modules together. It NEVER writes an AUDIT_RESULT, NEVER
# authors a verdict, NEVER edits the governed tree, and NEVER decides an approval.
# Its GO aggregate is nothing but the conjunction of the FROZEN gates it wraps.
#
# Binding spec: NEO_SELF_ITERATION_DESIGN_v3_1.md (0F4C8B81) section 5 (state machine,
# lines 180-207), C1 (54-105: C1a/C1b/C1c), C3 (110-125), section 0 (spawn-ledger
# correlation), section 6 invariants. Scoping (recorded): S3a = the SINGLE-ROUND
# pipeline + round record + STOP/surface plumbing. S3b (THIS module, bottom) = the
# multi-round convergence WRAPPER Invoke-NeoLoopConverge (C1 auto-act re-dispatch,
# C3 cap/wall-clock circuit-breaker looping, NB1 caller-records rows, run_id
# single-read hardening of the manifest writer); END assembly (trail + XC2) is S3c.
#
# ROUND-RECORD CONTRACT (NB-2 write-ahead): STOP paths in this module record their
# OWN iteration-manifest row BEFORE the stop result surfaces to the caller. A round
# that completes clean (aggregation GO) is recorded by the CALLER (the S3b wrapper /
# the fixture acting as it) via Add-NeoIterationManifestEntry - exactly ONE row per
# round either way.
#
# THE STRUCTURAL NOTIFY CHOKE POINT: every STOP/surface path in this module routes
# through Invoke-NeoLoopStopNotify. An engine call cannot forget to notify - that is
# the point (the 100% fix for the manual-notify lapses). Notification is convenience
# NEVER authority (DEF-P8): a failed send never blocks or reorders the STOP; the STOP
# result carries the notify outcome for the manifest row.
#
# C4 SEAM (C4-WIRED) / C5 FAIL-CLOSED SEAM: the external audit lane is wired through
# orch_external.ps1 - STILL no codex call exists anywhere in THIS module (the live
# invoker is orch_external's alone; this module consumes its ON-DISK output through
# the shared derivation Get-NeoExternalLaneStatus, check==use at both boundaries). A
# HIGH slice aggregates GO ONLY on a validated current-round external GO; anything
# else => EXTERNAL_REQUIRED_UNAVAILABLE (=> surface; manual-external via Raphael).
# C5 inputs (slice plan, risk rows, pinned governance manifest) arrive as
# PARAMETERS - the loop consumes them and never authors them.
#
# REUSE (READ-ONLY, no frozen edit) - dot-source graph, grounded:
#   orch_govmanifest.ps1 -> orch_diff.ps1 -> orch_io.ps1 -> {orch_schema, orch_class}
#                                          -> _neo_root.ps1
#   orch_supervisor.ps1  -> _neo_root.ps1 + orch_io.ps1        (idempotent re-source)
#   orch_router.ps1      -> orch_enforce.ps1 -> orch_io.ps1    (idempotent re-source)
#   orch_external.ps1    -> orch_supervisor.ps1                (idempotent re-source;
#                           the C4 adapter + the shared lane derivation gate C calls)
#   notify\notify_raphael.ps1 (standalone; no Set-StrictMode; never throws to caller)
# Every module in this graph defines functions + script-vars ONLY (no top-level side
# effects), so repeated dot-sourcing of the shared dependencies is IDEMPOTENT.
$script:NeoLoopDir = $PSScriptRoot
. "$script:NeoLoopDir\orch_govmanifest.ps1"
. "$script:NeoLoopDir\orch_supervisor.ps1"
. "$script:NeoLoopDir\orch_router.ps1"
. "$script:NeoLoopDir\orch_enforce.ps1"
# orch_engine.ps1 is a GROUNDED RUNTIME DEPENDENCY of the frozen slot seam:
# Assert-NeoAuditorSlotSatisfied (orch_enforce.ps1:419) calls Read-NeoAuditResult,
# which is defined ONLY in orch_engine.ps1 - orch_enforce does not source it and
# every existing caller (orchestrator.ps1, orch_enforce_suite.ps1) loads the engine
# alongside it. Sourced READ-ONLY here for the same reason (no frozen edit).
. "$script:NeoLoopDir\orch_engine.ps1"
. "$script:NeoLoopDir\orch_external.ps1"
. "$script:NeoLoopDir\..\notify\notify_raphael.ps1"

# ---- constants ----------------------------------------------------------------
$script:NeoIterationManifestLeaf = 'iteration_manifest.jsonl'
$script:NeoIterationManifestSchemaId = 'neo:iteration_manifest_entry'

# reason_code -> attested gate class (DEF-P8 event classes). S1/S2a/S2b codes are
# GROUNDED from the live frozen modules; the S3a-INTRODUCED surface codes are:
#   EXTERNAL_REQUIRED_UNAVAILABLE (C4 fail-closed seam)
#   RISK_ESCALATION               (assigned by THIS wrapper when it catches the
#                                  router's escalation BLOCK - see the anchor note
#                                  at Invoke-NeoLoopRoundChecks step 4)
#   EXTERNAL_LANE_INVALID         (unrecognized/impossible external lane status)
#   AUDITOR_SLOT_UNSATISFIED      (the frozen slot gate BLOCKed; its messages carry
#                                  no reason_code= token)
#   DENIED_PATH                   (NF-1 dispatch-time deny-contract hit)
#   EMPTY_CHANGED_SET             (builder returned with an empty actual diff)
# The S3b-INTRODUCED surface code is:
#   BUILDER_SEAM_FAILED           (the caller-supplied builder-invocation seam is
#                                  null/not-a-scriptblock or THREW during a round -
#                                  assigned by the S3b convergence wrapper; the
#                                  seam's return value is NEVER an authority input,
#                                  so the ONLY seam facts the engine acts on are
#                                  "absent" and "threw" - both fail-closed)
$script:NeoLoopBreakerCodes = @(
  'CAPS_INVALID', 'CAP_FIX_ROUNDS', 'CAP_EXTERNAL_CALLS', 'CAP_WALL_CLOCK',
  'LEDGER_FAILURE', 'MANIFEST_CORRUPT'
)
$script:NeoLoopEscalationCodes = @(
  'BUILDER_COMMIT', 'JUDGING_OR_PROTECTED', 'OUTSIDE_APPROVED', 'EMPTY_PROPOSED_EDITS',
  'EMPTY_CHANGED_SET', 'GOVERNANCE_MANIFEST_MISMATCH', 'MANDATORY_MEMBER_MISSING',
  'C1C_JUDGING_FIX_REQUIRED', 'C1C_UNKNOWN_CHANGE_CLASS', 'SPAWN_INVALID',
  'SPAWN_UNCORRELATED', 'RISK_ESCALATION', 'EXTERNAL_REQUIRED_UNAVAILABLE',
  'EXTERNAL_LANE_INVALID', 'AUDITOR_SLOT_UNSATISFIED', 'DENIED_PATH', 'CLASSIFIER_ERROR',
  'BUILDER_SEAM_FAILED',
  # S3c-INTRODUCED: a FAILED END assembly (trail BLOCK / XC2 delta / consistency BLOCK)
  # routes THIS escalation code so the human sees the ESCALATION_STOP surface, never a
  # human-END class and never a mid-run breaker trip (spec 216-222 + dispatch item 3).
  'END_ASSEMBLY_FAILED'
)
# human END classes pass through unchanged (S3c consumes them).
$script:NeoLoopPassThroughClasses = @('DECISION_NEEDED', 'SESSION_END')
# external lane statuses the seam RECOGNIZES (C4-WIRED). 'GO' is honored ONLY when
# the shared on-disk derivation re-derives it at gate C (check==use; a bare caller
# 'GO' with no validating record => EXTERNAL_LANE_INVALID STOP). 'NOT_WIRED' remains
# RECOGNIZED-BUT-HISTORICAL vocabulary: no runtime path produces it since the C4
# wiring (LOW/MED fast-lane records the honest 'MISSING'); removing it would be a
# seam-vocabulary change - deliberately NOT done this slice, disclosed in END evidence.
$script:NeoLoopExternalLaneStatuses = @('NOT_WIRED', 'MISSING', 'STALE', 'UNPARSEABLE', 'NO_GO', 'GO')

# ---- small shared helpers -------------------------------------------------------

# Extract a reason_code= token from a NEO-BLOCK message; no token => 'UNKNOWN'
# (an UNKNOWN still notifies - never a silent skip).
function Get-NeoLoopReasonCode([string]$Message) {
  if ($null -eq $Message) { return 'UNKNOWN' }
  if ($Message -match 'reason_code=([A-Za-z0-9_]+)') { return $Matches[1] }
  return 'UNKNOWN'
}

# Sanitize one summary line for DEF-P8: printable ASCII only ('?' substitution),
# truncated to the notify module's per-line cap. Composition-side counterpart of
# the notify module's own refusal checks (check==use: notify re-checks).
function ConvertTo-NeoLoopAsciiLine([string]$Text, [int]$MaxLen = 200) {
  if ($null -eq $Text) { return '' }
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $Text.ToCharArray()) {
    $code = [int]$ch
    if ($code -ge 0x20 -and $code -le 0x7E) { [void]$sb.Append($ch) } else { [void]$sb.Append('?') }
  }
  $s = $sb.ToString()
  if ($s.Length -gt $MaxLen) { $s = $s.Substring(0, $MaxLen) }
  return $s
}

# ---- Assert-NeoLoopContext (the per-round stop-context contract) ----------------
# Every round function takes a $Context carrying the manifest/notify plumbing. The
# member-name set is EXACT (stray => BLOCK, F4 shape discipline); every member is
# validated HERE at the boundary (C6 lesson). notify mode is XOR: exactly one of
# notify_live_send=$true / non-empty notify_test_mode_dir (the notify module
# re-checks - check==use). Returns a normalized hashtable.
#
# F4 CLASSIFICATION: CONTRACT-NOT-RUNTIME (bare-throw is CORRECT and load-bearing).
# Every New-NeoBlock below hard-throws and is DELIBERATELY NOT routed through the
# STOP choke point: Complete-NeoLoopRoundStop CONSUMES a NORMALIZED $Context
# (run_root + notify mode) to notify + write the manifest row, so a malformed
# $Context cannot be routed through the very path that requires it - the routing
# would be CIRCULAR (no trustworthy run_root/notify channel yet). This is the
# boundary where $Context is proven; downstream round functions call this FIRST and
# only route their SUBSEQUENT (post-$ctx) guards through the choke point.
function Assert-NeoLoopContext {
  param([Parameter(Mandatory = $true)]$Context)
  $required = @('run_root', 'slice_id', 'round', 'attempt_seq', 'evidence_path',
    'timestamp_utc', 'notify_test_mode_dir', 'notify_live_send')
  if ($null -eq $Context) { New-NeoBlock "loop-context: Context is null => BLOCK" }
  $names = @(Get-NeoPropNames $Context)
  foreach ($n in $names) {
    if ($required -cnotcontains [string]$n) {
      New-NeoBlock "loop-context: STRAY member '$n' - member set must be EXACTLY {$($required -join ', ')} => BLOCK"
    }
  }
  foreach ($n in $required) {
    if (-not (Test-NeoHasProp $Context $n)) {
      New-NeoBlock "loop-context: member '$n' is MISSING => BLOCK"
    }
  }
  $runRoot = [string](Get-NeoProp $Context 'run_root')
  if ([string]::IsNullOrWhiteSpace($runRoot) -or -not (Test-Path -LiteralPath $runRoot -PathType Container)) {
    New-NeoBlock "loop-context: run_root '$runRoot' is not an existing directory => BLOCK"
  }
  $sliceId = [string](Get-NeoProp $Context 'slice_id')
  if ([string]::IsNullOrWhiteSpace($sliceId)) { New-NeoBlock "loop-context: slice_id is blank => BLOCK" }
  $roundRaw = Get-NeoProp $Context 'round'
  $round = 0
  try { $round = [int]$roundRaw } catch { New-NeoBlock "loop-context: round '$roundRaw' is not an integer => BLOCK" }
  if ($round -lt 0) { New-NeoBlock "loop-context: round $round is negative => BLOCK" }
  $seqRaw = Get-NeoProp $Context 'attempt_seq'
  $seq = 0
  try { $seq = [int]$seqRaw } catch { New-NeoBlock "loop-context: attempt_seq '$seqRaw' is not an integer => BLOCK" }
  if ($seq -lt 1) { New-NeoBlock "loop-context: attempt_seq $seq is not >= 1 (ties to the S1 attempt ledger) => BLOCK" }
  $evidence = [string](Get-NeoProp $Context 'evidence_path')
  if ([string]::IsNullOrWhiteSpace($evidence)) { New-NeoBlock "loop-context: evidence_path is blank => BLOCK" }
  $ts = [string](Get-NeoProp $Context 'timestamp_utc')
  [void](ConvertFrom-NeoRunTimestamp $ts 'Context.timestamp_utc' 'LEDGER_FAILURE')
  $testDir = [string](Get-NeoProp $Context 'notify_test_mode_dir')
  $liveRaw = Get-NeoProp $Context 'notify_live_send'
  if (-not ($liveRaw -is [bool])) { New-NeoBlock "loop-context: notify_live_send must be a BOOLEAN => BLOCK (never coerced)" }
  $live = [bool]$liveRaw
  $hasTest = -not [string]::IsNullOrEmpty($testDir)
  if ($live -and $hasTest) { New-NeoBlock "loop-context: notify_live_send and notify_test_mode_dir are mutually exclusive - exactly one channel mode => BLOCK" }
  if ((-not $live) -and (-not $hasTest)) { New-NeoBlock "loop-context: exactly one of notify_live_send / notify_test_mode_dir must be set - no default channel exists => BLOCK" }
  return @{
    run_root = $runRoot; slice_id = $sliceId; round = $round; attempt_seq = $seq
    evidence_path = $evidence; timestamp_utc = $ts
    notify_test_mode_dir = $testDir; notify_live_send = $live
  }
}

# ---- Invoke-NeoLoopStopNotify (THE STRUCTURAL NOTIFY CHOKE POINT) ----------------
# ONE helper EVERY loop STOP/surface path MUST route through. Maps reason_code ->
# attested gate class:
#   cap/ledger/wall-clock trips  => BREAKER_TRIP
#   enforcement/escalation STOPs => ESCALATION_STOP
#   DECISION_NEEDED/SESSION_END  => pass through the human END classes ONLY when the
#                                   caller sets -HumanEndClass (F5, see below)
#   UNKNOWN/unmapped/blank       => STILL notifies (ESCALATION_STOP) - NEVER silent.
# Composes capped ASCII summary lines (reason_code + slice + round + one-line
# detail; DEF-P8 content caps; NO source/diff/secret content ever enters a line).
# Calls Send-NeoGateNotification with the CALLER-supplied channel mode. NEVER throws:
# a notify failure never blocks or reorders the STOP (convenience-never-authority);
# the returned status is carried into the manifest row by the stop path.
# Returns @{ gate_class; mapped; status = @{ sent; deduped; refused; reason; composed_path } }.
#
# F5 (FIXED - distinct internal path for the human END classes): the pass-through
# classes SESSION_END / DECISION_NEEDED are reachable ONLY via the internal
# -HumanEndClass switch, NEVER via a reason_code lookup on arbitrary caller input.
# The loop STOP path (Complete-NeoLoopRoundStop) NEVER sets -HumanEndClass, so a
# supervisor cannot mislabel a breaker/escalation as a human-END class through the
# STOP choke point: without the switch, SESSION_END/DECISION_NEEDED are treated as an
# UNMAPPED code => fail-closed to ESCALATION_STOP (notified, disclosed). The S3c
# human-END surface (out of this slice's write scope) is the ONLY caller that passes
# -HumanEndClass, and even then only for the two human-END codes. This closes the
# public-surface misuse without a new file, schema, or call site.
function Invoke-NeoLoopStopNotify {
  param(
    [string]$ReasonCode,
    [string]$SliceId,
    $Round,
    [string]$Detail,
    [string]$EvidencePath,
    [string]$TestModeDir,
    [switch]$LiveSend,
    # F5: the ONLY gate that lets SESSION_END/DECISION_NEEDED pass through as
    # themselves. A loop STOP never sets this; only the S3c human-END entry does.
    [switch]$HumanEndClass
  )
  # gate-class resolution is pure lookups - it cannot throw.
  $code = [string]$ReasonCode
  $mapped = $true
  $gateClass = ''
  if ([string]::IsNullOrWhiteSpace($code)) {
    $code = 'UNKNOWN'; $mapped = $false; $gateClass = 'ESCALATION_STOP'
  } elseif ($HumanEndClass -and ($script:NeoLoopPassThroughClasses -ccontains $code)) {
    # F5: pass-through ONLY on the distinct internal human-END path.
    $gateClass = $code
  } elseif ($script:NeoLoopPassThroughClasses -ccontains $code) {
    # F5: a human-END class arriving WITHOUT the internal switch is a mislabeled
    # breaker attempt from the public STOP surface => fail-closed to ESCALATION_STOP
    # (still notifies; disclosed as unmapped-via-STOP-path). Never honored as a human
    # pass-through here.
    $mapped = $false; $gateClass = 'ESCALATION_STOP'
  } elseif ($script:NeoLoopBreakerCodes -ccontains $code) {
    $gateClass = 'BREAKER_TRIP'
  } elseif ($script:NeoLoopEscalationCodes -ccontains $code) {
    $gateClass = 'ESCALATION_STOP'
  } else {
    # unmapped reason_code: STILL notifies - never a silent skip.
    $mapped = $false; $gateClass = 'ESCALATION_STOP'
  }
  $status = @{ sent = $false; deduped = $false; refused = $false; reason = ''; composed_path = $null }
  try {
    $safeSlice = ConvertTo-NeoLoopAsciiLine ([string]$SliceId) 100
    if ([string]::IsNullOrWhiteSpace($safeSlice)) { $safeSlice = 'UNKNOWN-SLICE' }
    $safeEvidence = ConvertTo-NeoLoopAsciiLine ([string]$EvidencePath) 200
    if ([string]::IsNullOrWhiteSpace($safeEvidence)) { $safeEvidence = '(unspecified)' }
    $roundText = ConvertTo-NeoLoopAsciiLine ([string]$Round) 20
    if ([string]::IsNullOrWhiteSpace($roundText)) { $roundText = '?' }
    $lines = @()
    $lines += ConvertTo-NeoLoopAsciiLine ("NEO loop STOP: reason_code=" + $code) 200
    if (-not $mapped) { $lines += ConvertTo-NeoLoopAsciiLine ("(unmapped reason_code - notified fail-closed as " + $gateClass + ")") 200 }
    $lines += ConvertTo-NeoLoopAsciiLine ("slice=" + $safeSlice + " round=" + $roundText) 200
    $lines += ConvertTo-NeoLoopAsciiLine ("detail: " + [string]$Detail) 200
    $sendArgs = @{
      GateType = $gateClass; SliceId = $safeSlice; SummaryLines = $lines; EvidencePath = $safeEvidence
    }
    if ($LiveSend) { $sendArgs['LiveSend'] = $true } else { $sendArgs['TestModeDir'] = $TestModeDir }
    $res = Send-NeoGateNotification @sendArgs
    if ($null -ne $res) { $status = $res }
  } catch {
    # belt-and-braces: the choke point itself never throws (the frozen notify
    # module already never throws; this guards the composition code around it).
    $status.sent = $false
    $status.reason = "choke-point internal failure: $($_.Exception.Message) (STOP not blocked - notification is convenience, never authority)"
  }
  return @{ gate_class = $gateClass; mapped = $mapped; status = $status }
}

# ---- ITERATION MANIFEST (append-only JSONL; spec sec-5 197-198) ------------------
# One entry PER ROUND under the caller-supplied RunRoot (S1 run-state pattern:
# Resolve-NeoRunStatePath containment + Add-NeoRunJsonlLine append/write-then-verify,
# both REUSED from the frozen supervisor). Entries are schema-validated against
# neo:iteration_manifest_entry. Append-only: existing lines are NEVER rewritten. Any
# manifest read/write/parse failure => BLOCK LEDGER_FAILURE semantics (fail-closed,
# mirror S1). run_id and schema_id are stamped HERE from the persisted run manifest -
# a caller can never bind a row to a foreign run.
#
# $Fields is a hashtable/object whose member-name set is EXACTLY the entry fields
# minus {schema_id, run_id} (stamped here). Stray/missing member => BLOCK.
#
# F4 CLASSIFICATION: the LEDGER_FAILURE New-NeoBlock guards in this function (and in
# Read-NeoIterationManifest and Complete-NeoLoopRoundStop's RoundData guard) are
# CONTRACT-NOT-RUNTIME as far as the choke point is concerned: this IS the manifest
# writer/reader, and Complete-NeoLoopRoundStop notifies then calls THIS function to
# write the row - routing a manifest-write failure back through the writer would be
# CIRCULAR (and per the shared-stop-path contract a row-write failure is the ONE
# thing that PREEMPTS a STOP: it escalates to a thrown LEDGER_FAILURE fail-closed, so
# a STOP that cannot be recorded is never silently surfaced as recorded). These stay
# bare-throw and are already reason_code=LEDGER_FAILURE tagged.
function Add-NeoIterationManifestEntry {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)]$Fields,
    # S3b run_id SINGLE-READ HARDENING (Raphael KEEP 2026-07-07): when bound
    # (non-blank), the writer stamps THIS run_id and SKIPS its own run-manifest
    # read; when absent/blank, byte-equivalent prior behavior (every existing
    # caller unchanged). HONESTY: binding -RunId trades the writer's own
    # "stamped from disk" property for a single read shared with the caller's
    # pre-notify dry-run. Compensating controls, BOTH load-bearing:
    #   (a) the only in-engine caller that binds it is Complete-NeoLoopRoundStop,
    #       which is ENGINE-INTERNAL - the same tamper-EVIDENT trust boundary as
    #       its -EngineData channel (spec sec-0);
    #   (b) the READ side (Read-NeoIterationManifest -> Read-NeoRunLedgerEntries
    #       -ExpectedRunId) rejects any foreign-run row FAIL-CLOSED, so a forged
    #       -RunId row is caught at the very next read (fixture-proven).
    [string]$RunId
  )
  $callerFields = @(
    'slice_id', 'round', 'attempt_seq', 'baseline_head_sha', 'baseline_tree_hash',
    'changed_count', 'changed_paths_hash', 'classification', 'findings_summary',
    'auditor_slot_status', 'auditor_slot_recommendation', 'auditor_identity',
    'external_lane_status', 'effective_seam_tier', 'cap_events', 'stop_reason_code',
    'notify_gate_class', 'notify_sent', 'notify_deduped', 'notify_refused',
    'notify_reason', 'timestamp_utc'
  )
  if ($null -eq $Fields) { New-NeoBlock "reason_code=LEDGER_FAILURE iteration_manifest: Fields is null => STOP" }
  $names = @(Get-NeoPropNames $Fields)
  foreach ($n in $names) {
    if ($callerFields -cnotcontains [string]$n) {
      New-NeoBlock "reason_code=LEDGER_FAILURE iteration_manifest: STRAY field '$n' (schema_id/run_id are stamped by the engine, never caller-supplied) => STOP"
    }
  }
  foreach ($n in $callerFields) {
    if (-not (Test-NeoHasProp $Fields $n)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE iteration_manifest: field '$n' is MISSING => STOP (every field required; no optional escape hatches)"
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($RunId)) {
    # single-read path (S3b): the engine-internal caller already read the persisted
    # run manifest (pre-notify dry-run) - the dry-run-validated row and the written
    # row share that ONE read; the disk window shrinks to the irreducible JSONL
    # append. Foreign-run forgery via this parameter is caught fail-closed at the
    # very next Read-NeoIterationManifest (-ExpectedRunId binding).
    $runId = $RunId
  } else {
    $manifest = Read-NeoRunManifest -RunRoot $RunRoot
    $runId = [string](Get-NeoProp $manifest 'run_id')
  }
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoIterationManifestLeaf
  $entry = [ordered]@{}
  $entry['schema_id'] = $script:NeoIterationManifestSchemaId
  $entry['run_id'] = $runId
  # Get-NeoVal (shape-preserving) - an empty/single-element cap_events array must
  # stay an ARRAY through the copy (Get-NeoProp would unwrap it on return).
  foreach ($n in $callerFields) { $entry[$n] = (Get-NeoVal $Fields $n) }
  $obj = [pscustomobject]$entry
  $Index = Get-NeoRunSchemaIndex
  try { Assert-NeoValid $obj $script:NeoIterationManifestSchemaId $Index 'ITERATION_MANIFEST_ENTRY(append)' }
  catch { New-NeoBlock "reason_code=LEDGER_FAILURE iteration_manifest: entry failed schema validation ($(($_.Exception.Message) -replace '^NEO-BLOCK:\s*', '')) => STOP" }
  # append + re-read/re-verify (write-then-verify inside the reused helper).
  [void](Add-NeoRunJsonlLine $path $obj 'iteration_manifest')
  return @{ entry = $obj; path = $path }
}

# Fail-closed reader (S3c END-trail consumer + fixtures). Missing file => BLOCK
# (absence is NOT an empty manifest here - mirror Read-NeoAttemptLedger). Every
# line must parse, schema-validate and bind to the persisted run_id.
function Read-NeoIterationManifest {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [string]$SliceId
  )
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoIterationManifestLeaf
  if (-not (Test-Path -LiteralPath $path)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE iteration_manifest: read without a readable manifest => STOP (no $($script:NeoIterationManifestLeaf) under RunRoot)"
  }
  $Index = Get-NeoRunSchemaIndex
  $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId $script:NeoIterationManifestSchemaId -Index $Index -Label 'iteration_manifest' -ExpectedRunId $runId
  if ($PSBoundParameters.ContainsKey('SliceId') -and -not [string]::IsNullOrWhiteSpace($SliceId)) {
    return ,@($entries | Where-Object { [string](Get-NeoProp $_ 'slice_id') -ceq $SliceId })
  }
  return ,@($entries)
}

# ---- the shared STOP path (notify -> write-ahead row -> stop result) -------------
# EVERY loop STOP routes through here: (1) the choke point composes+sends the
# notification (never throws; outcome captured), (2) the iteration-manifest STOP row
# LANDS carrying that outcome (NB-2 write-ahead: the row is on disk BEFORE the stop
# result surfaces to the caller), (3) the stop result is RETURNED (the S3b wrapper
# maps it; nothing here re-throws the original block). A row write failure is the
# ONE thing that preempts: it escalates to a thrown LEDGER_FAILURE (fail-closed -
# a STOP that cannot be recorded must not be silently surfaced as recorded).
#
# S3a-FIX-3 CHANNEL SEPARATION (manifest-field-authority class-closer): the manifest
# row is the engine's HONEST record; caller data and engine-computed values reach it
# through TWO DISTINCT channels so an UNTRUSTED caller can never forge an engine-owned
# field.
#   * $RoundData (CALLER channel, tight-validated): may carry ONLY the round-diff
#     fields a legitimate caller/S3b wrapper genuinely originates from the round-checks
#     output - { baseline_head_sha, baseline_tree_hash, changed_count,
#     changed_paths_hash }. THAT IS THE COMPLETE CALLER-SUPPLIABLE SET. Any other key
#     (engine-owned OR unknown-to-schema) => BLOCK. Enforced at EVERY public round-stage
#     entry that takes a caller -RoundData (here AND Assert-NeoLoopAuditSatisfied); the
#     split is a class rule, not a one-function patch.
#   * $EngineData (ENGINE channel, trusted): the engine-computed verdict lanes /
#     classification / findings_summary / effective_seam_tier / cap_events this module's
#     OWN gate code produces. Applied WITHOUT the caller-restriction.
#
# TRUST BOUNDARY (stated honestly; the external channel probes it):
#   (a) The UNTRUSTED-caller closure is at the PUBLIC ROUND-STAGE ENTRY POINTS
#       (Assert-NeoLoopAuditSatisfied - and any future S3b round-stage entry): their
#       -RoundData is tight-validated and THEY fill -EngineData themselves from their
#       OWN gate computation, NEVER by copying a caller value into it. A caller going
#       through the proper API therefore cannot forge a lane.
#   (b) Complete-NeoLoopRoundStop is an ENGINE-INTERNAL helper. Its -EngineData channel
#       is ENGINE-TRUSTED: a direct Complete-NeoLoopRoundStop -EngineData caller IS
#       engine code (the loop functions + the future S3b breaker-stop path), which is
#       the TAMPER-EVIDENT supervisor boundary per spec sec-0. A malicious/buggy
#       supervisor forging its OWN manifest is OUT of the ENFORCED threat model - caught
#       by XC2 final-state + attempt-ledger correlation cross-checks (consistent with the
#       S1/S2a tamper-evident dispositions). -EngineData is NOT tamper-PROOF (impossible
#       on a shared FS) - it is tamper-EVIDENT, stated honestly.
#   (c) DEFENSE-IN-DEPTH kept: BOTH channels are schema-field-validated (a stray/
#       unknown-to-schema key in EITHER => BLOCK); ONLY -RoundData is additionally
#       restricted to the tight caller set. No caller-facing public parameter ever
#       FORWARDS an external value into -EngineData - the round-stage entries build
#       -EngineData from engine computation only.
#
# B3 (preserved): BOTH channels are validated at the TOP - BEFORE Invoke-
# NeoLoopStopNotify - so an invalid RoundData/EngineData fails-closed BEFORE any
# notification is composed => notify and row are ATOMIC (composed iff the row lands;
# never notify-without-row). Membership is case-insensitive, matching how the $fields
# hashtable resolves a key (a 'Stop_Reason_Code' spelling is blocked identically). B2
# (closed holistically): the wide fix-2 data-tier allowlist that let a caller forge the
# verdict lanes is REPLACED by the tight 4-field caller set; the lanes now arrive ONLY
# via the trusted engine channel.
function Complete-NeoLoopRoundStop {
  param(
    [Parameter(Mandatory = $true)]$Context,   # ALREADY normalized by Assert-NeoLoopContext
    [Parameter(Mandatory = $true)][string]$ReasonCode,
    [Parameter(Mandatory = $true)][string]$Detail,
    $RoundData,
    # ENGINE-TRUSTED channel (trust boundary (b) above): engine-computed fields. NEVER
    # populated from a caller-facing public parameter; the round-stage entries build it
    # from their own gate computation.
    $EngineData
  )
  # CALLER channel: tight allowlist. The COMPLETE caller-suppliable set is exactly the
  # round-diff the caller legitimately originates; EVERYTHING else is engine-owned.
  $roundDataCallerSuppliable = @(
    'baseline_head_sha', 'baseline_tree_hash', 'changed_count', 'changed_paths_hash'
  )
  # the full schema-known writable field set (schema_id/run_id are engine-stamped in
  # Add-NeoIterationManifestEntry, never row-field inputs here) - used to reject an
  # unknown-to-schema key in EITHER channel (defense-in-depth (c)).
  $schemaKnownFields = @(
    'slice_id', 'round', 'attempt_seq', 'baseline_head_sha', 'baseline_tree_hash',
    'changed_count', 'changed_paths_hash', 'classification', 'findings_summary',
    'auditor_slot_status', 'auditor_slot_recommendation', 'auditor_identity',
    'external_lane_status', 'effective_seam_tier', 'cap_events', 'stop_reason_code',
    'notify_gate_class', 'notify_sent', 'notify_deduped', 'notify_refused',
    'notify_reason', 'timestamp_utc'
  )
  # the fields the engine channel is entitled to set: the round's computed lanes /
  # classification / findings_summary / seam-tier / cap_events (+ the round-diff, so an
  # engine caller may also pass it here). Everything the STOP path itself AUTHORS -
  # slice/round/attempt/timestamp + stop_reason_code + notify_* - stays owned by THIS
  # function's own assignment below and is NOT settable via -EngineData.
  $engineDataSettable = @(
    'baseline_head_sha', 'baseline_tree_hash', 'changed_count', 'changed_paths_hash',
    'classification', 'findings_summary', 'auditor_slot_status',
    'auditor_slot_recommendation', 'auditor_identity', 'external_lane_status',
    'effective_seam_tier', 'cap_events'
  )
  if ($null -ne $RoundData) {
    foreach ($k in @(Get-NeoPropNames $RoundData)) {
      $ks = [string]$k
      if ($roundDataCallerSuppliable -contains $ks) { continue }
      elseif ($schemaKnownFields -contains $ks) {
        New-NeoBlock "reason_code=LEDGER_FAILURE loop-stop: RoundData cannot set engine-owned field '$ks' => STOP"
      }
      else {
        New-NeoBlock "reason_code=LEDGER_FAILURE loop-stop: RoundData carries unknown field '$ks' => STOP"
      }
    }
  }
  if ($null -ne $EngineData) {
    foreach ($k in @(Get-NeoPropNames $EngineData)) {
      $ks = [string]$k
      if ($engineDataSettable -contains $ks) { continue }
      elseif ($schemaKnownFields -contains $ks) {
        New-NeoBlock "reason_code=LEDGER_FAILURE loop-stop: EngineData cannot set the STOP-path-owned field '$ks' (stop_reason_code/notify_*/identity/round-id are authored by the stop path itself) => STOP"
      }
      else {
        New-NeoBlock "reason_code=LEDGER_FAILURE loop-stop: EngineData carries unknown field '$ks' => STOP"
      }
    }
  }

  # S3a-FIX-4 ROOT ATOMICITY CLOSE: build the FULL manifest row and SCHEMA-VALIDATE it
  # (the same validator/index Add-NeoIterationManifestEntry uses) BEFORE notify, so a
  # schema-invalid VALUE on an ALLOWED caller key (e.g. changed_count='not-an-integer',
  # empty baseline_head_sha/changed_paths_hash) fails-closed BEFORE any notification is
  # composed. Pre-fix the row schema-validation lived INSIDE the writer, AFTER notify:
  # the key-OWNERSHIP guard above accepts changed_count as a caller-suppliable field, so
  # notify fired then the writer rejected the row => notify-without-row (the B3 atomicity
  # sibling). This closes the WHOLE atomicity class at the ROOT (validate the assembled
  # row, not per-field) for BOTH reach paths at once - Complete-NeoLoopRoundStop is the
  # single shared STOP choke point (a direct call AND every routed early-guard STOP from
  # Assert-NeoLoopAuditSatisfied flow through here).
  #
  # NEW ORDER: validate keys+ownership (above) -> BUILD the row once -> DRY-RUN
  # schema-validate the assembled row (BLOCK LEDGER_FAILURE before notify on any invalid
  # content) -> notify -> overwrite ONLY the notify_* fields with the real result ->
  # write the SAME object. BUILD-ONCE / VALIDATE-ONCE / WRITE-THE-SAME-OBJECT: the ONLY
  # fields that differ between the validated dry-run row and the written row are notify_*,
  # and the REAL notify_* are schema-valid BY CONSTRUCTION (notify_gate_class is the pure-
  # lookup gate-class enum; notify_sent/deduped/refused are bools; notify_reason is an
  # ASCII-capped string with NO schema length bound). The dry-run seeds notify_* with
  # SCHEMA-VALID PLACEHOLDERS (a valid enum member + $false bools + '') so the dry-run row
  # is complete and validates against EXACTLY the constraints a caller/engine can influence.
  # Therefore "dry-run row schema-valid" <=> "written row schema-valid" for every caller/
  # engine-influenceable field; the write can then fail ONLY on DISK / run-manifest I/O
  # (the documented writer-contract exception - the one residual notify-without-row).
  $fields = @{
    slice_id = $Context.slice_id; round = $Context.round; attempt_seq = $Context.attempt_seq
    baseline_head_sha = 'NOT_EVALUATED'; baseline_tree_hash = 'NOT_EVALUATED'
    changed_count = 0; changed_paths_hash = 'NOT_EVALUATED'
    classification = 'STOPPED'; findings_summary = (ConvertTo-NeoLoopAsciiLine $Detail 200)
    auditor_slot_status = 'NOT_EVALUATED'; auditor_slot_recommendation = 'NOT_EVALUATED'
    auditor_identity = 'NOT_EVALUATED'; external_lane_status = 'NOT_EVALUATED'
    effective_seam_tier = 'NOT_EVALUATED'; cap_events = @()
    stop_reason_code = $ReasonCode
    # SCHEMA-VALID PLACEHOLDER notify_* (the real values come from $n, which does not exist
    # until AFTER notify; these placeholders satisfy the schema so the dry-run validates the
    # caller/engine content, not the not-yet-known notify outcome): 'NONE' is a valid
    # notify_gate_class enum member; the flags are bools; the reason is the empty string.
    notify_gate_class = 'NONE'
    notify_sent = $false; notify_deduped = $false
    notify_refused = $false
    notify_reason = ''
    timestamp_utc = $Context.timestamp_utc
  }
  # ENGINE channel first (the module's OWN computed lanes/classification/findings_summary/
  # seam-tier/cap_events), then the CALLER channel (the 4 round-diff fields). Both are
  # PRE-VALIDATED above (any illegal key already fail-closed BEFORE notify), so neither
  # loop can throw here => notify+row stay atomic (B3). The two key-sets do not overlap
  # except on the 4 round-diff fields, where an engine caller and a caller-diff caller are
  # mutually exclusive in practice; applying caller LAST keeps the legitimate caller-diff
  # authoritative for those 4 (matching the round-checks -> RoundData baseline flow).
  if ($null -ne $EngineData) {
    foreach ($k in @(Get-NeoPropNames $EngineData)) {
      # Get-NeoVal: shape-preserving (an empty/single-element cap_events array stays an
      # ARRAY through the copy).
      $fields[[string]$k] = (Get-NeoVal $EngineData $k)
    }
  }
  if ($null -ne $RoundData) {
    foreach ($k in @(Get-NeoPropNames $RoundData)) {
      # Pre-validated (ownership) above: every key is a CALLER-SUPPLIABLE round-diff field
      # (engine-owned + unknown keys already fail-closed BEFORE notify). Its VALUE is
      # schema-validated by the dry-run below, BEFORE notify. Get-NeoVal: shape-preserving.
      $fields[[string]$k] = (Get-NeoVal $RoundData $k)
    }
  }
  # DRY-RUN schema-validation of the ASSEMBLED row, BEFORE notify. Reuses the SAME machinery
  # the writer (Add-NeoIterationManifestEntry) uses - {schema_id, run_id} stamped identically
  # (run_id read the SAME way, from the persisted run manifest), Get-NeoRunSchemaIndex, and
  # Assert-NeoValid against neo:iteration_manifest_entry - so this is a faithful dry-run of the
  # exact object the writer will persist (no re-implemented validation, no schema edit). If
  # reading the run manifest for the dry-run itself fails, that IS the documented ledger/disk
  # exception and BLOCKs LEDGER_FAILURE here - correctly, BEFORE notify (fails closed 0/0).
  $dryManifest = Read-NeoRunManifest -RunRoot $Context.run_root
  $dryRunId = [string](Get-NeoProp $dryManifest 'run_id')
  $dryEntry = [ordered]@{}
  $dryEntry['schema_id'] = $script:NeoIterationManifestSchemaId
  $dryEntry['run_id'] = $dryRunId
  foreach ($k in @(
    'slice_id', 'round', 'attempt_seq', 'baseline_head_sha', 'baseline_tree_hash',
    'changed_count', 'changed_paths_hash', 'classification', 'findings_summary',
    'auditor_slot_status', 'auditor_slot_recommendation', 'auditor_identity',
    'external_lane_status', 'effective_seam_tier', 'cap_events', 'stop_reason_code',
    'notify_gate_class', 'notify_sent', 'notify_deduped', 'notify_refused',
    'notify_reason', 'timestamp_utc')) {
    # Get-NeoVal: shape-preserving (cap_events array stays an ARRAY), matching the writer.
    $dryEntry[$k] = (Get-NeoVal $fields $k)
  }
  $dryIndex = Get-NeoRunSchemaIndex
  try { Assert-NeoValid ([pscustomobject]$dryEntry) $script:NeoIterationManifestSchemaId $dryIndex 'ITERATION_MANIFEST_ENTRY(pre-notify dry-run)' }
  catch { New-NeoBlock "reason_code=LEDGER_FAILURE loop-stop: assembled manifest row fails schema validation BEFORE notify ($(($_.Exception.Message) -replace '^NEO-BLOCK:\s*', '')) => STOP (fail-closed: no notification is composed on a row that cannot persist)" }

  $notifyArgs = @{
    ReasonCode = $ReasonCode; SliceId = $Context.slice_id; Round = $Context.round
    Detail = $Detail; EvidencePath = $Context.evidence_path
  }
  if ($Context.notify_live_send) { $notifyArgs['LiveSend'] = $true }
  else { $notifyArgs['TestModeDir'] = $Context.notify_test_mode_dir }
  $n = Invoke-NeoLoopStopNotify @notifyArgs

  # Overwrite ONLY the notify_* fields with the REAL result (schema-valid BY CONSTRUCTION -
  # see the header note), then write the SAME $fields object the dry-run validated. Every
  # other field is byte-identical to the validated row => dry-run-valid <=> written-valid.
  $fields['notify_gate_class'] = [string]$n.gate_class
  $fields['notify_sent'] = [bool]$n.status.sent
  $fields['notify_deduped'] = [bool]$n.status.deduped
  $fields['notify_refused'] = [bool]$n.status.refused
  $fields['notify_reason'] = (ConvertTo-NeoLoopAsciiLine ([string]$n.status.reason) 200)
  # S3b run_id SINGLE-READ: pass the dry-run-read run_id ($dryRunId, read ONCE above)
  # so the dry-run-validated row and the written row share ONE run-manifest read - a
  # manifest mutated between the dry-run and the write can no longer diverge the
  # row's run_id (the old second read at the writer was the tamper window).
  $row = Add-NeoIterationManifestEntry -RunRoot $Context.run_root -Fields $fields -RunId $dryRunId
  return @{
    stopped = $true; reason_code = $ReasonCode; gate_class = [string]$n.gate_class
    detail = $Detail; notify = $n.status; manifest_entry = $row.entry
  }
}

# ---- Invoke-NeoLoopRoundChecks (C1b PER-ROUND ENFORCEMENT CHAIN; spec 186-193) ----
# Runs the post-builder enforcement chain IN ORDER. Ordering is load-bearing:
# enforcement runs BEFORE any verdict aggregation (spec 189-193). Every check
# delegates to a FROZEN function; every STOP routes through the shared stop path
# (choke-point notify + write-ahead manifest row) and RETURNS a stop result.
#   (1) Get-NeoChangedSet vs pinned baseline  - builder commit => STOP BUILDER_COMMIT
#       (empty actual diff => STOP EMPTY_CHANGED_SET - nothing legitimate routes on it)
#   (2) Assert-NeoChangedSetAllowed three-branch on the ACTUAL changed set
#       - judging/protected => STOP; outside approved => STOP
#   (3) Assert-NeoGovManifestReverify vs the pinned manifest - mismatch => STOP
#   (4) Invoke-NeoDiffRiskRederive on the actual changed set - escalate-only;
#       escalation => STOP RISK_ESCALATION + surface (higher-tier re-audit is S3b)
#   (5) C1c: Assert-NeoNoJudgingFix on each proposed fix target => STOP on judging.
# Returns @{ stopped=$false; changed_set; changed_count; changed_paths_hash;
#            rederive } on a clean chain, else the stop result.
function Invoke-NeoLoopRoundChecks {
  param(
    [Parameter(Mandatory = $true)]$Context,
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)]$Baseline,
    [Parameter(Mandatory = $true)][string[]]$ApprovedPaths,
    [Parameter(Mandatory = $true)][string[]]$ProtectedPaths,
    [Parameter(Mandatory = $true)][string]$PinnedGovManifestPath,
    [Parameter(Mandatory = $true)][string]$GovernedRoot,
    [Parameter(Mandatory = $true)][string]$DerivedAt,
    [Parameter(Mandatory = $true)]$RouterProfile,
    [Parameter(Mandatory = $true)]$RiskRow,
    [string[]]$ProposedFixTargets = @()
  )
  # F4 CLASSIFICATION: Assert-NeoLoopContext validates $Context FIRST (its OWN
  # structural guards stay bare-throw, contract-not-runtime - same circularity note
  # as Assert-NeoLoopAuditSatisfied: the STOP choke point consumes this same
  # $Context). AFTER $ctx is valid, the following guards are RUNTIME-REACHABLE (a
  # real round's supervisor supplies RepoRoot/Baseline/ApprovedPaths/gov-manifest
  # path/GovernedRoot/DerivedAt/RouterProfile/RiskRow as parameter values, and an
  # adversarial/malformed round can hit any of them), so each routes through
  # Complete-NeoLoopRoundStop (notify + write-ahead row) with CLASSIFIER_ERROR - not
  # a bare throw. The DerivedAt timestamp parse already fails closed with a
  # reason_code=LEDGER_FAILURE token via ConvertFrom-NeoRunTimestamp; routed below so
  # it too notifies + records a row.
  $ctx = Assert-NeoLoopContext -Context $Context
  if ([string]::IsNullOrWhiteSpace($RepoRoot) -or -not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail ("RepoRoot '" + (ConvertTo-NeoLoopAsciiLine $RepoRoot 120) + "' is not an existing directory => STOP") -RoundData @{})
  }
  if ($null -eq $Baseline -or [string]::IsNullOrWhiteSpace([string](Get-NeoProp $Baseline 'head_sha'))) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'a pinned Baseline with head_sha is required (Pin-NeoDispatchBaseline output) => STOP' -RoundData @{})
  }
  if (@($ApprovedPaths).Count -eq 0) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'ApprovedPaths is empty - an autonomous round always has an approved scope => STOP' -RoundData @{})
  }
  if ([string]::IsNullOrWhiteSpace($PinnedGovManifestPath)) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'PinnedGovManifestPath is blank => STOP' -RoundData @{})
  }
  if ([string]::IsNullOrWhiteSpace($GovernedRoot)) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'GovernedRoot is blank => STOP' -RoundData @{})
  }
  try { [void](ConvertFrom-NeoRunTimestamp $DerivedAt 'DerivedAt' 'LEDGER_FAILURE') }
  catch {
    $m = $_.Exception.Message
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData @{})
  }
  if ($null -eq $RouterProfile) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'RouterProfile is required (Resolve-NeoRouterProfile output) => STOP' -RoundData @{})
  }
  if ($null -eq $RiskRow) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'RiskRow is required (C5-frozen row - consumed, never authored) => STOP' -RoundData @{})
  }

  $baseSha = [string](Get-NeoProp $Baseline 'head_sha')
  $baseTree = [string](Get-NeoProp $Baseline 'tree_hash')
  if ([string]::IsNullOrWhiteSpace($baseTree)) { $baseTree = 'NOT_EVALUATED' }
  # S3a-FIX-3 CHANNEL SEPARATION: $roundData carries ONLY the round-diff (the caller-
  # suppliable set: baseline + changed-set summary) => passed as the -RoundData channel.
  # The engine-COMPUTED classification is accumulated separately in $engineData => passed
  # as the trusted -EngineData channel. This function is ENGINE code building -EngineData
  # from its OWN computation (never from a caller value); the channels stay disjoint.
  $roundData = @{ baseline_head_sha = $baseSha; baseline_tree_hash = $baseTree }
  $engineData = @{}

  # (1) actual changed set vs pinned baseline (I2/NF-3; commits forbidden).
  $changed = $null
  try { $changed = Get-NeoChangedSet -RepoRoot $RepoRoot -Baseline $Baseline }
  catch {
    $m = $_.Exception.Message
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData $roundData)
  }
  $changed = @($changed)
  if ($changed.Count -eq 0) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'EMPTY_CHANGED_SET' `
      -Detail 'builder returned with an EMPTY actual changed set - nothing legitimate routes on an empty diff (fail-closed)' -RoundData $roundData)
  }
  $roundData['changed_count'] = $changed.Count
  $roundData['changed_paths_hash'] = (Get-NeoStringSha256 (($changed | Sort-Object) -join "`n"))

  # (2) three-branch classification of EVERY changed path (I5; XC1 inside).
  try { [void](Assert-NeoChangedSetAllowed -RepoRoot $RepoRoot -ChangedSet $changed -ApprovedPaths $ApprovedPaths -ProtectedPaths $ProtectedPaths) }
  catch {
    $m = $_.Exception.Message
    $engineData['classification'] = 'STOPPED_THREE_BRANCH'
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData $roundData -EngineData $engineData)
  }
  $engineData['classification'] = 'THREE_BRANCH_CLEAN'

  # (3) governance-manifest re-verify vs the C5 pin (I3/NF-2; mismatch => STOP).
  try {
    $current = Build-NeoGovManifest -GovernedRoot $GovernedRoot -DerivedAt $DerivedAt
    [void](Assert-NeoGovManifestReverify -PinnedPath $PinnedGovManifestPath -Current $current -GovernedRoot $GovernedRoot)
  } catch {
    $m = $_.Exception.Message
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData $roundData -EngineData $engineData)
  }

  # (4) diff-time risk re-derive on the ACTUAL changed set (C6 I4, escalate-only).
  # GROUNDED MECHANISM NOTE (session-control correction, folded in): the router's
  # escalation refusal is a prose NEO-BLOCK thrown INSIDE Invoke-NeoDiffRiskRederive
  # (orch_router.ps1:368) with NO reason_code= token, so the function's escalated
  # return member is UNREACHABLE for the escalate case. THIS wrapper therefore
  # assigns the S3a surface code RISK_ESCALATION when the caught block carries the
  # STABLE anchor substring 'EXCEEDS frozen row risk' (the load-bearing phrase of
  # that one message); every other router block keeps its own extracted code /
  # UNKNOWN. No full-message parse.
  $red = $null
  try { $red = Invoke-NeoDiffRiskRederive -ChangedSet $changed -RouterProfile $RouterProfile -RiskRow $RiskRow -RepoRoot $RepoRoot }
  catch {
    $m = $_.Exception.Message
    $code = 'UNKNOWN'
    if ($m -like '*EXCEEDS frozen row risk*') { $code = 'RISK_ESCALATION' } else { $code = Get-NeoLoopReasonCode $m }
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode $code -Detail $m -RoundData $roundData -EngineData $engineData)
  }

  # (5) C1c: no proposed fix may land on a judging class (fail-closed tri-state
  # inside the frozen helper; class resolved against the ENGINE'S OWN live map -
  # Resolve-NeoGovernanceMapPath - never an app-supplied map).
  foreach ($target in @($ProposedFixTargets)) {
    if ([string]::IsNullOrWhiteSpace($target)) {
      return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'C1C_UNKNOWN_CHANGE_CLASS' `
        -Detail 'proposed fix target is blank - class cannot be resolved (fail-closed)' -RoundData $roundData -EngineData $engineData)
    }
    try {
      Assert-NeoSafeRel $target
      $mapPath = Resolve-NeoGovernanceMapPath
      $map = Get-NeoClassMap $mapPath
      $cls = Resolve-NeoArtifactClass $map ($target -replace '\\', '/')
      [void](Assert-NeoNoJudgingFix -ChangeClass $cls -TargetRel $target)
    } catch {
      $m = $_.Exception.Message
      return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData $roundData -EngineData $engineData)
    }
  }

  return @{
    stopped = $false
    changed_set = $changed
    changed_count = [int]$roundData['changed_count']
    changed_paths_hash = [string]$roundData['changed_paths_hash']
    baseline_head_sha = $baseSha
    baseline_tree_hash = $baseTree
    rederive = $red
  }
}

# ---- Assert-NeoLoopAuditSatisfied (VERDICT AGGREGATION + C4 SEAM; spec 192-194) ---
# Wraps BOTH frozen gates - never re-implements either:
#   * Assert-NeoAuditorSlotSatisfied w/ RequiredTierFloor='isolated' (NB-1: the
#     no-auditor-vacuum floor, ALL tiers - a null slot on a LOW row blocks inside
#     the frozen seam);
#   * Assert-NeoSpawnCorrelatedSlot (sec-0: the consumed slot must correlate with
#     EXACTLY ONE prior spawn-ledger entry; forged/uncorrelated/stale => BLOCK).
# Then the C4 FAIL-CLOSED SEAM: EffectiveRiskClass 'high' REQUIRES a current-round
# external GO from the external_audit_verdict lane. The lane is NOT WIRED in S3a,
# so NO input can produce that GO: every recognized status (incl. the vocabulary
# value 'GO', which is REFUSED as impossible-while-unwired) is not-GO => a HIGH
# slice CANNOT aggregate GO (STOP EXTERNAL_REQUIRED_UNAVAILABLE => surface; manual
# external via Raphael). No codex call, no adapter - a placeholder with an explicit
# lane-status contract (missing/stale/unparseable/NOT_WIRED all => not-GO).
# GO aggregate = slot-satisfied AND spawn-correlated AND (class != high OR external GO).
# Returns @{ stopped=$false; go=$true; slot; effective_seam_tier; external_lane_status }
# on GO, else the stop result (notify + write-ahead manifest row already landed).
function Assert-NeoLoopAuditSatisfied {
  param(
    [Parameter(Mandatory = $true)]$Context,
    [Parameter(Mandatory = $true)]$RiskRow,
    [Parameter(Mandatory = $true)][string]$EffectiveRiskClass,
    [Parameter(Mandatory = $true)]$EndReport,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [Parameter(Mandatory = $true)][string]$MasterIdentity,
    [Parameter(Mandatory = $true)][string]$BuilderIdentity,
    [Parameter(Mandatory = $true)]$Index,
    [Parameter(Mandatory = $true)][string]$RoundId,
    [string]$ExternalLaneStatus = 'NOT_WIRED',
    $RoundData
  )
  # F4 CLASSIFICATION (runtime-reachable STOP vs contract-assert), grounded per line:
  #   - Assert-NeoLoopContext (below) VALIDATES $Context FIRST; its OWN structural
  #     guards (null/stray/missing member, non-bool live flag) stay BARE-THROW and
  #     are CONTRACT-NOT-RUNTIME: a malformed $Context CANNOT be routed through the
  #     STOP choke point, because Complete-NeoLoopRoundStop CONSUMES that very
  #     $Context (run_root + notify mode) - routing a malformed-context failure
  #     through the path that needs the context is circular. That is why the context
  #     contract is validated at its OWN boundary and hard-throws.
  #   - EVERY guard AFTER $ctx is validated (EffectiveRiskClass casing/unknown,
  #     blank RoundId, null RiskRow/EndReport, blank SessionRoot/Master/Builder,
  #     null Index, unresolvable frozen row class) is RUNTIME-REACHABLE (a real or
  #     adversarial round supplies these as parameter values) AND $ctx now carries a
  #     valid run_root + notify mode, so each routes through Complete-NeoLoopRoundStop
  #     (choke-point notify + write-ahead manifest row) with reason_code
  #     CLASSIFIER_ERROR - never a bare throw (S3a headline: an engine call cannot
  #     forget to notify).
  $ctx = Assert-NeoLoopContext -Context $Context
  # S3a-FIX-3 CHANNEL SEPARATION (trust boundary (a): this is a PUBLIC ROUND-STAGE ENTRY -
  # its untrusted caller -RoundData is TIGHT-VALIDATED here at the boundary, then it fills
  # -EngineData ITSELF from its OWN gate computation, never by copying a caller value into
  # it). This closes the routed-STOP forgery: pre-fix the caller RoundData was copied whole
  # into $rd BEFORE the early guards fired, so a CLASSIFIER_ERROR row could claim GO lanes
  # gate A/C never validly produced. Now:
  #   * $callerDiff: ONLY the tight caller-suppliable round-diff set. Any engine-owned or
  #     unknown-to-schema key in the caller RoundData => BLOCK at this entry (before any
  #     guard's own STOP). Forwarded to Complete-NeoLoopRoundStop as -RoundData.
  #   * $engine: the ENGINE-computed lanes/classification/findings_summary/seam-tier this
  #     function derives below. Forwarded as the trusted -EngineData. NEVER seeded from the
  #     caller RoundData.
  $callerSuppliable = @('baseline_head_sha', 'baseline_tree_hash', 'changed_count', 'changed_paths_hash')
  $schemaKnown = @(
    'slice_id', 'round', 'attempt_seq', 'baseline_head_sha', 'baseline_tree_hash',
    'changed_count', 'changed_paths_hash', 'classification', 'findings_summary',
    'auditor_slot_status', 'auditor_slot_recommendation', 'auditor_identity',
    'external_lane_status', 'effective_seam_tier', 'cap_events', 'stop_reason_code',
    'notify_gate_class', 'notify_sent', 'notify_deduped', 'notify_refused',
    'notify_reason', 'timestamp_utc'
  )
  $callerDiff = @{}
  if ($null -ne $RoundData) {
    foreach ($k in @(Get-NeoPropNames $RoundData)) {
      $ks = [string]$k
      if ($callerSuppliable -contains $ks) {
        # Get-NeoVal: shape-preserving (arrays never unwrapped on the copy).
        $callerDiff[$ks] = (Get-NeoVal $RoundData $ks)
      }
      elseif ($schemaKnown -contains $ks) {
        New-NeoBlock "reason_code=LEDGER_FAILURE loop-audit: RoundData cannot set engine-owned field '$ks' (verdict lanes/classification/findings_summary are engine-computed) => STOP"
      }
      else {
        New-NeoBlock "reason_code=LEDGER_FAILURE loop-audit: RoundData carries unknown field '$ks' => STOP"
      }
    }
  }
  # $engine accumulates the engine-COMPUTED fields as each gate runs. A stop BEFORE a
  # stage runs leaves that stage's field UNSET here => the STOP row keeps the honest
  # NOT_EVALUATED default (invariant iii).
  $engine = @{}
  if (@('high', 'medium', 'low') -cnotcontains $EffectiveRiskClass) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' `
      -Detail ("EffectiveRiskClass '" + (ConvertTo-NeoLoopAsciiLine $EffectiveRiskClass 40) + "' is not high|medium|low (the rederive's effective_class) => STOP (unknown => fail-closed, never assumed)") -RoundData $callerDiff -EngineData $engine)
  }
  if ([string]::IsNullOrWhiteSpace($RoundId)) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'RoundId is blank => STOP (a round always carries its id; fail-closed)' -RoundData $callerDiff -EngineData $engine)
  }
  if ($null -eq $RiskRow) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'RiskRow is required (C5-frozen row - consumed, never authored) => STOP' -RoundData $callerDiff -EngineData $engine)
  }
  if ($null -eq $EndReport) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'EndReport is required => STOP' -RoundData $callerDiff -EngineData $engine)
  }
  if ([string]::IsNullOrWhiteSpace($SessionRoot)) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'SessionRoot is blank => STOP' -RoundData $callerDiff -EngineData $engine)
  }
  if ([string]::IsNullOrWhiteSpace($MasterIdentity)) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'MasterIdentity is blank => STOP' -RoundData $callerDiff -EngineData $engine)
  }
  if ([string]::IsNullOrWhiteSpace($BuilderIdentity)) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'BuilderIdentity is blank => STOP' -RoundData $callerDiff -EngineData $engine)
  }
  if ($null -eq $Index) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail 'schema Index is required => STOP' -RoundData $callerDiff -EngineData $engine)
  }

  # ---- F2: HIGH-row ESCALATE-ONLY CLAMP - a caller EffectiveRiskClass BELOW the
  # frozen RiskRow can NEVER downgrade it. The C4 high gate binds to the HIGHER of
  # the frozen RiskRow's risk_class and the caller-supplied EffectiveRiskClass:
  #   * rowClass is derived from the frozen RiskRow using the SAME lowercase
  #     vocabulary + ordering the frozen tier oracle uses (low<medium<high,
  #     $riskRank = @{ low=0; medium=1; high=2 } - verbatim orch_router.ps1); an
  #     unknown/blank row class => fail-closed STOP (an unresolvable frozen row class
  #     is a runtime event, and a caller class can never substitute for it).
  #   * effective = max(rowClass, EffectiveRiskClass) on that ordering.
  #   * a caller value STRICTLY BELOW the row is an INVERSION: CLAMP UP
  #     (escalate-only, DISCLOSED in the row's findings_summary + the STOP detail) -
  #     never honored downward. The clamped tier is what gate C and the manifest row
  #     (NB-1) see. (The EffectiveRiskClass vocabulary guard above already fails
  #     closed on an unknown CALLER value.)
  # B1 (S3a-FIX-2): CASE-NORMALIZE the frozen risk class BEFORE any comparison, then
  # validate membership CASE-EXACT. A PS hashtable lookup is case-INSENSITIVE, so a raw
  # $rowClass='HIGH' would pass ContainsKey/index yet carry uppercase into $effectiveClass,
  # and gate C (:715 -ceq 'high') is case-EXACT => the HIGH external gate would be SKIPPED
  # (the F2 downgrade re-entered via casing). Fix: fold the VALUE to canonical lowercase,
  # keep the CHECK case-exact (never loosen a guard to case-insensitive). Only the risk
  # class (low|medium|high) is normalized here - the audit slot's effective_seam_tier
  # (set later from $slot.effective_tier) is a DISTINCT concept and is untouched.
  $rowClass = ([string](Get-NeoProp $RiskRow 'risk_class')).ToLowerInvariant()
  $riskRank = @{ low = 0; medium = 1; high = 2 }
  if (@('low', 'medium', 'high') -cnotcontains $rowClass) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' `
      -Detail ("RiskRow.risk_class '" + (ConvertTo-NeoLoopAsciiLine $rowClass 40) + "' is not low|medium|high => STOP (unresolvable frozen row class => fail-closed; a caller class can never substitute for it)") -RoundData $callerDiff -EngineData $engine)
  }
  # $EffectiveRiskClass is ALREADY case-exact-lowercase (rejected at the -cnotcontains
  # guard against the lowercase set); folding it here is belt-and-suspenders for the max
  # arithmetic and never widens that guard.
  $callerClass = $EffectiveRiskClass.ToLowerInvariant()
  $effectiveClass = $callerClass
  if ($riskRank[$rowClass] -gt $riskRank[$callerClass]) {
    # inversion: caller value below the frozen row => escalate-only clamp UP. The clamped
    # effective class is CANONICAL LOWERCASE, so gate C's case-exact -ceq 'high' fires for
    # every high spelling; the disclosure records the canonical lowercase classes. F2
    # findings_summary is ENGINE-computed => written to the trusted $engine channel (a
    # caller findings_summary is already REFUSED at the entry validation, so no collision).
    $effectiveClass = $rowClass
    $engine['findings_summary'] = (ConvertTo-NeoLoopAsciiLine ("effective risk CLAMPED UP from caller '" + $callerClass + "' to frozen row class '" + $rowClass + "' (escalate-only; a caller class below the frozen row can never downgrade it)") 200)
  }

  # external lane status: recognized vocabulary only; unknown => STOP (an
  # unparseable lane report is an EVENT, not a pass) - fail-closed, never
  # fall-through. The lane status is ENGINE-computed => $engine channel.
  if ($script:NeoLoopExternalLaneStatuses -cnotcontains $ExternalLaneStatus) {
    $engine['external_lane_status'] = 'UNPARSEABLE'
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'EXTERNAL_LANE_INVALID' `
      -Detail ("external lane status '" + (ConvertTo-NeoLoopAsciiLine $ExternalLaneStatus 60) + "' is not in the recognized set (" + ($script:NeoLoopExternalLaneStatuses -join ', ') + ") => STOP (fail-closed)") -RoundData $callerDiff -EngineData $engine)
  }
  $engine['external_lane_status'] = $ExternalLaneStatus

  # gate A: the frozen auditor-slot seam @ the NB-1 escalate-only floor.
  $slot = $null
  try {
    $slot = Assert-NeoAuditorSlotSatisfied -RiskRow $RiskRow -EndReport $EndReport -SessionRoot $SessionRoot `
      -MasterIdentity $MasterIdentity -BuilderIdentity $BuilderIdentity -Index $Index -RequiredTierFloor 'isolated'
  } catch {
    $m = $_.Exception.Message
    $code = Get-NeoLoopReasonCode $m
    # the frozen slot gate's messages carry no reason_code= token; the S3a surface
    # code AUDITOR_SLOT_UNSATISFIED names that event honestly (detail = original).
    if ($code -ceq 'UNKNOWN') { $code = 'AUDITOR_SLOT_UNSATISFIED' }
    $engine['auditor_slot_status'] = 'BLOCKED'
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode $code -Detail $m -RoundData $callerDiff -EngineData $engine)
  }
  $engine['auditor_slot_status'] = 'SATISFIED'
  $engine['auditor_slot_recommendation'] = [string]$slot.recommendation
  $engine['auditor_identity'] = [string]$slot.auditor_identity
  $engine['effective_seam_tier'] = [string]$slot.effective_tier

  # gate B: sec-0 spawn-ledger correlation on the CONSUMED slot (check==use: the
  # correlation gate re-reads the ledger fail-closed itself).
  try {
    $slotObj = [pscustomobject]@{ auditor_identity = [string]$slot.auditor_identity; bundle_ref = [string]$slot.bundle_ref }
    [void](Assert-NeoSpawnCorrelatedSlot -RunRoot $ctx.run_root -Slot $slotObj -RoundId $RoundId)
  } catch {
    $m = $_.Exception.Message
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData $callerDiff -EngineData $engine)
  }

  # gate C: the C4 EVIDENCE-BACKED seam (WIRED this slice). A caller lane claim is
  # NEVER authority: 'GO' is honored ONLY when the shared on-disk derivation
  # (Get-NeoExternalLaneStatus, orch_external.ps1 - ONE rule in ONE place, called at
  # BOTH boundaries) re-derives GO for the FULL CURRENT BINDING TUPLE (run_id +
  # slice_id + round_id + the hash of THIS round's slot-consumed bundle - the SAME
  # bundle gate A validated and gate B spawn-correlated, resolved by the SAME
  # containment rule) WITH the dual ledger re-correlation. A bare/forged 'GO' with
  # no validating record => EXTERNAL_LANE_INVALID STOP (fail-closed; the engine
  # channel records the DERIVED status, never the forged claim). The HIGH
  # determination binds to $effectiveClass (F2: max(frozen row class, caller value)),
  # so a caller EffectiveRiskClass below a HIGH frozen row cannot skip this gate.
  if ($ExternalLaneStatus -ceq 'GO') {
    $derived = 'UNPARSEABLE'
    $derivedReason = ''
    try {
      $tupleRef = [string]$slot.bundle_ref
      Assert-NeoSafeRel $tupleRef
      $tupleBundleFull = Assert-NeoContained $SessionRoot $tupleRef
      $tupleHash = Get-NeoSha256File $tupleBundleFull
      $d = Get-NeoExternalLaneStatus -RunRoot $ctx.run_root -SliceId $ctx.slice_id -RoundId $RoundId -BundleDiffHash $tupleHash -Index $Index
      $derived = [string]$d.status
      $derivedReason = [string]$d.reason
    } catch {
      $derived = 'UNPARSEABLE'
      $derivedReason = ('gate-C lane derivation failed (fail-closed): ' + (ConvertTo-NeoLoopAsciiLine $_.Exception.Message 160))
    }
    if ($derived -cne 'GO') {
      $engine['external_lane_status'] = $derived
      return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'EXTERNAL_LANE_INVALID' `
        -Detail ("external lane reported GO but the on-disk derivation returned '" + $derived + "' (" + (ConvertTo-NeoLoopAsciiLine $derivedReason 220) + ") - a caller lane claim is never authority (check==use at the consumption boundary) => STOP (fail-closed)") -RoundData $callerDiff -EngineData $engine)
    }
  }
  if (($effectiveClass -ceq 'high') -and ($ExternalLaneStatus -cne 'GO')) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'EXTERNAL_REQUIRED_UNAVAILABLE' `
      -Detail ("HIGH slice requires a current-round external GO; effective risk class '" + $effectiveClass + "' (row='" + $rowClass + "', caller='" + $EffectiveRiskClass + "') with external lane status '" + $ExternalLaneStatus + "' (no validated current-round external GO) => cannot aggregate GO; fall back to manual-external via Raphael") -RoundData $callerDiff -EngineData $engine)
  }

  # ---- F1: the GO-aggregate RECOMMENDATION gate. The frozen slot seam's "satisfied"
  # means "verdict present + valid + consistent" (re-validated vs the bundle_ref
  # verdict artifact), NOT "== GO". A GO aggregate therefore additionally REQUIRES
  # slot.recommendation -ceq 'GO' (case-exact). A VALID, spawn-correlated slot whose
  # recommendation is NEEDS-MORE or NO-GO is the NORMAL ITERATE signal (spec sec-5
  # L194-195 "if GO -> break; else scoped fix dispatch"; C1 L54 "on NEEDS-MORE/NO-GO
  # -> auto-generate a SCOPED fix dispatch and re-dispatch"), NOT a breaker or an
  # enforcement STOP: return a NON-stopped, NON-go result carrying the recommendation
  # so the S3b wrapper dispatches a fix round. This path does NOT route through the
  # STOP choke point - a plain non-GO verdict is not an escalation (no notify, no STOP
  # row from here). The round's manifest row is recorded by the CALLER via
  # Add-NeoIterationManifestEntry - the SAME one-row-per-round caller-records contract
  # as a clean-GO round (a non-GO round's row is identical in shape; only its
  # auditor_slot_recommendation differs). A FORGED/uncorrelated/invalid slot never
  # reaches here: it already escalated via the frozen seam (gate A) or gate B.
  $slotRec = [string]$slot.recommendation
  if ($slotRec -ceq 'GO') {
    # GO aggregate: slot-satisfied AND spawn-correlated AND recommendation==GO AND
    # (effective class != high OR current-round external GO). The CALLER records
    # this round's manifest row (one row per round contract).
    return @{
      stopped = $false; go = $true; slot = $slot
      effective_seam_tier = [string]$slot.effective_tier
      external_lane_status = $ExternalLaneStatus
    }
  }
  if (@('NEEDS-MORE', 'NO-GO') -ccontains $slotRec) {
    # normal ITERATE: valid, correlated non-GO verdict => S3b dispatches a fix round.
    return @{
      stopped = $false; go = $false; slot = $slot
      recommendation = $slotRec
      effective_seam_tier = [string]$slot.effective_tier
      external_lane_status = $ExternalLaneStatus
    }
  }
  # defense-in-depth: the frozen seam already restricts recommendation to
  # GO|NEEDS-MORE|NO-GO, so this is unreachable; if a future seam change ever admitted
  # another value, fail closed rather than aggregating GO on an unrecognized verdict.
  return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'AUDITOR_SLOT_UNSATISFIED' `
    -Detail ("auditor slot recommendation '" + (ConvertTo-NeoLoopAsciiLine $slotRec 40) + "' is not GO|NEEDS-MORE|NO-GO => STOP (fail-closed; never aggregated as GO)") -RoundData $callerDiff -EngineData $engine)
}

# ---- NF-1 deny-contract helper (assemble-side AND consume-side, one rule) --------
# A proposed edit whose canonical forward-slash spelling matches ANY denied entry
# (exact rel, or glob via the frozen Test-NeoGlobMatch, or prefix of a '/**' tree
# deny) => BLOCK DENIED_PATH. Reused by New-NeoLoopRoundDispatch at assembly and
# available to packet consumers for the re-check (check==use, one rule one place).
#
# F4 CLASSIFICATION: this reusable PURE HELPER hard-throws DENIED_PATH; that is
# correct because its one loop caller - New-NeoLoopRoundDispatch - CATCHES the throw
# and routes it through the choke point (notify + write-ahead row) as a runtime STOP.
# consume-side re-check callers (packet firewall) want the raw throw. One rule, one
# place: the helper throws; the loop caller routes. (Grep the dispatch: the
# Assert-NeoLoopDeniedPaths call is wrapped in try/catch -> Complete-NeoLoopRoundStop.)
function Assert-NeoLoopDeniedPaths {
  param(
    # deliberately NOT Mandatory (PS 5.1 refuses empty arrays on Mandatory params):
    # an EMPTY Rels list has nothing to check (the NF-1 empty-dispatch STOP is the
    # sibling guard); an EMPTY DeniedPaths must reach the fail-closed BLOCK inside,
    # never die as a raw parameter-binding error.
    [AllowEmptyCollection()][AllowEmptyString()][string[]]$Rels = @(),
    [AllowEmptyCollection()][AllowEmptyString()][string[]]$DeniedPaths = @()
  )
  $denied = @($DeniedPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($denied.Count -eq 0) {
    New-NeoBlock "reason_code=DENIED_PATH deny contract is EMPTY - the DENIED_PATHS member can never be vacated => BLOCK (fail-closed)"
  }
  foreach ($rel in @($Rels)) {
    if ([string]::IsNullOrWhiteSpace($rel)) {
      New-NeoBlock "reason_code=DENIED_PATH proposed edit rel is blank => BLOCK (fail-closed)"
    }
    $norm = ([string]$rel) -replace '\\', '/'
    foreach ($d in $denied) {
      $dn = ([string]$d) -replace '\\', '/'
      $hit = $false
      if ($dn.EndsWith('/**')) {
        $prefix = $dn.Substring(0, $dn.Length - 3)
        if (($norm -ieq $prefix) -or $norm.StartsWith($prefix + '/', [System.StringComparison]::OrdinalIgnoreCase)) { $hit = $true }
      } elseif ($dn.IndexOf('*') -ge 0) {
        $hit = Test-NeoGlobMatch $norm $dn
      } else {
        $hit = ($norm -ieq $dn)
      }
      if ($hit) {
        New-NeoBlock "reason_code=DENIED_PATH proposed edit '$rel' is inside the denied surface '$d' => STOP at dispatch (defense-in-depth; the governance-manifest re-verify stays the load-bearing check)"
      }
    }
  }
  return $true
}

# ---- New-NeoLoopRoundDispatch (NF-1 DISPATCH-TIME + FS-DENY; spec 74-79 + 100-102) -
# Assembles one round's builder dispatch:
#   (1) deny contract: '.neo/**' + the governance-tree rels (default = the S2b
#       mandatory floor, ALWAYS non-empty) checked against EVERY proposed edit -
#       a hit => STOP DENIED_PATH at dispatch time;
#   (2) Assert-NeoDispatchProposedEdits - empty/missing ProposedEdits => STOP
#       EMPTY_PROPOSED_EDITS; three-branch dispatch-time routing per edit;
#   (3) New-NeoFirewalledBuilderPacket (the FROZEN C2 assembler - untouched).
# The DENIED_PATHS contract member lives in THIS wrapper record (the packet's
# schema-fixed shape carries no such member; the frozen supervisor stays frozen).
# The spawner (S3b) must enforce it on the sub-agent's filesystem;
# Test-NeoBuilderPacketFirewall-side consumers re-check via Assert-NeoLoopDeniedPaths.
# Every STOP routes through the shared stop path (notify + write-ahead row).
# Returns @{ stopped=$false; packet; denied_paths; routes } on success.
function New-NeoLoopRoundDispatch {
  param(
    [Parameter(Mandatory = $true)]$Context,
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    # deliberately NOT Mandatory: an EMPTY or MISSING ProposedEdits list must reach
    # the fail-closed NF-1 guard (STOP EMPTY_PROPOSED_EDITS with a manifest row +
    # notification), never die as a raw parameter-binding error.
    [AllowEmptyCollection()][string[]]$ProposedEdits = @(),
    [Parameter(Mandatory = $true)][string[]]$ApprovedPaths,
    [Parameter(Mandatory = $true)][string[]]$ProtectedPaths,
    [Parameter(Mandatory = $true)][string]$Goal,
    [Parameter(Mandatory = $true)][string]$RiskClass,
    [Parameter(Mandatory = $true)]$AllowlistItems,
    [Parameter(Mandatory = $true)][string[]]$TestPlan,
    [Parameter(Mandatory = $true)][string[]]$StopConditions,
    [string[]]$DeclaredSurfaces = @(),
    [string]$Timestamp = '2026-07-06T00:00:00Z',
    [string]$PacketId = 'neo-s3a-round-dispatch',
    [string[]]$DeniedPaths
  )
  # F4: $ctx is validated FIRST (contract-not-runtime bare-throw inside
  # Assert-NeoLoopContext); AFTER it is valid the RepoRoot guard is RUNTIME-REACHABLE
  # (a real dispatch supplies RepoRoot) => route through the choke point (notify +
  # write-ahead row), CLASSIFIER_ERROR, not a bare throw.
  $ctx = Assert-NeoLoopContext -Context $Context
  if ([string]::IsNullOrWhiteSpace($RepoRoot) -or -not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode 'CLASSIFIER_ERROR' -Detail ("RepoRoot '" + (ConvertTo-NeoLoopAsciiLine $RepoRoot 120) + "' is not an existing directory => STOP") -RoundData @{})
  }
  # F3: NF-4 MANDATORY-UNION deny contract (verbatim the S2b govmanifest floor
  # lesson). The mandatory floor - '.neo/**' + the governance-tree rels - is ALWAYS
  # present; a caller-supplied DeniedPaths list is ADDITIVE-UNION only. It can NEVER
  # REPLACE the floor: an empty/absent caller list still carries the full floor, and
  # the floor can never be vacated. (The prior `if ContainsKey { $deny = @($DeniedPaths) }`
  # let a caller list REPLACE the floor - e.g. -DeniedPaths @('docs/**') vacated the
  # .neo/** floor - which this closes.) Assert-NeoLoopDeniedPaths's wholly-empty
  # refusal stays the second layer.
  $deny = @('.neo/**') + @($script:NeoGovDefaultMandatoryRels) + @($DeniedPaths)

  # (1) deny check on every proposed edit (belt-and-suspenders; three-branch below
  # stays the load-bearing routing decision).
  try { [void](Assert-NeoLoopDeniedPaths -Rels @($ProposedEdits) -DeniedPaths $deny) }
  catch {
    $m = $_.Exception.Message
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m)
  }

  # (2) NF-1: empty ProposedEdits => STOP; three-branch routing per edit.
  $routes = $null
  try { $routes = Assert-NeoDispatchProposedEdits -RepoRoot $RepoRoot -ProposedEdits @($ProposedEdits) -ApprovedPaths $ApprovedPaths -ProtectedPaths $ProtectedPaths }
  catch {
    $m = $_.Exception.Message
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m)
  }

  # (3) the frozen C2 firewalled assembler (context firewall; PURE - writes nothing).
  $packet = $null
  try {
    $packet = New-NeoFirewalledBuilderPacket -Goal $Goal -ApprovedPaths $ApprovedPaths -ProtectedPaths $ProtectedPaths `
      -RiskClass $RiskClass -AllowlistItems $AllowlistItems -TestPlan $TestPlan -StopConditions $StopConditions `
      -RepoRoot $RepoRoot -DeclaredSurfaces $DeclaredSurfaces -Timestamp $Timestamp -PacketId $PacketId
  } catch {
    $m = $_.Exception.Message
    return (Complete-NeoLoopRoundStop -Context $ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m)
  }

  return @{
    stopped = $false
    packet = $packet
    denied_paths = @($deny)
    routes = @($routes)
  }
}

# ==================================================================================
# ---- S3b: THE MULTI-ROUND CONVERGENCE WRAPPER (spec sec-5 lines 184-198) ---------
# ==================================================================================

# ---- Invoke-NeoLoopWallClockGate (S3b-internal breaker check; C3 / DEF-P7 4h) ----
# ONE wall-clock check, used at round 0 AND before EVERY fix dispatch. Persisted-
# state only (Test-NeoRunWallClock reads started_at_utc + caps from the run
# manifest - the frozen S1 gate; no crafted-object lane exists). NowUtc is
# ENGINE-READ inside this function (S3b-FIX CX-F1: the -NowUtcProvider caller
# time-authority channel is REMOVED - cap arithmetic = persisted started_at_utc
# + the engine's OWN clock read, NOTHING caller-supplied). FAIL-CLOSED time
# semantics: a malformed/regressed NowUtc is treated as a wall-clock event
# ("never 'not yet tripped'" - the frozen gate's own rule), so every failure
# path here routes the choke point as CAP_WALL_CLOCK/CAPS_INVALID
# (BREAKER_TRIP class) with a write-ahead manifest STOP row.
# Returns @{ stopped=$false; now_utc } when the gate passes, else the stop result.
function Invoke-NeoLoopWallClockGate {
  param(
    [Parameter(Mandatory = $true)]$Ctx              # ALREADY normalized by Assert-NeoLoopContext
  )
  # engine-read now, in the EXACT persisted-state format the frozen gate parses.
  $nowUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $wall = $null
  try { $wall = Test-NeoRunWallClock -RunRoot $Ctx.run_root -NowUtc $nowUtc }
  catch {
    # frozen-gate failures carry their own codes (CAP_WALL_CLOCK malformed/regressed
    # clock, CAPS_INVALID missing caps) - route them, never re-classify.
    $m = $_.Exception.Message
    return (Complete-NeoLoopRoundStop -Context $Ctx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData @{})
  }
  if ([bool]$wall.tripped) {
    $engine = @{ cap_events = @((ConvertTo-NeoLoopAsciiLine ("CAP_WALL_CLOCK: elapsed_hours=" + $wall.elapsed_hours + " exceeds cap_hours=" + $wall.cap_hours + " measured from the PERSISTED started_at_utc") 200)) }
    return (Complete-NeoLoopRoundStop -Context $Ctx -ReasonCode 'CAP_WALL_CLOCK' `
      -Detail ("wall-clock breaker TRIPPED: elapsed " + $wall.elapsed_hours + "h exceeds the " + $wall.cap_hours + "h cap (persisted run start; crash-safe, not process uptime) => STOP") -RoundData @{} -EngineData $engine)
  }
  return @{ stopped = $false; now_utc = $nowUtc }
}

# ---- Invoke-NeoLoopConverge (C1 auto-act + C3 circuit-breaker looping) -----------
# Drives ONE SLICE to convergence, STRICTLY SERIAL, by wiring the FROZEN S1 breaker
# gates and the S3a round stages together. COORDINATION-only crown jewel (same
# discipline as the S3a header): it NEVER authors a verdict, NEVER writes an
# AUDIT_RESULT, NEVER edits the governed tree, NEVER decides an approval - its
# convergence is nothing but "the frozen aggregation gate said GO".
#
# LOOP ORDER per round (spec sec-5 186-195):
#   wall-clock gate -> WRITE-AHEAD attempt-ledger entry (NB-2: the entry precedes
#   the dispatch it counts; at the cap the ENTRY LANDS and the DISPATCH is refused)
#   -> Pin-NeoDispatchBaseline -> New-NeoLoopRoundDispatch -> BUILDER SEAM ->
#   Invoke-NeoLoopRoundChecks -> Assert-NeoLoopAuditSatisfied ->
#     GO      => caller-record the round's ONE manifest row (NB1) -> BREAK;
#     non-GO  => caller-record the row (recommendation preserved) -> wall-clock
#                gate again -> write-ahead 'fix' ledger entry -> SCOPED fix
#                re-dispatch bounded to the SAME ApprovedPaths -> re-loop.
# ROUND COUNTING (C3 110-125): round 0 = 'initial' (never counts against the fix
# cap); fix rounds are 1..3; the 4th fix is refused BY THE LEDGER (post-increment
# vs cap) - this wrapper adds NO cap arithmetic of its own. Loop exit is
# STRUCTURALLY guaranteed: every iteration either converges, STOPs, or lands a
# counted fix entry that the frozen cap eventually refuses.
#
# ROW DISCIPLINE (NB1, one row per round):
#   * STOP rounds: the row + notification ALREADY landed write-ahead inside the
#     round core / stop path - this wrapper surfaces the stop result UNCHANGED
#     (wrapped in the converge envelope) and records NO second row.
#   * GO / non-GO rounds: THIS WRAPPER is the NB1 caller - it records the round's
#     single row from its OWN captured stage outputs (never from the seam or the
#     provider). stop_reason_code='NONE', notify_* = NONE/false/'' - a converged
#     round notifies NOTHING (the human END surface is S3c's).
#   * A caller-record row-write failure propagates as the writer's thrown
#     LEDGER_FAILURE (fail-closed): a round that cannot be recorded never
#     continues, and routing a manifest-write failure through the manifest-writing
#     stop path would be circular (the S3a writer-contract exception, unchanged).
#
# BUILDER-INVOCATION SEAM (containment story, all load-bearing):
#   * The wrapper does NOT spawn sub-agents (the outer supervisor owns C2 spawn +
#     firewall + spawn ledger). -BuilderSeam is a caller-supplied scriptblock
#     invoked between dispatch and round checks with ONE argument
#     @{ packet; round; kind; repo_root; denied_paths } (the firewalled packet the
#     frozen C2 assembler built - no supervisor context crosses the seam).
#   * The seam's RETURN VALUE IS NEVER AN AUTHORITY INPUT: it is DISCARDED at the
#     call site ($null = ...). Every verdict/change fact the loop acts on comes
#     from the FROZEN gates reading DISK after the seam ran (Get-NeoChangedSet vs
#     the pinned baseline; the slot/spawn/lane gates; the rederive). A seam
#     returning forged GO/verdict/EndReport-shaped data changes NOTHING.
#   * A seam that THROWS => routed STOP BUILDER_SEAM_FAILED (detail = the caught
#     message, ASCII-capped - grounded, not invented). A null/absent/non-
#     scriptblock seam => the same routed STOP fail-closed BEFORE any ledger
#     write or dispatch (an autonomous round has NO default builder).
#
# PER-ROUND AUDIT SOURCING (START clarification C2): -AuditProvider is a caller-
# supplied scriptblock invoked ONCE per round with @{ round; round_id; slice_id }.
# It returns PATHS ONLY - member set EXACTLY { end_report_path; session_root } -
# and the wrapper reads the END report from DISK via the frozen engine reader
# (Read-NeoEndReport) and hands it to the frozen aggregation gate, which
# re-validates the verdict against the bundle_ref artifact ON DISK and re-checks
# spawn correlation against the RunRoot ledger. Seam-return injection into the
# audit stage is impossible BY CONSTRUCTION: the seam's return was discarded at
# step (6) and the provider channel never sees it. A provider that is null/throws/
# returns a malformed member set => routed STOP fail-closed. The provider is a
# LOCATOR, not an authority: a forged world it points at still fails the frozen
# slot re-validation / spawn correlation / run_id binding.
#
# PER-ROUND EFFECTIVE RISK CLASS (START clarification C1): fed from THIS round's
# OWN rederive output (round-checks result .rederive.effective_class - the C6
# frozen-row authority), NEVER a static caller value across rounds. Absent/blank
# => routed STOP CLASSIFIER_ERROR (never assumed). The F2 escalate-only clamp in
# the aggregation gate stays as defense-in-depth behind it.
#
# SCOPE DISCIPLINE (C1 54-56): every fix re-dispatch is bounded to the SAME
# ApprovedPaths/ProtectedPaths/DeniedPaths the caller supplied (never widened;
# the deny floor re-unions inside the frozen-shape dispatch assembler every
# round). The fix round's ProposedEdits are the prior round's ACTUAL changed set
# (engine-derived by the frozen diff gate from DISK - never seam-supplied, never
# verdict-supplied), so the fix targets exactly the surfaces that were built and
# the dispatch-time three-branch re-routes every one of them. The C1c
# ProposedFixTargets lane carries the CALLER'S DECLARED fix targets into EVERY
# round's screen (see the step-12 note: the frozen C1c tri-state passes ONLY a
# registered 'implementation' class - it screens declared judging-risky intents,
# and stays untouched).
#
# C4 IS WIRED THROUGH A PROVIDER SEAM (this slice): the external lane is NO LONGER
# hard-pinned - on a HIGH round the wrapper invokes the caller-supplied
# $ExternalProvider seam (the orch_external adapter in production), then DERIVES the
# lane from the ON-DISK verdict record via the shared Get-NeoExternalLaneStatus (a
# caller-supplied lane string would be a forgeable authority input - so the lane
# handed to aggregation is DISK-derived at boundary 1, and gate C RE-derives any GO
# at boundary 2: check==use). STRUCTURALLY PRESERVED: no codex call exists anywhere
# in THIS module - the live invoker lives in orch_external.ps1 only; this wrapper
# consumes its on-disk OUTPUT. LOW/MED rounds are the FAST LANE: no seam call, no
# egress, no budget burn, lane recorded as the honest 'MISSING' (no verdict exists
# for the round; gate C does not require one below high). C5 inputs (pinned
# manifest, risk row, router profile) arrive as parameters - consumed, never
# authored. The run-ledger budget writes live in orch_external's adapter.
#
# Returns:
#   converged: @{ stopped=$false; converged=$true; go=$true; rounds=@(trail);
#                 fix_rounds_used; final=<the GO aggregation result> }
#   stopped:   @{ stopped=$true; converged=$false; go=$false; stop=<the stop
#                 result, UNCHANGED>; rounds=@(trail); fix_rounds_used }
# where trail carries one @{ round; kind; attempt_seq; go; recommendation;
# changed_count; row } per COMPLETED (recorded) round.
function Invoke-NeoLoopConverge {
  param(
    [Parameter(Mandatory = $true)]$Context,          # per-round context PROTOTYPE (round/attempt_seq re-stamped per round)
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string[]]$ApprovedPaths,
    [Parameter(Mandatory = $true)][string[]]$ProtectedPaths,
    [Parameter(Mandatory = $true)][string]$PinnedGovManifestPath,
    [Parameter(Mandatory = $true)][string]$GovernedRoot,
    [Parameter(Mandatory = $true)][string]$DerivedAt,
    [Parameter(Mandatory = $true)]$RouterProfile,
    [Parameter(Mandatory = $true)]$RiskRow,
    [Parameter(Mandatory = $true)][string]$MasterIdentity,
    [Parameter(Mandatory = $true)][string]$BuilderIdentity,
    [Parameter(Mandatory = $true)]$Index,
    [Parameter(Mandatory = $true)][string]$Goal,
    [Parameter(Mandatory = $true)][string]$RiskClass,
    [Parameter(Mandatory = $true)]$AllowlistItems,
    [Parameter(Mandatory = $true)][string[]]$TestPlan,
    [Parameter(Mandatory = $true)][string[]]$StopConditions,
    # deliberately NOT Mandatory: an EMPTY round-0 ProposedEdits must reach the
    # frozen NF-1 fail-closed STOP (EMPTY_PROPOSED_EDITS with row + notification),
    # never die as a raw parameter-binding error.
    [AllowEmptyCollection()][string[]]$ProposedEdits = @(),
    [string[]]$DeclaredSurfaces = @(),
    [AllowEmptyCollection()][AllowEmptyString()][string[]]$DeniedPaths = @(),
    [AllowEmptyCollection()][string[]]$ProposedFixTargets = @(),
    [string]$RoundIdPrefix = 'round-',
    [string]$PacketIdPrefix = 'neo-s3b-round-dispatch-',
    # deliberately UNTYPED: a null/non-scriptblock seam or provider must reach the
    # routed fail-closed STOP below, never a raw binding error.
    # (S3b-FIX CX-F1: NO NowUtcProvider parameter exists - the wall-clock gate
    # reads the engine's own clock; a caller attempting to bind -NowUtcProvider
    # gets a parameter-binding failure, proving the channel is GONE.)
    $BuilderSeam,
    $AuditProvider,
    # C4 external provider seam (same discipline): deliberately untyped. Validated
    # AT THE HIGH ROUND that needs it, not at entry - LOW/MED runs legitimately omit
    # it (fast lane, no external channel); a HIGH round with a null/malformed seam
    # => routed fail-closed STOP (EXTERNAL_REQUIRED_UNAVAILABLE). Its return value
    # is NEVER authority - the lane is derived from DISK (see step 9b).
    $ExternalProvider
  )
  # F4: the Context contract is validated FIRST at its own boundary (bare-throw,
  # contract-not-runtime - the STOP choke point consumes this very context; same
  # circularity rationale as every S3a stage entry).
  $ctxProto = Assert-NeoLoopContext -Context $Context

  $trail = @()
  $fixUsed = 0

  # per-round context builder: clone the normalized prototype, stamp round +
  # attempt_seq. Every stage entry re-validates it (check==use).
  $newRoundCtx = {
    param([int]$r, [int]$s)
    return @{
      run_root = $ctxProto.run_root; slice_id = $ctxProto.slice_id
      round = $r; attempt_seq = $s
      evidence_path = $ctxProto.evidence_path; timestamp_utc = $ctxProto.timestamp_utc
      notify_test_mode_dir = $ctxProto.notify_test_mode_dir; notify_live_send = $ctxProto.notify_live_send
    }
  }
  # converge envelope for a STOP: the stop result itself is carried UNCHANGED.
  $finishStop = {
    param($stop)
    return @{ stopped = $true; converged = $false; go = $false; stop = $stop; rounds = @($trail); fix_rounds_used = $fixUsed }
  }
  $ctx0 = & $newRoundCtx 0 1

  # ---- boundary validation of the wrapper's OWN parameters (every public
  # function validates EVERY parameter at ITS OWN boundary; unknown/default =>
  # BLOCK). All of these are RUNTIME-REACHABLE (a real supervisor supplies them),
  # so each routes through the choke point - notify + write-ahead row.
  if (($null -eq $BuilderSeam) -or -not ($BuilderSeam -is [scriptblock])) {
    return (& $finishStop (Complete-NeoLoopRoundStop -Context $ctx0 -ReasonCode 'BUILDER_SEAM_FAILED' `
      -Detail 'builder-invocation seam is null/absent or not a scriptblock - an autonomous round has NO default builder => STOP (fail-closed, before any ledger write or dispatch)' -RoundData @{}))
  }
  if (($null -eq $AuditProvider) -or -not ($AuditProvider -is [scriptblock])) {
    return (& $finishStop (Complete-NeoLoopRoundStop -Context $ctx0 -ReasonCode 'CLASSIFIER_ERROR' `
      -Detail 'audit-world provider is null/absent or not a scriptblock - per-round audit inputs have NO default source => STOP (fail-closed)' -RoundData @{}))
  }
  if ([string]::IsNullOrWhiteSpace($RepoRoot) -or -not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    return (& $finishStop (Complete-NeoLoopRoundStop -Context $ctx0 -ReasonCode 'CLASSIFIER_ERROR' `
      -Detail ("RepoRoot '" + (ConvertTo-NeoLoopAsciiLine $RepoRoot 120) + "' is not an existing directory => STOP") -RoundData @{}))
  }
  if (@($ApprovedPaths).Count -eq 0) {
    return (& $finishStop (Complete-NeoLoopRoundStop -Context $ctx0 -ReasonCode 'CLASSIFIER_ERROR' `
      -Detail 'ApprovedPaths is empty - an autonomous slice always has an approved scope => STOP' -RoundData @{}))
  }
  foreach ($pair in @(
      @('PinnedGovManifestPath', $PinnedGovManifestPath), @('GovernedRoot', $GovernedRoot),
      @('MasterIdentity', $MasterIdentity), @('BuilderIdentity', $BuilderIdentity),
      @('Goal', $Goal), @('RiskClass', $RiskClass),
      @('RoundIdPrefix', $RoundIdPrefix), @('PacketIdPrefix', $PacketIdPrefix))) {
    if ([string]::IsNullOrWhiteSpace([string]$pair[1])) {
      return (& $finishStop (Complete-NeoLoopRoundStop -Context $ctx0 -ReasonCode 'CLASSIFIER_ERROR' `
        -Detail ("converge: parameter '" + $pair[0] + "' is blank => STOP (fail-closed)") -RoundData @{}))
    }
  }
  try { [void](ConvertFrom-NeoRunTimestamp $DerivedAt 'DerivedAt' 'LEDGER_FAILURE') }
  catch {
    $m = $_.Exception.Message
    return (& $finishStop (Complete-NeoLoopRoundStop -Context $ctx0 -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData @{}))
  }
  foreach ($pair in @(@('RouterProfile', $RouterProfile), @('RiskRow', $RiskRow), @('Index', $Index), @('AllowlistItems', $AllowlistItems))) {
    if ($null -eq $pair[1]) {
      return (& $finishStop (Complete-NeoLoopRoundStop -Context $ctx0 -ReasonCode 'CLASSIFIER_ERROR' `
        -Detail ("converge: parameter '" + $pair[0] + "' is null => STOP (fail-closed)") -RoundData @{}))
    }
  }

  # ---- the convergence loop (exit structurally guaranteed: GO / STOP / cap) -----
  $round = 0
  $kind = 'initial'
  $lastSeq = 0
  $nextProposedEdits = @($ProposedEdits)
  $nextFixTargets = @($ProposedFixTargets)

  while ($true) {
    # attempt_seq is provisional (lastSeq+1) until the ledger entry lands; a STOP
    # BEFORE the write-ahead entry honestly records the attempt being started.
    $roundCtx = & $newRoundCtx $round ($lastSeq + 1)

    # (1) wall-clock breaker gate (round 0 AND before every fix dispatch).
    $wall = Invoke-NeoLoopWallClockGate -Ctx $roundCtx
    if ($wall.stopped) { return (& $finishStop $wall) }

    # (2) WRITE-AHEAD attempt-ledger entry (NB-2: precedes the dispatch it counts;
    # ANY ledger failure => STOP through the choke point, never repair-and-continue).
    $led = $null
    try { $led = Add-NeoAttemptLedgerEntry -RunRoot $roundCtx.run_root -SliceId $roundCtx.slice_id -Round $round -Kind $kind -Timestamp ([string]$wall.now_utc) }
    catch {
      $m = $_.Exception.Message
      return (& $finishStop (Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData @{}))
    }
    $lastSeq = [int](Get-NeoProp $led.entry 'seq')
    $roundCtx = & $newRoundCtx $round $lastSeq
    if (($kind -ceq 'fix') -and -not [bool]$led.refused) { $fixUsed = [int]$led.post_increment_count }

    # (3) NB-2 cap refusal: the entry LANDED (write-ahead); the DISPATCH is what is
    # refused - the 4th fix dispatch NEVER runs. Manifest STOP row + BREAKER_TRIP
    # notification via the shared stop path; manifest count == ledger count holds.
    if ([bool]$led.refused) {
      $engine = @{ cap_events = @((ConvertTo-NeoLoopAsciiLine ("" + $led.reason + ": fix dispatch round " + $round + " REFUSED at the cap (post_increment_count=" + $led.post_increment_count + "); the write-ahead ledger entry LANDED - the dispatch is refused, never the ledger write (NB-2)") 200)) }
      $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode ([string]$led.reason) `
        -Detail ("circuit-breaker: fix-round cap reached for slice '" + $roundCtx.slice_id + "' - the write-ahead entry landed (seq " + $lastSeq + ", refused=true, reason " + $led.reason + ") and the fix dispatch was REFUSED; nothing runs past the cap (C3 110-125)") -RoundData @{} -EngineData $engine
      return (& $finishStop $stop)
    }

    # (4) pin the PRE-DISPATCH baseline (C1b: the changed set is diff(baseline..
    # worktree) including untracked; commits forbidden - the frozen diff gate rules).
    $baseline = $null
    try { $baseline = Pin-NeoDispatchBaseline -RepoRoot $RepoRoot }
    catch {
      $m = $_.Exception.Message
      return (& $finishStop (Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode (Get-NeoLoopReasonCode $m) -Detail $m -RoundData @{}))
    }

    # (5) round dispatch (NF-1 empty-edits STOP + deny-union + frozen C2 assembler;
    # every STOP inside already landed its row + notification write-ahead).
    $disp = New-NeoLoopRoundDispatch -Context $roundCtx -RepoRoot $RepoRoot -ProposedEdits @($nextProposedEdits) `
      -ApprovedPaths $ApprovedPaths -ProtectedPaths $ProtectedPaths -Goal $Goal -RiskClass $RiskClass `
      -AllowlistItems $AllowlistItems -TestPlan $TestPlan -StopConditions $StopConditions `
      -DeclaredSurfaces $DeclaredSurfaces -Timestamp $roundCtx.timestamp_utc `
      -PacketId ($PacketIdPrefix + $round) -DeniedPaths @($DeniedPaths)
    if ($disp.stopped) { return (& $finishStop $disp) }

    # (6) THE BUILDER SEAM. Return value DISCARDED - never an authority input.
    try {
      $null = & $BuilderSeam (@{ packet = $disp.packet; round = $round; kind = $kind; repo_root = $RepoRoot; denied_paths = @($disp.denied_paths) })
    } catch {
      $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode 'BUILDER_SEAM_FAILED' `
        -Detail ("builder-invocation seam THREW during round " + $round + ": " + (ConvertTo-NeoLoopAsciiLine $_.Exception.Message 160) + " => STOP (reason grounded in the caught failure; the seam return is never authority)") -RoundData @{}
      return (& $finishStop $stop)
    }

    # (7) post-builder enforcement chain - FROZEN gates read DISK (the seam's
    # return played no part; a forged seam "success" changes nothing here).
    $chk = Invoke-NeoLoopRoundChecks -Context $roundCtx -RepoRoot $RepoRoot -Baseline $baseline `
      -ApprovedPaths $ApprovedPaths -ProtectedPaths $ProtectedPaths -PinnedGovManifestPath $PinnedGovManifestPath `
      -GovernedRoot $GovernedRoot -DerivedAt $DerivedAt -RouterProfile $RouterProfile -RiskRow $RiskRow `
      -ProposedFixTargets @($nextFixTargets)
    if ($chk.stopped) { return (& $finishStop $chk) }
    $roundDiff = @{
      baseline_head_sha = [string]$chk.baseline_head_sha; baseline_tree_hash = [string]$chk.baseline_tree_hash
      changed_count = [int]$chk.changed_count; changed_paths_hash = [string]$chk.changed_paths_hash
    }

    # (8) per-round effective risk class - THIS round's rederive output (START C1);
    # absent/blank => fail-closed, never assumed, never a stale caller value.
    $effClass = ''
    if ($null -ne $chk.rederive) { $effClass = [string](Get-NeoProp $chk.rederive 'effective_class') }
    if ([string]::IsNullOrWhiteSpace($effClass)) {
      $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode 'CLASSIFIER_ERROR' `
        -Detail 'round rederive carries no effective_class - the per-round effective risk class is never assumed => STOP (fail-closed)' -RoundData $roundDiff
      return (& $finishStop $stop)
    }

    # (9) per-round audit world (START C2): the provider LOCATES paths; the frozen
    # reader + gates on DISK stay the authority. Member set EXACT; fail-closed.
    $roundId = $RoundIdPrefix + $round
    $world = $null
    try { $world = & $AuditProvider (@{ round = $round; round_id = $roundId; slice_id = $roundCtx.slice_id }) }
    catch {
      $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode 'CLASSIFIER_ERROR' `
        -Detail ("audit-world provider THREW for round " + $round + ": " + (ConvertTo-NeoLoopAsciiLine $_.Exception.Message 160) + " => STOP (fail-closed)") -RoundData $roundDiff
      return (& $finishStop $stop)
    }
    $worldMembers = @('end_report_path', 'session_root')
    $worldOk = ($null -ne $world)
    if ($worldOk) {
      $names = @(Get-NeoPropNames $world)
      if (@($names).Count -ne $worldMembers.Count) { $worldOk = $false }
      foreach ($n in $names) { if ($worldMembers -cnotcontains [string]$n) { $worldOk = $false } }
      foreach ($n in $worldMembers) { if (-not (Test-NeoHasProp $world $n)) { $worldOk = $false } }
    }
    if (-not $worldOk) {
      $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode 'CLASSIFIER_ERROR' `
        -Detail ("audit-world provider returned a malformed member set for round " + $round + " - member set must be EXACTLY {" + ($worldMembers -join ', ') + "} => STOP (fail-closed)") -RoundData $roundDiff
      return (& $finishStop $stop)
    }
    $erPath = [string](Get-NeoProp $world 'end_report_path')
    $sessRoot = [string](Get-NeoProp $world 'session_root')
    if ([string]::IsNullOrWhiteSpace($erPath) -or -not (Test-Path -LiteralPath $erPath -PathType Leaf)) {
      $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode 'CLASSIFIER_ERROR' `
        -Detail ("audit-world end_report_path '" + (ConvertTo-NeoLoopAsciiLine $erPath 120) + "' is blank or not an existing file => STOP (fail-closed)") -RoundData $roundDiff
      return (& $finishStop $stop)
    }
    if ([string]::IsNullOrWhiteSpace($sessRoot) -or -not (Test-Path -LiteralPath $sessRoot -PathType Container)) {
      $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode 'CLASSIFIER_ERROR' `
        -Detail ("audit-world session_root '" + (ConvertTo-NeoLoopAsciiLine $sessRoot 120) + "' is blank or not an existing directory => STOP (fail-closed)") -RoundData $roundDiff
      return (& $finishStop $stop)
    }
    $endLive = $null
    try { $endLive = Read-NeoEndReport $erPath $Index }
    catch {
      $m = $_.Exception.Message
      $code = Get-NeoLoopReasonCode $m
      if ($code -ceq 'UNKNOWN') { $code = 'CLASSIFIER_ERROR' }
      $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode $code `
        -Detail ("round " + $round + " END report unreadable/invalid at the provider-located path: " + $m) -RoundData $roundDiff
      return (& $finishStop $stop)
    }

    # (9b) THE C4 EXTERNAL PROVIDER SEAM - invoked ONLY when THIS round's effective
    # class is 'high' (LOW/MED = fast lane: NO seam call, NO egress, NO budget burn;
    # the recorded lane is the honest 'MISSING' - no verdict exists for the round and
    # gate C does not require one below high). Seam discipline ($BuilderSeam /
    # $AuditProvider precedent): untyped; null/malformed/thrown => routed fail-closed
    # STOP. THE SEAM RETURN IS NEVER AUTHORITY: the lane handed to aggregation is
    # DERIVED FROM DISK via the shared Get-NeoExternalLaneStatus (boundary 1), and
    # gate C re-derives any GO at consumption (boundary 2, check==use). STRUCTURAL:
    # no codex invocation exists in this module - the live invoker lives in
    # orch_external.ps1 only; this wrapper consumes its ON-DISK output.
    $externalLane = 'MISSING'
    if ($effClass -ceq 'high') {
      if (($null -eq $ExternalProvider) -or -not ($ExternalProvider -is [scriptblock])) {
        $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode 'EXTERNAL_REQUIRED_UNAVAILABLE' `
          -Detail ("round " + $round + " effective class is 'high' but the external provider seam is null/absent or not a scriptblock - a HIGH round has NO default external channel => STOP (fail-closed; fall back to manual-external via Raphael)") -RoundData $roundDiff
        return (& $finishStop $stop)
      }
      try {
        $null = & $ExternalProvider (@{ run_root = $roundCtx.run_root; slice_id = $roundCtx.slice_id; round = $round; round_id = $roundId; session_root = $sessRoot; end_report_path = $erPath; timestamp_utc = $roundCtx.timestamp_utc })
      } catch {
        $stop = Complete-NeoLoopRoundStop -Context $roundCtx -ReasonCode 'EXTERNAL_REQUIRED_UNAVAILABLE' `
          -Detail ("external provider seam THREW during round " + $round + ": " + (ConvertTo-NeoLoopAsciiLine $_.Exception.Message 160) + " => STOP (fail-closed; the seam return is never authority; fall back to manual-external via Raphael)") -RoundData $roundDiff
        return (& $finishStop $stop)
      }
      # boundary-1 derivation from DISK (the seam's word plays no part): the tuple
      # hash is THIS round's END-report slot bundle, resolved under the provider's
      # session root by the standing containment rule. Any failure folds to
      # UNPARSEABLE fail-closed; gate C (which re-derives) decides the round.
      $externalLane = 'UNPARSEABLE'
      try {
        $extSlot = Get-NeoProp $endLive 'auditor_recommendation_slot'
        $extRef = [string](Get-NeoProp $extSlot 'bundle_ref')
        Assert-NeoSafeRel $extRef
        $extBundleFull = Assert-NeoContained $sessRoot $extRef
        $extHash = Get-NeoSha256File $extBundleFull
        $dLane = Get-NeoExternalLaneStatus -RunRoot $roundCtx.run_root -SliceId $roundCtx.slice_id -RoundId $roundId -BundleDiffHash $extHash -Index $Index
        $externalLane = [string]$dLane.status
      } catch { $externalLane = 'UNPARSEABLE' }
    }

    # (10) verdict aggregation - the frozen slot/spawn gates + the WIRED C4 lane:
    # $externalLane is step (9b)'s DISK-derived status (never the seam's word) or
    # the LOW/MED fast-lane 'MISSING'; gate C re-derives any GO claim at
    # consumption (check==use).
    $agg = Assert-NeoLoopAuditSatisfied -Context $roundCtx -RiskRow $RiskRow -EffectiveRiskClass $effClass `
      -EndReport $endLive -SessionRoot $sessRoot -MasterIdentity $MasterIdentity -BuilderIdentity $BuilderIdentity `
      -Index $Index -RoundId $roundId -ExternalLaneStatus $externalLane -RoundData $roundDiff
    if ($agg.stopped) { return (& $finishStop $agg) }

    # (11) NB1 CALLER-RECORDS: this wrapper is the caller for GO and non-GO rounds.
    # Every value below is the wrapper's OWN captured stage output (chk/agg/led) -
    # never the seam's or the provider's word. A write failure here propagates as
    # the writer's thrown LEDGER_FAILURE (see ROW DISCIPLINE above).
    $capEvents = @()
    if ($kind -ceq 'fix') {
      $capEvents = @((ConvertTo-NeoLoopAsciiLine ("fix round " + $round + " consumed within cap (post_increment_count=" + $led.post_increment_count + ")") 200))
    }
    $rowRes = Add-NeoIterationManifestEntry -RunRoot $roundCtx.run_root -Fields (@{
      slice_id = $roundCtx.slice_id; round = $round; attempt_seq = $lastSeq
      baseline_head_sha = [string]$chk.baseline_head_sha; baseline_tree_hash = [string]$chk.baseline_tree_hash
      changed_count = [int]$chk.changed_count; changed_paths_hash = [string]$chk.changed_paths_hash
      classification = 'THREE_BRANCH_CLEAN'; findings_summary = 'NONE'
      auditor_slot_status = 'SATISFIED'; auditor_slot_recommendation = [string]$agg.slot.recommendation
      auditor_identity = [string]$agg.slot.auditor_identity
      external_lane_status = [string]$agg.external_lane_status
      effective_seam_tier = [string]$agg.effective_seam_tier; cap_events = $capEvents
      stop_reason_code = 'NONE'; notify_gate_class = 'NONE'
      notify_sent = $false; notify_deduped = $false; notify_refused = $false
      notify_reason = ''; timestamp_utc = $roundCtx.timestamp_utc
    })
    $trail += , @{
      round = $round; kind = $kind; attempt_seq = $lastSeq; go = [bool]$agg.go
      recommendation = [string]$agg.slot.recommendation
      changed_count = [int]$chk.changed_count; row = $rowRes.entry
    }

    if ([bool]$agg.go) {
      # CONVERGED: a converged round notifies NOTHING (the human END surface is
      # S3c's). Return the full round trail.
      return @{ stopped = $false; converged = $true; go = $true; rounds = @($trail); fix_rounds_used = $fixUsed; final = $agg }
    }

    # (12) C1 AUTO-ACT on a valid non-GO verdict (NEEDS-MORE|NO-GO - the NORMAL
    # ITERATE signal, not a STOP): the next round's SCOPED fix dispatch EDITS the
    # round's OWN ACTUAL changed set (frozen-diff-derived from DISK - never seam-
    # supplied, never verdict-supplied), bounded to the SAME approved scope; the
    # dispatch-time three-branch routes each within-approved edit. The C1c
    # ProposedFixTargets lane keeps flowing the CALLER'S DECLARED fix targets
    # (screened EVERY round): the frozen C1c helper is a strict tri-state (only a
    # class resolving EXACTLY 'implementation' under the engine's own map passes;
    # UNKNOWN fails closed, S2b-FIX F6), so it screens DECLARED judging-risky fix
    # intents - flowing the raw app changed set there would fail closed on every
    # unregistered app file and could never iterate (grounded vs the live map;
    # the frozen gate is not touched, not widened, not re-implemented).
    $nextProposedEdits = @($chk.changed_set)
    $round = $round + 1
    $kind = 'fix'
  }
}

# ==================================================================================
# ---- S3c: END ASSEMBLY (I7/N3 trail validation + XC2 final-state + human-END) ----
# ==================================================================================
# Binding spec: NEO_SELF_ITERATION_DESIGN_v3_1.md (10652365) section 5 lines 206-211
# (END assembly trail + XC2) + the 2026-07-07b STOP-PATH END ASSEMBLY clarifier
# (lines 216-222: trail validation ALWAYS; XC2 per-slice ONLY where a validated GO
# bundle exists; a never-GO slice records the mechanical marker NO_GO_BUNDLE and is
# NOT an XC2 failure) + section 0 NB-4 (tamper-EVIDENT, not tamper-proof, honesty).
#
# COORDINATION-only crown jewel (same discipline as S3a/S3b): these functions NEVER
# author a verdict, NEVER write an AUDIT_RESULT, NEVER edit the governed tree, NEVER
# decide an approval. END assembly is nothing but "the frozen readers + the frozen
# bundle/spawn machinery said the trail reconciles and the kept bytes == the audited
# bytes". keep/iterate/toss stays the human's.
#
# REUSE (READ-ONLY, no frozen edit): Read-NeoIterationManifest / Read-NeoAttemptLedger
# (fail-closed run_id-bound readers), Read-NeoRunLedgerEntries (spawn-ledger read),
# Assert-NeoSpawnCorrelatedSlot (the SAME gate-B correlation rule the live round runs -
# NOTE-1 one-rule-one-place), Read-NeoJsonFile + Assert-NeoValid + Assert-NeoArtifactHash
# + Assert-NeoPacketSelfHash (bundle re-validation, byte-identical to the frozen slot
# seam), Get-NeoSha256File (XC2 re-hash - NEVER re-implemented), Assert-NeoSafeRel +
# Assert-NeoContained (XC1 containment on every member path), Invoke-NeoLoopStopNotify
# with -HumanEndClass (the F5 human-END surface; S3c is its ONLY legitimate caller).

# The mechanical NO_GO_BUNDLE marker (spec 216-222): XC2 has no comparison target for a
# slice that never reached a validated GO round; that is NOT a failure and NOT a silent
# skip - it is recorded as this exact string.
$script:NeoLoopNoGoBundleMarker = 'NO_GO_BUNDLE'

# S3c-FIX F1: the ENUMERATED pre-ledger-CAPABLE reason-code set, DERIVED from the live
# Invoke-NeoLoopConverge path (every code a STOP can carry on a manifest row that lands
# BEFORE converge step (2) Add-NeoAttemptLedgerEntry, i.e. attempt-less for that round).
# The three pre-ledger STOP sources and the ONLY codes each can emit:
#   (a) wrapper boundary-validation on $ctx0 (before the loop): BUILDER_SEAM_FAILED,
#       CLASSIFIER_ERROR, and LEDGER_FAILURE (the DerivedAt timestamp parse, called with
#       ReasonCode 'LEDGER_FAILURE').
#   (b) the per-round wall-clock gate (converge step (1), strictly before step (2)):
#       CAP_WALL_CLOCK, CAPS_INVALID, and LEDGER_FAILURE (Test-NeoRunWallClock reads the
#       PERSISTED run manifest via Read-NeoRunManifest - a missing/unparseable/schema-
#       invalid manifest throws reason_code=LEDGER_FAILURE before the ledger write).
#   (c) the write-ahead ledger-write CATCH (converge 1427-1429): Add-NeoAttemptLedgerEntry
#       THROWS before the append lands => an attempt-less row. Its reachable throw codes
#       are LEDGER_FAILURE (blank/reserved slice, bad kind, write-ahead ordering) and
#       CAPS_INVALID (cap number) - BOTH already in this set. ROUND_MISMATCH is also a
#       throw of that writer BUT is UNREACHABLE from the converge loop ($round/$kind are
#       engine-controlled and track the ledger post-increment exactly: round 0 = 'initial';
#       fix round N = post-increment N; a refused entry returns without incrementing), so
#       its EXCLUSION is fail-closed-safe (a narrower set only ever BLOCKs more forgeries).
# Post-ledger-only codes (EMPTY_CHANGED_SET/DENIED_PATH/EMPTY_PROPOSED_EDITS from dispatch;
# AUDITOR_SLOT_UNSATISFIED/SPAWN_*/EXTERNAL_* from aggregation; RISK_ESCALATION;
# CAP_FIX_ROUNDS/CAP_EXTERNAL_CALLS which land a REFUSED entry by construction;
# END_ASSEMBLY_FAILED which is not a converge row code) are DELIBERATELY EXCLUDED. An
# attempt-less STOP row whose reason is OUTSIDE this set is a forgery => BLOCK (PA-1).
$script:NeoLoopPreLedgerReasonCodes = @(
  'BUILDER_SEAM_FAILED', 'CLASSIFIER_ERROR', 'LEDGER_FAILURE', 'CAP_WALL_CLOCK', 'CAPS_INVALID'
)

# ---- Get-NeoLoopRunSliceUniverse (S3c-FIX-2 SLICE-UNIVERSE class-closer) -----------
# THE AUTHORITATIVE RUN SLICE UNIVERSE, DERIVED FROM RUN EVIDENCE - never the caller's
# word. The round-1 F3 fix stopped the caller forging a TrailResult digest, but the
# validated slice SET was still whatever -SliceIds the caller passed: a caller omitting
# a GO slice on a 2-slice run silently skipped that slice's trail + XC2. Root-close it -
# the universe is the distinct slice_id set the run itself RECORDED.
#
# DISCOVERY (run_id-bound, fail-closed, UNFILTERED): read BOTH ledgers via the FROZEN
# readers with the OPTIONAL SliceId OMITTED so each returns ALL entries (each entry/row
# already bound to the persisted run_id inside the reader - PA-2). The iteration manifest
# is ALWAYS present for a validated run (a slice records >= round 0); its absence BLOCKs
# inside the frozen reader (fail-closed). The ATTEMPT ledger is legitimately ABSENT for a
# pre-ledger-STOP-only run (the round-0 STOP row lands before the write-ahead attempt
# entry) - treated as zero attempts here, exactly as the END-trail reader does (the frozen
# Read-NeoAttemptLedger BLOCKs on absence for resume semantics, so guard with Test-Path).
# The distinct union of slice_ids across both streams is the universe. Case-sensitive
# ($union keyed -ceq) to match every other slice-id comparison in this module (check==use).
#
# GROUNDED AUTHORITY (honest): in the FULL design C5 freezes the slice PLAN as the run's
# slice authority; C5 is an UNBUILT fail-closed seam (untouched here - zero external
# calls), so in S3c the run's RECORDED slices (these two ledgers) ARE the authority. When
# C5 lands, the frozen slice plan supersedes the ledgers as the universe source; until
# then a slice that never recorded even round 0 cannot be detected as missing here (the
# disclosed C5 plan-vs-ledger completeness carry). No schema field is added - the ledgers
# already record slice_id.
function Get-NeoLoopRunSliceUniverse {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    # -ExpectedRunId is the caller's TRUSTED run identity. The frozen readers bind every
    # row/entry to the PERSISTED run_id themselves (fail-closed), and Assert-NeoLoopEndTrail
    # already asserted -ExpectedRunId == persisted run_id at ITS boundary BEFORE calling the
    # universe gate, so discovery here is transitively run_id-bound. The parameter is kept in
    # the signature so this reader can be called run_id-scoped in isolation without relying on
    # an upstream assertion (defense-in-depth; validated at its own boundary).
    [Parameter(Mandatory = $true)][string]$ExpectedRunId
  )
  if ([string]::IsNullOrWhiteSpace($RunRoot) -or -not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE slice-universe: RunRoot '$RunRoot' is not an existing directory => BLOCK"
  }
  if ([string]::IsNullOrWhiteSpace($ExpectedRunId)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE slice-universe: ExpectedRunId is blank => BLOCK (PA-2)"
  }
  # assert -ExpectedRunId agrees with the persisted run manifest at THIS boundary too (the
  # frozen resolver both readers use), so a standalone caller is also run_id-checked here.
  $persistedRunId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $RunRoot) 'run_id')
  if ($persistedRunId -cne $ExpectedRunId) {
    New-NeoBlock "reason_code=LEDGER_FAILURE slice-universe: -ExpectedRunId '$ExpectedRunId' does not match the persisted run manifest run_id '$persistedRunId' => BLOCK (PA-2)"
  }
  # collect ALL recorded slice_ids across both streams, then de-duplicate case-sensitively
  # (ordinal) preserving first-seen order. The frozen readers return ,@(...) (one stream
  # object wrapping the array); ASSIGN to a variable first - assignment unrolls the outer
  # wrapper so @($var) yields the ENTRY pscustomobjects (piping the return value directly
  # leaves the inner Object[] as a single element - the object-array-vs-pscustomobject trap).
  $recorded = @()
  # iteration manifest is ALWAYS present (absence BLOCKs inside the frozen reader); read it
  # UNFILTERED (SliceId omitted => ALL rows), run_id-bound.
  $manifestRows = Read-NeoIterationManifest -RunRoot $RunRoot
  foreach ($mr in @($manifestRows)) { $recorded += [string](Get-NeoProp $mr 'slice_id') }
  # attempt ledger is absence-tolerant here (a pre-ledger-STOP-only run has none); when
  # present, read it UNFILTERED, run_id-bound, and union its slice_ids in.
  $attemptLedgerPath = Resolve-NeoRunStatePath $RunRoot $script:NeoAttemptLedgerLeaf
  if (Test-Path -LiteralPath $attemptLedgerPath) {
    $attemptRows = Read-NeoAttemptLedger -RunRoot $RunRoot
    foreach ($are in @($attemptRows)) { $recorded += [string](Get-NeoProp $are 'slice_id') }
  }
  # de-duplicate into the distinct universe (ordinal/case-sensitive hashtable set).
  $seen = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
  $universe = @()
  foreach ($s in @($recorded)) {
    if ([string]::IsNullOrWhiteSpace($s)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE slice-universe: a recorded ledger entry carries a blank slice_id => BLOCK"
    }
    if (-not $seen.ContainsKey($s)) { $seen[$s] = $true; $universe += $s }
  }
  if (@($universe).Count -eq 0) {
    New-NeoBlock "reason_code=LEDGER_FAILURE slice-universe: the run's ledgers record NO slices => BLOCK (a validated run always recorded at least one slice)"
  }
  # S3c-FIX-4 (-ceq-distinctness closure): the universe is ordinal-distinct, but the FROZEN
  # reader filters (Read-NeoIterationManifest / Read-NeoAttemptLedger) compare slice_id with
  # culture-loose -ceq. Refuse any run whose ordinally-DISTINCT members collide under -ceq, so
  # the ordinal set-equality and the per-slice -ceq reads can never disagree (check==use closed
  # at root, fail-closed). O(n^2) over the tiny per-run slice set.
  $uArr = @($universe)
  for ($i = 0; $i -lt $uArr.Count; $i++) {
    for ($j = $i + 1; $j -lt $uArr.Count; $j++) {
      $a = [string]$uArr[$i]; $b = [string]$uArr[$j]
      if ($a -ceq $b) {
        New-NeoBlock "reason_code=LEDGER_FAILURE slice-universe: the run records slice-ids '$a' and '$b' that are ORDINALLY DISTINCT but collide under the reader's case-sensitive -ceq filter (the per-slice ledger reads cannot cleanly separate them) => BLOCK (a run must not record -ceq-colliding slice-ids)"
      }
    }
  }
  return @($universe)
}

# ---- Assert-NeoLoopRunSliceUniverse (ordinal set-equality: caller set == discovered) --
# The new invariant (S3c-FIX-2): the EFFECTIVE validated set MUST EQUAL the discovered
# universe. -SliceIds stays a public parameter (a caller's claim is validated at the
# boundary, which IS this fix's lesson), but a caller can neither NARROW nor RESHAPE the
# universe: a discovered slice the caller OMITS => BLOCK (silent-skip forgery, the exact
# round-2 finding); a caller slice NOT present in the run (EXTRA) => BLOCK (no phantom
# slice). Ordinal/case-sensitive both directions (check==use with every slice-id -ceq).
function Assert-NeoLoopRunSliceUniverse {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedRunId,
    [Parameter(Mandatory = $true)][string[]]$CallerSliceIds
  )
  $discovered = Get-NeoLoopRunSliceUniverse -RunRoot $RunRoot -ExpectedRunId $ExpectedRunId
  $discoveredSet = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal); foreach ($d in @($discovered)) { $discoveredSet[[string]$d] = $true }
  $callerSet = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal); foreach ($c in @($CallerSliceIds)) { $callerSet[[string]$c] = $true }
  # OMISSION: every discovered slice MUST be in the caller set (else a slice is silently skipped).
  foreach ($d in @($discovered)) {
    if (-not $callerSet.ContainsKey([string]$d)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE slice-universe: caller -SliceIds OMITS discovered run slice '$d' (discovered universe [$($discovered -join ', ')]) => BLOCK (the run's recorded slices are the authority; a caller cannot narrow the validated set - its trail + XC2 would be silently skipped)"
    }
  }
  # EXTRA: every caller slice MUST be in the discovered set (else a phantom slice with no run evidence).
  foreach ($c in @($CallerSliceIds)) {
    if (-not $discoveredSet.ContainsKey([string]$c)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE slice-universe: caller -SliceIds names slice '$c' NOT present in the run (discovered universe [$($discovered -join ', ')]) => BLOCK (a caller cannot reshape the universe with a slice the run never recorded)"
    }
  }
  return @($discovered)
}

# ---- Assert-NeoLoopEndTrail (I7/N3 TRAIL VALIDATION; spec 206-208) ----------------
# Per slice, fail-closed: reconcile the append-only iteration manifest against the
# write-ahead attempt ledger, binding EVERY entry AND EVERY row to a TRUSTED
# -ExpectedRunId (PA-2: run identity is NEVER taken from the untrusted ledger body).
# ANY gap => BLOCK. The ONLY tolerated asymmetry is the mechanically-defined PRE-LEDGER
# STOP class (PA-1). Returns the validated per-slice trail digest; throws NEO-BLOCK on
# any gap (never a human-END class - a failed assembly routes ESCALATION_STOP upstream).
#
# THE MECHANICAL PRE-LEDGER DISCRIMINATOR (PA-1, grounded from the live S3b converge
# loop): the write-ahead attempt-ledger entry lands at converge step (2)
# (Add-NeoAttemptLedgerEntry). Every STOP that fires BEFORE it - the wrapper's OWN
# boundary-validation STOPs on $ctx0 and the round-0/pre-dispatch wall-clock gate -
# lands a manifest row with NO attempt entry for that round. Such a row is a legitimate
# pre-ledger STOP iff ALL of: classification 'STOPPED'; a non-empty, != 'NONE'
# stop_reason_code; NO aligned attempt entry; and ALL downstream lanes at the honest
# NOT_EVALUATED sentinels (the pre-ledger paths never reached a stage that fills them).
# An unmatched POST-ledger STOP row (real reason_code, but a round that DID land an
# attempt entry) fails the "no aligned entry" clause => BLOCK. That is what proves
# "pre-ledger" is mechanical, not merely "STOPPED with a reason".
function Assert-NeoLoopEndTrail {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedRunId,
    [Parameter(Mandatory = $true)][string[]]$SliceIds
  )
  # boundary validation (every public function validates EVERY parameter at ITS OWN
  # boundary; unknown/default => BLOCK). NO notify here - trail validation is a checker;
  # the END gate (Invoke-NeoLoopEndGate) owns the notify + human-class routing.
  if ([string]::IsNullOrWhiteSpace($RunRoot) -or -not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-trail: RunRoot '$RunRoot' is not an existing directory => BLOCK"
  }
  if ([string]::IsNullOrWhiteSpace($ExpectedRunId)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-trail: ExpectedRunId is blank => BLOCK (run identity is caller-TRUSTED from the run/converge envelope, never inferred from ledger bodies - PA-2)"
  }
  if (@($SliceIds).Count -eq 0) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-trail: SliceIds is empty - a run always carries at least one slice => BLOCK"
  }
  foreach ($sid in @($SliceIds)) {
    if ([string]::IsNullOrWhiteSpace($sid)) { New-NeoBlock "reason_code=LEDGER_FAILURE end-trail: a slice id is blank => BLOCK" }
  }

  # PA-2 check==use: the frozen readers bind rows/entries to the PERSISTED run_id; I
  # ADDITIONALLY assert -ExpectedRunId == that persisted run_id at MY boundary, so a
  # caller who passed a different trusted id (drift) is caught here, not silently
  # trusted downstream. Read-NeoRunManifest is the frozen resolver both readers use.
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $persistedRunId = [string](Get-NeoProp $manifest 'run_id')
  if ($persistedRunId -cne $ExpectedRunId) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-trail: -ExpectedRunId '$ExpectedRunId' does not match the persisted run manifest run_id '$persistedRunId' => BLOCK (PA-2: trusted run identity must agree with the persisted run at the END boundary)"
  }

  # (S3c-FIX-2) THE SLICE-UNIVERSE INVARIANT: the effective validated set MUST EQUAL the
  # run's discovered slice universe (evidence-derived, never caller-chosen). A caller that
  # OMITS a discovered slice (its trail + XC2 would be silently skipped) OR names an EXTRA
  # slice not in the run => BLOCK, both directions. Discovery is the run_id-bound unfiltered
  # union of both ledgers. This runs ONCE per END (the ledgers are then read per-slice below,
  # a bounded second read the reconciliation already needs - one discovery, non-redundant).
  [void](Assert-NeoLoopRunSliceUniverse -RunRoot $RunRoot -ExpectedRunId $ExpectedRunId -CallerSliceIds $SliceIds)

  $sliceDigests = @()
  foreach ($sid in @($SliceIds)) {
    # (R0) READ both ledgers via the FROZEN fail-closed readers. The frozen readers
    # return ,@($entries) (ONE stream object wrapping the array); pipe through
    # ForEach-Object so each ENTRY is an element (a plain @() wrap would nest the whole
    # array as a single element - the object-array-vs-pscustomobject trap).
    #
    # ABSENCE HANDLING (the pre-ledger STOP class, spec 216-222): the iteration manifest
    # is ALWAYS present (a validated slice recorded at least round 0), and its absence
    # BLOCKs (fail-closed). The ATTEMPT ledger, however, is legitimately ABSENT for a run
    # whose only round is a PRE-LEDGER STOP (a round-0 wall-clock trip records its manifest
    # row BEFORE the write-ahead attempt entry, so attempt_ledger.jsonl may never be
    # written). The frozen Read-NeoAttemptLedger BLOCKs on absence (resume semantics); here
    # the END-trail reader treats an ABSENT attempt ledger as ZERO attempts, and the
    # per-row discriminator below then REQUIRES every attempt-less row to be a mechanical
    # pre-ledger STOP (a non-pre-ledger row with no attempt entry still => BLOCK). A PRESENT
    # attempt ledger is read fail-closed via the frozen reader (run_id-bound, monotone).
    $attemptLedgerPath = Resolve-NeoRunStatePath $RunRoot $script:NeoAttemptLedgerLeaf
    $attempts = @()
    if (Test-Path -LiteralPath $attemptLedgerPath) {
      Read-NeoAttemptLedger -RunRoot $RunRoot -SliceId $sid | ForEach-Object { $attempts += $_ }
    }
    $rows = @(); Read-NeoIterationManifest -RunRoot $RunRoot -SliceId $sid | ForEach-Object { $rows += $_ }

    # index attempts by round (write-ahead entries; seq is the per-slice monotonic
    # attempt_seq the frozen reader already verified contiguous). More than one attempt
    # entry per round is impossible on a serial run - fail closed if seen.
    $attemptByRound = @{}
    foreach ($a in $attempts) {
      $ar = [int](Get-NeoProp $a 'round')
      if ($attemptByRound.ContainsKey($ar)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: DUPLICATE attempt-ledger entry for round $ar => BLOCK (serial run: one attempt entry per round)"
      }
      $attemptByRound[$ar] = $a
    }
    # index rows by round; a duplicate-round row => BLOCK (R3).
    $rowByRound = @{}
    foreach ($r in $rows) {
      $rr = [int](Get-NeoProp $r 'round')
      if ($rowByRound.ContainsKey($rr)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: DUPLICATE iteration-manifest row for round $rr => BLOCK (one row per round)"
      }
      $rowByRound[$rr] = $r
    }

    if (@($rows).Count -eq 0) {
      New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: no iteration-manifest rows for the slice => BLOCK (a validated slice always recorded at least its round 0)"
    }

    # (R3) ROUND ORDER: rows are contiguous 0..N (no holes).
    $rowRounds = @($rowByRound.Keys | Sort-Object)
    for ($i = 0; $i -lt $rowRounds.Count; $i++) {
      if ([int]$rowRounds[$i] -ne $i) {
        New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round HOLE - rows present are [$($rowRounds -join ', ')], expected contiguous 0..$($rowRounds.Count - 1) => BLOCK (I7/N3: no round holes)"
      }
    }

    # (R1, reverse direction) EVERY attempt-ledger entry MUST have a manifest row (an
    # attempt entry without a row is an unrecorded round => a trail gap). The per-row loop
    # below covers the forward direction (rows must have entries or be pre-ledger STOPs);
    # this closes the other direction so a round that landed an attempt entry but never
    # recorded its row cannot slip through.
    foreach ($ar in @($attemptByRound.Keys)) {
      if (-not $rowByRound.ContainsKey($ar)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: attempt-ledger entry for round $ar has NO iteration-manifest row => BLOCK (I7/N3: an attempt entry without a row is an unrecorded round)"
      }
    }

    $goRound = $null
    $goAuditorIdentity = $null
    $preLedgerRounds = @()

    # (R1/R2/R4/R5/R6) reconcile per round.
    foreach ($rnd in $rowRounds) {
      $row = $rowByRound[$rnd]
      # (R8, S3c-FIX F2) TRAIL FINALITY AFTER GO: convergence breaks on the FIRST GO
      # (Invoke-NeoLoopConverge returns immediately), so the loop emits NO further round.
      # $rowRounds is ascending (sorted at 1728), so any round > the GO round is processed
      # here AFTER $goRound was set. ANY such row - a forged post-GO STOP row OR a forged
      # post-GO non-STOP row - is a trail inconsistency => BLOCK (fires before the
      # STOP/non-STOP split, so it catches both). A post-loop re-check (below) is the
      # sort-order-robust belt-and-suspenders.
      if (($null -ne $goRound) -and ($rnd -gt $goRound)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd is recorded AFTER the slice's GO round $goRound => BLOCK (convergence breaks on the first GO; the loop emits no further round - any later row is a trail inconsistency)"
      }
      $cls = [string](Get-NeoProp $row 'classification')
      $stopCode = [string](Get-NeoProp $row 'stop_reason_code')
      $rec = [string](Get-NeoProp $row 'auditor_slot_recommendation')
      $slotStatus = [string](Get-NeoProp $row 'auditor_slot_status')
      $seamTier = [string](Get-NeoProp $row 'effective_seam_tier')
      $laneStatus = [string](Get-NeoProp $row 'external_lane_status')
      $rowSeq = [int](Get-NeoProp $row 'attempt_seq')
      $hasAttempt = $attemptByRound.ContainsKey($rnd)
      $isStopRow = ($cls -ceq 'STOPPED') -or ($cls -ceq 'STOPPED_THREE_BRANCH')

      # the mechanical PRE-LEDGER discriminator (PA-1) - ALL four clauses.
      $preLedgerLanesSentinelled = (
        ($slotStatus -ceq 'NOT_EVALUATED') -and ($rec -ceq 'NOT_EVALUATED') -and
        ($seamTier -ceq 'NOT_EVALUATED') -and ($laneStatus -ceq 'NOT_EVALUATED') -and
        ([string](Get-NeoProp $row 'auditor_identity') -ceq 'NOT_EVALUATED')
      )
      $isPreLedger = (
        (-not $hasAttempt) -and ($cls -ceq 'STOPPED') -and
        (-not [string]::IsNullOrWhiteSpace($stopCode)) -and ($stopCode -cne 'NONE') -and
        # (ii-set, S3c-FIX F1): the reason code MUST be in the ENUMERATED pre-ledger-CAPABLE
        # set (derived from the live converge path). A forged attempt-less STOP row carrying
        # a POST-ledger-only code (e.g. SPAWN_UNCORRELATED, AUDITOR_SLOT_UNSATISFIED) is NOT
        # pre-ledger and falls to the PA-1 BLOCK below. -ccontains is case-sensitive.
        ($script:NeoLoopPreLedgerReasonCodes -ccontains $stopCode) -and
        $preLedgerLanesSentinelled
      )

      if ($hasAttempt) {
        # (R1) an attempt entry MUST align with exactly this row on attempt_seq == seq.
        $entrySeq = [int](Get-NeoProp $attemptByRound[$rnd] 'seq')
        if ($entrySeq -ne $rowSeq) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd attempt_seq MISALIGNED - manifest row attempt_seq=$rowSeq but attempt-ledger seq=$entrySeq => BLOCK"
        }
      } else {
        # (R2) a row with NO attempt entry PASSES iff it is a mechanical pre-ledger STOP,
        # and NOTHING wider. A non-STOP row, or a STOPPED row failing any discriminator
        # clause (e.g. an unmatched POST-ledger STOP whose lanes are filled, or a
        # 'STOPPED_THREE_BRANCH' which is only reachable post-ledger), => BLOCK.
        if (-not $isPreLedger) {
          if (-not $isStopRow) {
            New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd manifest row has NO attempt-ledger entry and is not a STOP row (classification '$cls') => BLOCK (I7/N3: an attempt-less row must be a mechanical pre-ledger STOP)"
          }
          $inPreLedgerSet = ($script:NeoLoopPreLedgerReasonCodes -ccontains $stopCode)
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd STOP row has NO attempt-ledger entry but does NOT satisfy the mechanical pre-ledger discriminator (classification='$cls', stop_reason_code='$stopCode', in-pre-ledger-reason-set=$inPreLedgerSet [$($script:NeoLoopPreLedgerReasonCodes -join ', ')], lanes-sentinelled=$preLedgerLanesSentinelled) => BLOCK (PA-1: 'pre-ledger' is the mechanical on-disk discriminator, not 'STOPPED with a reason' - an unmatched POST-ledger STOP, OR a STOP carrying a POST-ledger-only reason code, is a gap)"
        }
        $preLedgerRounds += $rnd
      }

      # (R4) every STOP row's reason_code non-empty (schema enforces the charset; the
      # semantic != 'NONE'/non-empty is asserted here).
      if ($isStopRow) {
        if ([string]::IsNullOrWhiteSpace($stopCode) -or ($stopCode -ceq 'NONE')) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd is a STOP row but stop_reason_code is blank/'NONE' => BLOCK (every STOP row carries a reason)"
        }
      }

      # (R6) OUTCOME CONSISTENCY (PR-1) - a consistency check the schema CANNOT make;
      # field PRESENCE is already structural via the reader's schema validation (I do
      # NOT re-assert it). Assert that the DECLARED outcome and the CARRIED lanes agree.
      if (-not $isStopRow) {
        # a completed (non-STOP) round: classification is THREE_BRANCH_CLEAN, the slot is
        # SATISFIED, the recommendation is a real verdict, and the lanes are non-sentinel.
        if ($cls -cne 'THREE_BRANCH_CLEAN') {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd is a non-STOP row but classification '$cls' is not 'THREE_BRANCH_CLEAN' => BLOCK (PR-1 outcome inconsistency)"
        }
        if ($slotStatus -cne 'SATISFIED') {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd is a completed round but auditor_slot_status '$slotStatus' is not 'SATISFIED' => BLOCK (PR-1)"
        }
        if (@('GO', 'NEEDS-MORE', 'NO-GO') -cnotcontains $rec) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd is a completed round but auditor_slot_recommendation '$rec' is not GO|NEEDS-MORE|NO-GO => BLOCK (PR-1)"
        }
        if (($seamTier -ceq 'NOT_EVALUATED') -or ($laneStatus -ceq 'NOT_EVALUATED')) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd declares outcome '$rec' but carries a NOT_EVALUATED verdict lane (effective_seam_tier='$seamTier', external_lane_status='$laneStatus') => BLOCK (PR-1: a GO/non-GO round's lanes were evaluated)"
        }
        if ($rec -ceq 'GO') {
          if ($null -ne $goRound) {
            New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: TWO GO rounds (round $goRound and round $rnd) => BLOCK (convergence breaks on the first GO; a second GO round is a trail inconsistency)"
          }
          $goRound = $rnd
          $goAuditorIdentity = [string](Get-NeoProp $row 'auditor_identity')
        }
      } else {
        # a STOP row: stop_reason_code must match its stop class. A pre-ledger STOP is
        # legitimately sentinelled (asserted above). A POST-ledger STOP row (has an
        # attempt entry) is a real gap unless it is a recorded terminal STOP whose earlier
        # lanes may legitimately be sentinelled up to the stage it stopped at; the trail
        # tolerates it ONLY as a surfaced breaker/escalation STOP with a non-NONE reason
        # (already asserted). The specific inconsistency PR-1 names - a clean
        # classification with a breaker reason - is caught here: a THREE_BRANCH_CLEAN row
        # can never carry a stop_reason_code other than the completed-round 'NONE'
        # (handled in the non-STOP branch); a STOPPED* row can never carry 'NONE'.
        # RISK_ESCALATION belongs to a STOPPED_THREE_BRANCH class row (the escalation
        # fires after the three-branch stage); a plain 'STOPPED' pre-dispatch row cannot
        # carry it.
        if (($stopCode -ceq 'RISK_ESCALATION') -and ($cls -cne 'STOPPED_THREE_BRANCH')) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd carries stop_reason_code 'RISK_ESCALATION' but classification '$cls' is not 'STOPPED_THREE_BRANCH' (the escalation fires only after the three-branch stage) => BLOCK (PR-1 outcome inconsistency)"
        }
      }
    }

    # (R8 post-loop re-check, S3c-FIX F2) TRAIL FINALITY AFTER GO, sort-order-robust: the
    # inline guard above relies on ascending iteration; this second pass re-checks EVERY
    # row's round against the finalized $goRound independently of iteration order, so a
    # post-GO row can never slip through even if $rowRounds were ever produced unsorted.
    if ($null -ne $goRound) {
      foreach ($rnd in $rowRounds) {
        if ([int]$rnd -gt [int]$goRound) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd is recorded AFTER the slice's GO round $goRound => BLOCK (post-loop finality re-check: convergence breaks on the first GO; the loop emits no further round)"
        }
      }
    }

    # (R5) CAP CONSISTENCY BOTH DIRECTIONS (PA-6). A refused attempt entry (refused=true,
    # reason CAP_*) MUST pair with a CAP_* STOP row for the SAME round/attempt_seq; a
    # CAP_* stop_reason_code row MUST pair with a refused attempt entry. Either direction
    # unmatched => BLOCK.
    foreach ($rnd in @($attemptByRound.Keys)) {
      $a = $attemptByRound[$rnd]
      $refused = [bool](Get-NeoProp $a 'refused')
      $reason = [string](Get-NeoProp $a 'reason')
      if ($refused) {
        if (-not $rowByRound.ContainsKey($rnd)) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd attempt entry is REFUSED (reason '$reason') but there is NO manifest row => BLOCK (PA-6)"
        }
        $row = $rowByRound[$rnd]
        $rowStop = [string](Get-NeoProp $row 'stop_reason_code')
        if ($rowStop -notlike 'CAP_*') {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd attempt entry is REFUSED (reason '$reason') but the manifest row stop_reason_code '$rowStop' is not a CAP_* code => BLOCK (PA-6: a refused attempt must pair with a CAP_* STOP row)"
        }
        if ([int](Get-NeoProp $row 'attempt_seq') -ne [int](Get-NeoProp $a 'seq')) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd refused-attempt / CAP_* STOP row attempt_seq MISMATCH => BLOCK (PA-6)"
        }
      }
    }
    # ONLY the two LEDGER-REFUSAL cap codes pair with a refused attempt entry: the attempt
    # ledger's reason enum is {NONE, CAP_FIX_ROUNDS, CAP_EXTERNAL_CALLS} (schema-grounded),
    # and those refusals are POST-ledger by construction (the write-ahead entry LANDS
    # refused). The wall-clock breaker codes (CAP_WALL_CLOCK / CAPS_INVALID) fire at the
    # gate BEFORE the write-ahead entry (converge step 1 precedes step 2), so a legitimate
    # round-0 wall-clock trip is a PRE-LEDGER STOP with NO attempt entry - it must NOT be
    # forced to pair with a refused entry. So the reverse-direction cap check is scoped to
    # the ledger-refusal codes, not all CAP_*.
    $ledgerRefusalCodes = @('CAP_FIX_ROUNDS', 'CAP_EXTERNAL_CALLS')
    foreach ($rnd in $rowRounds) {
      $row = $rowByRound[$rnd]
      $rowStop = [string](Get-NeoProp $row 'stop_reason_code')
      if ($ledgerRefusalCodes -ccontains $rowStop) {
        if (-not $attemptByRound.ContainsKey($rnd)) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd manifest row carries a ledger-refusal stop_reason_code '$rowStop' but there is NO attempt-ledger entry (a cap refusal is post-ledger by construction: the write-ahead entry LANDS refused) => BLOCK (PA-6)"
        }
        $a = $attemptByRound[$rnd]
        if (-not [bool](Get-NeoProp $a 'refused')) {
          New-NeoBlock "reason_code=LEDGER_FAILURE end-trail[$sid]: round $rnd manifest row carries a ledger-refusal stop_reason_code '$rowStop' but its attempt-ledger entry is NOT refused => BLOCK (PA-6: a CAP_FIX_ROUNDS/CAP_EXTERNAL_CALLS STOP must pair with a refused attempt entry)"
        }
      }
    }

    $sliceDigests += , @{
      slice_id = $sid
      row_rounds = @($rowRounds)
      go_round = $goRound
      go_auditor_identity = $goAuditorIdentity
      pre_ledger_rounds = @($preLedgerRounds)
      attempt_count = @($attempts).Count
      row_count = @($rows).Count
    }
  }

  return @{ ok = $true; expected_run_id = $ExpectedRunId; slices = @($sliceDigests) }
}

# ---- Assert-NeoLoopFinalState (XC2 FINAL-STATE VALIDATION; spec 209-211 + 216-222) --
# Per slice, ONLY where the validated trail (TrailResult from Assert-NeoLoopEndTrail)
# contains a GO round (PR-2): the FINAL on-disk hashes of the slice's surfaces MUST
# EQUAL the last GO-audited bundle's member hashes. A slice with no GO round records the
# mechanical marker NO_GO_BUNDLE (NOT a failure, NOT a silent skip). Throws NEO-BLOCK on
# any delta / member-set inequality / ref forgery.
#
# TRUST ROOT (NOTE-2, stated honestly - the arc's recurring external-channel finding):
# BOTH the audited-bundle read (X2) AND the final-surface re-hash (X4) resolve members
# under the per-slice caller-supplied session_root. This single root is INHERENT to the
# run's evidence layout: the AUDIT_BUNDLE's allowlist rels are, by construction
# (New-NeoAuditBundle in the frozen orch_engine), relative to the audit session_root, and
# the frozen slot seam itself resolves them there (orch_enforce Assert-NeoContained
# $SessionRoot $rel) - re-hashing the same rels from a different root would resolve to
# non-existent paths, so a distinct trusted root is not cleanly available. This is the
# sec-0 tamper-EVIDENT (NOT tamper-proof) boundary (NB-4): Invoke-NeoLoopEndGate is an
# ENGINE-INTERNAL caller. The cross-checks that make a co-forged (bundle + matching
# surfaces at the same rels) world EVIDENT, all load-bearing:
#   (a) the last-GO bundle_ref is DERIVED from the run_id-bound spawn ledger via the
#       SAME frozen correlation the live round runs (X1 below), NOT the caller's word
#       (PA-3) - a forged SessionRoot needs a forged bundle that ALSO carries a spawn
#       entry correlated on the authentic, run_id-bound spawn ledger;
#   (b) the bundle's envelope artifact hash + packet self-hash are re-validated
#       (Assert-NeoArtifactHash / Assert-NeoPacketSelfHash) - a hand-edited bundle fails;
#   (c) the spawn ledger is END evidence and run_id-bound (foreign-run entry => the
#       frozen reader BLOCKs), so the correlation cannot borrow another run's bundle.
# A forger controlling only session_root, without a correlated authentic-run spawn entry
# for that exact auditor_identity+round, cannot pass X1. This is disclosed, not unexamined.
function Assert-NeoLoopFinalState {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedRunId,
    # S3c-FIX F3: XC2 takes the SLICE ID LIST and RE-DERIVES the validated trail ITSELF
    # from the on-disk ledgers (single source of truth; check==use). It NEVER trusts a
    # caller-supplied TrailResult digest - the go_round authority is the on-disk ledgers,
    # not the caller. A forged @{ ...; go_round=$null } can no longer be expressed here.
    [Parameter(Mandatory = $true)][string[]]$SliceIds,
    # per-slice final-state descriptors: member set EXACTLY
    # { slice_id; session_root; final_surfaces=@(@{ rel; path }); caller_bundle_ref (opt) }
    [Parameter(Mandatory = $true)]$SliceFinalState
  )
  if ([string]::IsNullOrWhiteSpace($RunRoot) -or -not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE xc2: RunRoot '$RunRoot' is not an existing directory => BLOCK"
  }
  if ([string]::IsNullOrWhiteSpace($ExpectedRunId)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE xc2: ExpectedRunId is blank => BLOCK (PA-2)"
  }
  if (@($SliceIds).Count -eq 0) {
    New-NeoBlock "reason_code=LEDGER_FAILURE xc2: SliceIds is empty => BLOCK"
  }
  if ($null -eq $SliceFinalState) {
    New-NeoBlock "reason_code=LEDGER_FAILURE xc2: SliceFinalState is null => BLOCK"
  }

  # (F3) DERIVE the validated trail HERE, as XC2's first act, from the on-disk ledgers via
  # the single-source-of-truth trail validator (check==use). This is the ONLY trail
  # derivation in the END gate (Invoke-NeoLoopEndGate no longer validates it separately);
  # its go_round is the on-disk authority every XC2 comparison anchors to. A trail BLOCK
  # here IS an assembly failure and routes ESCALATION_STOP upstream (the end-gate catch).
  $TrailResult = Assert-NeoLoopEndTrail -RunRoot $RunRoot -ExpectedRunId $ExpectedRunId -SliceIds $SliceIds

  # index the caller's final-state descriptors by slice_id (member set EXACT per entry).
  $fsBySlice = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
  foreach ($fs in @($SliceFinalState)) {
    if ($null -eq $fs) { New-NeoBlock "reason_code=LEDGER_FAILURE xc2: a SliceFinalState entry is null => BLOCK" }
    $fsRequired = @('slice_id', 'session_root', 'final_surfaces')
    $names = @(Get-NeoPropNames $fs)
    foreach ($n in $names) {
      if (($fsRequired -cnotcontains [string]$n) -and ([string]$n -cne 'caller_bundle_ref')) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2: SliceFinalState entry has STRAY member '$n' - member set must be {$($fsRequired -join ', '), caller_bundle_ref(optional)} => BLOCK"
      }
    }
    foreach ($n in $fsRequired) {
      if (-not (Test-NeoHasProp $fs $n)) { New-NeoBlock "reason_code=LEDGER_FAILURE xc2: SliceFinalState entry missing member '$n' => BLOCK" }
    }
    $fsid = [string](Get-NeoProp $fs 'slice_id')
    if ([string]::IsNullOrWhiteSpace($fsid)) { New-NeoBlock "reason_code=LEDGER_FAILURE xc2: SliceFinalState entry slice_id is blank => BLOCK" }
    if ($fsBySlice.ContainsKey($fsid)) { New-NeoBlock "reason_code=LEDGER_FAILURE xc2: DUPLICATE SliceFinalState entry for slice '$fsid' => BLOCK" }
    $fsBySlice[$fsid] = $fs
  }

  # (S3c-FIX-2) NO STRAY DESCRIPTOR: one authoritative universe drives BOTH directions. The
  # GO-slice-without-descriptor direction already BLOCKs below; this closes the reverse - a
  # SliceFinalState descriptor for a slice_id ABSENT from the discovered universe is a
  # forged/stray descriptor => BLOCK. $TrailResult.slices IS the discovered universe (the
  # trail validator asserted -SliceIds == discovered, then iterated it), so membership here
  # is against evidence, not the caller's word. Case-sensitive (ordinal) set.
  $universeSet = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
  foreach ($sd in @(Get-NeoProp $TrailResult 'slices')) { $universeSet[[string](Get-NeoProp $sd 'slice_id')] = $true }
  foreach ($fsid in @($fsBySlice.Keys)) {
    if (-not $universeSet.ContainsKey([string]$fsid)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE xc2: SliceFinalState descriptor for slice '$fsid' is NOT in the run's discovered universe [$(@($universeSet.Keys) -join ', ')] => BLOCK (no stray/forged descriptor - a final-state descriptor must correspond to a slice the run actually recorded)"
    }
  }

  $Index = Get-NeoRunSchemaIndex
  $sliceResults = @()
  foreach ($sd in @(Get-NeoProp $TrailResult 'slices')) {
    $sid = [string](Get-NeoProp $sd 'slice_id')
    $goRound = Get-NeoProp $sd 'go_round'

    # PR-2: no GO round for the slice => XC2 has no comparison target => NO_GO_BUNDLE.
    # NOT a failure, NOT a silent skip. A caller asserting a GO bundle ref for a slice
    # the trail shows never reached GO => BLOCK (PA-3 forgery).
    if ($null -eq $goRound) {
      if ($fsBySlice.ContainsKey($sid) -and (Test-NeoHasProp $fsBySlice[$sid] 'caller_bundle_ref')) {
        $cbr = [string](Get-NeoProp $fsBySlice[$sid] 'caller_bundle_ref')
        if (-not [string]::IsNullOrWhiteSpace($cbr)) {
          New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: caller asserts a GO bundle_ref '$cbr' but the validated trail shows the slice NEVER reached GO => BLOCK (PA-3 forgery; a never-GO slice records $($script:NeoLoopNoGoBundleMarker))"
        }
      }
      $sliceResults += , @{ slice_id = $sid; xc2 = $script:NeoLoopNoGoBundleMarker; bundle_ref = $null; members_checked = 0 }
      continue
    }

    if (-not $fsBySlice.ContainsKey($sid)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: the validated trail has a GO round $goRound but no SliceFinalState descriptor was supplied for the slice => BLOCK (a GO slice must present its final surfaces for XC2)"
    }
    $fs = $fsBySlice[$sid]
    $sessRoot = [string](Get-NeoProp $fs 'session_root')
    if ([string]::IsNullOrWhiteSpace($sessRoot) -or -not (Test-Path -LiteralPath $sessRoot -PathType Container)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: session_root '$sessRoot' is not an existing directory => BLOCK"
    }

    # (X1) DERIVE the authoritative last-GO bundle_ref from the run_id-bound spawn ledger
    # for this slice's GO round (round_id 'round-<go>' + the validated GO auditor_identity),
    # NOT the caller's word (PA-3). REUSE the frozen readers + the frozen correlation rule
    # (NOTE-1: one rule, one place). Assert-NeoSpawnCorrelatedSlot correlates a KNOWN
    # bundle_ref; here we must first DERIVE the ref from (auditor_identity + round_id), then
    # re-confirm uniqueness with the frozen gate on a synthesized Slot - byte-identical to
    # the live gate-B correlation, never a second divergent lookup.
    $goRoundId = 'round-' + [int]$goRound
    $goAuditor = [string](Get-NeoProp $sd 'go_auditor_identity')
    if ([string]::IsNullOrWhiteSpace($goAuditor)) {
      New-NeoBlock "reason_code=SPAWN_UNCORRELATED xc2[$sid]: the validated GO round carries no auditor_identity => BLOCK (cannot derive the audited bundle)"
    }
    $spawnPath = Resolve-NeoRunStatePath $RunRoot $script:NeoSpawnLedgerLeaf
    if (-not (Test-Path -LiteralPath $spawnPath)) {
      New-NeoBlock "reason_code=SPAWN_UNCORRELATED xc2[$sid]: NO spawn ledger under RunRoot - the audited bundle for the GO round cannot be derived => BLOCK"
    }
    # frozen fail-closed reader, run_id-bound (foreign-run entry => BLOCK inside). Pipe
    # through ForEach-Object so each entry is an element (the ,@() nesting trap, as above).
    $spawnEntries = @(); Read-NeoRunLedgerEntries -Path $spawnPath -SchemaId 'neo:spawn_ledger_entry' -Index $Index -Label 'spawn_ledger' -ExpectedRunId $ExpectedRunId | ForEach-Object { $spawnEntries += $_ }
    $goSpawn = @($spawnEntries | Where-Object {
        ([string](Get-NeoProp $_ 'auditor_identity') -ceq $goAuditor) -and
        ([string](Get-NeoProp $_ 'round_id') -ceq $goRoundId)
      })
    if (@($goSpawn).Count -eq 0) {
      New-NeoBlock "reason_code=SPAWN_UNCORRELATED xc2[$sid]: no spawn-ledger entry for the validated GO round ('$goRoundId' + auditor_identity '$goAuditor') - the audited bundle cannot be derived => BLOCK"
    }
    if (@($goSpawn).Count -gt 1) {
      New-NeoBlock "reason_code=SPAWN_INVALID xc2[$sid]: AMBIGUOUS - $(@($goSpawn).Count) spawn-ledger entries match the GO round ('$goRoundId' + auditor_identity '$goAuditor'); spec sec-0 requires a single entry => BLOCK"
    }
    $derivedBundleRef = [string](Get-NeoProp $goSpawn[0] 'bundle_ref')

    # NOTE-1 re-confirm via the frozen gate-B correlation, byte-identical to the live round:
    # synthesize the Slot the validated GO evidence implies and run the SAME function. A
    # non-unique/absent/stale correlation => BLOCK inside the frozen gate. This is the same
    # rule in one place, never a second correlation.
    $synthSlot = [pscustomobject]@{ auditor_identity = $goAuditor; bundle_ref = $derivedBundleRef }
    [void](Assert-NeoSpawnCorrelatedSlot -RunRoot $RunRoot -Slot $synthSlot -RoundId $goRoundId)

    # PA-3: a caller-supplied bundle_ref, when present, MUST equal the derived one
    # (stale / wrong-slice / wrong-round / absent-from-validated-trail all diverge here).
    if (Test-NeoHasProp $fs 'caller_bundle_ref') {
      $cbr = [string](Get-NeoProp $fs 'caller_bundle_ref')
      if ((-not [string]::IsNullOrWhiteSpace($cbr)) -and ($cbr -cne $derivedBundleRef)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: caller-supplied bundle_ref '$cbr' does not match the spawn-ledger-derived last-GO bundle_ref '$derivedBundleRef' for round '$goRoundId' => BLOCK (PA-3: the comparison TARGET comes from validated evidence, not the caller's word)"
      }
    }

    # (X2) RESOLVE + RE-VALIDATE the audited bundle exactly as the frozen seam does
    # (XC1 containment on the ref; schema + envelope + packet self-hash re-checked).
    Assert-NeoSafeRel $derivedBundleRef
    $bundleFull = Assert-NeoContained $sessRoot $derivedBundleRef
    if (-not (Test-Path -LiteralPath $bundleFull -PathType Leaf)) {
      New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: derived bundle_ref '$derivedBundleRef' resolves to no file under session_root => BLOCK"
    }
    $bundle = Read-NeoJsonFile $bundleFull
    Assert-NeoValid $bundle 'neo:input_packet' $Index 'AUDIT_BUNDLE(xc2 derived bundle_ref)'
    Assert-NeoArtifactHash $bundle 'AUDIT_BUNDLE(xc2)'
    Assert-NeoPacketSelfHash $bundle 'AUDIT_BUNDLE(xc2)'

    # the audited member set is the AUTHORITATIVE path set (PA-4). Canonical rels.
    $auditedByRel = @{}
    foreach ($m in @($bundle.allowlist)) {
      $mrel = [string](Get-NeoProp $m 'path')
      Assert-NeoSafeRel $mrel
      $canon = ($mrel -replace '\\', '/')
      if ($auditedByRel.ContainsKey($canon)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: audited bundle carries a DUPLICATE member rel '$mrel' => BLOCK"
      }
      $auditedByRel[$canon] = [string](Get-NeoProp $m 'content_hash')
    }

    # the caller's final-surface set (member set EXACT per surface).
    $finalByRel = @{}
    foreach ($surf in @(Get-NeoProp $fs 'final_surfaces')) {
      if ($null -eq $surf) { New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: a final_surfaces entry is null => BLOCK" }
      $sNames = @(Get-NeoPropNames $surf)
      foreach ($n in $sNames) {
        if (@('rel', 'path') -cnotcontains [string]$n) {
          New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: final_surfaces entry has STRAY member '$n' - member set must be EXACTLY {rel, path} => BLOCK"
        }
      }
      foreach ($n in @('rel', 'path')) {
        if (-not (Test-NeoHasProp $surf $n)) { New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: final_surfaces entry missing member '$n' => BLOCK" }
      }
      $srel = [string](Get-NeoProp $surf 'rel')
      Assert-NeoSafeRel $srel
      $scanon = ($srel -replace '\\', '/')
      if ($finalByRel.ContainsKey($scanon)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: DUPLICATE final surface rel '$srel' => BLOCK"
      }
      $finalByRel[$scanon] = $surf
    }

    # (X3) MEMBER-SET EQUALITY FIRST (PA-4): final set == audited set EXACTLY, BEFORE any
    # hash comparison. An audited member OMITTED from the final list => BLOCK (no
    # surface-omission bypass); an extra final surface not in the audited set => BLOCK.
    foreach ($ar in @($auditedByRel.Keys)) {
      if (-not $finalByRel.ContainsKey($ar)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: audited bundle member '$ar' is OMITTED from the final surface list => BLOCK (PA-4: no surface-omission bypass)"
      }
    }
    foreach ($fr in @($finalByRel.Keys)) {
      if (-not $auditedByRel.ContainsKey($fr)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: final surface '$fr' is NOT in the audited bundle member set => BLOCK (PA-4: exact member-set equality)"
      }
    }

    # (X4) HASH EQUALITY: final on-disk Get-NeoSha256File (REUSED, never re-implemented)
    # of each member, resolved with XC1 containment, MUST -ceq the audited content_hash.
    foreach ($rel in @($auditedByRel.Keys)) {
      $surf = $finalByRel[$rel]
      # the AUTHORITATIVE on-disk location is the rel resolved+contained under session_root
      # (check==use; a rel that resolves outside session_root => BLOCK inside).
      $memberFull = Assert-NeoContained $sessRoot $rel
      # (S3c-FIX F4) `path` is LOAD-BEARING, not decorative: the caller-supplied absolute
      # `path` MUST resolve to EXACTLY this contained location. A `path` that disagrees with
      # its own `rel` (points elsewhere / outside session_root) is misleading evidence =>
      # BLOCK. GetFullPath-normalized, OrdinalIgnoreCase to match Assert-NeoContained's own
      # containment comparison. The HASH is still taken from $memberFull (the rel authority),
      # so `path` can never REDIRECT the hash - it can only be asserted consistent or BLOCK.
      $surfPath = [string](Get-NeoProp $surf 'path')
      if ([string]::IsNullOrWhiteSpace($surfPath)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: final surface '$rel' carries a blank 'path' => BLOCK (F4: path is load-bearing evidence, never blank)"
      }
      $surfPathFull = ''
      try { $surfPathFull = [System.IO.Path]::GetFullPath($surfPath) }
      catch { New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: final surface '$rel' 'path' ('$surfPath') is not a resolvable path => BLOCK (F4)" }
      if (-not $surfPathFull.Equals($memberFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: final surface 'path' ('$surfPathFull') does not resolve to the session_root-contained location of its 'rel' '$rel' ('$memberFull') => BLOCK (F4: a path that disagrees with its rel is misleading evidence)"
      }
      if (-not (Test-Path -LiteralPath $memberFull -PathType Leaf)) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: final surface '$rel' resolves to no file under session_root => BLOCK (XC2: an audited member missing at END is a silent delta)"
      }
      $finalHash = Get-NeoSha256File $memberFull
      if ($finalHash -cne $auditedByRel[$rel]) {
        New-NeoBlock "reason_code=LEDGER_FAILURE xc2[$sid]: final on-disk hash of '$rel' ($finalHash) != last GO-audited content_hash ($($auditedByRel[$rel])) => BLOCK (XC2: no silent delta between what was audited and what is kept - a post-audit mutation is either a recorded+audited NEW round or an END BLOCK)"
      }
    }

    $sliceResults += , @{
      slice_id = $sid; xc2 = 'MATCHED'; bundle_ref = $derivedBundleRef
      members_checked = @($auditedByRel.Keys).Count
    }
  }

  # (F3) return the SELF-DERIVED validated trail alongside the XC2 results so the end gate
  # can surface it WITHOUT a second re-derivation (single-derivation wiring).
  return @{ ok = $true; slices = @($sliceResults); trail = $TrailResult }
}

# ---- Invoke-NeoLoopEndGate (THE HUMAN-END SURFACE; F5 -HumanEndClass call site) ----
# Assembles the END result: trail validation ALWAYS + final-state validation WHERE a GO
# bundle exists (PR-2) + the run's stop/converge envelope; then notifies through
# Invoke-NeoLoopStopNotify with -HumanEndClass: SESSION_END on an all-GO converged run,
# DECISION_NEEDED on a surfaced STOP needing keep/iterate/toss (INCLUDING a STOP-before-GO
# run). THIS IS THE ONLY -HumanEndClass CALL SITE (F5): the two human classes, nothing
# else, and ONLY after the assembly gates ran. A FAILED assembly (trail BLOCK / XC2 delta
# / consistency BLOCK) routes the ESCALATION_STOP lane (a normal reason_code, NEVER a
# human class); NO_GO_BUNDLE is NOT an assembly failure. Notification stays
# convenience-never-authority (DEF-P8): a notify failure never blocks or reorders the
# result; the END result carries the notify outcome. NO auto-decision: the function
# returns the assembled evidence; keep/iterate/toss is the human's.
function Invoke-NeoLoopEndGate {
  param(
    [Parameter(Mandatory = $true)]$Context,
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedRunId,
    [Parameter(Mandatory = $true)][string[]]$SliceIds,
    [Parameter(Mandatory = $true)]$ConvergeEnvelope,
    # per-slice final-state descriptors for XC2 (only used where a GO bundle exists).
    $SliceFinalState
  )
  # F4: the Context contract is validated FIRST at its own boundary (bare-throw,
  # contract-not-runtime - the notify choke point consumes this same normalized context).
  $ctx = Assert-NeoLoopContext -Context $Context
  if ([string]::IsNullOrWhiteSpace($RunRoot) -or -not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-gate: RunRoot '$RunRoot' is not an existing directory => BLOCK"
  }
  if ([string]::IsNullOrWhiteSpace($ExpectedRunId)) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-gate: ExpectedRunId is blank => BLOCK (PA-2: run identity is caller-TRUSTED from the run/converge envelope)"
  }
  if (@($SliceIds).Count -eq 0) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-gate: SliceIds is empty => BLOCK"
  }
  if ($null -eq $ConvergeEnvelope -or -not (Test-NeoHasProp $ConvergeEnvelope 'stopped')) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-gate: ConvergeEnvelope is null/malformed (must be an Invoke-NeoLoopConverge return) => BLOCK"
  }
  # derive the run disposition from the envelope: converged all-GO vs surfaced STOP.
  $envStopped = [bool](Get-NeoProp $ConvergeEnvelope 'stopped')
  $envConverged = $false
  if (Test-NeoHasProp $ConvergeEnvelope 'converged') { $envConverged = [bool](Get-NeoProp $ConvergeEnvelope 'converged') }
  $stopPresent = $envStopped
  if ($envStopped -eq $envConverged) {
    New-NeoBlock "reason_code=LEDGER_FAILURE end-gate: ConvergeEnvelope is internally inconsistent (stopped=$envStopped, converged=$envConverged - exactly one must hold) => BLOCK"
  }

  # ---- ASSEMBLY (fail-closed): trail ALWAYS, XC2 where a GO bundle exists. A BLOCK in
  # either is an ASSEMBLY FAILURE => ESCALATION_STOP, never a human class. NO_GO_BUNDLE is
  # a value, not a failure. We catch the assembly BLOCK, route it, and return the evidence.
  $trail = $null
  $finalState = $null
  $assemblyOk = $true
  $assemblyFailDetail = ''
  $assemblyFailCode = ''
  try {
    # (S3c-FIX F3) SINGLE-DERIVATION: XC2 now RE-DERIVES the validated trail itself from
    # the on-disk ledgers (never a caller-trusted digest) and returns it. The end gate no
    # longer validates the trail separately - trail validation runs EXACTLY ONCE (inside
    # XC2) and XC2 runs once. Trail-ALWAYS is preserved: XC2 is always invoked and its
    # first act validates every slice's trail. A trail BLOCK inside XC2 throws here and is
    # caught as an assembly failure => ESCALATION_STOP; in that case $trail stays $null
    # (a failed assembly has no validated trail - honest evidence, session-control-accepted).
    $sfs = @()
    if ($null -ne $SliceFinalState) { $sfs = @($SliceFinalState) }
    $finalState = Assert-NeoLoopFinalState -RunRoot $RunRoot -ExpectedRunId $ExpectedRunId -SliceIds $SliceIds -SliceFinalState $sfs
    $trail = $finalState.trail
  } catch {
    $m = $_.Exception.Message
    $assemblyOk = $false
    $assemblyFailDetail = $m
    $assemblyFailCode = Get-NeoLoopReasonCode $m
    if ($assemblyFailCode -ceq 'UNKNOWN') { $assemblyFailCode = 'CLASSIFIER_ERROR' }
  }

  if (-not $assemblyOk) {
    # FAILED assembly => the ESCALATION_STOP lane (spec 216-222 + dispatch item 3:
    # "a FAILED assembly => the ESCALATION_STOP lane, never a human class"), NEVER
    # -HumanEndClass. An END-assembly failure (trail BLOCK / XC2 delta / consistency BLOCK)
    # is an ESCALATION event surfaced to the human via the escalation lane - NOT a mid-run
    # breaker trip. The underlying assembly-fail reason_code (which may be a breaker-class
    # code such as LEDGER_FAILURE from the trail/XC2 readers) is preserved in the return +
    # the notify detail for evidence; the GATE CLASS the notification carries is routed
    # through the ESCALATION_STOP-mapped code so the human sees an escalation surface, not a
    # breaker. A human-END class can never be reached here because -HumanEndClass is not
    # passed AND the routing code is an escalation code (fail-closed either way).
    $n = Invoke-NeoLoopStopNotify -ReasonCode 'END_ASSEMBLY_FAILED' -SliceId $ctx.slice_id -Round $ctx.round `
      -Detail ("END assembly FAILED (underlying reason_code=" + $assemblyFailCode + "): " + (ConvertTo-NeoLoopAsciiLine $assemblyFailDetail 150)) -EvidencePath $ctx.evidence_path `
      -TestModeDir:$ctx.notify_test_mode_dir -LiveSend:$ctx.notify_live_send
    return @{
      assembly_ok = $false; human_class = $null; gate_class = [string]$n.gate_class
      trail = $trail; final_state = $finalState; notify = $n.status
      converged = $envConverged; stop_present = $stopPresent
      assembly_fail_code = $assemblyFailCode; assembly_fail_detail = $assemblyFailDetail
    }
  }

  # ---- clean assembly => the human-END class. SESSION_END on a clean all-GO converged
  # run; DECISION_NEEDED on a surfaced STOP (incl. STOP-before-GO). NO_GO_BUNDLE slices do
  # NOT change the class - the gate still assembles + surfaces (spec 216-222 + PR-2).
  $humanClass = if ($envConverged) { 'SESSION_END' } else { 'DECISION_NEEDED' }
  $detail = if ($envConverged) {
    "converged all-GO run - END assembly clean (trail 1:1 + XC2 validated); keep/iterate/toss is the human's"
  } else {
    "surfaced STOP - END assembly clean (trail validated; XC2 where a GO bundle exists, NO_GO_BUNDLE otherwise); keep/iterate/toss is the human's"
  }
  # F5: -HumanEndClass is passed ONLY here, ONLY for the two human classes, ONLY after
  # both assembly gates passed. Notify is convenience-never-authority: a failure leaves
  # the assembled END result intact (the choke point never throws).
  $n = Invoke-NeoLoopStopNotify -ReasonCode $humanClass -SliceId $ctx.slice_id -Round $ctx.round `
    -Detail $detail -EvidencePath $ctx.evidence_path `
    -TestModeDir:$ctx.notify_test_mode_dir -LiveSend:$ctx.notify_live_send -HumanEndClass
  return @{
    assembly_ok = $true; human_class = $humanClass; gate_class = [string]$n.gate_class
    trail = $trail; final_state = $finalState; notify = $n.status
    converged = $envConverged; stop_present = $stopPresent
  }
}
