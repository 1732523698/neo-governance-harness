# orch_router_suite.ps1 - NEO 4.0-P4-AUTONOMY C6 INDEPENDENT router harness.
# ASCII-only (D10). Kept SEPARATE from the engine it tests.
#
# Proves the C6 risk-tier router FAILS CLOSED: profile-completeness gate (N1/NF-4,
# OR-semantics + mandatory governed-token union), autonomous-row gate (I8 + I4),
# diff-time escalate-only re-derive (I4), and the NB-1 seam floor on
# Assert-NeoAuditorSlotSatisfied (the LOW-row null-slot auditor vacuum, I1, closed).
# C6-FIX (2026-07-06) adds the converged triple-audit closures: denylist per-entry
# SHAPE guard (F1), attestation record SHAPE (F4), changed-set canonical-spelling
# contract + RepoRoot-contained reads (F2/F3), and downgrade-key PRESENCE (I-1).
# C6-FIX-2 (2026-07-06) adds the delta-triple boundary-re-validation closures:
# ChangedSet member validation - never repaired-by-filtering (D1), crafted-
# RouterProfile re-validation at the re-derive boundary via the SHARED shape
# helpers (D2), and risk_tokens field/member SHAPE - never auto-wrapped,
# stringified, or silently skipped (D3).
# Writes NO AUDIT_RESULT; synthetic fixtures only, in scratch; residue-clean second pass.
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'

$orchDir = Split-Path -Parent $PSScriptRoot   # ...\.neo\scripts\orchestrator
. "$orchDir\orch_router.ps1"                   # dot-sources orch_enforce.ps1 -> orch_io chain
$TS = '2026-07-05T00:00:00Z'

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_orch_c6_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors the B2a enforce-suite framing) -----------------
$script:results = @()
function Record($name, $pass, $detail, $kind = 'negative') {
  $script:results += [pscustomobject]@{ guard = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  $ktag = if ($kind -eq 'negative') { 'GUARD' } else { 'info ' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $ktag, $name, $detail) -ForegroundColor $col
}
function Expect-Block($name, $sb) {
  try { & $sb; Record $name $false 'NO BLOCK (guard did not fire)' 'negative' }
  catch {
    if ($_.Exception.Message -like 'NEO-BLOCK:*') { Record $name $true $_.Exception.Message 'negative' }
    else { Record $name $false ('threw non-BLOCK: ' + $_.Exception.Message) 'negative' }
  }
}
function Expect-Ok($name, $sb) {
  try { $r = & $sb; Record $name $true "$r" 'positive' }
  catch { Record $name $false ('unexpected block/error: ' + $_.Exception.Message) 'positive' }
}

# ---- fixture builders ---------------------------------------------------------
function Row($rc, $tier, $downgrade) {
  $o = [ordered]@{ id = 'r1'; area = 'app'; risk_class = $rc; never_batchable = $true; audit_tier = $tier }
  if ($null -ne $downgrade) { $o['explicit_downgrade'] = $downgrade }
  return [pscustomobject]$o
}
function Profile($denyEntries, $authTokens, $finTokens) {
  return [pscustomobject]@{
    denylist    = [pscustomobject]@{ entries = @($denyEntries) }
    risk_tokens = [pscustomobject]@{ auth_tokens = @($authTokens); fin_tokens = @($finTokens) }
  }
}
function DenyEntry($pattern, $isGlob) { return [pscustomobject]@{ pattern = $pattern; is_glob = [bool]$isGlob } }
# C6-FIX F4 interface: shape-valid C5 attestation record (SHAPE binds here; AUTHORITY
# binds at the C5 gate - the record fields below are the suite's synthetic stand-in).
function AttestRecord($gap) {
  return [pscustomobject]@{ gap = $gap; attested_by = 'Raphael'; attested_date = '2026-07-06'; run_scope = 'c6fix-router-suite' }
}
# C6-FIX F2/F3 interface: creates the file under ScratchRoot but returns the CANONICAL
# REPO-RELATIVE path (forward slashes) - re-derive fixtures now pass rel + -RepoRoot.
function New-ChangedFile($rel, $content) {
  $p = Join-Path $ScratchRoot $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
  Set-Content -LiteralPath $p -Value $content -Encoding ASCII -NoNewline
  return ($rel -replace '\\', '/')
}
# Minimal END-report object: the NB-1 seam fixtures all resolve at/before the null-slot
# early-return, so no bundle/verdict world is needed (the deep machinery is the B2a
# enforce suite's proven ground; this suite tests the floor parameter's gating of it).
$erNullSlot = [pscustomobject]@{ subsession_id = 'ss-c6'; auditor_recommendation_slot = $null }

$fullProfile = Profile @((DenyEntry 'modules/app/locked/**' $true), (DenyEntry 'modules/app/charges.ts' $false)) @('owner_user_id', 'req.user') @('charge', 'payout')
$rowLow  = Row 'low' 'lightweight' $null
$rowHigh = Row 'high' 'isolated' $null

Write-Host ""
Write-Host "== C6 router suite: profile-completeness gate (N1/NF-4) ==" -ForegroundColor Cyan

# --- N-C6-EMPTY-PROFILE: denylist AND tokens empty => BLOCK
Expect-Block 'N-C6-EMPTY-PROFILE' { Resolve-NeoRouterProfile -Profile (Profile @() @() @()) | Out-Null }

# --- N-C6-HALF-EMPTY-A/B: exactly ONE side empty => BLOCK (the OR is load-bearing, NF-4)
Expect-Block 'N-C6-HALF-EMPTY-A-denylist' { Resolve-NeoRouterProfile -Profile (Profile @() @('owner_user_id') @('charge')) | Out-Null }
Expect-Block 'N-C6-HALF-EMPTY-B-tokens' { Resolve-NeoRouterProfile -Profile (Profile @(DenyEntry 'locked/**' $true) @() @()) | Out-Null }

# --- N-C6-UNPARSEABLE: null / garbage profile => BLOCK
Expect-Block 'N-C6-UNPARSEABLE-null' { Resolve-NeoRouterProfile -Profile $null | Out-Null }
Expect-Block 'N-C6-UNPARSEABLE-garbage' { Resolve-NeoRouterProfile -Profile 'not-a-profile' | Out-Null }

# --- P-C6-ATTESTED-GAP: the SPECIFIC named gap passes AND the governed minimum survives
# (C6-FIX F4 interface hunk: bare -AttestedGaps string list -> shape-valid record)
Expect-Ok 'P-C6-ATTESTED-GAP' {
  $r = Resolve-NeoRouterProfile -Profile (Profile @(DenyEntry 'locked/**' $true) @() @()) -AttestedGapRecords @((AttestRecord 'risk_tokens'))
  foreach ($t in (Get-NeoGovernedTokenSet)) { if ($r.tokens -notcontains $t) { throw "governed token '$t' missing after attestation" } }
  if (@($r.attested_gaps_applied) -cnotcontains 'risk_tokens') { throw 'attested_gaps_applied does not record the gap' }
  'attested gap passed; governed-token minimum survives attestation (union unconditional)'
}
# --- attestation is SPECIFIC, never wholesale: naming the OTHER gap does not cover this one
# (C6-FIX F4 interface hunk: the wrong-gap attestation is now a VALID record naming 'denylist')
Expect-Block 'N-C6-ATTEST-WRONG-GAP' { Resolve-NeoRouterProfile -Profile (Profile @(DenyEntry 'locked/**' $true) @() @()) -AttestedGapRecords @((AttestRecord 'denylist')) | Out-Null }

# --- P-C6-UNION: full profile - returned tokens are a SUPERSET of the governed set
Expect-Ok 'P-C6-UNION' {
  $r = Resolve-NeoRouterProfile -Profile $fullProfile
  foreach ($t in (Get-NeoGovernedTokenSet)) { if ($r.tokens -notcontains $t) { throw "governed token '$t' missing from union" } }
  foreach ($t in @('owner_user_id', 'req.user', 'charge', 'payout')) { if ($r.tokens -notcontains $t) { throw "profile token '$t' missing from union" } }
  'returned tokens = profile tokens UNION governed minimum (superset proven)'
}

Write-Host ""
Write-Host "== C6-FIX router suite: denylist per-entry SHAPE guard (F1) ==" -ForegroundColor Cyan

# All => BLOCK at Resolve-NeoRouterProfile: a malformed denylist SHAPE is unparseable
# and may never count as complete - the confirmed F1 fail-open ('passes completeness
# with >=1 malformed entry, then silently matches NOTHING at diff-time') is closed.
$goodTokensA = @('owner_user_id'); $goodTokensF = @('charge')
Expect-Block 'N-C6F-ENTRY-STRING' { Resolve-NeoRouterProfile -Profile (Profile @('modules/app/charges.ts') $goodTokensA $goodTokensF) | Out-Null }
Expect-Block 'N-C6F-ENTRY-NULL' { Resolve-NeoRouterProfile -Profile (Profile @($null, (DenyEntry 'locked/**' $true)) $goodTokensA $goodTokensF) | Out-Null }
Expect-Block 'N-C6F-ENTRY-PATTERN-BLANK' { Resolve-NeoRouterProfile -Profile (Profile @(DenyEntry '   ' $true) $goodTokensA $goodTokensF) | Out-Null }
Expect-Block 'N-C6F-ENTRY-PATTERN-NULL' { Resolve-NeoRouterProfile -Profile (Profile @(DenyEntry $null $true) $goodTokensA $goodTokensF) | Out-Null }
Expect-Block 'N-C6F-ENTRY-ISGLOB-MISSING' { Resolve-NeoRouterProfile -Profile (Profile @([pscustomobject]@{ pattern = 'locked/**' }) $goodTokensA $goodTokensF) | Out-Null }
Expect-Block 'N-C6F-ENTRIES-SCALAR' {
  $p = [pscustomobject]@{
    denylist    = [pscustomobject]@{ entries = 'modules/app/charges.ts' }
    risk_tokens = [pscustomobject]@{ auth_tokens = @('owner_user_id'); fin_tokens = @('charge') }
  }
  Resolve-NeoRouterProfile -Profile $p | Out-Null
}
# positive control: well-formed entries still round-trip through the shape guard
Expect-Ok 'P-C6F-ENTRIES-WELLFORMED' {
  $r = Resolve-NeoRouterProfile -Profile $fullProfile
  if (@($r.denylist_entries).Count -ne 2) { throw "well-formed entries did not round-trip (count $(@($r.denylist_entries).Count) != 2)" }
  'well-formed denylist entries pass the per-entry shape guard unchanged'
}

Write-Host ""
Write-Host "== C6-FIX router suite: attestation record SHAPE (F4) ==" -ForegroundColor Cyan

# Malformed record => BLOCK in itself; a gap passes ONLY via a VALID record naming
# exactly that gap (record AUTHORITY binds at the C5 gate - SHAPE binds here).
$starvedTokens = Profile @(DenyEntry 'locked/**' $true) @() @()
$starvedDeny   = Profile @() @('owner_user_id') @('charge')
Expect-Block 'N-C6F-ATTEST-RECORD-STRING' { Resolve-NeoRouterProfile -Profile $starvedTokens -AttestedGapRecords @('risk_tokens') | Out-Null }
Expect-Block 'N-C6F-ATTEST-RECORD-INCOMPLETE' {
  $rec = [pscustomobject]@{ gap = 'risk_tokens'; attested_date = '2026-07-06'; run_scope = 's' }   # attested_by missing
  Resolve-NeoRouterProfile -Profile $starvedTokens -AttestedGapRecords @($rec) | Out-Null
}
Expect-Block 'N-C6F-ATTEST-RECORD-BADDATE' {
  $rec = [pscustomobject]@{ gap = 'risk_tokens'; attested_by = 'Raphael'; attested_date = '07/06/2026'; run_scope = 's' }
  Resolve-NeoRouterProfile -Profile $starvedTokens -AttestedGapRecords @($rec) | Out-Null
}
# a VALID record naming the OTHER gap never covers this one (mirror of N-C6-ATTEST-WRONG-GAP)
Expect-Block 'N-C6F-ATTEST-WRONG-GAP' { Resolve-NeoRouterProfile -Profile $starvedDeny -AttestedGapRecords @((AttestRecord 'risk_tokens')) | Out-Null }
# gap id is case-EXACT: 'Denylist' is not 'denylist'
Expect-Block 'N-C6F-ATTEST-GAP-CASE' { Resolve-NeoRouterProfile -Profile $starvedDeny -AttestedGapRecords @((AttestRecord 'Denylist')) | Out-Null }

Write-Host ""
Write-Host "== C6 router suite: autonomous-row gate (I8 + I4) ==" -ForegroundColor Cyan

# --- N-C6-UNKNOWN-ROW: risk_class 'wat' => BLOCK (via the REUSED oracle - no parallel map)
Expect-Block 'N-C6-UNKNOWN-ROW' { Assert-NeoAutonomousRowEligible -RiskRow (Row 'wat' 'isolated' $null) | Out-Null }
Expect-Block 'N-C6-NULL-ROW' { Assert-NeoAutonomousRowEligible -RiskRow $null | Out-Null }

# --- N-C6-DOWNGRADE-CHANNEL: an autonomous row carrying explicit_downgrade => BLOCK.
# Load-bearing case: a COMPLETE downgrade record that the plain oracle would ACCEPT
# (medium->lightweight) is still refused on the autonomous path.
$dgComplete = [pscustomobject]@{ reason = 'r'; authority = 'Raphael'; timestamp = $TS; scope = 's' }
Expect-Block 'N-C6-DOWNGRADE-CHANNEL' { Assert-NeoAutonomousRowEligible -RiskRow (Row 'medium' 'lightweight' $dgComplete) | Out-Null }

# --- C6-FIX I-1: PRESENCE of the key is the test - value inspection is the wrong test
# (PowerShell unwraps an empty-array property to $null, which slipped past the old
# null-value check). Both row shapes are covered: PSCustomObject and hashtable.
Expect-Block 'N-C6F-DOWNGRADE-EMPTY-ARRAY' {
  $row = [pscustomobject]@{ id = 'r1'; area = 'app'; risk_class = 'low'; never_batchable = $true; audit_tier = 'lightweight'; explicit_downgrade = @() }
  Assert-NeoAutonomousRowEligible -RiskRow $row | Out-Null
}
Expect-Block 'N-C6F-DOWNGRADE-KEY-PRESENT-NULL' {
  $row = @{ id = 'r1'; area = 'app'; risk_class = 'low'; never_batchable = $true; audit_tier = 'lightweight'; explicit_downgrade = $null }
  Assert-NeoAutonomousRowEligible -RiskRow $row | Out-Null
}

# --- positive control: a clean LOW row is eligible
Expect-Ok 'P-C6-ROW-ELIGIBLE' {
  $null = Assert-NeoAutonomousRowEligible -RiskRow $rowLow
  'clean LOW row (no downgrade record) is autonomous-eligible'
}

Write-Host ""
Write-Host "== C6 router suite: diff-time escalate-only re-derive (I4) ==" -ForegroundColor Cyan

$rp = Resolve-NeoRouterProfile -Profile $fullProfile

# (C6-FIX F2/F3 interface hunks in this section: every Invoke-NeoDiffRiskRederive call
# now passes -RepoRoot $ScratchRoot, and changed sets are CANONICAL REPO-RELATIVE paths
# - New-ChangedFile returns rel; the unreadable fixture is a rel spelling. Assertions
# and expected outcomes are UNCHANGED.)

# --- N-C6-EMPTY-CHANGESET: empty/null actual diff => BLOCK
Expect-Block 'N-C6-EMPTY-CHANGESET-empty' { Invoke-NeoDiffRiskRederive -ChangedSet @() -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
Expect-Block 'N-C6-EMPTY-CHANGESET-null' { Invoke-NeoDiffRiskRederive -ChangedSet $null -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }

# --- N-C6-DENY-HIT: changed path matches a denylist glob => STOP (never merely a bump)
# (also the CANONICAL-SPELLING CONTROL for the C6-FIX spelling contract: the canonical
# rel spelling still reaches the denylist and STOPs on the hit)
$fClean = New-ChangedFile 'work\notes.txt' 'hello world'
Expect-Block 'N-C6-DENY-HIT' { Invoke-NeoDiffRiskRederive -ChangedSet @('modules/app/locked/inner.ts') -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
# exact (non-glob) entry, case-variant on Windows => still a STOP
Expect-Block 'N-C6-DENY-HIT-exact-case' { Invoke-NeoDiffRiskRederive -ChangedSet @('MODULES/APP/CHARGES.TS') -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }

# --- N-C6-UNREADABLE: a changed file that cannot be read => BLOCK (fail-closed)
Expect-Block 'N-C6-UNREADABLE' { Invoke-NeoDiffRiskRederive -ChangedSet @('work/does_not_exist.txt') -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }

# --- N-C6-ESCALATE: LOW frozen row + changed CONTENT containing 'payment' => escalation BLOCK
$fPay = New-ChangedFile 'work\impl.txt' 'this line wires the payment flow'
Expect-Block 'N-C6-ESCALATE' { Invoke-NeoDiffRiskRederive -ChangedSet @($fPay) -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
# escalation via token in the PATH alone (content clean)
$fPathTok = New-ChangedFile 'work\ledger_view.txt' 'clean body'
Expect-Block 'N-C6-ESCALATE-path-token' { Invoke-NeoDiffRiskRederive -ChangedSet @($fPathTok) -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }

# --- P-C6-NEVER-DOWNGRADE: HIGH frozen row + clean diff => effective_class stays 'high'
Expect-Ok 'P-C6-NEVER-DOWNGRADE' {
  $r = Invoke-NeoDiffRiskRederive -ChangedSet @($fClean) -RouterProfile $rp -RiskRow $rowHigh -RepoRoot $ScratchRoot
  if ($r.effective_class -cne 'high') { throw "effective_class '$($r.effective_class)' != 'high' (downgrade!)" }
  if ($r.frozen_class -cne 'high') { throw 'frozen_class mutated' }
  if ($r.escalated) { throw 'escalated flag wrongly set' }
  'clean diff on a HIGH frozen row keeps effective_class=high (never downgrade)'
}
# --- positive control: LOW row + clean diff routes at the frozen LOW class
Expect-Ok 'P-C6-CLEAN-LOW' {
  $r = Invoke-NeoDiffRiskRederive -ChangedSet @($fClean) -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot
  if ($r.effective_class -cne 'low') { throw "effective_class '$($r.effective_class)' != 'low'" }
  if ($r.derived_class -cne 'low') { throw "derived_class '$($r.derived_class)' != 'low'" }
  'clean diff on a LOW frozen row returns the frozen class unchanged'
}

Write-Host ""
Write-Host "== C6-FIX router suite: changed-set spelling contract + contained reads (F2/F3) ==" -ForegroundColor Cyan

# REJECT, never normalize (XC1): each dodging spelling of a denylisted/changed file
# must BLOCK on the SPELLING itself - the canonical-spelling control that still STOPs
# on the deny hit is N-C6-DENY-HIT above.
Expect-Block 'N-C6F-DOTSLASH-DODGE' { Invoke-NeoDiffRiskRederive -ChangedSet @('./modules/app/charges.ts') -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
Expect-Block 'N-C6F-ABSOLUTE-DODGE' { Invoke-NeoDiffRiskRederive -ChangedSet @((($ScratchRoot -replace '\\', '/') + '/modules/app/charges.ts')) -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
Expect-Block 'N-C6F-BACKSLASH-SPELLING' { Invoke-NeoDiffRiskRederive -ChangedSet @('modules\app\charges.ts') -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
Expect-Block 'N-C6F-TRAVERSAL' { Invoke-NeoDiffRiskRederive -ChangedSet @('a/../b') -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
# '.' mid-path segment: permitted by Assert-NeoSafeRel, rejected by the canonical contract
Expect-Block 'N-C6F-DOT-SEGMENT' { Invoke-NeoDiffRiskRederive -ChangedSet @('modules/./app/charges.ts') -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
# RepoRoot is REQUIRED and must exist: contained reads have no CWD fallback
Expect-Block 'N-C6F-REPOROOT-MISSING' { Invoke-NeoDiffRiskRederive -ChangedSet @($fClean) -RouterProfile $rp -RiskRow $rowLow | Out-Null }
Expect-Block 'N-C6F-REPOROOT-NOT-DIR' { Invoke-NeoDiffRiskRederive -ChangedSet @($fClean) -RouterProfile $rp -RiskRow $rowLow -RepoRoot (Join-Path $ScratchRoot 'no_such_dir') | Out-Null }

Write-Host ""
Write-Host "== C6-FIX-2 router suite: boundary re-validation (D1/D2/D3) ==" -ForegroundColor Cyan

# --- D1: ChangedSet members VALIDATED, never repaired-by-filtering. The confirmed
# repro: ('work/notes.txt','') and ('work/notes.txt',$null) both routed LOW on the
# surviving path - now the malformed member itself is a BLOCK naming its index.
Expect-Block 'N-C6F2-CHANGESET-BLANK-MEMBER' { Invoke-NeoDiffRiskRederive -ChangedSet @('work/notes.txt', '') -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
Expect-Block 'N-C6F2-CHANGESET-NULL-MEMBER' { Invoke-NeoDiffRiskRederive -ChangedSet @('work/notes.txt', $null) -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }
Expect-Block 'N-C6F2-CHANGESET-NONSTRING-MEMBER' { Invoke-NeoDiffRiskRederive -ChangedSet @('work/notes.txt', @{ path = 'x' }) -RouterProfile $rp -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null }

# --- D2: a CRAFTED RouterProfile fed DIRECTLY to the re-derive boundary (bypassing
# Resolve-NeoRouterProfile) can never dodge the F1 shape rules - the SHARED helper
# re-validates at this boundary. First fixture = the EXACT confirmed D2 repro that
# routed a DENYLISTED path LOW (string entry -> blank pattern -> 'continue').
Expect-Block 'N-C6F2-CRAFTED-PROFILE-STRING-ENTRY' {
  $crafted = @{ denylist_entries = @('modules/app/charges.ts'); tokens = @('benign') }
  Invoke-NeoDiffRiskRederive -ChangedSet @('modules/app/charges.ts') -RouterProfile $crafted -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null
}
Expect-Block 'N-C6F2-CRAFTED-PROFILE-BLANKPATTERN' {
  $crafted = @{ denylist_entries = @([pscustomobject]@{ pattern = '   '; is_glob = $false }); tokens = @('benign') }
  Invoke-NeoDiffRiskRederive -ChangedSet @($fClean) -RouterProfile $crafted -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null
}
Expect-Block 'N-C6F2-CRAFTED-PROFILE-NONSTRING-TOKEN' {
  $crafted = @{ denylist_entries = @((DenyEntry 'modules/app/locked/**' $true)); tokens = @(@{ g = 1 }) }
  Invoke-NeoDiffRiskRederive -ChangedSet @($fClean) -RouterProfile $crafted -RiskRow $rowLow -RepoRoot $ScratchRoot | Out-Null
}

# --- D3: risk_tokens field/member SHAPE at the profile gate. A SCALAR is never
# auto-wrapped, a non-string member never stringifies into completeness
# ('System.Collections.Hashtable' may never satisfy the gate), a blank member is
# never silently filtered. Profiles are built RAW (the Profile builder would @()-wrap).
Expect-Block 'N-C6F2-AUTHTOKENS-SCALAR' {
  $p = [pscustomobject]@{
    denylist    = [pscustomobject]@{ entries = @((DenyEntry 'locked/**' $true)) }
    risk_tokens = [pscustomobject]@{ auth_tokens = 'owner_user_id'; fin_tokens = @('charge') }
  }
  Resolve-NeoRouterProfile -Profile $p | Out-Null
}
Expect-Block 'N-C6F2-FINTOKENS-SCALAR' {
  $p = [pscustomobject]@{
    denylist    = [pscustomobject]@{ entries = @((DenyEntry 'locked/**' $true)) }
    risk_tokens = [pscustomobject]@{ auth_tokens = @('owner_user_id'); fin_tokens = 'charge' }
  }
  Resolve-NeoRouterProfile -Profile $p | Out-Null
}
Expect-Block 'N-C6F2-TOKEN-NONSTRING-MEMBER' {
  $p = [pscustomobject]@{
    denylist    = [pscustomobject]@{ entries = @((DenyEntry 'locked/**' $true)) }
    risk_tokens = [pscustomobject]@{ auth_tokens = @(@{ garbage = $true }); fin_tokens = @('charge') }
  }
  Resolve-NeoRouterProfile -Profile $p | Out-Null
}
Expect-Block 'N-C6F2-TOKEN-BLANK-MEMBER' {
  $p = [pscustomobject]@{
    denylist    = [pscustomobject]@{ entries = @((DenyEntry 'locked/**' $true)) }
    risk_tokens = [pscustomobject]@{ auth_tokens = @('req.user', '  '); fin_tokens = @('charge') }
  }
  Resolve-NeoRouterProfile -Profile $p | Out-Null
}

# --- positive control: valid EMPTY token arrays are SHAPE-valid emptiness - they
# still route to the gap/attestation path (the D3 shape guard did not break the
# C6 N1/NF-4 gap semantics) and the governed-token union survives.
Expect-Ok 'P-C6F2-VALID-EMPTY-TOKENLIST' {
  $p = [pscustomobject]@{
    denylist    = [pscustomobject]@{ entries = @((DenyEntry 'locked/**' $true)) }
    risk_tokens = [pscustomobject]@{ auth_tokens = @(); fin_tokens = @() }
  }
  $r = Resolve-NeoRouterProfile -Profile $p -AttestedGapRecords @((AttestRecord 'risk_tokens'))
  if (@($r.attested_gaps_applied) -cnotcontains 'risk_tokens') { throw 'valid EMPTY token arrays did not route to the attestation path' }
  foreach ($t in (Get-NeoGovernedTokenSet)) { if ($r.tokens -notcontains $t) { throw "governed token '$t' missing after attestation" } }
  'valid EMPTY token arrays (shape-valid emptiness) still route to the gap/attestation path; governed union intact'
}

Write-Host ""
Write-Host "== C6 router suite: NB-1 seam floor (Assert-NeoAuditorSlotSatisfied) ==" -ForegroundColor Cyan

# --- NB-1 SEAM BLOCK (headline): LOW row + NULL slot + floor 'isolated' => BLOCK.
# Without the floor this exact world PASSES (the I1 auditor vacuum); the floor gates the
# REQUIREDNESS computation itself, so the null-slot early-return now blocks.
Expect-Block 'NB-1-SEAM-BLOCK-low-null-slot-floor' {
  Assert-NeoAuditorSlotSatisfied -RiskRow $rowLow -EndReport $erNullSlot -SessionRoot $ScratchRoot `
    -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $null -RequiredTierFloor 'isolated' | Out-Null
}

# --- P-SEAM-COMPAT: same row/slot, NO floor => passes with required=false (existing behavior)
Expect-Ok 'P-SEAM-COMPAT' {
  $r = Assert-NeoAuditorSlotSatisfied -RiskRow $rowLow -EndReport $erNullSlot -SessionRoot $ScratchRoot `
    -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $null
  if ($r.required) { throw 'expected required=false with no floor' }
  if (-not $r.satisfied) { throw 'expected satisfied=true with no floor' }
  if ($r.effective_tier -cne 'lightweight') { throw "effective_tier '$($r.effective_tier)' != 'lightweight'" }
  'no floor => LOW row + null slot passes exactly as before (required=false, effective_tier=lightweight)'
}

# --- N-SEAM-BOGUS-FLOOR: unknown floor spellings => BLOCK (F3 mirror; never no-floor)
Expect-Block 'N-SEAM-BOGUS-FLOOR-isolate' {
  Assert-NeoAuditorSlotSatisfied -RiskRow $rowLow -EndReport $erNullSlot -SessionRoot $ScratchRoot `
    -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $null -RequiredTierFloor 'isolate' | Out-Null
}
Expect-Block 'N-SEAM-BOGUS-FLOOR-High' {
  Assert-NeoAuditorSlotSatisfied -RiskRow $rowLow -EndReport $erNullSlot -SessionRoot $ScratchRoot `
    -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $null -RequiredTierFloor 'High' | Out-Null
}
# case-EXACT: a miscased KNOWN tier is unknown (mirrors the F3 pattern)
Expect-Block 'N-SEAM-BOGUS-FLOOR-Isolated-case' {
  Assert-NeoAuditorSlotSatisfied -RiskRow $rowLow -EndReport $erNullSlot -SessionRoot $ScratchRoot `
    -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $null -RequiredTierFloor 'Isolated' | Out-Null
}

# --- P-SEAM-NO-DOWNGRADE: HIGH row + floor 'lightweight' => tier STILL 'isolated'.
# The proof is fail-closed: were the floor able to LOWER the tier, requiredness would
# compute false and this null-slot world would PASS; instead it must BLOCK, and the
# BLOCK message must name the row's own tier 'isolated'.
Expect-Ok 'P-SEAM-NO-DOWNGRADE' {
  try {
    Assert-NeoAuditorSlotSatisfied -RiskRow $rowHigh -EndReport $erNullSlot -SessionRoot $ScratchRoot `
      -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $null -RequiredTierFloor 'lightweight' | Out-Null
    throw 'floor LOWERED the tier: HIGH row + null slot passed under floor lightweight'
  } catch {
    if ($_.Exception.Message -notlike 'NEO-BLOCK:*') { throw }
    if ($_.Exception.Message -notlike "*audit_tier 'isolated'*") { throw "BLOCK does not name tier 'isolated': $($_.Exception.Message)" }
  }
  "floor 'lightweight' cannot lower a HIGH row: still blocked at tier 'isolated' (max, never min)"
}

Write-Host ""
Write-Host "== C6-FIX-3 router suite: rederive boundary autonomy eligibility (E1/I8) ==" -ForegroundColor Cyan

# --- E1 (C6-FIX-3): the rederive boundary must enforce AUTONOMY ELIGIBILITY, not
# just the tier vocabulary. The EXACT confirmed repro: valid profile, clean rel
# changed file, RepoRoot, MEDIUM row carrying a COMPLETE explicit_downgrade record
# - refused by Assert-NeoAutonomousRowEligible (I8) but formerly ACCEPTED here by
# the plain oracle (routed effective_class=medium). Now => BLOCK at rederive.
Expect-Block 'N-C6F3-REDERIVE-DOWNGRADE-ROW' {
  $dg = [pscustomobject]@{ reason = 'r'; authority = 'Raphael'; timestamp = $TS; scope = 's' }
  Invoke-NeoDiffRiskRederive -ChangedSet @($fClean) -RouterProfile $rp -RiskRow (Row 'medium' 'lightweight' $dg) -RepoRoot $ScratchRoot | Out-Null
}
# --- key PRESENCE is the test (I-1 semantics at THIS boundary): explicit_downgrade
# = @() blocks the same as a complete record. Clean-row routing is proven by the
# existing positive controls (clean rows carry no explicit_downgrade key).
Expect-Block 'N-C6F3-REDERIVE-DOWNGRADE-EMPTYARRAY' {
  Invoke-NeoDiffRiskRederive -ChangedSet @($fClean) -RouterProfile $rp -RiskRow (Row 'medium' 'lightweight' @()) -RepoRoot $ScratchRoot | Out-Null
}

# ---- summary + residue-clean --------------------------------------------------
$neg = @($script:results | Where-Object { $_.kind -eq 'negative' })
$pos = @($script:results | Where-Object { $_.kind -eq 'positive' })
$negFail = @($neg | Where-Object { -not $_.pass }).Count
$posFail = @($pos | Where-Object { -not $_.pass }).Count
$fail = $negFail + $posFail
Write-Host ""
Write-Host ("NEGATIVE fail-closed GUARDS: {0}/{1} pass" -f ($neg.Count - $negFail), $neg.Count) -ForegroundColor $(if ($negFail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("POSITIVE / info checks:      {0}/{1} pass" -f ($pos.Count - $posFail), $pos.Count) -ForegroundColor $(if ($posFail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("RESULT: {0} pass / {1} fail (of {2})" -f ($script:results.Count - $fail), $fail, $script:results.Count) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

if ($ProofOut) {
  $report = [pscustomobject]@{
    suite = 'NEO-4.0-P4-C6-ROUTER'; timestamp = $TS
    negative_guards = $neg.Count; negative_pass = ($neg.Count - $negFail)
    positive_checks = $pos.Count; positive_pass = ($pos.Count - $posFail)
    fail = $fail; results = $script:results
  }
  ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ProofOut -Encoding UTF8
  Write-Host "proof written: $ProofOut"
}

$residueClean = $true
if (-not $KeepScratch) {
  Remove-Item -Recurse -Force -LiteralPath $ScratchRoot
  $residueClean = -not (Test-Path -LiteralPath $ScratchRoot)
  Write-Host ("residue-clean: {0} (scratch removed)" -f $residueClean)
}

if ($fail -eq 0 -and $residueClean) { exit 0 } else { exit 1 }
