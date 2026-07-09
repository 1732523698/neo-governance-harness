#requires -version 5.1
# subsession_watchdog.ps1
# NEO auto-hardening-watchdog-2026-07-08, slice 2: the silent sub-session stall
# WATCHDOG - a NEW out-of-band monitor. ASCII-only. PS 5.1 compatible.
#
# READ-ONLY vs every watched surface: mtime/existence/process-metadata only, plus the
# two ledger jsonl kinds (external_slice_call_ledger.jsonl / external_call_ledger.jsonl),
# which are content-read because they are append-only accounting logs, not credentials.
# NEVER kills a process. NEVER runs a real codex call. NEVER sends live mail from the
# suite (the -NotifyTestModeDir seam covers that; governed callers never pass test seams).
#
# LEDGER SEMANTICS GROUNDING (read-only, done before writing this file):
#   - .neo\schema\external_slice_call_entry.schema.json (neo:external_slice_call_entry,
#     home <RunRoot>/external_slice_call_ledger.jsonl): fields include round_id,
#     bundle_diff_hash, refused, reason, post_increment_count, run_ledger_ref_kind,
#     timestamp_utc. A "consumed" (non-refused) entry has refused=false, reason=NONE,
#     run_ledger_ref_kind=CONSUMED.
#   - .neo\schema\attempt_ledger_entry.schema.json (neo:attempt_ledger_entry, home BOTH
#     <RunRoot>/attempt_ledger.jsonl [kind initial|fix] AND
#     <RunRoot>/external_call_ledger.jsonl [kind external_call, reserved slice_id
#     '__run__']): fields are run_id/slice_id/seq/round/kind/timestamp_utc/refused/reason
#     only - NO round_id/bundle_diff_hash/post_increment_count on this shape.
#   - .neo\schema\external_audit_verdict.schema.json (neo:external_audit_verdict, home
#     <RunRoot>/external_verdict_ledger.jsonl): "ONE line per LAUNCHED external call that
#     yielded a parseable, model-pinned verdict"; keyed by run_id/slice_id/round_id/
#     bundle_diff_hash.
#   - orch_supervisor.ps1 Add-NeoRunExternalCallEntry (~line 878) and orch_external.ps1
#     Add-NeoExternalSliceCallEntry (~line 166) / the write-ahead call sequence (~line
#     612-692): EVERY ledger append across BOTH files is a SINGLE write-ahead JSONL line,
#     appended BEFORE the external process launches, with refused/reason ALREADY DECIDED
#     synchronously (cap arithmetic, not an async result). There is NO separate "call
#     started" then "call completed" pair of lines in either ledger schema - a call's
#     completion (parsed verdict) is recorded ONLY as a SEPARATE, later append to
#     external_verdict_ledger.jsonl (a different file/schema the slot-seam never reads).
#
#   CONCLUSION (the packet's "started but never completed" language assumed a two-phase
#   record within one ledger; that pair does not literally exist on disk). The most
#   conservative, still-correct heuristic given what is actually grounded: treat a
#   "consumed" entry in external_slice_call_ledger.jsonl (refused=false, reason=NONE,
#   run_ledger_ref_kind=CONSUMED - i.e., a call that WAS launched) as an OPEN CALL if its
#   own timestamp_utc is older than ledger_open_call_min AND no external_verdict_ledger.jsonl
#   entry with the SAME join key exists alongside it (same run root).
#   This is a cross-ledger join, not a single-line status field; documented here and in the
#   coder report as the grounded, conservative detection rule. FLAGGED as an ambiguity
#   resolved conservatively (see coder_report_slice2.json).
#
#   FINAL JOIN KEY (FIX-2, round 2 - re-grounded directly against the schema files):
#   both .neo\schema\external_slice_call_entry.schema.json (neo:external_slice_call_entry)
#   AND .neo\schema\external_audit_verdict.schema.json (neo:external_audit_verdict) list
#   run_id, slice_id, round_id, and bundle_diff_hash as REQUIRED properties (both schemas'
#   "required" arrays were read directly, not inferred). The join therefore uses ALL FOUR
#   fields present on BOTH sides: run_id|slice_id|round_id|bundle_diff_hash. Using only
#   round_id+bundle_diff_hash (round-1 behavior) under-scoped the join and could false-
#   match across different runs/slices that happen to reuse those two values; the four-
#   field key is the tightest join actually grounded in the schemas.
#
#   The run-level external_call_ledger.jsonl (attempt_ledger_entry shape) carries NO
#   round_id/bundle_diff_hash, so it CANNOT be joined against the verdict ledger by this
#   watchdog; it is scanned for existence/mtime/parseability only (unparseable lines make
#   the FILE unreadable, never "healthy"), and does not itself drive an open-call alert.
#   All open-call alerting is driven from external_slice_call_ledger.jsonl, which is the
#   ledger that actually carries the correlatable keys.
#
#   FIX-1 (round 2): if the sibling external_verdict_ledger.jsonl exists but is
#   unreadable/unparseable, this run root's open-call evaluation is NOT performed
#   against an empty verdict-key set (that produced false open-call alerts pre-fix).
#   Instead every would-be-open entry in that ledger is recorded INDETERMINATE
#   (disclosed, no alert); the verdict file itself stays under "unreadable".
#
#   FIX-3 (round 2): the open_ledger_call stall object carries run_root + slice_id
#   explicitly, and the dedupe/alert stall key folds both in (alongside kind/path/
#   start_marker) so two distinct stalls (e.g. two slice_id entries in the same ledger
#   file sharing round_id+bundle_diff_hash) can never collapse into one alert.

param(
  [string]$ConfigPath,
  [string]$ProcessSnapshotPath,
  [string]$NotifyTestModeDir
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------------
# CONFIG LOAD - fail-closed: missing/unparseable => ONE stderr line + exit 1.
# ---------------------------------------------------------------------------------
$script:NeoWatchdogRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
# $PSScriptRoot = <root>\.neo\scripts\watchdog ; root is 3 levels up.

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $PSScriptRoot 'watchdog_config.json'
}

function Write-WatchdogConfigFailure {
  param([string]$Reason)
  [Console]::Error.WriteLine("subsession_watchdog: CONFIG_FAILURE: $Reason")
  exit 1
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  Write-WatchdogConfigFailure "config not found at '$ConfigPath'"
}

$cfgRaw = $null
try {
  $cfgRaw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
} catch {
  Write-WatchdogConfigFailure "config unreadable at '$ConfigPath': $($_.Exception.Message)"
}

$cfg = $null
try {
  $cfg = $cfgRaw | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-WatchdogConfigFailure "config is not valid JSON at '$ConfigPath': $($_.Exception.Message)"
}

function Get-CfgProp {
  param($Obj, [string]$Name)
  if ($null -eq $Obj) { return $null }
  $p = $Obj.PSObject.Properties[$Name]
  if ($null -eq $p) { return $null }
  return $p.Value
}

$requiredKeys = @('task_output_stale_min','codex_wall_min','ledger_open_call_min',
  'active_run_root_max_age_hours','temp_tasks_root','run_roots','scan_depth','state_dir')
foreach ($k in $requiredKeys) {
  $v = Get-CfgProp $cfg $k
  if ($null -eq $v) { Write-WatchdogConfigFailure "config missing required key '$k'" }
}

try {
  $taskOutputStaleMin = [int](Get-CfgProp $cfg 'task_output_stale_min')
  $codexWallMin       = [int](Get-CfgProp $cfg 'codex_wall_min')
  $ledgerOpenCallMin  = [int](Get-CfgProp $cfg 'ledger_open_call_min')
  $activeRunRootMaxAgeHours = [int](Get-CfgProp $cfg 'active_run_root_max_age_hours')
  $scanDepth          = [int](Get-CfgProp $cfg 'scan_depth')
} catch {
  Write-WatchdogConfigFailure "config numeric field is not a valid integer: $($_.Exception.Message)"
}

$tempTasksRootRaw = [string](Get-CfgProp $cfg 'temp_tasks_root')
if ([string]::IsNullOrWhiteSpace($tempTasksRootRaw)) { Write-WatchdogConfigFailure "temp_tasks_root is blank" }
$tempTasksRoot = [System.Environment]::ExpandEnvironmentVariables($tempTasksRootRaw)

$runRootsRaw = Get-CfgProp $cfg 'run_roots'
$runRoots = @($runRootsRaw | ForEach-Object { [System.Environment]::ExpandEnvironmentVariables([string]$_) })
if (@($runRoots).Count -eq 0) { Write-WatchdogConfigFailure "run_roots is empty" }

# SLICE 2b (human-approved, Raphael option 1): watch_task_outputs gates the ENTIRE
# target-(i) stale-task-output scan. Shipped default = false (OFF). A missing flag is
# ALSO treated as false - chosen default because target (i) is known-noisy pending a
# completion-marker discriminator (soak finding: a real sweep composed 153
# stale_task_output alerts, all COMPLETED harness task outputs of live sessions;
# mtime-only cannot distinguish completed from stalled and no on-disk completion
# marker exists). Targets (ii) codex-overrun and (iii) open-ledger-call both soaked
# clean and stay live. NOT in $requiredKeys by design (missing => OFF, fail-quiet on
# this one key only; every other config key remains fail-closed).
$watchTaskOutputs = $false
$watchTaskOutputsRaw = Get-CfgProp $cfg 'watch_task_outputs'
if ($null -ne $watchTaskOutputsRaw) {
  try { $watchTaskOutputs = [bool]$watchTaskOutputsRaw } catch { $watchTaskOutputs = $false }
}

$stateDirRaw = [string](Get-CfgProp $cfg 'state_dir')
if ([string]::IsNullOrWhiteSpace($stateDirRaw)) { Write-WatchdogConfigFailure "state_dir is blank" }
if ([System.IO.Path]::IsPathRooted($stateDirRaw)) {
  $stateDir = $stateDirRaw
} else {
  $stateDir = Join-Path $script:NeoWatchdogRoot $stateDirRaw
}

try {
  New-Item -ItemType Directory -Force -Path $stateDir -ErrorAction Stop | Out-Null
} catch {
  Write-WatchdogConfigFailure "cannot create/access state_dir '$stateDir': $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------------
# RE-ENTRANCY LOCK
# FIX-4 (round 2): ATOMIC acquisition. The old check-then-write (Test-Path then
# Set-Content) had a TOCTOU race window between two concurrent sweeps. Now the FIRST
# acquisition attempt is a single atomic exclusive-create filesystem call
# ([System.IO.File]::Open with FileMode.CreateNew, which fails atomically if the file
# already exists - no separate existence check beforehand). Only on that failing
# (file already exists - either a live sweep or a stale dead-PID lock) do we fall back
# to the existing live-PID check logic. Dead-PID takeover is itself made race-safe:
# delete the stale lock file then retry CreateNew exactly once; if that second attempt
# ALSO loses the race (another sweep grabbed it first), silently exit 0 (no sweep).
# ---------------------------------------------------------------------------------
$lockPath = Join-Path $stateDir 'sweep.lock'

function Test-NeoPidAlive {
  param([int]$ProcId)
  try {
    $p = Get-Process -Id $ProcId -ErrorAction Stop
    return ($null -ne $p)
  } catch {
    return $false
  }
}

function Try-NeoAtomicLockCreate {
  # Attempts an atomic exclusive create of $Path containing $PidText.
  # Returns $true on success (we now own the lock), $false if creation failed
  # (already exists, or any other race/IO failure - caller decides what to do next).
  param([string]$Path, [string]$PidText)
  $fs = $null
  try {
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($PidText)
    $fs.Write($bytes, 0, $bytes.Length)
    $fs.Flush()
    return $true
  } catch {
    return $false
  } finally {
    if ($null -ne $fs) { $fs.Dispose() }
  }
}

$haveLock = $false
$pidText = [string]$PID

# First attempt: atomic exclusive create. No prior existence check - CreateNew itself
# is the atomic test-and-set.
if (Try-NeoAtomicLockCreate -Path $lockPath -PidText $pidText) {
  $haveLock = $true
} else {
  # Lock file already exists (or a transient IO race) - fall back to the live-PID
  # check logic against whatever is currently on disk.
  $existingPidRaw = $null
  try { $existingPidRaw = (Get-Content -LiteralPath $lockPath -Raw -ErrorAction Stop).Trim() } catch { $existingPidRaw = $null }
  $existingPidInt = 0
  $parsedOk = [int]::TryParse($existingPidRaw, [ref]$existingPidInt)
  if ($parsedOk -and (Test-NeoPidAlive -ProcId $existingPidInt)) {
    # a live sweep already owns the lock -> exit 0 silently, no sweep.
    exit 0
  }

  # Dead-PID (or unreadable/unparseable) lock -> race-safe takeover: delete the stale
  # lock, then retry the atomic CreateNew exactly once.
  try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue } catch { }
  if (Try-NeoAtomicLockCreate -Path $lockPath -PidText $pidText) {
    $haveLock = $true
  } else {
    # Second attempt ALSO lost the race (another sweep won it between our delete and
    # our retry) - silent exit 0, no sweep, per contract.
    exit 0
  }
}

# ---------------------------------------------------------------------------------
# STATE (status accumulators)
# ---------------------------------------------------------------------------------
$stalls = New-Object System.Collections.Generic.List[object]
$indeterminate = New-Object System.Collections.Generic.List[object]
$unreadable = New-Object System.Collections.Generic.List[object]
$countTaskOutputs = 0
$countProcesses = 0
$countLedgers = 0

function Add-Unreadable {
  param([string]$Path, [string]$Reason)
  $script:unreadable.Add([pscustomobject]@{ path = $Path; reason = $Reason })
}

# ---------------------------------------------------------------------------------
# PROCESS ENUMERATION (live or test seam)
# ---------------------------------------------------------------------------------
# Returns @{ ok; processes; reason } - processes is an array of
# @{ name; command_line; start_time_utc_iso; pid }. ok=false => enumeration failed
# (liveness INDETERMINATE downstream).
function Get-NeoWatchdogProcesses {
  param([string]$SnapshotPath)
  if (-not [string]::IsNullOrWhiteSpace($SnapshotPath)) {
    if (-not (Test-Path -LiteralPath $SnapshotPath)) {
      return @{ ok = $false; processes = @(); reason = "process snapshot not found at '$SnapshotPath'" }
    }
    try {
      $raw = Get-Content -LiteralPath $SnapshotPath -Raw -ErrorAction Stop
      $arr = $raw | ConvertFrom-Json -ErrorAction Stop
      $list = @($arr | ForEach-Object {
        [pscustomobject]@{
          name = [string](Get-CfgProp $_ 'name')
          command_line = [string](Get-CfgProp $_ 'command_line')
          start_time_utc_iso = [string](Get-CfgProp $_ 'start_time_utc_iso')
          pid_val = [string](Get-CfgProp $_ 'pid')
        }
      })
      return @{ ok = $true; processes = $list; reason = '' }
    } catch {
      return @{ ok = $false; processes = @(); reason = "process snapshot unparseable: $($_.Exception.Message)" }
    }
  }

  try {
    $rows = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
    $list = @($rows | ForEach-Object {
      $cts = $null
      try {
        if ($_.CreationDate) { $cts = ([System.Management.ManagementDateTimeConverter]::ToDateTime($_.CreationDate)).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
      } catch { $cts = $null }
      [pscustomobject]@{
        name = [string]$_.Name
        command_line = [string]$_.CommandLine
        start_time_utc_iso = $cts
        pid_val = [string]$_.ProcessId
      }
    })
    return @{ ok = $true; processes = $list; reason = '' }
  } catch {
    return @{ ok = $false; processes = @(); reason = "Get-CimInstance Win32_Process enumeration failed: $($_.Exception.Message)" }
  }
}

$procResult = Get-NeoWatchdogProcesses -SnapshotPath $ProcessSnapshotPath
$countProcesses = @($procResult.processes).Count

function ConvertFrom-NeoWatchdogIsoUtc {
  param([string]$IsoText)
  if ([string]::IsNullOrWhiteSpace($IsoText)) { return $null }
  try {
    return [datetime]::Parse($IsoText, [System.Globalization.CultureInfo]::InvariantCulture,
      [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
  } catch {
    return $null
  }
}

$nowUtc = [datetime]::UtcNow

# ===================================================================================
# WATCH TARGET (i): STALE TASK OUTPUT
# ===================================================================================
function Test-NeoSessionLive {
  param([string]$SessionFolderName, [array]$Processes)
  foreach ($p in $Processes) {
    $cl = [string]$p.command_line
    if (-not [string]::IsNullOrEmpty($cl) -and $cl.Contains($SessionFolderName)) { return $true }
  }
  return $false
}

# SLICE 2b: the ENTIRE target-(i) scan is gated on watch_task_outputs (shipped default
# OFF; missing flag = OFF - see the flag-parse comment near the config block). When
# disabled: nothing under temp_tasks_root is enumerated or counted
# (targets_checked.task_outputs stays 0), no stale_task_output stall/indeterminate/
# unreadable entries are produced, and the status file discloses
# disabled_targets:["task_outputs"] so a quiet status is never mistaken for a
# scanned-and-clean surface. When enabled: behavior is unchanged from round 2.
if ($watchTaskOutputs) {
if (-not (Test-Path -LiteralPath $tempTasksRoot)) {
  Add-Unreadable -Path $tempTasksRoot -Reason 'temp_tasks_root does not exist'
} else {
  try {
    $projectDirs = @(Get-ChildItem -LiteralPath $tempTasksRoot -Directory -ErrorAction Stop)
    foreach ($projDir in $projectDirs) {
      try {
        $sessionDirs = @(Get-ChildItem -LiteralPath $projDir.FullName -Directory -ErrorAction Stop)
      } catch {
        Add-Unreadable -Path $projDir.FullName -Reason "cannot list session dirs: $($_.Exception.Message)"
        continue
      }
      foreach ($sessDir in $sessionDirs) {
        $tasksPath = Join-Path $sessDir.FullName 'tasks'
        if (-not (Test-Path -LiteralPath $tasksPath)) { continue }
        try {
          $outFiles = @(Get-ChildItem -LiteralPath $tasksPath -Filter '*.output' -File -ErrorAction Stop)
        } catch {
          Add-Unreadable -Path $tasksPath -Reason "cannot list *.output files: $($_.Exception.Message)"
          continue
        }
        foreach ($of in $outFiles) {
          $countTaskOutputs++
          $ageMin = [math]::Round(($nowUtc - $of.LastWriteTimeUtc).TotalMinutes, 2)
          if ($ageMin -le $taskOutputStaleMin) { continue }
          if (-not $procResult.ok) {
            $indeterminate.Add([pscustomobject]@{
              kind = 'stale_task_output'; path = $of.FullName; age_min = $ageMin
              reason = "liveness INDETERMINATE: $($procResult.reason)"
            })
            continue
          }
          $isLive = Test-NeoSessionLive -SessionFolderName $sessDir.Name -Processes $procResult.processes
          if ($isLive) {
            $stalls.Add([pscustomobject]@{
              kind = 'stale_task_output'
              path = $of.FullName
              age_min = $ageMin
              start_marker = $of.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
              alerted = $false
            })
          }
          # not live -> finished session leaves stale outputs legitimately, not a stall.
        }
      }
    }
  } catch {
    Add-Unreadable -Path $tempTasksRoot -Reason "cannot list project dirs: $($_.Exception.Message)"
  }
}
}  # end SLICE 2b watch_task_outputs gate

# ===================================================================================
# WATCH TARGET (ii): CODEX OVERRUN
# ===================================================================================
if ($procResult.ok) {
  foreach ($p in $procResult.processes) {
    $nm = [string]$p.name
    $cl = [string]$p.command_line
    $isCodexLike = $false
    if ($nm -match '^(?i)codex') { $isCodexLike = $true }
    elseif (($nm -match '^(?i)node') -and (-not [string]::IsNullOrEmpty($cl)) -and ($cl -match '(?i)codex')) { $isCodexLike = $true }
    if (-not $isCodexLike) { continue }

    $startDt = ConvertFrom-NeoWatchdogIsoUtc -IsoText ([string]$p.start_time_utc_iso)
    if ($null -eq $startDt) {
      $indeterminate.Add([pscustomobject]@{
        kind = 'codex_overrun'; path = ('pid:' + [string]$p.pid_val + ' ' + $nm); age_min = $null
        reason = 'start_time_utc_iso missing or unparseable - cannot evaluate wall-clock age'
      })
      continue
    }
    $ageMin = [math]::Round(($nowUtc - $startDt).TotalMinutes, 2)
    if ($ageMin -gt $codexWallMin) {
      $stalls.Add([pscustomobject]@{
        kind = 'codex_overrun'
        path = ('pid:' + [string]$p.pid_val + ' ' + $nm)
        age_min = $ageMin
        start_marker = $startDt.ToString('yyyy-MM-ddTHH:mm:ssZ')
        alerted = $false
      })
    }
  }
} else {
  $indeterminate.Add([pscustomobject]@{
    kind = 'codex_overrun'; path = '(process enumeration)'; age_min = $null
    reason = "liveness INDETERMINATE: $($procResult.reason)"
  })
}

# ===================================================================================
# WATCH TARGET (iii): OPEN LEDGER CALL
# See the grounding block at the top of this file for the detection rule and why.
# ===================================================================================
function Get-NeoJsonlLinesSafe {
  param([string]$Path)
  # Returns @{ ok; lines (array of parsed objects); reason }
  try {
    $raw = Get-Content -LiteralPath $Path -ErrorAction Stop
  } catch {
    return @{ ok = $false; lines = @(); reason = "cannot read file: $($_.Exception.Message)" }
  }
  $parsed = New-Object System.Collections.Generic.List[object]
  foreach ($ln in @($raw)) {
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try {
      $obj = $ln | ConvertFrom-Json -ErrorAction Stop
      $parsed.Add($obj)
    } catch {
      return @{ ok = $false; lines = @(); reason = "unparseable JSONL line: $($_.Exception.Message)" }
    }
  }
  return @{ ok = $true; lines = $parsed.ToArray(); reason = '' }
}

function Find-NeoRunRootLedgerFiles {
  param([string]$RunRoot, [int]$MaxDepth)
  # Recurse up to MaxDepth levels under RunRoot, collecting matching ledger filenames.
  $results = New-Object System.Collections.Generic.List[object]
  if (-not (Test-Path -LiteralPath $RunRoot)) { return ,$results.ToArray() }
  $names = @('external_slice_call_ledger.jsonl','external_call_ledger.jsonl')
  $queue = New-Object System.Collections.Generic.Queue[object]
  $queue.Enqueue(@{ path = $RunRoot; depth = 0 })
  while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    try {
      $children = @(Get-ChildItem -LiteralPath $cur.path -ErrorAction Stop)
    } catch {
      Add-Unreadable -Path $cur.path -Reason "cannot list directory for ledger scan: $($_.Exception.Message)"
      continue
    }
    foreach ($c in $children) {
      if ($c.PSIsContainer) {
        if ($cur.depth -lt $MaxDepth) {
          $queue.Enqueue(@{ path = $c.FullName; depth = ($cur.depth + 1) })
        }
      } elseif ($names -contains $c.Name) {
        $results.Add($c)
      }
    }
  }
  return ,$results.ToArray()
}

foreach ($runRoot in $runRoots) {
  if (-not (Test-Path -LiteralPath $runRoot)) {
    Add-Unreadable -Path $runRoot -Reason 'run_roots entry does not exist'
    continue
  }
  $ledgerFiles = Find-NeoRunRootLedgerFiles -RunRoot $runRoot -MaxDepth $scanDepth
  foreach ($lf in $ledgerFiles) {
    $ageHours = ($nowUtc - $lf.LastWriteTimeUtc).TotalHours
    if ($ageHours -gt $activeRunRootMaxAgeHours) { continue }  # inactive run, skip.

    $countLedgers++
    $parsedResult = Get-NeoJsonlLinesSafe -Path $lf.FullName
    if (-not $parsedResult.ok) {
      Add-Unreadable -Path $lf.FullName -Reason $parsedResult.reason
      continue
    }

    if ($lf.Name -ne 'external_slice_call_ledger.jsonl') {
      # external_call_ledger.jsonl (attempt_ledger_entry shape) carries no round_id /
      # bundle_diff_hash - scanned for parseability only per the grounding above; it
      # does not itself drive an open-call alert (no correlatable key on this shape).
      continue
    }

    # Build the sibling verdict ledger lookup set (same run root dir as this file).
    # JOIN KEY GROUNDING (FIX-2, round 2): both neo:external_slice_call_entry
    # (external_slice_call_ledger.jsonl) and neo:external_audit_verdict
    # (external_verdict_ledger.jsonl) list run_id, slice_id, round_id, and
    # bundle_diff_hash as REQUIRED fields (verified directly against
    # .neo\schema\external_slice_call_entry.schema.json and
    # .neo\schema\external_audit_verdict.schema.json). The join key therefore uses ALL
    # FOUR correlating fields present on BOTH sides: run_id|slice_id|round_id|bundle_diff_hash.
    # (attempt_ledger_entry / external_call_ledger.jsonl carries none of round_id,
    # bundle_diff_hash - it is excluded from this join per the grounding above and is
    # only scanned for parseability.)
    $verdictPath = Join-Path (Split-Path -Parent $lf.FullName) 'external_verdict_ledger.jsonl'
    $verdictKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    $verdictLedgerUnreadable = $false
    if (Test-Path -LiteralPath $verdictPath) {
      $verdictParsed = Get-NeoJsonlLinesSafe -Path $verdictPath
      if ($verdictParsed.ok) {
        foreach ($v in $verdictParsed.lines) {
          $key = [string](Get-CfgProp $v 'run_id') + '|' + [string](Get-CfgProp $v 'slice_id') + '|' +
                 [string](Get-CfgProp $v 'round_id') + '|' + [string](Get-CfgProp $v 'bundle_diff_hash')
          [void]$verdictKeys.Add($key)
        }
      } else {
        Add-Unreadable -Path $verdictPath -Reason $verdictParsed.reason
        # FIX-1 (round 2): an unreadable/unparseable verdict ledger must NOT be
        # evaluated against an empty verdict-key set below (that produced FALSE
        # open-call alerts pre-fix, since every consumed entry looked "incomplete"
        # against an empty set). Instead this run root's open-call evaluation is
        # INDETERMINATE (disclosed) and produces NO open-call alerts; the verdict
        # file itself stays recorded under "unreadable" (already done above).
        $verdictLedgerUnreadable = $true
      }
    }

    foreach ($entry in $parsedResult.lines) {
      $refused = [bool](Get-CfgProp $entry 'refused')
      $reason  = [string](Get-CfgProp $entry 'reason')
      $refKind = [string](Get-CfgProp $entry 'run_ledger_ref_kind')
      if ($refused -or ($reason -ne 'NONE') -or ($refKind -ne 'CONSUMED')) { continue }  # not a launched call.

      $tsRaw = [string](Get-CfgProp $entry 'timestamp_utc')
      $tsDt = ConvertFrom-NeoWatchdogIsoUtc -IsoText $tsRaw
      if ($null -eq $tsDt) {
        Add-Unreadable -Path $lf.FullName -Reason "entry with unparseable timestamp_utc '$tsRaw'"
        continue
      }
      $ageMin = [math]::Round(($nowUtc - $tsDt).TotalMinutes, 2)
      if ($ageMin -le $ledgerOpenCallMin) { continue }

      $entryRunId = [string](Get-CfgProp $entry 'run_id')
      $entrySliceId = [string](Get-CfgProp $entry 'slice_id')
      $roundId = [string](Get-CfgProp $entry 'round_id')
      $bundleHash = [string](Get-CfgProp $entry 'bundle_diff_hash')

      if ($verdictLedgerUnreadable) {
        # FIX-1: cannot confirm completion for this run root at all - disclose
        # INDETERMINATE per-entry rather than silently skip or falsely alert.
        $indeterminate.Add([pscustomobject]@{
          kind = 'open_ledger_call'; path = $lf.FullName; age_min = $ageMin
          reason = "sibling external_verdict_ledger.jsonl is unreadable/unparseable - cannot confirm completion for run_id=$entryRunId slice_id=$entrySliceId round_id=$roundId"
        })
        continue
      }

      $key = $entryRunId + '|' + $entrySliceId + '|' + $roundId + '|' + $bundleHash
      if ($verdictKeys.Contains($key)) { continue }  # completed - a matching verdict landed.

      # FIX-3 (round 2): the stall key/object must include the run-root path AND
      # slice_id so two distinct stalls (e.g. two different slice_id entries in the
      # same ledger file that happen to share round_id+bundle_diff_hash) never
      # collapse into one dedupe/alert key.
      $stalls.Add([pscustomobject]@{
        kind = 'open_ledger_call'
        path = $lf.FullName
        run_root = $runRoot
        slice_id = $entrySliceId
        age_min = $ageMin
        start_marker = ($entryRunId + '#' + $entrySliceId + '#' + $roundId + '#' + $bundleHash)
        alerted = $false
      })
    }
  }
}

# ===================================================================================
# ALERTING
# ===================================================================================
$sentAlertsPath = Join-Path $stateDir 'sent_alerts.json'
$sentAlerts = @{}
if (Test-Path -LiteralPath $sentAlertsPath) {
  try {
    $raw = Get-Content -LiteralPath $sentAlertsPath -Raw -ErrorAction Stop
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
      $obj = $raw | ConvertFrom-Json -ErrorAction Stop
      foreach ($p in $obj.PSObject.Properties) { $sentAlerts[$p.Name] = $true }
    }
  } catch {
    # unreadable sent_alerts.json -> fail-closed by treating as EMPTY (conservative:
    # would rather re-send/dedupe-miss than silently suppress a real stall forever);
    # this does not affect "healthy" classification of watch targets, only dedupe memory.
    $sentAlerts = @{}
  }
}

# Self-locating: derive the notify module from this script's own location
# (<root>\.neo\scripts\watchdog\ -> <root>). No hardcoded install path; portable across installs.
$notifyModulePath = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) '.neo\scripts\notify\notify_raphael.ps1'
$notifyLoaded = $false
if ($stalls.Count -gt 0) {
  try {
    . $notifyModulePath
    $notifyLoaded = $true
  } catch {
    # cannot load notify module - stalls remain recorded in status but unalerted.
    $notifyLoaded = $false
  }
}

foreach ($s in $stalls) {
  # FIX-3 (round 2): explicitly fold run-root path + slice_id into the stall key
  # (when the stall carries them - open_ledger_call does; stale_task_output and
  # codex_overrun do not have a run_root/slice_id concept and are unaffected) so
  # two distinct stalls can never collapse into one dedupe/alert key.
  $sRunRoot = [string](Get-CfgProp $s 'run_root')
  $sSliceId = [string](Get-CfgProp $s 'slice_id')
  $stallKey = $s.kind + '|' + $s.path + '|' + $sRunRoot + '|' + $sSliceId + '|' + $s.start_marker
  if ($sentAlerts.ContainsKey($stallKey)) {
    $s.alerted = $true
    continue
  }
  if (-not $notifyLoaded) { continue }

  $summaryLines = @(
    ('stalled: ' + $s.kind),
    ('target: ' + $s.path),
    ('age_min: ' + [string]$s.age_min + ' vs threshold'),
    'recommend: kill / wait / investigate - watchdog never kills'
  )

  $sendParams = @{
    GateType = 'ESCALATION_STOP'
    SliceId = ('watchdog/' + $s.kind)
    SummaryLines = $summaryLines
    EvidencePath = $s.path
    # Redirect the module's OWN DEF-P8 dedupe ledger into our approved state_dir so
    # the watchdog never writes to the real %USERPROFILE%\.neo_notify\send_ledger.jsonl
    # (out-of-band tests and repeated sweeps would otherwise pollute/dedupe against a
    # shared, uncontrolled location outside every approved path).
    LedgerPath = (Join-Path $stateDir 'notify_send_ledger.jsonl')
  }
  if (-not [string]::IsNullOrWhiteSpace($NotifyTestModeDir)) {
    $sendParams['TestModeDir'] = $NotifyTestModeDir
  } else {
    $sendParams['LiveSend'] = $true
  }

  $result = $null
  try {
    $result = Send-NeoGateNotification @sendParams
  } catch {
    $result = $null
  }

  $composedOrSent = $false
  if ($null -ne $result) {
    if ([bool]$result.sent) { $composedOrSent = $true }
    elseif (-not [string]::IsNullOrEmpty($result.composed_path)) { $composedOrSent = $true }
  }

  if ($composedOrSent) {
    $s.alerted = $true
    $sentAlerts[$stallKey] = $true
  }
}

try {
  ($sentAlerts.Keys | ForEach-Object { @{ $_ = $true } } | ForEach-Object { $_ } | Out-Null)
  $sentAlertsObj = [ordered]@{}
  foreach ($k in $sentAlerts.Keys) { $sentAlertsObj[$k] = $true }
  ($sentAlertsObj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $sentAlertsPath -Encoding ascii -ErrorAction Stop
} catch {
  # best-effort persistence; dedupe memory loss is a degraded mode, never a crash.
}

# ===================================================================================
# STATUS FILE
# ===================================================================================
$statusPath = Join-Path $stateDir 'watchdog_status.json'
$statusObj = [ordered]@{
  last_sweep_utc = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
  targets_checked = [ordered]@{
    task_outputs = $countTaskOutputs
    processes = $countProcesses
    ledgers = $countLedgers
  }
  stalls = @($stalls | ForEach-Object {
    [ordered]@{ kind = $_.kind; path = $_.path; age_min = $_.age_min; alerted = $_.alerted }
  })
  indeterminate = $indeterminate.ToArray()
  unreadable = $unreadable.ToArray()
}
# SLICE 2b: when target (i) is disabled, disclose it explicitly so a quiet status is
# never mistaken for a scanned-and-clean surface (targets_checked.task_outputs=0 alone
# is ambiguous between "scanned, none found" and "not scanned"). Field added ONLY when
# disabled - the enabled status shape is unchanged from round 2.
if (-not $watchTaskOutputs) {
  $statusObj['disabled_targets'] = @('task_outputs')
}

try {
  ($statusObj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $statusPath -Encoding ascii -ErrorAction Stop
} catch {
  # status write failure: still must not throw stdout per the silence contract; fall
  # through to lock cleanup and exit 0 (best-effort persistence, never a crash on write).
}

# ===================================================================================
# CLEANUP (always release own lock)
# ===================================================================================
try {
  if ($haveLock -and (Test-Path -LiteralPath $lockPath)) {
    $curOwner = (Get-Content -LiteralPath $lockPath -Raw -ErrorAction SilentlyContinue)
    if ($curOwner -and ($curOwner.Trim() -eq [string]$PID)) {
      Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
  }
} catch {
  # best-effort lock cleanup.
}

exit 0
