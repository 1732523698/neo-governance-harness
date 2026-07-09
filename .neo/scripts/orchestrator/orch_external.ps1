# orch_external.ps1 - NEO 4.0-P4-AUTONOMY C4 AUTOMATED EXTERNAL-MODEL CHANNEL (the adapter).
# ASCII-only (D10). Dot-source; defines functions only. THE ONLY MODULE THAT MAY LAUNCH
# THE EXTERNAL PROCESS: the live invoker (Invoke-NeoExternalCodex) lives HERE and nowhere
# else - orch_loop consumes this module's OUTPUT (on-disk records) through the shared
# derivation, never a process. Binding spec: NEO_SELF_ITERATION_DESIGN_v3_1.md (10652365)
# sec-4 C4 (lane split + round binding + HIGH fail-closed), sec-7 (channel), sec-0/NB-4
# (tamper-EVIDENT supervisor stamps; END evidence), sec-6 invariant 1 (channel
# independence). Governed by the DEF-P7 attestation (FE439FDD, IN FORCE): OpenAI Codex
# via `codex exec` subscription auth ONLY; credential file EXISTENCE-checked, contents
# NEVER read/printed/logged; read-only verdict-only; caps: manifest max_external_calls
# per run (configured authority, never hardcoded) + <=3/HIGH-slice sub-cap (the
# attested constant below).
#
# LANE SPLIT (spec C4): the parsed verdict becomes a `neo:external_audit_verdict`
# record - NEVER an AUDIT_RESULT; the auditor slot seam never reads it; the sec-0
# spawn-ledger correlation keeps the slot closed to it.
#
# WRITE-AHEAD BUDGET - EXACT ORDER per attempt (dispatch 3.A.3, R4-F1):
#   (i)   SUB-CAP CHECK (fail-closed read of the per-slice ledger): counting this
#         attempt, over <=3/HIGH-slice => a REFUSED per-slice entry lands (shape 2:
#         NO run-ledger reference at all), NO run-ledger append, NO launch, lane MISSING.
#   (ii)  run-level write-ahead via the FROZEN Add-NeoRunExternalCallEntry;
#         refused => a REFUSED per-slice entry lands (shape 3: the refusing
#         post_increment_count MARKED REFUSED), NO launch, lane MISSING.
#   (iii) the NON-REFUSED per-slice entry lands (shape 1: round id + bundle/diff hash
#         + post_increment_count + CONSUMED) - THEN the process launches. An entry-write
#         failure aborts the launch (LEDGER_FAILURE => lane MISSING).
# Every launch attempt is counted at BOTH levels; no retry path dodges either ledger.
#
# MODEL PIN (dispatch 3.A.7, R6-F2): the CLI-reported banner id must equal the pinned
# constant below - enforced at CALL time (parser) AND USE time (derivation): check==use
# at both boundaries; the pin authority is THIS single module constant (the schema
# deliberately does not double-pin it). Pinned from the dispatch (manager-grounded live
# 2026-07-07); NEVER discovered by a live call (R9-F3).
#
# REUSE (READ-ONLY, no frozen edit): orch_supervisor.ps1 (frozen run-ledger machinery:
# Add-NeoRunExternalCallEntry, Read-NeoRunLedgerEntries, the shared external-call shape
# guard, Resolve-NeoRunStatePath, timestamps, manifest) -> _neo_root + orch_io
# (-> orch_schema + orch_class). Idempotent re-source (functions + script vars only).
$script:NeoExternalDir = $PSScriptRoot
. "$script:NeoExternalDir\orch_supervisor.ps1"

# ---- constants ------------------------------------------------------------------
# The DEF-P7-attested channel pin: every plan-audit codex run printed `model: gpt-5.5`
# in the banner (manager-grounded 2026-07-07). Drift is surfaced by the manager's END
# smoke, never by a silent pin weakening here.
$script:NeoExternalPinnedModelId       = 'gpt-5.5'
# DEF-P7 <=3 external calls / HIGH slice (attested; the run manifest carries NO
# per-slice field - this constant is the sub-cap's single authority).
$script:NeoExternalSliceSubCap         = 3
$script:NeoExternalSliceCallLedgerLeaf = 'external_slice_call_ledger.jsonl'
$script:NeoExternalVerdictLedgerLeaf   = 'external_verdict_ledger.jsonl'
$script:NeoExternalDefaultTimeoutSec   = 300
$script:NeoExternalAttestationRel      = 'NEO_SESSION\_neo_roadmap\DEF-P7_EXTERNAL_MODEL_ATTESTATION.md'
$script:NeoExternalFindingsCap         = 1800   # < the schema's 2000-char pattern cap

# ---- small helpers ----------------------------------------------------------------
# Printable-ASCII sanitizer ('?' substitution) + hard cap; the composition-side twin of
# the schema's ^[ -~]{0,2000}$ findings pattern (check==use: the schema re-checks).
function ConvertTo-NeoExternalAsciiLine([string]$Text, [int]$MaxLen = 200) {
  if ($null -eq $Text) { return '' }
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $Text.ToCharArray()) {
    $code = [int]$ch
    if ($code -ge 0x20 -and $code -le 0x7E) { [void]$sb.Append($ch) } else { [void]$sb.Append('?') }
    if ($sb.Length -ge $MaxLen) { break }
  }
  return $sb.ToString()
}

# Default DEF-P7 attestation path: resolved from the governed root (C2-fix precedent -
# Resolve-NeoRoot $PSScriptRoot), never a relative-cwd guess.
function Resolve-NeoExternalAttestationPath {
  $root = Resolve-NeoRoot $script:NeoExternalDir
  return (Join-Path $root $script:NeoExternalAttestationRel)
}

# ---- (1) attestation gate (notify_raphael.ps1:129-149 pattern, REPLICATED not
# imported): file present + line-anchored 'STATUS: **APPROVED / IN FORCE' stamp + no
# REVOKED stamp. Returns '' when in force, else the refusal reason. EVERY failure mode
# (missing/unreadable/unstamped/revoked) refuses - fail-closed.
function Get-NeoExternalAttestationRefusal([string]$AttestationPath) {
  try {
    if ([string]::IsNullOrWhiteSpace($AttestationPath)) {
      return 'refused: external channel blocked - attestation path is blank (fail-closed)'
    }
    if (-not (Test-Path -LiteralPath $AttestationPath)) {
      return "refused: external channel blocked - DEF-P7 attestation file not found at '$AttestationPath' (fail-closed)"
    }
    $lines = @(Get-Content -LiteralPath $AttestationPath -ErrorAction Stop)
    $inForce = $false
    foreach ($ln in $lines) {
      if ($ln -match '^STATUS: \*\*APPROVED / IN FORCE') { $inForce = $true }
      if ($ln -match '^\s*REVOKED\b' -or $ln -match '^\s*STATUS:.*REVOKED') {
        return 'refused: external channel blocked - DEF-P7 attestation carries a REVOKED status stamp (fail-closed; HIGH falls back to manual-external via Raphael)'
      }
    }
    if (-not $inForce) {
      return 'refused: external channel blocked - DEF-P7 attestation is not stamped APPROVED / IN FORCE (fail-closed)'
    }
    return ''
  } catch {
    return "refused: external channel blocked - DEF-P7 attestation unreadable ($($_.Exception.Message)) (fail-closed)"
  }
}

# ---- (2) credential EXISTENCE check ONLY (DEF-P7): the file's contents are NEVER
# read, printed, logged, or hashed; only location-by-name appears in messages.
function Test-NeoExternalCredentialPresent([string]$CredentialPath) {
  if ([string]::IsNullOrWhiteSpace($CredentialPath)) { return $false }
  return [bool](Test-Path -LiteralPath $CredentialPath -PathType Leaf)
}
function Resolve-NeoExternalCredentialPath {
  return (Join-Path $env:USERPROFILE '.codex\auth.json')
}

# ---- per-slice accounting ledger (C4's OWN; the run-scope '__run__' ledger CANNOT
# serve the sub-cap - its entries carry the reserved run scope). Fail-closed read
# discipline identical to the S1 ledgers: unreadable/unparseable/schema-invalid/
# non-monotonic => LEDGER_FAILURE BLOCK, NEVER treated as empty (dispatch 3.E.17).
function Assert-NeoExternalSliceCallEntriesShape($Entries) {
  $n = 0
  foreach ($e in @($Entries)) {
    $n++
    $sid = [string](Get-NeoProp $e 'slice_id')
    if ($sid -ceq $script:NeoRunExternalSliceId) {
      New-NeoBlock "reason_code=LEDGER_FAILURE external_slice_call_ledger: line $n slice_id '$($script:NeoRunExternalSliceId)' is RESERVED for the run-scope external-call ledger => STOP (reservation symmetric across ledgers, check==use)"
    }
  }
}
# Per-slice slice_call_seq monotonicity (strict +1 from 1 per slice, file order) -
# the Assert-NeoRunLedgerMonotone discipline keyed on THIS ledger's field name.
function Assert-NeoExternalSliceLedgerMonotone($Entries) {
  $last = @{}
  $n = 0
  foreach ($e in @($Entries)) {
    $n++
    $sid = [string](Get-NeoProp $e 'slice_id')
    $seq = [int](Get-NeoProp $e 'slice_call_seq')
    $expected = 1
    if ($last.ContainsKey($sid)) { $expected = [int]$last[$sid] + 1 }
    if ($seq -ne $expected) {
      New-NeoBlock "reason_code=LEDGER_FAILURE external_slice_call_ledger: monotonicity violation at line $n - slice '$sid' slice_call_seq $seq, expected $expected (gap or regress) => STOP + surface, never repair-and-continue"
    }
    $last[$sid] = $seq
  }
}
function Read-NeoExternalSliceCallEntries {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)]$Index,
    [Parameter(Mandatory=$true)][string]$ExpectedRunId
  )
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoExternalSliceCallLedgerLeaf
  if (-not (Test-Path -LiteralPath $path)) { return ,@() }
  $entries = Read-NeoRunLedgerEntries -Path $path -SchemaId 'neo:external_slice_call_entry' -Index $Index `
    -Label 'external_slice_call_ledger' -ExpectedRunId $ExpectedRunId
  Assert-NeoExternalSliceCallEntriesShape $entries
  Assert-NeoExternalSliceLedgerMonotone $entries
  return ,@($entries)
}

# ---- (3/4) per-slice entry writer - the THREE SHAPES of dispatch 3.A.3 (the schema
# encodes them fail-closed; this writer builds exactly one of them and never mixes).
# Returns @{ entry; slice_call_seq }.
function Add-NeoExternalSliceCallEntry {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$SliceId,
    [Parameter(Mandatory=$true)][string]$RoundId,
    [Parameter(Mandatory=$true)][string]$BundleDiffHash,
    [Parameter(Mandatory=$true)][string]$Timestamp,
    [Parameter(Mandatory=$true)][ValidateSet('consumed','subcap_refusal','runcap_refusal')][string]$Shape,
    [int]$PostIncrementCount = 0
  )
  [void](ConvertFrom-NeoRunTimestamp $Timestamp 'Timestamp' 'LEDGER_FAILURE')
  if ([string]::IsNullOrWhiteSpace($SliceId)) { New-NeoBlock 'reason_code=LEDGER_FAILURE external_slice_call_ledger: SliceId is blank => STOP' }
  if ($SliceId -ceq $script:NeoRunExternalSliceId) { New-NeoBlock "reason_code=LEDGER_FAILURE external_slice_call_ledger: SliceId '$($script:NeoRunExternalSliceId)' is RESERVED for the run-scope ledger => STOP" }
  $manifest = Read-NeoRunManifest -RunRoot $RunRoot
  $runId = [string](Get-NeoProp $manifest 'run_id')
  $Index = Get-NeoRunSchemaIndex
  # assignment form, NOT @(call) - the engine family's ,@() return keeps the entry
  # array whole as ONE stream object; @(call) would nest it (loop-suite convention).
  $entries = Read-NeoExternalSliceCallEntries -RunRoot $RunRoot -Index $Index -ExpectedRunId $runId
  $mine = @($entries | Where-Object { ([string](Get-NeoProp $_ 'slice_id')) -ceq $SliceId })
  $seq = $mine.Count + 1
  $entry = $null
  switch ($Shape) {
    'consumed' {
      if ($PostIncrementCount -lt 1) { New-NeoBlock 'reason_code=LEDGER_FAILURE external_slice_call_ledger: a consumed entry requires the real post_increment_count (>=1) => STOP' }
      $entry = [pscustomobject]@{
        run_id = $runId; slice_id = $SliceId; slice_call_seq = $seq; refused = $false; reason = 'NONE'
        timestamp_utc = $Timestamp; round_id = $RoundId; bundle_diff_hash = $BundleDiffHash
        post_increment_count = $PostIncrementCount; run_ledger_ref_kind = 'CONSUMED'
      }
    }
    'subcap_refusal' {
      # shape 2: NO run-ledger reference AT ALL (none exists by design).
      $entry = [pscustomobject]@{
        run_id = $runId; slice_id = $SliceId; slice_call_seq = $seq; refused = $true; reason = 'CAP_EXTERNAL_SLICE'
        timestamp_utc = $Timestamp; round_id = $RoundId; bundle_diff_hash = $BundleDiffHash
      }
    }
    'runcap_refusal' {
      if ($PostIncrementCount -lt 1) { New-NeoBlock 'reason_code=LEDGER_FAILURE external_slice_call_ledger: a run-cap refusal entry requires the REFUSING post_increment_count (>=1) => STOP' }
      $entry = [pscustomobject]@{
        run_id = $runId; slice_id = $SliceId; slice_call_seq = $seq; refused = $true; reason = 'CAP_EXTERNAL_CALLS'
        timestamp_utc = $Timestamp; round_id = $RoundId; bundle_diff_hash = $BundleDiffHash
        post_increment_count = $PostIncrementCount; run_ledger_ref_kind = 'REFUSED'
      }
    }
  }
  Assert-NeoValid $entry 'neo:external_slice_call_entry' $Index 'EXTERNAL_SLICE_CALL_ENTRY(append)'
  $path = Resolve-NeoRunStatePath $RunRoot $script:NeoExternalSliceCallLedgerLeaf
  [void](Add-NeoRunJsonlLine $path $entry 'external_slice_call_ledger')
  return @{ entry = $entry; slice_call_seq = $seq }
}

# ---- (5) packet assembly - FAIL-HARD (dispatch 3.A.4; the S3b packet-corruption
# lesson: never a silently truncated packet). Self-contained ASCII packet from the
# CURRENT round's audit bundle: every member SafeRel + contained under SessionRoot,
# byte-identity VERIFIED (re-hash == recorded content_hash), printable-ASCII enforced.
# NEVER inlined: the codex credential, any secret, any path outside the bundle
# (structural: ONLY allowlist members are read, all contained under SessionRoot).
function New-NeoExternalPacket {
  param(
    [Parameter(Mandatory=$true)]$Bundle,          # the parsed, already-validated AUDIT_BUNDLE object
    [Parameter(Mandatory=$true)][string]$SessionRoot,
    [Parameter(Mandatory=$true)][string]$PacketDir,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SliceId,
    [Parameter(Mandatory=$true)][string]$RoundId,
    [Parameter(Mandatory=$true)][string]$BundleDiffHash
  )
  if (-not (Test-Path -LiteralPath $PacketDir -PathType Container)) { New-NeoBlock "external packet: PacketDir '$PacketDir' is not an existing directory => hard failure" }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('==== NEO C4 EXTERNAL AUDIT PACKET (READ-ONLY; VERDICT-ONLY) ====')
  [void]$sb.AppendLine('run_id: ' + $RunId)
  [void]$sb.AppendLine('slice_id: ' + $SliceId)
  [void]$sb.AppendLine('round_id: ' + $RoundId)
  [void]$sb.AppendLine('bundle_diff_hash: ' + $BundleDiffHash)
  [void]$sb.AppendLine('INSTRUCTIONS: You are an independent external auditor. Review the inlined')
  [void]$sb.AppendLine('slice source below for defects, contract violations and risky behavior.')
  [void]$sb.AppendLine('You MUST NOT modify anything. Reply with EXACTLY ONE line of the form')
  [void]$sb.AppendLine('VERDICT: GO   or   VERDICT: NEEDS-MORE   or   VERDICT: NO-GO')
  [void]$sb.AppendLine('followed by one line: FINDINGS: <single-line ASCII summary>.')
  $memberCount = 0
  foreach ($m in @($Bundle.allowlist)) {
    $rel = [string](Get-NeoProp $m 'path')
    Assert-NeoSafeRel $rel
    $full = Assert-NeoContained $SessionRoot $rel
    if (-not (Test-Path -LiteralPath $full)) { New-NeoBlock "external packet: bundle member '$rel' missing on disk => hard failure (lane MISSING)" }
    $actual = Get-NeoSha256File $full
    $recorded = [string](Get-NeoProp $m 'content_hash')
    if ($actual -cne $recorded) { New-NeoBlock "external packet: bundle member '$rel' byte-identity FAILED (re-hash != recorded content_hash) => hard failure (lane MISSING; never a silently corrupted packet)" }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    # byte-identity is the RAW-BYTES re-hash above; for the ASCII RENDERING a
    # leading UTF-8 BOM (EF BB BF - what PS 5.1 'UTF8' writers emit) is stripped,
    # then EVERY remaining byte must be ASCII (anything else => hard failure).
    $start = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $start = 3 }
    for ($bi = $start; $bi -lt $bytes.Length; $bi++) {
      if ($bytes[$bi] -gt 0x7F) { New-NeoBlock "external packet: bundle member '$rel' carries non-ASCII bytes - the packet is ASCII-only by contract => hard failure (lane MISSING)" }
    }
    $memberCount++
    [void]$sb.AppendLine('==== MEMBER ' + $rel + ' (sha256 ' + $recorded + ') ====')
    [void]$sb.AppendLine([System.Text.Encoding]::ASCII.GetString($bytes, $start, ($bytes.Length - $start)))
  }
  if ($memberCount -eq 0) { New-NeoBlock 'external packet: bundle allowlist is empty - an empty packet is not an audit => hard failure' }
  [void]$sb.AppendLine('==== END OF PACKET ====')
  $packetPath = Join-Path $PacketDir 'packet.txt'
  [System.IO.File]::WriteAllText($packetPath, $sb.ToString(), [System.Text.Encoding]::ASCII)
  # post-write verification: the packet file itself must exist and be non-empty.
  if (-not (Test-Path -LiteralPath $packetPath) -or ((Get-Item -LiteralPath $packetPath).Length -eq 0)) {
    New-NeoBlock 'external packet: packet.txt failed to land on disk => hard failure'
  }
  return @{ packet_path = $packetPath; member_count = $memberCount }
}

# ---- (6) THE LIVE INVOKER - the ONLY function in the whole engine that may launch
# the external process. SHIPS DARK this slice: no suite path reaches it (fixtures
# inject -InvokerSeam; the suite tripwires this function); the manager's one-time
# attested END smoke exercises it under the working tally. Proven invocation shape
# (2026-07-05 smoke + all SC audit runs): stdin MUST be closed or codex HANGS
# (cmd /c ... < NUL), -s read-only, -C <isolated packet dir>, --skip-git-repo-check.
# Timeout/hang/zero-output/nonzero-exit => CLI_ERROR class (=> lane MISSING).
function Invoke-NeoExternalCodex {
  param(
    [Parameter(Mandatory=$true)][string]$PacketDir,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [Parameter(Mandatory=$true)][int]$TimeoutSec
  )
  if ($TimeoutSec -lt 1) { New-NeoBlock 'external invoker: TimeoutSec must be a positive integer => STOP (a boundless external call is never acceptable)' }
  if (-not (Test-Path -LiteralPath $PacketDir -PathType Container)) { New-NeoBlock "external invoker: PacketDir '$PacketDir' is not an existing directory => STOP" }
  $prompt = 'Read the file packet.txt in the working directory and perform the audit it specifies. Reply with exactly one line VERDICT: GO or VERDICT: NEEDS-MORE or VERDICT: NO-GO, then one line FINDINGS: <ascii summary>.'
  $cmdLine = 'codex exec -s read-only -C "' + $PacketDir + '" --skip-git-repo-check "' + $prompt + '" < NUL > "' + $OutFile + '" 2>&1'
  $proc = $null
  try {
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', $cmdLine) -PassThru -WindowStyle Hidden
  } catch {
    return @{ ok = $false; class = 'CLI_ERROR'; detail = ('launch failed: ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 160)) }
  }
  if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
    try { $proc.Kill() } catch { }
    return @{ ok = $false; class = 'CLI_ERROR'; detail = ('timeout after ' + $TimeoutSec + 's - process killed (hung-call class)') }
  }
  $exit = $proc.ExitCode
  if ($exit -ne 0) { return @{ ok = $false; class = 'CLI_ERROR'; detail = ('nonzero exit code ' + $exit) } }
  if (-not (Test-Path -LiteralPath $OutFile) -or ((Get-Item -LiteralPath $OutFile).Length -eq 0)) {
    return @{ ok = $false; class = 'CLI_ERROR'; detail = 'zero output (empty/absent output file)' }
  }
  return @{ ok = $true; class = 'OK'; detail = ('exit 0; output ' + (Get-Item -LiteralPath $OutFile).Length + ' bytes') }
}

# ---- (7) parser - assistant-final-region-bound verdict (all-agree within the region)
# + the CALL-TIME model pin (R6-F2). The verdict/findings bind to the AUTHENTIC assistant
# region (after the LAST ^codex$ turn) so a planted verdict in the packet-echo/tool-output
# region cannot be returned (plan-audit R1 fail-open closed); codex's duplicate-final is
# accepted by the all-agree rule. Anything else => UNPARSEABLE. The pin failure is a
# POST-OUTPUT determination: the launched call was legitimately counted at both levels
# (R7-F3) - never modeled as preflight.
function Read-NeoExternalCodexVerdict([string]$OutFile) {
  if ([string]::IsNullOrWhiteSpace($OutFile) -or -not (Test-Path -LiteralPath $OutFile) -or ((Get-Item -LiteralPath $OutFile).Length -eq 0)) {
    return @{ class = 'CLI_ERROR'; detail = 'output file absent or empty (zero-output class)' }
  }
  $text = ''
  try { $text = [System.IO.File]::ReadAllText($OutFile) }
  catch { return @{ class = 'CLI_ERROR'; detail = ('output file unreadable: ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 120)) } }
  # CALL-TIME MODEL PIN: the AUTHENTICATED CLI BANNER must report the pinned model id.
  # The pin binds to the HEADER REGION ONLY - the text BEFORE the first turn marker
  # (^user$) - so response-body text that echoes 'model: <id>' can NOT satisfy the
  # channel-identity check (R6-F2). No ^user$ turn boundary => the output lacks the
  # authenticated banner structure => UNPARSEABLE (fail-closed; never trust body text).
  $um = [regex]::Match($text, '(?m)^user\s*$')
  if (-not $um.Success) {
    return @{ class = 'UNPARSEABLE'; detail = 'CLI banner turn boundary (^user$) ABSENT - the output lacks the authenticated banner structure; the model pin cannot bind to a header region => UNPARSEABLE (fail-closed)' }
  }
  $header = $text.Substring(0, $um.Index)
  $mm = [regex]::Match($header, '(?m)^model:\s*(\S+)\s*$')
  if (-not $mm.Success) {
    return @{ class = 'UNPARSEABLE'; detail = 'model banner ABSENT from the CLI header region (before the first ^user$ turn) - the pinned-channel check cannot pass => UNPARSEABLE (fail-closed)' }
  }
  $mid = [string]$mm.Groups[1].Value
  if ($mid -cne $script:NeoExternalPinnedModelId) {
    return @{ class = 'UNPARSEABLE'; detail = ('CLI-reported model id ''' + (ConvertTo-NeoExternalAsciiLine $mid 40) + ''' != pinned ''' + $script:NeoExternalPinnedModelId + ''' => UNPARSEABLE (not the DEF-P7-attested channel)'); model_id = $mid }
  }
  # ASSISTANT-FINAL-REGION BINDING (plan-audit R1, security-critical): the verdict +
  # findings are extracted ONLY from the AUTHENTIC assistant-final region - the text
  # AFTER the LAST codex turn marker (^codex$, the CLI's own column-0 turn line). The
  # transcript interleaves attacker-influenceable regions: the echoed PACKET (the audited
  # slice SOURCE, which a malicious builder controls) is echoed into tool-output/exec
  # blocks that live BEFORE the final codex turn. A planted column-0 'VERDICT: GO' in the
  # source would appear there; a whole-transcript scan would return it (FAIL-OPEN). Binding
  # to the last-^codex$ region excludes it (packet-echo/tool-output always precede the
  # authentic final turn). NO ^codex$ marker => the output lacks the authentic assistant
  # structure => UNPARSEABLE (fail-closed; never scan the whole transcript). This is the
  # VERDICT analog of the F2 banner-region binding.
  $cm = [regex]::Matches($text, '(?m)^codex\s*$')
  if ($cm.Count -eq 0) {
    return @{ class = 'UNPARSEABLE'; detail = 'assistant turn marker (^codex$) ABSENT - the output lacks the authentic assistant-final structure; verdict/findings cannot bind to an assistant region => UNPARSEABLE (fail-closed)'; model_id = $mid }
  }
  $lastCodex = $cm[$cm.Count - 1]
  $region = $text.Substring($lastCodex.Index + $lastCodex.Length)
  # ALL-AGREE within the assistant-final region (format-compatibility for codex's
  # duplicate-final message): codex ALWAYS prints its final message TWICE (inline + an
  # end-summary after 'tokens used'), so a real verdict carries >=2 identical anchored
  # VERDICT lines - both fall INSIDE this region. Collect all anchored matches: 0 =>
  # UNPARSEABLE; a DISTINCT (ordinal, case-exact) verdict set > 1 => UNPARSEABLE (genuine
  # contradiction, fail-closed, never pick one); else (>=1, all identical) => that verdict.
  $vm = [regex]::Matches($region, '(?m)^\s*VERDICT:\s*(GO|NEEDS-MORE|NO-GO)\s*$')
  if ($vm.Count -eq 0) {
    return @{ class = 'UNPARSEABLE'; detail = 'no anchored VERDICT line in the assistant-final region (after the last ^codex$) => UNPARSEABLE'; model_id = $mid }
  }
  $distinct = @($vm | ForEach-Object { [string]$_.Groups[1].Value } | Sort-Object -Unique -Culture '')
  if ($distinct.Count -ne 1) {
    return @{ class = 'UNPARSEABLE'; detail = ('contradictory verdicts in the assistant-final region (distinct set size ' + $distinct.Count + ') => UNPARSEABLE (fail-closed; never pick one)'); model_id = $mid }
  }
  $verdict = [string]$distinct[0]
  $fm = [regex]::Match($region, '(?m)^\s*FINDINGS:\s*(.*)$')
  $findings = ''
  if ($fm.Success) { $findings = ConvertTo-NeoExternalAsciiLine ([string]$fm.Groups[1].Value) $script:NeoExternalFindingsCap }
  return @{ class = 'OK'; verdict = $verdict; findings_summary = $findings; model_id = $mid; detail = ('parsed verdict ' + $verdict) }
}

# ---- verdict-ledger read (tolerant of foreign run_id/slice_id VALUES so the
# derivation can classify transplants as STALE per dispatch 3.C/3.E.12; every line
# must still be parseable + schema-valid - anything else BLOCKs => UNPARSEABLE lane).
function Read-NeoExternalVerdictEntries {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)]$Index
  )
  $lines = Read-NeoRunJsonlRawLines $Path 'external_verdict_ledger'
  $entries = @()
  $n = 0
  foreach ($ln in $lines) {
    $n++
    $obj = $null
    try { $obj = ($ln | ConvertFrom-Json) }
    catch { New-NeoBlock "reason_code=LEDGER_FAILURE external_verdict_ledger: line $n is UNPARSEABLE JSON => STOP + surface, never repair-and-continue" }
    if ($null -eq $obj) { New-NeoBlock "reason_code=LEDGER_FAILURE external_verdict_ledger: line $n parsed to null => STOP" }
    try { Assert-NeoValid $obj 'neo:external_audit_verdict' $Index "external_verdict_ledger line $n" }
    catch { New-NeoBlock "reason_code=LEDGER_FAILURE external_verdict_ledger: line $n schema-invalid: $($_.Exception.Message)" }
    $entries += $obj
  }
  return ,@($entries)
}

# ---- (9) THE SHARED LANE DERIVATION (dispatch 3.C) - ONE rule in ONE place, called
# at BOTH boundaries (adapter write side AND gate-C consumption side; check==use).
# Computes ExternalLaneStatus from the ON-DISK verdict record vs the FULL CURRENT
# BINDING TUPLE (run_id AND slice_id AND round_id AND bundle/diff hash) + the dual
# LEDGER RE-CORRELATION (F2/F3, re-read fail-closed at use time). Every error path
# fail-closed; no status outside the recognized set is ever returned.
#   record absent            => MISSING
#   any tuple-member mismatch=> STALE (treated missing; cross-run/cross-slice/
#                               old-round/old-hash transplants land here)
#   unreadable/schema-invalid/stamp-inconsistent/model-pin-fail/duplicate-tuple/
#   correlation-fail/ledger-unreadable => UNPARSEABLE
#   valid + full-tuple + correlated (ANY verdict): GO => GO, non-GO => NO_GO;
#                               correlation is required for EITHER (check==use, F1-fix)
function Get-NeoExternalLaneStatus {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$SliceId,
    [Parameter(Mandatory=$true)][string]$RoundId,
    [Parameter(Mandatory=$true)][string]$BundleDiffHash,
    $Index
  )
  try {
    if ([string]::IsNullOrWhiteSpace($SliceId) -or [string]::IsNullOrWhiteSpace($RoundId) -or [string]::IsNullOrWhiteSpace($BundleDiffHash)) {
      return @{ status = 'UNPARSEABLE'; reason = 'derivation inputs blank (slice/round/bundle hash) => fail-closed' }
    }
    if ($null -eq $Index) { $Index = Get-NeoRunSchemaIndex }
    $manifest = Read-NeoRunManifest -RunRoot $RunRoot
    $runId = [string](Get-NeoProp $manifest 'run_id')
    $vPath = Resolve-NeoRunStatePath $RunRoot $script:NeoExternalVerdictLedgerLeaf
    if (-not (Test-Path -LiteralPath $vPath)) {
      return @{ status = 'MISSING'; reason = 'no external verdict record exists for this run (verdict ledger absent)' }
    }
    # assignment form, NOT @(call) - see the reader-return convention note above.
    $all = Read-NeoExternalVerdictEntries -Path $vPath -Index $Index
    if (@($all).Count -eq 0) {
      return @{ status = 'MISSING'; reason = 'no external verdict record exists (verdict ledger empty)' }
    }
    $full = @($all | Where-Object {
      (([string](Get-NeoProp $_ 'run_id')) -ceq $runId) -and
      (([string](Get-NeoProp $_ 'slice_id')) -ceq $SliceId) -and
      (([string](Get-NeoProp $_ 'round_id')) -ceq $RoundId) -and
      (([string](Get-NeoProp $_ 'bundle_diff_hash')) -ceq $BundleDiffHash)
    })
    if ($full.Count -eq 0) {
      return @{ status = 'STALE'; reason = 'verdict record(s) exist but NONE matches the full current binding tuple (run_id+slice_id+round_id+bundle_diff_hash) => STALE, treated missing (transplant/replay refused)' }
    }
    if ($full.Count -gt 1) {
      return @{ status = 'UNPARSEABLE'; reason = ('' + $full.Count + ' verdict records match the SAME full binding tuple - duplicate-tuple ambiguity => UNPARSEABLE (fail-closed, never last-wins)') }
    }
    $rec = $full[0]
    # tamper-EVIDENT stamp: re-derive the body hash (excluding the stamp field itself).
    $expectedSha = Get-NeoBodyHash $rec @('record_sha256')
    if ($expectedSha -cne [string](Get-NeoProp $rec 'record_sha256')) {
      return @{ status = 'UNPARSEABLE'; reason = 'verdict record record_sha256 does not re-derive (post-write edit detected; NB-4 tamper-EVIDENT) => UNPARSEABLE' }
    }
    # USE-TIME MODEL PIN (check==use with the call-time parser check).
    if (([string](Get-NeoProp $rec 'model_id')) -cne $script:NeoExternalPinnedModelId) {
      return @{ status = 'UNPARSEABLE'; reason = ('verdict record model_id ''' + (ConvertTo-NeoExternalAsciiLine ([string](Get-NeoProp $rec 'model_id')) 40) + ''' != pinned ''' + $script:NeoExternalPinnedModelId + ''' => UNPARSEABLE (not the attested channel)') }
    }
    $verdict = [string](Get-NeoProp $rec 'verdict')
    # ENUM GUARD FIRST: a verdict outside the recognized set never reaches correlation.
    if (($verdict -cne 'GO') -and (@('NEEDS-MORE', 'NO-GO') -cnotcontains $verdict)) {
      return @{ status = 'UNPARSEABLE'; reason = ('verdict ''' + (ConvertTo-NeoExternalAsciiLine $verdict 30) + ''' outside GO|NEEDS-MORE|NO-GO => UNPARSEABLE') }
    }
    # ---- LAUNCH-EVIDENCE CORRELATION for ANY verdict (check==use symmetry: a record
    # with no correlated CONSUMED ledger evidence is a record for a call that never
    # launched, so it is trusted for NEITHER a GO nor a non-GO). The GO reduction and
    # the non-GO reduction BOTH ride on this same one correlation block, run once here.
    # USE-TIME SUB-CAP (F3): the counted call must sit within <=3/HIGH-slice.
    $recSeq = [int](Get-NeoProp $rec 'slice_call_seq')
    if ($recSeq -gt $script:NeoExternalSliceSubCap) {
      return @{ status = 'UNPARSEABLE'; reason = ('verdict record slice_call_seq ' + $recSeq + ' exceeds the <=' + $script:NeoExternalSliceSubCap + '/HIGH-slice sub-cap => NO correlated launch (fail-closed)') }
    }
    $recCount = [int](Get-NeoProp $rec 'post_increment_count')
    # (a) run-level external-call ledger: full frozen shape (R5-F2 - the shared
    # helper + monotone guard, exactly as Add-NeoRunExternalCallEntry reads it;
    # never a thinner seq/run_id/refused-only match).
    $runLedPath = Resolve-NeoRunStatePath $RunRoot $script:NeoExternalCallLedgerLeaf
    if (-not (Test-Path -LiteralPath $runLedPath)) {
      return @{ status = 'UNPARSEABLE'; reason = 'verdict record but NO run-level external-call ledger exists - the counted call cannot correlate (no evidence a call launched) => UNPARSEABLE (fail-closed)' }
    }
    $runEntries = Read-NeoRunLedgerEntries -Path $runLedPath -SchemaId 'neo:attempt_ledger_entry' -Index $Index -Label 'external_call_ledger' -ExpectedRunId $runId
    Assert-NeoExternalCallLedgerEntriesShape $runEntries
    Assert-NeoRunLedgerMonotone $runEntries 'external_call_ledger'
    $runHit = @($runEntries | Where-Object {
      (([int](Get-NeoProp $_ 'seq')) -eq $recCount) -and (-not [bool](Get-NeoProp $_ 'refused'))
    })
    if ($runHit.Count -ne 1) {
      return @{ status = 'UNPARSEABLE'; reason = ('verdict record post_increment_count ' + $recCount + ' does not correlate with exactly one NON-refused run-ledger external_call entry (found ' + $runHit.Count + ') => NO correlated launch (fail-closed)') }
    }
    # (b) C4's per-slice accounting: same run + slice, matching slice_call_seq,
    # non-refused CONSUMED, AND (R3-F1/R4-F2) the recorded round/bundle-hash/count
    # EQUAL the verdict record's own binding values - a prior same-run/same-slice
    # counted call never correlates a later round's forged verdict.
    $sliceEntries = Read-NeoExternalSliceCallEntries -RunRoot $RunRoot -Index $Index -ExpectedRunId $runId
    $sliceHit = @($sliceEntries | Where-Object {
      (([string](Get-NeoProp $_ 'slice_id')) -ceq $SliceId) -and
      (([int](Get-NeoProp $_ 'slice_call_seq')) -eq $recSeq) -and
      (-not [bool](Get-NeoProp $_ 'refused')) -and
      (([string](Get-NeoProp $_ 'run_ledger_ref_kind')) -ceq 'CONSUMED') -and
      (([string](Get-NeoProp $_ 'round_id')) -ceq $RoundId) -and
      (([string](Get-NeoProp $_ 'bundle_diff_hash')) -ceq $BundleDiffHash) -and
      (([int](Get-NeoProp $_ 'post_increment_count')) -eq $recCount)
    })
    if ($sliceHit.Count -ne 1) {
      return @{ status = 'UNPARSEABLE'; reason = ('verdict record slice_call_seq ' + $recSeq + ' does not correlate with exactly one NON-refused CONSUMED per-slice entry carrying the SAME round/bundle-hash/post_increment_count binding (found ' + $sliceHit.Count + ') => NO correlated launch (fail-closed; stale/refused/forged counted-call refused)') }
    }
    # ---- REDUCE LAST, on the CORRELATED record: GO => GO; non-GO => NO_GO. ----
    if (@('NEEDS-MORE', 'NO-GO') -ccontains $verdict) {
      return @{ status = 'NO_GO'; reason = ('current-round external verdict is ' + $verdict + ' with correlated launch evidence (run-ledger seq ' + $recCount + ' + per-slice seq ' + $recSeq + '; record kept in full; lane reduced)') }
    }
    return @{ status = 'GO'; reason = ('current-round external GO: full tuple match + stamp re-derived + model pin + run-ledger seq ' + $recCount + ' + per-slice seq ' + $recSeq + ' correlated (tamper-EVIDENT; ledgers + record ride in END evidence)') }
  } catch {
    return @{ status = 'UNPARSEABLE'; reason = ('derivation failure (fail-closed): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 200)) }
  }
}

# ---- (8) THE ADAPTER - one live-invocation attempt, EXACT ORDER (3.A.1..3.A.7).
# Returns @{ lane; reason; stage; verdict; slice_call_seq; post_increment_count } -
# lane ALWAYS in the recognized set; the RETURN VALUE IS NEVER AUTHORITY (the caller
# and gate C re-derive from disk via Get-NeoExternalLaneStatus). -InvokerSeam is the
# suite's stub channel (notify TestModeDir precedent); $null => the live invoker.
function Invoke-NeoExternalAudit {
  param(
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$SliceId,
    [Parameter(Mandatory=$true)][string]$RoundId,
    [Parameter(Mandatory=$true)][string]$SessionRoot,
    [Parameter(Mandatory=$true)][string]$BundleRef,
    [Parameter(Mandatory=$true)][string]$Timestamp,
    [Parameter(Mandatory=$true)][string]$StampedBy,
    [string]$AttestationPath,
    [string]$CredentialPath,
    [int]$TimeoutSec = 0,
    $InvokerSeam
  )
  # contract validation (caller bugs are BLOCKs; environmental refusals are lanes).
  foreach ($pair in @(@('RunRoot',$RunRoot), @('SliceId',$SliceId), @('RoundId',$RoundId), @('SessionRoot',$SessionRoot), @('BundleRef',$BundleRef), @('StampedBy',$StampedBy))) {
    if ([string]::IsNullOrWhiteSpace([string]$pair[1])) { New-NeoBlock ("external adapter: parameter '" + $pair[0] + "' is blank => STOP (fail-closed)") }
  }
  [void](ConvertFrom-NeoRunTimestamp $Timestamp 'Timestamp' 'LEDGER_FAILURE')
  if ($TimeoutSec -eq 0) { $TimeoutSec = $script:NeoExternalDefaultTimeoutSec }
  if ($TimeoutSec -lt 1) { New-NeoBlock 'external adapter: TimeoutSec must be a positive integer => STOP (never a boundless call)' }
  if ([string]::IsNullOrWhiteSpace($AttestationPath)) { $AttestationPath = Resolve-NeoExternalAttestationPath }
  if ([string]::IsNullOrWhiteSpace($CredentialPath)) { $CredentialPath = Resolve-NeoExternalCredentialPath }
  if (($null -ne $InvokerSeam) -and -not ($InvokerSeam -is [scriptblock])) {
    New-NeoBlock 'external adapter: -InvokerSeam must be a scriptblock when supplied => STOP (fail-closed)'
  }

  # (3.A.1) ATTESTATION GATE FIRST on every live invocation path: refusal => no
  # process launched, NO ledger entry consumed at EITHER level (R3-F3), lane MISSING.
  $att = Get-NeoExternalAttestationRefusal $AttestationPath
  if ($att -cne '') {
    return @{ lane = 'MISSING'; stage = 'ATTESTATION'; reason = $att; verdict = ''; slice_call_seq = 0; post_increment_count = 0 }
  }
  # (3.A.2) credential EXISTENCE only; absent => refuse before any call.
  if (-not (Test-NeoExternalCredentialPresent $CredentialPath)) {
    return @{ lane = 'MISSING'; stage = 'CREDENTIAL'; reason = 'refused: external channel blocked - codex credential file absent (location-by-name %USERPROFILE%\.codex\auth.json; contents never read) => no call (fail-closed; HIGH falls back to manual-external via Raphael)'; verdict = ''; slice_call_seq = 0; post_increment_count = 0 }
  }

  # bundle: SafeRel + contained + schema-valid + intact envelope/self-hash; the
  # binding hash is the SHA-256 of the on-disk AUDIT_BUNDLE.json itself.
  $bundle = $null; $bundleDiffHash = ''
  try {
    Assert-NeoSafeRel $BundleRef
    $bundleFull = Assert-NeoContained $SessionRoot $BundleRef
    if (-not (Test-Path -LiteralPath $bundleFull)) { New-NeoBlock "external adapter: BundleRef '$BundleRef' resolves to no file" }
    $Index = Get-NeoRunSchemaIndex
    $bundle = Read-NeoJsonFile $bundleFull
    Assert-NeoValid $bundle 'neo:input_packet' $Index 'AUDIT_BUNDLE(external adapter)'
    Assert-NeoArtifactHash $bundle 'AUDIT_BUNDLE(external adapter)'
    Assert-NeoPacketSelfHash $bundle 'AUDIT_BUNDLE(external adapter)'
    $bundleDiffHash = Get-NeoSha256File $bundleFull
  } catch {
    return @{ lane = 'MISSING'; stage = 'BUNDLE'; reason = ('bundle validation failed (fail-closed): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 200)); verdict = ''; slice_call_seq = 0; post_increment_count = 0 }
  }

  $manifest = $null; $runId = ''
  try { $manifest = Read-NeoRunManifest -RunRoot $RunRoot; $runId = [string](Get-NeoProp $manifest 'run_id') }
  catch {
    return @{ lane = 'MISSING'; stage = 'MANIFEST'; reason = ('run manifest unreadable (fail-closed): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 160)); verdict = ''; slice_call_seq = 0; post_increment_count = 0 }
  }

  # (3.A.3.i) SUB-CAP CHECK - fail-closed read; a malformed ledger is LEDGER_FAILURE:
  # NOT treated as empty, NO fresh entry, NO run-budget burn, NO launch (3.E.17).
  $existing = $null
  try { $existing = Read-NeoExternalSliceCallEntries -RunRoot $RunRoot -Index (Get-NeoRunSchemaIndex) -ExpectedRunId $runId }
  catch {
    return @{ lane = 'MISSING'; stage = 'LEDGER_FAILURE'; reason = ('per-slice accounting ledger unreadable/malformed (LEDGER_FAILURE, fail-closed - never treated as empty): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 200)); verdict = ''; slice_call_seq = 0; post_increment_count = 0 }
  }
  $mine = @($existing | Where-Object { ([string](Get-NeoProp $_ 'slice_id')) -ceq $SliceId })
  $postSlice = $mine.Count + 1
  if ($postSlice -gt $script:NeoExternalSliceSubCap) {
    # counting this attempt => over the sub-cap: the REFUSED entry lands (shape 2),
    # NO run-ledger append (a sub-cap refusal never burns run budget), NO launch.
    try {
      $r = Add-NeoExternalSliceCallEntry -RunRoot $RunRoot -SliceId $SliceId -RoundId $RoundId -BundleDiffHash $bundleDiffHash -Timestamp $Timestamp -Shape 'subcap_refusal'
      return @{ lane = 'MISSING'; stage = 'SUBCAP'; reason = ('refused: <=' + $script:NeoExternalSliceSubCap + '/HIGH-slice sub-cap reached (this attempt would be per-slice call ' + $postSlice + '); refusal recorded (slice_call_seq ' + $r.slice_call_seq + '), NO run budget burned, NO call made'); verdict = ''; slice_call_seq = [int]$r.slice_call_seq; post_increment_count = 0 }
    } catch {
      return @{ lane = 'MISSING'; stage = 'LEDGER_FAILURE'; reason = ('sub-cap refusal entry failed to land (LEDGER_FAILURE): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 160)); verdict = ''; slice_call_seq = 0; post_increment_count = 0 }
    }
  }

  # (3.A.3.ii) run-level write-ahead via the FROZEN Add-NeoRunExternalCallEntry.
  $runRes = $null
  try { $runRes = Add-NeoRunExternalCallEntry -RunRoot $RunRoot -Timestamp $Timestamp }
  catch {
    return @{ lane = 'MISSING'; stage = 'LEDGER_FAILURE'; reason = ('run-level external-call ledger write-ahead failed (LEDGER_FAILURE): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 200)); verdict = ''; slice_call_seq = 0; post_increment_count = 0 }
  }
  if ([bool]$runRes.refused) {
    # run-cap refusal: the run-ledger entry LANDED refused (write-ahead); record the
    # per-slice shape-3 twin carrying the REFUSING count; NO launch.
    try {
      $r = Add-NeoExternalSliceCallEntry -RunRoot $RunRoot -SliceId $SliceId -RoundId $RoundId -BundleDiffHash $bundleDiffHash -Timestamp $Timestamp -Shape 'runcap_refusal' -PostIncrementCount ([int]$runRes.post_increment_count)
      return @{ lane = 'MISSING'; stage = 'RUNCAP'; reason = ('refused: run-level external-call cap reached (refusing post_increment_count ' + $runRes.post_increment_count + ', reason ' + $runRes.reason + '); write-ahead refusal recorded at both levels, NO call made'); verdict = ''; slice_call_seq = [int]$r.slice_call_seq; post_increment_count = [int]$runRes.post_increment_count }
    } catch {
      return @{ lane = 'MISSING'; stage = 'LEDGER_FAILURE'; reason = ('run-cap refusal per-slice entry failed to land (LEDGER_FAILURE): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 160)); verdict = ''; slice_call_seq = 0; post_increment_count = [int]$runRes.post_increment_count }
    }
  }

  # (3.A.3.iii) the NON-REFUSED per-slice entry lands (full binding) BEFORE launch.
  $sliceRes = $null
  try { $sliceRes = Add-NeoExternalSliceCallEntry -RunRoot $RunRoot -SliceId $SliceId -RoundId $RoundId -BundleDiffHash $bundleDiffHash -Timestamp $Timestamp -Shape 'consumed' -PostIncrementCount ([int]$runRes.post_increment_count) }
  catch {
    return @{ lane = 'MISSING'; stage = 'LEDGER_FAILURE'; reason = ('write-ahead per-slice consumed entry failed to land - LAUNCH ABORTED (LEDGER_FAILURE): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 160)); verdict = ''; slice_call_seq = 0; post_increment_count = [int]$runRes.post_increment_count }
  }
  $seq = [int]$sliceRes.slice_call_seq
  $cnt = [int]$runRes.post_increment_count

  # (3.A.4) packet assembly FAIL-HARD in an isolated scratch dir (owned + cleaned here).
  $packetDir = Join-Path $env:TEMP ('neo_external_pkt_' + [guid]::NewGuid().ToString('N'))
  $outFile = Join-Path $packetDir 'codex_output.txt'
  try {
    New-Item -ItemType Directory -Force -Path $packetDir | Out-Null
    try {
      [void](New-NeoExternalPacket -Bundle $bundle -SessionRoot $SessionRoot -PacketDir $packetDir -RunId $runId -SliceId $SliceId -RoundId $RoundId -BundleDiffHash $bundleDiffHash)
    } catch {
      return @{ lane = 'MISSING'; stage = 'PACKET'; reason = ('packet assembly hard failure (never a silently corrupted packet): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 200)); verdict = ''; slice_call_seq = $seq; post_increment_count = $cnt }
    }

    # (3.A.5) invocation - the seam (suite stub) or the live invoker. The attempt is
    # ALREADY counted at both levels; a seam/CLI failure is CLI_ERROR => lane MISSING.
    $inv = $null
    try {
      if ($null -ne $InvokerSeam) {
        $inv = & $InvokerSeam (@{ packet_dir = $packetDir; out_file = $outFile; timeout_sec = $TimeoutSec })
      } else {
        $inv = Invoke-NeoExternalCodex -PacketDir $packetDir -OutFile $outFile -TimeoutSec $TimeoutSec
      }
    } catch {
      return @{ lane = 'MISSING'; stage = 'CLI_ERROR'; reason = ('invoker THREW (CLI_ERROR class): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 160)); verdict = ''; slice_call_seq = $seq; post_increment_count = $cnt }
    }
    $invOk = (($null -ne $inv) -and (Test-NeoHasProp $inv 'ok') -and ([bool](Get-NeoProp $inv 'ok')))
    if (-not $invOk) {
      $d = ''
      if ($null -ne $inv) { $d = ConvertTo-NeoExternalAsciiLine ([string](Get-NeoProp $inv 'detail')) 160 }
      return @{ lane = 'MISSING'; stage = 'CLI_ERROR'; reason = ('external CLI failed (CLI_ERROR class - hang/timeout/zero-output/nonzero-exit): ' + $d); verdict = ''; slice_call_seq = $seq; post_increment_count = $cnt }
    }

    # (3.A.6/3.A.7) parse + call-time model pin.
    $parsed = Read-NeoExternalCodexVerdict $outFile
    $pclass = [string](Get-NeoProp $parsed 'class')
    if ($pclass -ceq 'CLI_ERROR') {
      return @{ lane = 'MISSING'; stage = 'CLI_ERROR'; reason = [string](Get-NeoProp $parsed 'detail'); verdict = ''; slice_call_seq = $seq; post_increment_count = $cnt }
    }
    if ($pclass -cne 'OK') {
      return @{ lane = 'UNPARSEABLE'; stage = 'PARSE'; reason = [string](Get-NeoProp $parsed 'detail'); verdict = ''; slice_call_seq = $seq; post_increment_count = $cnt }
    }

    # write the round-bound verdict record (JSONL line; tamper-EVIDENT stamp).
    try {
      $Index = Get-NeoRunSchemaIndex
      $attSha = Get-NeoSha256File $AttestationPath
      $rec = [pscustomobject]@{
        run_id = $runId; slice_id = $SliceId; round_id = $RoundId; bundle_diff_hash = $bundleDiffHash
        verdict = [string](Get-NeoProp $parsed 'verdict'); findings_summary = [string](Get-NeoProp $parsed 'findings_summary')
        model_id = [string](Get-NeoProp $parsed 'model_id'); timestamp_utc = $Timestamp
        attestation_ref = ($script:NeoExternalAttestationRel.Replace('\', '/') + '#sha256:' + $attSha)
        post_increment_count = $cnt; slice_call_seq = $seq; stamped_by = $StampedBy
      }
      $rec | Add-Member -NotePropertyName 'record_sha256' -NotePropertyValue (Get-NeoBodyHash $rec @('record_sha256'))
      Assert-NeoValid $rec 'neo:external_audit_verdict' $Index 'EXTERNAL_AUDIT_VERDICT(append)'
      $vPath = Resolve-NeoRunStatePath $RunRoot $script:NeoExternalVerdictLedgerLeaf
      [void](Add-NeoRunJsonlLine $vPath $rec 'external_verdict_ledger')
    } catch {
      return @{ lane = 'MISSING'; stage = 'LEDGER_FAILURE'; reason = ('verdict record failed to land (LEDGER_FAILURE, fail-closed): ' + (ConvertTo-NeoExternalAsciiLine $_.Exception.Message 160)); verdict = ''; slice_call_seq = $seq; post_increment_count = $cnt }
    }

    # boundary-1 derivation (check==use: gate C re-derives at consumption with the
    # SAME shared rule). The seam/adapter return is NEVER authority.
    $lane = Get-NeoExternalLaneStatus -RunRoot $RunRoot -SliceId $SliceId -RoundId $RoundId -BundleDiffHash $bundleDiffHash -Index (Get-NeoRunSchemaIndex)
    return @{ lane = [string]$lane.status; stage = 'DERIVED'; reason = [string]$lane.reason; verdict = [string](Get-NeoProp $parsed 'verdict'); slice_call_seq = $seq; post_increment_count = $cnt }
  } finally {
    # the adapter owns this scratch: clean it (packet + raw output ride nowhere else;
    # the parsed verdict + findings live in the record).
    try { if (Test-Path -LiteralPath $packetDir) { Remove-Item -Recurse -Force -LiteralPath $packetDir } } catch { }
  }
}
