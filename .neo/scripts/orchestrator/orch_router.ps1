# orch_router.ps1 - NEO 4.0-P4-AUTONOMY C6 risk-tier router (COORDINATION only).
# ASCII-only (D10). Dot-source; defines functions only.
#
# CROWN JEWEL (coordinate-not-validate, v4 5.1): every function here is COORDINATION -
# it gates profile completeness, refuses ineligible autonomous risk rows, and re-derives
# risk from the ACTUAL diff, escalate-only. NONE writes an AUDIT_RESULT or a GO. The
# audit itself stays the SEPARATE isolated auditor; this library contains NO
# 'rehash_check' result literal and never references/invokes the auditor stub
# (structural guards G3c/G3d extended to it).
#
# SCOPE C6 (NEO_SELF_ITERATION_DESIGN_v3_1.md section 4, SHA 0F4C8B81):
#   - frozen authority (I4): slice plan / boundary-to-row mapping / risk rows are
#     C5-frozen; NOTHING here writes or modifies a row - rows are consumed read-only.
#   - diff-time re-derive (I4): risk independently re-derived from the profile's
#     denylist + risk_tokens applied to the ACTUAL changed set; ESCALATE-ONLY - a
#     higher derived class is a STOP (the supervisor surfaces + re-audits at the
#     higher tier in C1/C3); a lower derived class NEVER downgrades the frozen row.
#   - profile completeness fail-closed (N1/NF-4): denylist OR risk_tokens starved =>
#     BLOCK unless THAT SPECIFIC gap is C5-attested; the engine minimum governed-token
#     set is MANDATORILY UNIONED into every re-derive regardless.
#   - no downgrade channel (I8): an autonomous row carrying explicit_downgrade => BLOCK.
#
# LADDER + SERIAL NOTE: risk classes order low < medium < high (an ORDERING for the
# escalate-only comparison ONLY - never a tier-selection map; tier selection stays
# Resolve-NeoAuditTier's, orch_enforce.ps1). Autonomous execution is STRICTLY SERIAL at
# every level, ALL tiers; batching = report collection only (v3.1 sec 4/6).
. "$PSScriptRoot\orch_enforce.ps1"

# ============================================================================
# C6 - ENGINE MINIMUM GOVERNED-TOKEN SET (NF-4 mandatory union)
# ============================================================================
# The frozen literal minimum. Spec C6: this set is MANDATORILY UNIONED into every
# autonomous re-derive - applied enforcement, not shipped availability. A profile
# (complete, starved, or attested) can never subtract from it.
function Get-NeoGovernedTokenSet {
  return @('money', 'payment', 'tax', 'ledger', 'auth', 'secret', 'migration', 'gate')
}

# ============================================================================
# C6-FIX-2 - SHARED PRIVATE SHAPE HELPERS (D2 boundary re-validation)
# ============================================================================
# ONE shared validation helper per input class, called by EVERY public boundary
# where that input arrives (the EMS fix-4 lesson: enforcement lives at the API
# boundary where input arrives, not in the caller's good manners). Because the
# SAME code path validates at both Resolve-NeoRouterProfile and
# Invoke-NeoDiffRiskRederive, the two boundaries can never drift. NO branding/
# marker properties (forgeable in PowerShell) - re-validation IS the mechanism.

# Assert-NeoRouterDenyEntriesShape: the C6-FIX F1 per-entry denylist rules,
# extracted VERBATIM from the former inline guard in Resolve-NeoRouterProfile
# (semantics identical). Entries must be an IList (not a string); EVERY member a
# non-null OBJECT carrying a non-blank STRING 'pattern' and a BOOLEAN 'is_glob'.
# ANY violation => BLOCK (fail-closed). Returns the validated entries array.
function Assert-NeoRouterDenyEntriesShape {
  param($Entries, [string]$Context)
  if (($Entries -is [string]) -or -not ($Entries -is [System.Collections.IList])) {
    New-NeoBlock "${Context}: denylist.entries is not an array (scalar shape) => unparseable denylist => BLOCK (C6-FIX F1; N1 fail-closed)"
  }
  $validated = @()
  foreach ($e in @($Entries)) {
    if ($null -eq $e) { New-NeoBlock "${Context}: denylist entry is null => unparseable denylist => BLOCK (C6-FIX F1; null entries BLOCK, never filtered)" }
    if (($e -is [string]) -or ($e -is [bool]) -or (Test-NeoIsNumber $e) -or ($e -is [System.Collections.IList])) {
      New-NeoBlock "${Context}: denylist entry is not an object (bare string/scalar) => unparseable denylist => BLOCK (C6-FIX F1)"
    }
    $pat = Get-NeoProp $e 'pattern'
    if (-not ($pat -is [string]) -or [string]::IsNullOrWhiteSpace($pat)) {
      New-NeoBlock "${Context}: denylist entry 'pattern' missing/blank/non-string => unparseable denylist => BLOCK (C6-FIX F1; a blank pattern may never silently match nothing)"
    }
    $ig = Get-NeoProp $e 'is_glob'
    if (-not ($ig -is [bool])) {
      New-NeoBlock "${Context}: denylist entry 'is_glob' missing/non-boolean => unparseable denylist => BLOCK (C6-FIX F1)"
    }
    $validated += , $e
  }
  # Plain (enumerating) return: every caller collects with @(...), which
  # faithfully rebuilds the validated list including the EMPTY case.
  return $validated
}

# Assert-NeoRouterTokenListShape (C6-FIX-2 D3): when a token-list field is
# present/non-null it MUST be an IList - a bare STRING or any scalar => BLOCK,
# never auto-wrapped; EVERY member MUST be a STRING - a non-string member =>
# BLOCK, never stringified; a blank-string member => BLOCK, never silently
# skipped. An ABSENT/null field returns an empty list: EMPTINESS semantics
# (gap/attestation) stay with the caller, UNCHANGED - a valid empty array still
# routes to the attestation path. Returns the validated token array.
function Assert-NeoRouterTokenListShape {
  param($List, [string]$FieldName, [string]$Context)
  if ($null -eq $List) { return @() }
  if (($List -is [string]) -or -not ($List -is [System.Collections.IList])) {
    New-NeoBlock "${Context}: ${FieldName} is not an array (bare string/scalar shape) => BLOCK, never auto-wrapped (C6-FIX-2 D3)"
  }
  $validated = @()
  foreach ($t in @($List)) {
    if (-not ($t -is [string])) {
      New-NeoBlock "${Context}: ${FieldName} member is not a string => BLOCK, never stringified (C6-FIX-2 D3; garbage may never satisfy the completeness gate)"
    }
    if ([string]::IsNullOrWhiteSpace($t)) {
      New-NeoBlock "${Context}: ${FieldName} member is blank => BLOCK, never silently skipped (C6-FIX-2 D3)"
    }
    $validated += $t
  }
  # Plain (enumerating) return: every caller collects with @(...) (see above).
  return $validated
}

# ============================================================================
# C6 - PROFILE-COMPLETENESS GATE (N1/NF-4, fail-closed, OR-semantics)
# ============================================================================
# Consumes the app profile (neo:app_profile shape) and returns the router view:
#   @{ denylist_entries; tokens; attested_gaps_applied }
# BLOCKS (fail-closed): profile null/unparseable; denylist.entries empty/missing;
# UNION(risk_tokens.auth_tokens, risk_tokens.fin_tokens) empty/missing. OR-semantics:
# EITHER gap alone is a BLOCK - a half-starved profile never passes (NF-4).
#
# C6-FIX F1 - PER-ENTRY SHAPE GUARD (fail-closed): denylist.entries, when present,
# must be an ARRAY, and EVERY entry must be a non-null OBJECT carrying a non-blank
# STRING 'pattern' and a BOOLEAN 'is_glob'. ANY malformed entry (bare string entry,
# null entry, pattern missing/blank/non-string, is_glob missing/non-boolean, entries
# as a scalar) => BLOCK as unparseable (C6 N1). NO silent skip anywhere in the entry
# path: completeness now GUARANTEES shape, so the diff-time blank-pattern/null-entry
# 'continue' guards in Invoke-NeoDiffRiskRederive are unreachable defense-in-depth.
#
# C6-FIX F4 - ATTESTATION RECORD SHAPE: $AttestedGapRecords replaces the bare string
# list. Each record must be a non-null OBJECT with non-blank: gap ('denylist' |
# 'risk_tokens', case-exact), attested_by, attested_date (^\d{4}-\d{2}-\d{2}$),
# run_scope. A malformed record => BLOCK. A starved gap passes ONLY when a VALID
# record names exactly that gap - never inferred, never wholesale. HONEST BOUNDARY:
# the AUTHORITY of a record (that it truly is Raphael's C5-recorded per-run
# attestation) is bound at the C5 gate (later slice); THIS layer enforces the
# record's SHAPE + specificity fail-closed. REGARDLESS of profile content or
# attestation, the returned token set = profile tokens UNION Get-NeoGovernedTokenSet
# (the union is unconditional).
function Resolve-NeoRouterProfile {
  param($Profile, $AttestedGapRecords = @())

  if ($null -eq $Profile) { New-NeoBlock "router-profile: app profile null/unparseable => BLOCK (C6 N1/NF-4)" }

  # -- attestation record SHAPE gate (C6-FIX F4): validate EVERY record up front --
  # A malformed record is a BLOCK in itself (fail-closed), never a silently-ignored
  # non-attestation. Only shape-valid records contribute their (case-exact) gap id.
  $attestedGapIds = @()
  foreach ($rec in @($AttestedGapRecords)) {
    if ($null -eq $rec) { New-NeoBlock "router-profile: attestation record null => malformed record => BLOCK (C6-FIX F4)" }
    if (($rec -is [string]) -or ($rec -is [bool]) -or (Test-NeoIsNumber $rec) -or ($rec -is [System.Collections.IList])) {
      New-NeoBlock "router-profile: attestation record is not an object (bare string/scalar/array) => BLOCK (C6-FIX F4; record authority binds at the C5 gate, record SHAPE binds here)"
    }
    $gap = Get-NeoProp $rec 'gap'
    if (-not ($gap -is [string]) -or (($gap -cne 'denylist') -and ($gap -cne 'risk_tokens'))) {
      New-NeoBlock "router-profile: attestation record 'gap' must be 'denylist' or 'risk_tokens' (case-exact non-blank string) => BLOCK (C6-FIX F4)"
    }
    foreach ($f in @('attested_by', 'run_scope')) {
      $v = Get-NeoProp $rec $f
      if (-not ($v -is [string]) -or [string]::IsNullOrWhiteSpace($v)) {
        New-NeoBlock "router-profile: attestation record field '$f' missing/blank/non-string => BLOCK (C6-FIX F4)"
      }
    }
    $d = Get-NeoProp $rec 'attested_date'
    if (-not ($d -is [string]) -or ($d -cnotmatch '^\d{4}-\d{2}-\d{2}$')) {
      New-NeoBlock "router-profile: attestation record 'attested_date' missing/non-string or not ^\d{4}-\d{2}-\d{2}$ => BLOCK (C6-FIX F4)"
    }
    if ($attestedGapIds -cnotcontains $gap) { $attestedGapIds += $gap }
  }

  $appliedGaps = @()

  # -- denylist completeness + PER-ENTRY SHAPE (gap id 'denylist'; C6-FIX F1) ----
  # (Get-NeoProp/Get-NeoVal are only called on non-null owners: a garbage/primitive
  # profile yields null sub-objects, which read as MISSING - the gap BLOCKs, never a
  # raw index error. Get-NeoVal is SHAPE-PRESERVING, so a scalar 'entries' is seen
  # as the scalar it is - it can never masquerade as a one-entry array.)
  $denylist = Get-NeoProp $Profile 'denylist'
  $entries = @()
  $rawEntries = if ($null -ne $denylist) { Get-NeoVal $denylist 'entries' } else { $null }
  if ($null -ne $rawEntries) {
    # C6-FIX-2: the F1 per-entry rules moved VERBATIM into the shared helper
    # (semantics identical); the SAME helper re-validates at the
    # Invoke-NeoDiffRiskRederive boundary, so the two can never drift (D2).
    $entries = @(Assert-NeoRouterDenyEntriesShape $rawEntries 'router-profile')
  }
  if ($entries.Count -eq 0) {
    if ($attestedGapIds -ccontains 'denylist') { $appliedGaps += 'denylist' }
    else { New-NeoBlock "router-profile: denylist.entries empty/missing and gap 'denylist' not covered by a valid C5 attestation record => BLOCK (C6 N1/NF-4 OR-semantics)" }
  }

  # -- risk_tokens completeness (gap id 'risk_tokens') + FIELD SHAPE (C6-FIX-2 D3)
  # The RAW auth_tokens/fin_tokens fields are shape-gated BEFORE any @()-wrap
  # (Get-NeoVal is SHAPE-PRESERVING): a scalar can never be auto-wrapped into
  # validity, a non-string member is never stringified into completeness, a
  # blank member is never silently filtered - all BLOCK. The EMPTINESS/
  # attestation logic below is UNCHANGED: a valid EMPTY array still routes to
  # the gap/attestation path.
  $rt = Get-NeoProp $Profile 'risk_tokens'
  $profileTokens = @()
  if ($null -ne $rt) {
    $profileTokens = @(Assert-NeoRouterTokenListShape (Get-NeoVal $rt 'auth_tokens') 'risk_tokens.auth_tokens' 'router-profile') +
                     @(Assert-NeoRouterTokenListShape (Get-NeoVal $rt 'fin_tokens') 'risk_tokens.fin_tokens' 'router-profile')
  }
  if ($profileTokens.Count -eq 0) {
    if ($attestedGapIds -ccontains 'risk_tokens') { $appliedGaps += 'risk_tokens' }
    else { New-NeoBlock "router-profile: UNION(risk_tokens.auth_tokens, risk_tokens.fin_tokens) empty/missing and gap 'risk_tokens' not covered by a valid C5 attestation record => BLOCK (C6 N1/NF-4 OR-semantics)" }
  }

  # -- MANDATORY UNION (unconditional, NF-4): profile tokens + engine minimum ----
  $tokens = @()
  foreach ($t in ($profileTokens + (Get-NeoGovernedTokenSet))) {
    if ($tokens -notcontains $t) { $tokens += $t }   # -notcontains is case-insensitive: dedupe only
  }

  return @{
    denylist_entries     = $entries
    tokens               = $tokens
    attested_gaps_applied = $appliedGaps
  }
}

# ============================================================================
# C6 - AUTONOMOUS-ROW GATE (I8 + I4)
# ============================================================================
# Refuses a risk row that may not route autonomously. Row null / risk_class missing or
# unknown => BLOCK - vocabulary is checked by REUSING Resolve-NeoAuditTier (no parallel
# map; its fail-closed BLOCKs propagate). A row CARRYING the KEY 'explicit_downgrade'
# AT ALL => BLOCK: the spec says autonomous rows MUST NOT CARRY one, so PRESENCE is
# the test - value inspection is the wrong test (C6-FIX I-1: PowerShell unwraps an
# empty-array property to $null, so a value test let explicit_downgrade=[] slip
# through). There is NO downgrade channel in autonomous rows (I8; the
# MEDIUM->lightweight code path is thereby unreachable in autonomous mode). This
# function never writes or modifies a row - rows are C5-frozen authority (I4).
function Assert-NeoAutonomousRowEligible {
  param($RiskRow)
  # Reused oracle: null row => BLOCK; risk_class missing/unknown => BLOCK (inside).
  $null = Resolve-NeoAuditTier -RiskRow $RiskRow
  # C6-FIX I-1: Get-NeoPropNames (REUSED) enumerates key names for BOTH hashtable and
  # PSCustomObject row shapes - presence of the key blocks regardless of its value
  # ($null, [], a complete record: all BLOCK equally).
  if (@(Get-NeoPropNames $RiskRow) -contains 'explicit_downgrade') {
    New-NeoBlock "autonomous-row: row CARRIES key 'explicit_downgrade' (presence is the test; value irrelevant) => no downgrade channel in autonomous rows => BLOCK (C6 I8 / C6-FIX I-1)"
  }
  return $true
}

# ============================================================================
# C6 - DIFF-TIME RISK RE-DERIVE (I4, escalate-only)
# ============================================================================
# Re-derives risk from the ACTUAL changed set (never declared surfaces) using the
# router profile view (Resolve-NeoRouterProfile output). Fail-closed:
#   - -RepoRoot missing/blank or not an existing directory => BLOCK (C6-FIX F2/F3)
#   - a changed path in a NON-CANONICAL spelling => BLOCK (C6-FIX F2/F3, see below)
#   - ChangedSet empty/null => BLOCK (nothing legitimate routes on an empty actual diff)
#   - a changed PATH matching a denylist entry (glob per is_glob, else exact;
#     case-insensitive on Windows) => BLOCK - forbidden surface is a STOP, never a bump
#   - a changed file unreadable => BLOCK
#
# C6-FIX F2/F3 - CHANGED-SET SPELLING CONTRACT + CONTAINED READS: every changed path
# must be CANONICAL REPO-RELATIVE, enforced BEFORE any matching or reading.
# Assert-NeoSafeRel (REUSED standing rule) rejects rooted / drive-qualified / UNC /
# backslash / '..' / empty spellings; it PERMITS a './'-prefixed spelling (it strips
# '^\./' before its '..' scan - live-probed 2026-07-06), so './'-prefixed and every
# other non-canonical segment spelling ('.' segments, empty '//' segments, trailing
# '/') are REJECTED here ON TOP of it. REJECT, never normalize-and-accept:
# normalizing a crafted spelling into the canonical one is the XC1 trap - a dodging
# spelling is a STOP naming the offending path, never an input to clean up. Content
# is then read ONLY from the containment-checked join Assert-NeoContained(RepoRoot,
# rel) - the CWD-dependent ReadAllText on raw input is gone.
#
# Any profile token found (case-insensitive substring, AS11/AS14 precedent) in a
# changed file's CONTENT or PATH => derived class 'high'. Escalate-only comparison:
# derived HIGHER than the frozen row class => BLOCK with an explicit escalation message
# (the supervisor surfaces + re-audits at the higher tier in C1/C3 - this layer only
# STOPs honestly); derived lower/equal => the FROZEN row class is returned unchanged
# (never downgrade). Returns @{ frozen_class; derived_class; escalated; effective_class }.
function Invoke-NeoDiffRiskRederive {
  param($ChangedSet, $RouterProfile, $RiskRow, [string]$RepoRoot)

  # Risk-class rank: an ORDERING for the escalate-only comparison ONLY - never a
  # tier-selection map (tier selection stays Resolve-NeoAuditTier's).
  $riskRank = @{ low = 0; medium = 1; high = 2 }

  # -- C6-FIX F2/F3: RepoRoot is REQUIRED - reads are CONTAINED under it, never CWD --
  if ([string]::IsNullOrWhiteSpace($RepoRoot)) { New-NeoBlock "diff-rederive: -RepoRoot missing/blank - contained reads require the repo root => BLOCK (C6-FIX F2/F3)" }
  if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { New-NeoBlock "diff-rederive: -RepoRoot '$RepoRoot' is not an existing directory => BLOCK (C6-FIX F2/F3)" }

  # -- C6-FIX-2 D1: the RAW ChangedSet is VALIDATED, never repaired-by-filtering.
  # ANY member that is $null, not a string, or whitespace => BLOCK naming the
  # member index - a malformed changed set must STOP, never route on the
  # surviving paths. The existing empty/null-set BLOCK stays (a $null set is the
  # EMPTY case, checked first; a $null MEMBER of a non-null set is D1).
  if ($null -eq $ChangedSet) { New-NeoBlock "diff-rederive: ChangedSet empty/null - nothing legitimate routes on an empty actual diff => BLOCK (C6 I4)" }
  $paths = @()
  $rawSet = @($ChangedSet)
  for ($i = 0; $i -lt $rawSet.Count; $i++) {
    $p = $rawSet[$i]
    if ($null -eq $p) { New-NeoBlock "diff-rederive: ChangedSet member [$i] is null => malformed changed set => BLOCK, never repaired-by-filtering (C6-FIX-2 D1)" }
    if (-not ($p -is [string])) { New-NeoBlock "diff-rederive: ChangedSet member [$i] is not a string => malformed changed set => BLOCK, never repaired-by-filtering (C6-FIX-2 D1)" }
    if ([string]::IsNullOrWhiteSpace($p)) { New-NeoBlock "diff-rederive: ChangedSet member [$i] is blank/whitespace => malformed changed set => BLOCK, never repaired-by-filtering (C6-FIX-2 D1)" }
    $paths += $p
  }
  if ($paths.Count -eq 0) { New-NeoBlock "diff-rederive: ChangedSet empty/null - nothing legitimate routes on an empty actual diff => BLOCK (C6 I4)" }

  # -- C6-FIX F2/F3: spelling contract, fail-closed, BEFORE any matching or reading --
  foreach ($p in $paths) {
    Assert-NeoSafeRel $p   # REUSED: throws NEO-BLOCK naming the offending path (rooted/drive/UNC/backslash/../empty)
    if ($p.StartsWith('./')) {
      New-NeoBlock "diff-rederive: changed path '$p' is './'-prefixed - not canonical repo-relative => REJECTED, never normalized (C6-FIX F2; XC1) => BLOCK"
    }
    foreach ($seg in ($p -split '/')) {
      if ([string]::IsNullOrEmpty($seg) -or ($seg -eq '.')) {
        New-NeoBlock "diff-rederive: changed path '$p' carries a non-canonical segment ('.' or empty) => REJECTED, never normalized (C6-FIX F2; XC1) => BLOCK"
      }
    }
  }

  if ($null -eq $RouterProfile) { New-NeoBlock "diff-rederive: RouterProfile required (Resolve-NeoRouterProfile output) => BLOCK (C6 N1)" }
  # -- C6-FIX-2 D2: boundary RE-VALIDATION - the SAME shared helpers that gate
  # Resolve-NeoRouterProfile re-validate here, at the boundary where the input
  # arrives. A CRAFTED RouterProfile fed directly to this function (bypassing
  # the sibling) can never dodge the F1 shape rules or smuggle non-string/blank
  # tokens; no forgeable branding marker - re-validation IS the mechanism. The
  # tokens-empty BLOCK below stays (EMPTINESS is its own gate, C6 NF-4).
  $denyEntries = @(Assert-NeoRouterDenyEntriesShape (Get-NeoVal $RouterProfile 'denylist_entries') 'diff-rederive')
  $tokens = @(Assert-NeoRouterTokenListShape (Get-NeoVal $RouterProfile 'tokens') 'RouterProfile.tokens' 'diff-rederive')
  if ($tokens.Count -eq 0) { New-NeoBlock "diff-rederive: RouterProfile.tokens empty - the governed-token union can never be empty => BLOCK (C6 NF-4)" }

  # Frozen row authority (I4) + autonomous eligibility (I8, C6-FIX-3 E1): the row
  # gate wraps the tier oracle - null/unknown risk_class BLOCKs retained - and
  # refuses any explicit_downgrade-carrying row at THIS boundary too; every public
  # boundary of the autonomous router enforces autonomy eligibility.
  $null = Assert-NeoAutonomousRowEligible -RiskRow $RiskRow
  $frozenClass = [string](Get-NeoProp $RiskRow 'risk_class')

  # -- pass 1: denylist - a forbidden-surface hit is a STOP, never a tier bump ---
  # Matching runs against the CANONICAL REL path (spelling contract above). The
  # null-entry/blank-pattern 'continue' guards below are unreachable defense-in-depth
  # since C6-FIX F1 - and DOUBLY unreachable since C6-FIX-2 D2: the shared shape
  # helper now re-validates entries at THIS boundary too, so they can never fire.
  foreach ($p in $paths) {
    $normPath = ($p -replace '\\', '/')
    foreach ($entry in $denyEntries) {
      if ($null -eq $entry) { continue }
      $pattern = ($([string](Get-NeoProp $entry 'pattern')) -replace '\\', '/')
      if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
      $isGlob = [bool](Get-NeoProp $entry 'is_glob')
      $hit = if ($isGlob) { Test-NeoGlobMatch $normPath $pattern } else { $normPath -ieq $pattern }
      if ($hit) { New-NeoBlock "diff-rederive: changed path '$p' matches denylist entry '$pattern' - forbidden surface => STOP (C6 I4; never merely a tier bump)" }
    }
  }

  # -- pass 2: token scan over PATH and CONTENT (case-insensitive substring) -----
  $derivedClass = 'low'
  foreach ($p in $paths) {
    foreach ($t in $tokens) {
      if ($p.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $derivedClass = 'high'; break }
    }
    # C6-FIX F3: CONTAINED read - the full path is the containment-checked join of
    # RepoRoot + canonical rel (Assert-NeoContained, REUSED; throws NEO-BLOCK on
    # escape). NEVER the raw input, never CWD-dependent.
    $full = Assert-NeoContained $RepoRoot $p
    $content = $null
    try { $content = [System.IO.File]::ReadAllText($full) }
    catch { New-NeoBlock "diff-rederive: changed file '$p' unreadable at contained path '$full' => BLOCK (C6 I4 fail-closed)" }
    foreach ($t in $tokens) {
      if ($content.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $derivedClass = 'high'; break }
    }
  }

  # -- escalate-only compare vs the FROZEN row class (I4) ------------------------
  if ($riskRank[$derivedClass] -gt $riskRank[$frozenClass]) {
    New-NeoBlock ("diff-rederive: derived risk '" + $derivedClass + "' EXCEEDS frozen row risk '" + $frozenClass + "' => ESCALATION - STOP this round; the supervisor surfaces and re-audits at the higher tier (C6 I4 escalate-only; a mid-slice escalation is a surfaced event in END evidence)")
  }

  # Derived lower/equal: the FROZEN class is returned unchanged - never downgrade.
  return @{
    frozen_class    = $frozenClass
    derived_class   = $derivedClass
    escalated       = $false
    effective_class = $frozenClass
  }
}
