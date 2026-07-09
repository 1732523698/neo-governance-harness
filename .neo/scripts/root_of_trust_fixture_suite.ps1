# root_of_trust_fixture_suite.ps1 - NEO 3.1 P1-S5 permanent negative-fixture suite for the section 4.9
# root-of-trust anchor + section 4.4a lint-self pre-gate (verify_root_of_trust.ps1).
# ASCII-only, PowerShell 5.1. Sibling to custody_fixture_suite.ps1 (same self-clean discipline).
#
# PURPOSE: make verify_root_of_trust.ps1's fail-closed modes into STANDING regression tests. It builds a
# self-contained fixture NeoRoot (copies of lint_skills.ps1 + HUMAN_GATE_LEDGER.json) plus a matching
# host-held anchor, then mutates exactly one artifact per negative and asserts the fail-closed signal
# (exit 1 + the expected [FAIL] line). It edits NO engine/lint/frozen file and never touches the REAL
# anchor or the real .neo\gates ledger - only fixture copies under NEO_SESSION\rot_fixture.
#
# Cases (extends the S4 negative set; N-numbers per the P1-S5 plan):
#   POSITIVE    valid anchor + untampered artifacts                       -> exit 0, ALL CHECKS PASS
#   N5/N1a  lint-self bytes drift vs anchor (section 4.4a)                 -> FAIL DRIFTED (lint verdict UNTRUSTED)
#   N6      ledger bytes drift vs anchor (RT4-R1 ledger anchoring)        -> FAIL DRIFTED
#   N2      anchor ABSENT                                                 -> FAIL ABSENT
#   N3a     anchor malformed JSON                                         -> FAIL not valid JSON
#   N3b     wrong anchor_schema_id                                        -> FAIL not a neo:root_of_trust_anchor
#   N3c     wrong anchor_id                                               -> FAIL anchor_id ... != 'neo:root_of_trust'
#   N3d     anchor self-hash sidecar tampered                            -> FAIL sidecar mismatch
#   N4      anchor_scope != NeoRoot under test                           -> FAIL anchor_scope
#   N-role  anchor drops the human-gate-ledger role (artifact removed)   -> FAIL does not cover required role
#
# PROVISIONAL-DEV: these prove BYTE-INTEGRITY fail-closed behavior. In dev the anchor is principal-writable
# (tamper-EVIDENT, not tamper-PROOF); genuine un-forgeability = Option A / S6 ACL. Honest, not hidden.
#
# Exit 0 only when every case classifies as expected.

# NF-S4-1 style: -NeoRoot (default S:\NEO) locates verify_root_of_trust.ps1 + the source lint/ledger to copy.
param([switch]$KeepArtifacts,[string]$NeoRoot)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$scripts   = Join-Path $NeoRoot '.neo\scripts'
$verifier  = Join-Path $scripts 'verify_root_of_trust.ps1'
$srcLint   = Join-Path $scripts 'lint_skills.ps1'
$srcLedger = Join-Path $NeoRoot '.neo\gates\HUMAN_GATE_LEDGER.json'
$base      = Join-Path $NeoRoot 'NEO_SESSION\rot_fixture'

$script:failures = 0
$script:passes   = 0
$script:results  = New-Object System.Collections.ArrayList

function Report([string]$case,[bool]$ok,[string]$detail){
  $tag = if($ok){'PASS'}else{'FAIL'}
  [void]$script:results.Add(("[{0}] {1,-24} {2}" -f $tag,$case,$detail))
  if($ok){ $script:passes++ } else { $script:failures++ }
}

function Write-RotAnchor{
  param(
    [string]$AnchorPath,[string]$Scope,[string]$Custody,[string]$LintPath,[string]$LedgerPath,
    [bool]$IncludeLedger = $true,[string]$SchemaId = 'neo:root_of_trust_anchor',
    [string]$AnchorId = 'neo:root_of_trust',[bool]$WriteSidecar = $true
  )
  $prot = @( [ordered]@{ path='.neo\scripts\lint_skills.ps1'; role='lint-self'; sha256=(Get-FileHash -LiteralPath $LintPath -Algorithm SHA256).Hash.ToLower() } )
  if($IncludeLedger){ $prot += [ordered]@{ path='.neo\gates\HUMAN_GATE_LEDGER.json'; role='human-gate-ledger'; sha256=(Get-FileHash -LiteralPath $LedgerPath -Algorithm SHA256).Hash.ToLower() } }
  $obj = [ordered]@{
    anchor_schema_id = $SchemaId
    anchor_id        = $AnchorId
    custody          = $Custody
    anchor_scope     = $Scope
    created_at       = (Get-Date).ToString('yyyy-MM-dd')
    note             = 'FIXTURE anchor (root_of_trust_fixture_suite; never the real anchor)'
    protected        = $prot
  }
  ($obj | ConvertTo-Json -Depth 8) | Out-File -LiteralPath $AnchorPath -Encoding ascii
  if($WriteSidecar){
    $h = (Get-FileHash -LiteralPath $AnchorPath -Algorithm SHA256).Hash
    Set-Content -LiteralPath "$AnchorPath.sha256" -Value ("{0}  {1}" -f $h,(Split-Path $AnchorPath -Leaf)) -Encoding ascii -NoNewline
  }
}

function New-RotFixture([string]$name){
  $root = Join-Path $base $name
  $scriptsD = Join-Path $root '.neo\scripts'
  $gatesD   = Join-Path $root '.neo\gates'
  New-Item -ItemType Directory -Force -Path $scriptsD | Out-Null
  New-Item -ItemType Directory -Force -Path $gatesD   | Out-Null
  $lint   = Join-Path $scriptsD 'lint_skills.ps1'
  $ledger = Join-Path $gatesD 'HUMAN_GATE_LEDGER.json'
  Copy-Item -LiteralPath $srcLint   -Destination $lint   -Force
  Copy-Item -LiteralPath $srcLedger -Destination $ledger -Force
  # copies may inherit +R from a locked source; clear so tamper cases can write
  Set-ItemProperty -LiteralPath $lint   -Name IsReadOnly -Value $false
  Set-ItemProperty -LiteralPath $ledger -Name IsReadOnly -Value $false
  $anchor = Join-Path $root 'ANCHOR.json'
  Write-RotAnchor -AnchorPath $anchor -Scope $root -Custody 'provisional-dev' -LintPath $lint -LedgerPath $ledger
  return @{ root=$root; anchor=$anchor; lint=$lint; ledger=$ledger; scriptsD=$scriptsD; gatesD=$gatesD }
}

function Run-Rot([string]$root,[string]$anchor){
  $out = (& $verifier -NeoRoot $root -Anchor $anchor *>&1 | Out-String)
  return @{ code=$LASTEXITCODE; out=$out }
}
function Expect-RotFail([string]$case,[string]$root,[string]$anchor,[string]$needle){
  $r = Run-Rot $root $anchor
  $hit = if($needle){ [bool]($r.out -match [regex]::Escape($needle)) } else { $true }
  Report $case (($r.code -eq 1) -and $hit) "expect exit1 + '$needle'; got exit=$($r.code), needleSeen=$hit"
}

if(-not (Test-Path -LiteralPath $verifier)){ Write-Host "FATAL: verify_root_of_trust.ps1 not found at $verifier"; exit 1 }
if(Test-Path -LiteralPath $base){ Remove-Item -LiteralPath $base -Recurse -Force }
New-Item -ItemType Directory -Force -Path $base | Out-Null

Write-Host "=== root_of_trust_fixture_suite (P1-S5 section 4.9 + 4.4a) NeoRoot=$NeoRoot ==="
Write-Host "[WARN] fixture anchors are provisional-dev (principal-writable); these prove fail-closed BYTE-INTEGRITY, not tamper-proofness (Option A / S6)."

# ---------- POSITIVE ----------
$fx = New-RotFixture 'positive'
$r = Run-Rot $fx.root $fx.anchor
$pass = $r.out -match 'ALL CHECKS PASS'
Report 'POSITIVE' (($r.code -eq 0) -and $pass) "expect exit0 + ALL CHECKS PASS; got exit=$($r.code), passSeen=$pass"

# ---------- N5/N1a lint-self drift (section 4.4a: lint verdict UNTRUSTED on drift) ----------
$fx = New-RotFixture 'n5_lint_drift'
Add-Content -LiteralPath $fx.lint -Value "`r`n# tamper byte (simulated lint edit; lint could still self-exit 0)"
Expect-RotFail 'N5-lintself_drift' $fx.root $fx.anchor 'DRIFTED vs anchor: .neo\scripts\lint_skills.ps1'

# ---------- N6 ledger drift (RT4-R1 ledger anchoring) ----------
$fx = New-RotFixture 'n6_ledger_drift'
Add-Content -LiteralPath $fx.ledger -Value "`r`n"
Expect-RotFail 'N6-ledger_drift' $fx.root $fx.anchor 'DRIFTED vs anchor: .neo\gates\HUMAN_GATE_LEDGER.json'

# ---------- N2 anchor absent ----------
$fx = New-RotFixture 'n2_absent'
$ghost = Join-Path $fx.root 'NO_SUCH_ANCHOR.json'
Expect-RotFail 'N2-anchor_absent' $fx.root $ghost 'anchor ABSENT'

# ---------- N3a malformed anchor JSON ----------
$fx = New-RotFixture 'n3a_malformed'
Set-Content -LiteralPath $fx.anchor -Value '{ not : valid json ' -Encoding ascii
Expect-RotFail 'N3a-malformed_anchor' $fx.root $fx.anchor 'not valid JSON'

# ---------- N3b wrong anchor_schema_id ----------
$fx = New-RotFixture 'n3b_schemaid'
Write-RotAnchor -AnchorPath $fx.anchor -Scope $fx.root -Custody 'provisional-dev' -LintPath $fx.lint -LedgerPath $fx.ledger -SchemaId 'neo:not_an_anchor'
Expect-RotFail 'N3b-schemaid_spoof' $fx.root $fx.anchor 'not a neo:root_of_trust_anchor instance'

# ---------- N3c wrong anchor_id ----------
$fx = New-RotFixture 'n3c_anchorid'
Write-RotAnchor -AnchorPath $fx.anchor -Scope $fx.root -Custody 'provisional-dev' -LintPath $fx.lint -LedgerPath $fx.ledger -AnchorId 'neo:not_root'
Expect-RotFail 'N3c-anchorid_spoof' $fx.root $fx.anchor "!= 'neo:root_of_trust'"

# ---------- N3d sidecar self-hash tampered (anchor body still valid) ----------
$fx = New-RotFixture 'n3d_sidecar'
Set-Content -LiteralPath "$($fx.anchor).sha256" -Value ("{0}  {1}" -f ('0'*64),(Split-Path $fx.anchor -Leaf)) -Encoding ascii -NoNewline
Expect-RotFail 'N3d-sidecar_tamper' $fx.root $fx.anchor 'self-hash sidecar mismatch'

# ---------- N4 anchor_scope != NeoRoot under test ----------
$fx = New-RotFixture 'n4_scope'
Write-RotAnchor -AnchorPath $fx.anchor -Scope (Join-Path $fx.root 'WRONG_SUBTREE') -Custody 'provisional-dev' -LintPath $fx.lint -LedgerPath $fx.ledger
Expect-RotFail 'N4-scope_mismatch' $fx.root $fx.anchor 'anchor_scope'

# ---------- N-role anchor drops the human-gate-ledger role ----------
$fx = New-RotFixture 'nrole_missing'
Write-RotAnchor -AnchorPath $fx.anchor -Scope $fx.root -Custody 'provisional-dev' -LintPath $fx.lint -LedgerPath $fx.ledger -IncludeLedger $false
Expect-RotFail 'NROLE-missing_ledger' $fx.root $fx.anchor "does not cover required role 'human-gate-ledger'"

# ---------- summary + cleanup ----------
Write-Host ""
foreach($line in $script:results){ Write-Host $line }
Write-Host ""
Write-Host ("Summary: {0} pass, {1} fail." -f $script:passes,$script:failures)

if(-not $KeepArtifacts){
  Remove-Item -LiteralPath $base -Recurse -Force
  if(Test-Path -LiteralPath $base){ Write-Host "[RESIDUE] WARNING: base dir still present after cleanup"; $script:failures++ }
  else { Write-Host "Fixtures removed (NEO_SESSION restored). Second clean pass: 0 residue. Use -KeepArtifacts to inspect." }
}

if($script:failures -gt 0){ Write-Host "=== root_of_trust_fixture_suite: RED - $($script:failures) case(s) misclassified ==="; exit 1 }
Write-Host "=== root_of_trust_fixture_suite: PASS ($($script:passes) fail-closed proofs) ==="
exit 0
