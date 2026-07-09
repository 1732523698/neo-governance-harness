# =============================================================================
# NEO 4.0-P4-AUTONOMY INTEGRATE - orch_run.ps1 (THE ONE-CALL RUN SURFACE)
# =============================================================================
# Wires the SIX kept engine components into ONE callable end-to-end run surface:
#   instruct -> C5 (freeze -> plan audit -> gate readiness -> the HUMAN START
#   gate) -> per-slice STRICTLY SERIAL convergence loop -> END assembly -> the
#   human END gate.
# COORDINATE-ONLY DISCIPLINE (integrate dispatch sec-0/3.A.5): this module
# COORDINATES; it never validates its own work; every gate/check it relies on
# is a FROZEN function it CALLS, never re-derives; it writes NOTHING under
# .neo\ and never writes a freeze/gate/verdict/ledger record itself (the frozen
# surfaces own their writes; the run manifest is CALLER-created via the frozen
# New-NeoRunManifest BEFORE prepare - START-release ruling Q1, 2026-07-07).
# AUTO-MODE AMENDMENT (slice 1d, spec 4F549F3A sec 4 - disclosed honestly): the
# END decision consumer, under a VALID AUTO chain ONLY, writes ONE file -
# <RunRoot>\engine_auto_keep.json - a RUN-EVIDENCE record of an engine-decided
# auto-keep pending MANDATORY async human review. It lives under RunRoot ONLY
# (never under .neo\) and is NOT a gate/freeze/verdict record. INV-A1 stands:
# NO code path in this module writes the human-gate ledger, and the human
# end-keep decision remains EXCLUSIVELY human-authored.
# STRICTLY SERIAL at every level (spec invariant 5): no background jobs, no
# parallel slice/round constructs; batching = report collection only.
#
# THE TWO-CHAIN MEETING POINT (grounded orch_clarity.ps1:42-44 + 1005-1021):
# orch_clarity deliberately does NOT dot-source orch_loop (mutual-source
# recursion hazard); the completeness carry Assert-NeoClarityPlanSliceUniverse
# BLOCKs fail-closed (CLARITY_UNIVERSE) unless the CALLER's process sourced
# orch_loop. THIS module is the designated meeting point: it sources BOTH
# chains (both are re-sourceable - functions + script vars only, no load
# guards; the shared transitive helpers are redefined idempotently).
#
# THE HUMAN DECISION LIVES BETWEEN THE TWO PATHS (doctrine D3): the engine
# NEVER infers approval. Invoke-NeoRunPrepare surfaces the START gate;
# Invoke-NeoRunExecute requires the recorded human START approval (an exact
# engine-computed gate_ref binding + gate_kind 'human_start_approval'; the
# manager WRITES the ledger entry at the gate - the engine only READS it).
#
# ASCII-only (D10). Kept separate from the frozen legacy B1 surface
# orchestrator.ps1 (no name collision: every public surface here is *-NeoRun*).
# =============================================================================

$script:NeoRunDir = $PSScriptRoot
. "$script:NeoRunDir\orch_clarity.ps1"
. "$script:NeoRunDir\orch_loop.ps1"

# ---- START-approval constants (START-release ruling Q2/Q3, 2026-07-07;
# AUTO-mode 6-segment cutover per NEO_AUTOMODE_DESIGN_v1 rev5, slice 1d) ------
# gate_ref format: deterministic, no free-form parts, whole-string -ceq match:
#   NEO-RUN-START|<run_id>|<plan_round>|<freeze_record_sha256>|<bundle_diff_hash>|<autonomy_sha256>
# where <autonomy_sha256> = SHA-256 of <RunRoot>\autonomy_mode record file
# bytes at prepare time, or the literal token NONE when absent (interactive).
# The explicit positive decision is a case-exact ordinal gate_kind PAIRED to
# the run's autonomy mode (spec 3B / NF-A10): segment NONE (interactive)
# requires 'human_start_approval'; a hash-bearing segment (declared AUTO)
# requires 'attested_start_approval'; ANY cross-pairing and ANY other value
# (human_end_keep / blank / unknown / casing variants) on a correctly-bound
# entry is a bound NON-approval => refuse.
$script:NeoRunStartGateRefPrefix    = 'NEO-RUN-START'
$script:NeoRunStartGateKind         = 'human_start_approval'
$script:NeoRunStartGateKindAttested = 'attested_start_approval'
$script:NeoRunAutonomySegmentNone   = 'NONE'
# THE ONLY raw-filename site in the engine (NF-A7 one-read-site static proof).
$script:NeoRunAutonomyLeaf          = 'autonomy_mode.json'
$script:NeoRunAutoKeepLeaf          = 'engine_auto_keep.json'
$script:NeoRunAutoTiersDeclared     = @('LOW', 'MEDIUM', 'HIGH')

# =============================================================================
# (1) THE ENGINE-COMPUTED START-APPROVAL BINDING (dispatch 3.A.2)
# =============================================================================
# The engine COMPUTES the expected gate_ref from the CURRENT freeze identity +
# run manifest; it NEVER parses ledger entries and NEVER selects among them.
function Get-NeoRunStartGateRef {
  param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$PlanRound,
    [Parameter(Mandatory = $true)][string]$FreezeRecordSha256,
    [Parameter(Mandatory = $true)][string]$BundleDiffHash,
    # segment 6 (AUTO-mode cutover, spec 3A): the autonomy record's file-byte
    # SHA-256 at prepare time, or the literal token NONE when absent. A run
    # approved on the old 5-segment tuple recomputes 6 here, finds no matching
    # entry, and REFUSES (fail-closed cutover, DEV-only).
    [Parameter(Mandatory = $true)][string]$AutonomySegment
  )
  $parts = @(
    @('RunId', $RunId), @('PlanRound', $PlanRound),
    @('FreezeRecordSha256', $FreezeRecordSha256), @('BundleDiffHash', $BundleDiffHash),
    @('AutonomySegment', $AutonomySegment))
  foreach ($p in $parts) {
    $name = [string]$p[0]; $v = [string]$p[1]
    if ([string]::IsNullOrWhiteSpace($v)) {
      New-NeoBlock "reason_code=RUN_START_APPROVAL gate-ref: binding part '$name' is blank - the binding tuple is engine-derived and never optional => BLOCK"
    }
    if ($v.Contains('|')) {
      New-NeoBlock "reason_code=RUN_START_APPROVAL gate-ref: binding part '$name' contains the reserved separator '|' - the gate_ref format is deterministic with no free-form parts => BLOCK"
    }
  }
  if (($AutonomySegment -cne $script:NeoRunAutonomySegmentNone) -and ($AutonomySegment -cnotmatch '^[0-9a-f]{64}$')) {
    New-NeoBlock "reason_code=RUN_START_APPROVAL gate-ref: AutonomySegment '$AutonomySegment' is neither the literal token NONE nor a lowercase sha256 - the segment is engine-derived (case-exact), never free-form => BLOCK"
  }
  return ($script:NeoRunStartGateRefPrefix + '|' + $RunId + '|' + $PlanRound + '|' + $FreezeRecordSha256 + '|' + $BundleDiffHash + '|' + $AutonomySegment)
}

# Reads the recorded human START approval, fail-closed (dispatch 3.A.2 +
# START-release Q2/Q3). EXACTLY-ONE rule: multiplicity is counted on the RAW
# gate_ref-bound entries BEFORE any gate_kind filtering (filter-then-count is
# the dodge - one valid approval + one malformed same-tuple entry must still
# refuse). ZERO => refuse; TWO OR MORE (any decisions) => refuse naming the
# conflict - a conflicted ledger is a human question, never an engine pick.
# The single bound entry must then carry gate_kind -ceq 'human_start_approval'
# (Assert-NeoGateLedgerShape checks key PRESENCE only - the decision check
# lives HERE) and a non-blank authorized_by (the human principal).
function Read-NeoRunStartApproval {
  param(
    [Parameter(Mandatory = $true)][string]$LedgerPath,
    [Parameter(Mandatory = $true)][string]$ExpectedGateRef,
    # MODE<->KIND PAIRING (spec 3B / NF-A10, case-exact): segment NONE
    # (interactive) requires 'human_start_approval'; a hash-bearing segment
    # (declared AUTO) requires 'attested_start_approval'. ANY cross-pairing
    # REFUSES - the two START authorities are structurally non-confusable.
    [Parameter(Mandatory = $true)][string]$AutonomySegment,
    $Index
  )
  $expectedKind = $script:NeoRunStartGateKind
  if ($AutonomySegment -cne $script:NeoRunAutonomySegmentNone) { $expectedKind = $script:NeoRunStartGateKindAttested }
  $led = Read-NeoGateLedger $LedgerPath $Index
  # shape guard ALWAYS (Read-NeoGateLedger applies it only when $Index is
  # passed; the approval read is fail-closed regardless of index availability).
  Assert-NeoGateLedgerShape $led
  # RAW whole-string -ceq matches FIRST (never parsing, never selection order).
  $matched = @()
  foreach ($e in @(Get-NeoProp $led 'entries')) {
    if ([string](Get-NeoProp $e 'gate_ref') -ceq $ExpectedGateRef) { $matched += ,$e }
  }
  if (@($matched).Count -eq 0) {
    New-NeoBlock "reason_code=RUN_START_APPROVAL no ledger entry is bound to the CURRENT plan (expected gate_ref '$ExpectedGateRef') => REFUSE (approval is the human's explicit recorded answer bound to the exact approved plan - a missing or stale binding, e.g. an approval recorded for an earlier plan_round or a different freeze/bundle hash, is never accepted)"
  }
  if (@($matched).Count -ge 2) {
    $kinds = @()
    foreach ($m in @($matched)) { $kinds += ("'" + [string](Get-NeoProp $m 'gate_kind') + "'") }
    New-NeoBlock "reason_code=RUN_START_APPROVAL $(@($matched).Count) ledger entries are bound to the SAME gate_ref '$ExpectedGateRef' (gate_kinds: $($kinds -join ', ')) => REFUSE (EXACTLY-ONE rule: multiplicity counted on the RAW tuple-bound entries BEFORE any decision filtering; a conflicted ledger is a human question, never an engine pick)"
  }
  # CONFLICTED START AUTHORITY (iterate round; codex HIGH-1/MED-1): one
  # approved PLAN identity (the first five segments) may carry exactly ONE
  # autonomy identity (the sixth). An entry sharing the 5-segment prefix but
  # bound to a DIFFERENT autonomy segment means a post-gate mode flip forged a
  # SECOND START authority against the same approved plan => REFUSE. The
  # attacker is forced to also DELETE the recorded human answer - the strictly
  # stronger, pre-existing forgery class. Legitimate iterate rounds are
  # unaffected (a fresh prepare is a new plan_round => a new 5-segment prefix).
  $prefix5 = $ExpectedGateRef.Substring(0, $ExpectedGateRef.LastIndexOf('|') + 1)
  foreach ($e in @(Get-NeoProp $led 'entries')) {
    $er = [string](Get-NeoProp $e 'gate_ref')
    if ($er.StartsWith($prefix5, [System.StringComparison]::Ordinal) -and ($er -cne $ExpectedGateRef)) {
      New-NeoBlock "reason_code=RUN_START_APPROVAL CONFLICTED START AUTHORITY: a ledger entry is bound to the SAME plan identity '$prefix5' with a DIFFERENT autonomy segment (entry gate_ref '$er' vs expected '$ExpectedGateRef') => REFUSE (a single approved plan identity carries exactly ONE autonomy identity; a conflicted ledger is a human question, never an engine pick)"
    }
  }
  $entry = $matched[0]
  $kind = [string](Get-NeoProp $entry 'gate_kind')
  if ($kind -cne $expectedKind) {
    New-NeoBlock "reason_code=RUN_START_APPROVAL the single bound ledger entry carries gate_kind '$kind' - the explicit positive decision for this run's autonomy mode (segment '$AutonomySegment') is gate_kind '$expectedKind' EXACTLY (case-exact ordinal; the mode<->kind pairing refuses ANY cross-pairing, NF-A10); a correctly-bound record with ANY other value (denied / pending / blank / unknown / casing variant / wrong gate class) is a bound NON-approval => REFUSE (approval is never inferred from a record's existence or its binding freshness)"
  }
  $by = [string](Get-NeoProp $entry 'authorized_by')
  if ([string]::IsNullOrWhiteSpace($by)) {
    New-NeoBlock "reason_code=RUN_START_APPROVAL the bound approval entry carries a BLANK authorized_by - the recorded human principal is required => REFUSE"
  }
  return $entry
}

# =============================================================================
# (1b) AUTONOMY MODE (AUTO-mode slice 1d; spec NEO_AUTOMODE_DESIGN_v1 rev5
#      secs 3A/3B/5 - the ONE read surface + the park/keep evidence writers)
# =============================================================================
# The park/keep notifications ride the FROZEN notify surface directly (the
# clarity-gate precedent); convenience never authority: a send failure never
# blocks a park or a keep - it is RECORDED instead. Never throws.
function Send-NeoRunAutoNotice {
  param(
    [Parameter(Mandatory = $true)][string]$GateType,
    [Parameter(Mandatory = $true)][string]$SliceId,
    [Parameter(Mandatory = $true)][string[]]$SummaryLines,
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [string]$TestModeDir,
    [switch]$LiveSend
  )
  $status = @{ sent = $false; deduped = $false; refused = $false; reason = ''; composed_path = $null }
  try {
    $nArgs = @{ GateType = $GateType; SliceId = $SliceId; SummaryLines = $SummaryLines; EvidencePath = $EvidencePath }
    if (-not [string]::IsNullOrWhiteSpace($TestModeDir)) { $nArgs['TestModeDir'] = $TestModeDir }
    elseif ($LiveSend) { $nArgs['LiveSend'] = $true }
    $r = Send-NeoGateNotification @nArgs
    if ($null -ne $r) { $status = $r }
  } catch {
    $status.reason = ('auto-mode notice failed (never blocks the decision; recorded): ' + [string]$_.Exception.Message)
  }
  return $status
}

# Get-NeoRunAutonomyMode - THE ONLY read surface for the per-run autonomy state
# (spec sec 5 one-read-site invariant; NF-A7 carries the enumerated call-site
# allowlist: prepare entry validation, prepare full validation, execute entry
# validation, the END decision consumer's recompute, the END interactive tamper
# probe, and the C5/START package display line via prepare's return).
# FAIL-CLOSED, TWO PINNED LANES (spec 3A rev5):
#   (i)  record ABSENT  => INTERACTIVE (segment NONE; the per-run human C5 path)
#   (ii) record PRESENT but ANY chain link invalid => PARK + NOTIFY, then a
#        RUN_AUTONOMY_PARK BLOCK propagates: no START package in EITHER mode;
#        remedy = fix or remove the record + a FRESH prepare (the new freeze
#        binds NONE or the corrected hash - tamper-evidence preserved).
# Chain links (ENGINE-validated, never manager procedure alone - rev3 cold
# HIGH): file hash -> parse -> schema neo:run_autonomy_mode -> run_id match ->
# autonomy_mode -ceq 'auto' -> anchored attestation stamp (REPLICATING
# notify_raphael.ps1:129-149 semantics, NOT imported) -> attestation hash-match
# -> the NEVER-PROD assertion (the published PROD root literal S:\NEO is
# doctrine-pinned in this module; neither the declared root nor the run root
# may live under it) -> declared-root containment. Stage 'full' ADDS the
# envelope tier assertion
# over the freeze risk rows + the plan-audit-converged-GO assertion (staged
# AFTER the in-prepare plan-audit step per the spec 3B builder note; readiness
# state READY is the FROM-DISK meaning of an archived current-round GO).
# -AttestationPath is a TEST-ONLY seam (fixture twins under TEMP scratch);
# blank => the real engine attestation <NEO root>\.neo\AUTO_MODE_ATTESTATION.md.
function Get-NeoRunAutonomyMode {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [string]$Stage = 'full',
    [string]$AttestationPath,
    [string]$NotifyTestModeDir,
    [switch]$NotifyLiveSend,
    $Index
  )
  if (($Stage -cne 'entry') -and ($Stage -cne 'full')) {
    New-NeoBlock "reason_code=RUN_AUTONOMY_PARK autonomy accessor: Stage '$Stage' is not 'entry'|'full' (case-exact) => BLOCK"
  }
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')
  $recPath = Resolve-NeoRunStatePath $RunRoot $script:NeoRunAutonomyLeaf
  if (-not (Test-Path -LiteralPath $recPath -PathType Leaf)) {
    # lane (i): never declared AUTO => the normal per-run human C5 path.
    return @{ mode = 'interactive'; segment = $script:NeoRunAutonomySegmentNone; record = $null }
  }
  # lane (ii): record PRESENT - ANY invalid link parks (one notification via
  # the frozen surface, then the BLOCK propagates). A declared-hands-off run
  # never silently proceeds interactive and never surfaces a C5 package
  # against a hash-bearing tuple.
  $park = {
    param([string]$LinkDetail)
    $capped = [string]$LinkDetail
    if ($capped.Length -gt 300) { $capped = $capped.Substring(0, 300) }
    $st = Send-NeoRunAutoNotice -GateType 'ESCALATION_STOP' -SliceId $script:NeoClarityPlanSliceId `
      -SummaryLines @(
        'AUTO-mode chain INVALID - run PARKED (no START package in either mode)',
        ('run ' + $runId + '; validation stage ' + $Stage),
        ('link: ' + $capped),
        'remedy: fix or remove the autonomy record + FRESH prepare (tamper-evidence preserved)') `
      -EvidencePath $RunRoot -TestModeDir $NotifyTestModeDir -LiveSend:$NotifyLiveSend
    New-NeoBlock ("reason_code=RUN_AUTONOMY_PARK autonomy chain ($Stage): " + $LinkDetail + " => PARK + NOTIFY (notify sent=" + [string]$st.sent + "; a declared-hands-off run NEVER silently proceeds interactive; remedy: fix or remove the autonomy record + a FRESH prepare)")
  }
  $segment = ''
  try { $segment = Get-NeoSha256File $recPath } catch { & $park ('record unreadable for hashing: ' + [string]$_.Exception.Message) }
  $rec = $null
  try { $rec = Read-NeoJsonFile $recPath } catch { & $park ('record unparseable: ' + [string]$_.Exception.Message) }
  try { Assert-NeoValid $rec 'neo:run_autonomy_mode' $Index 'RUN_AUTONOMY_MODE(read)' } catch { & $park ('record schema-invalid: ' + [string]$_.Exception.Message) }
  if ([string](Get-NeoProp $rec 'run_id') -cne $runId) {
    & $park ("record run_id '" + [string](Get-NeoProp $rec 'run_id') + "' does not match the run manifest run_id '" + $runId + "' (case-exact)")
  }
  if ([string](Get-NeoProp $rec 'autonomy_mode') -cne 'auto') {
    & $park ("record autonomy_mode '" + [string](Get-NeoProp $rec 'autonomy_mode') + "' is not -ceq 'auto' (unknown is NEVER coerced to auto)")
  }
  # ---- standing attestation: anchored stamp semantics REPLICATED from
  # notify_raphael.ps1:129-149 (line-anchored, fail-closed; NOT imported) ------
  $att = $AttestationPath
  if ([string]::IsNullOrWhiteSpace($att)) {
    $att = Join-Path (Resolve-NeoRoot $script:NeoRunDir) '.neo\AUTO_MODE_ATTESTATION.md'
  }
  if (-not (Test-Path -LiteralPath $att -PathType Leaf)) {
    & $park ("standing AUTO attestation not found at '" + $att + "' (missing => refuse)")
  }
  $attLines = @()
  try { $attLines = @(Get-Content -LiteralPath $att -ErrorAction Stop) } catch { & $park ('standing AUTO attestation unreadable: ' + [string]$_.Exception.Message) }
  $inForce = $false
  foreach ($ln in $attLines) {
    if ($ln -match '^STATUS: \*\*APPROVED / IN FORCE') { $inForce = $true }
    if (($ln -match '^\s*REVOKED\b') -or ($ln -match '^\s*STATUS:.*REVOKED')) {
      & $park 'standing AUTO attestation carries a REVOKED status stamp (revocation kills the chain at the next validation boundary)'
    }
  }
  if (-not $inForce) {
    & $park 'standing AUTO attestation is not stamped APPROVED / IN FORCE (an UNSIGNED shipped template can never activate AUTO)'
  }
  $attSha = ''
  try { $attSha = Get-NeoSha256File $att } catch { & $park ('attestation unreadable for hashing: ' + [string]$_.Exception.Message) }
  if ($attSha -cne [string](Get-NeoProp $rec 'attestation_sha256')) {
    & $park ("record attestation_sha256 '" + [string](Get-NeoProp $rec 'attestation_sha256') + "' does not match the on-disk attestation re-hash " + $attSha + " (stale/foreign record; re-signing invalidates old records)")
  }
  # ---- envelope: declared root + max risk tier, parsed line-anchored ---------
  $declRoot = $null
  for ($i = 0; $i -lt $attLines.Count; $i++) {
    if ([string]$attLines[$i] -match '^\s*roots:') {
      $win = [string]$attLines[$i]
      for ($j = $i + 1; ($j -lt $attLines.Count) -and ($j -le ($i + 3)); $j++) { $win = $win + ' ' + [string]$attLines[$j] }
      $m = [regex]::Match($win, "'([^']+)'")
      if ($m.Success) { $declRoot = $m.Groups[1].Value }
      break
    }
  }
  if ([string]::IsNullOrWhiteSpace($declRoot)) {
    & $park 'attestation envelope unparseable: no declared root (a line-anchored roots: declaration carrying a quoted path is required)'
  }
  $declTier = $null
  foreach ($ln in $attLines) {
    if ([string]$ln -match '^\s*max_risk_tier:\s*([A-Za-z]+)') { $declTier = $matches[1]; break }
  }
  if ([string]::IsNullOrWhiteSpace($declTier) -or ($script:NeoRunAutoTiersDeclared -cnotcontains $declTier)) {
    & $park ("attestation envelope unparseable: declared max_risk_tier '" + [string]$declTier + "' is not LOW|MEDIUM|HIGH (case-exact)")
  }
  $runFull = ''
  $declFull = ''
  try {
    $runFull = ([System.IO.Path]::GetFullPath($RunRoot)).TrimEnd('\') + '\'
    $declFull = ([System.IO.Path]::GetFullPath($declRoot)).TrimEnd('\') + '\'
  } catch { & $park ('declared-root containment unresolvable: ' + [string]$_.Exception.Message) }
  # NEVER-PROD (iterate round; codex HIGH-2/MED-2): AUTO is DEV-only by
  # doctrine - NEITHER the declared root NOR the run root may equal or live
  # under the published PROD root. The PROD literal is doctrine-pinned here
  # deliberately (the sandbox boundary is not fixture-configurable). The
  # prefix compare is segment-safe: '<NEO_ROOT>\' does NOT start
  # with 'S:\NEO\'.
  $prodFull = ([System.IO.Path]::GetFullPath('S:\NEO')).TrimEnd('\') + '\'
  foreach ($pair in @(@('declared root', $declFull), @('run root', $runFull))) {
    $pairLbl = [string]$pair[0]
    $pairVal = [string]$pair[1]
    if ($pairVal.StartsWith($prodFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      & $park ($pairLbl + " '" + $pairVal + "' is (or lives under) the published PROD root '" + $prodFull + "' - AUTO is DEV-only; the PROD tree can never be an AUTO envelope")
    }
  }
  if (-not $runFull.StartsWith($declFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    & $park ("run root '" + $runFull + "' is OUTSIDE the attestation-declared root '" + $declFull + "' (envelope breach: non-declared root; DEV-only)")
  }
  if ($Stage -ceq 'full') {
    # (iii-a) envelope tier assertion over the FREEZE risk rows.
    $maxRank = 1
    if ($declTier -ceq 'MEDIUM') { $maxRank = 2 } elseif ($declTier -ceq 'HIGH') { $maxRank = 3 }
    $freeze = $null
    try { $freeze = Get-NeoClarityLatestFreeze -RunRoot $RunRoot -Index $Index } catch { & $park ('freeze unavailable for the envelope tier assertion: ' + [string]$_.Exception.Message) }
    foreach ($row in @(Get-NeoClarityList $freeze 'risk_rows')) {
      $cls = [string](Get-NeoProp $row 'risk_class')
      $rank = 0
      if ($cls -ceq 'low') { $rank = 1 } elseif ($cls -ceq 'medium') { $rank = 2 } elseif ($cls -ceq 'high') { $rank = 3 }
      if (($rank -eq 0) -or ($rank -gt $maxRank)) {
        & $park ("freeze risk row '" + [string](Get-NeoProp $row 'row_id') + "' risk_class '" + $cls + "' exceeds (or is unknown against) the attestation-declared max risk tier " + $declTier + " (envelope breach)")
      }
    }
    # (iii-b) the plan-audit-converged-GO assertion: readiness state READY is
    # the FROM-DISK derivation of an archived current-round GO verdict;
    # anything else (NO_GO, disclosure lanes, BLOCKED) is not a clean
    # converged GO for a declared-AUTO run.
    $readiness = Get-NeoClarityGateReadiness -RunRoot $RunRoot -SessionRoot $SessionRoot -Index $Index
    if ([string]$readiness.state -cne 'READY') {
      & $park ("pre-START plan-audit verdict is not a clean converged GO (readiness state '" + [string]$readiness.state + "'; reason: " + [string]$readiness.reason + ")")
    }
  }
  return @{ mode = 'auto'; segment = $segment; record = $rec; attestation_path = $att
            envelope = @{ declared_root = $declRoot; max_risk_tier = $declTier } }
}

# WRITER HOME (spec sec 4, cold LOW-7): RunRoot ONLY - never .neo\. The record
# is RUN-EVIDENCE of an engine-decided auto-keep pending MANDATORY async human
# review; it is NOT a gate/freeze/verdict record and NEVER substitutes a human
# keep downstream (D-A2 / NF-A6). INV-A1: this module has no writer for the
# human-gate ledger anywhere.
function Write-NeoRunEngineAutoKeep {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$FreezeRecordSha256,
    [Parameter(Mandatory = $true)][string]$AutonomySha256,
    [Parameter(Mandatory = $true)][string]$TrailRef,
    [Parameter(Mandatory = $true)][string]$RecordedAt,
    [Parameter(Mandatory = $true)][string]$NotifyOutcome,
    $Index
  )
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  # [pscustomobject] (the freeze-record precedent): the frozen validator's
  # object test accepts hashtable/PSCustomObject shapes.
  $rec = [pscustomobject]@{
    schema_id            = 'neo:engine_auto_keep'
    run_id               = $RunId
    decided_by           = 'engine_auto'
    freeze_record_sha256 = $FreezeRecordSha256
    autonomy_sha256      = $AutonomySha256
    trail_ref            = $TrailRef
    recorded_at          = $RecordedAt
    notify_outcome       = $NotifyOutcome
    human_review         = 'pending'
  }
  Assert-NeoValid $rec 'neo:engine_auto_keep' $Index 'ENGINE_AUTO_KEEP(write)'
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoRunAutoKeepLeaf
  Write-NeoJsonFile $path $rec
  return $path
}

# =============================================================================
# (2) THE DISPOSITION TRI-STATE (dispatch 3.A.2 slice-transition guard + 3.A.4
#     reduction re-validation; PUBLIC so the fixtures drive it directly - 3.D.6b)
# =============================================================================
# EXACTLY one of the two legal shapes, BOTH keys PRESENT, BOTH strictly boolean:
#   { stopped=$true  AND converged=$false }  -> 'stopped'
#   { stopped=$false AND converged=$true  }  -> 'converged'
# ANY other shape (both true / both false / missing key / non-boolean) =>
# fail-closed BLOCK naming the inconsistency (spec addendum 2026-07-07b:
# outcome-inconsistency is a hard BLOCK on both paths).
function Assert-NeoRunConvergeDisposition {
  param(
    $Envelope,
    [string]$Label = 'converge envelope'
  )
  if ($null -eq $Envelope) {
    New-NeoBlock "reason_code=RUN_DISPOSITION ${Label}: envelope is NULL => BLOCK (the disposition tri-state is fail-closed; no default disposition exists)"
  }
  foreach ($k in @('stopped', 'converged')) {
    if (-not (Test-NeoHasProp $Envelope $k)) {
      New-NeoBlock "reason_code=RUN_DISPOSITION ${Label}: member '$k' is MISSING - the legal shapes require BOTH keys PRESENT => BLOCK"
    }
  }
  $s = Get-NeoProp $Envelope 'stopped'
  $c = Get-NeoProp $Envelope 'converged'
  if (-not ($s -is [bool])) {
    New-NeoBlock "reason_code=RUN_DISPOSITION ${Label}: member 'stopped' is not a BOOLEAN (got '$s') => BLOCK (never coerced)"
  }
  if (-not ($c -is [bool])) {
    New-NeoBlock "reason_code=RUN_DISPOSITION ${Label}: member 'converged' is not a BOOLEAN (got '$c') => BLOCK (never coerced)"
  }
  if ($s -eq $c) {
    New-NeoBlock "reason_code=RUN_DISPOSITION ${Label}: envelope is internally inconsistent (stopped=$s, converged=$c - EXACTLY one must hold) => BLOCK (no further slice dispatch, no human-class END routing on a malformed disposition)"
  }
  if ($s) { return @{ shape = 'stopped' } }
  return @{ shape = 'converged' }
}

# =============================================================================
# (3) THE APP-PIN CARRY (dispatch 3.A.3 - the core new enforcement)
# =============================================================================
# Shared fail-closed check: the C5 APP manifest pin + the freeze's risk-register
# hash pin re-verified against the LIVE app root. THROWS on any mismatch with
# the stable 'APP_PIN_MISMATCH' anchor FIRST in the message (the frozen loop
# caps seam-failure detail at 160 ASCII chars - the anchor + cause survive).
function Assert-NeoRunAppPinCurrent {
  param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$AppPinPath,
    [Parameter(Mandatory = $true)][string]$RiskRegisterRel,
    [Parameter(Mandatory = $true)][string]$RiskRegisterPinSha256,
    [Parameter(Mandatory = $true)][string]$DerivedAt
  )
  try {
    $current = Build-NeoGovManifest -GovernedRoot $AppRoot -DerivedAt $DerivedAt
    [void](Assert-NeoGovManifestReverify -PinnedPath $AppPinPath -Current $current -GovernedRoot $AppRoot)
  } catch {
    throw ('APP_PIN_MISMATCH (C5 app manifest pin vs the LIVE app root): ' + $_.Exception.Message)
  }
  $regFull = $null
  try { $regFull = Assert-NeoContained $AppRoot $RiskRegisterRel }
  catch { throw ('APP_PIN_MISMATCH (risk register path): ' + $_.Exception.Message) }
  if (-not (Test-Path -LiteralPath $regFull -PathType Leaf)) {
    throw ("APP_PIN_MISMATCH (risk register): '" + $RiskRegisterRel + "' is MISSING from the live app root - the freeze-pinned register must exist => STOP")
  }
  $sha = Get-NeoSha256File $regFull
  if ($sha -cne $RiskRegisterPinSha256) {
    throw ("APP_PIN_MISMATCH (risk register): '" + $RiskRegisterRel + "' re-hashes to " + $sha + " but the freeze risk_register_pin.sha256 is " + $RiskRegisterPinSha256 + " => STOP")
  }
  return $true
}

# Wraps the caller's builder seam with an ALWAYS-ON app-pin preamble. The
# frozen loop's round order (grounded Invoke-NeoLoopConverge: write-ahead
# ledger -> baseline -> dispatch -> BUILDER SEAM -> round checks) means this
# preamble runs BEFORE the builder can mutate the app root in EVERY round
# INCLUDING round 0 and every fix round. A mismatch => a fail-closed throw
# INSIDE the seam, which the FROZEN loop routes as a BUILDER_SEAM_FAILED STOP
# (manifest row + notification); the detail carries the APP_PIN_MISMATCH cause.
# The wrapper preserves the caller seam's contract untouched: same single
# dispatch-info argument in, same return out, transparent on the clean path.
# ---- the per-wrapper WRITE-ONCE seam-config registry (FIX-ROUND-2 / CX-1) ----
# A PUBLIC factory must not depend on single-writer discipline the type system
# does not enforce (the round-1 single mutable slot let the LATEST creation
# re-point EVERY previously returned wrapper - SC-reproduced: wrapper A
# verified B's pins and delegated to B's inner seam). Each wrapper is now
# IMMUTABLY bound at creation to ITS OWN registry entry; writes are WRITE-ONCE
# (an existing key is REFUSED, never latest-wins). Public so the fixtures
# drive the guard directly (the 3.D.6b directly-testable-guards discipline).
function Register-NeoRunAppPinSeamConfig {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)]$Config
  )
  if ([string]::IsNullOrWhiteSpace($Id)) {
    New-NeoBlock "reason_code=APP_PIN_SEAM_CONFIG seam-config registry: Id is blank => REFUSE"
  }
  if ($null -eq $script:NeoRunAppPinRegistry) {
    $script:NeoRunAppPinRegistry = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
  }
  if ($script:NeoRunAppPinRegistry.ContainsKey($Id)) {
    New-NeoBlock "reason_code=APP_PIN_SEAM_CONFIG seam-config registry: entry '$Id' ALREADY EXISTS - the registry is WRITE-ONCE (a wrapper's binding is IMMUTABLE; overwrite refused, never latest-wins)"
  }
  $script:NeoRunAppPinRegistry[$Id] = $Config
  return $true
}

function New-NeoRunAppPinBuilderSeam {
  param(
    [Parameter(Mandatory = $true)]$InnerSeam,
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$AppPinPath,
    [Parameter(Mandatory = $true)][string]$RiskRegisterRel,
    [Parameter(Mandatory = $true)][string]$RiskRegisterPinSha256,
    [Parameter(Mandatory = $true)][string]$DerivedAt
  )
  # FIX-ROUND-2 (CX-1): IMMUTABLE PER-WRAPPER BINDING that also survives a
  # clean process. The returned block is built via [scriptblock]::Create with
  # ONLY the literal per-creation GUID baked in (no paths/values - no quoting
  # hazards): (a) an unbound block executes in the invoking session state - in
  # this dot-sourced (non-module) architecture that is the same script scope
  # where Assert-NeoRunAppPinCurrent lives, so it resolves in a clean process
  # (the fix-round-1 lesson: a GetNewClosure dynamic module cannot); (b) it
  # reads its OWN write-once registry entry by its baked immutable id; (c) a
  # later wrapper creation gets a DIFFERENT id and cannot re-point this one.
  # Binding loss is FAIL-CLOSED: a missing/mismatched registry entry at
  # invocation => a distinct APP_PIN_SEAM_CONFIG throw (the frozen loop routes
  # it BUILDER_SEAM_FAILED) - never a fallback to any other entry, never a
  # silent wrong-config verify.
  $id = [guid]::NewGuid().ToString('N')
  [void](Register-NeoRunAppPinSeamConfig -Id $id -Config @{
    id = $id; inner = $InnerSeam; app = $AppRoot; pin = $AppPinPath
    regRel = $RiskRegisterRel; regSha = $RiskRegisterPinSha256; ts = $DerivedAt
  })
  $text = @'
param($DispatchInfo)
$cfg = $null
if ($null -ne $script:NeoRunAppPinRegistry) { $cfg = $script:NeoRunAppPinRegistry['__NEO_RUN_SEAM_ID__'] }
if ($null -eq $cfg) {
  throw 'APP_PIN_SEAM_CONFIG: app-pin seam registry entry __NEO_RUN_SEAM_ID__ is MISSING at invocation => STOP (fail-closed; the wrapper never falls back to another entry and never verifies a different config silently)'
}
if ([string]$cfg.id -cne '__NEO_RUN_SEAM_ID__') {
  throw ('APP_PIN_SEAM_CONFIG: app-pin seam registry entry __NEO_RUN_SEAM_ID__ carries MISMATCHED binding id ' + [string]$cfg.id + ' => STOP (fail-closed)')
}
[void](Assert-NeoRunAppPinCurrent -AppRoot $cfg.app -AppPinPath $cfg.pin -RiskRegisterRel $cfg.regRel -RiskRegisterPinSha256 $cfg.regSha -DerivedAt $cfg.ts)
return (& $cfg.inner $DispatchInfo)
'@
  return ([scriptblock]::Create($text.Replace('__NEO_RUN_SEAM_ID__', $id)))
}

# =============================================================================
# (4) PREPARE PATH (dispatch 3.A.1): instruct -> the surfaced START gate
# =============================================================================
# freeze -> plan audit -> gate readiness -> gate surface, in EXACTLY that
# order, each via the FROZEN C5 surface. Returns the gate PRESENTATION PACKAGE.
# HARD REQUIREMENTS (fixture-proven): NO slice dispatch, NO attempt-ledger
# write, NO builder-seam invocation on this path (no seam parameter even
# exists here). NO try/catch anywhere on this path: a BLOCKED readiness (incl.
# the frozen CLARITY_GATE_NOT_READY) PROPAGATES to the caller as the BLOCK it
# is - there is NO parameter that surfaces the gate while BLOCKED and no
# wrapper that could swallow the BLOCK into a package or a skip.
function Invoke-NeoRunPrepare {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [Parameter(Mandatory = $true)][string]$InstructionDigestRef,
    # deliberately NOT Mandatory (the C5 freeze validators own the fail-closed
    # refusals; a $null must reach them as policy, never as a binding error):
    $AmbiguityRegister,
    $SlicePlan,
    $RiskRows,
    $Profile,
    $AttestedGapRecords = @(),
    [Parameter(Mandatory = $true)][string]$GovernedRoot,
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$RiskRegisterRel,
    [Parameter(Mandatory = $true)][string]$StampedBy,
    [Parameter(Mandatory = $true)][string]$Timestamp,
    [string]$PlanAuditAttestationPath,
    [string]$PlanAuditCredentialPath,
    [int]$PlanAuditTimeoutSec = 0,
    # fixtures pass a stub invoker seam; $null = the live C4 channel.
    $PlanAuditInvokerSeam,
    # TEST-ONLY seam for the AUTO-mode standing attestation (fixture twins
    # under TEMP); blank = the real engine attestation. Governed callers never
    # pass this.
    [string]$AutonomyAttestationPath,
    [string]$NotifyTestModeDir,
    [switch]$NotifyLiveSend,
    $Index
  )
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  # the run manifest is CALLER-created (START-release Q1): fail-closed read at
  # entry through the frozen reader (missing/invalid/caps-invalid => STOP).
  [void](Read-NeoRunManifest -RunRoot $RunRoot)

  # (a0) AUTONOMY chain validation, prepare ENTRY stage (spec 3B builder note):
  # record parse/schema/run_id/mode + anchored attestation stamp + hash-match +
  # declared-root containment. Record absent => interactive; record present but
  # chain-invalid => the accessor PARKS (one notification, then the
  # RUN_AUTONOMY_PARK BLOCK propagates) - NO START package in EITHER mode.
  [void](Get-NeoRunAutonomyMode -RunRoot $RunRoot -SessionRoot $SessionRoot -Stage 'entry' `
    -AttestationPath $AutonomyAttestationPath -NotifyTestModeDir $NotifyTestModeDir `
    -NotifyLiveSend:$NotifyLiveSend -Index $Index)

  # (a) FREEZE (the frozen C5 freeze point: clarity check, plan/row/registration
  # /profile validation, BOTH pins, tamper-evident record).
  [void](New-NeoClarityFreezeRecord -RunRoot $RunRoot -SessionRoot $SessionRoot `
    -InstructionDigestRef $InstructionDigestRef -AmbiguityRegister $AmbiguityRegister `
    -SlicePlan $SlicePlan -RiskRows $RiskRows -Profile $Profile `
    -AttestedGapRecords $AttestedGapRecords -GovernedRoot $GovernedRoot -AppRoot $AppRoot `
    -RiskRegisterRel $RiskRegisterRel -StampedBy $StampedBy -Timestamp $Timestamp -Index $Index)

  # (b) PLAN AUDIT (the frozen check==use pin-drift gate + the frozen C4
  # adapter over the plan bundle; -InvokerSeam passthrough, $null = live).
  [void](Invoke-NeoClarityPlanAudit -RunRoot $RunRoot -SessionRoot $SessionRoot `
    -StampedBy $StampedBy -Timestamp $Timestamp -AttestationPath $PlanAuditAttestationPath `
    -CredentialPath $PlanAuditCredentialPath -TimeoutSec $PlanAuditTimeoutSec `
    -InvokerSeam $PlanAuditInvokerSeam -Index $Index)

  # (c) GATE READINESS (the frozen FROM-DISK derivation; the mandated order
  # calls it HERE). Its value is NOT branched on: enforcement belongs to the
  # frozen gate below, which RE-DERIVES readiness itself (check==use) and
  # refuses fail-closed (CLARITY_GATE_NOT_READY) unless READY /
  # READY_WITH_DISCLOSURE - branching here could only duplicate or dodge it.
  [void](Get-NeoClarityGateReadiness -RunRoot $RunRoot -SessionRoot $SessionRoot -Index $Index)

  # (c2) AUTONOMY chain validation, FULL stage: the envelope tier assertion
  # over the freeze risk rows + the plan-audit-converged-GO assertion run
  # AFTER the in-prepare plan-audit step (the verdict does not exist earlier);
  # BOTH stages complete BEFORE any START package is emitted.
  $autonomy = Get-NeoRunAutonomyMode -RunRoot $RunRoot -SessionRoot $SessionRoot -Stage 'full' `
    -AttestationPath $AutonomyAttestationPath -NotifyTestModeDir $NotifyTestModeDir `
    -NotifyLiveSend:$NotifyLiveSend -Index $Index

  # (d) GATE SURFACE: returns the presentation package + fires the structural
  # APPROVAL_NEEDED notification (convenience never authority).
  $package = Invoke-NeoClarityStartGate -RunRoot $RunRoot -SessionRoot $SessionRoot `
    -NotifyTestModeDir $NotifyTestModeDir -NotifyLiveSend:$NotifyLiveSend -Index $Index
  # display-only autonomy read site (NF-A7 allowlisted): what Raphael SEES on
  # the surfaced C5/START package. Display NEVER branches engine behavior.
  if ([string]$autonomy.mode -ceq 'auto') {
    $package['autonomy_mode_display'] = ('autonomy mode: AUTO (attested start authority; autonomy_sha256 ' + [string]$autonomy.segment + ')')
  } else {
    $package['autonomy_mode_display'] = 'autonomy mode: INTERACTIVE (per-run human C5; gate_ref segment NONE)'
  }
  return $package
}

# =============================================================================
# (5) END ASSEMBLY (dispatch 3.A.4; PUBLIC so the fixtures drive the
#     path-conditional guards + the reduction contract directly - 3.D.5/6/6b)
# =============================================================================
# PATH-CONDITIONAL per the 2026-07-07b STOP-PATH addendum: a legitimate
# halt-on-stop is NEVER blocked for the slices it legitimately never reached,
# and a STOP is NEVER prevented from reaching the human END gate.
# $SliceEnvelopes = the ORDERED per-slice results the run produced:
#   @( @{ slice_id = <id>; envelope = <Invoke-NeoLoopConverge return> }, ... )
# Every envelope is RE-VALIDATED against the disposition tri-state at THIS
# boundary (check==use); all envelopes are retained VERBATIM in the returned
# END evidence. Keep/iterate/toss stays the human's, OUTSIDE the engine.
function Invoke-NeoRunEndAssembly {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)]$SliceEnvelopes,
    $SliceFinalState = @(),
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [Parameter(Mandatory = $true)][string]$Timestamp,
    [string]$NotifyTestModeDir,
    [switch]$NotifyLiveSend,
    $Index
  )
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')

  # the FROZEN plan (hash-verified latest freeze) is the authority for the
  # planned universe + the pins the END-entry re-verify anchors to.
  $freeze = Get-NeoClarityLatestFreeze -RunRoot $RunRoot -Index $Index
  $planRound = [string](Get-NeoProp $freeze 'plan_round')
  $planned = @()
  foreach ($s in @(Get-NeoClarityList $freeze 'slice_plan')) { $planned += [string](Get-NeoProp $s 'slice_id') }
  $paths = Get-NeoClarityPlanAuditPaths $SessionRoot $planRound
  $appPinSha  = [string](Get-NeoProp (Get-NeoProp $freeze 'app_manifest_pin') 'sha256')
  $regRel     = [string](Get-NeoProp (Get-NeoProp $freeze 'risk_register_pin') 'rel')
  $regSha     = [string](Get-NeoProp (Get-NeoProp $freeze 'risk_register_pin') 'sha256')
  $derivedAt  = [string](Get-NeoProp $freeze 'timestamp_utc')

  # ---- (a) envelope-sequence validation (the reduction contract's boundary) --
  $envList = @($SliceEnvelopes)
  if ($envList.Count -eq 0) {
    New-NeoBlock "reason_code=RUN_DISPOSITION end-assembly: SliceEnvelopes is EMPTY - a run that dispatched nothing has no END to assemble => BLOCK"
  }
  $n = 0
  $shapes = @()
  foreach ($se in $envList) {
    $n++
    if ($null -eq $se -or -not (Test-NeoHasProp $se 'slice_id') -or -not (Test-NeoHasProp $se 'envelope')) {
      New-NeoBlock "reason_code=RUN_DISPOSITION end-assembly: SliceEnvelopes item $n is not a { slice_id; envelope } pair => BLOCK"
    }
    $sid = [string](Get-NeoProp $se 'slice_id')
    if ([string]::IsNullOrWhiteSpace($sid)) {
      New-NeoBlock "reason_code=RUN_DISPOSITION end-assembly: SliceEnvelopes item $n carries a blank slice_id => BLOCK"
    }
    if (-not (@($planned) -ccontains $sid)) {
      New-NeoBlock "reason_code=RUN_DISPOSITION end-assembly: SliceEnvelopes item $n names slice '$sid' which is NOT in the frozen plan [$($planned -join ', ')] => BLOCK (dispatch evidence for an unplanned slice)"
    }
    $d = Assert-NeoRunConvergeDisposition -Envelope (Get-NeoProp $se 'envelope') -Label ("end-assembly envelope for slice '" + $sid + "'")
    $shapes += [string]$d.shape
  }
  # a stopped envelope anywhere but LAST means the run kept dispatching past a
  # surfaced STOP - a sequence no honest run produces => BLOCK.
  for ($i = 0; $i -lt ($shapes.Count - 1); $i++) {
    if ($shapes[$i] -ceq 'stopped') {
      New-NeoBlock "reason_code=RUN_DISPOSITION end-assembly: envelope $($i + 1) of $($shapes.Count) is a STOP but is not the LAST envelope - a legal stopped shape HALTS the run (no further slice dispatch) => BLOCK"
    }
  }
  $isStopPath = ($shapes[$shapes.Count - 1] -ceq 'stopped')
  $pathName = if ($isStopPath) { 'stop' } else { 'converged' }
  $lastSe = $envList[$envList.Count - 1]
  $lastSliceId = [string](Get-NeoProp $lastSe 'slice_id')

  # notify-mode plumbing for the escalation lane + the frozen end gate context.
  $liveSend = [bool]$NotifyLiveSend
  $testDir = [string]$NotifyTestModeDir

  # the RECORDED universe (frozen discovery over the on-disk ledgers) - derived
  # EARLY so caller-supplied envelopes are bound to disk evidence below.
  $recorded = @(Get-NeoLoopRunSliceUniverse -RunRoot $RunRoot -ExpectedRunId $runId)

  # ---- (a2) FIX-ROUND-2 / CX-2: STOP-path envelopes bound to the RECORDED
  # universe. The frozen loop's shared STOP path lands the iteration-manifest
  # row WRITE-AHEAD before ANY stop result surfaces (orch_loop.ps1:395-400 -
  # every routed STOP incl. BUILDER_SEAM_FAILED / NB-2 cap refusal / dispatch
  # stops), so the honest stopping slice is ALWAYS in the discovered universe.
  # A caller-supplied envelope can therefore never introduce a slice the run
  # never recorded, and the gate envelope (the END-gate authority) must be the
  # LAST recorded slice's - the honest stopping slice. Fail-closed both ways;
  # caller-supplied authority at this public boundary is refused. (Enforced on
  # the STOP path; the CONVERGED path's binding stays the frozen full-universe
  # carry in (c) - the converged controls are unchanged by design.)
  if ($isStopPath) {
    # OMISSION direction FIRST (the deeper disk-vs-plan inconsistency; blocks
    # on BOTH paths - here for stop, via the frozen carry for converged):
    # every RECORDED slice must be IN the frozen plan.
    foreach ($r in @($recorded)) {
      if (-not (@($planned) -ccontains [string]$r)) {
        $m = "reason_code=RUN_UNIVERSE_OMISSION end-assembly (STOP path): the run's ledgers record slice '$r' which is NOT in the frozen plan [$($planned -join ', ')] => BLOCK (recorded-but-unplanned blocks on BOTH paths)"
        [void](Invoke-NeoLoopStopNotify -ReasonCode 'END_ASSEMBLY_FAILED' -SliceId $lastSliceId -Round 0 `
          -Detail ('run ' + $runId + ': the omission-direction universe check BLOCKED on the STOP path: recorded-but-unplanned slice ' + $r) `
          -EvidencePath $EvidencePath -TestModeDir:$testDir -LiveSend:$liveSend)
        New-NeoBlock $m
      }
    }
    # RECORDED-membership binding: a caller-supplied envelope can never name a
    # slice the run's ledgers never recorded.
    foreach ($seB in $envList) {
      $sidB = [string](Get-NeoProp $seB 'slice_id')
      if (-not (@($recorded) -ccontains $sidB)) {
        New-NeoBlock "reason_code=RUN_STOP_UNIVERSE end-assembly (STOP path): SliceEnvelopes names slice '$sidB' which the run's ledgers NEVER RECORDED (discovered universe [$($recorded -join ', ')]) => BLOCK (dispatch evidence is bound to the on-disk recorded universe; a crafted envelope for an unrecorded slice can never become END-gate authority)"
      }
    }
    $lastRecorded = [string]@($recorded)[@($recorded).Count - 1]
    if ($lastSliceId -cne $lastRecorded) {
      New-NeoBlock "reason_code=RUN_STOP_UNIVERSE end-assembly (STOP path): the stopping envelope is for slice '$lastSliceId' but the LAST RECORDED slice is '$lastRecorded' => BLOCK (the gate envelope must be the honest stopping slice's - the last slice the run recorded)"
    }
  }

  # ---- (b) END-entry app-pin re-verify, PATH-CONDITIONAL (dispatch 3.A.3) ----
  # CONVERGED path: a mismatch => fail-closed BLOCK (a converged claim must not
  # surface for KEEP on a tampered app root - the post-final-round window).
  # STOP path: the re-verify still RUNS but its result is recorded as a
  # DISCLOSURE and NEVER blocks (the STOP itself is the surfaced event; an
  # app-pin-tamper STOP must flow to DECISION_NEEDED with the tampered state
  # disclosed, not deadlock at its own END entry).
  $appPinDisclosure = $null
  $appPinErr = $null
  try {
    [void](Assert-NeoRunAppPinCurrent -AppRoot $AppRoot -AppPinPath $paths.app_pin_full `
      -RiskRegisterRel $regRel -RiskRegisterPinSha256 $regSha -DerivedAt $derivedAt)
    $appPinDisclosure = @{ checked = $true; result = 'MATCH'; detail = 'END-entry app-pin + risk-register re-verify passed against the live app root' }
  } catch {
    $appPinErr = [string]$_.Exception.Message
    $appPinDisclosure = @{ checked = $true; result = 'MISMATCH'; detail = $appPinErr }
  }
  if ((-not $isStopPath) -and ($null -ne $appPinErr)) {
    # END-assembly failure lane: ONE escalation notification through the frozen
    # choke point (no frozen surface fires for this new check), then the BLOCK
    # propagates - never a swallow, never a human class.
    [void](Invoke-NeoLoopStopNotify -ReasonCode 'END_ASSEMBLY_FAILED' -SliceId $lastSliceId -Round 0 `
      -Detail ('run ' + $runId + ': END-entry app-pin re-verify FAILED on the CONVERGED path: ' + $appPinErr) `
      -EvidencePath $EvidencePath -TestModeDir:$testDir -LiveSend:$liveSend)
    New-NeoBlock "reason_code=RUN_END_APP_PIN end-assembly (CONVERGED path): $appPinErr - a converged claim must not surface for KEEP on a tampered app root => BLOCK"
  }

  # ---- (c) the completeness carry, PATH-CONDITIONAL (dispatch 3.A.4) ---------
  # ($recorded was derived EARLY, before the envelope validation - CX-2.)
  $notReached = @()
  if (-not $isStopPath) {
    # CONVERGED: the FULL frozen-plan universe assert (the frozen carry;
    # requires orch_loop in-process - THIS module sourced it). Its BLOCK routes
    # as an END-assembly failure (escalation lane), never a swallow.
    try {
      [void](Assert-NeoClarityPlanSliceUniverse -RunRoot $RunRoot -ExpectedRunId $runId -Index $Index)
    } catch {
      $m = [string]$_.Exception.Message
      [void](Invoke-NeoLoopStopNotify -ReasonCode 'END_ASSEMBLY_FAILED' -SliceId $lastSliceId -Round 0 `
        -Detail ('run ' + $runId + ': the frozen plan-slice-universe carry BLOCKED on the CONVERGED path: ' + $m) `
        -EvidencePath $EvidencePath -TestModeDir:$testDir -LiveSend:$liveSend)
      throw
    }
    # the reduction contract additionally requires EVERY frozen slice's
    # envelope present + legal converged (asserted below at the reduction).
  } else {
    # STOP path: the full-universe EXTRA check MUST NOT run (it would block the
    # legitimate partial trail). The OMISSION direction already enforced in
    # (a2) - FIRST, before the CX-2 recorded-membership binding.
    # planned-but-never-reached: computed + DISCLOSED (presented, never
    # blocked, never silently dropped).
    foreach ($p in @($planned)) {
      if (-not (@($recorded) -ccontains [string]$p)) { $notReached += [string]$p }
    }
  }

  # ---- (d) the FIXED reduction contract (dispatch 3.A.4) ---------------------
  # STOP path: the STOPPING slice's envelope UNCHANGED (it IS the honest stop
  # evidence) with SliceIds = the RECORDED slice ids. CONVERGED path: EVERY
  # frozen slice's envelope was asserted legal converged (any violation =>
  # refuse fail-closed, no end-gate call - enforced here); the LAST slice's
  # envelope with SliceIds = the FULL frozen plan ids.
  $gateEnvelope = $null
  $gateSliceIds = @()
  if ($isStopPath) {
    $gateEnvelope = Get-NeoProp $lastSe 'envelope'
    $gateSliceIds = @($recorded)
  } else {
    # every FROZEN slice must have exactly one legal converged envelope.
    foreach ($p in @($planned)) {
      $hits = @($envList | Where-Object { [string](Get-NeoProp $_ 'slice_id') -ceq [string]$p })
      if (@($hits).Count -ne 1) {
        New-NeoBlock "reason_code=RUN_DISPOSITION end-assembly (CONVERGED path): frozen slice '$p' has $(@($hits).Count) envelopes (exactly 1 required) => BLOCK (a run may not claim convergence without one legal converged envelope per planned slice)"
      }
      # legal converged shape already asserted in (a); re-assert the direction
      # explicitly at the reduction boundary (check==use).
      $d = Assert-NeoRunConvergeDisposition -Envelope (Get-NeoProp @($hits)[0] 'envelope') -Label ("reduction envelope for slice '" + [string]$p + "'")
      if ([string]$d.shape -cne 'converged') {
        New-NeoBlock "reason_code=RUN_DISPOSITION end-assembly (CONVERGED path): slice '$p' carries a non-converged envelope => BLOCK (refused BEFORE the end gate)"
      }
    }
    $gateEnvelope = Get-NeoProp $lastSe 'envelope'
    $gateSliceIds = @($planned)
  }
  # the ONE envelope passed to the frozen end gate is re-validated at the
  # reduction boundary (check==use - a malformed envelope never passes through).
  [void](Assert-NeoRunConvergeDisposition -Envelope $gateEnvelope -Label 'reduction output envelope')

  # ---- (e) the frozen END gate ------------------------------------------------
  # per-slice trail/final-state validation is the frozen Assert-NeoLoopFinalState's
  # job (it SELF-DERIVES every slice's trail from the on-disk ledgers).
  $ctx = @{
    run_root = $RunRoot; slice_id = $lastSliceId; round = 0; attempt_seq = 1
    evidence_path = $EvidencePath; timestamp_utc = $Timestamp
    notify_test_mode_dir = $testDir; notify_live_send = $liveSend
  }
  $sfs = @()
  if ($null -ne $SliceFinalState) { $sfs = @($SliceFinalState) }
  $gate = Invoke-NeoLoopEndGate -Context $ctx -RunRoot $RunRoot -ExpectedRunId $runId `
    -SliceIds $gateSliceIds -ConvergeEnvelope $gateEnvelope -SliceFinalState $sfs

  # ---- (f) the assembled END evidence ------------------------------------------
  return @{
    end_gate                = $gate
    path                    = $pathName
    run_id                  = $runId
    plan_round              = $planRound
    planned_slice_ids       = @($planned)
    recorded_slice_ids      = @($recorded)
    not_reached             = @($notReached)
    app_pin_end_disclosure  = $appPinDisclosure
    slice_envelopes         = @($envList)
  }
}

# =============================================================================
# (6) EXECUTE PATH (dispatch 3.A.2): post-approval -> slices -> END
# =============================================================================
# A SEPARATE function from prepare - the human decision happens BETWEEN the two
# paths (the engine NEVER infers approval; doctrine D3). Entry, each fail-closed:
#   (1) gate readiness RE-DERIVED FROM DISK (frozen Get-NeoClarityGateReadiness;
#       never a caller-passed readiness/state value),
#   (2) the recorded human START approval (engine-computed exact gate_ref +
#       gate_kind 'human_start_approval'; EXACTLY-ONE raw-count rule),
#   (3) both pin files re-hash to the freeze-recorded pin hashes (post-gate pin
#       drift => refuse; the C5 plan-audit drift gate precedent at execute entry).
# Then per slice FROM THE FROZEN PLAN (plan order, STRICTLY SERIAL), every
# converge input assembled FROM THE FREEZE (consumed, never authored, never
# widened); the three seams are CALLER-SUPPLIED passthroughs (never embedded,
# never read into any authority field - the frozen loop already discards seam
# returns); the builder seam is wrapped with the ALWAYS-ON app-pin preamble.
#
# NOTE (grounded deviation, disclosed): the freeze record does NOT persist the
# router-profile OBJECT (only its validation products: attestation_records +
# the pins; the clarity_freeze_record schema is FROZEN). -RouterProfile is
# therefore CALLER-SUPPLIED here; the frozen rederive's mandatory governed-
# token union (NF-4) applies regardless of its content, and the frozen RISK
# ROWS from the freeze stay the tier authority.
function Invoke-NeoRunExecute {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [Parameter(Mandatory = $true)][string]$GovernedRoot,
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$ApprovalLedgerPath,
    [Parameter(Mandatory = $true)]$RouterProfile,
    [Parameter(Mandatory = $true)][string]$MasterIdentity,
    [Parameter(Mandatory = $true)][string]$BuilderIdentity,
    # per-slice builder-facing dispatch text (goal / allowlist_items / test_plan
    # / stop_conditions / proposed_edits + optional declared_surfaces /
    # denied_paths / proposed_fix_targets), keyed by slice_id. The FREEZE is
    # the authority for scope + risk; these fields may not contradict it (the
    # frozen loop's gates enforce that on the actual diff).
    [Parameter(Mandatory = $true)]$SliceDispatch,
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [Parameter(Mandatory = $true)][string]$Timestamp,
    $SliceFinalState = @(),
    # TEST-ONLY seam for the AUTO-mode standing attestation (fixture twins
    # under TEMP); blank = the real engine attestation.
    [string]$AutonomyAttestationPath,
    [string]$NotifyTestModeDir,
    [switch]$NotifyLiveSend,
    # the three seams: caller-supplied passthroughs, deliberately untyped (the
    # frozen loop validates them at use; null/malformed => routed fail-closed STOP).
    $BuilderSeam,
    $AuditProvider,
    $ExternalProvider,
    $Index
  )
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  # frozen fail-closed manifest read (missing/unparseable/caps-invalid => STOP;
  # caps are REQUIRED config - no default caps exist anywhere in this module).
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')

  # ---- entry (0): the AUTONOMY chain re-validated in FULL from disk (spec 3B:
  # prepare AND execute; record absent => interactive, segment NONE; record
  # present but chain-invalid => PARK + NOTIFY inside the accessor, BLOCK
  # propagates - an invalid chain can never reach the pairing check with a
  # legitimate human answer stranded behind it) -------------------------------
  $autonomy = Get-NeoRunAutonomyMode -RunRoot $RunRoot -SessionRoot $SessionRoot -Stage 'full' `
    -AttestationPath $AutonomyAttestationPath -NotifyTestModeDir $NotifyTestModeDir `
    -NotifyLiveSend:$NotifyLiveSend -Index $Index
  $autonomyMode = [string]$autonomy.mode
  $autonomySegment = [string]$autonomy.segment

  # ---- entry (1): gate readiness re-derived FROM DISK (check==use) -----------
  $readiness = Get-NeoClarityGateReadiness -RunRoot $RunRoot -SessionRoot $SessionRoot -Index $Index
  $state = [string]$readiness.state
  if (($state -cne 'READY') -and ($state -cne 'READY_WITH_DISCLOSURE')) {
    New-NeoBlock "reason_code=RUN_EXECUTE_NOT_READY execute entry: gate readiness re-derived FROM DISK is '$state' (reason: $([string]$readiness.reason)) => REFUSE (the execute path is unreachable while the gate is not surfaceable; a caller-passed readiness is never accepted)"
  }
  $bundleDiffHash = [string]$readiness.bundle_diff_hash

  # ---- the frozen plan (hash-verified) + check==use across the two readers ---
  $freeze = Get-NeoClarityLatestFreeze -RunRoot $RunRoot -Index $Index
  $planRound = [string](Get-NeoProp $freeze 'plan_round')
  if ($planRound -cne [string]$readiness.plan_round) {
    New-NeoBlock "reason_code=RUN_EXECUTE_NOT_READY execute entry: the latest freeze plan_round '$planRound' does not match the readiness derivation's plan_round '$([string]$readiness.plan_round)' => REFUSE (check==use)"
  }
  $freezeSha = [string](Get-NeoProp $freeze 'record_sha256')

  # ---- entry (2): the recorded START approval (human per-run C5 approval on
  # segment NONE; the engine-validated attested entry on a hash-bearing
  # segment - mode<->kind pairing enforced in the reader, NF-A10) --------------
  $expectedRef = Get-NeoRunStartGateRef -RunId $runId -PlanRound $planRound `
    -FreezeRecordSha256 $freezeSha -BundleDiffHash $bundleDiffHash -AutonomySegment $autonomySegment
  $approval = Read-NeoRunStartApproval -LedgerPath $ApprovalLedgerPath -ExpectedGateRef $expectedRef -AutonomySegment $autonomySegment -Index $Index

  # ---- entry (3): post-gate pin drift (check==use at execute entry) ----------
  $paths = Get-NeoClarityPlanAuditPaths $SessionRoot $planRound
  $pinChecks = @(
    @('gov_manifest_pin', [string]$paths.gov_pin_full),
    @('app_manifest_pin', [string]$paths.app_pin_full))
  foreach ($pc in $pinChecks) {
    $pinName = [string]$pc[0]; $pinFull = [string]$pc[1]
    $want = [string](Get-NeoProp (Get-NeoProp $freeze $pinName) 'sha256')
    $got = ''
    try { $got = Get-NeoSha256File $pinFull }
    catch {
      New-NeoBlock "reason_code=RUN_PIN_DRIFT execute entry: pin file for '$pinName' unreadable at '$pinFull' ($($_.Exception.Message)) => REFUSE (fail-closed)"
    }
    if ($got -cne $want) {
      New-NeoBlock "reason_code=RUN_PIN_DRIFT execute entry: '$pinName' file at '$pinFull' re-hashes to $got but the freeze recorded $want => REFUSE (post-gate pin drift; the plan must be revised and re-gated)"
    }
  }

  # ---- per-slice dispatch-field validation (fail-closed, up front) ------------
  $planned = @()
  foreach ($s in @(Get-NeoClarityList $freeze 'slice_plan')) { $planned += [string](Get-NeoProp $s 'slice_id') }
  if ($null -eq $SliceDispatch) {
    New-NeoBlock "reason_code=RUN_SLICE_DISPATCH execute: SliceDispatch is null - every planned slice requires its builder-facing dispatch fields => REFUSE"
  }
  foreach ($k in @(Get-NeoPropNames $SliceDispatch)) {
    if (-not (@($planned) -ccontains [string]$k)) {
      New-NeoBlock "reason_code=RUN_SLICE_DISPATCH execute: SliceDispatch names slice '$k' which is NOT in the frozen plan [$($planned -join ', ')] (case-exact) => REFUSE (dispatch text for an unplanned slice)"
    }
  }
  foreach ($p in @($planned)) {
    $hit = $false
    foreach ($k in @(Get-NeoPropNames $SliceDispatch)) { if ([string]$k -ceq [string]$p) { $hit = $true } }
    if (-not $hit) {
      New-NeoBlock "reason_code=RUN_SLICE_DISPATCH execute: frozen slice '$p' has NO SliceDispatch entry => REFUSE (fail-closed; the run never invents builder-facing text)"
    }
    $d = Get-NeoProp $SliceDispatch $p
    foreach ($f in @('goal', 'allowlist_items', 'test_plan', 'stop_conditions', 'proposed_edits')) {
      if (-not (Test-NeoHasProp $d $f)) {
        New-NeoBlock "reason_code=RUN_SLICE_DISPATCH execute: SliceDispatch for slice '$p' is missing required field '$f' => REFUSE"
      }
    }
  }

  # ---- the ALWAYS-ON app-pin builder-seam wrap (dispatch 3.A.3) ---------------
  # Structurally always-on for the execute path: no parameter can omit it. A
  # null/non-scriptblock caller seam is passed through UNWRAPPED so it still
  # dies in the FROZEN loop's own pre-ledger fail-closed seam guard (wrapping a
  # null would hide it from that guard); a null seam can never run a builder,
  # so no app mutation is reachable without the preamble.
  $regRel = [string](Get-NeoProp (Get-NeoProp $freeze 'risk_register_pin') 'rel')
  $regSha = [string](Get-NeoProp (Get-NeoProp $freeze 'risk_register_pin') 'sha256')
  $derivedAt = [string](Get-NeoProp $freeze 'timestamp_utc')
  $seamToUse = $BuilderSeam
  if ($BuilderSeam -is [scriptblock]) {
    $seamToUse = New-NeoRunAppPinBuilderSeam -InnerSeam $BuilderSeam -AppRoot $AppRoot `
      -AppPinPath ([string]$paths.app_pin_full) -RiskRegisterRel $regRel `
      -RiskRegisterPinSha256 $regSha -DerivedAt $derivedAt
  }

  # ---- the slice loop: FROM THE FROZEN PLAN, plan order, STRICTLY SERIAL ------
  $liveSend = [bool]$NotifyLiveSend
  $testDir = [string]$NotifyTestModeDir
  $riskRows = @(Get-NeoClarityList $freeze 'risk_rows')
  $envelopes = @()
  foreach ($s in @(Get-NeoClarityList $freeze 'slice_plan')) {
    $sid = [string](Get-NeoProp $s 'slice_id')
    $approvedPaths = @()
    foreach ($p in @(Get-NeoClarityList $s 'approved_paths')) { $approvedPaths += [string]$p }
    $protectedPaths = @()
    foreach ($p in @(Get-NeoClarityList $s 'protected_paths')) { $protectedPaths += [string]$p }
    # the slice's risk row resolved through the frozen boundary-to-row mapping
    # rule (risk_row_ref -ceq row_id, exactly one hit - re-asserted here,
    # check==use with the freeze-time mapping).
    $rowRef = [string](Get-NeoProp $s 'risk_row_ref')
    $rowHits = @($riskRows | Where-Object { [string](Get-NeoProp $_ 'row_id') -ceq $rowRef })
    if (@($rowHits).Count -ne 1) {
      New-NeoBlock "reason_code=RUN_SLICE_DISPATCH execute: slice '$sid' risk_row_ref '$rowRef' resolves $(@($rowHits).Count) frozen risk rows (exactly 1 required) => REFUSE (fail-closed re-check of the frozen mapping)"
    }
    $row = @($rowHits)[0]
    $riskClass = [string](Get-NeoProp $row 'risk_class')
    $d = Get-NeoProp $SliceDispatch $sid

    $ctx = @{
      run_root = $RunRoot; slice_id = $sid; round = 0; attempt_seq = 1
      evidence_path = $EvidencePath; timestamp_utc = $Timestamp
      notify_test_mode_dir = $testDir; notify_live_send = $liveSend
    }
    $cargs = @{
      Context = $ctx; RepoRoot = $AppRoot
      ApprovedPaths = $approvedPaths; ProtectedPaths = $protectedPaths
      PinnedGovManifestPath = [string]$paths.gov_pin_full; GovernedRoot = $GovernedRoot
      DerivedAt = $derivedAt; RouterProfile = $RouterProfile; RiskRow = $row
      MasterIdentity = $MasterIdentity; BuilderIdentity = $BuilderIdentity; Index = $Index
      Goal = [string](Get-NeoProp $d 'goal'); RiskClass = $riskClass
      AllowlistItems = (Get-NeoProp $d 'allowlist_items')
      TestPlan = @(Get-NeoProp $d 'test_plan'); StopConditions = @(Get-NeoProp $d 'stop_conditions')
      ProposedEdits = @(Get-NeoProp $d 'proposed_edits')
      BuilderSeam = $seamToUse; AuditProvider = $AuditProvider; ExternalProvider = $ExternalProvider
    }
    if (Test-NeoHasProp $d 'declared_surfaces')    { $cargs['DeclaredSurfaces'] = @(Get-NeoProp $d 'declared_surfaces') }
    if (Test-NeoHasProp $d 'denied_paths')         { $cargs['DeniedPaths'] = @(Get-NeoProp $d 'denied_paths') }
    if (Test-NeoHasProp $d 'proposed_fix_targets') { $cargs['ProposedFixTargets'] = @(Get-NeoProp $d 'proposed_fix_targets') }

    $env = Invoke-NeoLoopConverge @cargs

    # slice-transition guard (fail-closed tri-state at THIS boundary too;
    # check==use with the frozen end gate's internal XOR).
    $disp = Assert-NeoRunConvergeDisposition -Envelope $env -Label ("slice-transition envelope for slice '" + $sid + "'")
    $envelopes += ,@{ slice_id = $sid; envelope = $env }
    if ([string]$disp.shape -ceq 'stopped') {
      # the legal stopped shape HALTS the run: NO slice N+1 dispatch; END
      # assembly proceeds on the partial trail (the STOP-PATH addendum).
      break
    }
  }

  # ---- END assembly + the END gate, MODE-CONDITIONALLY WRAPPED (spec sec 4;
  # cold LOW-4/LOW-5): INTERACTIVE re-throws UNCHANGED (byte-identical manual
  # behavior - the NF-A7 runtime zero-delta); ONLY a valid AUTO chain catches
  # + parks + notifies (the propagated-throw lane: RUN_DISPOSITION /
  # RUN_UNIVERSE_OMISSION and every other END throw make auto-keep unreachable).
  $endResult = $null
  $endThrowDetail = $null
  try {
    $endResult = Invoke-NeoRunEndAssembly -RunRoot $RunRoot -SessionRoot $SessionRoot -AppRoot $AppRoot `
      -SliceEnvelopes $envelopes -SliceFinalState $SliceFinalState -EvidencePath $EvidencePath `
      -Timestamp $Timestamp -NotifyTestModeDir $testDir -NotifyLiveSend:$NotifyLiveSend -Index $Index
  } catch {
    if ($autonomyMode -cne 'auto') { throw }
    $endThrowDetail = [string]$_.Exception.Message
  }
  if ($null -ne $endThrowDetail) {
    $cap = $endThrowDetail
    if ($cap.Length -gt 300) { $cap = $cap.Substring(0, 300) }
    $st = Send-NeoRunAutoNotice -GateType 'ESCALATION_STOP' -SliceId $script:NeoClarityPlanSliceId `
      -SummaryLines @(
        'AUTO run PARKED at END: the END call THREW (auto-keep unreachable on a throw)',
        ('run ' + $runId),
        ('detail: ' + $cap),
        'human decision required (park + notify, exactly as today)') `
      -EvidencePath $EvidencePath -TestModeDir $testDir -LiveSend:$NotifyLiveSend
    return @{
      run_id = $runId
      parked = $true
      auto   = @{ mode = 'auto'; decision = 'parked'; park_class = 'END_THROW'
                  park_detail = $endThrowDetail; notify = $st }
      end_gate = $null
    }
  }

  # the approval binding rides the returned evidence (read-only echo; never an
  # authority field - the gate ledger stays the record).
  $endResult['start_approval'] = @{
    gate_ref = $expectedRef
    authorized_by = [string](Get-NeoProp $approval 'authorized_by')
    recorded_at = [string](Get-NeoProp $approval 'recorded_at')
  }

  if ($autonomyMode -cne 'auto') {
    # INTERACTIVE END decision site: the ONLY added behavior is the post-gate
    # tamper probe (NF-A9, flip direction interactive->declared): an autonomy
    # record APPEARING after the START gate mismatches the tuple-bound segment
    # NONE => ESCALATION park + notify, NEVER a silent mode adoption. With no
    # record present (every legitimate manual run) the return below is
    # byte-identical to the pre-AUTO surface.
    $probeTamper = $null
    try {
      $probe = Get-NeoRunAutonomyMode -RunRoot $RunRoot -SessionRoot $SessionRoot -Stage 'entry' `
        -AttestationPath $AutonomyAttestationPath -NotifyTestModeDir $testDir -NotifyLiveSend:$NotifyLiveSend -Index $Index
      if ([string]$probe.mode -cne 'interactive') {
        $probeTamper = 'an autonomy record APPEARED after the START gate (the approved tuple is bound to segment NONE)'
      }
    } catch {
      $probeTamper = ('post-gate autonomy state is INVALID (a record appeared and its chain refuses): ' + [string]$_.Exception.Message)
    }
    if ($null -ne $probeTamper) {
      $capP = $probeTamper
      if ($capP.Length -gt 300) { $capP = $capP.Substring(0, 300) }
      $st = Send-NeoRunAutoNotice -GateType 'ESCALATION_STOP' -SliceId $script:NeoClarityPlanSliceId `
        -SummaryLines @(
          'POST-GATE AUTONOMY TAMPER (interactive run): END recompute mismatch => ESCALATION park',
          ('run ' + $runId),
          ('detail: ' + $capP),
          'tamper is an evidence problem, not a mode question - never a silent mode adoption') `
        -EvidencePath $EvidencePath -TestModeDir $testDir -LiveSend:$NotifyLiveSend
      New-NeoBlock ("reason_code=RUN_AUTONOMY_TAMPER END decision site (interactive): " + $probeTamper + " => ESCALATION park + notify (notify sent=" + [string]$st.sent + "); never auto-keep, never a silent mode downgrade/adoption")
    }
    return $endResult
  }

  # ---- AUTO END decision site (spec sec 4 (a)-(d)): everything re-derived
  # FROM DISK at decision time (the S1-FIX F4 caller-trusted-value class is
  # what this pins against; the bound hash is never carried as authority) ------
  $endChainParkDetail = $null
  $freshFreeze = $null
  $freshSegment = ''
  try {
    $endAuto = Get-NeoRunAutonomyMode -RunRoot $RunRoot -SessionRoot $SessionRoot -Stage 'full' `
      -AttestationPath $AutonomyAttestationPath -NotifyTestModeDir $testDir -NotifyLiveSend:$NotifyLiveSend -Index $Index
    if ([string]$endAuto.mode -cne 'auto') {
      $endChainParkDetail = 'the autonomy record is GONE at the END decision site (post-gate flip auto->absent; never a silent interactive downgrade)'
    } else {
      $freshSegment = [string]$endAuto.segment
      $freshFreeze = Get-NeoClarityLatestFreeze -RunRoot $RunRoot -Index $Index
      $freshReadiness = Get-NeoClarityGateReadiness -RunRoot $RunRoot -SessionRoot $SessionRoot -Index $Index
      if ([string]$freshReadiness.state -cne 'READY') {
        $endChainParkDetail = ('END-site readiness recompute is not READY (state ' + [string]$freshReadiness.state + ')')
      } else {
        # recompute the expected tuple from the on-disk artifacts and require
        # the recorded attested entry to match it: a flipped record file finds
        # no matching bound entry => park (NF-A9).
        $freshRef = Get-NeoRunStartGateRef -RunId $runId -PlanRound ([string](Get-NeoProp $freshFreeze 'plan_round')) `
          -FreezeRecordSha256 ([string](Get-NeoProp $freshFreeze 'record_sha256')) `
          -BundleDiffHash ([string]$freshReadiness.bundle_diff_hash) -AutonomySegment $freshSegment
        [void](Read-NeoRunStartApproval -LedgerPath $ApprovalLedgerPath -ExpectedGateRef $freshRef -AutonomySegment $freshSegment -Index $Index)
        if ($freshSegment -cne $autonomySegment) {
          # belt-and-braces beyond the ledger lookup: the END-site re-hash must
          # also equal the execute-entry tuple segment (a consistently rewritten
          # ledger+record pair still differs from the entry-validated state).
          $endChainParkDetail = ('END-site re-hash ' + $freshSegment + ' does not match the entry-validated tuple segment (post-gate flip)')
        }
      }
    }
  } catch {
    $endChainParkDetail = ('END-site chain recompute FAILED: ' + [string]$_.Exception.Message)
  }
  $gate = $endResult.end_gate
  $autoParkClass = $null
  $autoParkDetail = $null
  if ($null -ne $endChainParkDetail) {
    $autoParkClass = 'RUN_AUTONOMY_TAMPER'
    $autoParkDetail = $endChainParkDetail
  } elseif (-not [bool](Get-NeoProp $gate 'assembly_ok')) {
    # (b) fails: END assembly not clean => the ESCALATION lane parked.
    $autoParkClass = 'END_ASSEMBLY_FAILED'
    $autoParkDetail = ('END assembly is NOT clean (assembly_fail_code=' + [string](Get-NeoProp $gate 'assembly_fail_code') + '): ' + [string](Get-NeoProp $gate 'assembly_fail_detail'))
  } elseif ((-not [bool](Get-NeoProp $gate 'converged')) -or ([bool](Get-NeoProp $gate 'stop_present')) -or ([string]$endResult.path -cne 'converged')) {
    # (c) fails: any surfaced STOP / non-converged disposition (every breaker
    # trip, enforcement BLOCK, and classifier ambiguity routes here as a
    # stopped envelope) => park, never auto-keep/iterate/toss.
    $autoParkClass = 'RUN_NOT_CONVERGED'
    $autoParkDetail = ('the run is not a clean converged GO (path=' + [string]$endResult.path + ', converged=' + [string](Get-NeoProp $gate 'converged') + ', stop_present=' + [string](Get-NeoProp $gate 'stop_present') + ')')
  } elseif ([string](Get-NeoProp $gate 'human_class') -cne 'SESSION_END') {
    # (d) fails: (c) and (d) are deliberately redundant - defense in depth.
    $autoParkClass = 'RUN_HUMAN_CLASS'
    $autoParkDetail = ("END human class '" + [string](Get-NeoProp $gate 'human_class') + "' is not SESSION_END")
  }
  if ($null -ne $autoParkClass) {
    $capA = [string]$autoParkDetail
    if ($capA.Length -gt 300) { $capA = $capA.Substring(0, 300) }
    $st = Send-NeoRunAutoNotice -GateType 'ESCALATION_STOP' -SliceId $script:NeoClarityPlanSliceId `
      -SummaryLines @(
        ('AUTO run PARKED at the END decision site (' + $autoParkClass + ') - NEVER auto-keep on a non-clean run'),
        ('run ' + $runId),
        ('detail: ' + $capA),
        'human decision required; auto-iterate/auto-toss do not exist (iteration = a NEW authorized run)') `
      -EvidencePath $EvidencePath -TestModeDir $testDir -LiveSend:$NotifyLiveSend
    $endResult['parked'] = $true
    $endResult['auto'] = @{ mode = 'auto'; decision = 'parked'; park_class = $autoParkClass
                            park_detail = $autoParkDetail; notify = $st }
    return $endResult
  }
  # ---- AUTO-KEEP: sec-4 (a)-(d) ALL hold. Notify FIRST (a send failure never
  # blocks the keep - it is RECORDED), then the RunRoot-only evidence record. --
  $freshFreezeSha = [string](Get-NeoProp $freshFreeze 'record_sha256')
  $keepStatus = Send-NeoRunAutoNotice -GateType 'SESSION_END' -SliceId $script:NeoClarityPlanSliceId `
    -SummaryLines @(
      ('AUTO-KEPT (engine-decided); review trail at ' + $EvidencePath),
      ('run ' + $runId + '; freeze ' + $freshFreezeSha + '; autonomy_sha256 ' + $freshSegment),
      'human review: PENDING (MANDATORY async; engine_auto_keep NEVER substitutes a human keep downstream)') `
    -EvidencePath $EvidencePath -TestModeDir $testDir -LiveSend:$NotifyLiveSend
  $notifyOutcome = 'NOT-SENT'
  if ([bool]$keepStatus.sent) { $notifyOutcome = 'SENT' }
  elseif ([bool]$keepStatus.deduped) { $notifyOutcome = 'DEDUPED' }
  else { $notifyOutcome = ('NOT-SENT: ' + [string]$keepStatus.reason) }
  $keepPath = $null
  try {
    $keepPath = Write-NeoRunEngineAutoKeep -RunRoot $RunRoot -RunId $runId `
      -FreezeRecordSha256 $freshFreezeSha -AutonomySha256 $freshSegment `
      -TrailRef $EvidencePath -RecordedAt $Timestamp -NotifyOutcome $notifyOutcome -Index $Index
  } catch {
    # a keep without its honest evidence record is not a keep => park.
    $recFail = [string]$_.Exception.Message
    $capR = $recFail
    if ($capR.Length -gt 300) { $capR = $capR.Substring(0, 300) }
    $st2 = Send-NeoRunAutoNotice -GateType 'ESCALATION_STOP' -SliceId $script:NeoClarityPlanSliceId `
      -SummaryLines @(
        'AUTO run PARKED: the engine_auto_keep evidence record FAILED to write',
        ('run ' + $runId),
        ('detail: ' + $capR),
        'human decision required') `
      -EvidencePath $EvidencePath -TestModeDir $testDir -LiveSend:$NotifyLiveSend
    $endResult['parked'] = $true
    $endResult['auto'] = @{ mode = 'auto'; decision = 'parked'; park_class = 'AUTO_KEEP_RECORD_FAILED'
                            park_detail = $recFail; notify = $st2 }
    return $endResult
  }
  $endResult['parked'] = $false
  $endResult['auto'] = @{ mode = 'auto'; decision = 'auto_keep'; record_path = $keepPath
                          autonomy_sha256 = $freshSegment; freeze_record_sha256 = $freshFreezeSha
                          notify_outcome = $notifyOutcome; human_review = 'pending' }
  return $endResult
}
