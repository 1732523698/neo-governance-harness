# orch_diff.ps1 - NEO 4.0-P4-AUTONOMY C1C3-S2a DIFF ENFORCEMENT (ADDITIVE).
# ASCII-only (D10). Dot-source; defines functions only.
#
# CROWN JEWEL / COORDINATION-only: this module CLASSIFIES and REFUSES; it NEVER
# writes an AUDIT_RESULT, never emits a GO, never ACTS on the diff. The loop that
# ACTS is S3. Fail-closed: every refusal routes through New-NeoBlock (throw
# "NEO-BLOCK: ...") so a reason_code always surfaces. Strictly serial; batching is
# report collection only.
#
# ADDITIVE WRAPPER (Raphael-approved, NF-1): the dispatch-time three-branch lives
# HERE and DELEGATES to the frozen orch_engine/orch_class/orch_schema functions
# READ-ONLY. It NEVER edits them. Binding spec: NEO_SELF_ITERATION_DESIGN_v3_1.md
# section 4 C1b lines 60-102 (baseline I2/NF-3, classifier I5 three branches, XC1
# canonical containment) + NF-1 (dispatch-time routing) + NF-3 (git required).
#
# Governance hash manifest (I3), builder FS-deny, and C1c are S2b - NOT this slice.

$script:NeoDiffDir = $PSScriptRoot
# orch_io dot-sources orch_schema + orch_class itself (functions/script-vars only,
# no top-level side effects) and defines New-NeoBlock. Sourcing it read-only gives
# the whole reused surface in one chain: New-NeoBlock (fail-closed sink),
# Assert-NeoSafeRel / Assert-NeoContained (rel-safety; XC1 extends), and
# Resolve-NeoArtifactClass / Get-NeoClassMap (the read-only class ORACLE).
. "$script:NeoDiffDir\orch_io.ps1"
# _neo_root.ps1 defines Resolve-NeoRoot ONLY (no side effects). Dot-sourced
# READ-ONLY so the judging-class ORACLE loads from the NEO GOVERNED ROOT
# (Resolve-NeoRoot $PSScriptRoot), NOT the attacker-influenceable app RepoRoot -
# the same decouple C2-FIX used for the schema dir. orch_diff.ps1 lives at
# .neo\scripts\orchestrator, so _neo_root.ps1 (.neo\scripts) is one level up.
. "$script:NeoDiffDir\..\_neo_root.ps1"

# ---- Resolve-NeoGovernanceMapPath (F1: oracle from the NEO governed root) ----
# The judging-class ORACLE is ALWAYS the engine's OWN artifact_classes.json under
# the NEO governed root - never the app RepoRoot's (a real app repo has no .neo,
# and a planted app map is a tamper vector). Resolve-NeoRoot walks UP from this
# module to the first ancestor holding BOTH .neo and .claude; it THROWS loud if
# none exists. Unresolvable root OR absent map => BLOCK NO_GOVERNANCE_MAP
# (fail-closed) - the classifier NEVER leaves class UNKNOWN-by-default.
#
# S2a-FIX-2 F1 (MODULE-PATH canonicalization): $script:NeoDiffDir = $PSScriptRoot
# is the SPELLING this module was dot-sourced through. If that spelling is a
# JUNCTION/symlink under an app tree that ALSO plants .neo + .claude at the
# junction-spelled ancestor, Resolve-NeoRoot would walk UP the APP-spelled path
# and select the APP ancestor - redirecting the oracle to the app's PLANTED map
# (the RepoRoot tamper vector reopened at the module-path layer). FIX: canonicalize
# the module dir to its REAL filesystem path FIRST, reusing the module's existing
# XC1 real-path helper Get-NeoRealPath (reparse/junction-resolving; NOT duplicated),
# so a junctioned module dir resolves to its REAL governed location before the walk.
#
# RESIDUAL (tamper-EVIDENT boundary; spec sec-0 / NB-4 - NOT closed here, by design):
# an attacker who can PHYSICALLY place/redirect the engine's OWN install (a real copy
# of orch_diff.ps1 / _neo_root.ps1 / the governed tree under an app tree) is the
# irreducible boundary. Canonicalization cannot defeat a genuine relocated install
# (its real path IS the attacker's tree). That is closed by the S2b governance HASH
# MANIFEST (which hashes orch_diff.ps1 + _neo_root.ps1 + the governed tree every
# round) + custody, NOT by this diff-classifier - and is impossible to make
# tamper-PROOF on a shared single-user FS. This slice deliberately does NOT attempt
# engine tamper-proofness against its own compromised install (out of scope).
function Resolve-NeoGovernanceMapPath {
  $neoRoot = $null
  # F1: canonicalize the module dir to its REAL path (resolve junction/symlink/
  # reparse spelling) BEFORE Resolve-NeoRoot walks, so a junctioned module dir
  # resolves to its real governed location instead of the junction-spelled ancestor.
  # S2a-FIX-3 (fail-closed): the module dir is orch_diff.ps1's OWN physical load dir
  # and is ALWAYS resolvable in a legitimate run. If Get-NeoRealPath THROWS we MUST
  # NOT fall back to the un-canonicalized (attacker-spelled) $script:NeoDiffDir - that
  # would let Resolve-NeoRoot walk the app-spelled junctioned ancestor and select a
  # PLANTED map (the S2a-FIX-2 junction-redirect reopened on the error path). BLOCK
  # reason_code=MODULE_ROOT_UNRESOLVABLE (surface the module dir + inner message).
  $moduleReal = $null
  try { $moduleReal = Get-NeoRealPath -Path $script:NeoDiffDir }
  catch { New-NeoBlock "reason_code=MODULE_ROOT_UNRESOLVABLE cannot canonicalize module root '$($script:NeoDiffDir)' (fail-closed; never falls back to the un-canonicalized path): $($_.Exception.Message)" }
  try { $neoRoot = Resolve-NeoRoot $moduleReal }
  catch { New-NeoBlock "reason_code=NO_GOVERNANCE_MAP cannot resolve NEO governed root for the judging oracle: $($_.Exception.Message)" }
  if ([string]::IsNullOrWhiteSpace($neoRoot)) {
    New-NeoBlock "reason_code=NO_GOVERNANCE_MAP NEO governed root resolved empty for the judging oracle"
  }
  $mapPath = Join-Path $neoRoot '.neo\schema\artifact_classes.json'
  if (-not (Test-Path -LiteralPath $mapPath -PathType Leaf)) {
    New-NeoBlock "reason_code=NO_GOVERNANCE_MAP judging-class map not found under the NEO governed root: $mapPath"
  }
  return $mapPath
}

# ---- git helper (LOCAL tool; no network) ------------------------------------
# Runs git -C <RepoRoot> with the given args, returns { code; out (array) }.
# All git invocations funnel here so a git failure is a single, testable surface.
function Invoke-NeoGit {
  param([string]$RepoRoot, [string[]]$GitArgs)
  if ([string]::IsNullOrWhiteSpace($RepoRoot)) { New-NeoBlock "Invoke-NeoGit: RepoRoot required" }
  $all = @('-C', $RepoRoot) + $GitArgs
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $out = & git @all 2>&1 }
  catch { $ErrorActionPreference = $prev; New-NeoBlock "git invocation failed ($($GitArgs -join ' ')): $($_.Exception.Message)" }
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $lines = @()
  foreach ($l in @($out)) { $lines += ([string]$l) }
  return [pscustomobject]@{ code = [int]$code; out = $lines }
}

# Asserts RepoRoot is a git work tree; returns the resolved absolute root.
# No repo => BLOCK NO_REPO (NF-3: the snapshot-only lane is REFUSED).
function Assert-NeoGitRepo {
  param([string]$RepoRoot)
  if ([string]::IsNullOrWhiteSpace($RepoRoot)) { New-NeoBlock "reason_code=NO_REPO RepoRoot is empty" }
  if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    New-NeoBlock "reason_code=NO_REPO RepoRoot does not exist: $RepoRoot"
  }
  $r = Invoke-NeoGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--is-inside-work-tree')
  if ($r.code -ne 0 -or (@($r.out) -join '').Trim() -notmatch '^true') {
    New-NeoBlock "reason_code=NO_REPO not a git work tree: $RepoRoot"
  }
  return ([System.IO.Path]::GetFullPath($RepoRoot))
}

# ---- Pin-NeoDispatchBaseline (NF-3 baseline; PURE - returns an object) --------
# REQUIRE a git repo at RepoRoot else BLOCK NO_REPO. Returns
#   { head_sha; tree_hash; pinned_at }
# tree_hash is a DETERMINISTIC snapshot hash over the tracked+untracked tree
# (sorted path + git blob id / content hash). Persistence is S3's job: this
# function writes NOTHING and adds NO schema.
function Pin-NeoDispatchBaseline {
  param([string]$RepoRoot)
  $root = Assert-NeoGitRepo -RepoRoot $RepoRoot

  $head = Invoke-NeoGit -RepoRoot $root -GitArgs @('rev-parse', 'HEAD')
  if ($head.code -ne 0) {
    # unborn branch (no commit yet) - pin the empty-tree sentinel deterministically
    $headSha = '0000000000000000000000000000000000000000'
  } else {
    $headSha = (@($head.out) -join '').Trim()
  }

  # Deterministic tree snapshot: tracked (ls-files) + untracked (status) unioned,
  # each paired with a content hash, sorted, then hashed as one blob.
  $entries = New-Object System.Collections.Generic.List[string]
  $tracked = Invoke-NeoGit -RepoRoot $root -GitArgs @('ls-files', '-z')
  $untr    = Invoke-NeoGit -RepoRoot $root -GitArgs @('ls-files', '--others', '--exclude-standard', '-z')
  $paths = @{}
  foreach ($blob in @($tracked.out) + @($untr.out)) {
    foreach ($p in ($blob -split "`0")) {
      $pp = ([string]$p).Trim()
      if ($pp) { $paths[$pp] = $true }
    }
  }
  foreach ($rel in ($paths.Keys | Sort-Object)) {
    $full = Join-Path $root $rel
    $ch = ''
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      try { $ch = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash } catch { $ch = 'UNREADABLE' }
    } else { $ch = 'DIR-OR-GONE' }
    $entries.Add("$rel`:$ch")
  }
  $joined = ($entries -join "`n")
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
    $treeHash = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
  } finally { $sha.Dispose() }

  return [pscustomobject]@{
    head_sha  = $headSha
    tree_hash = $treeHash
    pinned_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
}

# ---- Get-NeoChangedSet (I2/NF-3) --------------------------------------------
# CHANGED SET = diff(baseline.head_sha .. current worktree) INCLUDING committed
# changes AND untracked AND ignored files. Union of:
#   git diff --name-only <sha>                       (committed vs baseline)
#   git status --porcelain -uall --ignored           (worktree incl untracked+ignored)
# BUILDER-COMMIT DETECTION: current HEAD != baseline.head_sha => BLOCK BUILDER_COMMIT.
# The declared-file fallback (CHANGED_FILES.txt) is PROHIBITED - never read.
function Get-NeoChangedSet {
  param([string]$RepoRoot, $Baseline)
  $root = Assert-NeoGitRepo -RepoRoot $RepoRoot
  if ($null -eq $Baseline -or [string]::IsNullOrWhiteSpace([string]$Baseline.head_sha)) {
    New-NeoBlock "reason_code=NO_BASELINE Get-NeoChangedSet requires a pinned Baseline with head_sha"
  }
  $baseSha = [string]$Baseline.head_sha

  # builder-commit detection
  $head = Invoke-NeoGit -RepoRoot $root -GitArgs @('rev-parse', 'HEAD')
  if ($head.code -eq 0) {
    $curr = (@($head.out) -join '').Trim()
    if ($curr -and $curr -ne $baseSha) {
      New-NeoBlock "reason_code=BUILDER_COMMIT HEAD moved after baseline ($baseSha -> $curr); commits are forbidden in the dispatch contract"
    }
  }

  $set = @{}

  # committed changes vs baseline sha (only meaningful when baseline had a commit)
  if ($baseSha -and $baseSha -notmatch '^0+$') {
    $diff = Invoke-NeoGit -RepoRoot $root -GitArgs @('diff', '--name-only', '-z', $baseSha)
    if ($diff.code -ne 0) { New-NeoBlock "reason_code=GIT_ERROR git diff against baseline failed: $((@($diff.out)) -join ' ')" }
    foreach ($p in ((@($diff.out) -join '') -split "`0")) {
      $pp = ([string]$p).Trim(); if ($pp) { $set[$pp] = $true }
    }
  }

  # worktree: untracked + ignored + modified/staged via porcelain -uall --ignored
  $st = Invoke-NeoGit -RepoRoot $root -GitArgs @('status', '--porcelain', '-uall', '--ignored', '-z')
  if ($st.code -ne 0) { New-NeoBlock "reason_code=GIT_ERROR git status failed: $((@($st.out)) -join ' ')" }
  # -z porcelain records are NUL-separated; a rename record ("R  old -> new") uses a
  # second NUL for the origin path. Parse defensively: strip the 3-char XY+space
  # prefix, take the entry after any ' -> ' as the current path.
  $recs = ((@($st.out) -join '') -split "`0") | Where-Object { $_ -ne '' }
  foreach ($rec in $recs) {
    $line = [string]$rec
    if ($line.Length -lt 4) { continue }
    $pathPart = $line.Substring(3)
    if ($pathPart -match ' -> ') { $pathPart = ($pathPart -split ' -> ')[-1] }
    $pp = $pathPart.Trim().Trim('"')
    if ($pp) { $set[$pp] = $true }
  }

  return @($set.Keys | Sort-Object)
}

# ---- Assert-NeoCanonicalContained (XC1 canonicalizer) ------------------------
# Closes the carried symlink/reparse residual (a) for loop surfaces.
#   1. Assert-NeoSafeRel first (reject traversal/backslash/rooted/drive spellings).
#   2. Canonicalize Rel to its REAL filesystem path: resolve any junction/symlink/
#      reparse point in the ancestor chain to its link target (Windows: Get-Item
#      -Force .Target on ReparsePoint components), rebuild, GetFullPath.
#   3. Normalize case per Windows semantics (comparisons are OrdinalIgnoreCase).
#   4. Real path escapes RepoRoot => BLOCK PATH_ESCAPE.
# Returns the canonical absolute path. A path that APPEARS inside RepoRoot but
# RESOLVES elsewhere => BLOCK. Glob/containment downstream runs ONLY on this.
function Get-NeoRealPath {
  param([string]$Path)
  # Component-walk canonicalizer (PS 5.1 safe; no .NET6 ResolveLinkTarget, no P/Invoke).
  # Resolves reparse points (junctions) in each existing ancestor to their target.
  $full = [System.IO.Path]::GetFullPath($Path)
  $sep = [System.IO.Path]::DirectorySeparatorChar
  $root = [System.IO.Path]::GetPathRoot($full)
  $rest = $full.Substring($root.Length)
  $segs = @($rest -split '[\\/]+' | Where-Object { $_ -ne '' })
  $cur = $root.TrimEnd($sep, [char]0x2F)
  if ([string]::IsNullOrEmpty($cur)) { $cur = $root }
  foreach ($seg in $segs) {
    $cur = Join-Path $cur $seg
    if (Test-Path -LiteralPath $cur) {
      # S2a-FIX-4 (HOLISTIC fail-closed - class closer): this component EXISTS
      # (Test-Path true). Inspect it fail-CLOSED. The prior bare -ErrorAction
      # SilentlyContinue left $it=$null for an existing-but-uninspectable component
      # (lock/permission/unsupported reparse tag/etc.), which SKIPPED the reparse check
      # and CONTINUED the walk on an UNINSPECTABLE component => a component that MAY be
      # a reparse point was left unresolved in the returned path (fail-open, the same
      # class as the FIX-3 target-lookup swallow). Now: if an EXISTING component cannot
      # be inspected (Get-Item throws OR returns null) we BLOCK - an existing component
      # we cannot inspect is UNTRUSTED (a redirect is possible). This guard fires ONLY
      # on Test-Path-true + Get-Item-null: a Test-Path-false (not-yet-existing) leaf
      # never reaches here, and a NORMAL component or a RESOLVABLE junction returns a
      # non-null $it and proceeds unchanged (no over-block).
      $it = $null; $itErr = ''
      try { $it = Get-Item -LiteralPath $cur -Force -ErrorAction Stop }
      catch { $itErr = $_.Exception.Message }
      if (-not $it) {
        $why = if ($itErr) { "inspection failed: $itErr" } else { 'metadata unavailable' }
        New-NeoBlock "reason_code=PATH_ESCAPE component '$cur' exists but cannot be inspected ($why) - uninspectable existing component, untrusted redirect possible, fail-closed"
      }
      if (($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        # S2a-FIX-3 (fail-closed): this component IS a reparse point. If its TARGET
        # cannot be resolved (Target lookup throws, OR returns null/empty) we MUST NOT
        # leave the unresolved reparse in the returned path and continue - a redirect
        # we cannot resolve is UNTRUSTED, and downstream containment/oracle decisions
        # would then run on a path still carrying an unresolved reparse (fail-open).
        # BLOCK reason_code=PATH_ESCAPE. A NORMAL, RESOLVABLE reparse has a non-null
        # target and falls straight through to the existing resolve/recurse unchanged
        # (no over-block).
        $tgt = $null; $tgtErr = ''
        try { $tgt = @($it.Target)[0] } catch { $tgtErr = $_.Exception.Message }
        if ([string]::IsNullOrWhiteSpace($tgt)) {
          $why = if ($tgtErr) { "target lookup failed: $tgtErr" } else { 'target is null/empty' }
          New-NeoBlock "reason_code=PATH_ESCAPE reparse point '$cur' has an unresolvable target ($why) - untrusted redirect, fail-closed"
        }
        if (-not [System.IO.Path]::IsPathRooted($tgt)) { $tgt = Join-Path (Split-Path -Parent $cur) $tgt }
        # recurse in case the target itself traverses another reparse point
        $cur = Get-NeoRealPath -Path $tgt
      }
    }
  }
  return [System.IO.Path]::GetFullPath($cur)
}

function Assert-NeoCanonicalContained {
  param([string]$RepoRoot, [string]$Rel)
  # (1) rel-safety first (reuse frozen helper: rejects backslash/rooted/drive/'..')
  Assert-NeoSafeRel $Rel
  $rootReal = Get-NeoRealPath -Path ([System.IO.Path]::GetFullPath($RepoRoot))
  $probe = $Rel -replace '^\./', ''
  $joined = Join-Path $rootReal $probe
  # (2)/(3) resolve to REAL path (reparse-aware) and normalize
  $real = Get-NeoRealPath -Path $joined
  # (4) containment on the CANONICAL result only
  $rootWithSep = $rootReal.TrimEnd([char]0x5C, [char]0x2F) + [System.IO.Path]::DirectorySeparatorChar
  $realCmp = $real.TrimEnd([char]0x5C, [char]0x2F)
  if (($realCmp + [System.IO.Path]::DirectorySeparatorChar) -ne $rootWithSep) {
    if (-not $real.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {
      New-NeoBlock "reason_code=PATH_ESCAPE '$Rel' resolves to '$real' which is not under RepoRoot '$rootReal'"
    }
  }
  return $real
}

# ---- three-branch classifier (I5, the CORE) ---------------------------------
# Get-NeoChangeClassification: canonicalize FIRST, then apply branches IN ORDER:
#   (1) JUDGING class (Resolve-NeoArtifactClass in {constraint,test_harness,
#       profile_risk}) OR matches ProtectedPaths => 'STOP-JUDGING'
#   (2) NOT within ApprovedPaths => 'STOP-OUTSIDE'
#   (3) within ApprovedPaths and class UNKNOWN => 'IMPLEMENTATION'
# Every ApprovedPaths/ProtectedPaths entry is ALSO XC1-canonicalized before match.
$script:NeoJudgingClasses = @('constraint', 'test_harness', 'profile_risk')

# Canonicalize a repo-relative approved/protected GOVERNANCE entry to its real
# absolute prefix. F2 (fail-closed): governance entries come from C5-frozen
# authority - a MALFORMED entry (blank/whitespace, traversal '..', backslash,
# rooted/drive, or UNC per Assert-NeoSafeRel) must NEVER be silently dropped
# (returning $null made it vanish from matching => a protected edit fell through
# to IMPLEMENTATION - a fail-open). Instead => BLOCK MALFORMED_SCOPE_ENTRY,
# surfacing the offending entry. Legit entries canonicalize + match as before.
# $Kind is 'approved' | 'protected' (surfaced in the reason for triage).
function Get-NeoCanonPrefix {
  param([string]$RepoRoot, [string]$Entry, [string]$Kind = 'scope')
  if ([string]::IsNullOrWhiteSpace($Entry)) {
    New-NeoBlock "reason_code=MALFORMED_SCOPE_ENTRY $Kind entry is blank/whitespace (fail-closed; not silently dropped)"
  }
  $e = ($Entry -replace '\\', '/').TrimEnd('/')
  # entries are repo-relative; run through safe-rel then real-path canonicalization.
  try { Assert-NeoSafeRel $e }
  catch { New-NeoBlock "reason_code=MALFORMED_SCOPE_ENTRY $Kind entry unusable (traversal/rooted/backslash/UNC): '$Entry'" }
  $rootReal = Get-NeoRealPath -Path ([System.IO.Path]::GetFullPath($RepoRoot))
  $joined = Join-Path $rootReal ($e -replace '^\./', '')
  return (Get-NeoRealPath -Path $joined)
}

function Test-NeoUnderPrefix {
  param([string]$Real, [string]$Prefix)
  if ([string]::IsNullOrEmpty($Prefix)) { return $false }
  $p = $Prefix.TrimEnd([char]0x5C, [char]0x2F)
  $r = $Real.TrimEnd([char]0x5C, [char]0x2F)
  if ($r -ieq $p) { return $true }
  return $r.StartsWith($p + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-NeoChangeClassification {
  param(
    [string]$RepoRoot,
    [string]$Rel,
    [string[]]$ApprovedPaths,
    [string[]]$ProtectedPaths
  )
  # F2 fail-closed: validate ALL governance entries up front so a malformed entry
  # BLOCKs deterministically (never masked by an earlier valid-entry match/break).
  foreach ($pp in @($ProtectedPaths)) { [void](Get-NeoCanonPrefix -RepoRoot $RepoRoot -Entry $pp -Kind 'protected') }
  foreach ($ap in @($ApprovedPaths))  { [void](Get-NeoCanonPrefix -RepoRoot $RepoRoot -Entry $ap -Kind 'approved') }

  # canonicalize the changed path FIRST (XC1)
  $real = Assert-NeoCanonicalContained -RepoRoot $RepoRoot -Rel $Rel

  # class resolution via the frozen oracle (read-only). F1: the ORACLE map is the
  # engine's OWN map under the NEO governed root (Resolve-NeoGovernanceMapPath),
  # NEVER the app RepoRoot - so an app repo without .neo cannot silently disable
  # judging protection and a planted app map is never consulted (tamper closed).
  # Unresolvable/absent/invalid map => BLOCK NO_GOVERNANCE_MAP (fail-closed, no
  # UNKNOWN-by-default). Feed the app-repo-RELATIVE spelling (leaf + full both
  # matched by Resolve-NeoArtifactClass -like globs).
  $mapPath = Resolve-NeoGovernanceMapPath
  # F2 (S2a-FIX-2, reason-code contract): Resolve-NeoGovernanceMapPath already
  # surfaces NO_GOVERNANCE_MAP for an unresolvable root / absent map, but an
  # INVALID-JSON governed map flows through the FROZEN Get-NeoClassMap as a raw
  # `throw "NEO-BLOCK: artifact_classes map is invalid JSON"` WITHOUT the reason_code.
  # Wrap the load at the CALL SITE (orch_class.ps1 stays byte-identical) so invalid
  # JSON - and ANY load failure - ALSO BLOCKs reason_code=NO_GOVERNANCE_MAP
  # (still fail-closed; now contract-complete). Surface the offending map path.
  $map = $null
  try { $map = Get-NeoClassMap $mapPath }
  catch { New-NeoBlock "reason_code=NO_GOVERNANCE_MAP judging-class map failed to load (invalid JSON or unreadable): $mapPath ($($_.Exception.Message))" }
  $cls = Resolve-NeoArtifactClass $map ($Rel -replace '\\', '/')

  # (1) JUDGING class OR protected
  if ($script:NeoJudgingClasses -contains $cls) { return 'STOP-JUDGING' }
  foreach ($pp in @($ProtectedPaths)) {
    $canon = Get-NeoCanonPrefix -RepoRoot $RepoRoot -Entry $pp -Kind 'protected'
    if (Test-NeoUnderPrefix -Real $real -Prefix $canon) { return 'STOP-JUDGING' }
  }

  # (2) NOT within approved
  $inApproved = $false
  foreach ($ap in @($ApprovedPaths)) {
    $canon = Get-NeoCanonPrefix -RepoRoot $RepoRoot -Entry $ap -Kind 'approved'
    if (Test-NeoUnderPrefix -Real $real -Prefix $canon) { $inApproved = $true; break }
  }
  if (-not $inApproved) { return 'STOP-OUTSIDE' }

  # (3) within approved + class UNKNOWN => implementation permitted
  return 'IMPLEMENTATION'
}

# ---- Assert-NeoChangedSetAllowed (post-diff aggregate) ----------------------
# Classify EVERY changed path; ANY STOP-JUDGING => BLOCK JUDGING_OR_PROTECTED;
# ANY STOP-OUTSIDE => BLOCK OUTSIDE_APPROVED (offending path surfaced). An empty
# ChangedSet returns clean here (the empty-ProposedEdits STOP is the dispatch-time
# guard below).
function Assert-NeoChangedSetAllowed {
  param(
    [string]$RepoRoot,
    [string[]]$ChangedSet,
    [string[]]$ApprovedPaths,
    [string[]]$ProtectedPaths
  )
  foreach ($rel in @($ChangedSet)) {
    if ([string]::IsNullOrWhiteSpace($rel)) { continue }
    $c = Get-NeoChangeClassification -RepoRoot $RepoRoot -Rel $rel -ApprovedPaths $ApprovedPaths -ProtectedPaths $ProtectedPaths
    switch ($c) {
      'STOP-JUDGING' { New-NeoBlock "reason_code=JUDGING_OR_PROTECTED changed path resolves judging/protected: $rel" }
      'STOP-OUTSIDE' { New-NeoBlock "reason_code=OUTSIDE_APPROVED changed path outside approved_paths: $rel" }
      'IMPLEMENTATION' { }
      default { New-NeoBlock "reason_code=CLASSIFIER_ERROR unexpected classification '$c' for: $rel" }
    }
  }
  return $true
}

# ---- Assert-NeoDispatchProposedEdits (NF-1 dispatch-time, ADDITIVE WRAPPER) ---
# An autonomous dispatch declaring NO proposed edits => BLOCK EMPTY_PROPOSED_EDITS
# (the fail-open dodge is refused). For each proposed edit apply the SAME
# three-branch (via Get-NeoChangeClassification): approved+UNKNOWN => routes
# implementation (permitted); judging/protected => STOP; outside approved => STOP.
# The three-branch decision is made HERE; orch_engine/orch_class stay byte-identical.
function Assert-NeoDispatchProposedEdits {
  param(
    [string]$RepoRoot,
    [string[]]$ProposedEdits,
    [string[]]$ApprovedPaths,
    [string[]]$ProtectedPaths
  )
  $edits = @($ProposedEdits | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($edits.Count -eq 0) {
    New-NeoBlock "reason_code=EMPTY_PROPOSED_EDITS autonomous dispatch declares no proposed edits (fail-open dodge refused)"
  }
  $routes = @()
  foreach ($rel in $edits) {
    $c = Get-NeoChangeClassification -RepoRoot $RepoRoot -Rel $rel -ApprovedPaths $ApprovedPaths -ProtectedPaths $ProtectedPaths
    switch ($c) {
      'STOP-JUDGING' { New-NeoBlock "reason_code=JUDGING_OR_PROTECTED proposed edit resolves judging/protected: $rel" }
      'STOP-OUTSIDE' { New-NeoBlock "reason_code=OUTSIDE_APPROVED proposed edit outside approved_paths: $rel" }
      'IMPLEMENTATION' { $routes += [pscustomobject]@{ path = $rel; route = 'implementation' } }
      default { New-NeoBlock "reason_code=CLASSIFIER_ERROR unexpected classification '$c' for: $rel" }
    }
  }
  return $routes
}
