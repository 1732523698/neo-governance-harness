# notify_fixture_suite.ps1 - fixture suite for notify_raphael.ps1 (P8-NOTIFY).
# ASCII-only (D10). Self-contained; PASS/FAIL counts; exit 0/1; scratch under %TEMP% only;
# residue-clean second pass. TEST_HARNESS class (judging-from-birth via *_fixture_suite.ps1).
#
# STRUCTURAL LIVE-SEND INCAPABILITY (dispatch requirement):
#   * The suite exercises ONLY the -TestModeDir compose path for every positive fixture.
#   * The ONLY fixtures that pass -LiveSend are refusal proofs, and EVERY one of them
#     points BOTH -AttestationPath and -CredentialPath at scratch files that guarantee
#     refusal BEFORE the SMTP code path can be reached (unattested DRAFT stamp, or a
#     non-existent credential path). No fixture can produce network egress.
#   * N-BOTH-MODES is the POSITIVE assertion that -LiveSend + -TestModeDir together
#     => refused (mutual exclusion fires before everything else).
#   * Every call passes an explicit scratch -LedgerPath: the REAL %USERPROFILE%\.neo_notify
#     is never read from or written to by this suite.

$ErrorActionPreference = 'Stop'

$pass = 0; $fail = 0
$results = @()
$allStatuses = @()   # collected for P-STATUS-SHAPE

function Check([string]$Name, [bool]$Cond, [string]$Detail) {
  if ($Cond) { $script:pass++; $tag = '[PASS]' } else { $script:fail++; $tag = '[FAIL]' }
  $line = ('{0} {1,-34} {2}' -f $tag, $Name, $Detail)
  Write-Output $line
  $script:results += $line
}

# --- Load the module under test ---
. (Join-Path $PSScriptRoot 'notify_raphael.ps1')

# --- Scratch layout (all under %TEMP%; removed in the residue pass) ---
$scratch = Join-Path $env:TEMP ('neo_notify_suite_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$composeDir = Join-Path $scratch 'compose'
$missingCred = Join-Path $scratch 'no_such_dir\smtp_credential'   # never created

# Per-fixture scratch ledger (fresh file per fixture keeps line-count assertions exact).
$ledgerSeq = 0
function New-ScratchLedger {
  $script:ledgerSeq++
  return (Join-Path $script:scratch ('ledger_' + $script:ledgerSeq + '\send_ledger.jsonl'))
}

# Wrapper: EVERY module call in this suite goes through here, which FORCES a scratch
# ledger path and never passes -LiveSend unless the fixture explicitly supplies the
# refusal-guaranteeing scratch seams (structural incapability).
function Invoke-NotifyTest {
  param([hashtable]$CallArgs, [string]$LedgerPath)
  $CallArgs['LedgerPath'] = $LedgerPath
  $r = Send-NeoGateNotification @CallArgs
  $script:allStatuses += ,@($r)
  return $r
}

$validSummary = @('C6 arc converged; P8-NOTIFY slice awaiting START.', 'Two files, contract-dense; RT3.')
$validEvidence = 'NEO_SESSION\p8-notify-example'
# expected addresses mirror the module's CONFIG-RESOLVED values (parameterized), so the
# compose assertions hold regardless of env/config/placeholder resolution at load time.
$recipient = $script:NeoNotifyRecipient
$sender = $script:NeoNotifySender
$footer = 'This is a NEO gate notification. Reply is not a channel; answer in the session.'

# Record the REAL notify dir state BEFORE fixtures (asserted unchanged at the end).
$realNotifyDir = Join-Path $env:USERPROFILE '.neo_notify'
$realPreExists = Test-Path -LiteralPath $realNotifyDir
$realPreSnapshot = @()
if ($realPreExists) {
  $realPreSnapshot = @(Get-ChildItem -LiteralPath $realNotifyDir -Force -Recurse | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.ToString('o') })
}

# ============================== FIXTURES ==============================

# --- P-COMPOSE: valid DECISION_NEEDED compose-to-disk; exact subject/body/footer; ASCII ---
$led = New-ScratchLedger
$r = Invoke-NotifyTest -LedgerPath $led -CallArgs @{
  GateType = 'DECISION_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = $validSummary
  EvidencePath = $validEvidence; TestModeDir = $composeDir
}
Check 'P-COMPOSE-status' (($r.sent -eq $true) -and ($r.refused -eq $false) -and ($r.deduped -eq $false)) ("sent=$($r.sent) refused=$($r.refused) deduped=$($r.deduped) reason='$($r.reason)'")
$fileOk = ($null -ne $r.composed_path) -and (Test-Path -LiteralPath $r.composed_path)
Check 'P-COMPOSE-file-exists' $fileOk ("composed_path=$($r.composed_path)")
if ($fileOk) {
  $expected = (@(
    ('To: ' + $recipient),
    ('From: ' + $sender),
    'Subject: [NEO] DECISION_NEEDED - P8-NOTIFY',
    ''
  ) + $validSummary + @(
    ('Evidence: ' + $validEvidence),
    '',
    $footer
  ) -join "`r`n") + "`r`n"
  $actual = [System.IO.File]::ReadAllText($r.composed_path)
  Check 'P-COMPOSE-content-exact' ($actual -eq $expected) ('exact match of To/From/Subject/blank/summary/Evidence/blank/footer = ' + ($actual -eq $expected))
  $bytes = [System.IO.File]::ReadAllBytes($r.composed_path)
  $nonAscii = 0; foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii++ } }
  Check 'P-COMPOSE-ascii' ($nonAscii -eq 0) ("non-ASCII bytes in composed file: $nonAscii")
  Check 'P-COMPOSE-filename-shape' ((Split-Path -Leaf $r.composed_path) -match '^\d{8}_\d{9}_DECISION_NEEDED_P8-NOTIFY\.eml\.txt$') ("name=" + (Split-Path -Leaf $r.composed_path))
} else {
  Check 'P-COMPOSE-content-exact' $false 'skipped: no composed file'
  Check 'P-COMPOSE-ascii' $false 'skipped: no composed file'
  Check 'P-COMPOSE-filename-shape' $false 'skipped: no composed file'
}

# --- N-GATETYPE-OUTSIDE: BUILD_PROGRESS is not a friction class => refused ---
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = 'BUILD_PROGRESS'; SliceId = 'P8-NOTIFY'; SummaryLines = $validSummary
  EvidencePath = $validEvidence; TestModeDir = $composeDir
}
Check 'N-GATETYPE-OUTSIDE' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like "*outside the attested friction set*")) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-GATETYPE-BLANK => refused ---
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = ''; SliceId = 'P8-NOTIFY'; SummaryLines = $validSummary
  EvidencePath = $validEvidence; TestModeDir = $composeDir
}
Check 'N-GATETYPE-BLANK' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*GateType is blank*')) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-BODY-TOO-MANY-LINES: 13 lines => refused ---
$thirteen = @(1..13 | ForEach-Object { "summary line $_" })
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = 'DECISION_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = $thirteen
  EvidencePath = $validEvidence; TestModeDir = $composeDir
}
Check 'N-BODY-TOO-MANY-LINES' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*13 lines*' -or $r.reason -like '*cap is 12*')) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-LINE-TOO-LONG: a 201-char line => refused ---
$longLine = ('x' * 201)
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = 'DECISION_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = @('ok line', $longLine)
  EvidencePath = $validEvidence; TestModeDir = $composeDir
}
Check 'N-LINE-TOO-LONG' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*201 characters*')) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-NONASCII: a non-ASCII char (e-acute, built via [char] so this file stays ASCII) ---
$accented = ('caf' + [string][char]0x00E9)
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = 'DECISION_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = @($accented)
  EvidencePath = $validEvidence; TestModeDir = $composeDir
}
Check 'N-NONASCII' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*non-ASCII*')) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-BOTH-MODES: -LiveSend + -TestModeDir => refused (POSITIVE mutual-exclusion proof).
# Belt-and-braces: even here the live seams point at scratch (DRAFT attestation + missing
# credential), so no path to network exists even if exclusion were broken. ---
$draftAtt = Join-Path $scratch 'attestation_draft.md'
@('# synthetic DEF-P8 copy (scratch; suite-made)', 'STATUS: DRAFT (not in force)', 'body irrelevant') | Set-Content -LiteralPath $draftAtt -Encoding Ascii
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = 'DECISION_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = $validSummary
  EvidencePath = $validEvidence; TestModeDir = $composeDir; LiveSend = $true
  AttestationPath = $draftAtt; CredentialPath = $missingCred
}
Check 'N-BOTH-MODES' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*mutually exclusive*')) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-NEITHER-MODE => refused ---
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = 'DECISION_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = $validSummary
  EvidencePath = $validEvidence
}
Check 'N-NEITHER-MODE' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*exactly one of*')) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-LIVE-UNATTESTED: -LiveSend against a synthetic DRAFT attestation (scratch seam)
# => refused at the attestation gate; credential seam ALSO points at a missing scratch
# path (defence in depth - no network reachable). ---
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = 'DECISION_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = $validSummary
  EvidencePath = $validEvidence; LiveSend = $true
  AttestationPath = $draftAtt; CredentialPath = $missingCred
}
Check 'N-LIVE-UNATTESTED' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*not stamped APPROVED / IN FORCE*')) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-LIVE-REVOKED-STAMP (hardening, same seam): an ACTUAL revocation stamp refuses,
# while the real attestation's mid-sentence policy mention of the token must NOT trip
# (that anchoring is asserted via the module's parser against a stamped copy). ---
$revokedAtt = Join-Path $scratch 'attestation_revoked.md'
@('# synthetic DEF-P8 copy (scratch; suite-made)', 'STATUS: **APPROVED / IN FORCE (then revoked below)', 'REVOKED 2026-07-07 by controller') | Set-Content -LiteralPath $revokedAtt -Encoding Ascii
$r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
  GateType = 'DECISION_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = $validSummary
  EvidencePath = $validEvidence; LiveSend = $true
  AttestationPath = $revokedAtt; CredentialPath = $missingCred
}
Check 'N-LIVE-REVOKED-STAMP' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*REVOKED status stamp*')) ("refused=$($r.refused) reason='$($r.reason)'")

# --- N-LIVE-NO-CREDENTIAL: attested (self-generated in-force attestation whose body carries a
# mid-sentence policy mention of REVOKED that must NOT trip the anchored revocation check) +
# credential path overridden to a non-existent scratch path => refused cleanly, no exception.
# Self-generated (not copied from a shipped file) so the suite is self-contained and the shipped
# attestation can stay an UNAPPROVED template. ---
$attCopy = Join-Path $scratch 'attestation_copy.md'
Set-Content -LiteralPath $attCopy -Encoding Ascii -Value @(
  '# DEF-P8 EMAIL NOTIFICATION CHANNEL ATTESTATION - fixture (in-force)',
  'STATUS: **APPROVED / IN FORCE (fixture-generated approved attestation for the in-force path)**',
  'revocation: revocable at any time; revocation = mark this record REVOKED (a mid-sentence policy',
  '            mention of REVOKED like this one must NOT trip the anchored revocation-stamp check).'
)
$threw = $false
try {
  $r = Invoke-NotifyTest -LedgerPath (New-ScratchLedger) -CallArgs @{
    GateType = 'APPROVAL_NEEDED'; SliceId = 'P8-NOTIFY'; SummaryLines = $validSummary
    EvidencePath = $validEvidence; LiveSend = $true
    AttestationPath = $attCopy; CredentialPath = $missingCred
  }
} catch { $threw = $true }
Check 'N-LIVE-NO-CREDENTIAL-noexcept' (-not $threw) ("threw=$threw (must refuse, never throw)")
if (-not $threw) {
  Check 'N-LIVE-NO-CREDENTIAL' (($r.refused -eq $true) -and ($r.sent -eq $false) -and ($r.reason -like '*credential file not present*')) ("refused=$($r.refused) reason='$($r.reason)'")
  Check 'N-LIVE-NO-CREDENTIAL-anchor' ($r.reason -notlike '*REVOKED status stamp*') 'real attestation copy passed the anchored REVOKED check (policy mention did not trip)'
} else {
  Check 'N-LIVE-NO-CREDENTIAL' $false 'skipped: call threw'
  Check 'N-LIVE-NO-CREDENTIAL-anchor' $false 'skipped: call threw'
}

# --- P-DEDUPE: two identical composes within the window => second deduped; ledger has
# exactly one SENT + one DEDUPED line. ---
$led = New-ScratchLedger
$dedupeDir = Join-Path $scratch 'dedupe_compose'
$argsDedupe = @{
  GateType = 'SESSION_END'; SliceId = 'P8-NOTIFY'; SummaryLines = @('Session ended; evidence assembled.')
  EvidencePath = $validEvidence; TestModeDir = $dedupeDir
}
$r1 = Invoke-NotifyTest -LedgerPath $led -CallArgs $argsDedupe.Clone()
$r2 = Invoke-NotifyTest -LedgerPath $led -CallArgs $argsDedupe.Clone()
Check 'P-DEDUPE-first-sent' (($r1.sent -eq $true) -and ($r1.deduped -eq $false)) ("sent=$($r1.sent) deduped=$($r1.deduped)")
Check 'P-DEDUPE-second-deduped' (($r2.deduped -eq $true) -and ($r2.sent -eq $false) -and ($r2.refused -eq $false)) ("sent=$($r2.sent) deduped=$($r2.deduped) reason='$($r2.reason)'")
$ledLines = @(Get-Content -LiteralPath $led -Encoding Ascii)
$sentCount = @($ledLines | Where-Object { $_ -like '*"outcome":"SENT"*' }).Count
$dedupCount = @($ledLines | Where-Object { $_ -like '*"outcome":"DEDUPED"*' }).Count
Check 'P-DEDUPE-ledger-lines' (($ledLines.Count -eq 2) -and ($sentCount -eq 1) -and ($dedupCount -eq 1)) ("lines=$($ledLines.Count) SENT=$sentCount DEDUPED=$dedupCount")

# --- P-DEDUPE-DISTINCT: different SliceId => both compose (no dedupe) ---
$led = New-ScratchLedger
$rA = Invoke-NotifyTest -LedgerPath $led -CallArgs @{
  GateType = 'SESSION_END'; SliceId = 'P8-NOTIFY-A'; SummaryLines = @('identical summary')
  EvidencePath = $validEvidence; TestModeDir = $dedupeDir
}
$rB = Invoke-NotifyTest -LedgerPath $led -CallArgs @{
  GateType = 'SESSION_END'; SliceId = 'P8-NOTIFY-B'; SummaryLines = @('identical summary')
  EvidencePath = $validEvidence; TestModeDir = $dedupeDir
}
Check 'P-DEDUPE-DISTINCT' (($rA.sent -eq $true) -and ($rB.sent -eq $true) -and ($rB.deduped -eq $false)) ("A.sent=$($rA.sent) B.sent=$($rB.sent) B.deduped=$($rB.deduped)")

# --- P-LEDGER-UNWRITABLE: unwritable ledger => compose STILL succeeds + honest reason.
# Unwritability is manufactured by making the ledger's PARENT PATH an existing FILE
# (deterministic on Windows; a directory's ReadOnly attribute does not block child-file
# creation, so the attribute trick would not actually make the ledger unwritable). ---
$blockerFile = Join-Path $scratch 'ledger_blocker'
Set-Content -LiteralPath $blockerFile -Value 'occupies the parent path slot' -Encoding Ascii
$unwritableLedger = Join-Path $blockerFile 'send_ledger.jsonl'   # parent is a FILE => every write fails
$r = Invoke-NotifyTest -LedgerPath $unwritableLedger -CallArgs @{
  GateType = 'ESCALATION_STOP'; SliceId = 'P8-NOTIFY'; SummaryLines = @('escalation stop reached')
  EvidencePath = $validEvidence; TestModeDir = $composeDir
}
Check 'P-LEDGER-UNWRITABLE-sent' (($r.sent -eq $true) -and ($r.refused -eq $false)) ("sent=$($r.sent) refused=$($r.refused)")
Check 'P-LEDGER-UNWRITABLE-honest' ($r.reason -like '*ledger write failed*') ("reason='$($r.reason)'")

# --- P-STATUS-SHAPE: all 5 keys on EVERY status returned above ---
$shapeOk = $true; $shapeDetail = ('statuses checked: ' + $allStatuses.Count)
foreach ($s in $allStatuses) {
  $st = $s[0]
  foreach ($k in @('sent','deduped','refused','reason','composed_path')) {
    if (-not $st.ContainsKey($k)) { $shapeOk = $false; $shapeDetail = "missing key '$k'" }
  }
}
Check 'P-STATUS-SHAPE' $shapeOk $shapeDetail

# --- STRUCTURAL: the real %USERPROFILE%\.neo_notify was never created/touched by this suite ---
$realPostExists = Test-Path -LiteralPath $realNotifyDir
$realPostSnapshot = @()
if ($realPostExists) {
  $realPostSnapshot = @(Get-ChildItem -LiteralPath $realNotifyDir -Force -Recurse | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.ToString('o') })
}
$realUntouched = ($realPreExists -eq $realPostExists) -and (@(Compare-Object $realPreSnapshot $realPostSnapshot).Count -eq 0)
Check 'STRUCTURAL-real-notify-untouched' $realUntouched ("preExists=$realPreExists postExists=$realPostExists metadataDelta=" + @(Compare-Object $realPreSnapshot $realPostSnapshot).Count)

# ============================== RESIDUE (second pass) ==============================
Remove-Item -LiteralPath $scratch -Recurse -Force -Confirm:$false
$residueClean = -not (Test-Path -LiteralPath $scratch)
Check 'RESIDUE-scratch-removed' $residueClean ("scratch=$scratch removed=$residueClean")
$leftover = @(Get-ChildItem -Path $env:TEMP -Filter 'neo_notify_suite_*' -Directory -ErrorAction SilentlyContinue)
Check 'RESIDUE-no-suite-dirs-left' ($leftover.Count -eq 0) ("leftover suite scratch dirs in TEMP: $($leftover.Count)")

# ============================== SUMMARY ==============================
Write-Output ''
Write-Output ('notify_fixture_suite: PASS=' + $pass + ' FAIL=' + $fail)
if ($fail -eq 0) {
  Write-Output '=== notify_fixture_suite: ALL CHECKS PASS (test path only; zero network by construction) ==='
  exit 0
} else {
  Write-Output '=== notify_fixture_suite: FAILURES PRESENT ==='
  exit 1
}
