# verify_neo.ps1 - NEO PORT-S3 recipient first-run VERIFY entrypoint + install-location anchor re-cut.
# ASCII-only, PowerShell 5.1. Lives at the NEO tree root; dot-sources the PORT-S1 self-locating resolver.
#
# WHAT IT PROVES (the recipient authenticity gate, fail-closed per T1):
#   1. UNCHANGED-SINCE-PACKAGING : re-hash every RELEASE_MANIFEST.files[] entry vs its recorded sha256, and
#      confirm there are no MISSING and no EXTRA files vs the manifest.
#   2. INTERNAL CONSISTENCY      : recompute the root SHA by the canonical method (SHA-256 over the sorted
#      "<sha256>  <path>" lines of files[], LF-joined, manifest excluded) and confirm it == manifest.root_sha256.
#   3. AUTHENTICITY              : compare that recomputed root SHA to the PUBLISHED root SHA the recipient
#      supplies OUT-OF-BAND via -PublishedRootSha. The in-tree manifest proves ONLY "unchanged since
#      packaging"; authenticity rides the out-of-band published SHA (A-BRIDGE section 5).
#   PASS (exit 0) ONLY if all three hold. If NO -PublishedRootSha is supplied -> FAIL-CLOSED (never pass on
#   internal consistency alone). FAIL (exit 1) on any tamper / mismatch / missing / extra / malformed.
#
# VERIFY IS ONE-TIME PRISTINE: it is STRICT against the freshly-unzipped tree. Once you RUN NEO (which writes
# under NEO_SESSION) or run -ReCutAnchor (which rewrites the anchor), verify no longer passes - that is the
# intended contract, not a defect. Verify BEFORE you use NEO.
#
# INSTALL RE-CUT (-ReCutAnchor): after verify PASSES, re-cut .neo\release\ROOT_OF_TRUST_ANCHOR.json so
# anchor_scope = your actual install path, making verify_root_of_trust pass locally. It REFUSES if verify
# did not pass (never re-cut an unverified/inauthentic tree). This mutates only YOUR copy; it does not
# refresh the manifest (re-check authenticity from a fresh unzip).
#
# Usage:
#   .\verify_neo.ps1 -PublishedRootSha <64-hex>                # authenticity gate (verify only)
#   .\verify_neo.ps1 -PublishedRootSha <64-hex> -ReCutAnchor   # verify, then install re-cut on PASS
#   (If .ps1 files are blocked by Mark-of-the-Web, see README.md step 0: Unblock-File / -ExecutionPolicy.)

[CmdletBinding()]
param(
  [string]$PublishedRootSha,
  [string]$NeoRoot,
  [switch]$ReCutAnchor
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\.neo\scripts\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$NeoRoot = (Resolve-Path -LiteralPath $NeoRoot).Path

$MANIFEST_REL = '.neo/release/RELEASE_MANIFEST.json'
$ANCHOR_REL   = '.neo/release/ROOT_OF_TRUST_ANCHOR.json'

$script:fail = 0
function Say-Pass($m){ Write-Host "[PASS] $m" }
function Say-Fail($m){ Write-Host "[FAIL] $m"; $script:fail = 1 }
function Say-Info($m){ Write-Host "[INFO] $m" }

function Sha([string]$p){ (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Canon-RootSha($entries){
  # canonical method - MUST match build_export.ps1 producer byte-for-byte:
  # sort by path.ToLowerInvariant(); "<sha256>  <path>" (two spaces); LF-joined; lowercased hex SHA-256 over UTF8.
  $sorted = @($entries | Sort-Object { ([string]$_.path).ToLowerInvariant() })
  $canon  = ($sorted | ForEach-Object { ([string]$_.sha256).ToLowerInvariant() + '  ' + [string]$_.path }) -join "`n"
  $h = New-Object System.Security.Cryptography.SHA256Managed
  return ([BitConverter]::ToString($h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canon))) -replace '-','').ToLower()
}

Write-Host "=== NEO verify_neo (PORT-S3 recipient first-run authenticity gate) ==="
Write-Host ("NeoRoot : " + $NeoRoot)
Write-Host ""

# ---------------------------------------------------------------- 0. published SHA presence + shape (T1 fail-closed)
$pubOk = $false
$pubNorm = ''
if ([string]::IsNullOrWhiteSpace($PublishedRootSha)) {
  Say-Fail "NO -PublishedRootSha supplied: authenticity CANNOT be established out-of-band -> FAIL-CLOSED (T1). The in-tree manifest proves only 'unchanged since packaging', never authenticity."
} else {
  $p = $PublishedRootSha.Trim()
  if ($p.ToLowerInvariant().StartsWith('sha256:')) { $p = $p.Substring(7).Trim() }
  $p = $p.ToLowerInvariant()
  if ($p -notmatch '^[0-9a-f]{64}$') {
    Say-Fail "-PublishedRootSha is not a 64-hex SHA-256 (malformed input) -> FAIL-CLOSED"
  } else {
    $pubOk = $true; $pubNorm = $p
    Say-Info "published root SHA supplied (out-of-band): $pubNorm"
  }
}

# ---------------------------------------------------------------- 1. load + validate RELEASE_MANIFEST (fail-closed)
$manFull = Join-Path $NeoRoot ($MANIFEST_REL -replace '/','\')
$M = $null
if (-not (Test-Path -LiteralPath $manFull)) {
  Say-Fail "RELEASE_MANIFEST ABSENT: $MANIFEST_REL (cannot verify; fail-closed)"
} else {
  try { $M = Get-Content -LiteralPath $manFull -Raw | ConvertFrom-Json }
  catch { Say-Fail "RELEASE_MANIFEST is not valid JSON: $($_.Exception.Message) (malformed; fail-closed)" }
}
if ($M) {
  if ([string]$M.manifest_id -ne 'neo:release_manifest') { Say-Fail "manifest_id '$($M.manifest_id)' != 'neo:release_manifest' (malformed; fail-closed)" }
  if (([string]$M.root_sha256) -notmatch '^[0-9A-Fa-f]{64}$') { Say-Fail "manifest.root_sha256 missing/!64-hex (malformed; fail-closed)" }
  if (-not ($M.PSObject.Properties.Name -contains 'files') -or @($M.files).Count -lt 1) { Say-Fail "manifest.files[] missing/empty (malformed; fail-closed)" }
  else {
    foreach ($e in @($M.files)) {
      if ([string]::IsNullOrWhiteSpace([string]$e.path) -or (([string]$e.sha256) -notmatch '^[0-9A-Fa-f]{64}$')) {
        Say-Fail "manifest has a files[] entry missing path or valid 64-hex sha256 (malformed; fail-closed)"; break
      }
    }
  }
}

# if the manifest is unusable, stop here (fail-closed) - the rest of the checks need a well-formed files[]
if ($script:fail -ne 0 -and -not ($M -and ($M.PSObject.Properties.Name -contains 'files') -and @($M.files).Count -ge 1 -and (([string]$M.root_sha256) -match '^[0-9A-Fa-f]{64}$'))) {
  Write-Host ""
  Write-Host "=== verify_neo: FAIL (see [FAIL] lines) ==="
  exit 1
}

# ---------------------------------------------------------------- 2. per-file unchanged-since-packaging
$manPathsLower = @{}
foreach ($e in @($M.files)) { $manPathsLower[([string]$e.path).ToLowerInvariant()] = $true }
$missing = 0; $tampered = 0; $matched = 0
foreach ($e in @($M.files)) {
  $rel = [string]$e.path
  $want = ([string]$e.sha256).ToLowerInvariant()
  $full = Join-Path $NeoRoot ($rel -replace '/','\')
  if (-not (Test-Path -LiteralPath $full)) { Say-Fail "MISSING vs manifest: $rel (fail-closed)"; $missing++; continue }
  $have = Sha $full
  if ($have -ne $want) { Say-Fail "TAMPERED vs manifest: $rel  on-disk=$have  manifest=$want (fail-closed)"; $tampered++ }
  else { $matched++ }
}
if ($missing -eq 0 -and $tampered -eq 0) { Say-Pass "all $matched manifest files present + unchanged since packaging" }

# ---------------------------------------------------------------- 3. no EXTRA files vs manifest
$extra = 0
foreach ($f in Get-ChildItem -LiteralPath $NeoRoot -Recurse -File -Force) {
  $rel = ($f.FullName.Substring($NeoRoot.Length).TrimStart('\','/')) -replace '\\','/'
  $relLower = $rel.ToLowerInvariant()
  if ($relLower -eq $MANIFEST_REL.ToLowerInvariant()) { continue }   # manifest excludes itself (it is the SHA preimage)
  if ($relLower -eq '.git' -or $relLower.StartsWith('.git/')) { continue }   # ignore the git working tree (public cut)
  if (-not $manPathsLower.ContainsKey($relLower)) { Say-Fail "EXTRA file not in manifest: $rel (fail-closed)"; $extra++ }
}
if ($extra -eq 0) { Say-Pass "no extra files beyond the manifest (tree matches manifest exactly)" }

# ---------------------------------------------------------------- 4. internal consistency: recomputed root == manifest.root_sha256
$recomputed = Canon-RootSha @($M.files)
$manRoot = ([string]$M.root_sha256).ToLowerInvariant()
if ($recomputed -ne $manRoot) { Say-Fail "recomputed root SHA != manifest.root_sha256  recomputed=$recomputed  manifest=$manRoot (internal inconsistency; fail-closed)" }
else { Say-Pass "recomputed root SHA == manifest.root_sha256 (internal consistency: $recomputed)" }

# ---------------------------------------------------------------- 5. authenticity: recomputed root == published root
if ($pubOk) {
  if ($recomputed -ne $pubNorm) { Say-Fail "recomputed root SHA != PUBLISHED root SHA  recomputed=$recomputed  published=$pubNorm (INAUTHENTIC / wrong SHA; fail-closed)" }
  else { Say-Pass "recomputed root SHA == PUBLISHED root SHA (authentic: $recomputed)" }
}
# (absent/malformed published SHA already recorded a fail in step 0 -> overall FAIL-CLOSED)

Write-Host ""
if ($script:fail -ne 0) {
  Write-Host "=== verify_neo: FAIL (see [FAIL] lines) - DO NOT trust or use this folder ==="
  if ($ReCutAnchor) { Say-Info "-ReCutAnchor REFUSED: verify did not PASS (never re-cut an unverified/inauthentic tree)." }
  exit 1
}
Write-Host "=== verify_neo: PASS - folder is unchanged since packaging AND authentic vs the published root SHA ==="

# ---------------------------------------------------------------- 6. install-location anchor RE-CUT (guarded: only after PASS)
if ($ReCutAnchor) {
  Write-Host ""
  Write-Host "--- install re-cut: ROOT_OF_TRUST_ANCHOR.json for this install path ---"
  $anchorFull = Join-Path $NeoRoot ($ANCHOR_REL -replace '/','\')
  if (-not (Test-Path -LiteralPath $anchorFull)) { Say-Fail "cannot re-cut: anchor absent at $ANCHOR_REL"; Write-Host "=== verify_neo: RE-CUT FAIL ==="; exit 1 }
  $lintFull = Join-Path $NeoRoot '.neo\scripts\lint_skills.ps1'
  $ledgFull = Join-Path $NeoRoot '.neo\gates\HUMAN_GATE_LEDGER.json'
  if (-not (Test-Path -LiteralPath $lintFull)) { Say-Fail "cannot re-cut: lint_skills.ps1 absent"; exit 1 }
  if (-not (Test-Path -LiteralPath $ledgFull)) { Say-Fail "cannot re-cut: HUMAN_GATE_LEDGER.json absent"; exit 1 }
  $anchorObj = [ordered]@{
    anchor_schema_id = 'neo:root_of_trust_anchor'
    anchor_id        = 'neo:root_of_trust'
    custody          = 'provisional-dev'
    anchor_scope     = $NeoRoot
    created_at       = (Get-Date).ToString('yyyy-MM-dd')
    note             = 'INSTALL-LOCATION root-of-trust anchor, RE-CUT by verify_neo.ps1 (PORT-S3 first-run) AFTER a PASSing verify, for this recipient install path. anchor_scope = the resolved local NEO root. In-tree + custody=provisional-dev => tamper-EVIDENT, NOT tamper-PROOF; authenticity was established out-of-band by the published root SHA at verify time (A-BRIDGE section 5). This re-cut makes verify_root_of_trust pass at the install path; it does NOT refresh RELEASE_MANIFEST - re-check authenticity from a fresh unzip. Attests the two artifacts that cannot pin themselves: lint_skills.ps1 (lint-self) and .neo\gates\HUMAN_GATE_LEDGER.json (human-gate-ledger).'
    protected        = @(
      [ordered]@{ path = '.neo\scripts\lint_skills.ps1';      role = 'lint-self';         sha256 = (Sha $lintFull) }
      [ordered]@{ path = '.neo\gates\HUMAN_GATE_LEDGER.json'; role = 'human-gate-ledger'; sha256 = (Sha $ledgFull) }
    )
  }
  ($anchorObj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $anchorFull -Encoding ascii
  $anchorHash = (Get-FileHash -LiteralPath $anchorFull -Algorithm SHA256).Hash
  Set-Content -LiteralPath "$anchorFull.sha256" -Value ("{0}  {1}" -f $anchorHash,'ROOT_OF_TRUST_ANCHOR.json') -Encoding ascii -NoNewline
  Write-Host ("[re-cut] anchor_scope set to install path + .sha256 sidecar regenerated: " + $NeoRoot)
  Write-Host "=== verify_neo: PASS + install re-cut DONE (run verify_root_of_trust to confirm the net passes here) ==="
}
exit 0
