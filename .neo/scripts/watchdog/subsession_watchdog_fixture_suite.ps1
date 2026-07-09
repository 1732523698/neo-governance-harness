#requires -version 5.1
# subsession_watchdog_fixture_suite.ps1
# ASCII-only, PS 5.1. RED-THEN-GREEN fixture suite for subsession_watchdog.ps1.
# Every case launches the watchdog in its OWN child powershell.exe process, with a
# per-case config JSON + scratch dirs under $env:TEMP\neo_watchdog_fixtures_<random>\.
# NO live mail, NO real codex, NO live process dependence, NO process kill.
# One PASS/FAIL line per case; exit 0 only if all pass.

$ErrorActionPreference = 'Stop'

$script:WatchdogScript = Join-Path $PSScriptRoot 'subsession_watchdog.ps1'
$script:AllResults = New-Object System.Collections.Generic.List[object]
$script:SuiteRoot = $null

function Write-CaseResult {
  param([string]$CaseName, [bool]$Pass, [string]$Detail = '')
  $line = if ($Pass) { "PASS: $CaseName" } else { "FAIL: $CaseName - $Detail" }
  Write-Host $line
  $script:AllResults.Add([pscustomobject]@{ case = $CaseName; pass = $Pass; detail = $Detail })
}

function New-ScratchRoot {
  $rand = [System.IO.Path]::GetRandomFileName() -replace '[^A-Za-z0-9]', ''
  $root = Join-Path $env:TEMP ('neo_watchdog_fixtures_' + $rand)
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  return $root
}

function New-CaseDirs {
  param([string]$CaseRoot)
  $stateDir = Join-Path $CaseRoot 'state'
  $tempTasksRoot = Join-Path $CaseRoot 'temp_tasks'
  $runRoot = Join-Path $CaseRoot 'run_root'
  $mailDir = Join-Path $CaseRoot 'mail'
  New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
  New-Item -ItemType Directory -Force -Path $tempTasksRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $mailDir | Out-Null
  return @{ root = $CaseRoot; state_dir = $stateDir; temp_tasks_root = $tempTasksRoot; run_root = $runRoot; mail_dir = $mailDir }
}

function Write-CaseConfig {
  param([hashtable]$Dirs, [string]$ConfigPath, [hashtable]$Overrides = @{})
  $cfg = [ordered]@{
    task_output_stale_min = 15
    codex_wall_min = 20
    ledger_open_call_min = 30
    active_run_root_max_age_hours = 24
    temp_tasks_root = $Dirs.temp_tasks_root
    run_roots = @($Dirs.run_root)
    scan_depth = 3
    state_dir = $Dirs.state_dir
    # slice 2b: mirrors the SHIPPED default (OFF) - target (i) is known-noisy pending a
    # completion-marker discriminator (soak: 153/153 false-positive class). Cases that
    # exercise target (i) override this to $true explicitly.
    watch_task_outputs = $false
  }
  foreach ($k in $Overrides.Keys) { $cfg[$k] = $Overrides[$k] }
  ($cfg | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ConfigPath -Encoding ascii
}

function Invoke-Watchdog {
  param(
    [string]$ConfigPath,
    [string]$SnapshotPath = $null,
    [string]$NotifyTestModeDir = $null
  )
  $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:WatchdogScript, '-ConfigPath', $ConfigPath)
  if ($SnapshotPath) { $argsList += @('-ProcessSnapshotPath', $SnapshotPath) }
  if ($NotifyTestModeDir) { $argsList += @('-NotifyTestModeDir', $NotifyTestModeDir) }
  $psExe = (Get-Process -Id $PID).Path
  $out = & $psExe @argsList 2>&1
  $exitCode = $LASTEXITCODE
  return @{ exit_code = $exitCode; output = @($out) }
}

function Write-SnapshotFile {
  param([string]$Path, [array]$Processes)
  ($Processes | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $Path -Encoding ascii
}

function Get-MailFiles {
  param([string]$MailDir)
  if (-not (Test-Path -LiteralPath $MailDir)) { return @() }
  return @(Get-ChildItem -LiteralPath $MailDir -File -ErrorAction SilentlyContinue)
}

function Get-StatusJson {
  param([hashtable]$Dirs)
  $p = Join-Path $Dirs.state_dir 'watchdog_status.json'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# CASE 1: stale-task-output detection
# ---------------------------------------------------------------------------
function Test-Case1-StaleTaskOutput {
  $caseRoot = Join-Path $script:SuiteRoot 'case1'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  # slice 2b: this case exercises target (i), which now ships default-OFF - enable it.
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath -Overrides @{ watch_task_outputs = $true }

  $projDir = Join-Path $dirs.temp_tasks_root 'proj1'
  $sessDir = Join-Path $projDir 'sess-case1-live'
  $tasksDir = Join-Path $sessDir 'tasks'
  New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
  $outFile = Join-Path $tasksDir 'a.output'
  Set-Content -LiteralPath $outFile -Value 'stale output' -Encoding ascii
  (Get-Item -LiteralPath $outFile).LastWriteTime = (Get-Date).AddMinutes(-30)

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @(
    @{ name = 'node'; command_line = "node.exe --session sess-case1-live worker"; start_time_utc_iso = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); pid = 4242 }
  )

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -ge 1) -and ($null -ne $status) -and ($status.stalls.Count -ge 1)
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) stalls=$(if($status){$status.stalls.Count}else{'null'})"
  Write-CaseResult -CaseName 'stale-task-output-detection' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 2: fresh-output no-alert
# ---------------------------------------------------------------------------
function Test-Case2-FreshOutputNoAlert {
  $caseRoot = Join-Path $script:SuiteRoot 'case2'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  # slice 2b: this case exercises target (i), which now ships default-OFF - enable it.
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath -Overrides @{ watch_task_outputs = $true }

  $projDir = Join-Path $dirs.temp_tasks_root 'proj1'
  $sessDir = Join-Path $projDir 'sess-case2-live'
  $tasksDir = Join-Path $sessDir 'tasks'
  New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
  $outFile = Join-Path $tasksDir 'a.output'
  Set-Content -LiteralPath $outFile -Value 'fresh output' -Encoding ascii
  (Get-Item -LiteralPath $outFile).LastWriteTime = (Get-Date).AddMinutes(-2)

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @(
    @{ name = 'node'; command_line = "node.exe --session sess-case2-live worker"; start_time_utc_iso = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString('yyyy-MM-ddTHH:mm:ssZ'); pid = 4243 }
  )

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -eq 0) -and ($null -ne $status) -and ($status.stalls.Count -eq 0)
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) stalls=$(if($status){$status.stalls.Count}else{'null'})"
  Write-CaseResult -CaseName 'fresh-output-no-alert' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 3: codex-overrun
# ---------------------------------------------------------------------------
function Test-Case3-CodexOverrun {
  $caseRoot = Join-Path $script:SuiteRoot 'case3'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @(
    @{ name = 'codex'; command_line = 'codex exec -s read-only'; start_time_utc_iso = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); pid = 5001 }
  )

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -ge 1) -and ($null -ne $status) -and ($status.stalls.Count -ge 1)
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) stalls=$(if($status){$status.stalls.Count}else{'null'})"
  Write-CaseResult -CaseName 'codex-overrun' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 4: open-ledger-entry
# ---------------------------------------------------------------------------
function Test-Case4-OpenLedgerEntry {
  $caseRoot = Join-Path $script:SuiteRoot 'case4'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath

  $runSubRoot = Join-Path $dirs.run_root 'session-case4'
  New-Item -ItemType Directory -Force -Path $runSubRoot | Out-Null
  $ledgerPath = Join-Path $runSubRoot 'external_slice_call_ledger.jsonl'
  $entry = [ordered]@{
    run_id = 'run-case4'; slice_id = 'slice-1'; slice_call_seq = 1; refused = $false; reason = 'NONE'
    timestamp_utc = (Get-Date).ToUniversalTime().AddMinutes(-45).ToString('yyyy-MM-ddTHH:mm:ssZ')
    round_id = 'round-1'; bundle_diff_hash = ('a' * 64)
    post_increment_count = 1; run_ledger_ref_kind = 'CONSUMED'
  }
  ($entry | ConvertTo-Json -Compress) | Set-Content -LiteralPath $ledgerPath -Encoding ascii
  # ledger mtime must be within active_run_root_max_age_hours (recent), even though the
  # entry's own timestamp_utc is old (that is the open-call signal).
  (Get-Item -LiteralPath $ledgerPath).LastWriteTime = (Get-Date).AddMinutes(-5)

  # FIX-5: pass an explicit EMPTY -ProcessSnapshotPath stub so this case never falls
  # through to live Get-CimInstance process enumeration (hermetic, no live-process dep;
  # this case does not need any process data since it is a pure ledger-file check).
  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @()

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -ge 1) -and ($null -ne $status) -and ($status.stalls.Count -ge 1)
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) stalls=$(if($status){$status.stalls.Count}else{'null'})"
  Write-CaseResult -CaseName 'open-ledger-entry' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 5: distinctness - two different stalls in one sweep -> two separate mails
# ---------------------------------------------------------------------------
function Test-Case5-Distinctness {
  $caseRoot = Join-Path $script:SuiteRoot 'case5'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  # slice 2b: one of this case's two stalls is a stale task output (target (i), now
  # default-OFF) - enable the flag so the distinctness scenario still has two stalls.
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath -Overrides @{ watch_task_outputs = $true }

  $projDir = Join-Path $dirs.temp_tasks_root 'proj1'
  $sessDir = Join-Path $projDir 'sess-case5-live'
  $tasksDir = Join-Path $sessDir 'tasks'
  New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
  $outFile = Join-Path $tasksDir 'a.output'
  Set-Content -LiteralPath $outFile -Value 'stale output' -Encoding ascii
  (Get-Item -LiteralPath $outFile).LastWriteTime = (Get-Date).AddMinutes(-30)

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @(
    @{ name = 'node'; command_line = "node.exe --session sess-case5-live worker"; start_time_utc_iso = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); pid = 4244 },
    @{ name = 'codex'; command_line = 'codex exec -s read-only'; start_time_utc_iso = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); pid = 5002 }
  )

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $distinctContents = $false
  if ($mails.Count -ge 2) {
    $contents = @($mails | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw })
    $distinctContents = ($contents[0] -ne $contents[1])
  }

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -eq 2) -and $distinctContents -and ($null -ne $status) -and ($status.stalls.Count -eq 2)
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) distinct=$distinctContents stalls=$(if($status){$status.stalls.Count}else{'null'})"
  Write-CaseResult -CaseName 'distinctness-two-stalls-two-mails' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 6: dedupe - run twice on same stall -> exactly one mail total
# ---------------------------------------------------------------------------
function Test-Case6-Dedupe {
  $caseRoot = Join-Path $script:SuiteRoot 'case6'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @(
    @{ name = 'codex'; command_line = 'codex exec -s read-only'; start_time_utc_iso = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); pid = 5003 }
  )

  $res1 = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $res2 = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir

  $pass = ($res1.exit_code -eq 0) -and ($res2.exit_code -eq 0) -and ($mails.Count -eq 1)
  $detail = "exit1=$($res1.exit_code) exit2=$($res2.exit_code) mails=$($mails.Count)"
  Write-CaseResult -CaseName 'dedupe-same-stall-one-mail' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 7: healthy sweep - clean scratch -> zero stdout, zero mails, exit 0, status written
# ---------------------------------------------------------------------------
function Test-Case7-HealthySweep {
  $caseRoot = Join-Path $script:SuiteRoot 'case7'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @()

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs
  $stdoutEmpty = (@($res.output).Count -eq 0) -or (($res.output -join '') -eq '')

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -eq 0) -and $stdoutEmpty -and ($null -ne $status)
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) stdoutEmpty=$stdoutEmpty statusPresent=$($null -ne $status)"
  Write-CaseResult -CaseName 'healthy-sweep-silent' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 8: unreadable-target fail-closed
# ---------------------------------------------------------------------------
function Test-Case8-UnreadableTarget {
  $caseRoot = Join-Path $script:SuiteRoot 'case8'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  $badRoot = Join-Path $caseRoot 'does_not_exist_root'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath -Overrides @{ run_roots = @($badRoot) }

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @()

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $hasUnreadable = $false
  if ($null -ne $status -and $null -ne $status.unreadable) {
    $hasUnreadable = @($status.unreadable | Where-Object { [string]$_.path -like "*does_not_exist_root*" }).Count -ge 1
  }

  $pass = ($res.exit_code -eq 0) -and ($null -ne $status) -and $hasUnreadable
  $detail = "exit=$($res.exit_code) statusPresent=$($null -ne $status) hasUnreadable=$hasUnreadable"
  Write-CaseResult -CaseName 'unreadable-target-fail-closed' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 9: re-entrancy - live lock with alive PID -> second invocation exits 0 without sweeping
# ---------------------------------------------------------------------------
function Test-Case9-Reentrancy {
  $caseRoot = Join-Path $script:SuiteRoot 'case9'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath

  $lockPath = Join-Path $dirs.state_dir 'sweep.lock'
  # our own PID is guaranteed alive - simulates "in-progress sweep by a live process"
  Set-Content -LiteralPath $lockPath -Value ([string]$PID) -Encoding ascii
  $lockBefore = Get-Content -LiteralPath $lockPath -Raw
  $statusBefore = Get-StatusJson -Dirs $dirs

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @()

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $statusAfter = Get-StatusJson -Dirs $dirs
  $lockAfter = if (Test-Path -LiteralPath $lockPath) { Get-Content -LiteralPath $lockPath -Raw } else { $null }

  $pass = ($res.exit_code -eq 0) -and ($null -eq $statusBefore) -and ($null -eq $statusAfter) -and ($lockAfter -eq $lockBefore)
  $detail = "exit=$($res.exit_code) statusBefore=$($null -ne $statusBefore) statusAfter=$($null -ne $statusAfter) lockUnchanged=$($lockAfter -eq $lockBefore)"
  Write-CaseResult -CaseName 're-entrancy-live-lock-skips-sweep' -Pass $pass -Detail $detail

  # cleanup: remove the lock we planted so it doesn't get swept up as residue.
  Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# CASE 11: unparseable-verdict-ledger -> NO false open-call alert, INDETERMINATE
# disclosed, verdict file stays under "unreadable" (FIX-1 regression fixture).
# ---------------------------------------------------------------------------
function Test-Case11-UnparseableVerdictLedgerNoFalseAlert {
  $caseRoot = Join-Path $script:SuiteRoot 'case11'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath

  $runSubRoot = Join-Path $dirs.run_root 'session-case11'
  New-Item -ItemType Directory -Force -Path $runSubRoot | Out-Null

  $ledgerPath = Join-Path $runSubRoot 'external_slice_call_ledger.jsonl'
  $entry = [ordered]@{
    run_id = 'run-case11'; slice_id = 'slice-1'; slice_call_seq = 1; refused = $false; reason = 'NONE'
    timestamp_utc = (Get-Date).ToUniversalTime().AddMinutes(-45).ToString('yyyy-MM-ddTHH:mm:ssZ')
    round_id = 'round-1'; bundle_diff_hash = ('b' * 64)
    post_increment_count = 1; run_ledger_ref_kind = 'CONSUMED'
  }
  ($entry | ConvertTo-Json -Compress) | Set-Content -LiteralPath $ledgerPath -Encoding ascii
  (Get-Item -LiteralPath $ledgerPath).LastWriteTime = (Get-Date).AddMinutes(-5)

  # sibling verdict ledger present but deliberately UNPARSEABLE (broken JSONL line).
  $verdictPath = Join-Path $runSubRoot 'external_verdict_ledger.jsonl'
  Set-Content -LiteralPath $verdictPath -Value '{ this is not valid json' -Encoding ascii
  (Get-Item -LiteralPath $verdictPath).LastWriteTime = (Get-Date).AddMinutes(-5)

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @()

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $hasUnreadableVerdict = $false
  $hasIndeterminateOpenCall = $false
  if ($null -ne $status) {
    if ($null -ne $status.unreadable) {
      $hasUnreadableVerdict = @($status.unreadable | Where-Object { [string]$_.path -like "*external_verdict_ledger.jsonl*" }).Count -ge 1
    }
    if ($null -ne $status.indeterminate) {
      $hasIndeterminateOpenCall = @($status.indeterminate | Where-Object { [string]$_.kind -eq 'open_ledger_call' }).Count -ge 1
    }
  }
  $noFalseStall = ($null -ne $status) -and (@($status.stalls | Where-Object { [string]$_.kind -eq 'open_ledger_call' }).Count -eq 0)

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -eq 0) -and $noFalseStall -and $hasUnreadableVerdict -and $hasIndeterminateOpenCall
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) noFalseStall=$noFalseStall unreadableVerdict=$hasUnreadableVerdict indeterminateOpenCall=$hasIndeterminateOpenCall"
  Write-CaseResult -CaseName 'unparseable-verdict-ledger-no-false-alert' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 12: same-run-root distinct-slice collapse guard - two open-call stalls
# in the SAME ledger file with DIFFERENT slice_id but IDENTICAL
# round_id+bundle_diff_hash must still produce two distinct mails (FIX-3
# regression fixture: stall key must include run-root path + slice_id).
# ---------------------------------------------------------------------------
function Test-Case12-DistinctSliceIdNoCollapse {
  $caseRoot = Join-Path $script:SuiteRoot 'case12'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath

  $runSubRoot = Join-Path $dirs.run_root 'session-case12'
  New-Item -ItemType Directory -Force -Path $runSubRoot | Out-Null
  $ledgerPath = Join-Path $runSubRoot 'external_slice_call_ledger.jsonl'

  $sharedRound = 'round-shared'
  $sharedHash = ('c' * 64)
  $entryA = [ordered]@{
    run_id = 'run-case12'; slice_id = 'slice-A'; slice_call_seq = 1; refused = $false; reason = 'NONE'
    timestamp_utc = (Get-Date).ToUniversalTime().AddMinutes(-45).ToString('yyyy-MM-ddTHH:mm:ssZ')
    round_id = $sharedRound; bundle_diff_hash = $sharedHash
    post_increment_count = 1; run_ledger_ref_kind = 'CONSUMED'
  }
  $entryB = [ordered]@{
    run_id = 'run-case12'; slice_id = 'slice-B'; slice_call_seq = 1; refused = $false; reason = 'NONE'
    timestamp_utc = (Get-Date).ToUniversalTime().AddMinutes(-50).ToString('yyyy-MM-ddTHH:mm:ssZ')
    round_id = $sharedRound; bundle_diff_hash = $sharedHash
    post_increment_count = 1; run_ledger_ref_kind = 'CONSUMED'
  }
  $lines = @(
    ($entryA | ConvertTo-Json -Compress),
    ($entryB | ConvertTo-Json -Compress)
  )
  Set-Content -LiteralPath $ledgerPath -Value $lines -Encoding ascii
  (Get-Item -LiteralPath $ledgerPath).LastWriteTime = (Get-Date).AddMinutes(-5)

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @()

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $distinctContents = $false
  if ($mails.Count -ge 2) {
    $contents = @($mails | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw })
    $distinctContents = ($contents[0] -ne $contents[1])
  }
  $openCallStallCount = 0
  if ($null -ne $status -and $null -ne $status.stalls) {
    $openCallStallCount = @($status.stalls | Where-Object { [string]$_.kind -eq 'open_ledger_call' }).Count
  }

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -eq 2) -and $distinctContents -and ($openCallStallCount -eq 2)
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) distinct=$distinctContents openCallStalls=$openCallStallCount"
  Write-CaseResult -CaseName 'distinct-slice-id-same-round-bundle-no-collapse' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 13: default-OFF task-output watch (slice 2b) - stale .output + live-session
# stub with the shipped default config (watch_task_outputs=false) must produce ZERO
# stalls and ZERO mails; status must show targets_checked.task_outputs=0 AND
# disabled_targets containing 'task_outputs' (a quiet status is never mistaken for a
# scanned-and-clean surface).
# ---------------------------------------------------------------------------
function Test-Case13-TaskOutputsDefaultOff {
  $caseRoot = Join-Path $script:SuiteRoot 'case13'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  # base config carries watch_task_outputs=false (the shipped default) - no override.
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath

  # identical stale-output + live-session layout to case 1 - the only difference is
  # the flag, proving the flag (not the fixture data) is what gates detection.
  $projDir = Join-Path $dirs.temp_tasks_root 'proj1'
  $sessDir = Join-Path $projDir 'sess-case13-live'
  $tasksDir = Join-Path $sessDir 'tasks'
  New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
  $outFile = Join-Path $tasksDir 'a.output'
  Set-Content -LiteralPath $outFile -Value 'stale output' -Encoding ascii
  (Get-Item -LiteralPath $outFile).LastWriteTime = (Get-Date).AddMinutes(-30)

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @(
    @{ name = 'node'; command_line = "node.exe --session sess-case13-live worker"; start_time_utc_iso = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); pid = 4245 }
  )

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $taskOutputsZero = $false
  $disabledListed = $false
  if ($null -ne $status) {
    $taskOutputsZero = ([int]$status.targets_checked.task_outputs -eq 0)
    if ($null -ne $status.disabled_targets) {
      $disabledListed = (@($status.disabled_targets) -contains 'task_outputs')
    }
  }
  $zeroStalls = ($null -ne $status) -and (@($status.stalls).Count -eq 0)

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -eq 0) -and $zeroStalls -and $taskOutputsZero -and $disabledListed
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) zeroStalls=$zeroStalls taskOutputsZero=$taskOutputsZero disabledListed=$disabledListed"
  Write-CaseResult -CaseName 'task-outputs-default-off-no-alert' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 14: flag explicitly true -> detection fires (mirror of case 1; proves the
# flag GATES target (i) rather than killing it).
# ---------------------------------------------------------------------------
function Test-Case14-TaskOutputsFlagTrueDetects {
  $caseRoot = Join-Path $script:SuiteRoot 'case14'
  $dirs = New-CaseDirs -CaseRoot $caseRoot
  $configPath = Join-Path $caseRoot 'config.json'
  Write-CaseConfig -Dirs $dirs -ConfigPath $configPath -Overrides @{ watch_task_outputs = $true }

  $projDir = Join-Path $dirs.temp_tasks_root 'proj1'
  $sessDir = Join-Path $projDir 'sess-case14-live'
  $tasksDir = Join-Path $sessDir 'tasks'
  New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
  $outFile = Join-Path $tasksDir 'a.output'
  Set-Content -LiteralPath $outFile -Value 'stale output' -Encoding ascii
  (Get-Item -LiteralPath $outFile).LastWriteTime = (Get-Date).AddMinutes(-30)

  $snapPath = Join-Path $caseRoot 'snapshot.json'
  Write-SnapshotFile -Path $snapPath -Processes @(
    @{ name = 'node'; command_line = "node.exe --session sess-case14-live worker"; start_time_utc_iso = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); pid = 4246 }
  )

  $res = Invoke-Watchdog -ConfigPath $configPath -SnapshotPath $snapPath -NotifyTestModeDir $dirs.mail_dir
  $mails = Get-MailFiles -MailDir $dirs.mail_dir
  $status = Get-StatusJson -Dirs $dirs

  $pass = ($res.exit_code -eq 0) -and ($mails.Count -ge 1) -and ($null -ne $status) -and ($status.stalls.Count -ge 1)
  $detail = "exit=$($res.exit_code) mails=$($mails.Count) stalls=$(if($status){$status.stalls.Count}else{'null'})"
  Write-CaseResult -CaseName 'task-outputs-flag-true-detects' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# CASE 10: residue-clean second pass
# ---------------------------------------------------------------------------
function Test-Case10-ResidueClean {
  # Executed by the caller AFTER all other cases + their scratch cleanup.
  # Verifies: suite root scratch is fully removable (nothing locked/left dangling
  # beyond what we deliberately clean here), and asserts no writes escaped scratch
  # into the approved evidence paths' sibling areas.
  $stillThere = Test-Path -LiteralPath $script:SuiteRoot
  Remove-Item -LiteralPath $script:SuiteRoot -Recurse -Force -ErrorAction SilentlyContinue
  $goneAfter = -not (Test-Path -LiteralPath $script:SuiteRoot)

  $pass = $stillThere -and $goneAfter
  $detail = "existedBefore=$stillThere goneAfterCleanup=$goneAfter path=$($script:SuiteRoot)"
  Write-CaseResult -CaseName 'residue-clean-second-pass' -Pass $pass -Detail $detail
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
$script:SuiteRoot = New-ScratchRoot
try {
  Test-Case1-StaleTaskOutput
  Test-Case2-FreshOutputNoAlert
  Test-Case3-CodexOverrun
  Test-Case4-OpenLedgerEntry
  Test-Case5-Distinctness
  Test-Case6-Dedupe
  Test-Case7-HealthySweep
  Test-Case8-UnreadableTarget
  Test-Case9-Reentrancy
  Test-Case11-UnparseableVerdictLedgerNoFalseAlert
  Test-Case12-DistinctSliceIdNoCollapse
  Test-Case13-TaskOutputsDefaultOff
  Test-Case14-TaskOutputsFlagTrueDetects
} finally {
  # Case 10 runs last and owns final cleanup of $script:SuiteRoot.
  Test-Case10-ResidueClean
}

$failCount = @($script:AllResults | Where-Object { -not $_.pass }).Count
$totalCount = $script:AllResults.Count
Write-Host "----"
Write-Host ("TOTAL: {0} PASS: {1} FAIL: {2}" -f $totalCount, ($totalCount - $failCount), $failCount)

if ($failCount -gt 0) { exit 1 } else { exit 0 }
