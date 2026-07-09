# notify_raphael.ps1 - NEO P8-NOTIFY gate-notification module (Gmail SMTP).
# ASCII-only (D10). Dot-source; defines functions only. IMPLEMENTATION-CLASS (non-judging;
# unmatched by any artifact_classes.json glob => default_class=implementation for AS18).
#
# Governed by the DEF-P8 attestation (APPROVED / IN FORCE 2026-07-06):
#   NEO_SESSION\_neo_roadmap\DEF-P8_EMAIL_NOTIFY_ATTESTATION.md
# That record is the authority this module checks before ANY live send.
#
# CONTRACT (binding, from DEF-P8):
#   * OUTBOUND gate notifications ONLY, restricted to the FRICTION event classes:
#     DECISION_NEEDED / APPROVAL_NEEDED / SESSION_END / ESCALATION_STOP / BREAKER_TRIP.
#     Any other GateType => REFUSE. The event-class restriction IS the cap (no numeric cap).
#   * Recipient AND sender are CONFIG-RESOLVED (parameterized for distribution): env
#     NEO_NOTIFY_RECIPIENT / NEO_NOTIFY_SENDER, else %USERPROFILE%\.neo_notify\config.json
#     ({ "recipient": "...", "sender": "..." }), else a non-routable placeholder. A live
#     send with an unconfigured/placeholder address REFUSES fail-closed (never egresses).
#   * Content: subject "[NEO] <GateType> - <SliceId>"; body = SummaryLines (max 12 lines,
#     each <= 200 chars, printable ASCII) + one "Evidence: <path>" line + a fixed footer.
#     NOTHING else enters the mail. NO attachment capability exists AT ALL.
#   * AUTHORITY RULE (both directions): a failed send NEVER blocks a gate (this function
#     never throws to the caller for send-path failures); a successful send NEVER advances
#     a gate (a delivery is not an approval; the in-chat gate is the only decision surface).
#   * DEDUPE (anti-runaway, not a cap): an IDENTICAL attempt (GateType + SliceId +
#     summary SHA-256) within 10 minutes of a SENT ledger entry is deduplicated (ledgered,
#     not re-sent). The ledger is bookkeeping, never authority: if it cannot be written the
#     send still proceeds, with the failure noted honestly in .reason.
#   * LIVE path (-LiveSend) requires ALL of: the DEF-P8 attestation present with a
#     line-anchored 'STATUS: **APPROVED / IN FORCE' stamp and NO active REVOKED status
#     stamp; and the credential file EXISTS (existence check ONLY). Otherwise REFUSE.
#     The credential's contents are read ONLY inside the send call, held ONLY in locals,
#     normalized (whitespace/BOM stripped), and are NEVER logged, output, or ledgered.
#   * TEST path (-TestModeDir) composes the IDENTICAL message to disk with ZERO network.
#     Exactly one of -LiveSend / -TestModeDir must be supplied; both or neither => REFUSE.
#   * WRITE SURFACE: this module writes ONLY %USERPROFILE%\.neo_notify\* (ledger) and the
#     caller-supplied -TestModeDir. It NEVER writes under the governed NEO tree(s) or any
#     off-tree backup location.
#
# REVOKED-STAMP ANCHORING (deliberate): the attestation's revocation-POLICY sentence
# ("... mark this record REVOKED; ...") legitimately contains the token 'REVOKED'. The
# live-path check therefore matches only an ACTUAL revocation stamp: a line whose first
# token is REVOKED, or a STATUS: line that carries REVOKED. A mid-sentence policy mention
# never blocks; a real revocation stamp always does (fail-closed).
#
# TEST-ONLY SEAMS (auditor note - the module's trust boundary): -AttestationPath,
# -CredentialPath and -LedgerPath are OPTIONAL parameters DEFAULTING to the real paths.
# They exist ONLY so the fixture suite can prove refusal behavior against scratch files.
# Overriding the attestation path to a permissive file is CALLER-SIDE spoofing that the
# governed C1/C3 engine never performs; callers in governed flows MUST NOT pass them.
#
# STATUS OBJECT: every call path returns @{ sent; deduped; refused; reason; composed_path }.

# NOTE: deliberately NO Set-StrictMode here - dot-sourcing runs in the CALLER's scope and
# a convenience module must never mutate a gate caller's execution preferences.

# --- Recipient/sender: CONFIG-RESOLVED for distribution (parameterized; DEF-P8) ---
# Resolution order: env var -> %USERPROFILE%\.neo_notify\config.json -> non-routable placeholder.
# The placeholder is deliberately unusable: a live send with it REFUSES (see the live path).
$script:NeoNotifyAddrPlaceholder = 'you@example.com'
function Get-NeoNotifyAddr([string]$EnvName, [string]$JsonKey) {
  $v = [Environment]::GetEnvironmentVariable($EnvName)
  if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
  try {
    $cfg = Join-Path $env:USERPROFILE '.neo_notify\config.json'
    if (Test-Path -LiteralPath $cfg) {
      $o = Get-Content -LiteralPath $cfg -Raw -ErrorAction Stop | ConvertFrom-Json
      $val = [string]$o.$JsonKey
      if (-not [string]::IsNullOrWhiteSpace($val)) { return $val.Trim() }
    }
  } catch {}
  return $script:NeoNotifyAddrPlaceholder
}
$script:NeoNotifyRecipient  = Get-NeoNotifyAddr 'NEO_NOTIFY_RECIPIENT' 'recipient'
$script:NeoNotifySender     = Get-NeoNotifyAddr 'NEO_NOTIFY_SENDER'    'sender'
$script:NeoNotifySmtpHost   = 'smtp.gmail.com'
$script:NeoNotifySmtpPort   = 587
$script:NeoNotifyGateTypes  = @('DECISION_NEEDED','APPROVAL_NEEDED','SESSION_END','ESCALATION_STOP','BREAKER_TRIP')
$script:NeoNotifyFooter     = 'This is a NEO gate notification. Reply is not a channel; answer in the session.'
$script:NeoNotifyMaxLines   = 12
$script:NeoNotifyMaxLineLen = 200
$script:NeoNotifyDedupeWindowMinutes = 10
$script:NeoNotifySmtpTimeoutMs = 30000

# Real default paths. The attestation lives in the governed tree this module is installed
# under (<root>\NEO_SESSION\_neo_roadmap\...), derived from this file's own location
# (<root>\.neo\scripts\notify\) so DEV and a future promoted copy each bind to their own tree.
$script:NeoNotifyDefaultAttestationPath = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'NEO_SESSION\_neo_roadmap\DEF-P8_EMAIL_NOTIFY_ATTESTATION.md'
$script:NeoNotifyDefaultCredentialPath  = Join-Path $env:USERPROFILE '.neo_notify\smtp_credential'
$script:NeoNotifyDefaultLedgerPath      = Join-Path $env:USERPROFILE '.neo_notify\send_ledger.jsonl'

# Printable-ASCII test (space..tilde only; no tabs, control chars, or 8-bit chars).
function Test-NeoNotifyAscii([string]$s) {
  if ($null -eq $s) { return $true }
  return ($s -match '^[\x20-\x7E]*$')
}

# SHA-256 hex of the joined summary lines (dedupe identity component).
function Get-NeoNotifySummarySha([string[]]$SummaryLines) {
  $joined = (@($SummaryLines) -join "`n")
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($joined)
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '')
  } finally { $sha.Dispose() }
}

# Best-effort append-only ledger write. Returns $true on success, $false on any failure.
# NEVER throws: the ledger is bookkeeping, not authority (DEF-P8 anti-runaway guard).
function Write-NeoNotifyLedger([string]$LedgerPath, [hashtable]$Entry) {
  try {
    $dir = Split-Path -Parent $LedgerPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null
    }
    $json = ConvertTo-Json -InputObject $Entry -Compress
    Add-Content -LiteralPath $LedgerPath -Value $json -Encoding Ascii -ErrorAction Stop
    return $true
  } catch { return $false }
}

# Dedupe probe: $true when the ledger holds a SENT entry with identical gate+slice+summary_sha
# inside the window. Unreadable/corrupt ledger lines are skipped (bookkeeping, not authority).
function Test-NeoNotifyDuplicate([string]$LedgerPath, [string]$GateType, [string]$SliceId, [string]$SummarySha) {
  try {
    if (-not (Test-Path -LiteralPath $LedgerPath)) { return $false }
    $nowUtc = [datetime]::UtcNow
    foreach ($line in @(Get-Content -LiteralPath $LedgerPath -Encoding Ascii -ErrorAction Stop)) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $e = $null
      try { $e = ConvertFrom-Json -InputObject $line } catch { continue }
      if ($null -eq $e) { continue }
      try {
        if ([string]$e.outcome -ne 'SENT') { continue }
        if ([string]$e.gate -ne $GateType) { continue }
        if ([string]$e.slice -ne $SliceId) { continue }
        if ([string]$e.summary_sha -ne $SummarySha) { continue }
        $ts = [datetime]::Parse([string]$e.ts, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if (($nowUtc - $ts.ToUniversalTime()).TotalMinutes -le $script:NeoNotifyDedupeWindowMinutes) { return $true }
      } catch { continue }
    }
    return $false
  } catch { return $false }
}

# Live-path attestation gate: file present + line-anchored APPROVED / IN FORCE stamp +
# no ACTUAL revocation stamp (see REVOKED-STAMP ANCHORING in the header).
# Returns '' when in force, else the refusal reason (fail-closed on every failure mode).
function Get-NeoNotifyAttestationRefusal([string]$AttestationPath) {
  try {
    if (-not (Test-Path -LiteralPath $AttestationPath)) {
      return "refused: live send blocked - attestation file not found at '$AttestationPath' (fail-closed)"
    }
    $lines = @(Get-Content -LiteralPath $AttestationPath -ErrorAction Stop)
    $inForce = $false
    foreach ($ln in $lines) {
      if ($ln -match '^STATUS: \*\*APPROVED / IN FORCE') { $inForce = $true }
      if ($ln -match '^\s*REVOKED\b' -or $ln -match '^\s*STATUS:.*REVOKED') {
        return 'refused: live send blocked - attestation carries a REVOKED status stamp (fail-closed no-send)'
      }
    }
    if (-not $inForce) {
      return 'refused: live send blocked - attestation is not stamped APPROVED / IN FORCE (fail-closed)'
    }
    return ''
  } catch {
    return "refused: live send blocked - attestation unreadable ($($_.Exception.Message)) (fail-closed)"
  }
}

function Send-NeoGateNotification {
  param(
    [string]$GateType,
    [string]$SliceId,
    [string[]]$SummaryLines,
    [string]$EvidencePath,
    [string]$TestModeDir,
    [switch]$LiveSend,
    # test-only seams; default to the REAL paths; governed callers never pass these
    [string]$AttestationPath = $script:NeoNotifyDefaultAttestationPath,
    [string]$CredentialPath  = $script:NeoNotifyDefaultCredentialPath,
    [string]$LedgerPath      = $script:NeoNotifyDefaultLedgerPath
  )

  $status = @{ sent = $false; deduped = $false; refused = $false; reason = ''; composed_path = $null }
  if ($null -eq $SummaryLines) { $SummaryLines = @() }
  $summarySha = ''

  # Best-effort ledger of THIS attempt (one JSON line per attempt), then return $status.
  $finishAttempt = {
    param([string]$Outcome)
    $entry = @{
      ts          = [datetime]::UtcNow.ToString('o')
      gate        = [string]$GateType
      slice       = [string]$SliceId
      summary_sha = $summarySha
      outcome     = $Outcome
    }
    if (-not (Write-NeoNotifyLedger -LedgerPath $LedgerPath -Entry $entry)) {
      $note = "ledger write failed at '$LedgerPath' - bookkeeping only, outcome not blocked (DEF-P8 anti-runaway guard is advisory)"
      if ([string]::IsNullOrEmpty($status.reason)) { $status.reason = $note } else { $status.reason = $status.reason + '; ' + $note }
    }
    return $status
  }

  try {
    $summarySha = Get-NeoNotifySummarySha -SummaryLines $SummaryLines

    # --- Mode exclusivity (exactly one of -LiveSend / -TestModeDir) ---
    $hasTestDir = -not [string]::IsNullOrEmpty($TestModeDir)
    if ($LiveSend -and $hasTestDir) {
      $status.refused = $true
      $status.reason = 'refused: -LiveSend and -TestModeDir are mutually exclusive - exactly one mode per call'
      return (& $finishAttempt 'REFUSED')
    }
    if ((-not $LiveSend) -and (-not $hasTestDir)) {
      $status.refused = $true
      $status.reason = 'refused: exactly one of -LiveSend or -TestModeDir must be supplied - no default channel exists'
      return (& $finishAttempt 'REFUSED')
    }

    # --- Event-class restriction (DEF-P8: this IS the cap) ---
    if ([string]::IsNullOrWhiteSpace($GateType)) {
      $status.refused = $true
      $status.reason = 'refused: GateType is blank - only the attested friction classes may notify'
      return (& $finishAttempt 'REFUSED')
    }
    if ($script:NeoNotifyGateTypes -notcontains $GateType) {
      $status.refused = $true
      $status.reason = "refused: GateType '$GateType' is outside the attested friction set (" + ($script:NeoNotifyGateTypes -join ', ') + ') - the event-class restriction is the cap'
      return (& $finishAttempt 'REFUSED')
    }

    # --- Content rules (subject/body caps; ASCII; nothing else enters the mail) ---
    if ([string]::IsNullOrWhiteSpace($SliceId)) {
      $status.refused = $true
      $status.reason = 'refused: SliceId is blank'
      return (& $finishAttempt 'REFUSED')
    }
    if (-not (Test-NeoNotifyAscii $SliceId)) {
      $status.refused = $true
      $status.reason = 'refused: SliceId contains non-ASCII or control characters'
      return (& $finishAttempt 'REFUSED')
    }
    if (@($SummaryLines).Count -gt $script:NeoNotifyMaxLines) {
      $status.refused = $true
      $status.reason = ('refused: SummaryLines has ' + @($SummaryLines).Count + ' lines - the cap is ' + $script:NeoNotifyMaxLines + ' lines')
      return (& $finishAttempt 'REFUSED')
    }
    for ($i = 0; $i -lt @($SummaryLines).Count; $i++) {
      $ln = [string]@($SummaryLines)[$i]
      if ($ln.Length -gt $script:NeoNotifyMaxLineLen) {
        $status.refused = $true
        $status.reason = ('refused: SummaryLines[' + $i + '] is ' + $ln.Length + ' characters - the cap is ' + $script:NeoNotifyMaxLineLen + ' per line')
        return (& $finishAttempt 'REFUSED')
      }
      if (-not (Test-NeoNotifyAscii $ln)) {
        $status.refused = $true
        $status.reason = ('refused: SummaryLines[' + $i + '] contains non-ASCII or control characters')
        return (& $finishAttempt 'REFUSED')
      }
    }
    if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
      $status.refused = $true
      $status.reason = 'refused: EvidencePath is blank - the evidence folder path line is a required content element'
      return (& $finishAttempt 'REFUSED')
    }
    if (-not (Test-NeoNotifyAscii $EvidencePath)) {
      $status.refused = $true
      $status.reason = 'refused: EvidencePath contains non-ASCII or control characters'
      return (& $finishAttempt 'REFUSED')
    }

    # --- Compose (IDENTICAL for live and test; nothing else ever enters the mail) ---
    $subject = "[NEO] $GateType - $SliceId"
    $bodyLines = @()
    $bodyLines += @($SummaryLines)
    $bodyLines += ('Evidence: ' + $EvidencePath)
    $bodyLines += ''
    $bodyLines += $script:NeoNotifyFooter
    $body = ($bodyLines -join "`r`n")

    # --- Dedupe (identical attempt within the window of a SENT entry => not re-sent) ---
    if (Test-NeoNotifyDuplicate -LedgerPath $LedgerPath -GateType $GateType -SliceId $SliceId -SummarySha $summarySha) {
      $status.deduped = $true
      $status.reason = ('deduplicated: identical notification (gate+slice+summary hash) was SENT within the last ' + $script:NeoNotifyDedupeWindowMinutes + ' minutes - not re-sent (DEF-P8 anti-runaway guard)')
      return (& $finishAttempt 'DEDUPED')
    }

    if ($LiveSend) {
      # --- LIVE path: attestation gate, credential existence, config-address gate, then SMTP ---
      $attRefusal = Get-NeoNotifyAttestationRefusal -AttestationPath $AttestationPath
      if ($attRefusal -ne '') {
        $status.refused = $true
        $status.reason = $attRefusal
        return (& $finishAttempt 'REFUSED')
      }
      if (-not (Test-Path -LiteralPath $CredentialPath)) {
        $status.refused = $true
        $status.reason = "refused: live send blocked - credential file not present at '$CredentialPath' (existence check only; contents are never read here)"
        return (& $finishAttempt 'REFUSED')
      }
      # Parameterized recipient/sender must be configured to a real address; the placeholder
      # (or a blank value) fails closed here so an unconfigured install can never egress.
      if ([string]::IsNullOrWhiteSpace($script:NeoNotifyRecipient) -or [string]::IsNullOrWhiteSpace($script:NeoNotifySender) -or
          $script:NeoNotifyRecipient -eq $script:NeoNotifyAddrPlaceholder -or $script:NeoNotifySender -eq $script:NeoNotifyAddrPlaceholder) {
        $status.refused = $true
        $status.reason = 'refused: live send blocked - recipient/sender not configured (set NEO_NOTIFY_RECIPIENT/NEO_NOTIFY_SENDER or %USERPROFILE%\.neo_notify\config.json) (fail-closed)'
        return (& $finishAttempt 'REFUSED')
      }
      $smtp = $null; $msg = $null
      try {
        # Credential is read INSIDE the send call, held ONLY in locals, normalized
        # (all whitespace incl. CR/LF/tabs and any UTF-8 BOM stripped), never logged.
        $credRaw = [System.IO.File]::ReadAllText($CredentialPath)
        $credNorm = ($credRaw -replace '[\s\uFEFF]', '')
        $credRaw = $null
        $msg = New-Object System.Net.Mail.MailMessage
        $msg.From = New-Object System.Net.Mail.MailAddress($script:NeoNotifySender)
        $msg.To.Add($script:NeoNotifyRecipient) | Out-Null
        $msg.Subject = $subject
        $msg.Body = $body
        $msg.IsBodyHtml = $false
        $smtp = New-Object System.Net.Mail.SmtpClient($script:NeoNotifySmtpHost, $script:NeoNotifySmtpPort)
        $smtp.EnableSsl = $true
        $smtp.Timeout = $script:NeoNotifySmtpTimeoutMs
        $smtp.Credentials = New-Object System.Net.NetworkCredential($script:NeoNotifySender, $credNorm)
        $smtp.Send($msg)
        $credNorm = $null
        $status.sent = $true
        return (& $finishAttempt 'SENT')
      } catch {
        # authority_rule: a failed send NEVER blocks a gate - report, never rethrow.
        $status.sent = $false
        $status.reason = "live send failed: $($_.Exception.Message) (gate NOT blocked - notification is convenience, never authority)"
        return (& $finishAttempt 'FAILED')
      } finally {
        $credNorm = $null
        if ($null -ne $msg) { $msg.Dispose() }
        if ($null -ne $smtp) { $smtp.Dispose() }
      }
    }

    # --- TEST path: compose the identical message to disk; ZERO network ---
    try {
      if (-not (Test-Path -LiteralPath $TestModeDir)) {
        New-Item -ItemType Directory -Force -Path $TestModeDir -ErrorAction Stop | Out-Null
      }
      $ts = [datetime]::Now.ToString('yyyyMMdd_HHmmssfff')
      $safeSlice = ($SliceId -replace '[^A-Za-z0-9_.-]', '-')
      $fileName = ('{0}_{1}_{2}.eml.txt' -f $ts, $GateType, $safeSlice)
      $outPath = Join-Path $TestModeDir $fileName
      $composedLines = @(
        ('To: ' + $script:NeoNotifyRecipient),
        ('From: ' + $script:NeoNotifySender),
        ('Subject: ' + $subject),
        ''
      ) + $bodyLines
      $text = (($composedLines -join "`r`n") + "`r`n")
      [System.IO.File]::WriteAllText($outPath, $text, [System.Text.Encoding]::ASCII)
      $status.sent = $true
      $status.composed_path = $outPath
      return (& $finishAttempt 'SENT')
    } catch {
      $status.sent = $false
      $status.reason = "test-mode compose failed: $($_.Exception.Message) (gate NOT blocked)"
      return (& $finishAttempt 'FAILED')
    }
  } catch {
    # Belt-and-braces: NO code path may throw to the caller (a failed notification
    # never blocks a gate). Contract violations were handled above as refusals.
    $status.sent = $false
    $status.reason = "send-path internal failure: $($_.Exception.Message) (gate NOT blocked)"
    return $status
  }
}
