# verify_root_of_trust.ps1 - NEO 3.1 P1-S5 section 4.9 root-of-trust verifier + section 4.4a lint-self pre-gate.
# ASCII-only, PowerShell 5.1.
#
# PURPOSE: close the two circular-trust gaps that a self-pin cannot close:
#   section 4.4a lint-self          - lint_skills.ps1 cannot pin itself (a tampered lint could rewrite its own
#                                     recorded hash). This pre-gate verifies lint's on-disk bytes against a
#                                     HOST-HELD anchor BEFORE lint's exit-0 verdict is trusted. A lint-self hash
#                                     mismatch here means lint's verdict is UNTRUSTED regardless of its exit code.
#   RT4-R1 ledger anchoring         - .neo\gates\HUMAN_GATE_LEDGER.json (the authority AS4 binds an UNLOCK_RECORD
#                                     to) is likewise brought under the host-held anchor, so a byte change to the
#                                     ledger is detected out-of-band from the ledger itself.
#
# THE ANCHOR (neo:root_of_trust_anchor, .neo\schema\root_of_trust_anchor.schema.json) lives IN-TREE at its
# A-BRIDGE home .neo\release\ROOT_OF_TRUST_ANCHOR.json (PORT-S2 host-strip: the engine no longer depends on an
# off-tree/host-specific anchor path). The default is a FIXED ROOT-RELATIVE constant resolved against the
# PORT-S1 self-locating root (the relative form is constant, NOT caller/tree DATA); -Anchor overrides it for a
# TRUSTED OPERATOR / fixtures ONLY (mirrors verify_app_slice's -HumanGateLedger precedent) so the governed tree
# under test can never inject its own permissive anchor PATH. Authority-supply defense preserved: fixed
# root-relative default + operator-only -Anchor override.
#
# PROVISIONAL-DEV (honest): the in-tree anchor is a plain file the session principal can still write, so it is
# tamper-EVIDENT, NOT tamper-PROOF (a principal could rewrite the anchor AND the artifact together). Genuine
# un-forgeability would require placing the anchor under a host-owned ACL outside the principal's write scope
# (anchor custody='host-anchored') -- NOT currently pursued. Until then RT4-R1 PASS-WITH-AUTH is NOT trusted in
# PROD; the DEV->PROD push gate is the backstop. This script verifies BYTE-INTEGRITY vs the anchor; the custody
# label tells the consumer HOW MUCH to trust the anchor itself (provisional-dev now; host-anchored if/when ACL'd).
#
# Exit 0 only when: the anchor loads + is a well-formed neo:root_of_trust_anchor with anchor_id=neo:root_of_trust,
# its anchor_scope == the -NeoRoot under test, both required roles (lint-self + human-gate-ledger) are covered,
# and every protected artifact exists on disk with a SHA-256 equal to the anchor's recorded hash. Any failure
# is fail-closed (exit 1). If a <anchor>.sha256 sidecar is present it is also checked (tamper-evidence).

[CmdletBinding()]
param(
  [string]$NeoRoot,
  [string]$Anchor  = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
# FIXED ROOT-RELATIVE default: the anchor's A-BRIDGE in-tree home, resolved against the PORT-S1 root. The
# relative PATH form is a constant (always .neo\release\ROOT_OF_TRUST_ANCHOR.json), NOT caller/tree DATA, so the
# governed tree under test cannot inject a permissive anchor path; -Anchor stays trusted-operator/fixture-only.
$DEFAULT_ANCHOR = Join-Path $NeoRoot '.neo\release\ROOT_OF_TRUST_ANCHOR.json'
$REQUIRED_ROLES = @('lint-self','human-gate-ledger')

$script:fail = 0
function Say-Pass($m){ Write-Host "[PASS] $m" }
function Say-Fail($m){ Write-Host "[FAIL] $m"; $script:fail = 1 }
function Say-Info($m){ Write-Host "[INFO] $m" }

function Norm-Root([string]$p){
  # normalize an absolute governed-root path for comparison (trim trailing slashes; lowercase; single form)
  $t = $p.Trim()
  $t = $t.TrimEnd('\','/')
  return $t.ToLowerInvariant()
}

if(-not $Anchor){ $Anchor = $DEFAULT_ANCHOR }

Write-Host "=== NEO verify_root_of_trust (3.1 P1-S5 section 4.9 + 4.4a) ==="
Write-Host ("NeoRoot: " + $NeoRoot)
Write-Host ("Anchor : " + $Anchor + $(if($Anchor -eq $DEFAULT_ANCHOR){' (fixed in-tree default)'}else{' (-Anchor override; trusted-operator/fixture)'}))
Write-Host ""

# ---------------------------------------------------------------- load the anchor (fail-closed)
if(-not (Test-Path -LiteralPath $Anchor)){
  Say-Fail "root-of-trust anchor ABSENT: $Anchor (fail-closed; cannot trust the chain without the host-held anchor)"
  Write-Host ""
  Write-Host "=== verify_root_of_trust: FAIL ==="
  exit 1
}
$A = $null
try { $A = Get-Content -LiteralPath $Anchor -Raw | ConvertFrom-Json }
catch { Say-Fail "anchor is not valid JSON ($Anchor): $($_.Exception.Message) (fail-closed)" }

if($script:fail -eq 0){
  if($A.anchor_schema_id -ne 'neo:root_of_trust_anchor'){ Say-Fail "anchor is not a neo:root_of_trust_anchor instance (anchor_schema_id='$($A.anchor_schema_id)'; fail-closed)" }
  if($A.anchor_id -ne 'neo:root_of_trust'){ Say-Fail "anchor_id '$($A.anchor_id)' != 'neo:root_of_trust' (named-anchor-identity mismatch; fail-closed)" }
  if($A.custody -notin @('provisional-dev','host-anchored')){ Say-Fail "anchor custody '$($A.custody)' invalid (must be provisional-dev|host-anchored; fail-closed)" }
}

# ---------------------------------------------------------------- optional sidecar self-hash (tamper-evidence)
$sidecar = "$Anchor.sha256"
if($script:fail -eq 0){
  if(Test-Path -LiteralPath $sidecar){
    $recorded = ((Get-Content -LiteralPath $sidecar -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
    $actual = (Get-FileHash -LiteralPath $Anchor -Algorithm SHA256).Hash.ToUpperInvariant()
    if($recorded -ne $actual){ Say-Fail "anchor self-hash sidecar mismatch (anchor tampered vs $([System.IO.Path]::GetFileName($sidecar)); fail-closed)" }
    else { Say-Pass "anchor self-hash matches its .sha256 sidecar (tamper-evidence intact)" }
  } else {
    Say-Info "no <anchor>.sha256 sidecar present (self-hash tamper-evidence not available; anchor byte-integrity still enforced per-artifact below)"
  }
}

# ---------------------------------------------------------------- anchor_scope must match the tree under test
if($script:fail -eq 0){
  if([string]::IsNullOrWhiteSpace([string]$A.anchor_scope)){ Say-Fail "anchor has no anchor_scope (fail-closed)" }
  elseif((Norm-Root ([string]$A.anchor_scope)) -ne (Norm-Root $NeoRoot)){
    Say-Fail "anchor_scope '$($A.anchor_scope)' != NeoRoot under test '$NeoRoot' (a dev anchor cannot attest a different root; fail-closed)"
  } else {
    Say-Pass "anchor_scope matches the NeoRoot under test ($NeoRoot)"
  }
}

# ---------------------------------------------------------------- per-artifact byte-integrity vs the anchor
if($script:fail -eq 0){
  $entries = @($A.protected)
  if($entries.Count -lt 1){ Say-Fail "anchor 'protected' list is empty (nothing attested; fail-closed)" }
  $rolesSeen = @()
  foreach($e in $entries){
    $rel = [string]$e.path
    $role = [string]$e.role
    $want = ([string]$e.sha256).ToLowerInvariant()
    $rolesSeen += $role
    if([string]::IsNullOrWhiteSpace($rel) -or [string]::IsNullOrWhiteSpace($want)){ Say-Fail "protected entry missing path/sha256 (fail-closed)"; continue }
    $full = Join-Path $NeoRoot $rel
    if(-not (Test-Path -LiteralPath $full)){ Say-Fail "attested artifact ABSENT on disk: $rel (role=$role; fail-closed)"; continue }
    $have = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    if($have -ne $want){ Say-Fail "attested artifact DRIFTED vs anchor: $rel (role=$role) on-disk=$have anchor=$want (fail-closed)" }
    else { Say-Pass "attested artifact matches anchor: $rel (role=$role)" }
  }
  foreach($rr in $REQUIRED_ROLES){
    if($rolesSeen -notcontains $rr){ Say-Fail "anchor does not cover required role '$rr' (an attacker cannot drop a protected artifact; fail-closed)" }
  }
}

Write-Host ""
if($A -and $A.custody -eq 'provisional-dev'){
  Say-Info "custody=provisional-dev: anchor is tamper-EVIDENT, NOT tamper-PROOF (principal can write the in-tree anchor). Un-forgeability would require a host-owned ACL (custody='host-anchored'), not currently pursued. RT4-R1 PASS-WITH-AUTH remains NOT trusted in PROD (push-gate backstop)."
}

if($script:fail -eq 0){ Write-Host "=== verify_root_of_trust: ALL CHECKS PASS (byte-integrity vs host-held anchor) ==="; exit 0 }
else { Write-Host "=== verify_root_of_trust: FAIL (see [FAIL] lines above) ==="; exit 1 }
