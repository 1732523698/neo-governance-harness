<#
.SYNOPSIS
  NEO_GOVERNOR: resumability-first checkpointing + stale-checkpoint resume guard. Honest by design.
.DESCRIPTION
  -Action checkpoint : write/refresh checkpoint.json (current task/progress/next step, model map,
     spend estimate) and stamp a changed_files_baseline (sha256 of files under -BaselineRoot,
     sandbox-root-relative). Emits governor_report.json.
  -Action resume-check : re-hash changed_files_baseline from checkpoint.json and compare to current
     files. On ANY mismatch/missing file -> STALE_CHECKPOINT: write stop_reason.json, do NOT continue.

  HONESTY SPLIT (do not oversell):
    reliable    = checkpoint, resume-from-checkpoint, stale-checkpoint detection, API provider spend cap
    best-effort = own-counter token/cost estimate, proactive pause before likely overrun
    unsupported = exact subscription quota; auto-resume after reset (needs an external scheduler)
.EXAMPLE
  .\governor.ps1 -SessionPath <dir> -Action checkpoint -CurrentTask T1 -Progress "edited index.js" -NextStep "run verifier" -BaselineRoot S:\NEO\modules\echo -SpendAmount 0.12 -SpendUnit api_usd
  .\governor.ps1 -SessionPath <dir> -Action resume-check
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SessionPath,
  [Parameter(Mandatory = $true)][ValidateSet('checkpoint', 'resume-check')][string]$Action,
  [string]$CurrentTask = '',
  [string]$Progress = '',
  [string]$NextStep = '',
  [string]$BaselineRoot,
  [double]$SpendAmount = 0,
  [ValidateSet('api_usd', 'output_tokens')][string]$SpendUnit = 'api_usd',
  [bool]$SpendIsEstimate = $true,
  [string]$UpdatedAt = ''
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SessionPath)) { throw "Session path not found: $SessionPath" }
$sandboxRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$cpPath = Join-Path $SessionPath 'checkpoint.json'

function Read-Json($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return '__PARSE_ERROR__' }
}
function Get-BaselineHashes($root) {
  $list = @()
  if ($root -and (Test-Path -LiteralPath $root)) {
    $rootResolved = (Resolve-Path -LiteralPath $root).Path
    foreach ($f in (Get-ChildItem -LiteralPath $rootResolved -Recurse -File -ErrorAction SilentlyContinue)) {
      $rel = $f.FullName.Substring($sandboxRoot.Length).TrimStart('\', '/').Replace('\', '/')
      $list += [pscustomobject]@{ path = $rel; sha256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
    }
  }
  return $list
}

$contract = Read-Json (Join-Path $SessionPath 'session_contract.json')
$sessionId = 'unknown'; if ($contract -and $contract -ne '__PARSE_ERROR__') { $sessionId = $contract.session_id }

if ($Action -eq 'checkpoint') {
  if (-not $UpdatedAt) { $UpdatedAt = (Get-Date).ToString('o') }
  $baseline = Get-BaselineHashes $BaselineRoot
  $checkpoint = [pscustomobject]@{
    session_id              = $sessionId
    current_task            = $CurrentTask
    progress                = $Progress
    next_step               = $NextStep
    model_map               = [pscustomobject]@{}
    spend_so_far            = [pscustomobject]@{ unit = $SpendUnit; amount = $SpendAmount; is_estimate = $SpendIsEstimate }
    changed_files_baseline  = @($baseline)
    updated_at              = $UpdatedAt
  }
  $checkpoint | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cpPath -Encoding UTF8
  [pscustomobject]@{ action = 'checkpoint'; session_id = $sessionId; baseline_files = @($baseline).Count; spend = "$SpendAmount $SpendUnit (estimate=$SpendIsEstimate)"; updated_at = $UpdatedAt } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $SessionPath 'governor_report.json') -Encoding UTF8
  Write-Host "Checkpoint written: $cpPath (baseline files=$(@($baseline).Count))"
  Write-Host "HONESTY: spend is an $(if($SpendIsEstimate){'ESTIMATE (best-effort)'}else{'provider-reported value'}); exact subscription quota is NOT tracked; auto-resume after reset needs an external scheduler."
  exit 0
}
else {
  # resume-check: STALE-CHECKPOINT GUARD
  $cp = Read-Json $cpPath
  if ($null -eq $cp) { throw "No checkpoint.json to resume from at $cpPath" }
  if ($cp -eq '__PARSE_ERROR__') { throw "checkpoint.json is invalid JSON" }
  $mismatches = @()
  foreach ($rec in @($cp.changed_files_baseline)) {
    $full = Join-Path $sandboxRoot ($rec.path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full)) { $mismatches += "missing: $($rec.path)"; continue }
    $h = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    if ($h -ne $rec.sha256) { $mismatches += "changed: $($rec.path)" }
  }
  $resumeOk = ($mismatches.Count -eq 0)
  [pscustomobject]@{ action = 'resume-check'; session_id = $sessionId; resume_ok = $resumeOk; mismatches = $mismatches } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $SessionPath 'governor_report.json') -Encoding UTF8
  if (-not $resumeOk) {
    [pscustomobject]@{ reason = 'STALE_CHECKPOINT'; detail = 'changed_files_baseline no longer matches working tree; refusing to resume from a possibly invalid checkpoint'; files = $mismatches; route = 'PM -> Ambassador' } |
      ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $SessionPath 'stop_reason.json') -Encoding UTF8
    Write-Host "STALE_CHECKPOINT - resume refused. Mismatches: $($mismatches -join '; ')" -ForegroundColor Red
    Write-Host "Routed via PM -> Ambassador (stop_reason.json written)."
    exit 1
  }
  Write-Host "Resume OK - working tree matches checkpoint baseline ($(@($cp.changed_files_baseline).Count) files)." -ForegroundColor Green
  exit 0
}
