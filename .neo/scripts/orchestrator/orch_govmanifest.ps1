# orch_govmanifest.ps1 - NEO 4.0-P4-AUTONOMY C1C3-S2b governance HASH-MANIFEST engine.
# ASCII-only (D10). Dot-source; defines functions only. COORDINATION-only crown jewel:
# this module DERIVES + RE-VERIFIES the governance-integrity manifest (spec sec 4 C1b
# I3/NF-2 + V1 + C1c). It READS + HASHES the governed tree; it NEVER mutates it.
#
# LOAD-BEARING NOTE: the governance hash manifest built HERE is the LOAD-BEARING
# governance-integrity check (spec line 100-102; orch_diff.ps1 lines 50-58 name S2b as
# the closure of the engine-self-tamper residual). The builder sub-agent FS-DENY on
# `.neo/**` is S3 spawn-wiring (belt-and-suspenders), NOT this slice.
#
# REUSE (READ-ONLY, no frozen edit): one dot-source of orch_diff.ps1 transitively
# provides the entire helper surface -
#   orch_diff.ps1  -> Get-NeoRealPath / Assert-NeoCanonicalContained / Resolve-NeoGovernanceMapPath
#   orch_io.ps1    -> New-NeoBlock / Assert-NeoValid
#   orch_schema.ps1-> Get-NeoSha256File / Assert-NeoSafeRel / Get-NeoSchemaIndex
#   orch_class.ps1 -> Resolve-NeoArtifactClass / Get-NeoClassMap
#   _neo_root.ps1  -> Resolve-NeoRoot
# (orch_diff -> orch_io -> {orch_schema, orch_class}; orch_diff -> _neo_root. All frozen.)
$script:NeoGovManifestDir = $PSScriptRoot
. "$script:NeoGovManifestDir\orch_diff.ps1"

# Judging classes (per spec: constraint | test_harness | profile_risk). A manifest
# member is EXACTLY a governed file resolving one of these under the LIVE class map.
$script:NeoGovJudgingClasses = @('constraint', 'test_harness', 'profile_risk')

# S2b-FIX F3 (NF-4 "mandatory union" lesson): the engine DEFAULT FLOOR is ALWAYS
# enforced and can NEVER be vacated. -MandatoryMembers (F3 rename of -MandatoryLeaves)
# ADDS to this floor, never replaces it; an empty caller list @() still checks the
# full floor. The floor members are matched by their FULL EXPECTED CANONICAL REL
# (F2 fix: NOT bare leaf - a right-leaf/wrong-location file must NOT satisfy). Each
# {rel} is the known governed path of an always-present judging artifact.
#
# S2b-FIX-2 F1 (existential PATTERN floor -> explicit full-rel floor): the prior
# mandatory floor had an EXISTENTIAL part - three leaf-globbed pattern groups
# (orch_*.ps1 / *SKILL.md / *.schema.json) each asserted "at least one member
# present". That let a governed tree missing ONE required engine script / role body
# / schema still PASS V1 as long as any sibling survived; a starved initial C5 pin
# was then re-verified forever by Compare (the missing file was never pinned) - an
# in-model fail-open at the pin boundary. FIX: ELIMINATE the existential groups;
# ENUMERATE every mandatory member by EXPLICIT FULL CANONICAL REL (ordinal, case-
# exact) here. A tree missing ANY enumerated rel => BLOCK MANDATORY_MEMBER_MISSING.
# No group is ever "satisfied by a sibling".
#
# GROUNDED 2026-07-06 against the LIVE classmap (DIRECTOR ruling R1, recorded): each
# rel below is PRESENT + resolves a JUDGING class (constraint | test_harness |
# profile_risk) in the real governed tree, so this floor never false-blocks the real
# engine. NEO_SYSTEM/SKILL.md and NEO_QA_SCENARIO/SKILL.md resolve NON-JUDGING
# (router + lazy manager; default_class=implementation per the frozen classmap, which
# registers ONLY the 3 active role bodies DIRECTOR/BUILDER/AUDITOR as judging) - they
# are DELIBERATELY NOT mandatory members (a mandatory member MUST resolve judging per
# V1; requiring a non-judging file would false-block the real engine).
$script:NeoGovDefaultMandatoryRels = @(
  # ENGINE SCRIPTS (18, all test_harness): the 15 orch_*.ps1 + orchestrator.ps1 +
  # _neo_root.ps1 + verify_app_slice.ps1. (C4: orch_external.ps1 joined the floor -
  # the S3a 23->24 precedent, then 24->25; C5: orch_clarity.ps1 joined, 25->26;
  # INTEGRATE: orch_run.ps1 joined, 26->27.)
  '.neo/scripts/orchestrator/orch_auditor_stub.ps1',
  '.neo/scripts/orchestrator/orch_clarity.ps1',
  '.neo/scripts/orchestrator/orch_class.ps1',
  '.neo/scripts/orchestrator/orch_diff.ps1',
  '.neo/scripts/orchestrator/orch_enforce.ps1',
  '.neo/scripts/orchestrator/orch_engine.ps1',
  '.neo/scripts/orchestrator/orch_external.ps1',
  '.neo/scripts/orchestrator/orch_govmanifest.ps1',
  '.neo/scripts/orchestrator/orch_io.ps1',
  '.neo/scripts/orchestrator/orch_loop.ps1',
  '.neo/scripts/orchestrator/orch_rollover.ps1',
  '.neo/scripts/orchestrator/orch_run.ps1',
  '.neo/scripts/orchestrator/orch_router.ps1',
  '.neo/scripts/orchestrator/orch_schema.ps1',
  '.neo/scripts/orchestrator/orch_supervisor.ps1',
  '.neo/scripts/orchestrator/orchestrator.ps1',
  '.neo/scripts/_neo_root.ps1',
  '.neo/scripts/verify_app_slice.ps1',
  # CORE ROLE BODIES (3, constraint): the ONLY 3 role SKILL.md bodies the frozen
  # classmap registers judging. NEO_SYSTEM + NEO_QA_SCENARIO are non-judging, excluded.
  '.claude/skills/NEO_DIRECTOR/SKILL.md',
  '.claude/skills/NEO_BUILDER/SKILL.md',
  '.claude/skills/NEO_AUDITOR/SKILL.md',
  # CONSTRAINT / RISK (2).
  '.neo/schema/artifact_classes.json',
  '.neo/NEO_RISK_TIERS.md',
  # CORE GOVERNANCE / LEDGER SCHEMAS (4, constraint): the load-bearing schemas this
  # engine's own operation depends on.
  '.neo/schema/governance_manifest.schema.json',
  '.neo/schema/run_manifest.schema.json',
  '.neo/schema/attempt_ledger_entry.schema.json',
  '.neo/schema/spawn_ledger_entry.schema.json'
)

# ---- governed-root resolution (S2a-FIX-2/4 module-root hardening) ------------
# Canonicalize the module dir to its REAL filesystem path FIRST (resolve any
# junction/symlink spelling) BEFORE Resolve-NeoRoot walks up - a junctioned module
# dir must resolve to its REAL governed location, never an app-spelled ancestor.
# Unresolvable module dir => BLOCK MODULE_ROOT_UNRESOLVABLE (fail-closed; NEVER falls
# back to the un-canonicalized path, NEVER returns an app RepoRoot). Unresolvable /
# empty governed root => BLOCK NO_GOVERNANCE_ROOT.
function Get-NeoGovernedRoot {
  $moduleReal = $null
  try { $moduleReal = Get-NeoRealPath -Path $script:NeoGovManifestDir }
  catch { New-NeoBlock "reason_code=MODULE_ROOT_UNRESOLVABLE cannot canonicalize module root '$($script:NeoGovManifestDir)' (fail-closed; never falls back to the un-canonicalized path): $($_.Exception.Message)" }
  $root = $null
  try { $root = Resolve-NeoRoot $moduleReal }
  catch { New-NeoBlock "reason_code=NO_GOVERNANCE_ROOT cannot resolve NEO governed root from module dir: $($_.Exception.Message)" }
  if ([string]::IsNullOrWhiteSpace($root)) {
    New-NeoBlock "reason_code=NO_GOVERNANCE_ROOT NEO governed root resolved empty"
  }
  return (Get-NeoRealPath -Path $root)
}

# Load the LIVE class map that sits under the governed root (the SAME oracle path the
# frozen classifier uses - never an app RepoRoot's map). Absent/invalid => BLOCK.
# S2b-FIX F1 (classmap read must be canonical-contained): the map rel is resolved
# through the frozen Assert-NeoCanonicalContained (rel-safe + reparse-aware REAL path
# + containment) BEFORE any read. A '.neo\schema' or artifact_classes.json that is a
# junction/symlink to an app-controlled location resolves OUTSIDE the governed root
# => BLOCK PATH_ESCAPE. The classmap is NEVER read at its un-canonicalized spelling.
function Get-NeoGovLiveClassMap {
  param([string]$GovernedRoot)
  if ([string]::IsNullOrWhiteSpace($GovernedRoot)) { New-NeoBlock "reason_code=NO_GOVERNANCE_ROOT GovernedRoot required for live class map" }
  # Canonicalize the governed root itself first (reparse-aware real path).
  $rootReal = $null
  try { $rootReal = Get-NeoRealPath -Path $GovernedRoot }
  catch { New-NeoBlock "reason_code=NO_GOVERNANCE_ROOT cannot canonicalize governed root '$GovernedRoot' for the live class map: $($_.Exception.Message)" }
  # Resolve the classmap rel to its REAL contained path; a classmap escaping the
  # governed root (junction/symlink) throws NEO-BLOCK reason_code=PATH_ESCAPE here.
  $mapReal = $null
  try { $mapReal = Assert-NeoCanonicalContained -RepoRoot $rootReal -Rel '.neo/schema/artifact_classes.json' }
  catch { New-NeoBlock (($_.Exception.Message) -replace '^NEO-BLOCK:\s*', '') }
  if (-not (Test-Path -LiteralPath $mapReal -PathType Leaf)) {
    New-NeoBlock "reason_code=NO_GOVERNANCE_MAP judging-class map not found under the governed root: $mapReal"
  }
  try { return (Get-NeoClassMap $mapReal) }
  catch { New-NeoBlock "reason_code=NO_GOVERNANCE_MAP judging-class map unusable under the governed root '$mapReal': $($_.Exception.Message)" }
}

# ---- canonical root-relative spelling ---------------------------------------
# Turn an absolute file path (real) into a forward-slash root-relative rel that is
# SAFE (Assert-NeoSafeRel) and CONTAINED under GovernedRoot. Reused for every member.
function Get-NeoGovRel {
  param([string]$GovernedRoot, [string]$FullPath)
  $rootReal = (Get-NeoRealPath -Path $GovernedRoot).TrimEnd([char]0x5C, [char]0x2F)
  $fileReal = Get-NeoRealPath -Path $FullPath
  $rootCmp = $rootReal + [System.IO.Path]::DirectorySeparatorChar
  if (-not $fileReal.StartsWith($rootCmp, [System.StringComparison]::OrdinalIgnoreCase)) {
    New-NeoBlock "reason_code=PATH_ESCAPE governed file '$fileReal' is not under governed root '$rootReal'"
  }
  $rel = $fileReal.Substring($rootCmp.Length) -replace '\\', '/'
  Assert-NeoSafeRel $rel
  return $rel
}

# ---- Build-NeoGovManifest (I3/NF-2 RULE-DERIVED core) ------------------------
# Enumerate EVERY file under the governed tree, classify each via the LIVE class map,
# and INCLUDE every file resolving a JUDGING class. Enumeration is BY RULE
# (classify-and-include), NEVER an ad-hoc hardcoded list. Reads + hashes only - NO
# mutation of the governed tree. Deterministic ordering (sorted rel, ordinal).
# derived_at is CALLER-SUPPLIED (agents never self-generate time).
# Returns { schema_id; governed_root; derived_at; members[] { rel; class; content_hash } }.
function Build-NeoGovManifest {
  param(
    [Parameter(Mandatory = $true)][string]$GovernedRoot,
    [Parameter(Mandatory = $true)][string]$DerivedAt
  )
  if ([string]::IsNullOrWhiteSpace($GovernedRoot)) { New-NeoBlock "reason_code=NO_GOVERNANCE_ROOT GovernedRoot required for Build-NeoGovManifest" }
  if ([string]::IsNullOrWhiteSpace($DerivedAt))    { New-NeoBlock "Build-NeoGovManifest requires a caller-supplied DerivedAt (agents do not self-generate time)" }
  $rootReal = Get-NeoRealPath -Path $GovernedRoot
  if (-not (Test-Path -LiteralPath $rootReal -PathType Container)) {
    New-NeoBlock "reason_code=NO_GOVERNANCE_ROOT governed root does not exist: $rootReal"
  }
  $map = Get-NeoGovLiveClassMap -GovernedRoot $rootReal

  $members = @()
  # Enumerate EVERY file under the governed tree (files only; recurse).
  $files = @(Get-ChildItem -LiteralPath $rootReal -Recurse -File -Force -ErrorAction Stop)
  foreach ($f in $files) {
    $rel = Get-NeoGovRel -GovernedRoot $rootReal -FullPath $f.FullName
    # classify BY RULE against the LIVE map (leaf + full both matched by the oracle globs)
    $cls = Resolve-NeoArtifactClass $map $rel
    if ($script:NeoGovJudgingClasses -contains $cls) {
      $members += [pscustomobject]@{
        rel          = $rel
        class        = [string]$cls
        content_hash = (Get-NeoSha256File $f.FullName)
      }
    }
  }
  # deterministic ordering: sort by rel (ordinal, case-insensitive stable)
  $sorted = @($members | Sort-Object -Property @{ Expression = { $_.rel } } -Culture '' )
  # F7: a rule-derived governed tree ALWAYS yields judging members; an empty derivation
  # (or any unsafe/duplicate rel that slipped enumeration) is fail-closed here too.
  Assert-NeoGovMembersWellFormed -Members $sorted -Label 'derived' | Out-Null
  return [pscustomobject]@{
    schema_id     = 'neo:governance_manifest'
    governed_root = $rootReal
    derived_at    = $DerivedAt
    members       = $sorted
  }
}

# ---- Assert-NeoGovManifestMandatoryMembers (V1 MANDATORY-MEMBER, fail-closed) -
# Each mandatory member MUST be PRESENT in the derived manifest AND resolve a judging
# class under the LIVE map. ABSENT or NON-JUDGING => BLOCK
# reason_code=MANDATORY_MEMBER_MISSING (surface which).
#
# S2b-FIX F2 (wrong-file/leaf-match): mandatory members are matched by their FULL
# EXPECTED CANONICAL REL (ordinal, case-exact), NOT bare leaf. A right-leaf/wrong-
# location file (e.g. 'app/fixtures/verify_app_slice.ps1') does NOT satisfy the floor
# member '.neo/scripts/verify_app_slice.ps1'.
#
# S2b-FIX F3 (NF-4 "mandatory union" lesson - override erased the floor): the engine
# DEFAULT FLOOR ($script:NeoGovDefaultMandatoryRels - the full explicit rel set, no
# existential group after S2b-FIX-2 F1) is ALWAYS enforced. The caller-supplied
# -MandatoryMembers (renamed from -MandatoryLeaves) is
# ADDITIVE ONLY - it is UNIONED onto the floor, it NEVER replaces it. An empty caller
# list @() still checks the full floor; @() can NEVER vacate the floor. Caller
# additions are full canonical rels too (e.g. C5 adds 'NEO_APP_PROFILE.json' at the
# app root, or a subdir'd path); each is matched case-exact.
function Assert-NeoGovManifestMandatoryMembers {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [string[]]$MandatoryMembers = @(),
    [string]$GovernedRoot
  )
  if ($null -eq $Manifest) { New-NeoBlock "reason_code=MANDATORY_MEMBER_MISSING manifest is null" }
  $members = @($Manifest.members)
  # Live map for the non-judging re-check (a member could be PRESENT but the mandatory
  # entry itself must resolve judging - defends the spec's grounded orch_* example).
  $root = if ($GovernedRoot) { Get-NeoRealPath -Path $GovernedRoot } else { [string]$Manifest.governed_root }
  $map = Get-NeoGovLiveClassMap -GovernedRoot $root

  # F3 UNION: floor (always) + caller additions (never replacing). @() adds nothing but
  # the full floor is still checked below.
  $requiredRels = @($script:NeoGovDefaultMandatoryRels) + @($MandatoryMembers)

  # S2b-FIX-2 F1: EXPLICIT FULL-CANONICAL-REL floor ONLY - no existential pattern
  # group. EVERY enumerated mandatory rel (the 26-rel floor + any caller additions)
  # must be exactly-present-by-rel AND resolve judging. A tree missing ANY enumerated
  # rel => BLOCK; nothing is ever "satisfied by a group sibling".
  foreach ($rel in $requiredRels) {
    if ([string]::IsNullOrWhiteSpace($rel)) { continue }
    # F2: case-EXACT (ordinal) full-rel match - NOT leaf.
    $hit = @($members | Where-Object { ([string]$_.rel) -ceq ([string]$rel) })
    if ($hit.Count -eq 0) {
      New-NeoBlock "reason_code=MANDATORY_MEMBER_MISSING mandatory member '$rel' is ABSENT from the derived manifest (matched by full canonical rel, not leaf)"
    }
    foreach ($h in $hit) {
      if ($script:NeoGovJudgingClasses -notcontains $h.class) {
        New-NeoBlock "reason_code=MANDATORY_MEMBER_MISSING mandatory member '$($h.rel)' resolves NON-JUDGING ('$($h.class)') under the live map"
      }
      # independent live re-classification (member class could be stale vs live map)
      $live = Resolve-NeoArtifactClass $map $h.rel
      if ($script:NeoGovJudgingClasses -notcontains $live) {
        New-NeoBlock "reason_code=MANDATORY_MEMBER_MISSING mandatory member '$($h.rel)' resolves NON-JUDGING ('$live') under the LIVE class map"
      }
    }
  }
  return $true
}

# ---- Assert-NeoGovMembersWellFormed (F5/F7 shared member-identity guard) ------
# S2b-FIX F7 (member identity underconstrained - CODE guard, schema tightening
# DEFERRED) + F5 (duplicate / case-variant rels collapse): the schema's rel is only
# minLength:1 and members[] may be empty, so the LOAD-BEARING closure is here at the
# code boundary. For a members[] array:
#   * REJECT an EMPTY members array (a governed tree ALWAYS has judging members).
#   * Assert-NeoSafeRel EVERY member rel (reject ../ abs / backslash / UNC / drive /
#     traversal) - reuses the frozen orch_schema helper.
#   * REJECT ANY duplicate rel (case-SENSITIVE/ordinal exact) OR any case-VARIANT
#     near-duplicate (two rels equal case-insensitively but not ordinal-equal, e.g.
#     'A/skill.md' vs 'a/SKILL.md') => BLOCK. This is what makes the ordinal Compare
#     maps below safe from silent collapse.
# NOTE (DEFERRED, documented): a schema-level rel pattern (^(?!.*\.\.)[^/\\][^\\:*?"<>|]*$)
# + minItems:1 would move this into governance_manifest.schema.json. That schema is
# FROZEN this round; the schema edit is a SEPARATE future gated schema-edit halt. The
# code guard here is the load-bearing check for now.
# $Label is surfaced ('pinned' | 'current') for triage.
function Assert-NeoGovMembersWellFormed {
  param($Members, [string]$Label = 'manifest')
  if ($null -eq $Members) {
    New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH $Label manifest has no members[] (fail-closed; never treat-as-empty)"
  }
  $arr = @($Members)
  if ($arr.Count -eq 0) {
    New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH $Label manifest has an EMPTY members[] - a governed tree always has judging members (fail-closed)"
  }
  # case-exact (ordinal) + case-insensitive tracking sets for dup / case-variant detect
  $exact = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  $ci    = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($m in $arr) {
    $rel = [string]$m.rel
    if ([string]::IsNullOrWhiteSpace($rel)) {
      New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH $Label member has empty rel (corrupt manifest)"
    }
    # F7: every rel must be safe (../ abs backslash UNC drive traversal all rejected)
    try { Assert-NeoSafeRel $rel }
    catch { New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH $Label member rel is unsafe: '$rel' ($(($_.Exception.Message) -replace '^NEO-BLOCK:\s*', ''))" }
    # F5: reject case-exact duplicate rel
    if (-not $exact.Add($rel)) {
      New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH $Label manifest contains a DUPLICATE rel: '$rel'"
    }
    # F5: reject case-VARIANT near-duplicate (differs only by case from a prior rel)
    if (-not $ci.Add($rel)) {
      New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH $Label manifest contains a CASE-VARIANT duplicate rel: '$rel'"
    }
  }
  return $true
}

# ---- Compare-NeoGovManifest (RE-VERIFY EVERY ROUND) --------------------------
# Compare a PINNED manifest against a CURRENT (freshly re-derived) manifest: member-set
# + per-member content_hash. ANY added member, removed member, OR content_hash mismatch
# => BLOCK reason_code=GOVERNANCE_MANIFEST_MISMATCH (surface the offending member). A
# post-C5 write that empties the profile's token lists, or edits any judging artifact,
# is caught the SAME round. Unreadable/unparseable pinned manifest => BLOCK (fail-closed;
# NEVER treat-as-empty).
# S2b-FIX F5: the member maps are ORDINAL (case-SENSITIVE) dictionaries; a duplicate or
# case-variant rel is REJECTED up front by Assert-NeoGovMembersWellFormed so it can
# never silently collapse (the pre-fix case-insensitive hashtable overwrote dup keys).
function Compare-NeoGovManifest {
  param(
    $Pinned,
    $Current
  )
  if ($null -eq $Pinned)  { New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH pinned manifest is null/unreadable (fail-closed; never treat-as-empty)" }
  if ($null -eq $Current) { New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH current manifest is null (fail-closed)" }

  # F5/F7: reject empty / unsafe / duplicate / case-variant members BEFORE mapping.
  Assert-NeoGovMembersWellFormed -Members $Pinned.members  -Label 'pinned'  | Out-Null
  Assert-NeoGovMembersWellFormed -Members $Current.members -Label 'current' | Out-Null

  $pMembers = @($Pinned.members)
  $cMembers = @($Current.members)

  # F5: ORDINAL (case-SENSITIVE) dictionaries - 'A/skill.md' and 'a/SKILL.md' are
  # DISTINCT keys (and already rejected as case-variants above), never collapsed.
  $pMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
  foreach ($m in $pMembers) { $pMap[[string]$m.rel] = $m }
  $cMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
  foreach ($m in $cMembers) { $cMap[[string]$m.rel] = $m }

  # removed members (in pinned, not in current)
  foreach ($rel in $pMap.Keys) {
    if (-not $cMap.ContainsKey($rel)) {
      New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH member REMOVED since pin: '$rel'"
    }
  }
  # added members (in current, not in pinned)
  foreach ($rel in $cMap.Keys) {
    if (-not $pMap.ContainsKey($rel)) {
      New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH member ADDED since pin: '$rel'"
    }
  }
  # content_hash mismatch on the shared set (ordinal hash compare)
  foreach ($rel in $pMap.Keys) {
    $ph = [string]$pMap[$rel].content_hash
    $ch = [string]$cMap[$rel].content_hash
    if ($ph -cne $ch) {
      New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH member TAMPERED since pin: '$rel' (pinned=$ph current=$ch)"
    }
  }
  return $true
}

# Read + re-verify convenience: load a PINNED manifest from disk fail-closed, then
# SCHEMA-VALIDATE it, then compare against a freshly-derived Current. Missing/invalid
# pinned file => BLOCK.
# S2b-FIX F4 (pinned manifest not schema-validated on re-verify): BEFORE compare, the
# pinned manifest is validated against schema 'neo:governance_manifest' (indexed from
# the governed root's .neo\schema via the frozen Get-NeoSchemaIndex + Assert-NeoValid).
# A wrong schema_id / malformed rel / invalid class / structural violation => BLOCK,
# never treated-as-empty. The schema is read READ-ONLY as an index entry (never edited).
# The governed root for the schema index is taken from the freshly-derived Current
# manifest (authoritative, canonicalized in Build-NeoGovManifest); -GovernedRoot may
# override for callers that pass a bare Current.
function Assert-NeoGovManifestReverify {
  param(
    [Parameter(Mandatory = $true)][string]$PinnedPath,
    [Parameter(Mandatory = $true)]$Current,
    [string]$GovernedRoot
  )
  if (-not (Test-Path -LiteralPath $PinnedPath -PathType Leaf)) {
    New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH pinned manifest file missing: $PinnedPath (fail-closed; never treat-as-empty)"
  }
  $pinned = $null
  try { $pinned = (Get-Content -LiteralPath $PinnedPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
  catch { New-NeoBlock "reason_code=MANIFEST_CORRUPT pinned manifest is unreadable/invalid JSON: $PinnedPath (fail-closed; never treat-as-empty)" }
  if ($null -eq $pinned) { New-NeoBlock "reason_code=MANIFEST_CORRUPT pinned manifest parsed null: $PinnedPath (fail-closed)" }

  # F4: schema-validate the pinned manifest BEFORE compare.
  $root = if ($GovernedRoot) { $GovernedRoot } else { [string]$Current.governed_root }
  if ([string]::IsNullOrWhiteSpace($root)) {
    New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH cannot resolve governed root to schema-validate the pinned manifest (fail-closed)"
  }
  $rootReal = $null
  try { $rootReal = Get-NeoRealPath -Path $root }
  catch { New-NeoBlock "reason_code=NO_GOVERNANCE_ROOT cannot canonicalize governed root '$root' for pinned-manifest schema validation: $($_.Exception.Message)" }
  $schemaDir = $null
  try { $schemaDir = Assert-NeoCanonicalContained -RepoRoot $rootReal -Rel '.neo/schema' }
  catch { New-NeoBlock (($_.Exception.Message) -replace '^NEO-BLOCK:\s*', '') }
  $idx = $null
  try { $idx = Get-NeoSchemaIndex $schemaDir }
  catch { New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH cannot index schemas under '$schemaDir' to validate the pinned manifest: $($_.Exception.Message)" }
  # Assert-NeoValid throws NEO-BLOCK on wrong schema_id / malformed rel / invalid class /
  # any structural violation. Re-wrap into the manifest reason code for triage.
  try { Assert-NeoValid $pinned 'neo:governance_manifest' $idx 'pinned governance manifest' }
  catch { New-NeoBlock "reason_code=GOVERNANCE_MANIFEST_MISMATCH pinned manifest failed schema validation ($(($_.Exception.Message) -replace '^NEO-BLOCK:\s*', ''))" }

  return (Compare-NeoGovManifest -Pinned $pinned -Current $Current)
}

# ---- Assert-NeoNoJudgingFix (C1c HARD-STOP helper) ---------------------------
# Given a proposed fix's TARGET classification (reuse the S2a three-branch /
# Resolve-NeoArtifactClass result). The loop STOPs and surfaces; judging edits stay
# separately gated and are shown EXPLICITLY in END evidence. Never auto-edits a judging
# file.
#
# S2b-FIX F6 (default-open on unknown/typo class): FAIL-CLOSED TRI-STATE. The pre-fix
# code returned $true for anything that was not blank and not one of the 3 judging
# classes ('UNKNOWN' / 'profile' / 'wat' all defaulted OPEN). Now:
#   * a JUDGING class (constraint | test_harness | profile_risk)
#       => BLOCK reason_code=C1C_JUDGING_FIX_REQUIRED
#   * EXACTLY 'implementation' (ordinal, case-exact)
#       => ALLOW (return $true)
#   * ANY other value (unknown / typo / blank / null)
#       => BLOCK reason_code=C1C_UNKNOWN_CHANGE_CLASS
# There is NO default-open path.
function Assert-NeoNoJudgingFix {
  param(
    [string]$ChangeClass,
    [string]$TargetRel = ''
  )
  $where = if ($TargetRel) { " target='$TargetRel'" } else { '' }
  if ($script:NeoGovJudgingClasses -contains $ChangeClass) {
    New-NeoBlock "reason_code=C1C_JUDGING_FIX_REQUIRED proposed fix lands on JUDGING class '$ChangeClass'$where - the loop STOPs; judging edits are separately gated and shown explicitly in END evidence"
  }
  if ([string]$ChangeClass -ceq 'implementation') {
    return $true
  }
  # blank / null / unknown / typo => fail-closed BLOCK (no default-open)
  $shown = if ([string]::IsNullOrWhiteSpace($ChangeClass)) { '(blank)' } else { "'$ChangeClass'" }
  New-NeoBlock "reason_code=C1C_UNKNOWN_CHANGE_CLASS proposed-fix class $shown is not exactly 'implementation'$where (fail-closed; unknown/typo/blank never defaults open)"
}
