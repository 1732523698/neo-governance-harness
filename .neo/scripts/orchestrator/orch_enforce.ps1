# orch_enforce.ps1 - NEO 4.0-P3-B2a enforcement layer (COORDINATION only).
# ASCII-only (D10). Dot-source; defines functions only.
#
# CROWN JEWEL (coordinate-not-validate, v4 5.1): every function here is COORDINATION -
# select an audit tier, bind a human gate, route an edit by artifact class. NONE writes
# an AUDIT_RESULT or a GO. The audit itself stays the SEPARATE isolated auditor
# (orch_auditor_stub.ps1). This library contains NO 'rehash_check' result literal and
# never references/invokes the auditor stub (structural guards G3c/G3d extended to it).
#
# SCOPE B2a: E1 tiered audit (D4), E2 human-gate binding (D5), E3 model-routing
# fail-closed (D6). E4 rollback/dependent-continuation and E5 rollover are B2b (NOT here).
# SCOPE slice-2 (P3-D): E6 auditor-slot seam (D4) - engine-side fail-closed enforcement of
# SUBSESSION_END_REPORT.auditor_recommendation_slot. Read-only; consumes, never authors.
. "$PSScriptRoot\orch_io.ps1"

# ============================================================================
# E1 - TIERED AUDIT (D4 / neo:risk_register / neo:subsession_index)
# ============================================================================
# Select lightweight | isolated | full_isolated from the RISK_REGISTER row. Fail-closed:
# risk_class missing/UNKNOWN => BLOCK; HIGH is never lightweight; MEDIUM defaults ISOLATED
# and may be lightweight ONLY with a complete explicit_downgrade record; dev->prod release
# is always full_isolated. There is NO silent downgrade path (T2).
function Resolve-NeoAuditTier {
  param($RiskRow, [switch]$IsDevProdRelease)
  if ($IsDevProdRelease) { return 'full_isolated' }   # every dev->prod release, D4 sec5
  if ($null -eq $RiskRow) { New-NeoBlock "audit-tier: RISK_REGISTER row required to select tier => BLOCK (A7, D4)" }

  $rc = [string](Get-NeoProp $RiskRow 'risk_class')
  if ([string]::IsNullOrWhiteSpace($rc)) { New-NeoBlock "audit-tier: risk_class missing/UNKNOWN => BLOCK (A7, D4)" }
  if (@('high', 'medium', 'low') -notcontains $rc) { New-NeoBlock "audit-tier: unknown risk_class '$rc' => BLOCK (A7, D4)" }
  $rowTier = [string](Get-NeoProp $RiskRow 'audit_tier')

  switch ($rc) {
    'low'  { return 'lightweight' }
    'high' {
      if ($rowTier -eq 'lightweight') { New-NeoBlock "audit-tier: HIGH risk with audit_tier='lightweight' => BLOCK (high is never lightweight, D4)" }
      return 'isolated'
    }
    'medium' {
      if ($rowTier -eq 'lightweight') {
        $dg = Get-NeoProp $RiskRow 'explicit_downgrade'
        # Single load-bearing guard (T2): a MEDIUM sub-session is lightweight-audited ONLY
        # with a COMPLETE explicit_downgrade record. No record / incomplete => BLOCK. There
        # is no silent fall-through to the cheap tier.
        if (-not (Test-NeoDowngradeComplete $dg)) { New-NeoBlock "audit-tier: MEDIUM risk with audit_tier='lightweight' and no complete explicit_downgrade {reason,authority,timestamp,scope} => BLOCK (T2 no silent fall-through, D4)" }
        return 'lightweight'
      }
      return 'isolated'   # MEDIUM default
    }
  }
}

# A downgrade record is COMPLETE iff it exists and all four required subfields are non-empty.
# (The schema already requires the four keys IF the object is present; this also rejects a
# present-but-null object and any all-blank field - defence in depth.)
function Test-NeoDowngradeComplete($dg) {
  if ($null -eq $dg) { return $false }
  foreach ($f in @('reason', 'authority', 'timestamp', 'scope')) {
    $v = [string](Get-NeoProp $dg $f)
    if ([string]::IsNullOrWhiteSpace($v)) { return $false }
  }
  return $true
}

# ============================================================================
# E2 - HUMAN-GATE BINDING (D5 / neo:human_gate_ledger)
# ============================================================================
# The Q6-ratified never-batchable / exact-inspection set - DOCUMENTATION ONLY. The sensitivity
# DECISION in Assert-NeoGateBound is `area -cne 'general_feature'` (fail-closed: unknown/blank
# areas are sensitive), NOT membership in this list. Every area except general_feature is sensitive.
$script:NeoSensitiveAreas = @(
  'security', 'payment', 'data_migration', 'deploy', 'root_of_trust', 'constraints',
  'harness_tests', 'audit_rubrics', 'risk_profile', 'artifact_classification',
  'release_authenticity', 'prod_export_promotion'
)

# Structural fail-closed shape guard for a HUMAN_GATE_LEDGER (residual (c) fold, B2b). Turns a
# MALFORMED ledger (e.g. a null entry, or an entry missing a required key) into a CLEAN NEO-BLOCK
# instead of a raw crash deeper in the gate-binding path. This mirrors the neo:human_gate_ledger
# shape invariants WITHOUT depending on the $id-keyed schema index (that schema carries no $id, so
# Get-NeoSchemaIndex does not register it and Assert-NeoValid cannot reach it - see B2b note).
function Assert-NeoGateLedgerShape($Led) {
  if (-not (Test-NeoHasProp $Led 'entries')) { New-NeoBlock "gate-binding: ledger has no 'entries' array => BLOCK (A7)" }
  foreach ($e in @(Get-NeoProp $Led 'entries')) {
    if ($null -eq $e) { New-NeoBlock "gate-binding: ledger contains a null entry => BLOCK (malformed ledger, A7, D5)" }
    foreach ($k in @('gate_ref', 'gate_kind', 'authorized_by', 'recorded_at', 'app_slug', 'authorized_paths')) {
      if (-not (Test-NeoHasProp $e $k)) { New-NeoBlock "gate-binding: ledger entry missing required '$k' => BLOCK (malformed ledger, A7, D5)" }
    }
  }
}

# The ledger PATH is an explicit required argument. Tests MUST pass a FIXTURE-LOCAL ledger;
# the live .neo/gates/HUMAN_GATE_LEDGER.json is never a default here (its entries are empty).
# Residual (c) FOLD (B2b): when the caller supplies the schema $Index (the E4b bind path does),
# the ledger is validated ON LOAD so a malformed ledger fails as a CLEAN NEO-BLOCK, not a raw
# crash later. Full schema validation is used IFF the index actually registers the ledger schema
# (forward-compatible - neo:human_gate_ledger has no $id today, so it is not indexed); otherwise a
# structural shape guard covers the same invariants. The $Index parameter is OPTIONAL and defaults
# to $null: WITHOUT it the pre-existing lightweight 'entries'-presence check is retained UNCHANGED,
# so every B1/B2a caller is byte-behaviour-identical (the frozen enforce suite stays 48/48).
function Read-NeoGateLedger([string]$LedgerPath, $Index = $null) {
  if ([string]::IsNullOrWhiteSpace($LedgerPath)) { New-NeoBlock "gate-binding: ledger path required (tests bind a fixture-local ledger, never the live empty ledger) => BLOCK (D5)" }
  $led = Read-NeoJsonFile $LedgerPath
  if ($null -ne $Index) {
    if ($Index.ContainsKey('neo:human_gate_ledger')) { Assert-NeoValid $led 'neo:human_gate_ledger' $Index 'HUMAN_GATE_LEDGER' }
    Assert-NeoGateLedgerShape $led
  }
  if (-not (Test-NeoHasProp $led 'entries')) { New-NeoBlock "gate-binding: ledger has no 'entries' array => BLOCK (A7)" }
  return $led
}

# A repo-relative authorized path covers a scope path if equal, a directory prefix, or a
# glob match. Root-relative './...' normalized; backslashes normalized to forward slashes.
function Test-NeoPathCovered([string]$auth, [string]$scope) {
  $a = ($auth  -replace '\\', '/') -replace '^\./', ''
  $s = ($scope -replace '\\', '/') -replace '^\./', ''
  if ($a -eq $s) { return $true }
  $aDir = $a.TrimEnd('/')
  if ($s -eq $aDir) { return $true }
  if ($s.StartsWith($aDir + '/')) { return $true }
  if ($a -match '[*?]') { return (Test-NeoGlobMatch $s $a) }
  return $false
}

# Resolve a gate_ref against the ledger. Fail-closed order: missing => BLOCK; not found =>
# BLOCK(unmatched); app_slug/authorized_paths do not cover the scope => BLOCK(unmatched-scope);
# expired (lowest priority) => BLOCK. Returns the matched entry.
function Resolve-NeoGate {
  param($Ledger, [string]$GateRef, [string]$AppSlug, [string[]]$ScopePaths, [string]$AsOf, [int]$MaxAgeDays = 0)
  # A missing gate_ref is a special case of 'unmatched': an empty ref matches no ledger
  # entry (gate_ref has minLength 1 in the schema), so the not-found guard below is the
  # single load-bearing barrier covering BOTH missing and unmatched.
  $match = $null
  if (-not [string]::IsNullOrWhiteSpace($GateRef)) {
    foreach ($e in @($Ledger.entries)) {
      if ([string](Get-NeoProp $e 'gate_ref') -ceq $GateRef) { $match = $e; break }
    }
  }
  if ($null -eq $match) { New-NeoBlock "gate-binding: gate_ref '$GateRef' missing/not found in ledger => BLOCK (missing-or-unmatched, D5)" }

  if ($AppSlug) {
    if ([string](Get-NeoProp $match 'app_slug') -cne $AppSlug) { New-NeoBlock "gate-binding: gate_ref '$GateRef' app_slug mismatch (want '$AppSlug') => BLOCK (unmatched-scope, D5)" }
  }
  # F2 fail-closed: a BOUND gate must authorize a DECLARED scope. Empty/blank ScopePaths on a
  # bound gate => BLOCK; the coverage loop then ALWAYS runs for a gated dispatch (no silent skip).
  # The `$null -ne $match` gate is defensive ordering: in production $match is ALWAYS non-null here
  # because the not-found guard above blocked every unmatched gate_ref first, so this never fires
  # on a real unmatched dispatch (it is not a fail-open) - it only stays null-safe if the not-found
  # guard is neutered on a copy, keeping that guard independently load-bearing.
  $scopes = @($ScopePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if (($null -ne $match) -and ($scopes.Count -eq 0)) { New-NeoBlock "gate-binding: gate_ref '$GateRef' bound with no declared scope paths => BLOCK (a gate must authorize a declared scope, D5)" }
  # Coverage runs iff there is a declared scope; F2 above guarantees a BOUND gate has one, so
  # this is never skipped in production. ($auth is read only inside, keeping it null-safe when
  # the not-found guard is neutered on a copy and $match is null.)
  if ($scopes.Count -gt 0) {
    $auth = @(Get-NeoProp $match 'authorized_paths')
    foreach ($sp in $scopes) {
      $covered = $false
      foreach ($ap in $auth) { if (Test-NeoPathCovered ([string]$ap) ([string]$sp)) { $covered = $true; break } }
      if (-not $covered) { New-NeoBlock "gate-binding: scope path '$sp' not covered by gate_ref '$GateRef' authorized_paths => BLOCK (unmatched-scope, D5)" }
    }
  }
  # Expiry: bind-layer freshness, NO schema field. recorded_at + MaxAgeDays < AsOf => expired.
  if ($MaxAgeDays -gt 0 -and $AsOf) {
    $recStr = [string](Get-NeoProp $match 'recorded_at')
    $recDate = [datetime]::MinValue; $asOfDate = [datetime]::MinValue
    if (-not [datetime]::TryParse($recStr, [ref]$recDate)) { New-NeoBlock "gate-binding: gate_ref '$GateRef' recorded_at '$recStr' unparseable => BLOCK (A7)" }
    if (-not [datetime]::TryParse($AsOf,   [ref]$asOfDate)) { New-NeoBlock "gate-binding: -AsOf '$AsOf' unparseable => BLOCK (A7)" }
    if ($recDate.AddDays($MaxAgeDays) -lt $asOfDate) { New-NeoBlock "gate-binding: gate_ref '$GateRef' expired (recorded_at $recStr + ${MaxAgeDays}d < $AsOf) => BLOCK (D5)" }
  }
  return $match
}

# Top-level E2 gate decision for a dispatch. Sensitive areas REQUIRE an explicit gate and
# may NOT be batched. general_feature must declare EITHER -Batched OR a bindable gate_ref
# (fail-closed: declaring neither is a BLOCK - the handling mode must be explicit).
function Assert-NeoGateBound {
  param(
    $RiskRow, [string]$GateRef, $Ledger, [string]$AppSlug, [string[]]$ScopePaths,
    [string]$AsOf, [int]$MaxAgeDays = 0, [switch]$Batched
  )
  if ($null -eq $RiskRow) { New-NeoBlock "gate-binding: RISK_REGISTER row required => BLOCK (A7)" }
  $area = [string](Get-NeoProp $RiskRow 'area')
  # F1 fail-closed: a MISSING/BLANK area cannot be classified => BLOCK (never defaults open).
  if ([string]::IsNullOrWhiteSpace($area)) { New-NeoBlock "gate-binding: RISK_REGISTER row area missing/blank => cannot classify => BLOCK (A7, D5)" }
  $neverBatch = [bool](Get-NeoProp $RiskRow 'never_batchable')
  # F1 fail-closed sensitivity DECISION: ONLY the exact 'general_feature' area is batchable-
  # eligible; EVERY other area - whether in the known-sensitive set OR unknown/crafted - is
  # sensitive and requires an explicit bound gate. never_batchable may only ADD sensitivity,
  # never remove it (a general_feature with never_batchable=true is sensitive). $NeoSensitiveAreas
  # is the DOCUMENTED ratified set (below), not the decision - a missing area never defaults open.
  $sensitive = ($area -cne 'general_feature') -or $neverBatch

  if ($sensitive) {
    if ($Batched) { New-NeoBlock "gate-binding: sensitive area '$area' presented as batched => BLOCK (never-batchable set, D5)" }
    return (Resolve-NeoGate -Ledger $Ledger -GateRef $GateRef -AppSlug $AppSlug -ScopePaths $ScopePaths -AsOf $AsOf -MaxAgeDays $MaxAgeDays)
  }
  # general_feature (the only batchable-eligible area)
  if ($Batched) { return $null }   # batched + logged (the master records it in the index)
  if (-not [string]::IsNullOrWhiteSpace($GateRef)) {
    return (Resolve-NeoGate -Ledger $Ledger -GateRef $GateRef -AppSlug $AppSlug -ScopePaths $ScopePaths -AsOf $AsOf -MaxAgeDays $MaxAgeDays)
  }
  New-NeoBlock "gate-binding: general_feature dispatch declared neither -Batched nor a gate_ref => BLOCK (declare handling mode, D5)"
}

# ============================================================================
# E3 - MODEL-ROUTING FAIL-CLOSED (D6 / artifact_classes.json / neo:model_routing_log)
# ============================================================================
$script:NeoJudgingClasses = @('constraint', 'test_harness', 'profile_risk')

# Capability ranks. Producer axis: cheap < strong. Validator axis: validator < auditor.
# The two axes share a scale so 'validator >= producer' is comparable (D6): a strong_producer
# (2) needs at least a validator (2); a judging/audit edit needs an auditor (3).
function Get-NeoProducerRank([string]$c) {
  switch ($c) { 'cheap_producer' { return 1 } 'strong_producer' { return 2 } default { New-NeoBlock "routing: unknown producer_class '$c' => BLOCK (A7, D6)" } }
}
function Get-NeoValidatorRank([string]$c) {
  # Shared ladder with the producer axis so 'validator >= producer' is comparable: a plain
  # 'validator' has baseline capability 1 (adequate for a cheap_producer's low-risk work); an
  # 'auditor' has capability 2. A strong_producer (2) therefore needs an auditor-class validator.
  switch ($c) { 'validator' { return 1 } 'auditor' { return 2 } default { New-NeoBlock "routing: unknown validator_class '$c' => BLOCK (A7, D6)" } }
}

# Route a proposed edit. Fail-closed: UNKNOWN class => BLOCK (default_class NOT consumed);
# cheap_producer editing a judging class => BLOCK; cheap_producer on non-low risk => BLOCK;
# missing routing entry or empty validator_adequacy_rationale => BLOCK; validator<producer =>
# BLOCK; a judging-class edit requires an independent auditor-class validator.
function Assert-NeoRouteEdit {
  param($ClassMap, [string]$TargetPath, [string]$ProducerClass, [string]$TaskRisk, $RoutingEntry)
  $class = Assert-NeoResolvableClass $ClassMap $TargetPath   # UNKNOWN => throws NEO-BLOCK
  $judging = ($script:NeoJudgingClasses -contains $class)

  if ($judging -and ($ProducerClass -eq 'cheap_producer')) {
    New-NeoBlock "routing: cheap_producer editing judging-class '$class' target '$TargetPath' => BLOCK (route to gated constraint-edit session, D6/A4)"
  }
  if (($ProducerClass -eq 'cheap_producer') -and ($TaskRisk -ne 'low')) {
    New-NeoBlock "routing: cheap_producer with task_risk='$TaskRisk' (!= low) => BLOCK (cheap produces low-risk only, D6)"
  }
  if ($null -eq $RoutingEntry) { New-NeoBlock "routing: MODEL_ROUTING_LOG entry required => BLOCK (A7, D6)" }

  $rationale = [string](Get-NeoProp $RoutingEntry 'validator_adequacy_rationale')
  if ([string]::IsNullOrWhiteSpace($rationale)) { New-NeoBlock "routing: empty validator_adequacy_rationale => BLOCK (A7, D6)" }

  $pc = [string](Get-NeoProp $RoutingEntry 'producer_class')
  $vc = [string](Get-NeoProp $RoutingEntry 'validator_class')
  if ($pc -cne $ProducerClass) { New-NeoBlock "routing: producer_class param '$ProducerClass' != routing entry producer_class '$pc' => BLOCK (split-brain, A7)" }
  $pr = Get-NeoProducerRank $pc
  $vr = Get-NeoValidatorRank $vc
  if ($vr -lt $pr) { New-NeoBlock "routing: validator_class '$vc' (rank $vr) < producer_class '$pc' (rank $pr) => BLOCK (D6 validator>=producer)" }
  if ($judging -and ($vc -ne 'auditor')) {
    New-NeoBlock "routing: judging-class edit requires validator_class='auditor' (independent), got '$vc' => BLOCK (D6)"
  }
  return @{ class = $class; judging = $judging }
}

# ============================================================================
# DISPATCH PRECONDITION (B2a wiring): E2 -> E3 -> E1, all fail-closed.
# E4 (rollback/dependent-continuation) is NOT here - it ships with its wiring in B2b.
# ============================================================================
function Assert-NeoDispatchAllowed {
  param(
    $RiskRow, $ClassMap, $Ledger,
    [string]$GateRef, [string]$AppSlug, [string[]]$ScopePaths, [switch]$Batched,
    [string]$AsOf, [int]$MaxAgeDays = 0,
    $ProposedEdits,          # array of @{ path; producer_class; task_risk; routing_entry }
    [switch]$IsDevProdRelease
  )
  if ($null -eq $RiskRow) { New-NeoBlock "dispatch: RISK_REGISTER row required => BLOCK (A7)" }

  # E2: bind the human gate for this dispatch.
  $gate = Assert-NeoGateBound -RiskRow $RiskRow -GateRef $GateRef -Ledger $Ledger -AppSlug $AppSlug `
    -ScopePaths $ScopePaths -AsOf $AsOf -MaxAgeDays $MaxAgeDays -Batched:$Batched

  # E3: route every proposed edit by artifact class.
  foreach ($pe in @($ProposedEdits)) {
    if ($null -eq $pe) { continue }
    Assert-NeoRouteEdit -ClassMap $ClassMap -TargetPath ([string]$pe.path) `
      -ProducerClass ([string]$pe.producer_class) -TaskRisk ([string]$pe.task_risk) `
      -RoutingEntry $pe.routing_entry | Out-Null
  }

  # E1: select (and return) the audit tier this sub-session's END must satisfy.
  $tier = Resolve-NeoAuditTier -RiskRow $RiskRow -IsDevProdRelease:$IsDevProdRelease

  return @{ gate = $gate; audit_tier = $tier }
}

# ============================================================================
# TIER-RECORDING INDEX HELPER (E1): append a record carrying audit_tier_applied, then
# re-validate the whole SUBSESSION_INDEX (so its schema conditionals fire on every write).
# This is coordination only; it implements NO dependent-continuation logic (that is E4/B2b).
# ============================================================================
function Add-NeoIndexRecord {
  param($SubIndex, $Record, $Index, [string]$Timestamp)
  if ($null -eq $Record) { New-NeoBlock "index-append: record required => BLOCK" }
  $recs = @(@($SubIndex.records) + $Record)
  $SubIndex.records = $recs
  if ($Timestamp) {
    $prov = Get-NeoProp $SubIndex '_provenance'
    if ($prov) { $prov.updated_at = $Timestamp }
  }
  Set-NeoArtifactHash $SubIndex
  Assert-NeoValid $SubIndex 'neo:subsession_index' $Index 'SUBSESSION_INDEX(append)'
  return $SubIndex
}

# ============================================================================
# E6 - AUDITOR-SLOT SEAM (slice-2 / D4 / neo:subsession_end_report)
# ============================================================================
# Engine-side fail-closed enforcement of the END report's auditor_recommendation_slot.
# The schema states in prose "a high-risk END with null here => cannot pass (D4)" - this
# seam is that enforcement. COORDINATION ONLY (crown jewel v4 5.1): the seam READS and
# BLOCKS. It never writes the slot, never writes a verdict artifact, never synthesizes a
# recommendation. The slot is filled OUTSIDE the engine (by the master/coordinator, from
# the separately-consumed verdict); its trust comes ONLY from re-validating - via the
# REUSED Read-NeoAuditResult (independent member re-hash + auditor!=master!=builder +
# tier binding) - the verdict artifact its bundle_ref points at, never from the slot's
# own builder-rideable bytes. A bare {recommendation:"GO",...} with no real audit behind
# it is REJECTED.
#
# Fail-closed map (default-case-is-the-threat, A7):
#   blank/missing/unknown risk_class      => BLOCK (inside the reused Resolve-NeoAuditTier)
#   required tier + null/absent slot      => BLOCK (the D4 prose, now enforced)
#   malformed slot (validated whether or not required) => BLOCK
#   unsafe/uncontained bundle_ref or end_report member path => BLOCK (F2, before any join/read)
#   missing bundle / missing sibling AUDIT_RESULT.json      => BLOCK
#   bundle end_report members != exactly one canonical role => BLOCK (mislabel/enumeration dodge)
#   bundle end_report body != this subsession's END (slot-invariant id) => BLOCK (transplant/craft)
#   any Read-NeoAuditResult BLOCK         => propagate
#   re-validated verdict/auditor != slot  => BLOCK (forged/stale slot)
# GO-path: returns the re-validated verdict; ACTING on GO vs NEEDS-MORE vs NO-GO stays the
# caller's/human's separate decision - the seam enforces trustworthiness only.
function Assert-NeoAuditorSlotSatisfied {
  param(
    $RiskRow, [switch]$IsDevProdRelease,
    $EndReport,                 # the already-ingested SUBSESSION_END_REPORT object (read-only here)
    [string]$SessionRoot,       # containment root the bundle members resolve under (== consume BundleDir)
    [string]$MasterIdentity, [string]$BuilderIdentity, $Index,
    [string]$RequiredTierFloor  # NB-1 (C6): OPTIONAL escalate-only floor; absent/empty = current behavior
  )
  if ($null -eq $EndReport) { New-NeoBlock "auditor-slot: END report object required => BLOCK (A7)" }
  if ([string]::IsNullOrWhiteSpace($SessionRoot)) { New-NeoBlock "auditor-slot: SessionRoot required => BLOCK (A7)" }

  # (1) requiredness via the REUSED tier oracle - no parallel tier map. Blank/missing/unknown
  # risk BLOCKS inside the oracle (never assume low); HIGH resolves to isolated => required.
  $tier = Resolve-NeoAuditTier -RiskRow $RiskRow -IsDevProdRelease:$IsDevProdRelease

  # (1a) NB-1 (C6 no-auditor-vacuum): OPTIONAL escalate-only tier floor. The ladder below
  # is an ORDERING for the escalate-only max ONLY - NOT a parallel tier-selection map;
  # tier SELECTION stays the oracle's (Resolve-NeoAuditTier, above). A non-empty floor
  # must be a known tier, case-EXACT (mirrors Read-NeoAuditResult's F3 fail-closed
  # pattern; unknown => BLOCK, never silently treated as no-floor). The max can RAISE
  # but NEVER lower $tier, so requiredness (below), the null-slot early-return AND the
  # -RequiredTier handed to Read-NeoAuditResult all see the EFFECTIVE tier: a null slot
  # on a LOW row under floor 'isolated' now BLOCKS (the I1 vacuum closed).
  if (-not [string]::IsNullOrEmpty($RequiredTierFloor)) {
    if (@('lightweight', 'isolated', 'full_isolated') -cnotcontains $RequiredTierFloor) {
      New-NeoBlock "auditor-slot: unknown -RequiredTierFloor '$RequiredTierFloor' (not lightweight|isolated|full_isolated) => BLOCK (NB-1/D4/A7)"
    }
    $tierLadder = @{ lightweight = 0; isolated = 1; full_isolated = 2 }   # ORDERING for max, not a tier map
    if ($tierLadder[$RequiredTierFloor] -gt $tierLadder[$tier]) { $tier = $RequiredTierFloor }
  }

  $required = (($tier -ceq 'isolated') -or ($tier -ceq 'full_isolated'))

  # (2) required + null/absent slot => the END cannot pass (D4). Not-required + null passes
  # (no over-block on a lightweight-tier subsession that was never isolation-audited).
  $slot = Get-NeoProp $EndReport 'auditor_recommendation_slot'
  if ($null -eq $slot) {
    if ($required) { New-NeoBlock "auditor-slot: audit_tier '$tier' requires an isolated auditor verdict but auditor_recommendation_slot is null => END cannot pass (D4/A7)" }
    return @{ required = $false; satisfied = $true; recommendation = $null; auditor_identity = $null; bundle_ref = $null; effective_tier = $tier }
  }

  # (3) a PRESENT slot is validated whether or not required - a forged slot must never read
  # valid just because the tier happened to be cheap.
  $slotRec = [string](Get-NeoProp $slot 'recommendation')
  if (@('GO', 'NEEDS-MORE', 'NO-GO') -cnotcontains $slotRec) { New-NeoBlock "auditor-slot: slot recommendation '$slotRec' not in GO|NEEDS-MORE|NO-GO => BLOCK (A7)" }
  $slotAud = [string](Get-NeoProp $slot 'auditor_identity')
  if ([string]::IsNullOrWhiteSpace($slotAud)) { New-NeoBlock "auditor-slot: slot auditor_identity blank/missing => BLOCK (A7)" }
  $slotRef = [string](Get-NeoProp $slot 'bundle_ref')
  if ([string]::IsNullOrWhiteSpace($slotRef)) { New-NeoBlock "auditor-slot: slot bundle_ref blank/missing => BLOCK (A7)" }

  # (4) bundle_ref is FREE-FORM builder input: safe-rel + containment BEFORE any join/read
  # (F2; rooted/drive/UNC/backslash/../empty/escape => BLOCK). Then the bundle itself must be
  # schema-valid with intact envelope + packet self-hash (a crafted bundle fails here).
  Assert-NeoSafeRel $slotRef; $bundleFull = Assert-NeoContained $SessionRoot $slotRef
  if (-not (Test-Path -LiteralPath $bundleFull)) { New-NeoBlock "auditor-slot: bundle_ref '$slotRef' resolves to no file => BLOCK (A7)" }
  $bundle = Read-NeoJsonFile $bundleFull
  Assert-NeoValid $bundle 'neo:input_packet' $Index 'AUDIT_BUNDLE(slot bundle_ref)'
  Assert-NeoArtifactHash $bundle 'AUDIT_BUNDLE(slot bundle_ref)'
  Assert-NeoPacketSelfHash $bundle 'AUDIT_BUNDLE(slot bundle_ref)'

  # (E1) authoritative-end_report integrity (fix-2 carried residual): EXACTLY ONE member may
  # carry the end_report role, counted CASE-INSENSITIVELY so a miscased twin cannot dodge
  # enumeration, and that one member's role must be the exact canonical label.
  $endMembers = @(@($bundle.allowlist) | Where-Object { ([string](Get-NeoProp $_ 'role')) -ieq 'end_report' })
  if ($endMembers.Count -ne 1) { New-NeoBlock "auditor-slot: bundle must carry exactly one end_report member, found $($endMembers.Count) (mislabel/enumeration dodge) => BLOCK (A7)" }
  $emRole = [string](Get-NeoProp $endMembers[0] 'role')
  if ($emRole -cne 'end_report') { New-NeoBlock "auditor-slot: end_report member role '$emRole' is miscased (must be exactly 'end_report') => BLOCK (A7)" }

  # (E2) the audited end_report must BE this subsession's END: compare slot-invariant body ids
  # (body hash excluding _provenance/self_hash/auditor_recommendation_slot), so the audit-time
  # null-slot copy and the post-audit filled END agree iff everything else is identical. A
  # crafted flattering END or a transplanted foreign subsession's END fails here.
  $emRel = [string](Get-NeoProp $endMembers[0] 'path')
  Assert-NeoSafeRel $emRel; $emFull = Assert-NeoContained $SessionRoot $emRel
  if (-not (Test-Path -LiteralPath $emFull)) { New-NeoBlock "auditor-slot: bundle end_report member '$emRel' missing on disk => BLOCK (A7)" }
  $slotInvariantExclude = @('_provenance', 'self_hash', 'auditor_recommendation_slot')
  $liveEndId = Get-NeoBodyHash $EndReport $slotInvariantExclude
  $bundEndId = Get-NeoBodyHash (Read-NeoJsonFile $emFull) $slotInvariantExclude
  if ($bundEndId -cne $liveEndId) { New-NeoBlock "auditor-slot: bundle end_report is not this subsession's END (slot-invariant body id mismatch) => BLOCK (transplant/craft, A7)" }

  # (5) the verdict artifact is the SIBLING of the bundle (schema _home convention:
  # AUDIT_RESULT.json beside AUDIT_BUNDLE.json); absent => BLOCK. Re-validation is the REUSED
  # Read-NeoAuditResult - its independent member re-hash, auditor/master/builder separation and
  # tier binding all run again here; any of its BLOCKs propagates. No duplication of its logic.
  $arPath = Join-Path (Split-Path -Parent $bundleFull) 'AUDIT_RESULT.json'
  if (-not (Test-Path -LiteralPath $arPath)) { New-NeoBlock "auditor-slot: no AUDIT_RESULT.json beside bundle '$slotRef' => BLOCK (D4/A7)" }
  $validated = Read-NeoAuditResult -AuditResultPath $arPath -Bundle $bundle -BundleDir $SessionRoot `
    -MasterIdentity $MasterIdentity -BuilderIdentity $BuilderIdentity -Index $Index -RequiredTier $tier

  # (6) the slot must MATCH the re-validated verdict - a slot that says GO over an artifact
  # that re-validates to anything else is forged/stale, whoever wrote it.
  if (([string]$validated.recommendation) -cne $slotRec) { New-NeoBlock "auditor-slot: slot recommendation '$slotRec' != re-validated verdict '$($validated.recommendation)' => forged/stale slot => BLOCK (A7)" }
  if (([string]$validated.auditor_identity) -cne $slotAud) { New-NeoBlock "auditor-slot: slot auditor_identity '$slotAud' != verdict auditor_identity '$($validated.auditor_identity)' => BLOCK (A7)" }

  return @{ required = $required; satisfied = $true; recommendation = $slotRec; auditor_identity = $slotAud; bundle_ref = $slotRef; effective_tier = $tier }
}
