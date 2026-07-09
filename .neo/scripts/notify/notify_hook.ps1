# notify_hook.ps1 - NEO harness-hook -> gate-notification ADAPTER (B3H: FILTERED Stop hook +
# SESSION NAMING; supersedes the Item-3 unconditional Stop=>SESSION_END mapping).
# ASCII-only (D10). Invoked BY THE HARNESS (settings.json hooks) with the hook event as JSON
# on STDIN. Maps the friction event to AT MOST ONE capped Send-NeoGateNotification call
# through the FROZEN notify module (notify_raphael.ps1) - this adapter adds NO new send
# capability, NO new recipient surface, NO new content surface. The module contract IS the
# cap: attested friction classes only, hardcoded recipient/sender, 12-line/200-char caps,
# no attachments, 10-min dedupe, failed send never blocks.
#
# CONTRACT (binding; NEO_STOPHOOK_B3H_CONTRACT.md fire/no-fire table v2 wins over all docs):
#   * FAIL-OPEN, ALWAYS EXIT 0: malformed stdin, unknown event, unreadable transcript,
#     module refusal, send failure - NOTHING this script does may block or delay the
#     session (authority rule: notification is convenience, never gate).
#   * EVENT MAP (CASE-EXACT switch; only the literal harness event names map):
#       Notification + message ~ 'permission'  -> APPROVAL_NEEDED   (unchanged backstop)
#       Notification (any other message)       -> DECISION_NEEDED   (unchanged)
#       Stop                                   -> FILTERED classifier over the transcript
#                                                 tail (contract table v2, below)
#       UserPromptSubmit                       -> write-once session-name capture; NO send
#       anything else                          -> no send, exit 0
#   * STOP CLASSIFIER (bounded tail-read, last 256 KB; JSONL parsed from the end; LAST
#     assistant message = concatenation of its TEXT blocks only; scan scope = final
#     non-empty paragraph capped at its last 15 lines; markers case-insensitive exact-form):
#       row 1  gate-question marker            -> APPROVAL_NEEDED, ask VERBATIM
#       row 2  ends '?' / DECISION marker      -> DECISION_NEEDED, ask VERBATIM
#       row 3  blocked/breaker/park marker     -> ESCALATION_STOP, reason VERBATIM
#       row 4  permission-prompt exact form    -> APPROVAL_NEEDED (Notification = backstop)
#       row 5  genuine END-summary form        -> SESSION_END (the ONLY SESSION_END path)
#       row 6  unclassifiable ending           -> DECISION_NEEDED '(unclassified stop)'
#       row 7  idle after answering Raphael    -> DECISION_NEEDED '(session idle - awaiting you)'
#       row 8  status narration, no live work  -> DECISION_NEEDED '(session idle)'
#       row 8b POSITIVE evidence of live background work (bg task start with NO completion
#              record after it)                -> SILENT (session auto-resumes)
#       row 9  true duplicates                 -> module's 10-min dedupe (NOT re-implemented)
#       row 10 local commands (/clear /compact /model) / empty no-op turns -> SILENT
#     Silence on transcript size ONLY when no complete last assistant message is extractable
#     from the tail (oversized transcripts are the NORMAL case and are tail-read).
#   * MAIL SHAPE (GOAL-1, spec secs 1.2-1.4): caller SummaryLines <= 11 (so the module's
#     single prepended PROGRESS line keeps the total <= 12). Fixed priority: [1] session
#     header line ALWAYS first; [2] 'ACTION NEEDED: <per-class>' line ALWAYS; [3] optional
#     'Desc: <one-line>' line (the FIRST casualty under truncation); [4..N] VERBATIM ask
#     lines (TAIL-kept, tail-trimmed with a '[truncated]' line when over budget); [last]
#     working-dir line ALWAYS last. Ask lines are secret-masked ([masked]), ASCII-sanitized,
#     200-char capped.
#   * ACTION NEEDED (spec sec 1.3): derived from the computed gate class - the exact "what
#     Raphael must do" line, one per attested class.
#   * DOUBLE-FIRE BACKSTOP (addendum D1; SUPERSEDES spec sec 1.4 part 2): in the Stop
#     branch, a READ-ONLY, SILENT suppression step. It resolves T_open (the prior-user
#     entry's top-level 'timestamp', roundtrip-UTC) and reads the send ledger READ-ONLY;
#     it SUPPRESSES its own send (exit 0, no send, NO ledger write) iff a SENT row exists
#     with slice == <session-root> AND gate == its OWN computed class AND ts >= T_open (the
#     same yielded turn - the manager already mailed this SAME gate). Unresolvable T_open
#     => do NOT suppress (fail-toward-mail). This adds NO new live write surface.
#   * SESSION NAMING (BOTH send paths): Subject SliceId = sanitized session name (charset
#     [A-Za-z0-9_.-], cap 60) read from %USERPROFILE%\.neo_notify\session_names\
#     <session_id>.txt LINE 1 (written once, reject-filtered, by the UserPromptSubmit
#     branch from the first prompt; a manager overwrites it unconditionally as a separate
#     procedure); fallback '<tree>-<uuid8>'. LINE 2 (optional) = a one-line description ->
#     the 'Desc:' line. Body line 1: 'Session: <name> | id <uuid8> | tree: <tree>'.
#     Tree is path-segment-aware from cwd: DEV / PROD / other. Capture is REJECT-FILTERED
#     (spec sec 3.2 + addendum D3): banners / commissioning text / pasted code / degenerate
#     tokens fall back to the clean name; a multi-char single-token slug is accepted.
#   * WRITE SURFACE: ONLY the session_names name file above (outside the governed trees);
#     under -TestModeDir the session_names dir lives inside the TestModeDir (seams travel
#     together; fixture-only). This script NEVER writes the governed trees.
#   * TEST-ONLY SEAMS (fixture use ONLY; the harness hook line passes NEITHER):
#     -TestModeDir (compose-to-disk, zero network) and -LedgerPath (scratch dedupe ledger).
#     A lone -LedgerPath without -TestModeDir is REFUSED outright (anti-runaway sidestep).
#     Default (no params) = live send via the module's own attestation-gated path.

param(
  [string]$TestModeDir,
  [string]$LedgerPath
)

# --- ASCII sanitize + cap (composition-side twin of the module's own checks) ---
function Get-NeoHookAsciiLine {
  param([string]$s, [int]$max)
  if ($null -eq $s) { return '' }
  $s = ($s -replace '[^\x20-\x7E]', '?')
  if ($max -gt 0 -and $s.Length -gt $max) { $s = $s.Substring(0, $max) }
  return $s
}

# --- module SliceId-safe charset ([A-Za-z0-9_.-]; everything else -> '-') + cap ---
function Get-NeoHookCharsetName {
  param([string]$s, [int]$max)
  $s = Get-NeoHookAsciiLine $s 0
  $s = ($s -replace '[^A-Za-z0-9_.-]', '-')
  if ($max -gt 0 -and $s.Length -gt $max) { $s = $s.Substring(0, $max) }
  return $s
}

# --- tree label from cwd, path-segment-aware ('S:\NEO 5.0' is NOT PROD) ---
function Get-NeoHookTreeLabel {
  param([string]$c)
  if ([string]::IsNullOrWhiteSpace($c)) { return 'other' }
  $p = $c.Replace('/', '\').TrimEnd('\')
  if (($p -eq 'S:\NEO_dev') -or ($p -like 'S:\NEO_dev\*')) { return 'DEV' }
  if (($p -eq 'S:\NEO') -or ($p -like 'S:\NEO\*')) { return 'PROD' }
  return 'other'
}

# --- secret-shape masking (belt-and-braces, honestly incomplete - C9 wording) ---
function Get-NeoHookMaskedLine {
  param([string]$s)
  if ($null -eq $s) { return '' }
  if ($s -match '-----BEGIN') { return '[masked]' }
  $s = [regex]::Replace($s, 'sk-[A-Za-z0-9_\-]{8,}', '[masked]')
  $s = [regex]::Replace($s, 'AKIA[A-Z0-9]{8,}', '[masked]')
  $s = [regex]::Replace($s, '(?i)"api_key"\s*:\s*("[^"]*"|\S+)', '[masked]')
  $s = [regex]::Replace($s, '[A-Za-z0-9+/]{40,}={0,2}', '[masked]')
  return $s
}

# --- ACTION NEEDED per gate class (spec sec 1.3): the exact "what Raphael must do" line
# derived from the class the adapter already computes. An unmapped class => '' (the line
# is simply omitted, never invented). ---
function Get-NeoHookActionNeeded {
  param([string]$GateType)
  switch ($GateType) {
    'APPROVAL_NEEDED' { return 'ACTION NEEDED: review + answer the START/approval question in the Claude chat (approve / change / reject).' }
    'DECISION_NEEDED' { return 'ACTION NEEDED: answer the question in the Claude chat.' }
    'SESSION_END'     { return 'ACTION NEEDED: give the END verdict in chat - keep / iterate / toss.' }
    'ESCALATION_STOP' { return 'ACTION NEEDED: session PARKED - inspect the reason + tell it how to proceed.' }
    'BREAKER_TRIP'    { return 'ACTION NEEDED: circuit-breaker TRIPPED - review the trip reason + reset or abort.' }
    'PROGRESS_REPORT' { return 'ACTION NEEDED: none - running (FYI heartbeat).' }
    default           { return '' }
  }
}

# --- capture REJECT-FILTER (spec sec 3.2 as tightened by addendum D3): the write-once
# auto-capture STORES the candidate only if it looks like a real session slug. The reject
# checks run against BOTH the raw candidate AND the charset-sanitized candidate, using
# SEPARATOR-TOLERANT patterns (space / '-' / '.' / '_' treated as equivalent separators) -
# because the observed garbage was already sanitized to a '-'-separated banner, so a
# raw-only match would MISS it. Returns $true when the candidate must be REJECTED (fall
# back to the clean <tree>-<uuid8>), $false when it is an acceptable slug. ---
function Test-NeoHookRejectCapture {
  param([string]$Raw, [string]$Sanitized)
  try {
    # A single separator-tolerant matcher over BOTH forms: collapse every run of the
    # separator set (space/-/./_) to a single space, so 'Windows-PowerShell' and
    # 'Windows PowerShell' and 'Windows.PowerShell' all normalize identically.
    $forms = @()
    foreach ($f in @([string]$Raw, [string]$Sanitized)) {
      if ($null -eq $f) { continue }
      $norm = ($f -replace '[\s\.\-_]+', ' ').Trim()
      $forms += $norm
    }
    # pasted-code shapes: the RAW candidate (leading whitespace trimmed) starts with a code
    # sigil. Checked on the raw form only (sanitization would strip the sigil).
    $rawTrim = ([string]$Raw).TrimStart()
    if ($rawTrim.StartsWith('#') -or $rawTrim.StartsWith('$') -or $rawTrim.StartsWith('<#') -or
        ($rawTrim -match '^(?i)param\s*\(') -or ($rawTrim -match '^(?i)function\s')) {
      return $true
    }
    foreach ($form in $forms) {
      if ([string]::IsNullOrWhiteSpace($form)) { continue }
      # shell/console banners (separator-tolerant)
      if ($form -match '(?i)\bWindows PowerShell\b') { return $true }
      if ($form -match '(?i)\bCopyright\b') { return $true }
      if ($form -match '(?i)\bMicrosoft Corporation\b') { return $true }
      if ($form -match '(?i)\bAll rights reserved\b') { return $true }
      if ($form -match '(?i)\bPS C ') { return $true }              # 'PS C:\...' prompt fragment ('PS C:' -> 'PS C ')
      # NEO commissioning shapes
      if ($form -match '(?i)\bYou are a fresh NEO manager\b') { return $true }
      if ($form -match '(?i)^MODE ') { return $true }              # leading 'MODE:' ('MODE:' -> 'MODE ')
      if ($form -match '(?i)^MISSION ') { return $true }           # leading 'MISSION:'
      # menu-answer / resume / gate-answer shapes (observed live junk auto-captures:
      # '1-approve--2-include', 'resume', 'START-approved.--a--Yes...'). Separator-tolerant
      # over the normalized form. Tuned to NOT touch legit slugs (ems005, neo49,
      # notify-tracker-ux, notify-doublefire-fix carry none of these tokens):
      if ($form -match '(?i)^\s*resume\s*$') { return $true }      # bare 'resume' answer
      if ($form -match '(?i)^\s*\d+\s+(approve|include|reject|yes|no)\b') { return $true } # leading numbered menu pick ('1 approve ...')
      if ($form -match '(?i)^\s*(START|STOP)\s+approved?\b') { return $true }  # 'START-approved...', 'STOP approve...'
      if ($form -match '(?i)\bapproved?\b.*\binclude\b') { return $true }      # 'approve ... include' menu-answer body
    }
    # degenerate (addendum D3): the SANITIZED candidate is < 3 chars, OR a single-CHARACTER
    # token, OR all-punctuation (no [A-Za-z0-9]). A MULTI-character word-like single-token
    # slug (ems005, neo49, notify-tracker-ux) is ACCEPTED - do NOT reject it.
    $san = [string]$Sanitized
    if ($san.Length -lt 3) { return $true }
    if ($san -notmatch '[A-Za-z0-9]') { return $true }             # all-punctuation
    # single-CHARACTER token: one visible char surrounded only by separators/nothing
    $sanCore = ($san -replace '[\s\.\-_]+', '')
    if ($sanCore.Length -lt 2) { return $true }
    return $false
  } catch {
    # on any internal error, REJECT (fail toward the clean fallback, never toward garbage)
    return $true
  }
}

# --- bounded tail read: last 256 KB max; partial first line dropped; BOM tolerated.
# Returns $null on any read failure (silent path), '' when nothing is readable. ---
function Read-NeoHookTranscriptTail {
  param([string]$path)
  try {
    $fs = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
      $len = $fs.Length
      if ($len -le 0) { return '' }
      $maxBytes = 262144
      $start = [long]0
      if ($len -gt $maxBytes) { $start = $len - $maxBytes }
      $null = $fs.Seek($start, [System.IO.SeekOrigin]::Begin)
      $count = [int]($len - $start)
      $buf = New-Object byte[] $count
      $read = 0
      while ($read -lt $count) {
        $n = $fs.Read($buf, $read, $count - $read)
        if ($n -le 0) { break }
        $read += $n
      }
      $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
      if ($start -gt 0) {
        $nl = $text.IndexOf("`n")
        if ($nl -lt 0) { return '' }
        $text = $text.Substring($nl + 1)
      } elseif ($text.Length -gt 0 -and [int]$text[0] -eq 0xFEFF) {
        $text = $text.Substring(1)
      }
      return $text
    } finally { $fs.Dispose() }
  } catch { return $null }
}

# --- user-entry text: string content as-is; list content = concat of its text blocks ---
function Get-NeoHookUserText {
  param($o)
  $c = $null
  try { $c = $o.message.content } catch { $c = $null }
  if ($null -eq $c) { return '' }
  if ($c -is [string]) { return [string]$c }
  $parts = @()
  foreach ($b in @($c)) {
    if ($null -eq $b) { continue }
    $bt = ''
    try { $bt = [string]$b.type } catch { $bt = '' }
    if ($bt -eq 'text') { $parts += [string]$b.text }
  }
  return ($parts -join "`n")
}

# --- THE B3H STOP CLASSIFIER (contract table v2). Returns $null for every SILENT row,
# else @{ gate = <attested class>; ask = <verbatim content lines> }. ---
function Get-NeoHookStopClassification {
  param([string]$TranscriptPath)
  try {
    if ([string]::IsNullOrWhiteSpace($TranscriptPath)) { return $null }
    if (-not (Test-Path -LiteralPath $TranscriptPath)) { return $null }
    $tailText = Read-NeoHookTranscriptTail -path $TranscriptPath
    if ([string]::IsNullOrEmpty($tailText)) { return $null }

    # JSONL: parse what parses, skip what does not (bookkeeping tolerance, fail-open)
    $entries = New-Object System.Collections.ArrayList
    foreach ($ln in ($tailText -split "`n")) {
      $ln = $ln.TrimEnd("`r")
      if ([string]::IsNullOrWhiteSpace($ln)) { continue }
      $o = $null
      try { $o = ConvertFrom-Json -InputObject $ln } catch { continue }
      if ($null -ne $o) { [void]$entries.Add($o) }
    }
    if ($entries.Count -eq 0) { return $null }

    # LAST assistant entry (main thread only; sidechain entries never classify)
    $lastIdx = -1
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
      $o = $entries[$i]
      $t = ''
      try { $t = [string]$o.type } catch { $t = '' }
      if ($t -eq 'assistant' -and (-not ($o.isSidechain -eq $true))) { $lastIdx = $i; break }
    }
    if ($lastIdx -lt 0) { return $null }   # no complete last assistant message in the tail

    # row 10: the transcript ENDS on a local-command / compact turn -> nothing stopped
    for ($i = $lastIdx + 1; $i -lt $entries.Count; $i++) {
      $o = $entries[$i]
      $t = ''
      try { $t = [string]$o.type } catch { $t = '' }
      if ($t -ne 'user') { continue }
      if ($o.isCompactSummary -eq $true) { return $null }
      $ut = Get-NeoHookUserText -o $o
      if ($ut -match '<command-name>' -or $ut -match '<local-command-') { return $null }
    }

    # LAST assistant MESSAGE = concat of TEXT blocks across the entries sharing message.id
    # (one logical message streams as multiple JSONL entries, one content block each)
    $msgId = ''
    try { $msgId = [string]$entries[$lastIdx].message.id } catch { $msgId = '' }
    $textParts = @()
    $firstEntryIdx = $lastIdx
    for ($i = 0; $i -le $lastIdx; $i++) {
      $o = $entries[$i]
      $t = ''
      try { $t = [string]$o.type } catch { $t = '' }
      if ($t -ne 'assistant') { continue }
      if ($o.isSidechain -eq $true) { continue }
      $mid = ''
      try { $mid = [string]$o.message.id } catch { $mid = '' }
      $belongs = $false
      if ($msgId -ne '' -and $mid -eq $msgId) { $belongs = $true }
      if ($msgId -eq '' -and $i -eq $lastIdx) { $belongs = $true }
      if (-not $belongs) { continue }
      if ($i -lt $firstEntryIdx) { $firstEntryIdx = $i }
      foreach ($b in @($o.message.content)) {
        if ($null -eq $b) { continue }
        $bt = ''
        try { $bt = [string]$b.type } catch { $bt = '' }
        if ($bt -eq 'text') { $textParts += [string]$b.text }
      }
    }
    $text = ($textParts -join "`n")
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }   # row 10: empty/no-op turn

    # row 8b: POSITIVE evidence of live background work = a correlatable background
    # task/agent start (tool_use with run_in_background=true and a real id) with NO
    # task-notification completion record after it. Uncorrelatable starts are UNCERTAIN
    # and never silence (uncertain => FIRE).
    for ($i = 0; $i -lt $entries.Count; $i++) {
      $o = $entries[$i]
      $t = ''
      try { $t = [string]$o.type } catch { $t = '' }
      if ($t -ne 'assistant') { continue }
      if ($o.isSidechain -eq $true) { continue }   # sidechain bg work never silences the main session
      foreach ($b in @($o.message.content)) {
        if ($null -eq $b) { continue }
        $bt = ''
        try { $bt = [string]$b.type } catch { $bt = '' }
        if ($bt -ne 'tool_use') { continue }
        $isBg = $false
        try { if ($b.input.run_in_background -eq $true) { $isBg = $true } } catch { $isBg = $false }
        if (-not $isBg) { continue }
        $bid = ''
        try { $bid = [string]$b.id } catch { $bid = '' }
        if ([string]::IsNullOrWhiteSpace($bid)) { continue }
        $done = $false
        $needle = [regex]::Escape('<tool-use-id>' + $bid + '</tool-use-id>')
        for ($j = $i + 1; $j -lt $entries.Count; $j++) {
          $u = $entries[$j]
          $tu = ''
          try { $tu = [string]$u.type } catch { $tu = '' }
          if ($tu -ne 'user') { continue }
          $ut = Get-NeoHookUserText -o $u
          if ($ut -match '<task-notification>' -and $ut -match $needle) { $done = $true; break }
        }
        if (-not $done) { return $null }   # session auto-resumes; the next turn re-evaluates
      }
    }

    # scan scope: final non-empty paragraph of the message text, capped at its last 15 lines
    $norm = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $allLines = @($norm -split "`n")
    $endIdx = -1
    for ($i = $allLines.Count - 1; $i -ge 0; $i--) {
      if (-not [string]::IsNullOrWhiteSpace($allLines[$i])) { $endIdx = $i; break }
    }
    if ($endIdx -lt 0) { return $null }
    $startIdx = $endIdx
    while ($startIdx -gt 0 -and (-not [string]::IsNullOrWhiteSpace($allLines[$startIdx - 1]))) { $startIdx-- }
    $para = @($allLines[$startIdx..$endIdx])
    if ($para.Count -gt 15) { $para = @($para[($para.Count - 15)..($para.Count - 1)]) }
    $paraText = ($para -join "`n")
    $lastLine = ([string]$para[$para.Count - 1]).Trim()

    # classification: exact-form markers, case-insensitive; specific outranks generic
    if ($paraText -match '(?i)(APPROVAL NEEDED|APPROVAL_NEEDED|STOP-AND-WAIT|Keep / iterate / toss|START approval|\bdo you authorize\b|\bplease authorize\b|\bauthorize this\b|\bauthorization needed\b|\bAUTHORIZATION_NEEDED\b|\bawaiting your authorization\b|\battestation confirm\b|\bconfirm the attestation\b|\bconfirm your attestation\b)') {
      return @{ gate = 'APPROVAL_NEEDED'; ask = $para }                                     # row 1 (incl. authorize / attestation-confirm gate forms; bare 'authorized'/'attestation' prose never matches)
    }
    if ($paraText -match '(?im)^\s*[-=#*\[\]>]*\s*(ESCALATION[ _]STOP|BREAKER[ _]TRIP|FLOOR STOP|UNRECOVERABLE|PARKED)\b') {
      return @{ gate = 'ESCALATION_STOP'; ask = $para }                                     # row 3
    }
    if (($paraText -match '(?im)^\s*[-=#*\[\]]*\s*SESSION[ _]END\b') -or ($paraText -match '(?im)^\s*[-=#*\[\]]*\s*SESSION[ _]END SUMMARY\b')) {
      return @{ gate = 'SESSION_END'; ask = $para }                                         # row 5
    }
    if ($paraText -match '(?i)(needs your permission|permission needed|waiting for your permission|requesting permission|permission prompt)') {
      return @{ gate = 'APPROVAL_NEEDED'; ask = $para }                                     # row 4
    }
    if ($lastLine.EndsWith('?') -or ($paraText -match '(?i)(DECISION NEEDED|DECISION_NEEDED)')) {
      return @{ gate = 'DECISION_NEEDED'; ask = $para }                                     # row 2
    }

    # rows 7/8 idle vs row 6 unclassified: idle needs a prior user entry to anchor context
    $priorUser = $null
    for ($i = $firstEntryIdx - 1; $i -ge 0; $i--) {
      $t = ''
      try { $t = [string]$entries[$i].type } catch { $t = '' }
      if ($t -eq 'user') { $priorUser = $entries[$i]; break }
    }
    if ($null -eq $priorUser) {
      return @{ gate = 'DECISION_NEEDED'; ask = @('(unclassified stop)', $lastLine) }       # row 6
    }
    $pc = $null
    try { $pc = $priorUser.message.content } catch { $pc = $null }
    $isHuman = $false
    if ($pc -is [string]) {
      $pt = ([string]$pc).TrimStart()
      if ($pt.Length -gt 0 -and (-not $pt.StartsWith('<'))) { $isHuman = $true }
    }
    if ($isHuman) {
      return @{ gate = 'DECISION_NEEDED'; ask = @('(session idle - awaiting you)', $lastLine) }  # row 7
    }
    return @{ gate = 'DECISION_NEEDED'; ask = @('(session idle)', $lastLine) }              # row 8
  } catch {
    # DEFAULT-ON-AMBIGUITY = row 6 (fail-toward-notify): an internal classifier error on an
    # otherwise-readable transcript fires an unclassified-stop mail rather than going dark.
    return @{ gate = 'DECISION_NEEDED'; ask = @('(unclassified stop)', '(classifier error)') }
  }
}

# --- roundtrip-to-UTC parse (InvariantCulture, RoundtripKind, ToUniversalTime), the SAME
# convention the reader/heartbeat use. $null on any failure (fail-open). ---
function ConvertTo-NeoHookUtc {
  param([string]$s)
  try {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $dt = [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::RoundtripKind)
    return $dt.ToUniversalTime()
  } catch { return $null }
}

# --- DOUBLE-FIRE BACKSTOP T_open (addendum D1 step 2): resolve T_open = the PRIOR user
# entry's TOP-LEVEL 'timestamp' field, parsed roundtrip-to-UTC. "Prior user entry" mirrors
# the classifier: the last-assistant message is found, then the newest user entry BEFORE
# that message's first entry. Bounded tail read (same 256 KB seam as the classifier).
# Returns the UTC datetime, or $null when unresolvable (prior-user entry missing, or its
# timestamp absent/blank/unparseable) => the caller must NOT suppress (fail-toward-mail). ---
function Get-NeoHookTurnOpenUtc {
  param([string]$TranscriptPath)
  try {
    if ([string]::IsNullOrWhiteSpace($TranscriptPath)) { return $null }
    if (-not (Test-Path -LiteralPath $TranscriptPath)) { return $null }
    $tailText = Read-NeoHookTranscriptTail -path $TranscriptPath
    if ([string]::IsNullOrEmpty($tailText)) { return $null }
    $entries = New-Object System.Collections.ArrayList
    foreach ($ln in ($tailText -split "`n")) {
      $ln = $ln.TrimEnd("`r")
      if ([string]::IsNullOrWhiteSpace($ln)) { continue }
      $o = $null
      try { $o = ConvertFrom-Json -InputObject $ln } catch { continue }
      if ($null -ne $o) { [void]$entries.Add($o) }
    }
    if ($entries.Count -eq 0) { return $null }
    # last main-thread assistant entry
    $lastIdx = -1
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
      $t = ''
      try { $t = [string]$entries[$i].type } catch { $t = '' }
      if ($t -eq 'assistant' -and (-not ($entries[$i].isSidechain -eq $true))) { $lastIdx = $i; break }
    }
    if ($lastIdx -lt 0) { return $null }
    # first entry of that streamed message (share message.id) - the message's opening index
    $msgId = ''
    try { $msgId = [string]$entries[$lastIdx].message.id } catch { $msgId = '' }
    $firstEntryIdx = $lastIdx
    if ($msgId -ne '') {
      for ($i = 0; $i -le $lastIdx; $i++) {
        $t = ''
        try { $t = [string]$entries[$i].type } catch { $t = '' }
        if ($t -ne 'assistant') { continue }
        if ($entries[$i].isSidechain -eq $true) { continue }
        $mid = ''
        try { $mid = [string]$entries[$i].message.id } catch { $mid = '' }
        if ($mid -eq $msgId) { $firstEntryIdx = $i; break }
      }
    }
    # newest GENUINE turn-opener user entry BEFORE the message's opening index = this turn's
    # anchor. A REAL transcript records tool_result blocks as type=='user' too (message.content
    # is an ARRAY carrying a 'tool_result' element), timestamped ~now; those are NOT turn-openers
    # and must be SKIPPED so the anchor stays THIS turn's opening input (a human message or a
    # <task-notification> turn-opener). A qualifying opener has content that is a STRING, OR an
    # array with NO tool_result block. If none qualifies, return $null (fail-toward-mail).
    $priorUser = $null
    for ($i = $firstEntryIdx - 1; $i -ge 0; $i--) {
      $t = ''
      try { $t = [string]$entries[$i].type } catch { $t = '' }
      if ($t -ne 'user') { continue }
      # is this user entry a tool_result? (content is an array with a tool_result element)
      $isToolResult = $false
      try {
        $content = $entries[$i].message.content
        if ($null -ne $content -and ($content -is [System.Array])) {
          foreach ($blk in $content) {
            $bt = ''
            try { $bt = [string]$blk.type } catch { $bt = '' }
            if ($bt -eq 'tool_result') { $isToolResult = $true; break }
          }
        }
      } catch { $isToolResult = $false }
      if ($isToolResult) { continue }        # skip tool_results - not a turn-opener
      $priorUser = $entries[$i]; break        # newest genuine (non-tool_result) opener
    }
    if ($null -eq $priorUser) { return $null }
    $tsRaw = ''
    try { $tsRaw = [string]$priorUser.timestamp } catch { $tsRaw = '' }
    if ([string]::IsNullOrWhiteSpace($tsRaw)) { return $null }
    return (ConvertTo-NeoHookUtc -s $tsRaw)
  } catch { return $null }
}

# --- DOUBLE-FIRE BACKSTOP suppression probe (addendum D1 step 3, as REVISED by the
# notify-doublefire-fix contract v2; SUPERSEDES spec sec 1.4 part 2). READ-ONLY, SILENT:
# reads the send ledger and returns $true (SUPPRESS the hook's own send) iff a SENT row
# exists with ALL of: session-ROOT match (both the row slice and the hook's own SliceId
# stripped of a trailing '-START'/'-END' suffix, then compared) AND both gates fall in the
# human-gate-OPEN equivalence set {APPROVAL_NEEDED, DECISION_NEEDED} (the manager and the
# Stop classifier reading the SAME yielded final paragraph assign these two classes
# interchangeably for the SAME logical "a gate is open, answer now" event) AND ts >= T_open
# (row ts parsed the same roundtrip-UTC way; unparseable row ts ignored). This is NOT
# class-agnostic: a DIFFERENT-PURPOSE Stop class (SESSION_END / ESCALATION_STOP /
# BREAKER_TRIP) is NEVER collapsed - it still fires. If T_open is $null => NEVER suppress
# (fail-toward-mail). This writes NOTHING - no SKIPPED_MANAGER_PRESENT row, no new live
# write surface (D1). Rationale: the predicate means "an open-gate mail for this session
# root was already sent during this yielded turn" - the manual loop is strictly serial at
# the human surface (D2/D3), so the manager's explicit open-gate mail and the Stop
# classifier reading the SAME final paragraph are the SAME logical gate; suppressing the
# duplicate loses nothing, and a distinct-PURPOSE Stop class still fires. ---
function Test-NeoHookLedgerSuppress {
  param([string]$LedgerPath, [string]$SliceId, [string]$GateType, $TOpenUtc)
  try {
    if ($null -eq $TOpenUtc) { return $false }                     # unresolvable turn boundary => fire
    if ([string]::IsNullOrWhiteSpace($LedgerPath)) { return $false }
    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) { return $false }
    foreach ($line in @(Get-Content -LiteralPath $LedgerPath -Encoding Ascii -ErrorAction Stop)) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $e = $null
      try { $e = ConvertFrom-Json -InputObject $line } catch { continue }
      if ($null -eq $e) { continue }
      try {
        if ([string]$e.outcome -ne 'SENT') { continue }
        $rowRoot = ([string]$e.slice) -replace '[-:](START|END)$',''
        $myRoot  = ([string]$SliceId)  -replace '[-:](START|END)$',''
        if ($rowRoot -ne $myRoot) { continue }
        # Collapse ONLY the human-gate-OPEN duplicate pair. A different-PURPOSE Stop class
        # (SESSION_END / ESCALATION_STOP / BREAKER_TRIP) is NEVER collapsed - it still fires.
        $gateOpenSet = @('APPROVAL_NEEDED','DECISION_NEEDED')
        if (-not ( ($gateOpenSet -contains [string]$e.gate) -and ($gateOpenSet -contains [string]$GateType) )) { continue }
        $rowTs = ConvertTo-NeoHookUtc -s ([string]$e.ts)
        if ($null -eq $rowTs) { continue }                         # ignore rows with unparseable ts
        if ($rowTs -ge $TOpenUtc) { return $true }                 # same root + open-gate pair, this turn
      } catch { continue }
    }
    return $false
  } catch { return $false }
}

# --- caller line-budget assembler (spec sec 1.2/1.4, addendum): guarantee caller
# SummaryLines <= 11 (so the frozen module's single prepended PROGRESS line keeps the
# total <= 12). Fixed priority: [1] header ALWAYS first; [2] ACTION NEEDED ALWAYS;
# [last] working-dir ALWAYS last; [3] Desc is the FIRST casualty when over budget; the
# ask block [4..N] is TAIL-kept and tail-trimmed (drop OLDEST ask lines, a '[truncated]'
# line inserted as its own line) until total <= 11. All ask lines carry the existing
# secret-mask + ASCII + 200-char rules; the header/action/desc/workingdir lines are
# ASCII+200 capped by the caller before they arrive here. ---
function Get-NeoHookBudgetedSummary {
  param(
    [string]$HeaderLine,
    [string]$ActionLine,
    [string]$DescLine,
    [string[]]$AskLines,
    [string]$WorkingDirLine,
    [int]$Cap = 11
  )
  try {
    $ask = @()
    foreach ($al in @($AskLines)) {
      if ($null -eq $al) { continue }
      $ask += (Get-NeoHookAsciiLine -s (Get-NeoHookMaskedLine -s ([string]$al)) -max 200)
    }
    $hasHeader  = -not [string]::IsNullOrEmpty($HeaderLine)
    $hasAction  = -not [string]::IsNullOrEmpty($ActionLine)
    $hasWorkDir = -not [string]::IsNullOrEmpty($WorkingDirLine)
    $hasDesc    = -not [string]::IsNullOrWhiteSpace($DescLine)

    # reserved (always-kept) line count: header + action + working dir
    $reserved = 0
    if ($hasHeader)  { $reserved++ }
    if ($hasAction)  { $reserved++ }
    if ($hasWorkDir) { $reserved++ }

    # [3] Desc is the FIRST casualty (spec 1.2 truncation order: DROP Desc FIRST, THEN
    # tail-trim the ask block). So Desc is kept ONLY when the FULL ask block already fits
    # alongside the reserved lines + Desc; the moment the ask block would need trimming,
    # Desc is dropped to give the (higher-priority) ask lines the room.
    if ($hasDesc -and (($reserved + 1 + $ask.Count) -gt $Cap)) { $hasDesc = $false }
    $askBudget = $Cap - $reserved - $(if ($hasDesc) { 1 } else { 0 })
    if ($askBudget -lt 0) { $askBudget = 0 }

    # tail-trim the ask block to askBudget; when trimming, one slot holds '[truncated]'
    $askOut = @($ask)
    if ($askOut.Count -gt $askBudget) {
      if ($askBudget -le 0) {
        $askOut = @()
      } elseif ($askBudget -eq 1) {
        $askOut = @('[truncated]')
      } else {
        $keep = $askBudget - 1                                    # reserve one slot for the marker
        $tail = @($askOut[($askOut.Count - $keep)..($askOut.Count - 1)])
        $askOut = @('[truncated]') + $tail
      }
    }

    $summary = @()
    if ($hasHeader) { $summary += $HeaderLine }
    if ($hasAction) { $summary += $ActionLine }
    if ($hasDesc)   { $summary += $DescLine }
    $summary += $askOut
    if ($hasWorkDir) { $summary += $WorkingDirLine }
    return ,[string[]]$summary
  } catch {
    # fail-open: on any error return at least the header + action + working dir (never throw)
    $s = @()
    if (-not [string]::IsNullOrEmpty($HeaderLine)) { $s += $HeaderLine }
    if (-not [string]::IsNullOrEmpty($ActionLine)) { $s += $ActionLine }
    if (-not [string]::IsNullOrEmpty($WorkingDirLine)) { $s += $WorkingDirLine }
    return ,[string[]]$s
  }
}

try {
  # --- read the hook event from stdin (the harness pipes JSON) ---
  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
  $evt = $null
  try { $evt = ConvertFrom-Json -InputObject $raw } catch { exit 0 }
  if ($null -eq $evt) { exit 0 }

  $eventName = ''
  try { $eventName = [string]$evt.hook_event_name } catch { $eventName = '' }
  $message = ''
  try { $message = [string]$evt.message } catch { $message = '' }
  $sessionId = ''
  try { $sessionId = [string]$evt.session_id } catch { $sessionId = '' }
  $cwd = ''
  try { $cwd = [string]$evt.cwd } catch { $cwd = '' }
  $transcript = ''
  try { $transcript = [string]$evt.transcript_path } catch { $transcript = '' }
  $promptText = ''
  try { $promptText = [string]$evt.prompt } catch { $promptText = '' }

  # --- test-seam guard: -LedgerPath without -TestModeDir would LIVE-send deduped against
  # a scratch ledger (anti-runaway sidestep). The seams are fixture-only and travel
  # together => refuse the lone-ledger combination outright (fail-closed for the seam).
  if ((-not [string]::IsNullOrEmpty($LedgerPath)) -and [string]::IsNullOrEmpty($TestModeDir)) { exit 0 }

  # --- session identity (naming, both send paths) ---
  $tree = Get-NeoHookTreeLabel -c $cwd
  $uuid8 = 'no-id'
  if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
    $t8 = $sessionId
    if ($t8.Length -gt 8) { $t8 = $t8.Substring(0, 8) }
    $c8 = Get-NeoHookCharsetName -s $t8 -max 8
    if ($c8 -match '[A-Za-z0-9_]') { $uuid8 = $c8 }
  }
  if (-not [string]::IsNullOrEmpty($TestModeDir)) {
    $namesDir = Join-Path $TestModeDir 'session_names'    # seams travel together (fixtures)
  } else {
    $namesDir = Join-Path $env:USERPROFILE '.neo_notify\session_names'
  }
  $nameFile = ''
  if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
    $safeSid = Get-NeoHookCharsetName -s $sessionId -max 80
    if ($safeSid -match '[A-Za-z0-9_]') { $nameFile = Join-Path $namesDir ($safeSid + '.txt') }
  }

  # --- resolve session name + description from the sidecar (spec sec 3.1 + addendum D2):
  # line 1 = friendly NAME (sanitized to the module charset, cap 60), line 2 = one-line
  # DESCRIPTION (ASCII, cap ~80; NEW - the adapter emits a 'Desc:' line when present).
  # The sidecar is the AUTHORITY (D2); auto-capture only writes-when-absent, so a
  # manager-authored value always wins once written. Fallback name = <tree>-<uuid8>. ---
  $sessionName = ''
  $sessionDesc = ''
  try {
    if ($nameFile -ne '' -and (Test-Path -LiteralPath $nameFile)) {
      $nraw = [System.IO.File]::ReadAllText($nameFile)
      $nlines = @($nraw -split "`n")
      $nfirst = ([string]$nlines[0]).TrimEnd("`r")
      $sessionName = Get-NeoHookCharsetName -s $nfirst -max 60
      if ($nlines.Count -ge 2) {
        $nsecond = ([string]$nlines[1]).TrimEnd("`r")
        $sessionDesc = Get-NeoHookAsciiLine -s $nsecond -max 80
      }
    }
  } catch { $sessionName = ''; $sessionDesc = '' }
  if ($sessionName -notmatch '[A-Za-z0-9_]') { $sessionName = $tree + '-' + $uuid8 }
  $headerLine = Get-NeoHookAsciiLine -s ('Session: ' + $sessionName + ' | id ' + $uuid8 + ' | tree: ' + $tree) -max 200
  $descLine = ''
  if (-not [string]::IsNullOrWhiteSpace($sessionDesc)) { $descLine = Get-NeoHookAsciiLine -s ('Desc: ' + $sessionDesc) -max 200 }
  $workDirLine = ''
  if (-not [string]::IsNullOrWhiteSpace($cwd)) { $workDirLine = Get-NeoHookAsciiLine -s ('Working dir: ' + $cwd) -max 200 }

  # --- event map (unknown => no send; the class restriction is the cap; CASE-EXACT:
  # only the literal harness event names map - 'STOP'/'notification' do NOT) ---
  $gateType = ''
  $summary = @()
  switch -CaseSensitive ($eventName) {
    'UserPromptSubmit' {
      # write-once session-name capture from the FIRST prompt; NEVER sends; exit 0 always.
      # This name file is the adapter's ONLY write surface (outside the governed trees).
      try {
        if ($nameFile -ne '' -and (-not (Test-Path -LiteralPath $nameFile))) {
          if (-not [string]::IsNullOrWhiteSpace($promptText)) {
            $cand = $promptText
            $sidM = [regex]::Match($promptText, '(?i)Session[ _]id:\s*([A-Za-z0-9_][A-Za-z0-9_.-]*)')
            if ($sidM.Success) { $cand = ($sidM.Groups[1].Value).TrimEnd('.','-','_') }
            if ($cand.Length -gt 200) { $cand = $cand.Substring(0, 200) }
            $nm = Get-NeoHookCharsetName -s $cand -max 60
            # A1 REJECT-FILTER (spec sec 3.2 + addendum D3): store only when the candidate
            # looks like a real slug AND passes the reject-filter (checked against BOTH the
            # raw candidate and the sanitized form, separator-tolerant). On reject: do NOT
            # write - the clean <tree>-<uuid8> fallback applies. A MULTI-char single-token
            # slug (ems005, neo49, notify-tracker-ux) is ACCEPTED.
            if (($nm -match '[A-Za-z0-9_]') -and (-not (Test-NeoHookRejectCapture -Raw $cand -Sanitized $nm))) {
              if (-not (Test-Path -LiteralPath $namesDir)) {
                New-Item -ItemType Directory -Force -Path $namesDir | Out-Null
              }
              [System.IO.File]::WriteAllText($nameFile, $nm, [System.Text.Encoding]::ASCII)
            }
          }
        }
      } catch { }
      exit 0
    }
    'Notification' {
      if ($message -match '(?i)permission') { $gateType = 'APPROVAL_NEEDED' }
      else { exit 0 }
      # GOAL-1 field set (secs 1.2/1.3): header + ACTION NEEDED + Desc (droppable) + the
      # ask block (the retained Notification composition lines) + working dir. Budgeted to
      # <= 11 caller lines so the module's single prepend keeps the total <= 12.
      $actionLine = Get-NeoHookActionNeeded -GateType $gateType
      $askLines = @()
      $askLines += ('Harness friction event: ' + $eventName)
      if (-not [string]::IsNullOrWhiteSpace($message)) { $askLines += ('Message: ' + $message) }
      $askLines += 'Auto-sent by the settings.json hook adapter (notify_hook.ps1) - no manager action.'
      $askLines += 'The in-chat session is the only decision surface; this mail is a record.'
      $summary = Get-NeoHookBudgetedSummary -HeaderLine $headerLine -ActionLine $actionLine `
                   -DescLine $descLine -AskLines $askLines -WorkingDirLine $workDirLine -Cap 11
    }
    'Stop' {
      $cls = Get-NeoHookStopClassification -TranscriptPath $transcript
      if ($null -eq $cls) { exit 0 }   # SILENT rows: 8b / 10 / no extractable message
      $gateType = [string]$cls.gate
      $ask = @($cls.ask)

      # A5 DOUBLE-FIRE BACKSTOP (addendum D1; SUPERSEDES spec sec 1.4 part 2): a READ-ONLY,
      # SILENT suppression step. Resolve T_open (prior-user entry timestamp) and read the
      # send ledger read-only; SUPPRESS this hook's own send (exit 0 WITHOUT sending and
      # WITHOUT writing any ledger row) iff a SENT row exists for the SAME <session-root>
      # slice + the SAME computed gate class with ts >= T_open (same yielded turn). If
      # T_open is unresolvable => do NOT suppress (fail-toward-mail). No new live write
      # surface is added (D1) - the suppression decision is observable in the fixture only
      # via -TestModeDir, never via a live-ledger write.
      $suppressLedger = $LedgerPath
      if ([string]::IsNullOrEmpty($suppressLedger)) {
        # LIVE path reads the module's REAL ledger read-only (respecting the -TestModeDir
        # seam, which points the module's ledger into the test dir - same as the module).
        if (-not [string]::IsNullOrEmpty($TestModeDir)) { $suppressLedger = Join-Path $TestModeDir 'send_ledger.jsonl' }
        else { $suppressLedger = Join-Path $env:USERPROFILE '.neo_notify\send_ledger.jsonl' }
      }
      $tOpen = Get-NeoHookTurnOpenUtc -TranscriptPath $transcript
      if (Test-NeoHookLedgerSuppress -LedgerPath $suppressLedger -SliceId $sessionName -GateType $gateType -TOpenUtc $tOpen) {
        exit 0   # same-class same-turn duplicate already mailed by the manager => stand down
      }

      # GOAL-1 field set: header + ACTION NEEDED + Desc (droppable) + the VERBATIM ask
      # block (TAIL-kept, tail-trimmed with a '[truncated]' line) + working dir; <= 11.
      $actionLine = Get-NeoHookActionNeeded -GateType $gateType
      $summary = Get-NeoHookBudgetedSummary -HeaderLine $headerLine -ActionLine $actionLine `
                   -DescLine $descLine -AskLines $ask -WorkingDirLine $workDirLine -Cap 11
    }
    default { exit 0 }
  }

  $evidence = $transcript
  if ([string]::IsNullOrWhiteSpace($evidence)) { $evidence = $cwd }
  if ([string]::IsNullOrWhiteSpace($evidence)) { $evidence = '(no transcript path in event)' }
  $evidence = Get-NeoHookAsciiLine -s $evidence -max 200

  # --- dot-source the frozen module and fire exactly one capped call ---
  $modulePath = Join-Path $PSScriptRoot 'notify_raphael.ps1'
  if (-not (Test-Path -LiteralPath $modulePath)) { exit 0 }
  . $modulePath

  $callArgs = @{
    GateType     = $gateType
    SliceId      = $sessionName
    SummaryLines = $summary
    EvidencePath = $evidence
  }
  if (-not [string]::IsNullOrEmpty($TestModeDir)) { $callArgs['TestModeDir'] = $TestModeDir }
  else { $callArgs['LiveSend'] = $true }
  if (-not [string]::IsNullOrEmpty($LedgerPath)) { $callArgs['LedgerPath'] = $LedgerPath }

  $null = Send-NeoGateNotification @callArgs
  exit 0
} catch {
  # FAIL-OPEN: no failure mode of this adapter may block the session.
  exit 0
}
