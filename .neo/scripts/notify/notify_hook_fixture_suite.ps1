# notify_hook_fixture_suite.ps1 - B3H fixture suite for notify_hook.ps1 (FILTERED Stop hook +
# SESSION NAMING; contract NEO_STOPHOOK_B3H_CONTRACT.md fire/no-fire table v2).
# ASCII-only (D10). ZERO network: every send goes through -TestModeDir (compose-to-disk) +
# a SCRATCH -LedgerPath (the module's test-only seams; they travel together). Proves every
# contract row (1-8 FIRE with class + verbatim-content assertions; 8b/9/10 SILENT), the
# 8-vs-8b pair, the 61B28D5E same-session dedupe regression, truncation-keeps-the-TAIL,
# sanitize/mask, the long-transcript (>256KB) tail-read MUST-FIRE case, session naming
# (name file / fallback / non-ASCII / oversize / write-once UserPromptSubmit), and the
# retained fail-open negatives. ZERO-WRITE DISCIPLINE: the real
# %USERPROFILE%\.neo_notify\session_names is asserted untouched (all naming goes through
# the -TestModeDir seam).
# FIX ROUND 1 (2026-07-08, dual-lane audit r1): adds row-1 authorize / attestation-confirm
# gate forms + the bare-prose negative (F05b-F05d), the row-5 mid-line prose negative
# (F06b), the 8b uncertain=>FIRE blank-id pin (F10b), and the 8b sidechain-scope pin (F10c).
# Run:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File notify_hook_fixture_suite.ps1
#       [-HookPath <path to the hook under test; default = the sibling notify_hook.ps1>]
# Exit: 0 = all pass; 1 = any fail (the suite judges; a narrative never does).

param([string]$HookPath = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($HookPath)) { $HookPath = Join-Path $PSScriptRoot 'notify_hook.ps1' }
$HookPath = (Resolve-Path -LiteralPath $HookPath).Path
Write-Output ('HOOK UNDER TEST: ' + $HookPath)

$stamp = [datetime]::Now.ToString('yyyyMMdd_HHmmssfff')
$scratch = Join-Path $env:TEMP ('neo_b3h_hook_suite_' + $stamp)
New-Item -ItemType Directory -Force -Path $scratch | Out-Null

$psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

# --- zero-write discipline: snapshot the REAL session_names dir (must be untouched) ---
$realNamesDir = Join-Path $env:USERPROFILE '.neo_notify\session_names'
function Get-NamesDirState {
  if (-not (Test-Path -LiteralPath $realNamesDir)) { return '(absent)' }
  $items = @(Get-ChildItem -LiteralPath $realNamesDir -Force -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { $_.Name + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.ToString('o') })
  return ($items -join ';')
}
$namesStateBefore = Get-NamesDirState

$pass = 0; $fail = 0
function Assert([bool]$Cond, [string]$Name) {
  if ($Cond) { $script:pass++; Write-Output ('[PASS] ' + $Name) }
  else { $script:fail++; Write-Output ('[FAIL] ' + $Name) }
}

# Invoke the hook adapter exactly as the harness does: JSON on stdin, then inspect the
# compose dir. Every call passes BOTH seams (zero network by construction).
function Invoke-Hook {
  param([string]$Json, [string]$CaseDir, [string]$Ledger)
  if (-not (Test-Path -LiteralPath $CaseDir)) { New-Item -ItemType Directory -Force -Path $CaseDir | Out-Null }
  if ([string]::IsNullOrEmpty($Ledger)) { $Ledger = Join-Path $CaseDir 'ledger.jsonl' }
  $Json | & $psExe -NoProfile -ExecutionPolicy Bypass -File $HookPath -TestModeDir $CaseDir -LedgerPath $Ledger | Out-Null
  $code = $LASTEXITCODE
  $files = @(Get-ChildItem -LiteralPath $CaseDir -Filter '*.eml.txt' -ErrorAction SilentlyContinue | Sort-Object Name)
  return @{ exit = $code; files = $files; ledger = $Ledger }
}
function Read-Mail($r) {
  if ($r.files.Count -ge 1) { return [System.IO.File]::ReadAllText($r.files[$r.files.Count - 1].FullName) }
  return ''
}
function Get-MailLines([string]$m) { return @($m -split "`r`n") }
function Get-LedgerEntries([string]$Ledger) {
  if (-not (Test-Path -LiteralPath $Ledger)) { return @() }
  $out = @()
  foreach ($ln in @(Get-Content -LiteralPath $Ledger -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try { $out += (ConvertFrom-Json -InputObject $ln) } catch {}
  }
  return $out
}

# --- transcript builders (grounded against real harness JSONL, 2026-07-08:
# entries = one JSON object per line; assistant messages stream as MULTIPLE entries sharing
# message.id, one content block each (thinking/text/tool_use); user entries carry string
# content (human prompts, <task-notification>, <command-name> local commands) or block
# lists (tool_result); background tasks = tool_use with input.run_in_background=true,
# completed by a later user entry '<task-notification>...<tool-use-id>ID</tool-use-id>'.) ---
function JLine([hashtable]$h) { return (ConvertTo-Json -InputObject $h -Compress -Depth 12) }
function AsstTextLine([string]$mid, [string]$text) {
  return (JLine @{ type = 'assistant'; isSidechain = $false; message = @{ id = $mid; role = 'assistant'; content = @(@{ type = 'text'; text = $text }) } })
}
function AsstThinkLine([string]$mid) {
  return (JLine @{ type = 'assistant'; isSidechain = $false; message = @{ id = $mid; role = 'assistant'; content = @(@{ type = 'thinking'; thinking = 'internal reasoning'; signature = 'sig' }) } })
}
function AsstToolLine([string]$mid, [string]$tuid, [bool]$bg) {
  $inp = @{ command = 'echo x' }
  if ($bg) { $inp['run_in_background'] = $true }
  return (JLine @{ type = 'assistant'; isSidechain = $false; message = @{ id = $mid; role = 'assistant'; content = @(@{ type = 'tool_use'; id = $tuid; name = 'Bash'; input = $inp }) } })
}
function UserStrLine([string]$s) { return (JLine @{ type = 'user'; message = @{ role = 'user'; content = $s } }) }
function UserToolResultLine([string]$tuid) {
  return (JLine @{ type = 'user'; message = @{ role = 'user'; content = @(@{ type = 'tool_result'; tool_use_id = $tuid; content = 'ok' }) } })
}
function TaskNoteLine([string]$tuid) {
  return (UserStrLine ("<task-notification>`n<task-id>t1</task-id>`n<tool-use-id>" + $tuid + "</tool-use-id>`n<status>completed</status>`n</task-notification>"))
}
function Write-Transcript([string]$Path, [string[]]$Lines, [bool]$Bom) {
  $enc = New-Object System.Text.UTF8Encoding($Bom)
  [System.IO.File]::WriteAllLines($Path, $Lines, $enc)
}
function StopJson([string]$sid, [string]$cwd, [string]$tpath) {
  return (ConvertTo-Json -InputObject @{ hook_event_name = 'Stop'; session_id = $sid; cwd = $cwd; transcript_path = $tpath } -Compress)
}
function UpsJson([string]$sid, [string]$cwd, [string]$prompt) {
  return (ConvertTo-Json -InputObject @{ hook_event_name = 'UserPromptSubmit'; session_id = $sid; cwd = $cwd; prompt = $prompt } -Compress)
}
function Set-NameFile([string]$CaseDir, [string]$sid, [string]$name) {
  $d = Join-Path $CaseDir 'session_names'
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $d ($sid + '.txt')), $name, (New-Object System.Text.UTF8Encoding($true)))
}

$sid = 'abcd1234efgh'
$dev = 'S:\NEO_dev'

# ============ F01: row 1 - gate question => APPROVAL_NEEDED, ask VERBATIM ============
# Also proves: message-id grouping across streamed entries, thinking/tool blocks ignored,
# scan scope = FINAL paragraph only, naming from the name file, body line 1, evidence line.
$d1 = Join-Path $scratch 'f01'
New-Item -ItemType Directory -Force -Path $d1 | Out-Null
Set-NameFile $d1 $sid 'b3h-fixture'
$t1 = Join-Path $scratch 't01.jsonl'
Write-Transcript $t1 @(
  (UserStrLine 'please gate this'),
  (AsstThinkLine 'm1'),
  (AsstTextLine 'm1' 'Plan staged and audited.'),
  (AsstTextLine 'm1' ("`nSTART approval: the B3H slice plan is frozen.`nKeep / iterate / toss?"))
) $true
$r1 = Invoke-Hook (StopJson $sid $dev $t1) $d1
$c1 = Read-Mail $r1
$l1 = Get-MailLines $c1
Assert ($r1.exit -eq 0) 'F01 row1: exit 0'
Assert ($r1.files.Count -eq 1) 'F01 row1: exactly one composed mail'
Assert ($c1 -match 'Subject: \[NEO\] APPROVAL_NEEDED - b3h-fixture') 'F01 row1: APPROVAL_NEEDED subject carries the session name'
Assert ($l1.Count -gt 4 -and $l1[4] -eq 'Session: b3h-fixture | id abcd1234 | tree: DEV') 'F01 row1: body line 1 = Session | id uuid8 | tree'
Assert ($c1.Contains('START approval: the B3H slice plan is frozen.')) 'F01 row1: ask line 1 VERBATIM'
Assert ($c1.Contains('Keep / iterate / toss?')) 'F01 row1: ask line 2 VERBATIM'
Assert (-not $c1.Contains('Plan staged and audited.')) 'F01 row1: earlier paragraph NOT mailed (final-paragraph scope)'
Assert ($c1.Contains('Evidence: ' + $t1)) 'F01 row1: evidence = transcript path'
Assert ($c1.Contains('Working dir: S:\NEO_dev')) 'F01 row1: working-dir line present'

# ============ F02: row 2 - direct question (ends with ?) => DECISION_NEEDED ============
$d2 = Join-Path $scratch 'f02'
$t2 = Join-Path $scratch 't02.jsonl'
Write-Transcript $t2 @(
  (UserStrLine 'where should the ledger live'),
  (AsstTextLine 'm1' ("Two options exist for the ledger location.`n`nWhich ledger location do you want, A or B?"))
) $false
$r2 = Invoke-Hook (StopJson $sid $dev $t2) $d2
$c2 = Read-Mail $r2
Assert ($r2.exit -eq 0) 'F02 row2: exit 0'
Assert ($r2.files.Count -eq 1) 'F02 row2: composed'
Assert ($c2 -match 'Subject: \[NEO\] DECISION_NEEDED - ') 'F02 row2: DECISION_NEEDED class'
Assert ($c2.Contains('Which ledger location do you want, A or B?')) 'F02 row2: question VERBATIM'
Assert ($c2 -notmatch 'SESSION_END') 'F02 row2: not SESSION_END (case-4 rewrite pin)'

# ============ F03: row 2 - DECISION marker without ? => DECISION_NEEDED ============
$d3 = Join-Path $scratch 'f03'
$t3 = Join-Path $scratch 't03.jsonl'
Write-Transcript $t3 @(
  (UserStrLine 'plan the run'),
  (AsstTextLine 'm1' ("Analysis done.`n`nDECISION NEEDED: pick the EMS run window and reply in-session."))
) $false
$r3 = Invoke-Hook (StopJson $sid $dev $t3) $d3
$c3 = Read-Mail $r3
Assert ($r3.files.Count -eq 1) 'F03 row2-marker: composed'
Assert ($c3 -match 'Subject: \[NEO\] DECISION_NEEDED - ') 'F03 row2-marker: DECISION_NEEDED class'
Assert ($c3.Contains('DECISION NEEDED: pick the EMS run window and reply in-session.')) 'F03 row2-marker: ask VERBATIM'

# ============ F04: row 3 - breaker/park => ESCALATION_STOP, reason VERBATIM ============
$d4 = Join-Path $scratch 'f04'
$t4 = Join-Path $scratch 't04.jsonl'
Write-Transcript $t4 @(
  (UserStrLine 'run it'),
  (AsstTextLine 'm1' ("Slice 2 attempt log follows.`n`nBREAKER TRIP: slice 2 failed twice; the run is parked."))
) $false
$r4 = Invoke-Hook (StopJson $sid $dev $t4) $d4
$c4 = Read-Mail $r4
Assert ($r4.files.Count -eq 1) 'F04 row3: composed'
Assert ($c4 -match 'Subject: \[NEO\] ESCALATION_STOP - ') 'F04 row3: ESCALATION_STOP class'
Assert ($c4.Contains('BREAKER TRIP: slice 2 failed twice; the run is parked.')) 'F04 row3: reason VERBATIM'

# ============ F05: row 4 - permission prompt exact form => APPROVAL_NEEDED ============
$d5 = Join-Path $scratch 'f05'
$t5 = Join-Path $scratch 't05.jsonl'
Write-Transcript $t5 @(
  (UserStrLine 'proceed'),
  (AsstTextLine 'm1' ("Ready to run the suite.`n`nClaude needs your permission to use Bash for the fixture run."))
) $false
$r5 = Invoke-Hook (StopJson $sid $dev $t5) $d5
$c5 = Read-Mail $r5
Assert ($r5.files.Count -eq 1) 'F05 row4: composed'
Assert ($c5 -match 'Subject: \[NEO\] APPROVAL_NEEDED - ') 'F05 row4: APPROVAL_NEEDED class'
Assert ($c5.Contains('needs your permission to use Bash')) 'F05 row4: tool + ask carried'

# ============ F05b/F05c: row 1 - authorize / attestation-confirm gate forms (fix r1) ============
$d5b = Join-Path $scratch 'f05b'
$t5b = Join-Path $scratch 't05b.jsonl'
Write-Transcript $t5b @(
  (UserStrLine 'ready for the re-pin'),
  (AsstTextLine 'm1' ("The old->new ledger is assembled below.`n`nDo you authorize the re-pin ledger?"))
) $false
$r5b = Invoke-Hook (StopJson $sid $dev $t5b) $d5b
$c5b = Read-Mail $r5b
Assert ($r5b.files.Count -eq 1) 'F05b row1-authorize: composed'
Assert ($c5b -match 'Subject: \[NEO\] APPROVAL_NEEDED - ') 'F05b row1-authorize: APPROVAL_NEEDED class (not row-2 DECISION)'
Assert ($c5b.Contains('Do you authorize the re-pin ledger?')) 'F05b row1-authorize: ask VERBATIM'

$d5c = Join-Path $scratch 'f05c'
$t5c = Join-Path $scratch 't05c.jsonl'
Write-Transcript $t5c @(
  (UserStrLine 'auto mode next'),
  (AsstTextLine 'm1' ("The AUTO envelope is staged.`n`nPlease confirm the attestation for the standing AUTO record."))
) $false
$r5c = Invoke-Hook (StopJson $sid $dev $t5c) $d5c
$c5c = Read-Mail $r5c
Assert ($r5c.files.Count -eq 1) 'F05c row1-attestation: composed'
Assert ($c5c -match 'Subject: \[NEO\] APPROVAL_NEEDED - ') 'F05c row1-attestation: APPROVAL_NEEDED class'
Assert ($c5c.Contains('Please confirm the attestation for the standing AUTO record.')) 'F05c row1-attestation: ask VERBATIM'

# ============ F05d: NEGATIVE - bare authorized/attestation prose, non-gate ending ============
$d5d = Join-Path $scratch 'f05d'
$t5d = Join-Path $scratch 't05d.jsonl'
Write-Transcript $t5d @(
  (UserStrLine 'status'),
  (AsstTextLine 'm1' 'Raphael authorized the swap earlier and the attestation is stamped and archived. All suites are green. Standing by.')
) $false
$r5d = Invoke-Hook (StopJson $sid $dev $t5d) $d5d
$c5d = Read-Mail $r5d
Assert ($r5d.files.Count -eq 1) 'F05d row1-negative: still fires (idle), never silenced'
Assert ($c5d -notmatch 'Subject: \[NEO\] APPROVAL_NEEDED') 'F05d row1-negative: bare authorized/attestation prose does NOT classify row 1'
Assert ($c5d -match 'Subject: \[NEO\] DECISION_NEEDED - ') 'F05d row1-negative: lands as idle DECISION_NEEDED'

# ============ F06: row 5 - genuine END summary => SESSION_END (the ONLY such path) ============
$d6 = Join-Path $scratch 'f06'
$t6 = Join-Path $scratch 't06.jsonl'
Write-Transcript $t6 @(
  (UserStrLine 'wrap up'),
  (AsstTextLine 'm1' ("All slices landed.`n`nSESSION_END: B3H build complete; suite green; ledger updated."))
) $false
$r6 = Invoke-Hook (StopJson $sid $dev $t6) $d6
$c6 = Read-Mail $r6
Assert ($r6.files.Count -eq 1) 'F06 row5: composed'
Assert ($c6 -match 'Subject: \[NEO\] SESSION_END - ') 'F06 row5: SESSION_END class from genuine END summary'
Assert ($c6.Contains('SESSION_END: B3H build complete; suite green; ledger updated.')) 'F06 row5: status line VERBATIM'

# ============ F06b: row 5 NEGATIVE - mid-line 'session end summary' prose is NOT row 5 ============
$d6b = Join-Path $scratch 'f06b'
$t6b = Join-Path $scratch 't06b.jsonl'
Write-Transcript $t6b @(
  (UserStrLine 'wrap the notes'),
  (AsstTextLine 'm1' 'I archived the session end summary to the ledger and recorded the hashes. Standing by.')
) $false
$r6b = Invoke-Hook (StopJson $sid $dev $t6b) $d6b
$c6b = Read-Mail $r6b
Assert ($r6b.files.Count -eq 1) 'F06b row5-negative: composed (idle)'
Assert ($c6b -notmatch 'Subject: \[NEO\] SESSION_END') 'F06b row5-negative: mid-line end-summary prose does NOT hit row 5'
Assert ($c6b -match 'Subject: \[NEO\] DECISION_NEEDED - ') 'F06b row5-negative: lands as idle DECISION_NEEDED'

# ============ F07: row 6 - unclassifiable (no prior user anchor) => DECISION_NEEDED ============
$d7 = Join-Path $scratch 'f07'
$t7 = Join-Path $scratch 't07.jsonl'
Write-Transcript $t7 @(
  (AsstTextLine 'm1' 'Status recorded. Nothing else.')
) $false
$r7 = Invoke-Hook (StopJson $sid $dev $t7) $d7
$c7 = Read-Mail $r7
Assert ($r7.files.Count -eq 1) 'F07 row6: composed (fail-toward-notify)'
Assert ($c7 -match 'Subject: \[NEO\] DECISION_NEEDED - ') 'F07 row6: DECISION_NEEDED class'
Assert ($c7.Contains('(unclassified stop)')) 'F07 row6: (unclassified stop) marker'
Assert ($c7.Contains('Status recorded. Nothing else.')) 'F07 row6: last-line excerpt'

# ============ F08: row 7 - idle after answering Raphael => DECISION_NEEDED ============
$d8 = Join-Path $scratch 'f08'
$t8 = Join-Path $scratch 't08.jsonl'
Write-Transcript $t8 @(
  (UserStrLine 'thanks, that answers it'),
  (AsstTextLine 'm1' 'You are welcome. The registers are documented in the ledger note.')
) $false
$r8 = Invoke-Hook (StopJson $sid $dev $t8) $d8
$c8 = Read-Mail $r8
Assert ($r8.files.Count -eq 1) 'F08 row7: composed (idle now FIRES - inverts r12)'
Assert ($c8 -match 'Subject: \[NEO\] DECISION_NEEDED - ') 'F08 row7: DECISION_NEEDED class'
Assert ($c8.Contains('(session idle - awaiting you)')) 'F08 row7: awaiting-you marker'
Assert ($c8.Contains('You are welcome. The registers are documented in the ledger note.')) 'F08 row7: last-line excerpt'

# ============ F09/F10: the 8-vs-8b PAIR (same status text, without vs with live bg work) ============
$statusText = 'All fixtures green. Residue clean. Standing by.'
$d9 = Join-Path $scratch 'f09'
$t9 = Join-Path $scratch 't09.jsonl'
Write-Transcript $t9 @(
  (AsstToolLine 'm0' 'toolu_fg1' $false),
  (UserToolResultLine 'toolu_fg1'),
  (AsstTextLine 'm1' $statusText)
) $false
$r9 = Invoke-Hook (StopJson $sid $dev $t9) $d9
$c9 = Read-Mail $r9
Assert ($r9.files.Count -eq 1) 'F09 row8: status narration WITHOUT live bg work FIRES'
Assert ($c9 -match 'Subject: \[NEO\] DECISION_NEEDED - ') 'F09 row8: DECISION_NEEDED class'
Assert ($c9.Contains('(session idle)')) 'F09 row8: (session idle) marker'
Assert ($c9.Contains($statusText)) 'F09 row8: last-line excerpt'

$d10 = Join-Path $scratch 'f10'
$t10 = Join-Path $scratch 't10.jsonl'
Write-Transcript $t10 @(
  (AsstToolLine 'm0' 'toolu_bg1' $true),
  (UserToolResultLine 'toolu_bg1'),
  (AsstTextLine 'm1' $statusText)
) $false
$r10 = Invoke-Hook (StopJson $sid $dev $t10) $d10
Assert ($r10.exit -eq 0) 'F10 row8b: exit 0'
Assert ($r10.files.Count -eq 0) 'F10 row8b: SAME status text WITH live bg work => SILENT'

# ============ F11: 8b completion - bg task completed => the same ending FIRES again ============
$d11 = Join-Path $scratch 'f11'
$t11 = Join-Path $scratch 't11.jsonl'
Write-Transcript $t11 @(
  (AsstToolLine 'm0' 'toolu_bg2' $true),
  (UserToolResultLine 'toolu_bg2'),
  (TaskNoteLine 'toolu_bg2'),
  (AsstTextLine 'm1' $statusText)
) $false
$r11 = Invoke-Hook (StopJson $sid $dev $t11) $d11
$c11 = Read-Mail $r11
Assert ($r11.files.Count -eq 1) 'F11 8b-complete: completed bg task no longer silences'
Assert ($c11.Contains('(session idle)')) 'F11 8b-complete: idle class after completion record'

# ============ F10b: row 8b uncertain=>FIRE - blank-id bg start must NOT silence (pin #6) ============
$d10b = Join-Path $scratch 'f10b'
$t10b = Join-Path $scratch 't10b.jsonl'
$noIdTool = JLine @{ type = 'assistant'; isSidechain = $false; message = @{ id = 'm0'; role = 'assistant'; content = @(@{ type = 'tool_use'; name = 'Bash'; input = @{ command = 'echo x'; run_in_background = $true } }) } }
Write-Transcript $t10b @(
  $noIdTool,
  (UserToolResultLine 'toolu_x'),
  (AsstTextLine 'm1' $statusText)
) $false
$r10b = Invoke-Hook (StopJson $sid $dev $t10b) $d10b
$c10b = Read-Mail $r10b
Assert ($r10b.files.Count -eq 1) 'F10b 8b-uncertain: blank-id bg start does NOT silence (uncertain => FIRE)'
Assert ($c10b.Contains('(session idle)')) 'F10b 8b-uncertain: fires as idle DECISION_NEEDED'

# ============ F10c: 8b sidechain scope - sidechain bg start never silences the main session ============
$d10c = Join-Path $scratch 'f10c'
$t10c = Join-Path $scratch 't10c.jsonl'
$scTool = JLine @{ type = 'assistant'; isSidechain = $true; message = @{ id = 'sc0'; role = 'assistant'; content = @(@{ type = 'tool_use'; id = 'toolu_sc1'; name = 'Bash'; input = @{ command = 'echo x'; run_in_background = $true } }) } }
Write-Transcript $t10c @(
  $scTool,
  (UserToolResultLine 'toolu_sc1'),
  (AsstTextLine 'm1' $statusText)
) $false
$r10c = Invoke-Hook (StopJson $sid $dev $t10c) $d10c
$c10c = Read-Mail $r10c
Assert ($r10c.files.Count -eq 1) 'F10c 8b-sidechain: sidechain bg start with no completion does NOT silence the main Stop'
Assert ($c10c.Contains('(session idle)')) 'F10c 8b-sidechain: fires as idle DECISION_NEEDED'

# ============ F12: row 10 - trailing local command / compact => SILENT ============
$d12 = Join-Path $scratch 'f12'
$t12 = Join-Path $scratch 't12.jsonl'
Write-Transcript $t12 @(
  (UserStrLine 'status'),
  (AsstTextLine 'm1' $statusText),
  (UserStrLine ("<command-name>/model</command-name>`n<command-message>model</command-message>`n<command-args></command-args>"))
) $false
$r12 = Invoke-Hook (StopJson $sid $dev $t12) $d12
Assert ($r12.exit -eq 0) 'F12 row10: exit 0'
Assert ($r12.files.Count -eq 0) 'F12 row10: trailing /model local command => SILENT'

$d12b = Join-Path $scratch 'f12b'
$t12b = Join-Path $scratch 't12b.jsonl'
Write-Transcript $t12b @(
  (UserStrLine 'status'),
  (AsstTextLine 'm1' $statusText),
  (JLine @{ type = 'user'; isCompactSummary = $true; message = @{ role = 'user'; content = 'This session is being continued from a previous conversation...' } })
) $false
$r12b = Invoke-Hook (StopJson $sid $dev $t12b) $d12b
Assert ($r12b.files.Count -eq 0) 'F12b row10: trailing /compact summary record => SILENT'

# ============ F13: row 10 - empty/no-op turn (no text blocks) => SILENT ============
$d13 = Join-Path $scratch 'f13'
$t13 = Join-Path $scratch 't13.jsonl'
Write-Transcript $t13 @(
  (AsstTextLine 'm1' 'Prior turn text.'),
  (AsstToolLine 'm2' 'toolu_fg2' $false),
  (UserToolResultLine 'toolu_fg2')
) $false
$r13 = Invoke-Hook (StopJson $sid $dev $t13) $d13
Assert ($r13.exit -eq 0) 'F13 row10: exit 0'
Assert ($r13.files.Count -eq 0) 'F13 row10: last message has no text blocks => SILENT no-op'

# ============ F14: 61B28D5E regression - two DIFFERENT asks, same session => BOTH send ============
$led14 = Join-Path $scratch 'ledger14.jsonl'
$d14a = Join-Path $scratch 'f14a'
$t14a = Join-Path $scratch 't14a.jsonl'
Write-Transcript $t14a @((UserStrLine 'q1'), (AsstTextLine 'm1' 'Do you want the swap now?')) $false
$r14a = Invoke-Hook (StopJson $sid $dev $t14a) $d14a $led14
$d14b = Join-Path $scratch 'f14b'
$t14b = Join-Path $scratch 't14b.jsonl'
Write-Transcript $t14b @((UserStrLine 'q2'), (AsstTextLine 'm2' 'Should the suite rerun tonight?')) $false
$r14b = Invoke-Hook (StopJson $sid $dev $t14b) $d14b $led14
Assert ($r14a.files.Count -eq 1) 'F14 61B28D5E: first distinct ask composes'
Assert ($r14b.files.Count -eq 1) 'F14 61B28D5E: second DIFFERENT ask also composes (same session, <10 min)'
$sent14 = @(Get-LedgerEntries $led14 | Where-Object { $_.outcome -eq 'SENT' })
Assert ($sent14.Count -eq 2) 'F14 61B28D5E: two SENT ledger entries'
Assert ($sent14.Count -eq 2 -and $sent14[0].summary_sha -ne $sent14[1].summary_sha) 'F14 61B28D5E: verbatim asks hash DIFFERENTLY'

# ============ F15: row 9 - IDENTICAL ask twice inside 10 min => second DEDUPED ============
$led15 = Join-Path $scratch 'ledger15.jsonl'
$d15a = Join-Path $scratch 'f15a'
$d15b = Join-Path $scratch 'f15b'
$t15 = Join-Path $scratch 't15.jsonl'
Write-Transcript $t15 @((UserStrLine 'q'), (AsstTextLine 'm1' 'Confirm the promote window, yes or no?')) $false
$r15a = Invoke-Hook (StopJson $sid $dev $t15) $d15a $led15
$r15b = Invoke-Hook (StopJson $sid $dev $t15) $d15b $led15
Assert ($r15a.files.Count -eq 1) 'F15 row9: first identical ask composes'
Assert ($r15b.files.Count -eq 0) 'F15 row9: identical re-ask within 10 min => DEDUPED (module-side)'
$ded15 = @(Get-LedgerEntries $led15 | Where-Object { $_.outcome -eq 'DEDUPED' })
Assert ($ded15.Count -eq 1) 'F15 row9: DEDUPED ledger entry recorded'

# ============ F16: oversized ask - truncation keeps the TAIL + [truncated] marker ============
# GOAL-1 budget (spec 1.2): caller SummaryLines <= 11 = [header][ACTION NEEDED][truncated]
# [7 tail ask lines][working dir]. No name file => fallback name, no Desc line. The ask
# block tail-budget is 7 (Cap 11 - header - action - workdir - 1 for the [truncated] marker).
$d16 = Join-Path $scratch 'f16'
$items = @()
for ($i = 1; $i -le 11; $i++) { $items += ('pending item {0:d2}.' -f $i) }
$items += 'pending item 12 - which option?'
$t16 = Join-Path $scratch 't16.jsonl'
Write-Transcript $t16 @((UserStrLine 'list'), (AsstTextLine 'm1' ("Intro paragraph.`n`n" + ($items -join "`n")))) $false
$r16 = Invoke-Hook (StopJson $sid $dev $t16) $d16
$c16 = Read-Mail $r16
$l16 = Get-MailLines $c16
Assert ($r16.files.Count -eq 1) 'F16 truncation: composed'
Assert ($l16[4] -eq 'Session: DEV-abcd1234 | id abcd1234 | tree: DEV') 'F16 truncation: header is body line 1'
Assert ($l16[5].StartsWith('ACTION NEEDED:')) 'F16 truncation: ACTION NEEDED is body line 2 (always)'
Assert ($l16[6] -eq '[truncated]') 'F16 truncation: [truncated] is its OWN line, immediately after ACTION NEEDED (no Desc)'
Assert (-not $c16.Contains('pending item 05.')) 'F16 truncation: head line NOT kept (budget tightened by ACTION NEEDED)'
Assert ($c16.Contains('pending item 06.')) 'F16 truncation: TAIL starts at item 06 (7 tail lines kept)'
Assert ($c16.Contains('pending item 12 - which option?')) 'F16 truncation: final ask line kept VERBATIM'
# caller summary <= 11: header + action + [truncated] + 7 tail + working dir = 11 body lines
# (module composes them + Evidence + blank + footer within the 12-line body cap)
$bodyLines16 = @($l16[4..($l16.Count - 1)] | Where-Object { $_ -ne '' -and (-not $_.StartsWith('Evidence: ')) -and $_ -ne 'This is a NEO gate notification. Reply is not a channel; answer in the session.' })
Assert ($bodyLines16.Count -le 11) 'F16 truncation: caller SummaryLines <= 11 (module prepend keeps total <= 12)'
Assert ($c16.Contains('Working dir: S:\NEO_dev')) 'F16 truncation: working-dir line ALWAYS last (present)'

# ============ F16b: scan-scope cap - only the last 15 paragraph lines are in scope ============
$d16b = Join-Path $scratch 'f16b'
$rows = @()
for ($i = 1; $i -le 19; $i++) { $rows += ('queue row {0:d2}.' -f $i) }
$rows += 'queue row 20 - approve batch?'
$t16b = Join-Path $scratch 't16b.jsonl'
Write-Transcript $t16b @((UserStrLine 'queue'), (AsstTextLine 'm1' ($rows -join "`n"))) $false
$r16b = Invoke-Hook (StopJson $sid $dev $t16b) $d16b
$c16b = Read-Mail $r16b
Assert ($r16b.files.Count -eq 1) 'F16b scan-cap: composed'
Assert ($c16b.Contains('[truncated]')) 'F16b scan-cap: truncation marker present'
Assert (-not $c16b.Contains('queue row 13.')) 'F16b scan-cap: line outside the kept tail absent (budget tail = 7)'
Assert ($c16b.Contains('queue row 14.')) 'F16b scan-cap: kept tail = last 7 of the capped 15 (GOAL-1 ACTION NEEDED slot)'
Assert ($c16b.Contains('queue row 20 - approve batch?')) 'F16b scan-cap: final line kept'

# ============ F17: non-ASCII ask sanitized to ? ============
$d17 = Join-Path $scratch 'f17'
$t17 = Join-Path $scratch 't17.jsonl'
$eAcute = [string][char]0x00E9
Write-Transcript $t17 @((UserStrLine 'rename'), (AsstTextLine 'm1' ('Confirm the caf' + $eAcute + ' rename now?'))) $false
$r17 = Invoke-Hook (StopJson $sid $dev $t17) $d17
$c17 = Read-Mail $r17
Assert ($r17.files.Count -eq 1) 'F17 sanitize: composed'
Assert ($c17.Contains('Confirm the caf? rename now?')) 'F17 sanitize: non-ASCII -> ?'

# ============ F18: secret-shaped tokens => [masked] ============
$d18 = Join-Path $scratch 'f18'
$t18 = Join-Path $scratch 't18.jsonl'
$secretPara = "Token sk-abcdef1234567890 must rotate.`nAlso AKIA0123456789ABCDEF appeared in logs.`n-----BEGIN RSA PRIVATE KEY----- leaked`nProceed with rotation?"
Write-Transcript $t18 @((UserStrLine 'audit'), (AsstTextLine 'm1' ("Scan results below.`n`n" + $secretPara))) $false
$r18 = Invoke-Hook (StopJson $sid $dev $t18) $d18
$c18 = Read-Mail $r18
Assert ($r18.files.Count -eq 1) 'F18 mask: composed'
Assert ($c18.Contains('[masked]')) 'F18 mask: [masked] present'
Assert (-not $c18.Contains('sk-abcdef1234567890')) 'F18 mask: sk- token absent'
Assert (-not $c18.Contains('AKIA0123456789ABCDEF')) 'F18 mask: AKIA token absent'
Assert (-not $c18.Contains('-----BEGIN RSA PRIVATE KEY-----')) 'F18 mask: BEGIN-block line fully masked'
Assert ($c18.Contains('Proceed with rotation?')) 'F18 mask: non-secret ask line kept VERBATIM'

# ============ F19: malformed / non-assistant transcript => SILENT exit 0 ============
$d19 = Join-Path $scratch 'f19'
$t19 = Join-Path $scratch 't19.jsonl'
[System.IO.File]::WriteAllText($t19, "{{{{not json at all`ngarbage line two`n", (New-Object System.Text.UTF8Encoding($false)))
$r19 = Invoke-Hook (StopJson $sid $dev $t19) $d19
Assert ($r19.exit -eq 0) 'F19 malformed transcript: exit 0'
Assert ($r19.files.Count -eq 0) 'F19 malformed transcript: SILENT'
$d19b = Join-Path $scratch 'f19b'
$t19b = Join-Path $scratch 't19b.jsonl'
Write-Transcript $t19b @((JLine @{ type = 'queue-operation'; operation = 'enqueue' }), (UserStrLine 'only a user prompt')) $false
$r19b = Invoke-Hook (StopJson $sid $dev $t19b) $d19b
Assert ($r19b.files.Count -eq 0) 'F19b no assistant message in tail: SILENT'

# ============ F20: missing / blank transcript path => SILENT exit 0 ============
$d20 = Join-Path $scratch 'f20'
$r20 = Invoke-Hook (StopJson $sid $dev (Join-Path $scratch 'does_not_exist.jsonl')) $d20
Assert ($r20.exit -eq 0) 'F20 missing transcript: exit 0'
Assert ($r20.files.Count -eq 0) 'F20 missing transcript: SILENT'
$d20b = Join-Path $scratch 'f20b'
$r20b = Invoke-Hook (StopJson $sid $dev '') $d20b
Assert ($r20b.files.Count -eq 0) 'F20b blank transcript path: SILENT'

# ============ F21: >256KB transcript, complete last message in tail => MUST FIRE ============
$d21 = Join-Path $scratch 'f21'
$t21 = Join-Path $scratch 't21.jsonl'
$filler = UserStrLine ('filler ' + ('x' * 140))
$big = @()
for ($i = 0; $i -lt 1800; $i++) { $big += $filler }
$big += (UserStrLine 'final gate')
$big += (AsstTextLine 'mBig' ("Everything is staged.`n`nReady to promote B3H - do you approve the swap?"))
Write-Transcript $t21 $big $false
$len21 = (Get-Item -LiteralPath $t21).Length
$r21 = Invoke-Hook (StopJson $sid $dev $t21) $d21
$c21 = Read-Mail $r21
Assert ($len21 -gt 262144) 'F21 tail-read: transcript really exceeds 256KB'
Assert ($r21.files.Count -eq 1) 'F21 tail-read: oversized transcript STILL FIRES (oversized-is-normal)'
Assert ($c21.Contains('Ready to promote B3H - do you approve the swap?')) 'F21 tail-read: ask VERBATIM from the tail'

# ============ F22: prose-only approval/permission mid-message, non-ask ending ============
# Contract v2 rows 7/8 INVERT the old silent pin: this now FIRES as idle, and the class
# pin is DECISION_NEEDED (never APPROVAL_NEEDED from bare prose mentions).
$d22 = Join-Path $scratch 'f22'
$t22 = Join-Path $scratch 't22.jsonl'
Write-Transcript $t22 @(
  (UserStrLine 'how did the refactor go'),
  (AsstTextLine 'm1' ("The approval workflow and permission checks were refactored earlier today.`n`nAll suites are green and the tree is clean."))
) $false
$r22 = Invoke-Hook (StopJson $sid $dev $t22) $d22
$c22 = Read-Mail $r22
Assert ($r22.files.Count -eq 1) 'F22 FP pin: prose-only approval/permission ending FIRES as idle (contract v2)'
Assert ($c22 -match 'Subject: \[NEO\] DECISION_NEEDED - ') 'F22 FP pin: class is DECISION_NEEDED'
Assert ($c22 -notmatch 'Subject: \[NEO\] APPROVAL_NEEDED') 'F22 FP pin: NOT APPROVAL_NEEDED from bare prose'
Assert ($c22.Contains('(session idle - awaiting you)')) 'F22 FP pin: idle marker present'
Assert ($c22 -notmatch 'SESSION_END') 'F22 FP pin: no SESSION_END from a non-END stop (case-4 rewrite)'

# ============ F23: naming fallback chain + tree labels (segment-aware) ============
$d23a = Join-Path $scratch 'f23a'
$t23 = Join-Path $scratch 't23.jsonl'
Write-Transcript $t23 @((UserStrLine 'q'), (AsstTextLine 'm1' ("Fallback check.`n`nWhich option?"))) $false
$r23a = Invoke-Hook (StopJson $sid $dev $t23) $d23a
$c23a = Read-Mail $r23a
$l23a = Get-MailLines $c23a
Assert ($c23a -match 'Subject: \[NEO\] DECISION_NEEDED - DEV-abcd1234') 'F23a naming: no name file => <tree>-<uuid8> fallback (DEV)'
Assert ($l23a.Count -gt 4 -and $l23a[4] -eq 'Session: DEV-abcd1234 | id abcd1234 | tree: DEV') 'F23a naming: fallback body line 1'
$d23b = Join-Path $scratch 'f23b'
$r23b = Invoke-Hook (StopJson $sid 'S:\NEO\subdir' $t23) $d23b
$c23b = Read-Mail $r23b
Assert ($c23b -match 'Subject: \[NEO\] DECISION_NEEDED - PROD-abcd1234') 'F23b naming: S:\NEO\subdir => PROD fallback'
Assert ($c23b.Contains('| tree: PROD')) 'F23b naming: tree label PROD'
$d23c = Join-Path $scratch 'f23c'
$r23c = Invoke-Hook (StopJson $sid 'S:\NEO 5.0\x' $t23) $d23c
$c23c = Read-Mail $r23c
Assert ($c23c -match 'Subject: \[NEO\] DECISION_NEEDED - other-abcd1234') 'F23c naming: S:\NEO 5.0 is NOT PROD (segment-aware)'
$d23d = Join-Path $scratch 'f23d'
$r23d = Invoke-Hook (StopJson $sid 'C:\somewhere\else' $t23) $d23d
$c23d = Read-Mail $r23d
Assert ($c23d.Contains('| tree: other')) 'F23d naming: unrelated cwd => other'

# ============ F24: non-ASCII name file => sanitized; oversized name => capped ============
$d24 = Join-Path $scratch 'f24'
New-Item -ItemType Directory -Force -Path $d24 | Out-Null
Set-NameFile $d24 $sid ('caf' + $eAcute + '-session')
$r24 = Invoke-Hook (StopJson $sid $dev $t23) $d24
$c24 = Read-Mail $r24
Assert ($c24 -match 'Subject: \[NEO\] DECISION_NEEDED - caf--session') 'F24 naming: non-ASCII name sanitized into the module charset'
$d24b = Join-Path $scratch 'f24b'
New-Item -ItemType Directory -Force -Path $d24b | Out-Null
Set-NameFile $d24b $sid ('n' * 100)
$r24b = Invoke-Hook (StopJson $sid $dev $t23) $d24b
$c24b = Read-Mail $r24b
$subj24b = @((Get-MailLines $c24b) | Where-Object { $_.StartsWith('Subject: [NEO] DECISION_NEEDED - ') })
$name24b = ''
if ($subj24b.Count -ge 1) { $name24b = ([string]$subj24b[0]).Substring('Subject: [NEO] DECISION_NEEDED - '.Length) }
Assert ($name24b.Length -eq 60) 'F24b naming: oversized name capped at 60'

# ============ F25: UserPromptSubmit - write-once capture; NEVER sends ============
$d25 = Join-Path $scratch 'f25'
$r25a = Invoke-Hook (UpsJson $sid $dev 'Fix the EMS build slice') $d25
$nf25 = Join-Path (Join-Path $d25 'session_names') ($sid + '.txt')
Assert ($r25a.exit -eq 0) 'F25 UPS: exit 0'
Assert (Test-Path -LiteralPath $nf25) 'F25 UPS: name file created on first prompt'
$nv25 = ''
if (Test-Path -LiteralPath $nf25) { $nv25 = [System.IO.File]::ReadAllText($nf25) }
Assert ($nv25 -eq 'Fix-the-EMS-build-slice') 'F25 UPS: sanitized first-prompt name stored'
Assert ($r25a.files.Count -eq 0) 'F25 UPS: no mail composed'
Assert (-not (Test-Path -LiteralPath $r25a.ledger)) 'F25 UPS: module never invoked (no ledger)'
$r25b = Invoke-Hook (UpsJson $sid $dev 'A totally different second prompt') $d25
$nv25b = [System.IO.File]::ReadAllText($nf25)
Assert ($nv25b -eq 'Fix-the-EMS-build-slice') 'F25 UPS: write-once - second prompt does NOT overwrite'
Assert ($r25b.files.Count -eq 0) 'F25 UPS: second call still sends nothing'
$r25c = Invoke-Hook (StopJson $sid $dev $t23) $d25
$c25c = Read-Mail $r25c
Assert ($c25c -match 'Subject: \[NEO\] DECISION_NEEDED - Fix-the-EMS-build-slice') 'F25 UPS: captured name used by a later send'

# ============ F26: UPS edge cases - blank prompt / blank session / multiline prompt ============
$d26 = Join-Path $scratch 'f26'
$r26a = Invoke-Hook (UpsJson $sid $dev '') $d26
Assert (-not (Test-Path -LiteralPath (Join-Path (Join-Path $d26 'session_names') ($sid + '.txt')))) 'F26 UPS: blank prompt => no file'
$r26b = Invoke-Hook (UpsJson '' $dev 'a prompt') $d26
$snDir26 = Join-Path $d26 'session_names'
$cnt26 = 0
if (Test-Path -LiteralPath $snDir26) { $cnt26 = @(Get-ChildItem -LiteralPath $snDir26 -ErrorAction SilentlyContinue).Count }
Assert ($cnt26 -eq 0) 'F26 UPS: blank session_id => no write at all'
$d26c = Join-Path $scratch 'f26c'
$r26c = Invoke-Hook (UpsJson $sid $dev ("line one`nline two")) $d26c
$nv26c = [System.IO.File]::ReadAllText((Join-Path (Join-Path $d26c 'session_names') ($sid + '.txt')))
Assert ($nv26c -eq 'line-one-line-two') 'F26 UPS: multiline prompt flattened into the charset'

# ============ F27-F31: RETAINED fail-open negatives ============
$d27 = Join-Path $scratch 'f27'
$r27 = Invoke-Hook '{not json at all' $d27
Assert ($r27.exit -eq 0) 'F27 malformed stdin: exit 0'
Assert ($r27.files.Count -eq 0) 'F27 malformed stdin: nothing composed'

$d28 = Join-Path $scratch 'f28'
$r28 = Invoke-Hook '' $d28
Assert ($r28.exit -eq 0) 'F28 empty stdin: exit 0'
Assert ($r28.files.Count -eq 0) 'F28 empty stdin: nothing composed'

$d29 = Join-Path $scratch 'f29'
$r29 = Invoke-Hook '{"hook_event_name":"PreToolUse","message":"x","session_id":"abcd1234efgh"}' $d29
Assert ($r29.exit -eq 0) 'F29 unknown event: exit 0'
Assert ($r29.files.Count -eq 0) 'F29 unknown event: nothing composed'

$d30 = Join-Path $scratch 'f30'
$r30 = Invoke-Hook ('{"hook_event_name":"STOP","session_id":"abcd1234efgh","cwd":"S:\\NEO_dev","transcript_path":' + (ConvertTo-Json $t23) + '}') $d30
Assert ($r30.exit -eq 0) 'F30 case-exact: STOP (wrong case) exit 0'
Assert ($r30.files.Count -eq 0) 'F30 case-exact: STOP (wrong case) does NOT map'
$d30b = Join-Path $scratch 'f30b'
$r30b = Invoke-Hook '{"hook_event_name":"userpromptsubmit","session_id":"abcd1234efgh","prompt":"lower case event"}' $d30b
Assert (-not (Test-Path -LiteralPath (Join-Path $d30b 'session_names'))) 'F30b case-exact: userpromptsubmit (wrong case) writes nothing'

$d31 = Join-Path $scratch 'f31'
# EDIT3: only permission Notifications compose, so the CRLF-injection payload rides a permission message.
$j31 = '{"hook_event_name":"Notification","message":"needs your permission\r\nBcc: attacker@x.y\r\nX: y","session_id":"inj00001","cwd":"S:\\NEO_dev"}'
$r31 = Invoke-Hook $j31 $d31
$c31 = Read-Mail $r31
Assert ($r31.exit -eq 0) 'F31 CRLF injection: exit 0'
Assert ($r31.files.Count -eq 1) 'F31 CRLF injection: composed (permission Notification)'
Assert ($c31 -match 'needs your permission\?\?Bcc: attacker@x\.y\?\?X: y') 'F31 CRLF injection: CRLF neutralized to ?? inline'
Assert ($c31 -notmatch '(?m)^Bcc:') 'F31 CRLF injection: no injected header line'

# ============ F32: lone -LedgerPath seam guard (stub-module sandbox; zero network even
# under regression - the stub, not the real module, would be dot-sourced) ============
$d32 = Join-Path $scratch 'f32'
New-Item -ItemType Directory -Force -Path $d32 | Out-Null
Copy-Item -LiteralPath $HookPath -Destination (Join-Path $d32 'notify_hook.ps1')
$stub = @(
  '# fixture stub standing in for notify_raphael.ps1 - markers only, zero network.',
  '$null = New-Item -ItemType File -Force -Path (Join-Path $PSScriptRoot ''STUB_DOTSOURCED.marker'')',
  'function Send-NeoGateNotification {',
  '  $null = New-Item -ItemType File -Force -Path (Join-Path $PSScriptRoot ''STUB_CALLED.marker'')',
  '  return @{ sent = $false; deduped = $false; refused = $true; reason = ''fixture stub''; composed_path = $null }',
  '}'
)
[System.IO.File]::WriteAllLines((Join-Path $d32 'notify_raphael.ps1'), $stub, [System.Text.Encoding]::ASCII)
$d32ledger = Join-Path $scratch 'lone_ledger.jsonl'
$j32 = '{"hook_event_name":"Notification","message":"seam misuse","session_id":"seam0001"}'
$j32 | & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $d32 'notify_hook.ps1') -LedgerPath $d32ledger | Out-Null
Assert ($LASTEXITCODE -eq 0) 'F32 seam guard: lone -LedgerPath exit 0'
Assert (-not (Test-Path -LiteralPath (Join-Path $d32 'STUB_DOTSOURCED.marker'))) 'F32 seam guard: fired BEFORE any module dot-source'
Assert (-not (Test-Path -LiteralPath (Join-Path $d32 'STUB_CALLED.marker'))) 'F32 seam guard: send function never called'
Assert (-not (Test-Path -LiteralPath $d32ledger)) 'F32 seam guard: no ledger created'

# ============ F33: Notification-path composition retained (with naming) ============
$d33 = Join-Path $scratch 'f33'
New-Item -ItemType Directory -Force -Path $d33 | Out-Null
Set-NameFile $d33 $sid 'b3h-fixture'
$j33 = '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash","session_id":"abcd1234efgh","cwd":"S:\\NEO_dev","transcript_path":"C:\\t\\x.jsonl"}'
$r33 = Invoke-Hook $j33 $d33
$c33 = Read-Mail $r33
$l33 = Get-MailLines $c33
Assert ($r33.files.Count -eq 1) 'F33 Notification: composed'
Assert ($c33 -match 'Subject: \[NEO\] APPROVAL_NEEDED - b3h-fixture') 'F33 Notification: APPROVAL_NEEDED subject with session name'
Assert ($l33.Count -gt 5 -and $l33[4] -eq 'Session: b3h-fixture | id abcd1234 | tree: DEV') 'F33 Notification: Session line is body line 1'
Assert ($l33[5] -eq 'ACTION NEEDED: review + answer the START/approval question in the Claude chat (approve / change / reject).') 'F33 Notification: ACTION NEEDED is body line 2 (GOAL-1)'
Assert ($l33[6] -eq 'Harness friction event: Notification') 'F33 Notification: retained composition ask block after ACTION NEEDED'
Assert ($c33.Contains('Message: Claude needs your permission to use Bash')) 'F33 Notification: message line retained'
Assert ($c33.Contains('Working dir: S:\NEO_dev')) 'F33 Notification: working-dir line retained (ALWAYS last)'
Assert ($c33.Contains('Auto-sent by the settings.json hook adapter (notify_hook.ps1) - no manager action.')) 'F33 Notification: fixed trailer line 1 retained'
Assert ($c33.Contains('The in-chat session is the only decision surface; this mail is a record.')) 'F33 Notification: fixed trailer line 2 retained'
Assert ($c33.Contains('Evidence: C:\t\x.jsonl')) 'F33 Notification: evidence = transcript path'

# ============ F34: EDIT3 - idle Notification (no 'permission') => NO send (exit 0) ============
$led34 = Join-Path $scratch 'ledger34.jsonl'
$d34a = Join-Path $scratch 'f34a'
$d34b = Join-Path $scratch 'f34b'
$j34 = '{"hook_event_name":"Notification","message":"Claude is waiting for your input","session_id":"abcd1234efgh","cwd":"S:\\NEO_dev"}'
$r34a = Invoke-Hook $j34 $d34a $led34
$r34b = Invoke-Hook $j34 $d34b $led34
Assert ($r34a.exit -eq 0) 'F34 idle Notification (no permission): exit 0'
Assert ($r34a.files.Count -eq 0) 'F34 idle Notification (no permission) => NO send (EDIT3 non-permission no-send)'
Assert ($r34b.files.Count -eq 0) 'F34 idle Notification repeat => still NO send'
Assert (-not (Test-Path -LiteralPath $led34)) 'F34 idle Notification: no ledger row written (stood down before any send)'

# ============ F35: >200-char Notification message truncated to exactly 200 ============
# GOAL-1: the Notification ask block is now secret-masked + ASCII + 200-capped like the
# Stop block (A4 "preserve masking on all lines"). Use a long NON-secret-shaped message
# (spaced words) so the cap - not the mask - is what this fixture proves; F35b pins that a
# secret-shaped blob in the SAME message line IS masked (the new masking coverage).
$d35 = Join-Path $scratch 'f35'
# EDIT3: a permission Notification composes; the long spaced tail proves the 200-cap (not the mask).
$long = (('needs your permission ' + ('word ' * 80)).Trim())   # >200 chars, spaced => not a base64 blob
$j35 = '{"hook_event_name":"Notification","message":"' + $long + '","session_id":"long0001","cwd":"S:\\NEO_dev"}'
$r35 = Invoke-Hook $j35 $d35
$c35 = Read-Mail $r35
Assert ($r35.files.Count -eq 1) 'F35 cap: composed (module did not refuse an over-cap line)'
$msgLine = ''
foreach ($ln in (Get-MailLines $c35)) { if ($ln.StartsWith('Message: ')) { $msgLine = $ln } }
Assert ($msgLine.Length -eq 200) 'F35 cap: message line truncated to exactly 200 chars'

# ============ F35b: GOAL-1 - Notification ask block is now secret-masked too ============
$d35b = Join-Path $scratch 'f35b'
# EDIT3: secret rides a permission Notification so the ask-block masking path is exercised.
$j35b = '{"hook_event_name":"Notification","message":"needs your permission key sk-abcdef1234567890 leaked here","session_id":"long0002","cwd":"S:\\NEO_dev"}'
$r35b = Invoke-Hook $j35b $d35b
$c35b = Read-Mail $r35b
Assert ($r35b.files.Count -eq 1) 'F35b mask: composed'
Assert ($c35b.Contains('[masked]')) 'F35b mask: secret-shaped token in the Notification message masked (ask block masking now applies both paths)'
Assert (-not $c35b.Contains('sk-abcdef1234567890')) 'F35b mask: sk- token absent from the Notification mail'

# ================= GOAL-1 BUILD (notify-tracker-ux) NEW FIXTURES =================
# Helpers for the new cases: a name file with an explicit LINE-2 description, a Stop
# transcript whose PRIOR-USER entry carries a top-level 'timestamp' (T_open), and a
# ledger SENT-row seeder for the double-fire backstop.
function Set-NameFile2([string]$CaseDir, [string]$sid, [string]$name, [string]$desc) {
  $d = Join-Path $CaseDir 'session_names'
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $d ($sid + '.txt')), ($name + "`n" + $desc), (New-Object System.Text.UTF8Encoding($true)))
}
function UserStrLineTs([string]$s, [string]$ts) {
  return (JLine @{ type = 'user'; timestamp = $ts; message = @{ role = 'user'; content = $s } })
}
function Seed-LedgerSent([string]$Ledger, [string]$Slice, [string]$Gate, [string]$Ts, [string]$Sha = 'seedsha') {
  $dir = Split-Path -Parent $Ledger
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $row = (ConvertTo-Json -InputObject @{ ts = $Ts; gate = $Gate; slice = $Slice; summary_sha = $Sha; outcome = 'SENT' } -Compress)
  Add-Content -LiteralPath $Ledger -Value $row -Encoding Ascii
}

# ---- F40: ACTION NEEDED line, one per attested gate class (spec sec 1.3) ----
$actionMap = @{
  'APPROVAL_NEEDED' = @{ text = "ready`n`nSTART approval: proceed?"; act = 'ACTION NEEDED: review + answer the START/approval question in the Claude chat (approve / change / reject).' }
  'DECISION_NEEDED' = @{ text = "analysis`n`nWhich option, A or B?"; act = 'ACTION NEEDED: answer the question in the Claude chat.' }
  'SESSION_END'     = @{ text = "wrap`n`nSESSION_END: build complete; suite green."; act = 'ACTION NEEDED: give the END verdict in chat - keep / iterate / toss.' }
  'ESCALATION_STOP' = @{ text = "log`n`nBREAKER TRIP: slice 2 parked."; act = 'ACTION NEEDED: session PARKED - inspect the reason + tell it how to proceed.' }
}
$fi = 0
foreach ($cls in @('APPROVAL_NEEDED','DECISION_NEEDED','SESSION_END','ESCALATION_STOP')) {
  $fi++
  $dd = Join-Path $scratch ('f40_' + $fi)
  $tt = Join-Path $scratch ('t40_' + $fi + '.jsonl')
  Write-Transcript $tt @((UserStrLine 'go'), (AsstTextLine 'm1' $actionMap[$cls].text)) $false
  $rr = Invoke-Hook (StopJson $sid $dev $tt) $dd
  $cc = Read-Mail $rr
  $ll = Get-MailLines $cc
  Assert ($rr.files.Count -eq 1) ('F40 action ' + $cls + ': composed')
  Assert ($cc -match ('Subject: \[NEO\] ' + $cls + ' - ')) ('F40 action ' + $cls + ': class')
  Assert ($ll.Count -gt 5 -and $ll[5] -eq $actionMap[$cls].act) ('F40 action ' + $cls + ': ACTION NEEDED line is body line 2, exact')
}

# ---- F41: Desc from sidecar LINE 2 (spec 3.1 + addendum D2) ----
$d41 = Join-Path $scratch 'f41'
Set-NameFile2 $d41 $sid 'named-sess' 'a crisp one-line description'
$t41 = Join-Path $scratch 't41.jsonl'
Write-Transcript $t41 @((UserStrLine 'go'), (AsstTextLine 'm1' ("plan`n`nWhich option?"))) $false
$r41 = Invoke-Hook (StopJson $sid $dev $t41) $d41
$c41 = Read-Mail $r41
$l41 = Get-MailLines $c41
Assert ($r41.files.Count -eq 1) 'F41 desc: composed'
Assert ($c41 -match 'Subject: \[NEO\] DECISION_NEEDED - named-sess') 'F41 desc: name from sidecar line 1'
Assert ($l41[6] -eq 'Desc: a crisp one-line description') 'F41 desc: Desc line from sidecar line 2 (after header + ACTION NEEDED)'

# ---- F42: sidecar precedence over auto-capture (D2) - a pre-existing name file is NOT
# clobbered by a first prompt, and its name+desc are what the later Stop mail uses ----
$d42 = Join-Path $scratch 'f42'
Set-NameFile2 $d42 $sid 'sidecar-wins' 'sidecar description'
$r42u = Invoke-Hook (UpsJson $sid $dev 'a totally different first prompt') $d42
$nf42 = Join-Path (Join-Path $d42 'session_names') ($sid + '.txt')
$nv42 = [System.IO.File]::ReadAllText($nf42)
Assert ($nv42 -eq ("sidecar-wins`nsidecar description")) 'F42 precedence: UserPromptSubmit did NOT overwrite the manager sidecar (write-once-when-absent)'
$t42 = Join-Path $scratch 't42.jsonl'
Write-Transcript $t42 @((UserStrLine 'go'), (AsstTextLine 'm1' ("x`n`nWhich?"))) $false
$r42 = Invoke-Hook (StopJson $sid $dev $t42) $d42
$c42 = Read-Mail $r42
Assert ($c42 -match 'Subject: \[NEO\] DECISION_NEEDED - sidecar-wins') 'F42 precedence: Stop mail uses the manager sidecar name'
Assert ($c42.Contains('Desc: sidecar description')) 'F42 precedence: Stop mail uses the manager sidecar description'

# ---- F43: capture REJECT-FILTER on raw AND sanitized candidates (spec 3.2 + D3) ----
# Each rejected candidate => NO name file written => the later mail uses <tree>-<uuid8>.
$rejects = @{
  'banner'        = 'Windows PowerShell`nCopyright (C) Microsoft Corporation. All rights reserved.'
  'sanit-banner'  = 'Windows-PowerShell-Copyright--C--Microsoft-Corporation.-All-'
  'one-char'      = 'A'
  'commissioning' = 'You are a fresh NEO manager. MISSION: drive the EMS run.'
  'code-paste'    = 'param($x)'
}
$fj = 0
foreach ($key in $rejects.Keys) {
  $fj++
  $sidR = ('rej0000' + $fj)
  $dR = Join-Path $scratch ('f43_' + $fj)
  $prompt = ($rejects[$key] -replace '`n', "`n")
  Invoke-Hook (UpsJson $sidR $dev $prompt) $dR | Out-Null
  $nfR = Join-Path (Join-Path $dR 'session_names') ($sidR + '.txt')
  Assert (-not (Test-Path -LiteralPath $nfR)) ('F43 reject ' + $key + ': candidate REJECTED, no name file written (clean fallback)')
}
# ACCEPT: multi-char word-like single-token slugs (D3) - ems005, neo49
$accepts = @{ 'ems005' = 'ems005'; 'neo49' = 'neo49'; 'slug' = 'notify-tracker-ux' }
$fk = 0
foreach ($key in $accepts.Keys) {
  $fk++
  $sidA = ('acc0000' + $fk)
  $dA = Join-Path $scratch ('f43a_' + $fk)
  Invoke-Hook (UpsJson $sidA $dev $accepts[$key]) $dA | Out-Null
  $nfA = Join-Path (Join-Path $dA 'session_names') ($sidA + '.txt')
  $ok = (Test-Path -LiteralPath $nfA)
  $val = ''
  if ($ok) { $val = [System.IO.File]::ReadAllText($nfA) }
  Assert ($ok -and ($val -eq $accepts[$key])) ('F43 accept ' + $key + ': multi-char single-token slug ACCEPTED + stored')
}

# ---- F44: Desc is the FIRST casualty under truncation (spec 1.2 priority) ----
$d44 = Join-Path $scratch 'f44'
Set-NameFile2 $d44 $sid 'trunc-sess' 'this description is dropped first when over budget'
$items44 = @(); for ($i = 1; $i -le 11; $i++) { $items44 += ('row {0:d2}.' -f $i) }
$items44 += 'row 12 - approve?'
$t44 = Join-Path $scratch 't44.jsonl'
Write-Transcript $t44 @((UserStrLine 'list'), (AsstTextLine 'm1' ("intro`n`n" + ($items44 -join "`n")))) $false
$r44 = Invoke-Hook (StopJson $sid $dev $t44) $d44
$c44 = Read-Mail $r44
Assert ($r44.files.Count -eq 1) 'F44 desc-casualty: composed'
Assert (-not $c44.Contains('Desc: this description is dropped first')) 'F44 desc-casualty: Desc DROPPED first when the ask block is over budget'
Assert ($c44.Contains('[truncated]')) 'F44 desc-casualty: ask block still tail-trimmed with the marker'
Assert ($c44.Contains('row 12 - approve?')) 'F44 desc-casualty: final ask line kept'

# ---- F45: double-fire backstop - SAME-class row with ts >= T_open => hook SKIPS ----
$led45 = Join-Path $scratch 'ledger45.jsonl'
$d45 = Join-Path $scratch 'f45'
Set-NameFile $d45 $sid 'dfsess'
$tOpen45 = '2026-07-09T10:00:00.0000000Z'
$t45 = Join-Path $scratch 't45.jsonl'
Write-Transcript $t45 @((UserStrLineTs 'go' $tOpen45), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
# a manager SENT row for the SAME slice + SAME class (DECISION_NEEDED) INSIDE this turn
Seed-LedgerSent $led45 'dfsess' 'DECISION_NEEDED' '2026-07-09T10:00:05.0000000Z'
$r45 = Invoke-Hook (StopJson $sid $dev $t45) $d45 $led45
Assert ($r45.exit -eq 0) 'F45 double-fire: exit 0'
Assert ($r45.files.Count -eq 0) 'F45 double-fire: same-class row ts>=T_open => hook SUPPRESSES its own send (one mail)'
# and it wrote NO ledger row (read-only suppression - D1: no new live write surface)
$after45 = @(Get-LedgerEntries $led45)
Assert ($after45.Count -eq 1) 'F45 double-fire: hook wrote NO ledger row (read-only suppression, only the seeded SENT remains)'

# ---- F46: EARLIER-turn same-class row (ts < T_open) => hook STILL fires ----
$led46 = Join-Path $scratch 'ledger46.jsonl'
$d46 = Join-Path $scratch 'f46'
Set-NameFile $d46 $sid 'dfsess'
$tOpen46 = '2026-07-09T11:00:00.0000000Z'
$t46 = Join-Path $scratch 't46.jsonl'
Write-Transcript $t46 @((UserStrLineTs 'go' $tOpen46), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
Seed-LedgerSent $led46 'dfsess' 'DECISION_NEEDED' '2026-07-09T10:55:00.0000000Z'   # BEFORE T_open
$r46 = Invoke-Hook (StopJson $sid $dev $t46) $d46 $led46
Assert ($r46.files.Count -eq 1) 'F46 double-fire: earlier-turn same-class row (ts<T_open) => hook STILL fires (distinct gate not dropped)'

# ---- F47: gate-open PAIR this turn => hook SUPPRESSES (contract v2 FIX 1). A manager
# APPROVAL_NEEDED SENT row + the hook classifying DECISION_NEEDED (or vice-versa) are the
# SAME logical "a gate is open" event; the {APPROVAL_NEEDED,DECISION_NEEDED} equivalence
# set collapses them to ONE mail. (Superseded the pre-fix expectation that a distinct class
# always fired - only DISTINCT-PURPOSE classes now fire; see C4/F49-F50 for SESSION_END.) ----
$led47 = Join-Path $scratch 'ledger47.jsonl'
$d47 = Join-Path $scratch 'f47'
Set-NameFile $d47 $sid 'dfsess'
$tOpen47 = '2026-07-09T12:00:00.0000000Z'
$t47 = Join-Path $scratch 't47.jsonl'
Write-Transcript $t47 @((UserStrLineTs 'go' $tOpen47), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
Seed-LedgerSent $led47 'dfsess' 'APPROVAL_NEEDED' '2026-07-09T12:00:05.0000000Z'   # gate-open pair member
$r47 = Invoke-Hook (StopJson $sid $dev $t47) $d47 $led47
Assert ($r47.files.Count -eq 0) 'F47 double-fire: gate-open pair this turn (APPROVAL_NEEDED row + DECISION_NEEDED hook) => SUPPRESSED (contract v2 equivalence set)'
$after47 = @(Get-LedgerEntries $led47)
Assert ($after47.Count -eq 1) 'F47 double-fire: read-only suppression - only the seeded SENT row remains'

# ---- F48: unresolvable / absent T_open => hook fires (fail-toward-mail) ----
$led48 = Join-Path $scratch 'ledger48.jsonl'
$d48 = Join-Path $scratch 'f48'
Set-NameFile $d48 $sid 'dfsess'
# prior-user entry has NO timestamp field => T_open unresolvable
$t48 = Join-Path $scratch 't48.jsonl'
Write-Transcript $t48 @((UserStrLine 'go'), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
Seed-LedgerSent $led48 'dfsess' 'DECISION_NEEDED' '2026-07-09T13:00:05.0000000Z'   # would match if T_open resolved
$r48 = Invoke-Hook (StopJson $sid $dev $t48) $d48 $led48
Assert ($r48.files.Count -eq 1) 'F48 double-fire: unresolvable T_open (no prior-user timestamp) => hook FIRES (fail-toward-mail)'
# malformed T_open likewise fires
$led48b = Join-Path $scratch 'ledger48b.jsonl'
$d48b = Join-Path $scratch 'f48b'
Set-NameFile $d48b $sid 'dfsess'
$t48b = Join-Path $scratch 't48b.jsonl'
Write-Transcript $t48b @((UserStrLineTs 'go' 'not-a-timestamp'), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
Seed-LedgerSent $led48b 'dfsess' 'DECISION_NEEDED' '2026-07-09T14:00:05.0000000Z'
$r48b = Invoke-Hook (StopJson $sid $dev $t48b) $d48b $led48b
Assert ($r48b.files.Count -eq 1) 'F48b double-fire: malformed T_open => hook FIRES (fail-toward-mail)'

# ================= ITERATE-1: REAL-TRANSCRIPT-SHAPE double-fire pins =================
# The prior build passed F45-F48 but FAILED the LIVE proof: in a REAL Claude Code transcript
# tool_result entries are type=='user' too, so the "newest user entry before the final
# assistant" was a TOOL_RESULT timestamped ~now, not the turn-opener. These four cases model
# that real shape so the defect can never regress. Builders JLine/UserStrLineTs/UserToolResultLine/
# AsstToolLine/AsstTextLine/TaskNoteLine/Seed-LedgerSent already exist above.

# a real-shape transcript: [user HUMAN str ts=T0] [assistant tool_use ts=T1]
# [user TOOL_RESULT ts=T2] [assistant tool_use ts=T3] [user TOOL_RESULT ts=T4]
# [assistant FINAL text ts=T5], T0<T1<T2<T3<T4<T5. TOOL_RESULT entries carry a top-level
# timestamp (as the real harness records them) to prove the fix does not simply pick "the one
# with a timestamp" but genuinely SKIPS tool_results and anchors on the human opener.
function AsstToolLineTs([string]$mid, [string]$tuid, [string]$ts) {
  return (JLine @{ type = 'assistant'; isSidechain = $false; timestamp = $ts; message = @{ id = $mid; role = 'assistant'; content = @(@{ type = 'tool_use'; id = $tuid; name = 'Bash'; input = @{ command = 'echo x' } }) } })
}
function UserToolResultLineTs([string]$tuid, [string]$ts) {
  return (JLine @{ type = 'user'; timestamp = $ts; message = @{ role = 'user'; content = @(@{ type = 'tool_result'; tool_use_id = $tuid; content = 'ok' }) } })
}
function AsstTextLineTs([string]$mid, [string]$text, [string]$ts) {
  return (JLine @{ type = 'assistant'; isSidechain = $false; timestamp = $ts; message = @{ id = $mid; role = 'assistant'; content = @(@{ type = 'text'; text = $text }) } })
}
function New-RealShapeTranscript([string]$Path, [string]$Final,
    [string]$T0, [string]$T1, [string]$T2, [string]$T3, [string]$T4, [string]$T5) {
  Write-Transcript $Path @(
    (UserStrLineTs 'drive the run' $T0),
    (AsstToolLineTs 'm0' 'toolu_r1' $T1),
    (UserToolResultLineTs 'toolu_r1' $T2),
    (AsstToolLineTs 'm0' 'toolu_r2' $T3),
    (UserToolResultLineTs 'toolu_r2' $T4),
    (AsstTextLineTs 'm1' $Final $T5)
  ) $false
}

# ---- F49: THE REGRESSION PIN. Manager mailed EARLY in this turn (T0 < Tm < T2), BEFORE the
# first tool_result. OLD code anchored T_open=T2 (the tool_result) => managerRowTs(Tm) < T2 =>
# NOT suppressed => two mails (the live defect). FIXED code anchors T_open=T0 (the human
# opener) => Tm >= T0 => SUPPRESS (one mail). Uses a GATE-OPEN class (DECISION_NEEDED) so the
# {APPROVAL_NEEDED,DECISION_NEEDED} equivalence-set collapse (contract v2 FIX 1) applies; a
# distinct-PURPOSE SESSION_END would NOT collapse (proven separately in C4). ----
$led49 = Join-Path $scratch 'ledger49.jsonl'
$d49 = Join-Path $scratch 'f49'
Set-NameFile $d49 $sid 'dfsess'
$finalGate = "Analysis complete.`n`nWhich promote window do you want, A or B?"
$t49_path = Join-Path $scratch 't49.jsonl'
New-RealShapeTranscript $t49_path $finalGate `
  '2026-07-09T18:31:09.900Z' '2026-07-09T18:31:09.940Z' '2026-07-09T18:31:09.974Z' `
  '2026-07-09T18:31:10.010Z' '2026-07-09T18:31:10.050Z' '2026-07-09T18:31:10.090Z'
# manager SENT row: SAME root + gate-open class (APPROVAL_NEEDED pairs with the hook's
# DECISION_NEEDED), ts BETWEEN T0 and the first tool_result T2 (manager mailed early in the
# turn). Under OLD logic (T_open=T2) Tm < T_open => FIRE; under the fix (T_open=T0) Tm >= T_open
# AND both classes in the gate-open set => SUPPRESS.
Seed-LedgerSent $led49 'dfsess' 'APPROVAL_NEEDED' '2026-07-09T18:31:09.930Z'
$r49 = Invoke-Hook (StopJson $sid $dev $t49_path) $d49 $led49
Assert ($r49.exit -eq 0) 'F49 real-shape regression: exit 0'
Assert ($r49.files.Count -eq 0) 'F49 real-shape regression: tool_results skipped => T_open=human opener => gate-open manager row in-turn => SUPPRESS (one mail). FAILS on old logic (T_open=tool_result), PASSES on the fix.'
$after49 = @(Get-LedgerEntries $led49)
Assert ($after49.Count -eq 1) 'F49 real-shape regression: read-only suppression - only the seeded SENT row remains (hook wrote nothing)'

# ---- F50: same real shape, but the manager row is from an EARLIER turn (Te < T0) => the hook
# STILL fires (a distinct earlier-turn gate is never dropped), even for a gate-open class. ----
$led50 = Join-Path $scratch 'ledger50.jsonl'
$d50 = Join-Path $scratch 'f50'
Set-NameFile $d50 $sid 'dfsess'
$t50_path = Join-Path $scratch 't50.jsonl'
New-RealShapeTranscript $t50_path $finalGate `
  '2026-07-09T18:40:00.000Z' '2026-07-09T18:40:00.100Z' '2026-07-09T18:40:00.200Z' `
  '2026-07-09T18:40:00.300Z' '2026-07-09T18:40:00.400Z' '2026-07-09T18:40:00.500Z'
Seed-LedgerSent $led50 'dfsess' 'APPROVAL_NEEDED' '2026-07-09T18:35:00.000Z'   # EARLIER turn (< T0)
$r50 = Invoke-Hook (StopJson $sid $dev $t50_path) $d50 $led50
Assert ($r50.files.Count -eq 1) 'F50 real-shape earlier-turn: manager row ts<T0 (T_open) => hook STILL fires (earlier gate not dropped, even gate-open class)'

# ---- F51: a turn OPENED by a <task-notification> user entry (content string starting with
# '<') with a valid timestamp - it STILL anchors T_open (NOT skipped; only tool_results are the
# pollutant). A manager row after it (>= T_open) suppresses. ----
$led51 = Join-Path $scratch 'ledger51.jsonl'
$d51 = Join-Path $scratch 'f51'
Set-NameFile $d51 $sid 'dfsess'
$taskNoteOpener = "<task-notification>`n<task-id>t1</task-id>`n<tool-use-id>toolu_bg</tool-use-id>`n<status>completed</status>`n</task-notification>"
$t51 = Join-Path $scratch 't51.jsonl'
Write-Transcript $t51 @(
  (UserStrLineTs $taskNoteOpener '2026-07-09T19:00:00.000Z'),
  (AsstToolLineTs 'm0' 'toolu_s1' '2026-07-09T19:00:00.100Z'),
  (UserToolResultLineTs 'toolu_s1' '2026-07-09T19:00:00.200Z'),
  (AsstTextLineTs 'm1' ("plan`n`nWhich option, A or B?") '2026-07-09T19:00:00.300Z')
) $false
# manager row after the task-notification opener (>= T_open) => suppress
Seed-LedgerSent $led51 'dfsess' 'DECISION_NEEDED' '2026-07-09T19:00:00.050Z'
$r51 = Invoke-Hook (StopJson $sid $dev $t51) $d51 $led51
Assert ($r51.files.Count -eq 0) 'F51 task-notification opener: a <task-notification> user entry STILL anchors T_open (not skipped) => manager row after it SUPPRESSES'

# ---- F52: a transcript whose ONLY user entries before the final assistant are tool_results
# (no genuine opener) => T_open null => hook FIRES (fail-toward-mail). ----
$led52 = Join-Path $scratch 'ledger52.jsonl'
$d52 = Join-Path $scratch 'f52'
Set-NameFile $d52 $sid 'dfsess'
$t52 = Join-Path $scratch 't52.jsonl'
Write-Transcript $t52 @(
  (AsstToolLineTs 'm0' 'toolu_o1' '2026-07-09T20:00:00.100Z'),
  (UserToolResultLineTs 'toolu_o1' '2026-07-09T20:00:00.200Z'),
  (AsstToolLineTs 'm0' 'toolu_o2' '2026-07-09T20:00:00.300Z'),
  (UserToolResultLineTs 'toolu_o2' '2026-07-09T20:00:00.400Z'),
  (AsstTextLineTs 'm1' ("plan`n`nWhich option, A or B?") '2026-07-09T20:00:00.500Z')
) $false
Seed-LedgerSent $led52 'dfsess' 'DECISION_NEEDED' '2026-07-09T20:00:00.450Z'   # would match if T_open resolved
$r52 = Invoke-Hook (StopJson $sid $dev $t52) $d52 $led52
Assert ($r52.files.Count -eq 1) 'F52 only-tool_results: no genuine opener => T_open null => hook FIRES (fail-toward-mail)'

# ================= NOTIFY-DOUBLEFIRE-FIX (contract v2) NEW CASES =================
# C1-C6 + REJECT from the v2 test_plan. These exercise: FIX 1 (gate-open equivalence-set
# collapse across a DISTINCT class in the pair), FIX 2 (set_session_name.ps1 reconciling
# the sidecar onto <session_id>.txt so hook + manager share one root), and the tightened
# reject filter. The helper is invoked in a child powershell.exe with an EXPLICIT -SessionId
# + a scratch -NamesDir seam (zero-write against the real dir; the F36 assertion still holds).
$helperPath = Join-Path (Split-Path $HookPath -Parent) 'set_session_name.ps1'
Assert (Test-Path -LiteralPath $helperPath) 'DFX helper: set_session_name.ps1 present beside the hook'
function Invoke-SetName {
  param([string]$Name, [string]$Desc, [string]$SessionId, [string]$TranscriptPath, [string]$NamesDir)
  $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$helperPath,'-Name',$Name)
  if ($PSBoundParameters.ContainsKey('Desc'))           { $a += @('-Desc',$Desc) }
  if ($PSBoundParameters.ContainsKey('SessionId'))       { $a += @('-SessionId',$SessionId) }
  if ($PSBoundParameters.ContainsKey('TranscriptPath'))  { $a += @('-TranscriptPath',$TranscriptPath) }
  if ($PSBoundParameters.ContainsKey('NamesDir'))        { $a += @('-NamesDir',$NamesDir) }
  # Capture the child's STDOUT only; route STDERR to a scratch file so a fail-closed refusal
  # (which writes to stderr and exits non-zero) never trips this suite's ErrorActionPreference
  # Stop as a NativeCommandError. The exit code is the authority the helper contract exposes.
  $errFile = Join-Path $scratch ('setname_err_' + [guid]::NewGuid().ToString('N') + '.txt')
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $psExe @a 2>$errFile
  } finally { $ErrorActionPreference = $prev }
  return @{ exit = $LASTEXITCODE; out = ([string]($out -join "`n")).Trim() }
}

# ---- C1: manager APPROVAL_NEEDED SENT row + hook classifies DECISION_NEEDED (DISTINCT class,
# same root, ts >= T_open) => hook SUPPRESSES => exactly ONE row after the turn ----
$ledC1 = Join-Path $scratch 'ledgerC1.jsonl'
$dC1 = Join-Path $scratch 'c1'
Set-NameFile $dC1 $sid 'dfx-c1'
$tOpenC1 = '2026-07-09T09:00:00.0000000Z'
$tC1 = Join-Path $scratch 'tC1.jsonl'
Write-Transcript $tC1 @((UserStrLineTs 'go' $tOpenC1), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
Seed-LedgerSent $ledC1 'dfx-c1' 'APPROVAL_NEEDED' '2026-07-09T09:00:05.0000000Z'   # manager gate-open row (distinct class)
$rC1 = Invoke-Hook (StopJson $sid $dev $tC1) $dC1 $ledC1
Assert ($rC1.exit -eq 0) 'C1 gate-open collapse: exit 0'
Assert ($rC1.files.Count -eq 0) 'C1 gate-open collapse: APPROVAL_NEEDED row + DECISION_NEEDED hook, same root, ts>=T_open => hook SUPPRESSES (no second mail)'
$afterC1 = @(Get-LedgerEntries $ledC1)
Assert ($afterC1.Count -eq 1) 'C1 gate-open collapse: exactly ONE ledger row after the turn (read-only suppression)'

# ---- C1b: session-ROOT match across a '-START'/'-END' suffix mismatch (FIX 1 root strip).
# Manager row slice 'dfx-c1b-START', hook resolves 'dfx-c1b' => roots match => collapse. ----
$ledC1b = Join-Path $scratch 'ledgerC1b.jsonl'
$dC1b = Join-Path $scratch 'c1b'
Set-NameFile $dC1b $sid 'dfx-c1b'
$tOpenC1b = '2026-07-09T09:10:00.0000000Z'
$tC1b = Join-Path $scratch 'tC1b.jsonl'
Write-Transcript $tC1b @((UserStrLineTs 'go' $tOpenC1b), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
Seed-LedgerSent $ledC1b 'dfx-c1b-START' 'DECISION_NEEDED' '2026-07-09T09:10:05.0000000Z'
$rC1b = Invoke-Hook (StopJson $sid $dev $tC1b) $dC1b $ledC1b
Assert ($rC1b.files.Count -eq 0) 'C1b root-strip: row slice ...-START vs hook root ... => roots match => SUPPRESS'

# ---- C2: <uuid>.txt holds a JUNK auto-capture; after set_session_name.ps1 runs (explicit
# -SessionId + scratch -NamesDir), the hook's resolved subject shows the friendly name AND
# the hook slice root == the manager row root => ONE mail ----
$dC2 = Join-Path $scratch 'c2'
New-Item -ItemType Directory -Force -Path (Join-Path $dC2 'session_names') | Out-Null
$namesC2 = Join-Path $dC2 'session_names'
# pre-existing junk auto-capture keyed by the session_id
[System.IO.File]::WriteAllText((Join-Path $namesC2 ($sid + '.txt')), '1-approve--2-include', [System.Text.Encoding]::ASCII)
$setC2 = Invoke-SetName -Name 'dfx-friendly' -Desc 'reconciled by manager' -SessionId $sid -NamesDir $namesC2
Assert ($setC2.exit -eq 0) 'C2 reconcile: helper exit 0 with explicit -SessionId + scratch -NamesDir'
$tC2 = Join-Path $scratch 'tC2.jsonl'
Write-Transcript $tC2 @((UserStrLine 'go'), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
$rC2 = Invoke-Hook (StopJson $sid $dev $tC2) $dC2
$cC2 = Read-Mail $rC2
Assert ($rC2.files.Count -eq 1) 'C2 reconcile: hook composes one mail'
Assert ($cC2 -match 'Subject: \[NEO\] DECISION_NEEDED - dfx-friendly') 'C2 reconcile: subject shows the friendly name written by the helper (not the junk auto-capture)'
Assert ($cC2.Contains('Desc: reconciled by manager')) 'C2 reconcile: helper LINE-2 desc surfaces as the Desc line'

# ---- C3: T_open null (missing prior-user timestamp) => hook STILL fires (fail-open) even
# with a same-root same-class SENT row present ----
$ledC3 = Join-Path $scratch 'ledgerC3.jsonl'
$dC3 = Join-Path $scratch 'c3'
Set-NameFile $dC3 $sid 'dfx-c3'
$tC3 = Join-Path $scratch 'tC3.jsonl'
Write-Transcript $tC3 @((UserStrLine 'go'), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false   # NO timestamp on opener
Seed-LedgerSent $ledC3 'dfx-c3' 'DECISION_NEEDED' '2026-07-09T09:30:05.0000000Z'   # would match if T_open resolved
$rC3 = Invoke-Hook (StopJson $sid $dev $tC3) $dC3 $ledC3
Assert ($rC3.files.Count -eq 1) 'C3 null T_open: unresolvable turn boundary => hook FIRES (fail-open), never suppressed'

# ---- C4: same-root, same-turn, DISTINCT-PURPOSE class - a prior APPROVAL_NEEDED SENT row +
# the hook classifying SESSION_END => NOT collapsed => hook still sends (two rows) ----
$ledC4 = Join-Path $scratch 'ledgerC4.jsonl'
$dC4 = Join-Path $scratch 'c4'
Set-NameFile $dC4 $sid 'dfx-c4'
$tOpenC4 = '2026-07-09T09:40:00.0000000Z'
$tC4 = Join-Path $scratch 'tC4.jsonl'
Write-Transcript $tC4 @((UserStrLineTs 'go' $tOpenC4), (AsstTextLine 'm1' ("wrap`n`nSESSION_END: build complete; suite green."))) $false
Seed-LedgerSent $ledC4 'dfx-c4' 'APPROVAL_NEEDED' '2026-07-09T09:40:05.0000000Z'   # gate-open pair member, but hook is SESSION_END
$rC4 = Invoke-Hook (StopJson $sid $dev $tC4) $dC4 $ledC4
$cC4 = Read-Mail $rC4
Assert ($rC4.files.Count -eq 1) 'C4 distinct-purpose: APPROVAL_NEEDED row + SESSION_END hook => NOT collapsed => hook still sends'
Assert ($cC4 -match 'Subject: \[NEO\] SESSION_END - dfx-c4') 'C4 distinct-purpose: hook fires its own SESSION_END class'
$sentC4 = @(Get-LedgerEntries $ledC4 | Where-Object { $_.outcome -eq 'SENT' })
Assert ($sentC4.Count -eq 2) 'C4 distinct-purpose: two SENT rows (seeded APPROVAL_NEEDED + hook SESSION_END)'
# and the ESCALATION_STOP variant likewise does not collapse
$ledC4b = Join-Path $scratch 'ledgerC4b.jsonl'
$dC4b = Join-Path $scratch 'c4b'
Set-NameFile $dC4b $sid 'dfx-c4'
$tC4b = Join-Path $scratch 'tC4b.jsonl'
Write-Transcript $tC4b @((UserStrLineTs 'go' $tOpenC4), (AsstTextLine 'm1' ("log`n`nBREAKER TRIP: slice 2 parked."))) $false
Seed-LedgerSent $ledC4b 'dfx-c4' 'DECISION_NEEDED' '2026-07-09T09:40:05.0000000Z'
$rC4b = Invoke-Hook (StopJson $sid $dev $tC4b) $dC4b $ledC4b
Assert ($rC4b.files.Count -eq 1) 'C4b distinct-purpose: DECISION_NEEDED row + ESCALATION_STOP hook => NOT collapsed => hook still sends'

# ---- C4c: FINDING-2 (ITERATE-1, external codex LOW) - BREAKER_TRIP is NEVER in the
# {APPROVAL_NEEDED,DECISION_NEEDED} gate-open set, so it is never collapsed. A prior open-gate
# (APPROVAL_NEEDED) SENT row + the hook classifying the same-root same-turn event on the
# BREAKER-TRIP path => the hook STILL sends. (The Stop classifier maps breaker text to the
# ESCALATION_STOP class; both ESCALATION_STOP and the ledger class BREAKER_TRIP are outside
# the gate-open set - this pins the non-collapse of that distinct-PURPOSE stop, mirroring
# C4/C4b. A companion assertion also pins that a SEEDED BREAKER_TRIP row does not collapse a
# gate-open hook class either, covering the class from the ledger side.) ----
$ledC4c = Join-Path $scratch 'ledgerC4c.jsonl'
$dC4c = Join-Path $scratch 'c4c'
Set-NameFile $dC4c $sid 'dfx-c4'
$tC4c = Join-Path $scratch 'tC4c.jsonl'
Write-Transcript $tC4c @((UserStrLineTs 'go' $tOpenC4), (AsstTextLine 'm1' ("log`n`nBREAKER_TRIP: slice 2 failed twice; run parked."))) $false
Seed-LedgerSent $ledC4c 'dfx-c4' 'APPROVAL_NEEDED' '2026-07-09T09:40:05.0000000Z'   # open-gate row this turn
$rC4c = Invoke-Hook (StopJson $sid $dev $tC4c) $dC4c $ledC4c
$cC4c = Read-Mail $rC4c
Assert ($rC4c.files.Count -eq 1) 'C4c BREAKER_TRIP non-collapse: open-gate row + breaker-path hook classification => NOT collapsed => hook still sends'
Assert ($cC4c -match 'Subject: \[NEO\] ESCALATION_STOP - dfx-c4') 'C4c BREAKER_TRIP non-collapse: hook fires its own distinct-purpose stop class'
# companion: a SEEDED BREAKER_TRIP row (ledger side) does not collapse a gate-open hook class
$ledC4d = Join-Path $scratch 'ledgerC4d.jsonl'
$dC4d = Join-Path $scratch 'c4d'
Set-NameFile $dC4d $sid 'dfx-c4'
$tC4d = Join-Path $scratch 'tC4d.jsonl'
Write-Transcript $tC4d @((UserStrLineTs 'go' $tOpenC4), (AsstTextLine 'm1' ("plan`n`nWhich option, A or B?"))) $false
Seed-LedgerSent $ledC4d 'dfx-c4' 'BREAKER_TRIP' '2026-07-09T09:40:05.0000000Z'   # seeded distinct-purpose row
$rC4d = Invoke-Hook (StopJson $sid $dev $tC4d) $dC4d $ledC4d
Assert ($rC4d.files.Count -eq 1) 'C4d BREAKER_TRIP non-collapse (ledger side): seeded BREAKER_TRIP row + DECISION_NEEDED hook => NOT collapsed => hook still sends'

# ---- C5: multi-session isolation - helper -SessionId=A updates ONLY A.txt; a pre-existing
# B.txt is byte-unchanged ----
$dC5 = Join-Path $scratch 'c5'
$namesC5 = Join-Path $dC5 'session_names'
New-Item -ItemType Directory -Force -Path $namesC5 | Out-Null
$sidA = 'aaaa1111bbbb'
$sidB = 'cccc2222dddd'
[System.IO.File]::WriteAllText((Join-Path $namesC5 ($sidB + '.txt')), "b-name`nb-desc", [System.Text.Encoding]::ASCII)
$bBefore = [System.IO.File]::ReadAllBytes((Join-Path $namesC5 ($sidB + '.txt')))
$setC5 = Invoke-SetName -Name 'a-name' -Desc 'a-desc' -SessionId $sidA -NamesDir $namesC5
Assert ($setC5.exit -eq 0) 'C5 isolation: helper exit 0 writing A.txt'
Assert (Test-Path -LiteralPath (Join-Path $namesC5 ($sidA + '.txt'))) 'C5 isolation: A.txt written'
$bAfter = [System.IO.File]::ReadAllBytes((Join-Path $namesC5 ($sidB + '.txt')))
$bSame = ($bBefore.Length -eq $bAfter.Length)
if ($bSame) { for ($i = 0; $i -lt $bBefore.Length; $i++) { if ($bBefore[$i] -ne $bAfter[$i]) { $bSame = $false; break } } }
Assert $bSame 'C5 isolation: pre-existing B.txt byte-for-byte unchanged'

# ---- C6: helper-overwrite-wins-over-junk - junk auto-capture present, helper runs, the EXACT
# path written == <session_id>.txt and its line1 == friendly Name ----
$dC6 = Join-Path $scratch 'c6'
$namesC6 = Join-Path $dC6 'session_names'
New-Item -ItemType Directory -Force -Path $namesC6 | Out-Null
$sidC6 = 'eeee3333ffff'
[System.IO.File]::WriteAllText((Join-Path $namesC6 ($sidC6 + '.txt')), 'resume', [System.Text.Encoding]::ASCII)
$setC6 = Invoke-SetName -Name 'c6-friendly' -Desc 'c6 desc' -SessionId $sidC6 -NamesDir $namesC6
$expectC6 = Join-Path $namesC6 ($sidC6 + '.txt')
Assert ($setC6.exit -eq 0) 'C6 overwrite: helper exit 0'
Assert ($setC6.out -eq $expectC6) 'C6 overwrite: helper prints the EXACT <session_id>.txt path it wrote'
$c6raw = [System.IO.File]::ReadAllText($expectC6)
$c6line1 = ([string](@($c6raw -split "`n")[0])).TrimEnd("`r")
Assert ($c6line1 -eq 'c6-friendly') 'C6 overwrite: line1 == friendly Name (junk auto-capture overwritten)'

# ---- C7: helper id resolution via -TranscriptPath (UUID parsed out of the path) ----
$dC7 = Join-Path $scratch 'c7'
$namesC7 = Join-Path $dC7 'session_names'
$uuidC7 = 'e3f6d65f-2516-423a-8b8f-84c99241e31d'
$tpathC7 = "C:\\Users\\x\\.claude\\projects\\proj\\$uuidC7.jsonl"
$setC7 = Invoke-SetName -Name 'c7-from-transcript' -TranscriptPath $tpathC7 -NamesDir $namesC7
Assert ($setC7.exit -eq 0) 'C7 transcript-parse: helper exit 0 resolving id from -TranscriptPath'
Assert (Test-Path -LiteralPath (Join-Path $namesC7 ($uuidC7 + '.txt'))) 'C7 transcript-parse: wrote <uuid>.txt keyed by the parsed session_id'

# ---- C8: helper FAILS CLOSED with no id - >1 marker in the dir + no -SessionId/-TranscriptPath
# => non-zero, writes nothing new ----
$dC8 = Join-Path $scratch 'c8'
$namesC8 = Join-Path $dC8 'session_names'
New-Item -ItemType Directory -Force -Path $namesC8 | Out-Null
[System.IO.File]::WriteAllText((Join-Path $namesC8 'sid1.txt'), 'n1', [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText((Join-Path $namesC8 'sid2.txt'), 'n2', [System.Text.Encoding]::ASCII)
$before8 = @(Get-ChildItem -LiteralPath $namesC8 -File).Count
$setC8 = Invoke-SetName -Name 'ambiguous' -NamesDir $namesC8
Assert ($setC8.exit -ne 0) 'C8 fail-closed: no id (>1 marker, no -SessionId/-TranscriptPath) => non-zero exit'
$after8 = @(Get-ChildItem -LiteralPath $namesC8 -File).Count
Assert ($after8 -eq $before8) 'C8 fail-closed: nothing new written on the refusal path'

# ---- C8b: FINDING-1 (ITERATE-1, external codex MED) - the single-marker fallback was REMOVED.
# A LONE STALE other-session marker present + helper invoked with NEITHER -SessionId NOR
# -TranscriptPath => REFUSE: non-zero exit, NOTHING written, and that stale file BYTE-UNCHANGED
# (the old code would have silently overwritten it). ----
$dC8b = Join-Path $scratch 'c8b'
$namesC8b = Join-Path $dC8b 'session_names'
New-Item -ItemType Directory -Force -Path $namesC8b | Out-Null
$staleFile = Join-Path $namesC8b 'stale-other-session.txt'
[System.IO.File]::WriteAllText($staleFile, "stale-name`nstale-desc", [System.Text.Encoding]::ASCII)
$staleBefore = [System.IO.File]::ReadAllBytes($staleFile)
$cntBefore8b = @(Get-ChildItem -LiteralPath $namesC8b -File).Count
$setC8b = Invoke-SetName -Name 'would-clobber' -Desc 'would-clobber-desc' -NamesDir $namesC8b
Assert ($setC8b.exit -ne 0) 'C8b no-single-marker-fallback: lone stale marker + no -SessionId/-TranscriptPath => REFUSE (non-zero exit)'
$cntAfter8b = @(Get-ChildItem -LiteralPath $namesC8b -File).Count
Assert ($cntAfter8b -eq $cntBefore8b) 'C8b no-single-marker-fallback: no new file written on the refusal path'
$staleAfter = [System.IO.File]::ReadAllBytes($staleFile)
$staleSame = ($staleBefore.Length -eq $staleAfter.Length)
if ($staleSame) { for ($i = 0; $i -lt $staleBefore.Length; $i++) { if ($staleBefore[$i] -ne $staleAfter[$i]) { $staleSame = $false; break } } }
Assert $staleSame 'C8b no-single-marker-fallback: the stale other-session marker is BYTE-UNCHANGED (never silently overwritten)'

# ---- REJECT cases: the tightened Test-NeoHookRejectCapture via the UserPromptSubmit path.
# '1-approve--2-include' / 'resume' / 'START-approved...' each write NO sidecar; a positive
# that 'notify-doublefire-fix' IS accepted ----
$dfxRejects = @{
  'menu'   = '1-approve--2-include'
  'resume' = 'resume'
  'start'  = 'START-approved.--a--Yes-----baseline-2163C1C0.--b--Yes-----c'
}
$rn = 0
foreach ($k in $dfxRejects.Keys) {
  $rn++
  $sidRj = ('dfxrej0' + $rn)
  $dRj = Join-Path $scratch ('dfxrej_' + $rn)
  Invoke-Hook (UpsJson $sidRj $dev $dfxRejects[$k]) $dRj | Out-Null
  $nfRj = Join-Path (Join-Path $dRj 'session_names') ($sidRj + '.txt')
  Assert (-not (Test-Path -LiteralPath $nfRj)) ('DFX reject ' + $k + ': junk first-prompt writes NO sidecar (clean fallback)')
}
# positive: a real slice slug is still ACCEPTED
$dfxAcc = Join-Path $scratch 'dfxacc'
$sidAcc = 'dfxacc001'
Invoke-Hook (UpsJson $sidAcc $dev 'notify-doublefire-fix') $dfxAcc | Out-Null
$nfAcc = Join-Path (Join-Path $dfxAcc 'session_names') ($sidAcc + '.txt')
$accOk = (Test-Path -LiteralPath $nfAcc)
$accVal = ''
if ($accOk) { $accVal = [System.IO.File]::ReadAllText($nfAcc) }
Assert ($accOk -and ($accVal -eq 'notify-doublefire-fix')) 'DFX accept: notify-doublefire-fix is a valid slug, ACCEPTED + stored'

# ============ F36: zero-write discipline - real session_names dir untouched ============
$namesStateAfter = Get-NamesDirState
Assert ($namesStateAfter -eq $namesStateBefore) 'F36 zero-write: real %USERPROFILE%\.neo_notify\session_names untouched by the suite'

Write-Output ('RESULT: ' + $pass + ' pass / ' + $fail + ' fail (scratch: ' + $scratch + ')')
# residue discipline: scratch removed on a fully green run; kept on any fail for debugging.
if ($fail -eq 0) { try { Remove-Item -Recurse -Force -LiteralPath $scratch -ErrorAction Stop } catch {} }
if ($fail -gt 0) { exit 1 } else { exit 0 }
