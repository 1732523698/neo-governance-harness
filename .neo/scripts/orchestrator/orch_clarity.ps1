# orch_clarity.ps1 - NEO 4.0-P4-AUTONOMY C5: CLARITY-CHECK GATE + FREEZE POINT +
# PRE-START PLAN AUDIT (spec v3.1 sec-4 C5 lines 143-157 incl. the 2026-07-07
# PRE-START PLAN-AUDIT addendum; sec-4 C6 coupling; sec-5 instruct->CLARITY CHECK;
# sec-6 invariant 2; sec-0 NB-4 tamper-EVIDENT stamps). ASCII-only.
#
# THE ONE HUMAN GATE at the head of an autonomous run:
#   (a) CLARITY CHECK  - blocking-ambiguity classification, fail-closed;
#   (b) FREEZE POINT   - slice plan + boundary-to-risk-row mapping + risk rows +
#       C1a judging-class registrations + the C1b governance-manifest pin + the
#       app-side judging pins + the risk-register hash pin, persisted as a
#       tamper-EVIDENT record (record_sha256, NB-4);
#   (c) PRE-START PLAN AUDIT (2026-07-07 addendum AS CODE) - the C4 channel runs
#       over the derived plan artifacts BEFORE the human START gate can surface;
#       the gate CANNOT surface without either an archived current-round plan
#       verdict or an archived current-round unavailability disclosure.
#
# AUTHORITY DISCIPLINE (the forgeable-authority lesson, 10+ external saves):
#   - gate-readiness derives FROM DISK ONLY via the FROZEN Get-NeoExternalLaneStatus
#     (check==use; the adapter's return value is NEVER authority);
#   - the expected plan-bundle hash is RE-HASHED from the ON-DISK bundle at its
#     deterministic per-plan-round path (START release note R-1) - NEVER a stored
#     hash field;
#   - the unavailability-disclosure trigger is EXHAUSTIVE: ANY lane NOT in
#     {GO, NO_GO} - never an enumerated two-value check (START release note R-2);
#   - a notification is CONVENIENCE, never authority (DEF-P8); a send failure
#     never blocks a gate.
#
# REUSE (READ-ONLY, no frozen edit) - four engine chains + the notify convenience
# module (the orch_loop.ps1:60 sourcing precedent). All modules are idempotent
# re-sourceable (functions + script vars only; no load guards exist by grounded
# convention); the chains converge at orch_io -> {orch_schema, orch_class} +
# _neo_root:
#   orch_external.ps1    -> Invoke-NeoExternalAudit / Get-NeoExternalLaneStatus /
#                           ConvertTo-NeoExternalAsciiLine (-> orch_supervisor ->
#                           _neo_root + orch_io -> orch_schema/orch_class)
#   orch_govmanifest.ps1 -> Build-NeoGovManifest / Assert-NeoGovManifestMandatoryMembers /
#                           Assert-NeoGovManifestReverify / Get-NeoGovLiveClassMap
#                           (-> orch_diff -> orch_io + _neo_root)
#   orch_engine.ps1      -> New-NeoAuditBundle (the plan AUDIT_BUNDLE)
#   orch_router.ps1      -> Resolve-NeoRouterProfile / Assert-NeoAutonomousRowEligible
#                           (-> orch_enforce: the wrapped tier oracle)
# orch_loop.ps1 is DELIBERATELY NOT dot-sourced here: integrate wires the loop
# layer to THIS module, and with no load guards a mutual dot-source would recurse.
# Assert-NeoClarityPlanSliceUniverse therefore requires the frozen loop function to
# be present in the session and BLOCKs fail-closed when it is not.
$script:NeoClarityDir = $PSScriptRoot
. "$script:NeoClarityDir\orch_external.ps1"
. "$script:NeoClarityDir\orch_govmanifest.ps1"
. "$script:NeoClarityDir\orch_engine.ps1"
. "$script:NeoClarityDir\orch_router.ps1"
. "$script:NeoClarityDir\..\notify\notify_raphael.ps1"

# ---- constants --------------------------------------------------------------
# The FIXED plan pseudo-slice id for the pre-START plan audit's external calls.
# MUST NOT be '__run__' (orch_supervisor.ps1:389, the run-scope reserved id) and
# MUST NOT -ceq-collide with any real slice id - the freeze validation refuses
# both at the source, so this id can never appear in the loop's slice universe
# (which reads the iteration manifest + attempt ledger only).
$script:NeoClarityPlanSliceId = '__plan__'
# R1-1: a THROWN adapter failure (the adapter itself throwing, e.g. a
# caller-contract NEO-BLOCK) is captured fail-hard into this distinct structured
# stage value; every NON-thrown refusal takes the adapter's returned stage/reason
# VERBATIM (grounded vocabulary: ATTESTATION CREDENTIAL BUNDLE MANIFEST
# LEDGER_FAILURE SUBCAP RUNCAP PACKET CLI_ERROR PARSE DERIVED).
$script:NeoClarityAdapterThrewStage = 'ADAPTER_THREW'
# R1-2: the fixed ratified-policy citation every directional-disposition record
# carries as its authority_basis (the record is DISCLOSURE, not approval; the
# human START gate it rides to remains the sole plan authority).
$script:NeoClarityDispositionAuthorityBasis = 'ADDENDUM 2026-07-07 PRE-START PLAN AUDIT (Raphael-recorded): directional-only conservatism disagreements are disclosed at the gate and never auto-block; the human START gate is the sole plan authority.'
# Run-state ledger leaves (S1 discipline: append-only JSONL, fail-closed reads,
# never treat-as-empty on unreadable).
$script:NeoClarityFreezeLedgerLeaf = 'clarity_freeze_ledger.jsonl'
$script:NeoClarityGateLedgerLeaf   = 'clarity_gate_ledger.jsonl'
# Deterministic per-plan-round artifact leaves under <SessionRoot>/plan_audit/
# (R-1: gate readiness re-hashes the bundle at THIS path; forward-slash SafeRel).
$script:NeoClarityPlanAuditDirLeaf = 'plan_audit'
# Ambiguity classification vocabulary (ordinal, case-exact; anything else is an
# unclassifiable ambiguity => STOP).
$script:NeoClarityAmbiguityClasses = @('blocking_risk_tier', 'blocking_state_surfaces', 'blocking_governance_controls', 'documented_default')
$script:NeoClarityBlockingClasses  = @('blocking_risk_tier', 'blocking_state_surfaces', 'blocking_governance_controls')
$script:NeoClarityGateRecordKinds  = @('unavailability_disclosure', 'directional_disposition')
$script:NeoClarityDateOnlyPattern  = '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
$script:NeoClarityPlanRoundPattern = '^[1-9][0-9]*$'
$script:NeoClaritySha256Pattern    = '^[0-9a-f]{64}$'

# ---- small shared validators --------------------------------------------------
function Assert-NeoClarityNonBlankString($v, [string]$What, [string]$Where) {
  if (-not ($v -is [string]) -or [string]::IsNullOrWhiteSpace($v)) {
    New-NeoBlock "reason_code=CLARITY_SHAPE ${Where}: '$What' missing/blank/non-string => STOP (fail-closed)"
  }
}
function Test-NeoClarityIsList($v) {
  if ($null -eq $v) { return $false }
  if ($v -is [string]) { return $false }
  return ($v -is [System.Collections.IList])
}
# Flat-list accessor for INSTANCE-DATA arrays: Get-NeoVal is SHAPE-PRESERVING
# (Write-Output -NoEnumerate), so an INLINE @(Get-NeoVal ...) nests the array.
# This helper follows the engine's assign-first convention and returns a plain
# enumeration, so @(Get-NeoClarityList ...) is always the FLAT member list
# (null/absent => empty, single => 1, n => n).
function Get-NeoClarityList($o, [string]$name) {
  $v = Get-NeoVal $o $name
  return @($v)
}
function Assert-NeoClarityPlanRound([string]$PlanRound, [string]$Where) {
  if ([string]::IsNullOrWhiteSpace($PlanRound) -or ($PlanRound -cnotmatch $script:NeoClarityPlanRoundPattern)) {
    New-NeoBlock "reason_code=CLARITY_SHAPE ${Where}: plan_round '$PlanRound' is not a positive-integer string ($($script:NeoClarityPlanRoundPattern)) => STOP"
  }
}
function Get-NeoClarityPlanAuditPaths([string]$SessionRoot, [string]$PlanRound) {
  # Deterministic per-plan-round artifact paths (R-1). All rels are SafeRel +
  # contained under SessionRoot (validated through the frozen helpers at use).
  $bundleRel = ($script:NeoClarityPlanAuditDirLeaf + '/AUDIT_BUNDLE_round_' + $PlanRound + '.json')
  $freezeRel = ($script:NeoClarityPlanAuditDirLeaf + '/freeze_record_round_' + $PlanRound + '.json')
  $govPinRel = ($script:NeoClarityPlanAuditDirLeaf + '/gov_manifest_pin_round_' + $PlanRound + '.json')
  $appPinRel = ($script:NeoClarityPlanAuditDirLeaf + '/app_manifest_pin_round_' + $PlanRound + '.json')
  foreach ($r in @($bundleRel, $freezeRel, $govPinRel, $appPinRel)) { Assert-NeoSafeRel $r }
  return @{
    dir_full    = (Assert-NeoContained $SessionRoot $script:NeoClarityPlanAuditDirLeaf)
    bundle_rel  = $bundleRel; bundle_full = (Assert-NeoContained $SessionRoot $bundleRel)
    freeze_rel  = $freezeRel; freeze_full = (Assert-NeoContained $SessionRoot $freezeRel)
    gov_pin_rel = $govPinRel; gov_pin_full = (Assert-NeoContained $SessionRoot $govPinRel)
    app_pin_rel = $appPinRel; app_pin_full = (Assert-NeoContained $SessionRoot $appPinRel)
  }
}

# ============================================================================
# (1) CLARITY CHECK - one pass, fail-closed (dispatch 3.A.1)
# ============================================================================
# The NL derivation of the spec/constraint package is the SUPERVISOR's input; the
# ENGINE enforces structure. A $null/unreadable register is NEVER treated as empty
# (the S1 ledger discipline); a deliberately-empty register is VALID (a clear
# instruction has no ambiguity items). Returns
#   @{ status = 'CLEAR' | 'MUST_ASK'; unresolved_blocking = @(<item ids>) }
# MUST_ASK names every unresolved blocking item (these become the gate's
# questions); the freeze CANNOT proceed on MUST_ASK (enforced at the freeze).
function Assert-NeoClarityAmbiguityRegister {
  param($Register, [string]$Label = 'clarity ambiguity register')
  if ($null -eq $Register) {
    New-NeoBlock "reason_code=CLARITY_REGISTER_UNREADABLE ${Label}: register is null/unreadable => STOP (never treat-as-empty; a deliberately-empty register is an explicit empty list)"
  }
  if (-not (Test-NeoClarityIsList $Register)) {
    New-NeoBlock "reason_code=CLARITY_REGISTER_UNREADABLE ${Label}: register is not a list (scalar/string/object) => STOP (fail-closed)"
  }
  $unresolved = @()
  # SIBLING SWEEP (item_id is a lookup/naming key: the unresolved_blocking list -
  # built from item_id below - NAMES the gate's questions; a duplicate/case-variant
  # id conflates two distinct open questions). SAME three-guard distinctness
  # discipline as slice_id: (1) ordinal-dup, (2) OrdinalIgnoreCase case-variant
  # (the F5 lesson), (3) the -ceq culture-collision guard (the Kelvin class).
  $itemIds = @()
  $n = 0
  foreach ($item in @($Register)) {
    $n++
    if ($null -eq $item) {
      New-NeoBlock "reason_code=CLARITY_UNCLASSIFIED_AMBIGUITY ${Label}: item $n is null => STOP"
    }
    $itemId = Get-NeoProp $item 'item_id'
    Assert-NeoClarityNonBlankString $itemId 'item_id' "${Label} item $n"
    $itemIds += [string]$itemId
    Assert-NeoClarityNonBlankString (Get-NeoProp $item 'surface') 'surface' "${Label} item '$itemId'"
    $cls = Get-NeoProp $item 'classification'
    if (-not ($cls -is [string]) -or [string]::IsNullOrWhiteSpace($cls) -or ($script:NeoClarityAmbiguityClasses -cnotcontains $cls)) {
      New-NeoBlock "reason_code=CLARITY_UNCLASSIFIED_AMBIGUITY ${Label}: item '$itemId' classification '$cls' is missing/blank/unknown (must be one of: $($script:NeoClarityAmbiguityClasses -join ' | '), ordinal case-exact) => STOP (fail-closed on an unclassifiable ambiguity)"
    }
    if ($script:NeoClarityBlockingClasses -ccontains $cls) {
      # a blocking item needs a recorded HUMAN resolution: non-blank resolution +
      # resolved_by + resolved_date. Missing any => the item is an OPEN QUESTION.
      $res  = Get-NeoProp $item 'resolution'
      $by   = Get-NeoProp $item 'resolved_by'
      $date = Get-NeoProp $item 'resolved_date'
      $resolved = (($res -is [string]) -and -not [string]::IsNullOrWhiteSpace($res)) -and
                  (($by -is [string]) -and -not [string]::IsNullOrWhiteSpace($by)) -and
                  (($date -is [string]) -and ($date -cmatch $script:NeoClarityDateOnlyPattern))
      if (-not $resolved) { $unresolved += [string]$itemId }
    } else {
      # documented_default MUST carry a non-blank documented default; missing => STOP.
      $def = Get-NeoProp $item 'documented_default'
      if (-not ($def -is [string]) -or [string]::IsNullOrWhiteSpace($def)) {
        New-NeoBlock "reason_code=CLARITY_DEFAULT_MISSING ${Label}: item '$itemId' is documented_default but carries no non-blank documented default => STOP"
      }
    }
  }
  # item_id distinctness (three complementary guards - none subsumes another).
  $seenItem = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $seenItemCi = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($ii in $itemIds) {
    if (-not $seenItem.Add($ii)) {
      New-NeoBlock "reason_code=CLARITY_UNCLASSIFIED_AMBIGUITY ${Label}: duplicate item_id '$ii' => STOP (the unresolved_blocking list names the gate's questions; a duplicate id conflates two distinct open questions)"
    }
    if (-not $seenItemCi.Add($ii)) {
      New-NeoBlock "reason_code=CLARITY_UNCLASSIFIED_AMBIGUITY ${Label}: item_id '$ii' is a CASE-VARIANT near-duplicate of an earlier item_id (equal under OrdinalIgnoreCase but ordinally distinct) => STOP (case-insensitive question naming could not cleanly separate them - the F5 discipline)"
    }
  }
  for ($a = 0; $a -lt $itemIds.Count; $a++) {
    for ($b = $a + 1; $b -lt $itemIds.Count; $b++) {
      if ([string]$itemIds[$a] -ceq [string]$itemIds[$b]) {
        New-NeoBlock "reason_code=CLARITY_UNCLASSIFIED_AMBIGUITY ${Label}: item_ids '$($itemIds[$a])' and '$($itemIds[$b])' are ordinally distinct but COLLIDE under -ceq => STOP (the gate's question naming could not cleanly separate them)"
      }
    }
  }
  $status = 'CLEAR'
  if (@($unresolved).Count -gt 0) { $status = 'MUST_ASK' }
  return @{ status = $status; unresolved_blocking = @($unresolved) }
}

# ============================================================================
# (2) FREEZE-POINT VALIDATORS (dispatch 3.A.2) - each fail-closed, run BEFORE
#     the freeze record lands
# ============================================================================
function Assert-NeoClaritySlicePlan {
  param($SlicePlan, [string]$PlanSliceId = $script:NeoClarityPlanSliceId)
  if ($null -eq $SlicePlan -or -not (Test-NeoClarityIsList $SlicePlan) -or @($SlicePlan).Count -lt 1) {
    New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice plan: null/not-a-list/empty => STOP (a frozen plan has >=1 slice)"
  }
  $ids = @()
  $n = 0
  foreach ($s in @($SlicePlan)) {
    $n++
    if ($null -eq $s) { New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice plan: slice $n is null => STOP" }
    $sid = Get-NeoProp $s 'slice_id'
    Assert-NeoClarityNonBlankString $sid 'slice_id' "slice $n"
    # Reserved-id refusals are CASE-INSENSITIVE (OrdinalIgnoreCase): a case-variant
    # of a reserved id defeats the reservation's intent on a case-insensitive OS
    # (the F5 lesson - Assert-NeoGovMembersWellFormed). The case-exact refusals are
    # subsumed; the message names the case-variant explicitly. Same reason_code.
    if ([string]::Equals([string]$sid, [string]$script:NeoRunExternalSliceId, [System.StringComparison]::OrdinalIgnoreCase)) {
      New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice plan: slice_id '$sid' is RESERVED (case-insensitively; '$($script:NeoRunExternalSliceId)') for the run-scope external-call ledger => REFUSED at freeze"
    }
    if ([string]::Equals([string]$sid, [string]$PlanSliceId, [System.StringComparison]::OrdinalIgnoreCase)) {
      New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice plan: slice_id '$sid' is RESERVED (case-insensitively; '$PlanSliceId') for the plan-audit pseudo-slice => REFUSED at freeze"
    }
    $ap = Get-NeoVal $s 'approved_paths'
    if (-not (Test-NeoClarityIsList $ap) -or @($ap).Count -lt 1) {
      New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice '$sid': approved_paths missing/empty => STOP (every slice declares a non-empty approved set)"
    }
    foreach ($p in @($ap)) { Assert-NeoClarityNonBlankString $p 'approved_paths member' "slice '$sid'" }
    # protected_paths may be EMPTY only when EXPLICITLY DECLARED so (PowerShell
    # unwraps an empty-array property to $null on Get-NeoProp - the C6-FIX I-1
    # lesson - so PRESENCE is tested first, then the shape-preserving value).
    if (-not (Test-NeoHasProp $s 'protected_paths')) {
      New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice '$sid': protected_paths key ABSENT => STOP (an empty protected set must be explicitly declared, never implied)"
    }
    $pp = Get-NeoVal $s 'protected_paths'
    $ppCount = 0
    if ($null -ne $pp) {
      if (-not (Test-NeoClarityIsList $pp)) {
        New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice '$sid': protected_paths is not a list => STOP"
      }
      $ppCount = @($pp).Count
      foreach ($p in @($pp)) { Assert-NeoClarityNonBlankString $p 'protected_paths member' "slice '$sid'" }
    }
    if ($ppCount -eq 0) {
      $decl = Get-NeoProp $s 'protected_paths_declared_empty'
      if (-not ($decl -is [bool]) -or -not $decl) {
        New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice '$sid': protected_paths is EMPTY without protected_paths_declared_empty=true => STOP (empty only if explicitly declared)"
      }
    }
    $hp = Get-NeoVal $s 'acceptance_harness_paths'
    if (-not (Test-NeoClarityIsList $hp) -or @($hp).Count -lt 1) {
      New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice '$sid': acceptance_harness_paths missing/empty => STOP (C1a registration is mandatory per slice)"
    }
    foreach ($p in @($hp)) { Assert-NeoClarityNonBlankString $p 'acceptance_harness_paths member' "slice '$sid'" }
    Assert-NeoClarityNonBlankString (Get-NeoProp $s 'risk_row_ref') 'risk_row_ref' "slice '$sid'"
    $ids += [string]$sid
  }
  # THREE COMPLEMENTARY distinctness guards (none subsumes another):
  #  (1) ordinal-dup: exact-repeat slice_id refused AT THE SOURCE (the S3c
  #      collision class - Get-NeoLoopRunSliceUniverse collision-rule semantics);
  #  (2) case-variant: OrdinalIgnoreCase near-duplicate refused (the govmanifest
  #      F5 discipline verbatim - 'SliceA'/'slicea' on a case-insensitive OS);
  #  (3) culture-collision: the pairwise -ceq guard below (the Kelvin-class collision
  #      OrdinalIgnoreCase does NOT catch - ordinally distinct yet -ceq-equal).
  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $seenCi = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($i in $ids) {
    if (-not $seen.Add($i)) {
      New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice plan: duplicate slice_id '$i' => REFUSED at freeze"
    }
    if (-not $seenCi.Add($i)) {
      New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice plan: slice_id '$i' is a CASE-VARIANT near-duplicate of an earlier slice_id (equal under OrdinalIgnoreCase but ordinally distinct) => REFUSED at freeze (case-insensitive lookups could not cleanly separate them - the F5 discipline)"
    }
  }
  for ($a = 0; $a -lt $ids.Count; $a++) {
    for ($b = $a + 1; $b -lt $ids.Count; $b++) {
      if ([string]$ids[$a] -ceq [string]$ids[$b]) {
        New-NeoBlock "reason_code=CLARITY_SLICE_PLAN slice plan: slice_ids '$($ids[$a])' and '$($ids[$b])' are ordinally distinct but COLLIDE under -ceq => REFUSED at freeze (the per-slice ledger reads could not cleanly separate them)"
      }
    }
  }
  return $true
}

# Every slice maps to exactly ONE existing risk row; every row (referenced or not
# - the frozen row set is the authority surface) passes the FROZEN
# Assert-NeoAutonomousRowEligible (I8 explicit_downgrade key-presence => REFUSED;
# unknown/blank risk_class => BLOCK via the wrapped tier oracle). Returns the
# derived boundary-to-row mapping for the freeze record.
function Assert-NeoClarityRowMapping {
  param($SlicePlan, $RiskRows)
  if ($null -eq $RiskRows -or -not (Test-NeoClarityIsList $RiskRows) -or @($RiskRows).Count -lt 1) {
    New-NeoBlock "reason_code=CLARITY_ROW_MAPPING risk rows: null/not-a-list/empty => STOP"
  }
  $rowIds = @()
  $n = 0
  foreach ($row in @($RiskRows)) {
    $n++
    if ($null -eq $row) { New-NeoBlock "reason_code=CLARITY_ROW_MAPPING risk rows: row $n is null => STOP" }
    $rid = Get-NeoProp $row 'row_id'
    Assert-NeoClarityNonBlankString $rid 'row_id' "risk row $n"
    # frozen eligibility gate (reused, never re-implemented): I8 + tier oracle.
    [void](Assert-NeoAutonomousRowEligible -RiskRow $row)
    $rowIds += [string]$rid
  }
  # SIBLING SWEEP (row_id is a lookup key: risk_row_ref resolves against it via -ceq
  # requiring exactly ONE hit). The SAME three-guard distinctness discipline as
  # slice_id: (1) ordinal-dup, (2) OrdinalIgnoreCase case-variant (the F5 lesson),
  # (3) the pairwise -ceq culture-collision guard (unchanged - the Kelvin class).
  $seenRow = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $seenRowCi = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($ri in $rowIds) {
    if (-not $seenRow.Add($ri)) {
      New-NeoBlock "reason_code=CLARITY_ROW_MAPPING risk rows: duplicate row_id '$ri' => STOP (a slice cannot map to exactly one row through a duplicate id)"
    }
    if (-not $seenRowCi.Add($ri)) {
      New-NeoBlock "reason_code=CLARITY_ROW_MAPPING risk rows: row_id '$ri' is a CASE-VARIANT near-duplicate of an earlier row_id (equal under OrdinalIgnoreCase but ordinally distinct) => STOP (a case-insensitive ref lookup could not cleanly separate them - the F5 discipline)"
    }
  }
  for ($a = 0; $a -lt $rowIds.Count; $a++) {
    for ($b = $a + 1; $b -lt $rowIds.Count; $b++) {
      if ([string]$rowIds[$a] -ceq [string]$rowIds[$b]) {
        New-NeoBlock "reason_code=CLARITY_ROW_MAPPING risk rows: row_ids '$($rowIds[$a])' and '$($rowIds[$b])' collide under -ceq => STOP (a slice cannot map to exactly one row through an ambiguous id)"
      }
    }
  }
  $mapping = @()
  foreach ($s in @($SlicePlan)) {
    $sid = [string](Get-NeoProp $s 'slice_id')
    $ref = [string](Get-NeoProp $s 'risk_row_ref')
    $hits = @($rowIds | Where-Object { [string]$_ -ceq $ref })
    if (@($hits).Count -ne 1) {
      New-NeoBlock "reason_code=CLARITY_ROW_MAPPING slice '$sid': risk_row_ref '$ref' resolves $(@($hits).Count) risk rows (exactly 1 required) => STOP"
    }
    $mapping += [pscustomobject]@{ slice_id = $sid; row_id = $ref }
  }
  return ,@($mapping)
}

# C1a VERIFICATION (never a classmap edit): each declared acceptance-harness path
# must resolve a JUDGING class under the ENGINE'S OWN live classmap (the frozen
# canonical-contained Get-NeoGovLiveClassMap - never an app-supplied map). Returns
# the registrations list for the freeze record.
function Assert-NeoClarityJudgingRegistrations {
  param($SlicePlan, [string]$GovernedRoot)
  if ([string]::IsNullOrWhiteSpace($GovernedRoot) -or -not (Test-Path -LiteralPath $GovernedRoot -PathType Container)) {
    New-NeoBlock "reason_code=CLARITY_REGISTRATION GovernedRoot '$GovernedRoot' is not an existing directory => STOP"
  }
  $map = Get-NeoGovLiveClassMap -GovernedRoot $GovernedRoot
  $regs = @()
  foreach ($s in @($SlicePlan)) {
    $sid = [string](Get-NeoProp $s 'slice_id')
    foreach ($rel in @(Get-NeoClarityList $s 'acceptance_harness_paths')) {
      Assert-NeoSafeRel ([string]$rel)
      $cls = Resolve-NeoArtifactClass $map ([string]$rel)
      if ($script:NeoGovJudgingClasses -notcontains $cls) {
        New-NeoBlock "reason_code=CLARITY_REGISTRATION slice '$sid': acceptance harness '$rel' resolves NON-JUDGING ('$cls') under the live engine classmap => STOP (the C1a registration slice happens BEFORE C5; C5 verifies, never edits the classmap)"
      }
      $regs += [pscustomobject]@{ slice_id = $sid; harness_rel = [string]$rel; resolved_class = [string]$cls }
    }
  }
  return ,@($regs)
}

# C6 coupling: the FROZEN Resolve-NeoRouterProfile runs with the freeze's
# AttestedGapRecords; any BLOCK propagates (empty/half-empty profile => STOP
# unless that specific gap carries a valid attestation record). The freeze record
# ARCHIVES the records - "record authority binds at the C5 gate".
function Assert-NeoClarityProfileGate {
  param($Profile, $AttestedGapRecords = @())
  $view = Resolve-NeoRouterProfile -Profile $Profile -AttestedGapRecords $AttestedGapRecords
  return @{ profile_view = $view; attestation_records = @($AttestedGapRecords) }
}

# C1b: rule-derive the governed-root manifest + enforce the mandatory floor
# (26-rel incl. orch_clarity.ps1 after the lockstep edit) + persist the pin the
# loop's round check consumes as -PinnedGovManifestPath. Write-then-verify through
# the SAME frozen reverify the round check uses (check==use parity).
function New-NeoClarityGovManifestPin {
  param(
    [Parameter(Mandatory = $true)][string]$GovernedRoot,
    [Parameter(Mandatory = $true)][string]$DerivedAt,
    [Parameter(Mandatory = $true)][string]$PinOutPath
  )
  $man = Build-NeoGovManifest -GovernedRoot $GovernedRoot -DerivedAt $DerivedAt
  Assert-NeoGovManifestMandatoryMembers -Manifest $man -GovernedRoot $GovernedRoot
  $parent = Split-Path -Parent $PinOutPath
  if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  Write-NeoJsonFile $PinOutPath $man
  [void](Assert-NeoGovManifestReverify -PinnedPath $PinOutPath -Current $man -GovernedRoot $GovernedRoot)
  return @{ path = $PinOutPath; sha256 = (Get-NeoSha256File $PinOutPath) }
}

# App-side judging pins: a SECOND rule-derived manifest over the APP root
# (Build-NeoGovManifest works on any root carrying its own .neo/schema classmap;
# the app profile resolves profile_risk by glob - probed). The engine 26-rel floor
# does NOT apply here - the floor assert is DELIBERATELY NOT called; C5 asserts
# the app-side members itself. The risk register does NOT resolve judging by glob
# (probed: no instance glob exists) so it is pinned by EXPLICIT hash field.
function New-NeoClarityAppPin {
  param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$DerivedAt,
    [Parameter(Mandatory = $true)][string]$PinOutPath,
    [string[]]$RequiredAppMembers = @('NEO_APP_PROFILE.json'),
    [Parameter(Mandatory = $true)][string]$RiskRegisterRel
  )
  $man = Build-NeoGovManifest -GovernedRoot $AppRoot -DerivedAt $DerivedAt
  # C5-local app-side mandatory members (full canonical rel, case-exact).
  $members = @($man.members)
  foreach ($req in @($RequiredAppMembers)) {
    if ([string]::IsNullOrWhiteSpace($req)) { continue }
    $hit = @($members | Where-Object { ([string]$_.rel) -ceq ([string]$req) })
    if (@($hit).Count -eq 0) {
      New-NeoBlock "reason_code=CLARITY_APP_PIN app-side mandatory member '$req' is ABSENT from the app-root derived manifest => STOP (the app profile must be pinned; C5 asserts app-side members itself - the engine floor never applies to the app root)"
    }
  }
  Assert-NeoSafeRel $RiskRegisterRel
  $regFull = Assert-NeoContained $AppRoot $RiskRegisterRel
  if (-not (Test-Path -LiteralPath $regFull -PathType Leaf)) {
    New-NeoBlock "reason_code=CLARITY_APP_PIN risk register '$RiskRegisterRel' not found under the app root => STOP (the risk-register hash pin is a mandatory freeze product)"
  }
  $parent = Split-Path -Parent $PinOutPath
  if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  Write-NeoJsonFile $PinOutPath $man
  [void](Assert-NeoGovManifestReverify -PinnedPath $PinOutPath -Current $man -GovernedRoot $AppRoot)
  return @{
    app_manifest_pin  = @{ path = $PinOutPath; sha256 = (Get-NeoSha256File $PinOutPath) }
    risk_register_pin = @{ rel = $RiskRegisterRel; sha256 = (Get-NeoSha256File $regFull) }
  }
}

# ============================================================================
# FREEZE-LEDGER READERS (S1 fail-closed discipline + NB-4 stamp re-derive)
# ============================================================================
function Read-NeoClarityFreezeRecords {
  param([Parameter(Mandatory = $true)][string]$RunRoot, $Index)
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoClarityFreezeLedgerLeaf
  if (-not (Test-Path -LiteralPath $path)) { return ,@() }
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:clarity_freeze_record' -Index $Index `
    -Label 'clarity_freeze_ledger' -ExpectedRunId $runId
  $n = 0
  foreach ($e in @($entries)) {
    $n++
    # NB-4: any record whose record_sha256 does not re-derive => BLOCK.
    $expect = Get-NeoBodyHash $e @('record_sha256')
    if ($expect -cne [string](Get-NeoProp $e 'record_sha256')) {
      New-NeoBlock "reason_code=CLARITY_FREEZE_TAMPERED clarity_freeze_ledger: line $n record_sha256 does not re-derive (post-write edit detected; NB-4 tamper-EVIDENT) => BLOCK"
    }
    # a freeze is IMMUTABLE; a revision is a NEW record at round N+1: strict +1
    # from 1 in file order (check==use with the write side).
    $pr = [string](Get-NeoProp $e 'plan_round')
    Assert-NeoClarityPlanRound $pr "clarity_freeze_ledger line $n"
    if ([int]$pr -ne $n) {
      New-NeoBlock "reason_code=CLARITY_FREEZE_TAMPERED clarity_freeze_ledger: line $n carries plan_round '$pr', expected '$n' (strict +1 from 1; a revision is a NEW record with an INCREMENTED plan round) => BLOCK"
    }
  }
  return ,@($entries)
}
function Get-NeoClarityLatestFreeze {
  param([Parameter(Mandatory = $true)][string]$RunRoot, $Index)
  $entries = Read-NeoClarityFreezeRecords -RunRoot $RunRoot -Index $Index
  if (@($entries).Count -eq 0) {
    New-NeoBlock "reason_code=CLARITY_FREEZE_MISSING no clarity freeze record exists for this run => BLOCK (the frozen plan is the gate's authority; nothing to derive readiness from)"
  }
  return @($entries)[@($entries).Count - 1]
}

# ============================================================================
# (2) THE FREEZE POINT (dispatch 3.A.2) - assemble + validate + persist
# ============================================================================
# Runs EVERY freeze validator fail-closed BEFORE the record lands, derives the
# next plan round mechanically (immutability: revision = NEW record, round+1),
# writes the deterministic per-round pins under <SessionRoot>/plan_audit/, stamps
# record_sha256 (NB-4), schema-validates, and appends to the freeze ledger.
function New-NeoClarityFreezeRecord {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [Parameter(Mandatory = $true)][string]$InstructionDigestRef,
    # deliberately NOT [Parameter(Mandatory)]: a $null register/plan/rows/profile
    # must reach the fail-closed validators and produce a NEO-BLOCK (never a
    # PowerShell binding error a caller could distinguish from policy).
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
    $Index
  )
  Assert-NeoClarityNonBlankString $InstructionDigestRef 'InstructionDigestRef' 'freeze'
  Assert-NeoClarityNonBlankString $StampedBy 'StampedBy' 'freeze'
  [void](ConvertFrom-NeoRunTimestamp $Timestamp 'Timestamp' 'CLARITY_SHAPE')
  if ([string]::IsNullOrWhiteSpace($SessionRoot) -or -not (Test-Path -LiteralPath $SessionRoot -PathType Container)) {
    New-NeoBlock "reason_code=CLARITY_SHAPE freeze: SessionRoot '$SessionRoot' is not an existing directory => STOP"
  }
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }

  # (a) CLARITY CHECK: unresolved blocking ambiguity => the freeze cannot proceed;
  # the unresolved items ARE the gate's questions.
  $clarity = Assert-NeoClarityAmbiguityRegister -Register $AmbiguityRegister
  if ($clarity.status -cne 'CLEAR') {
    New-NeoBlock ("reason_code=CLARITY_MUST_ASK freeze: unresolved BLOCKING ambiguity item(s) [" + (@($clarity.unresolved_blocking) -join ', ') + "] - these are the gate's questions; the freeze cannot proceed until each carries a recorded human resolution (resolution + resolved_by + resolved_date)")
  }
  # (b) slice plan (incl. reserved/collision refusals at the source).
  [void](Assert-NeoClaritySlicePlan -SlicePlan $SlicePlan)
  # (c) boundary-to-risk-row mapping + frozen row eligibility (I8 + oracle).
  $mapping = Assert-NeoClarityRowMapping -SlicePlan $SlicePlan -RiskRows $RiskRows
  # (d) C1a judging-class registrations under the ENGINE's live map.
  $regs = Assert-NeoClarityJudgingRegistrations -SlicePlan $SlicePlan -GovernedRoot $GovernedRoot
  # (e) profile gate (C6 coupling; frozen router rules, never re-implemented).
  $prof = Assert-NeoClarityProfileGate -Profile $Profile -AttestedGapRecords $AttestedGapRecords
  # (f) plan round: mechanical increment over the fail-closed ledger read.
  $existing = Read-NeoClarityFreezeRecords -RunRoot $RunRoot -Index $Index
  $planRound = [string](@($existing).Count + 1)
  # (g) deterministic per-round pins under <SessionRoot>/plan_audit/.
  $paths = Get-NeoClarityPlanAuditPaths $SessionRoot $planRound
  if (-not (Test-Path -LiteralPath $paths.dir_full -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $paths.dir_full | Out-Null
  }
  $govPin = New-NeoClarityGovManifestPin -GovernedRoot $GovernedRoot -DerivedAt $Timestamp -PinOutPath $paths.gov_pin_full
  $appPin = New-NeoClarityAppPin -AppRoot $AppRoot -DerivedAt $Timestamp -PinOutPath $paths.app_pin_full -RiskRegisterRel $RiskRegisterRel

  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $rec = [pscustomobject]@{
    schema_id                = 'neo:clarity_freeze_record'
    run_id                   = [string](Get-NeoProp $manifest 'run_id')
    plan_round               = $planRound
    instruction_digest_ref   = $InstructionDigestRef
    ambiguity_register       = @($AmbiguityRegister)
    slice_plan               = @($SlicePlan)
    boundary_to_row_mapping  = @($mapping)
    risk_rows                = @($RiskRows)
    judging_registrations    = @($regs)
    gov_manifest_pin         = [pscustomobject]@{ rel = $paths.gov_pin_rel; sha256 = [string]$govPin.sha256 }
    app_manifest_pin         = [pscustomobject]@{ rel = $paths.app_pin_rel; sha256 = [string]$appPin.app_manifest_pin.sha256 }
    risk_register_pin        = [pscustomobject]@{ rel = [string]$appPin.risk_register_pin.rel; sha256 = [string]$appPin.risk_register_pin.sha256 }
    attestation_records      = @($prof.attestation_records)
    stamped_by               = $StampedBy
    timestamp_utc            = $Timestamp
  }
  $rec | Add-Member -NotePropertyName 'record_sha256' -NotePropertyValue (Get-NeoBodyHash $rec @('record_sha256'))
  Assert-NeoValid $rec 'neo:clarity_freeze_record' $Index 'CLARITY_FREEZE_RECORD(append)'
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoClarityFreezeLedgerLeaf
  [void](Add-NeoRunJsonlLine $path $rec 'clarity_freeze_ledger')
  return $rec
}

# ============================================================================
# GATE-RECORD LEDGER (disclosures + dispositions; dispatch 3.B kind discipline)
# ============================================================================
function Read-NeoClarityGateRecords {
  param([Parameter(Mandatory = $true)][string]$RunRoot, $Index)
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoClarityGateLedgerLeaf
  if (-not (Test-Path -LiteralPath $path)) { return ,@() }
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:clarity_gate_record' -Index $Index `
    -Label 'clarity_gate_ledger' -ExpectedRunId $runId
  $n = 0
  foreach ($e in @($entries)) {
    $n++
    $expect = Get-NeoBodyHash $e @('record_sha256')
    if ($expect -cne [string](Get-NeoProp $e 'record_sha256')) {
      New-NeoBlock "reason_code=CLARITY_GATE_RECORD_TAMPERED clarity_gate_ledger: line $n record_sha256 does not re-derive (NB-4 tamper-EVIDENT) => BLOCK"
    }
  }
  return ,@($entries)
}

# Writes ONE gate record of EXACTLY one kind; the kind-specific fields are
# DISJOINT and fully fail-closed both ways (R1-3) - enforced here AND in the
# schema (if/then both directions + additionalProperties:false).
function Add-NeoClarityGateRecord {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$Kind,
    [Parameter(Mandatory = $true)][string]$PlanRound,
    [Parameter(Mandatory = $true)][string]$BundleDiffHash,
    [Parameter(Mandatory = $true)][string]$StampedBy,
    [Parameter(Mandatory = $true)][string]$Timestamp,
    [string]$Stage,
    [string]$Reason,
    [string]$RecordedBy,
    [string]$AuthorityBasis,
    [string]$DisagreementText,
    [string]$Rationale,
    $Index
  )
  # kind vocabulary is ordinal case-exact (ValidateSet is case-insensitive - wrong tool).
  if ($script:NeoClarityGateRecordKinds -cnotcontains $Kind) {
    New-NeoBlock "reason_code=CLARITY_GATE_RECORD gate record: kind '$Kind' outside $($script:NeoClarityGateRecordKinds -join '|') (ordinal case-exact) => STOP"
  }
  Assert-NeoClarityPlanRound $PlanRound 'gate record'
  if ([string]::IsNullOrWhiteSpace($BundleDiffHash) -or ($BundleDiffHash -cnotmatch $script:NeoClaritySha256Pattern)) {
    New-NeoBlock "reason_code=CLARITY_GATE_RECORD gate record: BundleDiffHash is not a lowercase sha256 => STOP (the record binds to the exact plan bundle)"
  }
  Assert-NeoClarityNonBlankString $StampedBy 'StampedBy' 'gate record'
  [void](ConvertFrom-NeoRunTimestamp $Timestamp 'Timestamp' 'CLARITY_GATE_RECORD')
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')

  $rec = $null
  if ($Kind -ceq 'unavailability_disclosure') {
    # R1-1: stage/reason come VERBATIM from the adapter (or ADAPTER_THREW); a
    # blank/unattributed stage is refused - never "channel unavailable" prose
    # with no mechanical source. Disposition fields must be ABSENT.
    foreach ($f in @(@('RecordedBy', $RecordedBy), @('AuthorityBasis', $AuthorityBasis), @('DisagreementText', $DisagreementText), @('Rationale', $Rationale))) {
      if (-not [string]::IsNullOrWhiteSpace([string]$f[1])) {
        New-NeoBlock "reason_code=CLARITY_GATE_RECORD unavailability_disclosure: disposition field '$($f[0])' supplied => STOP (kind fields are DISJOINT, fail-closed both ways)"
      }
    }
    Assert-NeoClarityNonBlankString $Stage 'Stage' 'unavailability_disclosure'
    Assert-NeoClarityNonBlankString $Reason 'Reason' 'unavailability_disclosure'
    $rec = [pscustomobject]@{
      schema_id = 'neo:clarity_gate_record'; run_id = $runId; kind = $Kind
      plan_round = $PlanRound; bundle_diff_hash = $BundleDiffHash
      stage = $Stage; reason = $Reason
      stamped_by = $StampedBy; timestamp_utc = $Timestamp
    }
  } else {
    # directional_disposition (R1-2): authority fields EXPLICIT; the record is
    # DISCLOSURE not approval - the human gate it rides to remains the sole
    # authority. Adapter-stage fields must be ABSENT.
    foreach ($f in @(@('Stage', $Stage), @('Reason', $Reason))) {
      if (-not [string]::IsNullOrWhiteSpace([string]$f[1])) {
        New-NeoBlock "reason_code=CLARITY_GATE_RECORD directional_disposition: adapter-stage field '$($f[0])' supplied => STOP (kind fields are DISJOINT, fail-closed both ways)"
      }
    }
    Assert-NeoClarityNonBlankString $RecordedBy 'RecordedBy' 'directional_disposition'
    Assert-NeoClarityNonBlankString $DisagreementText 'DisagreementText' 'directional_disposition'
    Assert-NeoClarityNonBlankString $Rationale 'Rationale' 'directional_disposition'
    if ([string]::IsNullOrWhiteSpace($AuthorityBasis)) { $AuthorityBasis = $script:NeoClarityDispositionAuthorityBasis }
    if ($AuthorityBasis -cne $script:NeoClarityDispositionAuthorityBasis) {
      New-NeoBlock "reason_code=CLARITY_GATE_RECORD directional_disposition: authority_basis is not the fixed ratified-policy citation => STOP (the basis is a constant, never free prose)"
    }
    $rec = [pscustomobject]@{
      schema_id = 'neo:clarity_gate_record'; run_id = $runId; kind = $Kind
      plan_round = $PlanRound; bundle_diff_hash = $BundleDiffHash
      recorded_by = $RecordedBy; authority_basis = $AuthorityBasis
      disagreement_text = $DisagreementText; rationale = $Rationale
      stamped_by = $StampedBy; timestamp_utc = $Timestamp
    }
  }
  $rec | Add-Member -NotePropertyName 'record_sha256' -NotePropertyValue (Get-NeoBodyHash $rec @('record_sha256'))
  Assert-NeoValid $rec 'neo:clarity_gate_record' $Index 'CLARITY_GATE_RECORD(append)'
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoClarityGateLedgerLeaf
  [void](Add-NeoRunJsonlLine $path $rec 'clarity_gate_ledger')
  return $rec
}

# ============================================================================
# (3) PRE-START PLAN AUDIT (the 2026-07-07 addendum as CODE; dispatch 3.A.3)
# ============================================================================
# Runs the FROZEN C4 channel over the LATEST freeze's plan artifacts. The verdict
# lands in the run's external verdict ledger AUTOMATICALLY (frozen adapter) - NO
# parallel verdict store. Calls COUNT against the DEF-P7 run budget + the <=3
# per-plan-pseudo-slice sub-cap. ANY lane NOT in {GO, NO_GO} (R-2 exhaustive:
# MISSING, STALE, UNPARSEABLE, or ANY unrecognized value - the unknown/default
# case is the threat) => a durable UNAVAILABILITY DISCLOSURE record bound to the
# current plan-round + plan-bundle hash, stage/reason VERBATIM from the adapter
# (R1-1); a THROWN adapter failure => stage ADAPTER_THREW. NEVER silently skipped.
function Invoke-NeoClarityPlanAudit {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [Parameter(Mandatory = $true)][string]$StampedBy,
    [Parameter(Mandatory = $true)][string]$Timestamp,
    [string]$AttestationPath,
    [string]$CredentialPath,
    [int]$TimeoutSec = 0,
    $InvokerSeam,
    $Index
  )
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  if ([string]::IsNullOrWhiteSpace($SessionRoot) -or -not (Test-Path -LiteralPath $SessionRoot -PathType Container)) {
    New-NeoBlock "reason_code=CLARITY_SHAPE plan audit: SessionRoot '$SessionRoot' is not an existing directory => STOP"
  }
  $freeze = Get-NeoClarityLatestFreeze -RunRoot $RunRoot -Index $Index
  $planRound = [string](Get-NeoProp $freeze 'plan_round')
  $paths = Get-NeoClarityPlanAuditPaths $SessionRoot $planRound
  if (-not (Test-Path -LiteralPath $paths.dir_full -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $paths.dir_full | Out-Null
  }

  # check==use: the freeze's recorded pin hashes must still match the on-disk pin
  # files the bundle will carry (pin drift after freeze => STOP; revise the plan).
  foreach ($pin in @(
      @('gov_manifest_pin', $paths.gov_pin_full),
      @('app_manifest_pin', $paths.app_pin_full))) {
    $ref = Get-NeoProp $freeze $pin[0]
    $full = [string]$pin[1]
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
      New-NeoBlock "reason_code=CLARITY_PLAN_AUDIT plan audit: $($pin[0]) file absent at its deterministic round path '$full' => STOP"
    }
    if ((Get-NeoSha256File $full) -cne [string](Get-NeoProp $ref 'sha256')) {
      New-NeoBlock "reason_code=CLARITY_PLAN_AUDIT plan audit: $($pin[0]) on-disk hash does not match the freeze-recorded pin => STOP (post-freeze pin drift; a revision is a NEW freeze round)"
    }
  }

  # materialize the freeze record at its deterministic per-round path (the bundle
  # member the external model audits; the ledger line remains the authority).
  Write-NeoJsonFile $paths.freeze_full $freeze

  # plan-scope boundary for the bundle envelope: the union of the frozen slices'
  # approved/protected paths (presentation of scope; the freeze is the authority).
  $ap = @(); $pp = @()
  foreach ($s in @(Get-NeoClarityList $freeze 'slice_plan')) {
    foreach ($p in @(Get-NeoClarityList $s 'approved_paths'))  { if ($ap -cnotcontains [string]$p) { $ap += [string]$p } }
    foreach ($p in @(Get-NeoClarityList $s 'protected_paths')) { if ($pp -cnotcontains [string]$p) { $pp += [string]$p } }
  }
  $members = @(
    @{ path = $paths.freeze_full;  rel = ('./' + $paths.freeze_rel);  role = 'plan_freeze_record' },
    @{ path = $paths.gov_pin_full; rel = ('./' + $paths.gov_pin_rel); role = 'gov_manifest_pin' },
    @{ path = $paths.app_pin_full; rel = ('./' + $paths.app_pin_rel); role = 'app_manifest_pin' }
  )
  # surfaces vocabulary = the frozen input_packet enum (filesystem | database |
  # object_storage | external_account); the plan artifacts are filesystem members.
  [void](New-NeoAuditBundle -BundleId ('plan-audit-round-' + $planRound) -MemberItems $members `
    -ApprovedPaths $ap -ProtectedPaths $pp -Surfaces @('filesystem') -RiskTier 'high' `
    -Timestamp $Timestamp -Index $Index -OutPath $paths.bundle_full)

  # the FROZEN adapter (attestation gate -> caps -> write-ahead -> invoker ->
  # parser -> round-bound verdict record). A THROW here is a caller-contract
  # failure captured fail-hard into the distinct ADAPTER_THREW stage (R1-1).
  $res = $null
  try {
    $callArgs = @{
      RunRoot = $RunRoot; SliceId = $script:NeoClarityPlanSliceId; RoundId = $planRound
      SessionRoot = $SessionRoot; BundleRef = ('./' + $paths.bundle_rel)
      Timestamp = $Timestamp; StampedBy = $StampedBy
    }
    if (-not [string]::IsNullOrWhiteSpace($AttestationPath)) { $callArgs['AttestationPath'] = $AttestationPath }
    if (-not [string]::IsNullOrWhiteSpace($CredentialPath))  { $callArgs['CredentialPath']  = $CredentialPath }
    if ($TimeoutSec -gt 0) { $callArgs['TimeoutSec'] = $TimeoutSec }
    if ($null -ne $InvokerSeam) { $callArgs['InvokerSeam'] = $InvokerSeam }
    $res = Invoke-NeoExternalAudit @callArgs
  } catch {
    $bundleHash = Get-NeoSha256File $paths.bundle_full
    $reason = ConvertTo-NeoExternalAsciiLine ([string]$_.Exception.Message) 400
    [void](Add-NeoClarityGateRecord -RunRoot $RunRoot -Kind 'unavailability_disclosure' `
      -PlanRound $planRound -BundleDiffHash $bundleHash -Stage $script:NeoClarityAdapterThrewStage `
      -Reason $reason -StampedBy $StampedBy -Timestamp $Timestamp -Index $Index)
    return @{ lane = 'MISSING'; stage = $script:NeoClarityAdapterThrewStage; reason = $reason
              verdict = ''; plan_round = $planRound; bundle_diff_hash = $bundleHash; disclosure_written = $true }
  }
  $bundleHash = Get-NeoSha256File $paths.bundle_full
  $lane = [string](Get-NeoProp $res 'lane')
  # R-2 EXHAUSTIVE TRIGGER: any lane NOT in {GO, NO_GO} writes the disclosure -
  # MISSING, STALE, UNPARSEABLE, or ANY unrecognized lane string. Never an
  # enumerated two-value check; the unknown/default case is the threat.
  if (($lane -cne 'GO') -and ($lane -cne 'NO_GO')) {
    $stage = [string](Get-NeoProp $res 'stage')
    $reason = [string](Get-NeoProp $res 'reason')
    if ([string]::IsNullOrWhiteSpace($stage)) {
      # an unattributed non-verdict outcome is refused loudly, never disclosed
      # vaguely and never silently passed (the disclosure must carry a
      # mechanical source; this surfaces as a STOP, not a skip).
      New-NeoBlock "reason_code=CLARITY_PLAN_AUDIT plan audit: adapter returned non-verdict lane '$lane' with a BLANK stage - an unavailability disclosure must carry the mechanical stage/reason source => STOP (fail-closed; nothing archived, the gate stays blocked)"
    }
    if ([string]::IsNullOrWhiteSpace($reason)) { $reason = ('adapter returned lane ' + $lane + ' with no reason text') }
    [void](Add-NeoClarityGateRecord -RunRoot $RunRoot -Kind 'unavailability_disclosure' `
      -PlanRound $planRound -BundleDiffHash $bundleHash -Stage $stage `
      -Reason (ConvertTo-NeoExternalAsciiLine $reason 400) -StampedBy $StampedBy -Timestamp $Timestamp -Index $Index)
    return @{ lane = $lane; stage = $stage; reason = $reason; verdict = [string](Get-NeoProp $res 'verdict')
              plan_round = $planRound; bundle_diff_hash = $bundleHash; disclosure_written = $true }
  }
  return @{ lane = $lane; stage = [string](Get-NeoProp $res 'stage'); reason = [string](Get-NeoProp $res 'reason')
            verdict = [string](Get-NeoProp $res 'verdict'); plan_round = $planRound
            bundle_diff_hash = $bundleHash; disclosure_written = $false }
}

# ============================================================================
# (4) GATE-READINESS DERIVATION (dispatch 3.A.4) - FROM DISK ONLY
# ============================================================================
# No caller-supplied verdict/lane/round values (the forgeable-authority lesson).
# Binds to the LATEST freeze (recorded plan-round + re-derived record_sha256);
# R-1: the expected plan-bundle hash is RE-HASHED from the ON-DISK bundle at its
# deterministic per-round path - a missing/swapped/tampered bundle re-hashes
# differently => lane STALE/MISSING => BLOCKED. Any derivation failure => BLOCKED
# (fail-closed, never READY). States:
#   READY                 - archived current-round GO verdict.
#   READY_WITH_DISCLOSURE - NO_GO + stamped directional disposition for THIS
#                           round+hash, OR non-verdict lane + archived
#                           unavailability disclosure for THIS round+hash.
#   BLOCKED               - everything else (THE GATE CANNOT SURFACE).
function Get-NeoClarityGateReadiness {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    $Index
  )
  try {
    if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
    if ([string]::IsNullOrWhiteSpace($SessionRoot) -or -not (Test-Path -LiteralPath $SessionRoot -PathType Container)) {
      return @{ state = 'BLOCKED'; reason = "SessionRoot '$SessionRoot' is not an existing directory (fail-closed)" }
    }
    # (a) the LATEST freeze, tamper- and schema-verified from disk.
    $freeze = Get-NeoClarityLatestFreeze -RunRoot $RunRoot -Index $Index
    $planRound = [string](Get-NeoProp $freeze 'plan_round')
    # (b) R-1: re-hash the ON-DISK bundle at the deterministic per-round path.
    $paths = Get-NeoClarityPlanAuditPaths $SessionRoot $planRound
    if (-not (Test-Path -LiteralPath $paths.bundle_full -PathType Leaf)) {
      return @{ state = 'BLOCKED'; plan_round = $planRound
                reason = "no plan AUDIT_BUNDLE exists at the deterministic round path '$($paths.bundle_rel)' - the pre-START plan audit has not run for freeze round $planRound (the gate cannot surface)" }
    }
    $bundleHash = Get-NeoSha256File $paths.bundle_full
    # (c) the FROZEN shared lane rule over the full binding tuple (check==use).
    $lane = Get-NeoExternalLaneStatus -RunRoot $RunRoot -SliceId $script:NeoClarityPlanSliceId `
      -RoundId $planRound -BundleDiffHash $bundleHash -Index $Index
    $laneStatus = [string]$lane.status
    # (d) current-round gate records (tamper-verified reader), bound to THIS
    # exact plan-round + bundle hash.
    $gateRecords = Read-NeoClarityGateRecords -RunRoot $RunRoot -Index $Index
    $disclosures = @($gateRecords | Where-Object {
        ([string](Get-NeoProp $_ 'kind') -ceq 'unavailability_disclosure') -and
        ([string](Get-NeoProp $_ 'plan_round') -ceq $planRound) -and
        ([string](Get-NeoProp $_ 'bundle_diff_hash') -ceq $bundleHash) })
    $dispositions = @($gateRecords | Where-Object {
        ([string](Get-NeoProp $_ 'kind') -ceq 'directional_disposition') -and
        ([string](Get-NeoProp $_ 'plan_round') -ceq $planRound) -and
        ([string](Get-NeoProp $_ 'bundle_diff_hash') -ceq $bundleHash) })

    if ($laneStatus -ceq 'GO') {
      # presentation-only read of the verdict record (authority stays the lane).
      $verdict = Get-NeoClarityPlanVerdictRecord -RunRoot $RunRoot -PlanRound $planRound -BundleDiffHash $bundleHash -Index $Index
      return @{ state = 'READY'; reason = [string]$lane.reason; plan_round = $planRound
                bundle_diff_hash = $bundleHash; lane_status = $laneStatus; freeze = $freeze
                verdict_record = $verdict; disclosures = @(); dispositions = @() }
    }
    if ($laneStatus -ceq 'NO_GO') {
      if (@($dispositions).Count -ge 1) {
        $verdict = Get-NeoClarityPlanVerdictRecord -RunRoot $RunRoot -PlanRound $planRound -BundleDiffHash $bundleHash -Index $Index
        return @{ state = 'READY_WITH_DISCLOSURE'; plan_round = $planRound
                  reason = ('current-round plan verdict is NO_GO with a stamped directional-only disposition for this exact round+bundle - BOTH presented verbatim at the gate (conservatism never auto-blocks and is never hidden)')
                  bundle_diff_hash = $bundleHash; lane_status = $laneStatus; freeze = $freeze
                  verdict_record = $verdict; disclosures = @(); dispositions = @($dispositions) }
      }
      return @{ state = 'BLOCKED'; plan_round = $planRound; bundle_diff_hash = $bundleHash; lane_status = $laneStatus
                reason = 'current-round plan verdict is NO_GO and no stamped directional-only disposition exists for this exact round+bundle => plan defects require revision before the gate surfaces' }
    }
    # MISSING / STALE / UNPARSEABLE / ANY unrecognized lane (exhaustive default):
    # only an archived current-round unavailability disclosure lets the gate
    # surface (WITH the disclosure); otherwise THE GATE CANNOT SURFACE.
    if (@($disclosures).Count -ge 1) {
      return @{ state = 'READY_WITH_DISCLOSURE'; plan_round = $planRound
                reason = ('external lane is ' + $laneStatus + ' and an archived current-round unavailability disclosure exists for this exact round+bundle - disclosed at the gate, never silently skipped')
                bundle_diff_hash = $bundleHash; lane_status = $laneStatus; freeze = $freeze
                verdict_record = $null; disclosures = @($disclosures); dispositions = @() }
    }
    return @{ state = 'BLOCKED'; plan_round = $planRound; bundle_diff_hash = $bundleHash; lane_status = $laneStatus
              reason = ('external lane is ' + $laneStatus + ' and NEITHER an archived current-round plan verdict NOR an archived current-round unavailability disclosure exists => THE GATE CANNOT SURFACE (the addendum load-bearing rule); lane detail: ' + [string]$lane.reason) }
  } catch {
    # ANY derivation failure is BLOCKED, never READY (fail-closed).
    return @{ state = 'BLOCKED'; reason = ('gate-readiness derivation failed (fail-closed): ' + [string]$_.Exception.Message) }
  }
}

# presentation-only helper: the on-disk verdict record for the exact binding
# tuple (the lane derivation already proved uniqueness + stamp + correlation).
function Get-NeoClarityPlanVerdictRecord {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$PlanRound,
    [Parameter(Mandatory = $true)][string]$BundleDiffHash,
    $Index
  )
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')
  $path = Resolve-NeoRunStatePath $RunRoot 'external_verdict_ledger.jsonl'
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:external_audit_verdict' -Index $Index `
    -Label 'external_verdict_ledger' -ExpectedRunId $runId
  $hits = @($entries | Where-Object {
      ([string](Get-NeoProp $_ 'slice_id') -ceq $script:NeoClarityPlanSliceId) -and
      ([string](Get-NeoProp $_ 'round_id') -ceq $PlanRound) -and
      ([string](Get-NeoProp $_ 'bundle_diff_hash') -ceq $BundleDiffHash) })
  if (@($hits).Count -eq 1) { return @($hits)[0] }
  return $null
}

# ============================================================================
# (4b) THE GATE SURFACE (dispatch 3.A.4) - consumes ONLY the derivation
# ============================================================================
# On READY / READY_WITH_DISCLOSURE: fires a structural APPROVAL_NEEDED
# notification (convenience never authority; a send failure never blocks - the
# DEF-P8 contract is asserted by reuse, not re-derived) and returns the gate
# PRESENTATION PACKAGE (I4/NB-3: Raphael SEES the slice list AND the manifest
# coverage; a non-GO verdict and its disposition are BOTH presented verbatim).
# On BLOCKED: throws with the exact missing-artifact reason. There is NO
# parameter or code path that surfaces the gate while BLOCKED.
function Invoke-NeoClarityStartGate {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$SessionRoot,
    [string]$NotifyTestModeDir,
    [switch]$NotifyLiveSend,
    $Index
  )
  if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
  $r = Get-NeoClarityGateReadiness -RunRoot $RunRoot -SessionRoot $SessionRoot -Index $Index
  $state = [string]$r.state
  if (($state -cne 'READY') -and ($state -cne 'READY_WITH_DISCLOSURE')) {
    New-NeoBlock ("reason_code=CLARITY_GATE_NOT_READY START gate cannot surface: " + [string]$r.reason)
  }
  $freeze = $r.freeze
  # slice list + manifest coverage (what Raphael SEES, I4/NB-3).
  $sliceList = @()
  foreach ($s in @(Get-NeoClarityList $freeze 'slice_plan')) {
    $sliceList += [pscustomobject]@{
      slice_id        = [string](Get-NeoProp $s 'slice_id')
      approved_paths  = @(Get-NeoClarityList $s 'approved_paths')
      protected_paths = @(Get-NeoClarityList $s 'protected_paths')
      risk_row_ref    = [string](Get-NeoProp $s 'risk_row_ref')
    }
  }
  $govPinRef = Get-NeoProp $freeze 'gov_manifest_pin'
  $govPinMembers = $null
  try {
    $paths = Get-NeoClarityPlanAuditPaths $SessionRoot ([string](Get-NeoProp $freeze 'plan_round'))
    $pinDoc = Read-NeoJsonFile $paths.gov_pin_full
    $govPinMembers = @(Get-NeoClarityList $pinDoc 'members').Count
  } catch { $govPinMembers = $null }   # presentation detail only; the pin hash rides regardless
  $package = @{
    state                 = $state
    plan_round            = [string]$r.plan_round
    bundle_diff_hash      = [string]$r.bundle_diff_hash
    instruction_digest_ref = [string](Get-NeoProp $freeze 'instruction_digest_ref')
    slice_list            = @($sliceList)
    manifest_coverage     = @{
      gov_manifest_pin  = $govPinRef
      gov_pin_member_count = $govPinMembers
      app_manifest_pin  = (Get-NeoProp $freeze 'app_manifest_pin')
      risk_register_pin = (Get-NeoProp $freeze 'risk_register_pin')
    }
    risk_rows             = @(Get-NeoClarityList $freeze 'risk_rows')
    judging_registrations = @(Get-NeoClarityList $freeze 'judging_registrations')
    attestation_records   = @(Get-NeoClarityList $freeze 'attestation_records')
    ambiguity_register    = @(Get-NeoClarityList $freeze 'ambiguity_register')
    plan_verdict          = $r.verdict_record
    plan_disclosures      = @($r.disclosures)
    plan_dispositions     = @($r.dispositions)
    notification          = $null
  }
  # structural notification - the engine analog of the standing manager rule.
  # Convenience NEVER authority: any failure (refusal, throw) is captured into
  # the package and never blocks the surfaced gate. The summary NAMES the exact
  # bound plan bundle: honest gate content AND a per-run-unique dedupe identity
  # (DEF-P8 dedupes on gate+slice+summary sha inside a 10-minute window; a
  # generic summary would falsely dedupe distinct runs' gates).
  $summary = @(
    ('C5 START gate ready: ' + $state),
    ('plan_round ' + [string]$r.plan_round + '; slices ' + @($sliceList).Count),
    ('lane ' + [string]$r.lane_status),
    ('plan bundle sha256 ' + [string]$r.bundle_diff_hash)
  )
  try {
    $nArgs = @{ GateType = 'APPROVAL_NEEDED'; SliceId = $script:NeoClarityPlanSliceId
                SummaryLines = $summary; EvidencePath = $RunRoot }
    if (-not [string]::IsNullOrWhiteSpace($NotifyTestModeDir)) { $nArgs['TestModeDir'] = $NotifyTestModeDir }
    elseif ($NotifyLiveSend) { $nArgs['LiveSend'] = $true }
    $package.notification = Send-NeoGateNotification @nArgs
  } catch {
    $package.notification = @{ sent = $false; deduped = $false; refused = $true
                               reason = ('notify threw (never blocks a gate): ' + [string]$_.Exception.Message); composed_path = $null }
  }
  return $package
}

# ============================================================================
# (5) THE S3c COMPLETENESS CARRY (dispatch 3.A.5)
# ============================================================================
# The FROZEN PLAN is the slice-universe authority: derive the planned ids from
# the LATEST freeze (hash-verified read) and assert them against the run's
# recorded evidence via the FROZEN Assert-NeoLoopRunSliceUniverse. A planned
# slice that never recorded round 0 => EXTRA BLOCK; a recorded slice missing
# from the frozen plan => OMISSION BLOCK (an unplanned slice is equally a trail
# defect). orch_loop.ps1 is not dot-sourced here (mutual-source recursion hazard
# at integrate); its absence is a fail-closed BLOCK, never a skip.
function Assert-NeoClarityPlanSliceUniverse {
  param(
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedRunId,
    $Index
  )
  if ($null -eq (Get-Command 'Assert-NeoLoopRunSliceUniverse' -ErrorAction SilentlyContinue)) {
    New-NeoBlock "reason_code=CLARITY_UNIVERSE completeness carry: the frozen Assert-NeoLoopRunSliceUniverse is not loaded (orch_loop.ps1 must be sourced by the caller) => STOP (fail-closed, never skipped)"
  }
  $freeze = Get-NeoClarityLatestFreeze -RunRoot $RunRoot -Index $Index
  $ids = @()
  foreach ($s in @(Get-NeoClarityList $freeze 'slice_plan')) { $ids += [string](Get-NeoProp $s 'slice_id') }
  if (@($ids).Count -lt 1) {
    New-NeoBlock "reason_code=CLARITY_UNIVERSE completeness carry: the frozen plan names no slices => STOP"
  }
  return (Assert-NeoLoopRunSliceUniverse -RunRoot $RunRoot -ExpectedRunId $ExpectedRunId -CallerSliceIds $ids)
}
