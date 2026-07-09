# orch_diff_suite.ps1 - NEO 4.0-P4-AUTONOMY C1C3-S2a(-FIX) INDEPENDENT diff-enforcement harness.
# ASCII-only (D10). Kept SEPARATE from the module it tests.
#
# Proves orch_diff.ps1 fails closed on the C1b post-diff + NF-1 dispatch-time
# surface: baseline/changed-set (I2/NF-3 incl untracked+ignored + builder-commit
# detection), the I5 three-branch classifier, and the XC1 canonical-containment
# battery (traversal, junction/reparse escape, case normalization; symlink attempted
# with HONEST disclosure if privilege is unavailable).
#
# S2a-FIX additions (judging-oracle root + malformed-entry fail-closed):
#   - N-S2A-JUDGING now tests the REAL deployment: an app repo WITHOUT .neo, a
#     judging-named file (orch_*.ps1 / *.schema.json) inside an approved path =>
#     STOP-JUDGING via the NEO-GOVERNED-ROOT map (not the app RepoRoot's).
#   - N-S2A-TAMPER-MAP: app repo PLANTS a permissive .neo/schema map => IGNORED,
#     STILL STOP-JUDGING (tamper vector closed).
#   - N-S2A-NO-GOVMAP: NEO-root unresolvable (module chain copied to a no-ancestor
#     scratch dir) => BLOCK NO_GOVERNANCE_MAP (fail-closed; no UNKNOWN-by-default).
#   - N-S2A-MALFORMED-PROTECTED / -APPROVED: a malformed governance entry
#     (whitespace / traversal / rooted) => BLOCK MALFORMED_SCOPE_ENTRY (never
#     silently dropped).
# S2a-FIX-2 additions (module-path canonicalization + reason-code contract):
#   - N-S2A-JUNCTION-MODULE-ROOT (F1): module dot-sourced via a JUNCTION whose real
#     target is a governed mirror (real map), under an app tree that plants its own
#     .neo+.claude + permissive map => the module dir is canonicalized to its REAL
#     governed location => STILL STOP-JUDGING (planted-at-junction map ignored).
#   - N-S2A-INVALID-GOVMAP (F2): a governed root that RESOLVES but whose
#     artifact_classes.json is INVALID JSON => BLOCK NO_GOVERNANCE_MAP (the
#     invalid-JSON case now carries the reason_code; orch_class stays frozen).
# Writes NO AUDIT_RESULT; synthetic fixtures + throwaway git repos in scratch under
# $env:TEMP; residue-clean SECOND PASS removes every repo. exit 0/1.
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'

$orchDir = Split-Path -Parent $PSScriptRoot   # ...\.neo\scripts\orchestrator
. "$orchDir\orch_diff.ps1"                     # dot-sources orch_class + orch_schema -> orch_io chain

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_orch_s2a_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors orch_router_suite framing) ---------------------
$script:results = @()
function Record($name, $pass, $detail, $kind = 'negative') {
  $script:results += [pscustomobject]@{ guard = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  $ktag = if ($kind -eq 'negative') { 'GUARD' } elseif ($kind -eq 'skip') { 'SKIP ' } else { 'info ' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $ktag, $name, $detail) -ForegroundColor $col
}
function Expect-Block($name, $codeSubstr, $sb) {
  try { & $sb; Record $name $false 'NO BLOCK (guard did not fire)' 'negative' }
  catch {
    $m = $_.Exception.Message
    if ($m -like 'NEO-BLOCK:*') {
      if ($codeSubstr -and ($m -notlike "*$codeSubstr*")) {
        Record $name $false ("BLOCK but wrong reason (want $codeSubstr): " + $m) 'negative'
      } else { Record $name $true $m 'negative' }
    } else { Record $name $false ('threw non-BLOCK: ' + $m) 'negative' }
  }
}
function Expect-Ok($name, $sb) {
  try { $r = & $sb; Record $name $true "$r" 'positive' }
  catch { Record $name $false ('unexpected block/error: ' + $_.Exception.Message) 'positive' }
}
function Expect-Value($name, $want, $sb) {
  try { $r = & $sb
    if ("$r" -eq "$want") { Record $name $true "= $r" 'positive' }
    else { Record $name $false ("got '$r' want '$want'") 'positive' }
  } catch { Record $name $false ('unexpected error: ' + $_.Exception.Message) 'positive' }
}

# ---- git fixture builders (throwaway repos in scratch; pinned local identity) -
$script:repoSeq = 0
function New-NeoRepo {
  param([switch]$NoInit)
  $script:repoSeq++
  $repo = Join-Path $ScratchRoot ("repo{0}" -f $script:repoSeq)
  New-Item -ItemType Directory -Force -Path $repo | Out-Null
  if (-not $NoInit) {
    Invoke-NeoGitQuiet $repo @('init','-q')
    Invoke-NeoGitQuiet $repo @('config','user.email','neo@sandbox.local')
    Invoke-NeoGitQuiet $repo @('config','user.name','neo-fixture')
    Invoke-NeoGitQuiet $repo @('config','commit.gpgsign','false')
    Invoke-NeoGitQuiet $repo @('config','core.autocrlf','false')  # silence LF/CRLF stderr warnings
    Invoke-NeoGitQuiet $repo @('config','core.safecrlf','false')
  }
  return $repo
}
# Fixture-local git runner: swallows stdout+stderr so native warnings (e.g. CRLF)
# never trip the suite's ErrorActionPreference=Stop. Not the module's Invoke-NeoGit.
function Invoke-NeoGitQuiet { param([string]$Repo, [string[]]$GitArgs)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & git -C $Repo @GitArgs 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
}
function Commit-NeoRepo { param([string]$Repo, [string]$Msg = 'c')
  Invoke-NeoGitQuiet $Repo @('add','-A')
  Invoke-NeoGitQuiet $Repo @('commit','-q','-m',$Msg)
}
function Write-NeoFile { param([string]$Repo, [string]$Rel, [string]$Body = 'x')
  $full = Join-Path $Repo $Rel
  $dir = Split-Path -Parent $full
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Set-Content -LiteralPath $full -Value $Body -Encoding Ascii
}

Write-Host "== orch_diff_suite (C1C3-S2a) ==" -ForegroundColor Cyan

# =============================================================================
# BASELINE / CHANGED-SET (I2 / NF-3)
# =============================================================================

# N-S2A-NO-REPO : no git repo => BLOCK NO_REPO
$noRepo = New-NeoRepo -NoInit
Expect-Block 'N-S2A-NO-REPO' 'NO_REPO' { Pin-NeoDispatchBaseline -RepoRoot $noRepo }

# P-S2A-CHANGED-TRACKED : committed baseline, edit tracked file => appears
$r1 = New-NeoRepo
Write-NeoFile -Repo $r1 -Rel 'app/tracked.txt' -Body 'v1'
Commit-NeoRepo -Repo $r1
$b1 = Pin-NeoDispatchBaseline -RepoRoot $r1
Write-NeoFile -Repo $r1 -Rel 'app/tracked.txt' -Body 'v2-edited'
Expect-Ok 'P-S2A-CHANGED-TRACKED' {
  $cs = Get-NeoChangedSet -RepoRoot $r1 -Baseline $b1
  if ($cs -contains 'app/tracked.txt') { 'tracked edit appears' } else { throw "missing: $($cs -join ',')" }
}

# P-S2A-UNTRACKED : new untracked file => appears
$r2 = New-NeoRepo
Write-NeoFile -Repo $r2 -Rel 'app/seed.txt' -Body 's'
Commit-NeoRepo -Repo $r2
$b2 = Pin-NeoDispatchBaseline -RepoRoot $r2
Write-NeoFile -Repo $r2 -Rel 'app/newfile.txt' -Body 'brand new'
Expect-Ok 'P-S2A-UNTRACKED' {
  $cs = Get-NeoChangedSet -RepoRoot $r2 -Baseline $b2
  if ($cs -contains 'app/newfile.txt') { 'untracked appears' } else { throw "missing untracked: $($cs -join ',')" }
}

# P-S2A-IGNORED : .gitignore'd file => STILL appears (union must catch it)
$r3 = New-NeoRepo
Write-NeoFile -Repo $r3 -Rel '.gitignore' -Body 'ignored/'
Write-NeoFile -Repo $r3 -Rel 'app/seed.txt' -Body 's'
Commit-NeoRepo -Repo $r3
$b3 = Pin-NeoDispatchBaseline -RepoRoot $r3
Write-NeoFile -Repo $r3 -Rel 'ignored/secret.txt' -Body 'should still be seen'
Expect-Ok 'P-S2A-IGNORED' {
  $cs = Get-NeoChangedSet -RepoRoot $r3 -Baseline $b3
  if ($cs -contains 'ignored/secret.txt') { 'ignored file appears (union caught it)' } else { throw "ignored MISSED: $($cs -join ',')" }
}

# N-S2A-BUILDER-COMMIT : HEAD moved after baseline => BLOCK BUILDER_COMMIT
$r4 = New-NeoRepo
Write-NeoFile -Repo $r4 -Rel 'app/a.txt' -Body 'a'
Commit-NeoRepo -Repo $r4
$b4 = Pin-NeoDispatchBaseline -RepoRoot $r4
Write-NeoFile -Repo $r4 -Rel 'app/b.txt' -Body 'b'
Commit-NeoRepo -Repo $r4 'builder illegal commit'
Expect-Block 'N-S2A-BUILDER-COMMIT' 'BUILDER_COMMIT' { Get-NeoChangedSet -RepoRoot $r4 -Baseline $b4 }

# =============================================================================
# THREE-BRANCH CLASSIFIER (I5)  -- S2a-FIX: the judging ORACLE is the NEO GOVERNED
# ROOT's own artifact_classes.json (Resolve-NeoRoot $PSScriptRoot), NOT the app
# RepoRoot. So the classifier repos are REAL app repos WITHOUT a .neo governance
# tree - proving judging protection fires with no app map (F1) and that a planted
# app map is ignored (tamper). orch_*.ps1 => test_harness, *.schema.json =>
# constraint via the engine's OWN map.
# =============================================================================
# Build a REAL-shape app repo: NO .neo/schema; just app files + a commit.
function New-NeoAppRepo {
  $repo = New-NeoRepo
  Write-NeoFile -Repo $repo -Rel 'app/keep.txt' -Body 'seed'
  Commit-NeoRepo -Repo $repo
  return $repo
}
$approved  = @('app')
$protected = @('.neo', 'app/locked.txt')

# N-S2A-JUDGING (REAL SHAPE): app repo WITHOUT .neo, judging-named files inside an
# approved path => STOP-JUDGING via the NEO-ROOT map. Covers BOTH judging globs:
# orch_*.ps1 => test_harness AND *.schema.json => constraint.
$cr = New-NeoAppRepo
if (Test-Path -LiteralPath (Join-Path $cr '.neo')) { throw 'fixture invariant broken: app repo unexpectedly has .neo' }
Write-NeoFile -Repo $cr -Rel 'app/orch_evil.ps1' -Body '# harness'   # orch_*.ps1 => test_harness
Write-NeoFile -Repo $cr -Rel 'app/x.schema.json' -Body '{}'          # *.schema.json => constraint
Expect-Value 'N-S2A-JUDGING' 'STOP-JUDGING' {
  Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/orch_evil.ps1' -ApprovedPaths $approved -ProtectedPaths $protected
}
Expect-Value 'N-S2A-JUDGING-SCHEMA' 'STOP-JUDGING' {
  Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/x.schema.json' -ApprovedPaths $approved -ProtectedPaths $protected
}

# N-S2A-TAMPER-MAP : the app PLANTS a permissive .neo/schema/artifact_classes.json
# (empty rules) to try to disable the oracle => IGNORED; the classifier STILL uses
# the NEO-ROOT map => judging-named file STILL => STOP-JUDGING (tamper closed).
$tr = New-NeoAppRepo
Write-NeoFile -Repo $tr -Rel '.neo/schema/artifact_classes.json' -Body '{ "rules": [] }'
Commit-NeoRepo -Repo $tr
Write-NeoFile -Repo $tr -Rel 'app/orch_evil.ps1' -Body '# harness'
Expect-Value 'N-S2A-TAMPER-MAP' 'STOP-JUDGING' {
  Get-NeoChangeClassification -RepoRoot $tr -Rel 'app/orch_evil.ps1' -ApprovedPaths $approved -ProtectedPaths $protected
}

# N-S2A-PROTECTED : matches protected_paths => STOP (surfaced as STOP-JUDGING branch 1)
Write-NeoFile -Repo $cr -Rel 'app/locked.txt' -Body 'do not touch'
Expect-Value 'N-S2A-PROTECTED' 'STOP-JUDGING' {
  Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/locked.txt' -ApprovedPaths $approved -ProtectedPaths $protected
}

# N-S2A-OUTSIDE : outside approved => STOP-OUTSIDE
Write-NeoFile -Repo $cr -Rel 'other/loose.txt' -Body 'nope'
Expect-Value 'N-S2A-OUTSIDE' 'STOP-OUTSIDE' {
  Get-NeoChangeClassification -RepoRoot $cr -Rel 'other/loose.txt' -ApprovedPaths $approved -ProtectedPaths $protected
}

# P-S2A-APPROVED-UNKNOWN : inside approved, unknown class => IMPLEMENTATION
Write-NeoFile -Repo $cr -Rel 'app/feature.py' -Body 'print(1)'
Expect-Value 'P-S2A-APPROVED-UNKNOWN' 'IMPLEMENTATION' {
  Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/feature.py' -ApprovedPaths $approved -ProtectedPaths $protected
}

# Aggregate: a clean set passes, a poisoned set blocks
Expect-Ok 'P-S2A-AGG-CLEAN' {
  Assert-NeoChangedSetAllowed -RepoRoot $cr -ChangedSet @('app/feature.py') -ApprovedPaths $approved -ProtectedPaths $protected
  'clean set allowed'
}
Expect-Block 'N-S2A-AGG-JUDGING' 'JUDGING_OR_PROTECTED' {
  Assert-NeoChangedSetAllowed -RepoRoot $cr -ChangedSet @('app/feature.py','app/orch_evil.ps1') -ApprovedPaths $approved -ProtectedPaths $protected
}

# =============================================================================
# DISPATCH-TIME (NF-1)
# =============================================================================
# N-S2A-EMPTY-PROPOSED : empty ProposedEdits => BLOCK
Expect-Block 'N-S2A-EMPTY-PROPOSED' 'EMPTY_PROPOSED_EDITS' {
  Assert-NeoDispatchProposedEdits -RepoRoot $cr -ProposedEdits @() -ApprovedPaths $approved -ProtectedPaths $protected
}

# P-S2A-DISPATCH-APPROVED : approved+unknown proposed edit => routes implementation
Expect-Ok 'P-S2A-DISPATCH-APPROVED' {
  $routes = Assert-NeoDispatchProposedEdits -RepoRoot $cr -ProposedEdits @('app/feature.py') -ApprovedPaths $approved -ProtectedPaths $protected
  if (@($routes)[0].route -eq 'implementation') { 'routed implementation' } else { throw "route=$(@($routes)[0].route)" }
}

# N-S2A-DISPATCH-JUDGING : judging proposed edit => STOP
Expect-Block 'N-S2A-DISPATCH-JUDGING' 'JUDGING_OR_PROTECTED' {
  Assert-NeoDispatchProposedEdits -RepoRoot $cr -ProposedEdits @('app/orch_evil.ps1') -ApprovedPaths $approved -ProtectedPaths $protected
}

# =============================================================================
# S2a-FIX: MALFORMED GOVERNANCE ENTRY (F2) + NO-GOVMAP (F1 fail-closed root)
# =============================================================================
# N-S2A-MALFORMED-PROTECTED : a blank/whitespace protected entry must NOT be
# silently dropped (that dropped a protected edit to IMPLEMENTATION - a fail-open)
# => BLOCK MALFORMED_SCOPE_ENTRY.
Expect-Block 'N-S2A-MALFORMED-PROTECTED' 'MALFORMED_SCOPE_ENTRY' {
  Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/feature.py' -ApprovedPaths $approved -ProtectedPaths @('   ')
}

# N-S2A-MALFORMED-APPROVED : a traversal/rooted approved entry => BLOCK
# MALFORMED_SCOPE_ENTRY (fail-closed; not silently dropped).
Expect-Block 'N-S2A-MALFORMED-APPROVED' 'MALFORMED_SCOPE_ENTRY' {
  Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/feature.py' -ApprovedPaths @('..\evil') -ProtectedPaths $protected
}

# N-S2A-NO-GOVMAP : if the NEO governed root / judging map cannot be resolved the
# classifier must fail CLOSED (BLOCK NO_GOVERNANCE_MAP), never leave class UNKNOWN.
# Exercised honestly WITHOUT moving the real map: copy the module chain into an
# ISOLATED scratch dir with NO .neo/.claude ancestor (mirroring the real
# scripts\orchestrator layout so relative dot-sources resolve), dot-source THAT
# copy, and classify - Resolve-NeoRoot then throws => NO_GOVERNANCE_MAP.
$isoOk = $false; $isoErr = ''
try {
  $iso = Join-Path $ScratchRoot ('iso_nogovmap_' + [guid]::NewGuid().ToString('N'))
  $isoOrch = Join-Path $iso 'scripts\orchestrator'
  $isoHarn = Join-Path $isoOrch 'harness'
  New-Item -ItemType Directory -Force -Path $isoHarn | Out-Null
  # copy the module + its full dependency chain (orch_io -> orch_schema/orch_class)
  foreach ($f in @('orch_diff.ps1','orch_io.ps1','orch_schema.ps1','orch_class.ps1')) {
    Copy-Item -LiteralPath (Join-Path $orchDir $f) -Destination (Join-Path $isoOrch $f)
  }
  # _neo_root.ps1 lives one level up from orchestrator (scripts\)
  Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $orchDir) '_neo_root.ps1') -Destination (Join-Path $iso 'scripts\_neo_root.ps1')
  $isoOk = $true
} catch { $isoErr = $_.Exception.Message }
if ($isoOk) {
  # dot-source the ISOLATED copy in a child scope so the live module stays loaded.
  Expect-Block 'N-S2A-NO-GOVMAP' 'NO_GOVERNANCE_MAP' {
    & {
      . (Join-Path $isoOrch 'orch_diff.ps1')
      # sanity: the copy has no NEO ancestor
      Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/feature.py' -ApprovedPaths $approved -ProtectedPaths $protected
    }
  }
} else {
  Record 'N-S2A-NO-GOVMAP' $false ('could not stage isolated module copy: ' + $isoErr) 'negative'
}

# -----------------------------------------------------------------------------
# S2a-FIX-2 helper: stage a GOVERNED-SHAPED module mirror in scratch, mirroring the
# REAL NEO layout (module chain under <root>\.neo\scripts\orchestrator, _neo_root
# under <root>\.neo\scripts). Writes <root>\.neo\schema\artifact_classes.json with
# the supplied body. So Resolve-NeoRoot (walk-up for BOTH .neo + .claude) SUCCEEDS
# at <root> and the oracle map is the one planted at <root>. Returns the real
# orchestrator dir. NEVER touches the real governed tree.
function Stage-NeoGovernedMirror { param([string]$Root, [string]$MapBody)
  $scripts = Join-Path $Root '.neo\scripts'
  $orch = Join-Path $scripts 'orchestrator'
  New-Item -ItemType Directory -Force -Path (Join-Path $orch 'harness') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $Root '.claude') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $Root '.neo\schema') | Out-Null
  foreach ($f in @('orch_diff.ps1','orch_io.ps1','orch_schema.ps1','orch_class.ps1')) {
    Copy-Item -LiteralPath (Join-Path $orchDir $f) -Destination (Join-Path $orch $f)
  }
  Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $orchDir) '_neo_root.ps1') -Destination (Join-Path $scripts '_neo_root.ps1')
  Set-Content -LiteralPath (Join-Path $Root '.neo\schema\artifact_classes.json') -Value $MapBody -Encoding Ascii
  return $orch
}

# =============================================================================
# S2a-FIX-2: F1 MODULE-PATH CANONICALIZATION + F2 INVALID-GOVMAP REASON-CODE
# =============================================================================
# N-S2A-JUNCTION-MODULE-ROOT (F1): the engine module is dot-sourced through a JUNCTION
# on the module's OWN .neo\scripts dir whose REAL target is a governed mirror carrying
# the REAL judging map, while the junction is planted under an APP tree that carries
# its OWN .neo+.claude + a PERMISSIVE (empty-rules) map at the APP ROOT. Geometry:
#   <appTree>\.claude, <appTree>\.neo\schema\artifact_classes.json  = { "rules": [] }
#   <appTree>\.neo\scripts  --junction-->  <realGov>\.neo\scripts   (real chain + real map)
# Dot-source <appTree>\.neo\scripts\orchestrator\orch_diff.ps1. Its $PSScriptRoot is the
# APP-SPELLED junction path. WITHOUT F1, Resolve-NeoRoot walks the junction-spelled path
# and stops at <appTree> (its .neo+.claude) => consults the PLANTED permissive map =>
# orch_evil.ps1 classifies IMPLEMENTATION (judging bypass - the reopened vector). WITH F1
# the module dir is canonicalized to its REAL governed location first (<realGov>), so the
# REAL map is used => orch_evil.ps1 STILL STOP-JUDGING (planted-at-junction map ignored).
# (Verified as a negative control: the pre-fix snapshot returns IMPLEMENTATION here.)
$jmrOk = $false; $jmrErr = ''; $jmrLink = $null
try {
  # (a) REAL governed mirror (junction TARGET) with the REAL judging map.
  $realGov = Join-Path $ScratchRoot ('jmr_realgov_' + [guid]::NewGuid().ToString('N'))
  $realMapBody = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $orchDir) '..\schema\artifact_classes.json')
  [void](Stage-NeoGovernedMirror -Root $realGov -MapBody $realMapBody)
  $realScripts = Join-Path $realGov '.neo\scripts'
  # (b) APP tree: its OWN .neo+.claude + a PERMISSIVE map at the APP ROOT.
  $appTree = Join-Path $ScratchRoot ('jmr_app_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $appTree '.claude') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $appTree '.neo\schema') | Out-Null
  Set-Content -LiteralPath (Join-Path $appTree '.neo\schema\artifact_classes.json') -Value '{ "rules": [] }' -Encoding Ascii
  # (c) JUNCTION on the module's .neo\scripts spelling -> the REAL governed .neo\scripts.
  $jmrLink = Join-Path $appTree '.neo\scripts'
  New-Item -ItemType Junction -Path $jmrLink -Target $realScripts -EA Stop | Out-Null
  $jmrModPath = Join-Path $jmrLink 'orchestrator\orch_diff.ps1'
  $jmrOk = $true
} catch { $jmrErr = $_.Exception.Message }
if ($jmrOk) {
  # dot-source the JUNCTION-SPELLED copy in a child scope; classify a judging-named
  # file in a plain app repo. STOP-JUDGING => the REAL map (not the planted one) won.
  Expect-Value 'N-S2A-JUNCTION-MODULE-ROOT' 'STOP-JUDGING' {
    & {
      . $jmrModPath
      Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/orch_evil.ps1' -ApprovedPaths $approved -ProtectedPaths $protected
    }
  }
} else {
  Record 'N-S2A-JUNCTION-MODULE-ROOT' $false ('could not stage junctioned governed mirror (mklink /J should need no admin): ' + $jmrErr) 'positive'
}

# N-S2A-INVALID-GOVMAP (F2): a governed root that RESOLVES (has .neo+.claude) but
# whose artifact_classes.json is INVALID JSON. Pre-F2 this flowed through the frozen
# Get-NeoClassMap as a raw "NEO-BLOCK: ... invalid JSON" WITHOUT the reason_code.
# WITH the F2 call-site wrap it BLOCKs reason_code=NO_GOVERNANCE_MAP (contract
# complete). Staged in an ISOLATED governed mirror - the real map is never mutated.
$igmOk = $false; $igmErr = ''
try {
  $igmRoot = Join-Path $ScratchRoot ('igm_' + [guid]::NewGuid().ToString('N'))
  $igmOrch = Stage-NeoGovernedMirror -Root $igmRoot -MapBody '{ this is not valid json'
  $igmOk = $true
} catch { $igmErr = $_.Exception.Message }
if ($igmOk) {
  Expect-Block 'N-S2A-INVALID-GOVMAP' 'NO_GOVERNANCE_MAP' {
    & {
      . (Join-Path $igmOrch 'orch_diff.ps1')
      Get-NeoChangeClassification -RepoRoot $cr -Rel 'app/feature.py' -ApprovedPaths $approved -ProtectedPaths $protected
    }
  }
} else {
  Record 'N-S2A-INVALID-GOVMAP' $false ('could not stage invalid-govmap mirror: ' + $igmErr) 'negative'
}

# =============================================================================
# S2a-FIX-3: CANONICALIZATION FAIL-CLOSED (module-root throw + unresolvable reparse)
# =============================================================================
# N-S2A-CANON-FAILCLOSED (FIX 1): if the MODULE-ROOT Get-NeoRealPath THROWS, the fix
# must BLOCK reason_code=MODULE_ROOT_UNRESOLVABLE and NEVER fall back to the
# un-canonicalized $script:NeoDiffDir (which would let Resolve-NeoRoot walk the
# attacker-spelled ancestor and select a PLANTED map). We stage an ISOLATED governed
# mirror whose .neo\schema map is PERMISSIVE ({rules:[]}); WITHOUT the block, falling
# back to that dir would resolve the mirror root and consult the permissive map =>
# feature.py would NOT block. We force the module-root real-path call to throw by
# shadowing Get-NeoRealPath for EXACTLY the module dir inside a child scope (the real
# function is delegated to for every other path, so nothing else changes). Correct
# behavior: BLOCK MODULE_ROOT_UNRESOLVABLE (the permissive map is never reached).
$cfcOk = $false; $cfcErr = ''
try {
  $cfcRoot = Join-Path $ScratchRoot ('cfc_' + [guid]::NewGuid().ToString('N'))
  # permissive map at the mirror root: if the fix FELL BACK it would be consulted.
  $cfcOrch = Stage-NeoGovernedMirror -Root $cfcRoot -MapBody '{ "rules": [] }'
  $cfcOk = $true
} catch { $cfcErr = $_.Exception.Message }
if ($cfcOk) {
  Expect-Block 'N-S2A-CANON-FAILCLOSED' 'MODULE_ROOT_UNRESOLVABLE' {
    & {
      . (Join-Path $cfcOrch 'orch_diff.ps1')
      # shadow Get-NeoRealPath so ONLY the module-dir arg throws; all other paths
      # delegate to the real (dot-sourced) function unchanged.
      $script:RealGnrp = ${function:Get-NeoRealPath}
      $script:ModDir = $NeoDiffDir
      function Get-NeoRealPath {
        param([string]$Path)
        if ($Path -ieq $script:ModDir) { throw 'forced module-root resolution failure (fixture)' }
        & $script:RealGnrp -Path $Path
      }
      Resolve-NeoGovernanceMapPath
    }
  }
} else {
  Record 'N-S2A-CANON-FAILCLOSED' $false ('could not stage canon-failclosed mirror: ' + $cfcErr) 'negative'
}

# N-S2A-REPARSE-UNRESOLVED (FIX 2): a component that IS a reparse point but whose
# Target cannot be resolved (null/empty/throw) must BLOCK reason_code=PATH_ESCAPE, not
# be left unresolved in the returned path. A real junction/symlink always reports a
# non-null .Target (so it resolves normally - see N-S2A-JUNCTION), so we force the
# genuinely-unresolvable case by shadowing Get-Item for EXACTLY one probe dir to
# report a ReparsePoint with a NULL Target (as an unsupported reparse tag would); the
# real Get-NeoRealPath code then runs and must fail closed. Every other path delegates
# to the real Get-Item unchanged (no over-block on normal components).
$rurOk = $false; $rurErr = ''
try {
  $rurRoot = Join-Path $ScratchRoot ('rur_' + [guid]::NewGuid().ToString('N'))
  $rurProbe = Join-Path $rurRoot 'nullreparse'
  New-Item -ItemType Directory -Force -Path $rurProbe | Out-Null
  Set-Content -LiteralPath (Join-Path $rurProbe 'child.txt') -Value 'x' -Encoding Ascii
  $rurDeep = Join-Path $rurProbe 'child.txt'
  $rurOk = $true
} catch { $rurErr = $_.Exception.Message }
if ($rurOk) {
  Expect-Block 'N-S2A-REPARSE-UNRESOLVED' 'PATH_ESCAPE' {
    & {
      $script:ProbeDir = $rurProbe
      function Get-Item {
        $lp = $null
        for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-LiteralPath') { $lp = $args[$i + 1] } }
        if ($lp -and ($lp -ieq $script:ProbeDir)) {
          return [pscustomobject]@{ Attributes = [System.IO.FileAttributes]::ReparsePoint; Target = $null }
        }
        Microsoft.PowerShell.Management\Get-Item @args
      }
      Get-NeoRealPath -Path $rurDeep
    }
  }
} else {
  Record 'N-S2A-REPARSE-UNRESOLVED' $false ('could not stage reparse-unresolved probe: ' + $rurErr) 'negative'
}

# N-S2A-UNINSPECTABLE-COMPONENT (S2a-FIX-4, class closer): a component that EXISTS
# (Test-Path TRUE) but that Get-Item cannot inspect ($null) must BLOCK
# reason_code=PATH_ESCAPE - the walk must NOT continue on an uninspectable existing
# component (which MAY be an unresolved reparse => fail-open). Forcing a genuine
# exists-but-uninspectable state via real ACLs is not portable in this env, so - as
# with N-S2A-REPARSE-UNRESOLVED - we shadow Get-Item for EXACTLY one existing probe
# dir to return $null while Test-Path stays TRUE for it; every other path delegates to
# the real Get-Item unchanged (no over-block on normal components). The real
# Get-NeoRealPath code then runs and must fail closed. This is a code-guard behavioral
# proof, not a faked outcome: the guard, not the shadow, is the load-bearing artifact.
$uicOk = $false; $uicErr = ''
try {
  $uicRoot = Join-Path $ScratchRoot ('uic_' + [guid]::NewGuid().ToString('N'))
  $uicProbe = Join-Path $uicRoot 'existing_uninspectable'
  New-Item -ItemType Directory -Force -Path $uicProbe | Out-Null
  Set-Content -LiteralPath (Join-Path $uicProbe 'child.txt') -Value 'x' -Encoding Ascii
  $uicDeep = Join-Path $uicProbe 'child.txt'
  $uicOk = $true
} catch { $uicErr = $_.Exception.Message }
if ($uicOk) {
  Expect-Block 'N-S2A-UNINSPECTABLE-COMPONENT' 'PATH_ESCAPE' {
    & {
      $script:UicDir = $uicProbe
      function Get-Item {
        $lp = $null
        for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-LiteralPath') { $lp = $args[$i + 1] } }
        # Test-Path stays TRUE for the probe (it really exists); only its inspection is
        # suppressed to null, exactly the existing-but-uninspectable case. Everything
        # else delegates to the real Get-Item so normal components are unaffected.
        if ($lp -and ($lp -ieq $script:UicDir)) { return $null }
        Microsoft.PowerShell.Management\Get-Item @args
      }
      Get-NeoRealPath -Path $uicDeep
    }
  }
} else {
  Record 'N-S2A-UNINSPECTABLE-COMPONENT' $false ('could not stage uninspectable-component probe: ' + $uicErr) 'negative'
}

# =============================================================================
# XC1 CANONICAL-CONTAINMENT BATTERY
# =============================================================================
# N-S2A-TRAVERSAL : '..\' spelling => BLOCK (Assert-NeoSafeRel)
$xr = New-NeoRepo
Write-NeoFile -Repo $xr -Rel 'app/seed.txt' -Body 's'
Commit-NeoRepo -Repo $xr
Expect-Block 'N-S2A-TRAVERSAL' 'NEO-BLOCK' {
  Assert-NeoCanonicalContained -RepoRoot $xr -Rel '..\escape.txt'
}

# N-S2A-CASE : case-variant containment normalized correctly (still contained => OK)
Write-NeoFile -Repo $xr -Rel 'app/CaseFile.txt' -Body 'c'
Expect-Ok 'N-S2A-CASE' {
  $r = Assert-NeoCanonicalContained -RepoRoot $xr -Rel 'APP/casefile.txt'
  if ($r) { 'case-variant contained + normalized' } else { throw 'no result' }
}

# N-S2A-JUNCTION : a junction whose REAL path escapes RepoRoot => BLOCK PATH_ESCAPE
# Build an OUTSIDE tree, then a junction INSIDE the repo pointing at it.
$outside = Join-Path $ScratchRoot 'outside_tree'
New-Item -ItemType Directory -Force -Path $outside | Out-Null
Set-Content -LiteralPath (Join-Path $outside 'loot.txt') -Value 'exfil' -Encoding Ascii
$jxInside = Join-Path $xr 'app\jx'
$jxMade = $false
try { New-Item -ItemType Junction -Path $jxInside -Target $outside -EA Stop | Out-Null; $jxMade = $true }
catch { $jxMade = $false }
if ($jxMade) {
  Expect-Block 'N-S2A-JUNCTION' 'PATH_ESCAPE' {
    Assert-NeoCanonicalContained -RepoRoot $xr -Rel 'app/jx/loot.txt'
  }
} else {
  Record 'N-S2A-JUNCTION' $false 'junction creation FAILED unexpectedly (mklink /J should need no admin) - investigate' 'negative'
}

# N-S2A-SYMLINK : real-path escape => BLOCK PATH_ESCAPE. Attempt a true symlink;
# if privilege is unavailable, DISCLOSE honestly (SKIP, not fake) - the junction
# case above already covers the reparse-point escape surface.
$symTgt = Join-Path $ScratchRoot 'sym_outside'
New-Item -ItemType Directory -Force -Path $symTgt | Out-Null
Set-Content -LiteralPath (Join-Path $symTgt 'loot.txt') -Value 'exfil' -Encoding Ascii
$symInside = Join-Path $xr 'app\sx'
$symMade = $false; $symErr = ''
try { New-Item -ItemType SymbolicLink -Path $symInside -Target $symTgt -EA Stop | Out-Null; $symMade = $true }
catch { $symMade = $false; $symErr = $_.Exception.Message }
if ($symMade) {
  Expect-Block 'N-S2A-SYMLINK' 'PATH_ESCAPE' {
    Assert-NeoCanonicalContained -RepoRoot $xr -Rel 'app/sx/loot.txt'
  }
} else {
  Record 'N-S2A-SYMLINK' $true ("SKIPPED - symlink privilege unavailable in this env (" + $symErr + "); reparse escape covered by N-S2A-JUNCTION - NOT faked") 'skip'
}

# =============================================================================
# SUMMARY + RESIDUE-CLEAN SECOND PASS
# =============================================================================
$total = @($script:results).Count
$failed = @($script:results | Where-Object { -not $_.pass })
$skips = @($script:results | Where-Object { $_.kind -eq 'skip' })
$passCount = $total - $failed.Count

Write-Host ""
Write-Host ("Results: {0}/{1} PASS ({2} skip-disclosed)" -f $passCount, $total, $skips.Count) -ForegroundColor Cyan

if ($ProofOut) {
  $proof = [pscustomobject]@{
    suite      = 'orch_diff_suite'
    slice      = '4.0-P4-AUTONOMY-C1C3-S2a'
    total      = $total
    passed     = $passCount
    failed     = $failed.Count
    skipped    = $skips.Count
    results    = $script:results
    generated  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  $proof | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ProofOut -Encoding Ascii
}

# residue-clean second pass: remove ALL scratch incl every throwaway git repo,
# then PROVE the scratch root is gone.
if (-not $KeepScratch) {
  # junctions must be removed without following into the target: Remove-Item on a
  # reparse point deletes the link, not the target contents.
  Remove-Item -Recurse -Force -LiteralPath $ScratchRoot -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $ScratchRoot) {
    Write-Host "RESIDUE: scratch root survived cleanup: $ScratchRoot" -ForegroundColor Red
    $failed = @($failed) + [pscustomobject]@{ guard = 'RESIDUE-CLEAN'; pass = $false }
  } else {
    Write-Host "residue-clean: scratch + all repos removed" -ForegroundColor Green
  }
}

if ($failed.Count -gt 0) { exit 1 } else { exit 0 }
