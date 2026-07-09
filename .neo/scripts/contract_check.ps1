<#
.SYNOPSIS
  NEO_CONTRACT_CHECK: graduation-readiness check. Runs ONLY for graduation candidates.
.DESCRIPTION
  If session_contract.graduation_target is null -> SKIPPED (does NOT block sandbox-only modules).
  Otherwise verifies the module's contract.json: required fields present; exported_symbols actually
  appear in the module source; names non-colliding (no dupes, and not in an optional collision
  registry); allowed/forbidden side effects disjoint; and a static scan that the source does not
  perform any declared FORBIDDEN side effect. Emits contract_check_report.json.
.EXAMPLE
  .\contract_check.ps1 -SessionPath <dir> -ModuleRoot S:\NEO\modules\util
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SessionPath,
  [string]$ModuleRoot,
  [string]$CollisionRegistry
)
$ErrorActionPreference = 'Stop'
function Read-Json($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return '__PARSE_ERROR__' }
}
function Write-Report($obj) { $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $SessionPath 'contract_check_report.json') -Encoding UTF8 }

$contract = Read-Json (Join-Path $SessionPath 'session_contract.json')
if ($null -eq $contract -or $contract -eq '__PARSE_ERROR__') { throw "Invalid/missing session_contract.json" }

# GATE: only graduation candidates are checked.
if (-not $contract.graduation_target) {
  Write-Report ([pscustomobject]@{ status = 'SKIPPED'; reason = 'session_contract.graduation_target is null (sandbox-only module; not a graduation candidate)'; problems = @() })
  Write-Host "NEO_CONTRACT_CHECK: SKIPPED (not a graduation candidate)." -ForegroundColor Yellow
  exit 0
}

if (-not $ModuleRoot) { throw "ModuleRoot is required for a graduation candidate." }
if (-not (Test-Path -LiteralPath $ModuleRoot)) { throw "ModuleRoot not found: $ModuleRoot" }
$mc = Read-Json (Join-Path $ModuleRoot 'contract.json')
$problems = @()
if ($null -eq $mc) { $problems += 'module contract.json missing' }
elseif ($mc -eq '__PARSE_ERROR__') { $problems += 'module contract.json invalid JSON' }
else {
  foreach ($req in @('module_name', 'declared_inputs', 'declared_outputs', 'exported_symbols', 'connection_points', 'allowed_side_effects', 'forbidden_side_effects', 'graduation_target')) {
    if ($null -eq $mc.$req) { $problems += "contract missing '$req'" }
  }
  foreach ($req in @('declared_inputs', 'declared_outputs', 'exported_symbols', 'connection_points')) {
    if ((@($mc.$req)).Count -eq 0) { $problems += "'$req' is empty" }
  }
  # source text (everything under ModuleRoot except contract.json)
  $src = ''
  foreach ($f in (Get-ChildItem -LiteralPath $ModuleRoot -Recurse -File -ErrorAction SilentlyContinue)) {
    if ($f.Name -eq 'contract.json') { continue }
    $src += (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8) + "`n"
  }
  # exported symbols must appear in source
  foreach ($sym in @($mc.exported_symbols)) {
    if ($sym -and -not [regex]::IsMatch($src, '\b' + [regex]::Escape($sym) + '\b')) { $problems += "exported symbol '$sym' not found in module source" }
  }
  # non-colliding: no duplicate exported symbols
  $dups = @($mc.exported_symbols | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  if ($dups.Count -gt 0) { $problems += "duplicate exported symbols: " + ($dups -join ', ') }
  # optional collision registry
  if ($CollisionRegistry -and (Test-Path -LiteralPath $CollisionRegistry)) {
    $reg = @(Read-Json $CollisionRegistry)
    foreach ($sym in @($mc.exported_symbols)) { if ($reg -contains $sym) { $problems += "exported symbol '$sym' collides with collision registry" } }
  }
  # allowed/forbidden disjoint
  $overlap = @($mc.allowed_side_effects | Where-Object { @($mc.forbidden_side_effects) -contains $_ })
  if ($overlap.Count -gt 0) { $problems += "side effects in both allowed+forbidden: " + ($overlap -join ', ') }
  # static scan: source must NOT perform a declared forbidden side effect
  $fx = @{
    'network'         = 'fetch\(|https?://|require\((["''])https?|axios|http\.request'
    'child_process'   = 'child_process|\bexec\(|\bspawn\('
    'filesystem_write' = 'writeFile|fs\.write|appendFile'
    'env'             = 'process\.env'
    'eval'            = '\beval\('
  }
  foreach ($f in @($mc.forbidden_side_effects)) {
    if ($fx.ContainsKey($f) -and [regex]::IsMatch($src, $fx[$f])) { $problems += "forbidden side effect '$f' detected in module source" }
  }
}

$status = 'PASS'; if ($problems.Count -gt 0) { $status = 'FAIL' }
Write-Report ([pscustomobject]@{ status = $status; module_name = $(if ($mc -and $mc -ne '__PARSE_ERROR__') { $mc.module_name } else { $null }); graduation_target = $contract.graduation_target; problems = $problems })
Write-Host ""
Write-Host "NEO_CONTRACT_CHECK (graduation candidate -> $($contract.graduation_target))"
if ($status -eq 'PASS') { Write-Host "CONTRACT-CHECK: PASS" -ForegroundColor Green; exit 0 }
else { Write-Host ("CONTRACT-CHECK: FAIL - " + ($problems -join '; ')) -ForegroundColor Red; exit 1 }
