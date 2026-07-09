<#
.SYNOPSIS
  NEO_VERIFIER executor (v1, FILESYSTEM-ONLY): seed-agnostic run -> two-layer residue -> cleanup
  -> second clean run. Produces objective pass/fail evidence. It does NOT fix failures or judge
  test adequacy.
.DESCRIPTION
  Procedure:
    1. Guard: contract.state_surfaces must be ["filesystem"] only (v1 does not implement DB/object/
       external cleanup).
    2. Snapshot BEFORE (sha256 of every file under -SnapshotRoot, minus volatile paths).
    3. Run each command in contract.test_plan (always non-cached); capture cmd, exit, timestamps.
    4. Snapshot AFTER; classify created / modified / removed files vs BEFORE.
    5. Layer-1 cleanup: delete the CREATED files (recorded in the manifest). modified/removed source
       files cannot be auto-restored in v1 -> they make the residue diff NOT clean.
    6. Snapshot AFTER-CLEANUP; diff_clean = (post-cleanup state == before state).
    7. Second run from the clean state; second_run_pass = (all exit 0) AND (clean again after).
    8. Emit verifier_results/summary.json + verifier_residue_report.json.
  Timestamps come from Get-Date (this is a real script, not a workflow body).
.EXAMPLE
  .\verifier.ps1 -SessionPath S:\NEO\NEO_SESSION\<id> -SnapshotRoot S:\NEO\modules\echo
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SessionPath,
  [string]$SnapshotRoot
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"

function Read-Json($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return '__PARSE_ERROR__' }
}

$contract = Read-Json (Join-Path $SessionPath 'session_contract.json')
if ($null -eq $contract -or $contract -eq '__PARSE_ERROR__') { throw "Invalid/missing session_contract.json in $SessionPath" }

# --- guard: filesystem-only (v1) ---
$surfaces = @($contract.state_surfaces)
$nonFs = @($surfaces | Where-Object { $_ -ne 'filesystem' })
if ($nonFs.Count -gt 0) {
  throw "v1 verifier is FILESYSTEM-ONLY. Contract declares unsupported surface(s): $($nonFs -join ', '). Do not run DB/object/external verification in this version."
}
if ($surfaces.Count -eq 0) { throw "contract.state_surfaces is empty." }

if (-not $SnapshotRoot) { $SnapshotRoot = Join-Path (Resolve-NeoRoot $PSScriptRoot) 'modules' }
if (-not (Test-Path -LiteralPath $SnapshotRoot)) { throw "SnapshotRoot not found: $SnapshotRoot" }
$rootResolved = (Resolve-Path -LiteralPath $SnapshotRoot).Path
$sandboxRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path  # NEO root (self-located)
# safety: never let SnapshotRoot be a governance dir
foreach ($bad in @('\.neo', '\.claude', '\NEO_SESSION')) {
  if ($rootResolved -like "*$bad*") { throw "Refusing to snapshot a governance path: $rootResolved" }
}

$volatile = @($contract.volatile_paths_ignored_in_residue)
function Test-Volatile($rel) {
  foreach ($v in $volatile) { $vv = ($v -replace '\\', '/') -replace '\*\*', '*'; if (($rel -replace '\\', '/') -like $vv) { return $true } }
  return $false
}
function Get-Snapshot($root) {
  $map = @{}
  if (-not (Test-Path -LiteralPath $root)) { return $map }
  foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue)) {
    # paths are SANDBOX-ROOT-relative so they share the contract's frame (approved_paths/keep_paths)
    $rel = $f.FullName.Substring($sandboxRoot.Length).TrimStart('\', '/')
    if (Test-Volatile $rel) { continue }
    $map[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
  }
  return $map
}
function Compare-Snapshot($before, $after) {
  $created = @(); $modified = @(); $removed = @()
  foreach ($k in $after.Keys) { if (-not $before.ContainsKey($k)) { $created += $k } elseif ($before[$k] -ne $after[$k]) { $modified += $k } }
  foreach ($k in $before.Keys) { if (-not $after.ContainsKey($k)) { $removed += $k } }
  return [pscustomobject]@{ created = $created; modified = $modified; removed = $removed }
}
function Invoke-TestPlan($plan) {
  $runs = @()
  foreach ($cmd in @($plan)) {
    $start = (Get-Date).ToString('o')
    $global:LASTEXITCODE = 0
    $exit = 0
    try {
      Push-Location -LiteralPath $rootResolved
      cmd.exe /c $cmd 2>&1 | Out-Null
      $exit = $LASTEXITCODE
    } catch { $exit = 1 } finally { Pop-Location }
    $runs += [pscustomobject]@{ cmd = $cmd; exit = $exit; started = $start; ended = (Get-Date).ToString('o') }
  }
  return $runs
}

$keepPaths = @($contract.residue_keep_paths)
function Test-Keep($rel) {
  foreach ($k in $keepPaths) { $kk = ($k -replace '\\', '/') -replace '\*\*', '*'; if (($rel -replace '\\', '/') -like $kk) { return $true } }
  return $false
}

# --- snapshot_limits guard: FAIL (never silently partial) ---
$maxFiles = 5000; $maxTotalMb = 500; $maxSingleMb = 50
if ($contract.snapshot_limits) {
  if ($null -ne $contract.snapshot_limits.max_files) { $maxFiles = [int]$contract.snapshot_limits.max_files }
  if ($null -ne $contract.snapshot_limits.max_total_mb) { $maxTotalMb = [double]$contract.snapshot_limits.max_total_mb }
  if ($null -ne $contract.snapshot_limits.max_single_file_mb) { $maxSingleMb = [double]$contract.snapshot_limits.max_single_file_mb }
}
$allFiles = @(Get-ChildItem -LiteralPath $rootResolved -Recurse -File -ErrorAction SilentlyContinue)
$totalMb = 0; if ($allFiles.Count -gt 0) { $totalMb = (($allFiles | Measure-Object -Property Length -Sum).Sum) / 1MB }
$bigFiles = @($allFiles | Where-Object { ($_.Length / 1MB) -gt $maxSingleMb })
if ($allFiles.Count -gt $maxFiles) { throw "snapshot_limits: $($allFiles.Count) files > max_files $maxFiles. Narrow SnapshotRoot or raise the limit; refusing partial snapshot." }
if ($totalMb -gt $maxTotalMb) { throw ("snapshot_limits: total {0:N1}MB > max_total_mb {1}. Refusing partial snapshot." -f $totalMb, $maxTotalMb) }
if ($bigFiles.Count -gt 0) { throw "snapshot_limits: $($bigFiles.Count) file(s) > max_single_file_mb $maxSingleMb (e.g. $($bigFiles[0].Name)). Refusing partial snapshot." }

$verDir = Join-Path $SessionPath 'verifier_results'
if (-not (Test-Path -LiteralPath $verDir)) { New-Item -ItemType Directory -Force -Path $verDir | Out-Null }

# ===== RUN 1 =====
$before = Get-Snapshot $rootResolved
$runs1 = Invoke-TestPlan $contract.test_plan
$afterRun = Get-Snapshot $rootResolved
$diff1 = Compare-Snapshot $before $afterRun

# ===== LAYER-1 CLEANUP: delete created files EXCEPT approved keep paths =====
$createdManifest = @()
$approvedRetained = @()
foreach ($rel in $diff1.created) {
  if (Test-Keep $rel) { $approvedRetained += $rel; continue }   # declared artifact: retain, do not delete
  $full = Join-Path $sandboxRoot $rel
  if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue }
  $createdManifest += $rel
}
$afterClean = Get-Snapshot $rootResolved
$diffClean = Compare-Snapshot $before $afterClean
# Zero residue = no UNAPPROVED residue. Approved-retained (keep-list) files do not count.
$unapprovedCreated = @($diffClean.created | Where-Object { -not (Test-Keep $_) })
$fsClean = ($unapprovedCreated.Count -eq 0 -and $diffClean.modified.Count -eq 0 -and $diffClean.removed.Count -eq 0)
$manifestCleanupComplete = ($unapprovedCreated.Count -eq 0)
$diffDetail = "post-cleanup unapproved_created=$($unapprovedCreated.Count) retained=$($approvedRetained.Count) modified=$($diffClean.modified.Count) removed=$($diffClean.removed.Count)"

# ===== RUN 2 (from clean state) =====
$runs2 = Invoke-TestPlan $contract.test_plan
$after2 = Get-Snapshot $rootResolved
$diff2 = Compare-Snapshot $before $after2
foreach ($rel in $diff2.created) { if (Test-Keep $rel) { continue }; $full = Join-Path $sandboxRoot $rel; if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue } }
$after2clean = Get-Snapshot $rootResolved
$diff2clean = Compare-Snapshot $before $after2clean
$unapproved2 = @($diff2clean.created | Where-Object { -not (Test-Keep $_) })
$run2AllPass = (@($runs2 | Where-Object { $_.exit -ne 0 }).Count -eq 0)
$run2Clean = ($unapproved2.Count -eq 0 -and $diff2clean.modified.Count -eq 0 -and $diff2clean.removed.Count -eq 0)
$secondRunPass = ($run2AllPass -and $run2Clean)

# ===== EMIT summary.json =====
$testsExit = 0
$failed = @($runs1 | Where-Object { $_.exit -ne 0 })
if ($failed.Count -gt 0) { $testsExit = ($failed | Select-Object -First 1).exit }
$summary = [pscustomobject]@{
  session_id     = $contract.session_id
  tests_command  = @($contract.test_plan)
  runs           = $runs1
  tests_exit     = $testsExit
  typecheck_exit = $null
  cached         = $false
  freshness      = 'non-cached'
  snapshot_root  = $rootResolved
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $verDir 'summary.json') -Encoding UTF8

# ===== EMIT verifier_residue_report.json =====
$residue = [pscustomobject]@{
  session_id                = $contract.session_id
  manifest_cleanup_complete = $manifestCleanupComplete
  created_manifest          = $createdManifest
  state_surfaces            = @('filesystem')
  snapshots                 = [pscustomobject]@{
    filesystem = [pscustomobject]@{ before = "snapshot:before($($before.Count) files)"; after = "snapshot:after-cleanup($($afterClean.Count) files)"; diff_clean = $fsClean; diff_detail = $diffDetail }
  }
  volatile_paths_ignored    = $volatile
  approved_retained_artifacts = $approvedRetained
  second_run_pass           = $secondRunPass
}
$residue | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $SessionPath 'verifier_residue_report.json') -Encoding UTF8

# ---- report ----
Write-Host ""
Write-Host "NEO_VERIFIER (filesystem-only) - root: $rootResolved"
Write-Host ("Run1 exits: " + (@($runs1 | ForEach-Object { $_.exit }) -join ',') + " | created=$($diff1.created.Count) modified=$($diff1.modified.Count) removed=$($diff1.removed.Count)")
Write-Host ("Residue: manifest_cleanup=$manifestCleanupComplete fs_clean=$fsClean | $diffDetail")
Write-Host ("Second run pass: $secondRunPass")
if ($diff1.modified.Count -gt 0 -or $diff1.removed.Count -gt 0) {
  Write-Host "WARNING: test run modified/removed pre-existing files (cannot auto-restore in v1): mod=[$($diff1.modified -join ',')] rem=[$($diff1.removed -join ',')]" -ForegroundColor Yellow
}
Write-Host ""
$pass = ($testsExit -eq 0 -and $fsClean -and $secondRunPass)
if ($pass) { Write-Host "VERIFIER: PASS (tests exit 0, zero residue, second run clean)" -ForegroundColor Green; exit 0 }
else { Write-Host "VERIFIER: FAIL (tests_exit=$testsExit fs_clean=$fsClean second_run_pass=$secondRunPass)" -ForegroundColor Red; exit 1 }

