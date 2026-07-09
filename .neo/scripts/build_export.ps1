# build_export.ps1 - PORT-S2 dev->export producer. ASCII-only, PowerShell 5.1.
#
# PURPOSE: emit a clean, SELF-CONTAINED, A-BRIDGE-conforming EXPORT tree (a shippable ARTIFACT, not a third
# live copy) from the DEV NEO tree, RE-CUT every in-tree pin FRESH over the export bytes so the artifact is
# INTERNALLY pin-consistent, RE-CUT the root-of-trust anchor + RELEASE_MANIFEST for the EXPORT scope (NOT the
# dev anchor), and COMPUTE + EMIT the external published root SHA (out-of-band authenticity value).
#
# Custody / scope (PORT-S2):
#   - Reads DEV; WRITES only the export artifact location (never PROD S:\NEO, never a DEV overwrite, never
#     inside the governed DEV tree).
#   - Fresh pins on the ARTIFACT are NOT a governed-surface re-pin: this is a new artifact with its own fresh
#     manifest. The dev/prod governed manifest is untouched.
#   - The in-tree anchor proves only "unchanged since packaging"; authenticity rides the OUT-OF-BAND published
#     root SHA (A-BRIDGE section 5). anchor_scope = EXPORT root; install-location re-cut is PORT-S3 first-run.
#   - This script only EMITS the external root SHA; the verify-vs-published-SHA CHECKER is PORT-S3.
#
# Usage:
#   .\build_export.ps1                         # OutRoot defaults to S:\NEO_export\neo_export_<stamp>
#   .\build_export.ps1 -OutRoot D:\somewhere   # explicit artifact location (must be off all governed trees)
#   .\build_export.ps1 -Force                  # allow a non-empty existing OutRoot

[CmdletBinding()]
param(
  [string]$NeoRoot,
  [string]$OutRoot,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$NeoRoot = (Resolve-Path -LiteralPath $NeoRoot).Path
if (-not $OutRoot) { $OutRoot = Join-Path 'S:\NEO_export' ('neo_export_' + (Get-Date).ToString('yyyyMMdd_HHmmss')) }

function Norm([string]$p){ ($p.Trim().TrimEnd('\','/')).ToLowerInvariant() }
function Sha([string]$p){ (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

# ---------------------------------------------------------------- guards: never PROD, never DEV, never nested
$nOut  = Norm $OutRoot
$nNeo  = Norm $NeoRoot
$nProd = Norm 'S:\NEO'
if ($nOut -eq $nProd -or $nOut.StartsWith($nProd + '\')) { throw "REFUSED: OutRoot is inside/equal PROD (S:\NEO): $OutRoot" }
if ($nOut -eq $nNeo  -or $nOut.StartsWith($nNeo  + '\')) { throw "REFUSED: OutRoot is inside/equal the governed DEV tree: $OutRoot" }
if ($nNeo.StartsWith($nOut + '\'))                       { throw "REFUSED: OutRoot is an ancestor of the DEV tree: $OutRoot" }
if (Test-Path -LiteralPath $OutRoot) {
  $existing = @(Get-ChildItem -LiteralPath $OutRoot -Force)
  if ($existing.Count -gt 0 -and -not $Force) { throw "REFUSED: OutRoot exists and is non-empty (use -Force): $OutRoot" }
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$OutRoot = (Resolve-Path -LiteralPath $OutRoot).Path

Write-Host "=== build_export (PORT-S2 dev->export producer) ==="
Write-Host ("DEV source : " + $NeoRoot)
Write-Host ("EXPORT out : " + $OutRoot)
Write-Host ""

# ---------------------------------------------------------------- 1. COPY the runtime-essential tree (trimmed)
# Include: .neo (engine + doctrine + the 3 net-read _v3.0 archive files + _legacy_quarantine pinned skills),
#          .claude\skills (resolver needs .neo+.claude; lint pins the role skills), the app profile module,
#          an EMPTY NEO_SESSION. Exclude: bulk history (_v2.6_rollback, _v3.1, non-net-read _v3.0) and the DEV
#          anchor (.neo\release) - the export anchor is RE-CUT fresh below (A-BRIDGE 5.5: re-cut, do not copy).
$neoSrc = Join-Path $NeoRoot '.neo'
$neoDst = Join-Path $OutRoot '.neo'
New-Item -ItemType Directory -Force -Path $neoDst | Out-Null
$excludeNeoDirs = @('_v2.6_rollback','_v3.1','release')
$v30NetRead = @(
  'session1\FREEZE_INVENTORY.json',
  'session2\CORPUS_MANIFEST.json',
  'session2\GOLDEN_CORPUS\negatives\app_adapter_fixture_suite.cases.json'
)
foreach ($child in Get-ChildItem -LiteralPath $neoSrc -Force) {
  if ($child.PSIsContainer -and ($excludeNeoDirs -contains $child.Name)) { continue }
  if ($child.PSIsContainer -and $child.Name -eq '_v3.0') {
    foreach ($rel in $v30NetRead) {
      $s = Join-Path $child.FullName $rel
      $d = Join-Path (Join-Path $neoDst '_v3.0') $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $d -Parent) | Out-Null
      Copy-Item -LiteralPath $s -Destination $d -Force
    }
    continue
  }
  $dst = Join-Path $neoDst $child.Name
  if ($child.PSIsContainer) { Copy-Item -LiteralPath $child.FullName -Destination $dst -Recurse -Force }
  else { Copy-Item -LiteralPath $child.FullName -Destination $dst -Force }
}
# .claude\skills (governed skill surface; resolver root marker)
Copy-Item -LiteralPath (Join-Path $NeoRoot '.claude\skills') -Destination (Join-Path $OutRoot '.claude\skills') -Recurse -Force
# app profile module the app-adapter / custody nets read
$modRel = 'modules\unified-analytics-rental-platform'
Copy-Item -LiteralPath (Join-Path $NeoRoot $modRel) -Destination (Join-Path $OutRoot $modRel) -Recurse -Force
# recipient first-run entrypoint + README (PORT-S3): ship at the export tree root. These are runtime-essential
# (unlike the producer, stripped below). Root-level => not auto-pinned by lint, but they ship in the artifact
# and are covered by RELEASE_MANIFEST + the root SHA, so tampering is still caught by verify_neo.ps1.
foreach ($rootFile in @('verify_neo.ps1','README.md')) {
  $src = Join-Path $NeoRoot $rootFile
  if (-not (Test-Path -LiteralPath $src)) { throw "PORT-S3 root file missing in DEV source: $rootFile" }
  Copy-Item -LiteralPath $src -Destination (Join-Path $OutRoot $rootFile) -Force
}
# empty session dir (suites self-create their fixtures here)
New-Item -ItemType Directory -Force -Path (Join-Path $OutRoot 'NEO_SESSION') | Out-Null
# the producer itself is a DEV tool (not runtime-essential) and carries output-location literals; do not ship it.
$selfCopy = Join-Path $OutRoot '.neo\scripts\build_export.ps1'
if (Test-Path -LiteralPath $selfCopy) { Remove-Item -LiteralPath $selfCopy -Force }
Write-Host "[1] copied runtime-essential tree (+ verify_neo.ps1/README.md shipped at root; host-stripped verify_root_of_trust inherited from DEV; DEV anchor + producer NOT shipped)"

# ---------------------------------------------------------------- 2. RE-CUT lint H6 manifests over export bytes
# Rewrite each pinned '"<key>" = "<64hex>"' with the export file's actual SHA-256. key = a role name maps to
# .claude\skills\<role>\SKILL.md; otherwise key is a root-relative path.
$lintPath = Join-Path $OutRoot '.neo\scripts\lint_skills.ps1'
$rx = [regex]'^(\s*")([^"]+)("\s*=\s*")([0-9A-Fa-f]{64})(")\s*$'
$lines = [System.IO.File]::ReadAllLines($lintPath)
$lintRecut = 0
for ($i=0; $i -lt $lines.Length; $i++) {
  $m = $rx.Match($lines[$i])
  if (-not $m.Success) { continue }
  $key = $m.Groups[2].Value
  if ($key -match '^NEO_[A-Z]+$') { $fp = Join-Path $OutRoot (".claude\skills\$key\SKILL.md") }
  else { $fp = Join-Path $OutRoot $key }
  if (-not (Test-Path -LiteralPath $fp)) { throw "lint re-cut: pinned file absent in export: $key -> $fp" }
  $lines[$i] = $m.Groups[1].Value + $key + $m.Groups[3].Value + (Sha $fp) + $m.Groups[5].Value
  $lintRecut++
}
[System.IO.File]::WriteAllLines($lintPath, $lines)
Write-Host ("[2] re-cut lint H6 manifests over export bytes ($lintRecut pins)")

# ---------------------------------------------------------------- 3. RE-CUT FREEZE_INVENTORY over export bytes
$fiPath = Join-Path $OutRoot '.neo\_v3.0\session1\FREEZE_INVENTORY.json'
$fi = Get-Content -LiteralPath $fiPath -Raw | ConvertFrom-Json
$fiRecut = 0
foreach ($gName in $fi.groups.PSObject.Properties.Name) {
  foreach ($e in @($fi.groups.$gName)) {
    if (($e.PSObject.Properties.Name -contains 'path') -and ($e.PSObject.Properties.Name -contains 'sha256')) {
      $fp = Join-Path $OutRoot ([string]$e.path)
      if (Test-Path -LiteralPath $fp) { $e.sha256 = (Sha $fp); $fiRecut++ }
    }
  }
}
($fi | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $fiPath -Encoding ascii
Write-Host ("[3] re-cut FREEZE_INVENTORY group pins over export bytes ($fiRecut entries)")

# ---------------------------------------------------------------- 4. RE-CUT CORPUS_MANIFEST over export bytes
$cmPath = Join-Path $OutRoot '.neo\_v3.0\session2\CORPUS_MANIFEST.json'
$cm = Get-Content -LiteralPath $cmPath -Raw | ConvertFrom-Json
$cmRecut = 0
foreach ($it in @($cm.corpus_items)) {
  if ([string]$it.corpus_path -match 'source_identity/([^/]+\.ps1)$') {
    $fp = Join-Path $OutRoot (".neo\scripts\" + $Matches[1])
    if (Test-Path -LiteralPath $fp) {
      $h = Sha $fp
      $it.sha256 = $h
      if ($it.PSObject.Properties.Name -contains 'live_surface_sha256')     { $it.live_surface_sha256 = $h }
      if ($it.PSObject.Properties.Name -contains 'session1_inventory_sha256'){ $it.session1_inventory_sha256 = $h }
      if ($it.PSObject.Properties.Name -contains 'byte_copy_matches_live')  { $it.byte_copy_matches_live = $true }
      $cmRecut++
    }
  }
}
foreach ($rp in @($cm.referenced_producers)) {
  $fp = Join-Path $OutRoot (([string]$rp.referenced_path) -replace '/','\')
  if (Test-Path -LiteralPath $fp) {
    $h = Sha $fp
    $rp.sha256 = $h
    if ($rp.PSObject.Properties.Name -contains 'session1_inventory_sha256') { $rp.session1_inventory_sha256 = $h }
    if ($rp.PSObject.Properties.Name -contains 'matches_session1')          { $rp.matches_session1 = $true }
    $cmRecut++
  }
}
($cm | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $cmPath -Encoding ascii
Write-Host ("[4] re-cut CORPUS_MANIFEST source_identity + referenced_producers over export bytes ($cmRecut entries)")

# ---------------------------------------------------------------- 5. RE-CUT the export ANCHOR (scope=export root)
$relDir = Join-Path $OutRoot '.neo\release'
New-Item -ItemType Directory -Force -Path $relDir | Out-Null
$lintHash = (Sha (Join-Path $OutRoot '.neo\scripts\lint_skills.ps1')).ToLower()
$ledgHash = (Sha (Join-Path $OutRoot '.neo\gates\HUMAN_GATE_LEDGER.json')).ToLower()
$anchorObj = [ordered]@{
  anchor_schema_id = 'neo:root_of_trust_anchor'
  anchor_id        = 'neo:root_of_trust'
  custody          = 'provisional-dev'
  anchor_scope     = $OutRoot
  created_at       = (Get-Date).ToString('yyyy-MM-dd')
  note             = 'EXPORT-scope section 4.9 root-of-trust anchor, RE-CUT fresh by build_export.ps1 (PORT-S2) over the export bytes; anchor_scope = the EXPORT root (NOT the dev root). The stale dev/off-tree anchor is NOT copied. In-tree + custody=provisional-dev => tamper-EVIDENT, NOT tamper-PROOF; authenticity rides the OUT-OF-BAND published root SHA (A-BRIDGE section 5). If this artifact is MOVED to a different path, anchor_scope no longer matches the resolved root and verify_root_of_trust FAILS CLOSED BY DESIGN until PORT-S3 first-run re-cuts the anchor for the install location. Attests the two artifacts that cannot pin themselves: lint_skills.ps1 (lint-self) and .neo\gates\HUMAN_GATE_LEDGER.json (human-gate-ledger).'
  protected        = @(
    [ordered]@{ path = '.neo\scripts\lint_skills.ps1';            role = 'lint-self';          sha256 = $lintHash }
    [ordered]@{ path = '.neo\gates\HUMAN_GATE_LEDGER.json';       role = 'human-gate-ledger';  sha256 = $ledgHash }
  )
}
$anchorPath = Join-Path $relDir 'ROOT_OF_TRUST_ANCHOR.json'
($anchorObj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $anchorPath -Encoding ascii
$anchorHash = Sha $anchorPath
Set-Content -LiteralPath "$anchorPath.sha256" -Value ("{0}  {1}" -f $anchorHash,'ROOT_OF_TRUST_ANCHOR.json') -Encoding ascii -NoNewline
Write-Host "[5] re-cut export ROOT_OF_TRUST_ANCHOR.json (anchor_scope=export root) + .sha256 sidecar"

# ---------------------------------------------------------------- 6. RELEASE_MANIFEST + external published ROOT SHA
$relManPath = Join-Path $relDir 'RELEASE_MANIFEST.json'
$relManRel  = '.neo/release/RELEASE_MANIFEST.json'
$entries = @()
foreach ($f in Get-ChildItem -LiteralPath $OutRoot -Recurse -File -Force) {
  $rel = ($f.FullName.Substring($OutRoot.Length).TrimStart('\','/')) -replace '\\','/'
  if ($rel.ToLowerInvariant() -eq $relManRel) { continue }   # manifest cannot list itself (it is the SHA preimage)
  $entries += [pscustomobject]@{ path = $rel; sha256 = (Sha $f.FullName).ToLower() }
}
$entries = @($entries | Sort-Object { $_.path.ToLowerInvariant() })
# external root SHA = SHA-256 over the canonical "<sha>  <path>" lines (LF-joined). Authenticates the manifest,
# which authenticates every file. Recomputable by any party from the tree bytes (PORT-S3 checker).
$canon = ($entries | ForEach-Object { $_.sha256 + '  ' + $_.path }) -join "`n"
$sha = New-Object System.Security.Cryptography.SHA256Managed
$rootSha = ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canon))) -replace '-','').ToLower()
$relManifest = [ordered]@{
  manifest_id      = 'neo:release_manifest'
  note             = 'A-BRIDGE in-tree RELEASE_MANIFEST (homes-only; field schema deferred to 4.0 Session-0). Proves ONLY unchanged-since-packaging. Authenticity rides the OUT-OF-BAND published root SHA. root_sha here = SHA-256 over the sorted "<sha>  <path>" lines of files[] (this manifest excluded).'
  produced_by      = 'build_export.ps1 (PORT-S2)'
  produced_at_utc  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  source_dev_root  = $NeoRoot
  export_root      = $OutRoot
  anchor_scope     = $OutRoot
  hash_algorithm   = 'SHA256'
  file_count       = $entries.Count
  root_sha256      = $rootSha
  files            = $entries
}
($relManifest | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $relManPath -Encoding ascii

# external published root SHA sidecar - OUT-OF-BAND, written OUTSIDE the export tree (never in-tree per A-BRIDGE 5)
$shaSidecar = $OutRoot + '.ROOT_SHA.txt'
Set-Content -LiteralPath $shaSidecar -Value ("{0}  neo-export-root  {1}" -f $rootSha,(Split-Path $OutRoot -Leaf)) -Encoding ascii
Write-Host ("[6] wrote RELEASE_MANIFEST.json (" + $entries.Count + " files) + external root SHA sidecar (out-of-band): " + $shaSidecar)
Write-Host ""
Write-Host ("EXPORT_ROOT " + $OutRoot)
Write-Host ("EXPORT_ROOT_SHA256 " + $rootSha)
Write-Host "=== build_export: DONE (DEV + PROD byte-untouched) ==="
exit 0
