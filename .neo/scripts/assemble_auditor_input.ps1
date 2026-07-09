<#
.SYNOPSIS
  Assemble the ALLOWLISTED auditor input bundle into AUDITOR_INPUT/ so NEO_AUDITOR reviews from
  artifacts only — never the coder's chat/history/self-evaluation.
.DESCRIPTION
  Copies/derives only the allowed artifacts (session_contract.json, changed_files/, git_diff.patch,
  test_results.txt, typecheck_results.txt, verifier_residue_report.json, known_constraints.md) and
  writes input_manifest.json. The auditor subagent must be pointed ONLY at this folder.
.EXAMPLE
  .\assemble_auditor_input.ps1 -SessionPath S:\NEO\NEO_SESSION\<id>
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$SessionPath)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SessionPath)) { throw "Session path not found: $SessionPath" }

$out = Join-Path $SessionPath 'AUDITOR_INPUT'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null
$manifest = @()

# session_contract.json (the auditor needs the contract for context)
$contract = Join-Path $SessionPath 'session_contract.json'
if (Test-Path -LiteralPath $contract) { Copy-Item -LiteralPath $contract -Destination (Join-Path $out 'session_contract.json'); $manifest += 'session_contract.json' }

# changed_files/
$cf = Join-Path $SessionPath 'changed_files'
if (Test-Path -LiteralPath $cf) { Copy-Item -LiteralPath $cf -Destination (Join-Path $out 'changed_files') -Recurse; $manifest += 'changed_files' }

# git_diff.patch (concatenate all diffs)
$diffs = Join-Path $SessionPath 'diffs'
if (Test-Path -LiteralPath $diffs) {
  $all = ''
  foreach ($d in (Get-ChildItem -LiteralPath $diffs -Filter '*.patch' -File -ErrorAction SilentlyContinue)) {
    $all += (Get-Content -LiteralPath $d.FullName -Raw -Encoding UTF8) + "`n"
  }
  Set-Content -LiteralPath (Join-Path $out 'git_diff.patch') -Value $all -Encoding UTF8; $manifest += 'git_diff.patch'
}

# test_results.txt + typecheck_results.txt (derived from verifier summary; raw evidence, no confidence language)
$sum = Join-Path $SessionPath 'verifier_results\summary.json'
if (Test-Path -LiteralPath $sum) {
  $s = Get-Content -LiteralPath $sum -Raw -Encoding UTF8 | ConvertFrom-Json
  $tr = "tests_command: " + ((@($s.tests_command)) -join '; ') + "`r`ntests_exit: $($s.tests_exit)`r`ncached: $($s.cached)`r`nfreshness: $($s.freshness)`r`n"
  foreach ($r in @($s.runs)) { $tr += "run: $($r.cmd) exit=$($r.exit)`r`n" }
  Set-Content -LiteralPath (Join-Path $out 'test_results.txt') -Value $tr -Encoding UTF8; $manifest += 'test_results.txt'
  Set-Content -LiteralPath (Join-Path $out 'typecheck_results.txt') -Value ("typecheck_exit: " + $s.typecheck_exit) -Encoding UTF8; $manifest += 'typecheck_results.txt'
}

# verifier_residue_report.json
$rr = Join-Path $SessionPath 'verifier_residue_report.json'
if (Test-Path -LiteralPath $rr) { Copy-Item -LiteralPath $rr -Destination (Join-Path $out 'verifier_residue_report.json'); $manifest += 'verifier_residue_report.json' }

# known_constraints.md
$kc = Join-Path $SessionPath 'known_constraints.md'
if (Test-Path -LiteralPath $kc) { Copy-Item -LiteralPath $kc -Destination (Join-Path $out 'known_constraints.md') }
else { Set-Content -LiteralPath (Join-Path $out 'known_constraints.md') -Value "# Known constraints`r`n(none provided)" -Encoding UTF8 }
$manifest += 'known_constraints.md'

# Build per-file records (objective: C7 re-hashes these to detect post-assembly tampering).
$allowedCats = @('session_contract.json', 'changed_files', 'git_diff.patch', 'test_results.txt', 'typecheck_results.txt', 'verifier_residue_report.json', 'known_constraints.md')
$outResolved = (Resolve-Path -LiteralPath $out).Path
$nowIso = (Get-Date).ToString('o')
$files = @()
foreach ($f in (Get-ChildItem -LiteralPath $out -Recurse -File)) {
  if ($f.Name -eq 'input_manifest.json') { continue }
  $rel = $f.FullName.Substring($outResolved.Length).TrimStart('\', '/').Replace('\', '/')
  $cat = ($rel -split '/')[0]
  $files += [pscustomobject]@{
    relative_path     = $rel
    sha256            = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    created_at        = $nowIso
    source_path       = 'assembled from session ' + (Split-Path $SessionPath -Leaf)
    allowlist_category = $cat
  }
}
[pscustomobject]@{
  assembled_for   = (Split-Path $SessionPath -Leaf)
  allowlist       = $allowedCats
  input_artifacts = $manifest
  files           = $files
  note            = 'Auditor must read ONLY this folder. No coder chat/history/self-eval/why-its-safe narrative is included.'
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'input_manifest.json') -Encoding UTF8

Write-Host "AUDITOR_INPUT assembled at: $out"
foreach ($m in $manifest) { Write-Host "  - $m" }
