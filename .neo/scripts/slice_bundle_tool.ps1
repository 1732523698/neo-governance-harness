# slice_bundle_tool.ps1 - NEO 3.1 (P1-S1, RT4-R2) additive bundle ergonomics tool.
# ASCII-only, PowerShell 5.1. EDITS NO ENGINE LOGIC; it scaffolds and pre-lints slice bundles so a
# builder can fix shape problems BEFORE running the authoritative verify_app_slice.ps1 net. This tool
# is advisory: it never replaces or relaxes the AS-net or check_app_end_evidence.ps1.
#
# Actions:
#   scaffold     -SliceDir <dir> [-DeclaredTier RTn] [-Force]
#                Emits a correct slice-bundle skeleton: CHANGED_FILES.txt, SLICE_DECLARATION.txt,
#                HEAD_SHA.txt (documented: change TIP sha, not baseline), command_evidence.json
#                (right name/cmd/cwd/exit_code/timestamp/output_path/status fields), CUSTOM_CHECKS.md
#                (^name: PASS shape), HUMAN_ACCEPTANCE.md, ROLLBACK_PROOF.md, DEP_GUARD.md, SMOKE.md.
#   dry-run      -SliceDir <dir> [-AppRoot <dir>]
#                Pre-net linter: reports AS7 / AS11 / AS13 / AS15-shaped problems. Exit 1 if any.
#   ascii-guard  -Path <file-or-dir>[,<...>]
#                Fails (exit 1) on any non-ASCII byte in *.sql / *.ps1 under the given paths.
#
# Exit 0 only when the requested action finds no problem.

param(
  [ValidateSet('scaffold','dry-run','ascii-guard')][string]$Action = 'dry-run',
  [string]$SliceDir = '',
  [string]$AppRoot = '',
  [string[]]$Path = @(),
  [ValidateSet('RT1','RT2','RT3','RT4')][string]$DeclaredTier = 'RT3',
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
$problems = New-Object System.Collections.ArrayList
$notes    = New-Object System.Collections.ArrayList
function Add-Problem([string]$id,[string]$m){ [void]$problems.Add("[$id] $m") }
# advisory: reported but NON-gating (dry-run cannot see the profile's risk tokens, so it cannot
# decide whether human acceptance is actually REQUIRED - it surfaces the consideration instead).
function Add-Note([string]$id,[string]$m){ [void]$notes.Add("[$id NOTE] $m") }

# ---- ASCII guard helper (shared) -------------------------------------------------------------
function Test-FileAscii([string]$file){
  $bytes = [System.IO.File]::ReadAllBytes($file)
  foreach($b in $bytes){ if($b -gt 127){ return $false } }
  return $true
}
function Get-GuardTargets([string[]]$paths){
  $targets = @()
  foreach($p in $paths){
    if([string]::IsNullOrWhiteSpace($p)){ continue }
    if(Test-Path -LiteralPath $p -PathType Container){
      $targets += Get-ChildItem -LiteralPath $p -Recurse -File | Where-Object { $_.Extension -in @('.sql','.ps1') } | ForEach-Object { $_.FullName }
    } elseif(Test-Path -LiteralPath $p -PathType Leaf){
      if(([System.IO.Path]::GetExtension($p)) -in @('.sql','.ps1')){ $targets += (Resolve-Path -LiteralPath $p).Path }
    }
  }
  return ,@($targets)
}
function Invoke-AsciiGuard([string[]]$paths){
  $targets = Get-GuardTargets $paths
  $viol = @()
  foreach($t in $targets){ if(-not (Test-FileAscii $t)){ $viol += $t } }
  return @{ checked=$targets.Count; violations=$viol }
}

# ============================================================ ACTION: ascii-guard
if($Action -eq 'ascii-guard'){
  if($Path.Count -eq 0){ Write-Host 'FATAL: ascii-guard requires -Path'; exit 2 }
  $g = Invoke-AsciiGuard $Path
  if($g.violations.Count -gt 0){
    foreach($v in $g.violations){ Write-Host "[AS7 FAIL] non-ASCII bytes in $v" }
    Write-Host "ascii-guard: RED - $($g.violations.Count) of $($g.checked) *.sql/*.ps1 file(s) contain non-ASCII"
    exit 1
  }
  Write-Host "ascii-guard: GREEN - $($g.checked) *.sql/*.ps1 file(s) are ASCII-only"
  exit 0
}

# ============================================================ ACTION: scaffold
if($Action -eq 'scaffold'){
  if(-not $SliceDir){ Write-Host 'FATAL: scaffold requires -SliceDir'; exit 2 }
  if((Test-Path -LiteralPath $SliceDir) -and -not $Force){
    if(@(Get-ChildItem -LiteralPath $SliceDir -Force).Count -gt 0){ Write-Host "FATAL: $SliceDir is not empty (use -Force to scaffold into it)"; exit 2 }
  }
  New-Item -ItemType Directory -Force -Path $SliceDir | Out-Null
  $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  function W([string]$leaf,[string]$body){ Set-Content -LiteralPath (Join-Path $SliceDir $leaf) -Value $body -Encoding ascii }
  W 'CHANGED_FILES.txt' "# one path per line, relative to AppRoot. Prefix deletions with DELETED:"
  W 'SLICE_DECLARATION.txt' ("DECLARED_TIER: $DeclaredTier`r`nFAST_LANE: no")
  W 'HEAD_SHA.txt' "# Put the change TIP commit sha here (the commit that CONTAINS the change), NOT the parent/baseline."
  $cmdSkeleton = @(
    [ordered]@{ name='typecheck'; cmd='npm run typecheck'; cwd='frontend'; exit_code=0; timestamp=$ts; output_path='typecheck.log'; status='pass' }
  )
  ($cmdSkeleton | ConvertTo-Json) | Out-File -LiteralPath (Join-Path $SliceDir 'command_evidence.json') -Encoding ascii
  W 'CUSTOM_CHECKS.md' "# one per line in the '<check_name>: PASS' shape the net (AS15/E5) expects`r`nexample_custom_check: PASS (replace with the profile's required checks)"
  W 'HUMAN_ACCEPTANCE.md' "# Required when auth/financial tokens are touched (AS11/AS14). Record explicit human sign-off lines here, e.g.:`r`n# CLIENT_DEGRADED_ACCEPTED: <who> reviewed <what>"
  W 'ROLLBACK_PROOF.md' "# Required when the slice contains a migration / DDL (AS10). Describe the tested rollback path."
  W 'DEP_GUARD.md' "# Required when dependency/lockfile files change (AS9). Rationale + license/security + rollback plan."
  W 'SMOKE.md' "RESULT: pass`r`nEVIDENCE: <link or path to the smoke evidence>"
  Write-Host "scaffold: wrote slice-bundle skeleton to $SliceDir (tier=$DeclaredTier)"
  exit 0
}

# ============================================================ ACTION: dry-run (pre-net linter)
if(-not $SliceDir){ Write-Host 'FATAL: dry-run requires -SliceDir'; exit 2 }
if(-not (Test-Path -LiteralPath $SliceDir)){ Write-Host "FATAL: SliceDir not found: $SliceDir"; exit 2 }

# ---- AS13: command_evidence shape + self-claim consistency ----
$cmdPath = Join-Path $SliceDir 'command_evidence.json'
if(-not (Test-Path -LiteralPath $cmdPath)){
  Add-Problem 'AS13' 'command_evidence.json missing'
} else {
  $cmdEntries = $null
  try { $cmdEntries = @(Get-Content -LiteralPath $cmdPath -Raw | ConvertFrom-Json) } catch { Add-Problem 'AS13' "command_evidence.json is not valid JSON: $($_.Exception.Message)" }
  if($null -ne $cmdEntries){
    foreach($e in $cmdEntries){
      foreach($field in @('name','cmd','cwd','exit_code','timestamp','output_path','status')){
        if($null -eq $e.PSObject.Properties[$field]){ Add-Problem 'AS13' "command entry '$($e.name)' missing field '$field'" }
      }
      if($e.status -eq 'pass' -and $e.exit_code -ne 0){ Add-Problem 'AS13' "entry '$($e.name)' claims pass but exit_code=$($e.exit_code)" }
      if($e.output_path){
        $op = $e.output_path
        if(-not (Test-Path -LiteralPath $op)){ if(-not (Test-Path -LiteralPath (Join-Path $SliceDir $op))){ Add-Problem 'AS13' "entry '$($e.name)' output artifact not found: $op" } }
      }
    }
  }
}

# ---- AS15: CUSTOM_CHECKS.md shape (^<name>: PASS) ----
$ccPath = Join-Path $SliceDir 'CUSTOM_CHECKS.md'
if(Test-Path -LiteralPath $ccPath){
  $i = 0
  foreach($line in (Get-Content -LiteralPath $ccPath)){
    $i++
    $t = $line.Trim()
    if($t -eq '' -or $t.StartsWith('#')){ continue }
    if($t -notmatch '^[^:]+:\s*PASS'){ Add-Problem 'AS15' "CUSTOM_CHECKS.md line $i not in '<name>: PASS' shape: '$t'" }
  }
} else {
  Add-Problem 'AS15' 'CUSTOM_CHECKS.md missing (profile custom checks would have no evidence)'
}

# ---- AS11: HUMAN_ACCEPTANCE.md present and non-empty (advisory - gating belongs to the net, which
# alone knows the profile's auth/fin tokens) ----
$haPath = Join-Path $SliceDir 'HUMAN_ACCEPTANCE.md'
if(Test-Path -LiteralPath $haPath){
  $haReal = @(Get-Content -LiteralPath $haPath | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') })
  if($haReal.Count -eq 0){ Add-Note 'AS11' 'HUMAN_ACCEPTANCE.md has no acceptance lines yet (only template/comments); if this slice touches auth/financial tokens it will FAIL AS11/AS14 at the net' }
} else {
  Add-Note 'AS11' 'no HUMAN_ACCEPTANCE.md; required only if the slice touches auth/financial/degraded-client surfaces'
}

# ---- AS7: charset (ASCII) over *.sql/*.ps1 in the bundle and (if given) the changed app files ----
$guardPaths = @($SliceDir)
if($AppRoot -and (Test-Path -LiteralPath $AppRoot)){
  $cfPath = Join-Path $SliceDir 'CHANGED_FILES.txt'
  if(Test-Path -LiteralPath $cfPath){
    foreach($cf in (Get-Content -LiteralPath $cfPath | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') -and $_ -notlike 'DELETED:*' })){
      $abs = Join-Path $AppRoot ($cf.Trim() -replace '/','\')
      if(Test-Path -LiteralPath $abs){ $guardPaths += $abs }
    }
  }
}
$g = Invoke-AsciiGuard $guardPaths
foreach($v in $g.violations){ Add-Problem 'AS7' "non-ASCII bytes in $v" }

# ---- report ----
Write-Host "slice_bundle_tool dry-run: $SliceDir"
foreach($n in $notes){ Write-Host "  $n" }
if($problems.Count -gt 0){
  foreach($p in $problems){ Write-Host "  $p" }
  Write-Host "dry-run: RED - $($problems.Count) bundle problem(s) found BEFORE the net. Fix these, then run verify_app_slice.ps1."
  exit 1
}
Write-Host "dry-run: GREEN - bundle shape OK for AS7/AS13/AS15 ($($notes.Count) AS11 advisory note(s); run verify_app_slice.ps1 for the authoritative net)"
exit 0
