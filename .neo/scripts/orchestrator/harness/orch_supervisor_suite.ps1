# orch_supervisor_suite.ps1 - NEO 4.0-P4-AUTONOMY C2 INDEPENDENT firewall harness.
# ASCII-only (D10). Kept SEPARATE from the engine it tests.
#
# Proves the C2 cold-builder CONTEXT FIREWALL FAILS CLOSED and is re-checkable:
#   - P-ASSEMBLE: permitted-role members over real scratch files => a packet Assert-NeoValid
#     accepts, self_hash present, Test-NeoBuilderPacketFirewall passes.
#   - N-FORBIDDEN-COT/TRANSCRIPT/RATIONALE: each forbidden context source => BLOCK naming the role.
#   - N-UNKNOWN-ROLE / N-BLANK-ROLE => BLOCK.
#   - N-PATH-DODGE battery (drive/absolute, backslash, '..') + N-PATH-MISSING => BLOCK.
#   - N-RISK-UNKNOWN / N-RISK-BLANK => BLOCK.
#   - N-CONSUME-TAMPER: mutate a referenced file post-assembly => Test re-hash => BLOCK.
#   - P-NO-FREETEXT: a crafted extra key on the packet => Assert-NeoValid BLOCK (addlProps:false).
#   - N-APPROVED-PATH-DODGE: a non-canonical approved/protected path => BLOCK.
# C2-FIX additions (F1/F2/F3/F4):
#   - P-C2F-APPROOT (F1): assemble+consume with RepoRoot = an APP tree lacking .neo\schema =>
#     SUCCEEDS (schema resolves from the NEO governed root via Resolve-NeoRoot).
#   - N-C2F-GOAL-FORBIDDEN / N-C2F-TESTPLAN-FORBIDDEN (F2): a forbidden context token in
#     goal/test_plan => BLOCK; N-C2F-GOAL-TOOLONG => BLOCK; P-C2F-GOAL-CLEAN => assembles.
#   - N-C2F-DOTSLASH-REL / N-C2F-DOTSLASH-APPROVED (F3): a './'-prefixed rel/approved => BLOCK.
#   - N-C2F-MEMBER-STRAYKEY / -NONSTRING-REL / -NONSTRING-ROLE (F4): member shape fail-close.
# Writes NO AUDIT_RESULT; synthetic fixtures only, in scratch; residue-clean second pass.
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'

$orchDir = Split-Path -Parent $PSScriptRoot   # ...\.neo\scripts\orchestrator
. "$orchDir\orch_supervisor.ps1"              # dot-sources orch_io -> orch_schema/orch_class chain

# RepoRoot = the DEV repo root (four levels up from this file: harness -> orchestrator -> scripts -> .neo -> root)
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $orchDir))
$TS = '2026-07-06T00:00:00Z'

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_orch_c2_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors the router/enforce-suite framing) --------------
$script:results = @()
function Record($name, $pass, $detail, $kind = 'negative') {
  $script:results += [pscustomobject]@{ guard = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  $ktag = if ($kind -eq 'negative') { 'GUARD' } else { 'info ' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $ktag, $name, $detail) -ForegroundColor $col
}

# A negative fixture PASSES iff the call BLOCKs (throws NEO-BLOCK) with the expected substring.
function Expect-Block($name, $needle, [scriptblock]$body) {
  try {
    & $body
    Record $name $false "expected NEO-BLOCK '$needle' but call SUCCEEDED"
  } catch {
    $msg = "$($_.Exception.Message)"
    $ok = ($msg -like '*NEO-BLOCK*') -and ($msg -like "*$needle*")
    Record $name $ok $msg
  }
}

# A positive fixture PASSES iff the body runs without throwing and its assertion holds.
function Expect-Pass($name, [scriptblock]$body) {
  try {
    $r = & $body
    Record $name ([bool]$r) "assertion held" 'positive'
  } catch {
    Record $name $false "unexpected throw: $($_.Exception.Message)" 'positive'
  }
}

# ---- scratch fixtures: real on-disk files under RepoRoot (so rel paths are contained) --------
# Put scratch files INSIDE the repo tree (a temp subdir under .neo) so their root-relative
# spelling is genuinely contained by Assert-NeoContained. Cleaned in the finally block.
$relDir  = '.neo/_c2_scratch_' + [guid]::NewGuid().ToString('N')
$absDir  = Join-Path $RepoRoot ($relDir -replace '/', '\')
New-Item -ItemType Directory -Force -Path $absDir | Out-Null

$relFileA = "$relDir/fileA.txt"
$relFileB = "$relDir/fileB.txt"
$relFileC = "$relDir/fileC.txt"
$absFileA = Join-Path $RepoRoot ($relFileA -replace '/', '\')
$absFileB = Join-Path $RepoRoot ($relFileB -replace '/', '\')
$absFileC = Join-Path $RepoRoot ($relFileC -replace '/', '\')
Set-Content -LiteralPath $absFileA -Value 'alpha dispatch body'   -Encoding UTF8
Set-Content -LiteralPath $absFileB -Value 'bravo artifact body'   -Encoding UTF8
Set-Content -LiteralPath $absFileC -Value 'charlie finding body'  -Encoding UTF8

$approved  = @("$relDir/out.ps1")
$protected = @('.neo/schema/input_packet.schema.json')

# A valid, permitted-role allowlist over 3 real scratch files.
$goodAllow = @(
  @{ rel = $relFileA; role = 'dispatch' },
  @{ rel = $relFileB; role = 'current_artifact' },
  @{ rel = $relFileC; role = 'current_audit_finding' }
)

function New-Good {
  param($AllowlistItems = $goodAllow, $RiskClass = 'high', $Approved = $approved, $Protected = $protected)
  return (New-NeoFirewalledBuilderPacket `
    -Goal 'C2 firewall self-test' -ApprovedPaths $Approved -ProtectedPaths $Protected `
    -RiskClass $RiskClass -AllowlistItems $AllowlistItems -TestPlan @('run the suite') `
    -StopConditions @('scope_breach','ambiguity') -RepoRoot $RepoRoot -DeclaredSurfaces @('filesystem') `
    -Timestamp $TS)
}

try {
  Write-Host "`n=== NEO 4.0-P4 C2 CONTEXT-FIREWALL SUITE ===" -ForegroundColor Cyan

  # -- P-ASSEMBLE --------------------------------------------------------------
  Expect-Pass 'P-ASSEMBLE' {
    $pkt = New-Good
    $ip = $pkt.input_packet
    $hasSelf = -not [string]::IsNullOrWhiteSpace($ip.self_hash) -and $ip.self_hash -ne 'UNSET'
    $reok = Test-NeoBuilderPacketFirewall -Packet $pkt -RepoRoot $RepoRoot
    ($pkt.risk_class -eq 'high') -and $hasSelf -and $reok -and (@($ip.allowlist).Count -eq 3)
  }

  # -- N-FORBIDDEN-* (each forbidden context source => BLOCK naming the role) ---
  Expect-Block 'N-FORBIDDEN-COT' 'supervisor_cot' {
    New-Good -AllowlistItems @(@{ rel = $relFileA; role = 'supervisor_cot' })
  }
  Expect-Block 'N-FORBIDDEN-TRANSCRIPT' 'prior_builder_transcript' {
    New-Good -AllowlistItems @(@{ rel = $relFileA; role = 'prior_builder_transcript' })
  }
  Expect-Block 'N-FORBIDDEN-RATIONALE' 'prior_round_rationale' {
    New-Good -AllowlistItems @(@{ rel = $relFileA; role = 'prior_round_rationale' })
  }

  # -- N-UNKNOWN-ROLE / N-BLANK-ROLE -------------------------------------------
  Expect-Block 'N-UNKNOWN-ROLE' 'UNKNOWN allowlist role' {
    New-Good -AllowlistItems @(@{ rel = $relFileA; role = 'random_source' })
  }
  Expect-Block 'N-BLANK-ROLE' 'blank/empty role' {
    New-Good -AllowlistItems @(@{ rel = $relFileA; role = '' })
  }

  # -- N-PATH-DODGE battery (reused canonical-rel rule) ------------------------
  Expect-Block 'N-PATH-DRIVE' 'drive-qualified' {
    # forward-slash absolute so the drive-qualified branch (not the backslash branch) fires.
    New-Good -AllowlistItems @(@{ rel = 'C:/Windows/win.ini'; role = 'dispatch' })
  }
  Expect-Block 'N-PATH-BACKSLASH' 'backslash' {
    New-Good -AllowlistItems @(@{ rel = '.neo\schema\input_packet.schema.json'; role = 'dispatch' })
  }
  Expect-Block 'N-PATH-TRAVERSAL' 'parent traversal' {
    New-Good -AllowlistItems @(@{ rel = "$relDir/../../../etc/passwd"; role = 'dispatch' })
  }
  Expect-Block 'N-PATH-MISSING' 'missing on disk' {
    New-Good -AllowlistItems @(@{ rel = "$relDir/nope.txt"; role = 'dispatch' })
  }

  # -- N-RISK-* -----------------------------------------------------------------
  Expect-Block 'N-RISK-UNKNOWN' "risk_class 'wat'" {
    New-Good -RiskClass 'wat'
  }
  Expect-Block 'N-RISK-BLANK' 'risk_class' {
    # whitespace binds to the mandatory [string] param yet trips the IsNullOrWhiteSpace guard,
    # proving the assembler's own blank/UNKNOWN => STOP semantic (not just PS param binding).
    New-Good -RiskClass ' '
  }

  # -- N-CONSUME-TAMPER: assemble valid, mutate a referenced file, re-check => BLOCK ---
  Expect-Block 'N-CONSUME-TAMPER' 'content_hash mismatch' {
    $pkt = New-Good
    Set-Content -LiteralPath $absFileB -Value 'TAMPERED bravo body' -Encoding UTF8
    Test-NeoBuilderPacketFirewall -Packet $pkt -RepoRoot $RepoRoot
  }
  # restore fileB for any later use / clean residue reasoning
  Set-Content -LiteralPath $absFileB -Value 'bravo artifact body' -Encoding UTF8

  # -- P-NO-FREETEXT: a crafted extra key => Assert-NeoValid BLOCK (addlProps:false) ---
  Expect-Block 'P-NO-FREETEXT' 'failed schema' {
    $pkt = New-Good
    # inject an out-of-band free-text prompt field the schema forbids, then re-validate.
    $pkt.input_packet | Add-Member -NotePropertyName 'prompt' -NotePropertyValue 'do X out of band' -Force
    $Index = Get-NeoSchemaIndex (Join-Path $RepoRoot '.neo\schema')
    Assert-NeoValid $pkt.input_packet 'neo:input_packet' $Index 'INPUT_PACKET(freetext-probe)'
  }

  # -- N-APPROVED-PATH-DODGE: non-canonical approved/protected path => BLOCK ----
  Expect-Block 'N-APPROVED-PATH-DODGE' 'backslash' {
    New-Good -Approved @('.neo\scripts\orchestrator\out.ps1')
  }

  # ======================= C2-FIX ADDITIONS (F1/F2/F3/F4) =====================

  # -- P-C2F-APPROOT (F1 regression): assemble+consume with RepoRoot = a scratch APP
  # tree that HAS the allowlist files but NO .neo\schema. Pre-fix this hard-failed
  # "schema dir not found"; post-fix the schema resolves from the NEO governed root
  # (Resolve-NeoRoot), so it SUCCEEDS. The app tree is the write-boundary root only.
  Expect-Pass 'P-C2F-APPROOT' {
    $appRoot = Join-Path $ScratchRoot ('apptree_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $appRoot 'src') | Out-Null
    # deliberately NO .neo\schema under $appRoot
    $aRel = 'src/dispatch.md'
    $aAbs = Join-Path $appRoot ($aRel -replace '/', '\')
    Set-Content -LiteralPath $aAbs -Value 'app-tree dispatch body' -Encoding UTF8
    $pkt = New-NeoFirewalledBuilderPacket `
      -Goal 'C2-FIX app-root schema-decouple self-test' `
      -ApprovedPaths @('src/out.ps1') -ProtectedPaths @('src/dispatch.md') `
      -RiskClass 'low' -AllowlistItems @(@{ rel = $aRel; role = 'dispatch' }) `
      -TestPlan @('run the app slice') -StopConditions @('scope_breach') `
      -RepoRoot $appRoot -DeclaredSurfaces @('filesystem') -Timestamp $TS
    $noSchema = -not (Test-Path -LiteralPath (Join-Path $appRoot '.neo\schema'))
    $reok = Test-NeoBuilderPacketFirewall -Packet $pkt -RepoRoot $appRoot
    $noSchema -and $reok -and ($pkt.risk_class -eq 'low') -and (@($pkt.input_packet.allowlist).Count -eq 1)
  }

  # -- F2: goal/test_plan forbidden-token scan + bound ------------------------
  Expect-Block 'N-C2F-GOAL-FORBIDDEN' 'prior_builder_transcript' {
    New-NeoFirewalledBuilderPacket `
      -Goal 'do the work; context from prior_builder_transcript follows: ...' `
      -ApprovedPaths $approved -ProtectedPaths $protected -RiskClass 'high' `
      -AllowlistItems $goodAllow -TestPlan @('run the suite') `
      -StopConditions @('scope_breach') -RepoRoot $RepoRoot -DeclaredSurfaces @('filesystem') -Timestamp $TS
  }
  Expect-Block 'N-C2F-TESTPLAN-FORBIDDEN' 'supervisor_cot' {
    New-NeoFirewalledBuilderPacket `
      -Goal 'ordinary goal' `
      -ApprovedPaths $approved -ProtectedPaths $protected -RiskClass 'high' `
      -AllowlistItems $goodAllow -TestPlan @('step 1', 'inline supervisor_cot: because I thought...') `
      -StopConditions @('scope_breach') -RepoRoot $RepoRoot -DeclaredSurfaces @('filesystem') -Timestamp $TS
  }
  Expect-Block 'N-C2F-GOAL-TOOLONG' 'exceeds bound' {
    $bigGoal = 'x' * 2001
    New-NeoFirewalledBuilderPacket `
      -Goal $bigGoal `
      -ApprovedPaths $approved -ProtectedPaths $protected -RiskClass 'high' `
      -AllowlistItems $goodAllow -TestPlan @('run the suite') `
      -StopConditions @('scope_breach') -RepoRoot $RepoRoot -DeclaredSurfaces @('filesystem') -Timestamp $TS
  }
  Expect-Pass 'P-C2F-GOAL-CLEAN' {
    $pkt = New-NeoFirewalledBuilderPacket `
      -Goal 'Fix the parser bug in module X; keep public signatures stable.' `
      -ApprovedPaths $approved -ProtectedPaths $protected -RiskClass 'high' `
      -AllowlistItems $goodAllow -TestPlan @('run the suite', 'confirm exit 0') `
      -StopConditions @('scope_breach') -RepoRoot $RepoRoot -DeclaredSurfaces @('filesystem') -Timestamp $TS
    (@($pkt.input_packet.allowlist).Count -eq 3) -and ($pkt.goal.Length -gt 0)
  }

  # -- F3: explicit './' reject (allowlist rel AND approved path) -------------
  Expect-Block 'N-C2F-DOTSLASH-REL' "'./'-prefixed" {
    New-Good -AllowlistItems @(@{ rel = './dispatch.md'; role = 'dispatch' })
  }
  Expect-Block 'N-C2F-DOTSLASH-APPROVED' "'./'-prefixed" {
    New-Good -Approved @('./out.ps1')
  }

  # -- F4: member-shape fail-close --------------------------------------------
  Expect-Block 'N-C2F-MEMBER-STRAYKEY' 'STRAY key' {
    New-Good -AllowlistItems @(@{ rel = $relFileA; role = 'dispatch'; supervisor_cot = 'smuggled' })
  }
  Expect-Block 'N-C2F-MEMBER-NONSTRING-REL' 'not a STRING' {
    New-Good -AllowlistItems @(@{ rel = 123; role = 'dispatch' })
  }
  Expect-Block 'N-C2F-MEMBER-NONSTRING-ROLE' 'not a STRING' {
    New-Good -AllowlistItems @(@{ rel = $relFileA; role = @() })
  }

  # ================= C2-FIX-2 ADDITIONS (consume-side goal/test_plan scan) ====
  # The input_packet self_hash does NOT cover the wrapper fields goal/test_plan, so a
  # post-assembly mutation slipped past Test-NeoBuilderPacketFirewall (SC-confirmed
  # fail-open). These fixtures prove the consume re-check now enforces the IDENTICAL
  # assembler rules (same helper + bounds) on the wrapper fields.

  # -- N-C2F2-CONSUME-GOAL-MUTATED: the exact SC repro - assemble CLEAN, mutate
  # goal to forbidden context AFTER assembly, consume => BLOCK (was: PASS).
  Expect-Block 'N-C2F2-CONSUME-GOAL-MUTATED' 'prior_builder_transcript' {
    $pkt = New-Good
    $pkt.goal = 'prior_builder_transcript: builder said X then Y ...'
    Test-NeoBuilderPacketFirewall -Packet $pkt -RepoRoot $RepoRoot
  }

  # -- N-C2F2-CONSUME-TESTPLAN-MUTATED: same vector via a test_plan line ------
  Expect-Block 'N-C2F2-CONSUME-TESTPLAN-MUTATED' 'supervisor_cot' {
    $pkt = New-Good
    $pkt.test_plan = @('run the suite', 'inline supervisor_cot: because I reasoned...')
    Test-NeoBuilderPacketFirewall -Packet $pkt -RepoRoot $RepoRoot
  }

  # -- N-C2F2-CONSUME-GOAL-TOOLONG: bound enforced at consume too -------------
  Expect-Block 'N-C2F2-CONSUME-GOAL-TOOLONG' 'exceeds bound' {
    $pkt = New-Good
    $pkt.goal = 'x' * 2001
    Test-NeoBuilderPacketFirewall -Packet $pkt -RepoRoot $RepoRoot
  }

  # -- P-C2F2-CONSUME-CLEAN: regression guard - a clean assembled packet still
  # PASSES the consume re-check unchanged.
  Expect-Pass 'P-C2F2-CONSUME-CLEAN' {
    $pkt = New-Good
    Test-NeoBuilderPacketFirewall -Packet $pkt -RepoRoot $RepoRoot
  }

  # ================= C1C3-S1 LEDGERS + BREAKER CORE (2026-07-06) ===============
  # Fixtures for the S1 additive functions (spec C3 lines 110-125 + sec-0 lines
  # 19-27 + NB-2 line 310). Every RunRoot below is SCRATCH (under $ScratchRoot,
  # i.e. TEMP) and removed in the finally block - nothing writes outside scratch.
  Write-Host "`n--- C1C3-S1 LEDGERS + BREAKER CORE ---" -ForegroundColor Cyan

  $s1TS   = '2026-07-06T00:00:00Z'
  $s1Caps = @{ max_fix_rounds_per_slice = 3; max_external_calls = 10; max_wall_clock_hours = 4; max_spend = 25 }
  function New-S1Root {
    $r = Join-Path $ScratchRoot ('s1run_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $r | Out-Null
    return $r
  }
  # Craft one canonical attempt-ledger JSONL line (for corruption fixtures).
  function New-S1AttemptLine([string]$runId, [string]$sliceId, [int]$seq, [int]$round, [string]$kind) {
    return (Get-NeoCanonicalJson ([pscustomobject]@{
      run_id = $runId; slice_id = $sliceId; seq = $seq; round = $round; kind = $kind
      timestamp_utc = $s1TS; refused = $false; reason = 'NONE' }))
  }

  # -- N-S1-CAPS-*: each of the 4 caps x each bad shape => STOP CAPS_INVALID.
  # (Plain scriptblock literals: Expect-Block invokes them synchronously within
  # this loop iteration, in their origin scope, so $capName is current and the
  # script-scoped suite/supervisor functions resolve.)
  foreach ($capName in @('max_fix_rounds_per_slice', 'max_external_calls', 'max_wall_clock_hours', 'max_spend')) {
    Expect-Block "N-S1-CAPS-MISSING-$capName" 'CAPS_INVALID' {
      $bad = @{}; foreach ($k in $s1Caps.Keys) { if ($k -ne $capName) { $bad[$k] = $s1Caps[$k] } }
      New-NeoRunManifest -RunRoot (New-S1Root) -Caps $bad -Timestamp $s1TS
    }
    Expect-Block "N-S1-CAPS-ZERO-$capName" 'CAPS_INVALID' {
      $bad = @{}; foreach ($k in $s1Caps.Keys) { $bad[$k] = $s1Caps[$k] }; $bad[$capName] = 0
      New-NeoRunManifest -RunRoot (New-S1Root) -Caps $bad -Timestamp $s1TS
    }
    Expect-Block "N-S1-CAPS-NEGATIVE-$capName" 'CAPS_INVALID' {
      $bad = @{}; foreach ($k in $s1Caps.Keys) { $bad[$k] = $s1Caps[$k] }; $bad[$capName] = -1
      New-NeoRunManifest -RunRoot (New-S1Root) -Caps $bad -Timestamp $s1TS
    }
    Expect-Block "N-S1-CAPS-UNPARSEABLE-$capName" 'CAPS_INVALID' {
      $bad = @{}; foreach ($k in $s1Caps.Keys) { $bad[$k] = $s1Caps[$k] }; $bad[$capName] = 'not-a-number'
      New-NeoRunManifest -RunRoot (New-S1Root) -Caps $bad -Timestamp $s1TS
    }
  }

  # -- N-S1-MANIFEST-REWRITE: a run manifest is written ONCE ---------------------
  Expect-Block 'N-S1-MANIFEST-REWRITE' 'written ONCE' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
  }

  # -- N-S1-RESUME-NO-MANIFEST: no readable manifest = no readable run state ----
  Expect-Block 'N-S1-RESUME-NO-MANIFEST' 'LEDGER_FAILURE' {
    Read-NeoRunManifest -RunRoot (New-S1Root)
  }

  # -- N-S1-LEDGER-MALFORMED: garbage JSONL line => STOP on read, never skip ----
  Expect-Block 'N-S1-LEDGER-MALFORMED' 'LEDGER_FAILURE' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [System.IO.File]::AppendAllText((Join-Path $root 'attempt_ledger.jsonl'), "{this is not json}`n", (New-Object System.Text.UTF8Encoding($false)))
    Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 0 -Kind 'initial' -Timestamp $s1TS
  }

  # -- N-S1-LEDGER-NONMONOTONE: seq GAP and seq REGRESS both => STOP -------------
  Expect-Block 'N-S1-LEDGER-NONMONOTONE-GAP' 'monotonicity' {
    $root = New-S1Root
    $m = New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
    $enc = New-Object System.Text.UTF8Encoding($false)
    $l1 = New-S1AttemptLine $m.run_id 'slice-a' 1 0 'initial'
    $l3 = New-S1AttemptLine $m.run_id 'slice-a' 3 1 'fix'      # gap: seq 2 missing
    [System.IO.File]::AppendAllText((Join-Path $root 'attempt_ledger.jsonl'), "$l1`n$l3`n", $enc)
    Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 2 -Kind 'fix' -Timestamp $s1TS
  }
  Expect-Block 'N-S1-LEDGER-NONMONOTONE-REGRESS' 'monotonicity' {
    $root = New-S1Root
    $m = New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
    $enc = New-Object System.Text.UTF8Encoding($false)
    $l1 = New-S1AttemptLine $m.run_id 'slice-a' 1 0 'initial'
    $l2 = New-S1AttemptLine $m.run_id 'slice-a' 2 1 'fix'
    $l2b = New-S1AttemptLine $m.run_id 'slice-a' 2 2 'fix'     # regress: seq 2 repeated
    [System.IO.File]::AppendAllText((Join-Path $root 'attempt_ledger.jsonl'), "$l1`n$l2`n$l2b`n", $enc)
    Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 3 -Kind 'fix' -Timestamp $s1TS
  }

  # -- N-S1-LEDGER-APPENDFAIL: unwritable ledger => STOP, dispatch aborted -------
  Expect-Block 'N-S1-LEDGER-APPENDFAIL' 'ABORTED' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 0 -Kind 'initial' -Timestamp $s1TS)
    Set-ItemProperty -LiteralPath (Join-Path $root 'attempt_ledger.jsonl') -Name IsReadOnly -Value $true
    Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 1 -Kind 'fix' -Timestamp $s1TS
  }

  # -- N-S1-LEDGER-RESUME-MISSING: resume-shaped read of a missing ledger => STOP
  Expect-Block 'N-S1-LEDGER-RESUME-MISSING' 'resume without a readable ledger' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    Read-NeoAttemptLedger -RunRoot $root
  }

  # -- N-S1-CAP-BOUNDARY (NB-2, the headline fixture): rounds 1..3 land with
  # refused=$false; the 4TH fix entry LANDS in the ledger AND returns
  # refused=$true reason CAP_FIX_ROUNDS - assert BOTH.
  Expect-Pass 'N-S1-CAP-BOUNDARY' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    $ok = $true
    $r0 = Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 0 -Kind 'initial' -Timestamp $s1TS
    $ok = $ok -and (-not $r0.refused)
    foreach ($i in 1..3) {
      $ri = Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round $i -Kind 'fix' -Timestamp $s1TS
      $ok = $ok -and (-not $ri.refused) -and ($ri.reason -ceq 'NONE') -and ($ri.post_increment_count -eq $i)
    }
    $r4 = Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 4 -Kind 'fix' -Timestamp $s1TS
    $lines = @([System.IO.File]::ReadAllText((Join-Path $root 'attempt_ledger.jsonl')) -split "`n" | Where-Object { $_ -ne '' })
    # BOTH: the refusal fired AND the write-ahead entry landed (5 lines: initial + 4 fixes)
    $ok -and $r4.refused -and ($r4.reason -ceq 'CAP_FIX_ROUNDS') -and ($r4.post_increment_count -eq 4) -and ($lines.Count -eq 5)
  }
  # round-0 'initial' never counts against the cap: with cap=3 and the initial
  # entry present, the 3rd FIX still passes (if 'initial' counted, its
  # post-increment count would already exceed the cap at fix 3).
  Expect-Pass 'N-S1-CAP-BOUNDARY-INITIAL-UNCOUNTED' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-b' -Round 0 -Kind 'initial' -Timestamp $s1TS)
    [void](Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-b' -Round 1 -Kind 'fix' -Timestamp $s1TS)
    [void](Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-b' -Round 2 -Kind 'fix' -Timestamp $s1TS)
    $r3 = Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-b' -Round 3 -Kind 'fix' -Timestamp $s1TS
    (-not $r3.refused) -and ($r3.post_increment_count -eq 3)
  }

  # -- N-S1-WALLCLOCK-TRIP: started 5h ago, cap 4h => tripped (3h => not) --------
  # (REVISED S1-FIX F4, disclosed: Test-NeoRunWallClock now takes -RunRoot and
  # reads the PERSISTED manifest itself - the trip is computed from DISK state.)
  Expect-Pass 'N-S1-WALLCLOCK-TRIP' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp '2026-07-06T00:00:00Z')
    $trip = Test-NeoRunWallClock -RunRoot $root -NowUtc '2026-07-06T05:00:00Z'
    $hold = Test-NeoRunWallClock -RunRoot $root -NowUtc '2026-07-06T03:00:00Z'
    $trip.tripped -and ($trip.reason -ceq 'CAP_WALL_CLOCK') -and (-not $hold.tripped)
  }
  # -- N-S1-WALLCLOCK-MALFORMED: malformed clock input => STOP, never "not yet
  # tripped" (REVISED S1-FIX F4, disclosed: the crafted-manifest path no longer
  # exists - New-NeoRunManifest validates started_at_utc at write and
  # Read-NeoRunManifest re-validates at read - so the malformed-timestamp probe
  # moves to -NowUtc; the "never 'not yet tripped'" assertion is preserved.
  # The tampered-DISK case is newly pinned by N-S1F-WALLCLOCK-DISK-BOUND.)
  Expect-Block 'N-S1-WALLCLOCK-MALFORMED' 'CAP_WALL_CLOCK' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    Test-NeoRunWallClock -RunRoot $root -NowUtc 'yesterday-ish'
  }

  # -- N-S1-EXTCALL-CAP: the 11th call is refused AND its entry landed -----------
  Expect-Pass 'N-S1-EXTCALL-CAP' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    $ok = $true
    foreach ($i in 1..10) {
      $ri = Add-NeoRunExternalCallEntry -RunRoot $root -Timestamp $s1TS
      $ok = $ok -and (-not $ri.refused) -and ($ri.post_increment_count -eq $i)
    }
    $r11 = Add-NeoRunExternalCallEntry -RunRoot $root -Timestamp $s1TS
    $lines = @([System.IO.File]::ReadAllText((Join-Path $root 'external_call_ledger.jsonl')) -split "`n" | Where-Object { $_ -ne '' })
    $ok -and $r11.refused -and ($r11.reason -ceq 'CAP_EXTERNAL_CALLS') -and ($lines.Count -eq 11)
  }

  # -- N-S1-SLOT-FORGERY (spec sec-0, the headline fixture): a supervisor-crafted
  # auditor-labeled slot with NO spawn-ledger entry CANNOT fill the slot --------
  Expect-Block 'N-S1-SLOT-FORGERY' 'SPAWN_UNCORRELATED' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
  }
  # -- N-S1-SPAWN-STALE-ROUND: correlated identity+bundle but WRONG round => BLOCK
  Expect-Block 'N-S1-SPAWN-STALE-ROUND' 'SPAWN_UNCORRELATED' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-2'
  }
  # -- N-S1-SPAWN-WRONG-BUNDLE: right identity+round, other bundle_ref => BLOCK --
  Expect-Block 'N-S1-SPAWN-WRONG-BUNDLE' 'SPAWN_UNCORRELATED' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/OTHER.json' }
    Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
  }
  # -- N-S1-SPAWN-LEDGER-CORRUPT: malformed spawn ledger => BLOCK, never
  # treated-as-empty --------------------------------------------------------------
  Expect-Block 'N-S1-SPAWN-LEDGER-CORRUPT' 'LEDGER_FAILURE' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [System.IO.File]::AppendAllText((Join-Path $root 'spawn_ledger.jsonl'), "not json at all`n", (New-Object System.Text.UTF8Encoding($false)))
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
  }

  # -- P-S1-HAPPY-PATH: manifest -> initial -> 2 fixes -> spawn -> correlated slot
  # passes -> read-back clean (the correlate call IS the spawn read-back) --------
  Expect-Pass 'P-S1-HAPPY-PATH' {
    $root = New-S1Root
    $m = New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
    $r0 = Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 0 -Kind 'initial' -Timestamp $s1TS
    $r1 = Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 1 -Kind 'fix' -Timestamp $s1TS
    $r2 = Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 2 -Kind 'fix' -Timestamp $s1TS
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    $corr = Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
    $all  = Read-NeoAttemptLedger -RunRoot $root
    $mine = Read-NeoAttemptLedger -RunRoot $root -SliceId 'slice-a'
    (-not $r0.refused) -and (-not $r1.refused) -and (-not $r2.refused) -and $corr -and
      (@($all).Count -eq 3) -and (@($mine).Count -eq 3) -and ($m.run_id -ceq [string]$all[0].run_id)
  }
  # -- P-S1-RESUME-CONTINUES: a fresh read of an existing ledger CONTINUES the
  # count (next entry after crash-simulated re-read = seq 3, not seq 1) ----------
  Expect-Pass 'P-S1-RESUME-CONTINUES' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 0 -Kind 'initial' -Timestamp $s1TS)
    [void](Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 1 -Kind 'fix' -Timestamp $s1TS)
    # crash-simulate: nothing carried in memory; re-read from disk, then append.
    $resumed = Read-NeoAttemptLedger -RunRoot $root -SliceId 'slice-a'
    $next = Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 2 -Kind 'fix' -Timestamp $s1TS
    (@($resumed).Count -eq 2) -and ([int]$next.entry.seq -eq 3) -and ($next.post_increment_count -eq 2) -and (-not $next.refused)
  }

  # ================= C1C3-S1-FIX BOUNDARY CLOSURES (2026-07-06) ================
  # Fixtures pinning the four SC-confirmed fail-opens CLOSED (external Codex
  # F1-F4 + the isolated auditor's LOW, convergence record 2026-07-06): every
  # crafted-boundary case that previously slipped a consume/read/write seam
  # must now BLOCK with its specific reason, and one clean-path guard proves no
  # over-block. All RunRoots SCRATCH; removed in the finally block.
  Write-Host "`n--- C1C3-S1-FIX BOUNDARY CLOSURES ---" -ForegroundColor Cyan

  # Craft one canonical spawn-ledger JSONL line (for consume-side fixtures -
  # the sanctioned Add path now refuses these, so the fixture writes the file
  # the way an attacker would: by hand).
  function New-S1SpawnLine([string]$runId, [string]$spawnId, [string]$identity, [string]$bundleRef, [string]$roundId) {
    return (Get-NeoCanonicalJson ([pscustomobject]@{
      run_id = $runId; spawn_id = $spawnId; auditor_identity = $identity
      bundle_ref = $bundleRef; round_id = $roundId; timestamp_utc = $s1TS }))
  }

  # -- N-S1F-CONSUME-BADREF (F1, ledger side): a hand-crafted spawn-ledger line
  # with a traversal bundle_ref => BLOCK SPAWN_INVALID at the correlation gate,
  # EVEN THOUGH a clean correlated entry also exists and the slot itself is
  # safe (proves EVERY ledger-read ref is validated BEFORE any comparison).
  Expect-Block 'N-S1F-CONSUME-BADREF' 'SPAWN_INVALID' {
    $root = New-S1Root
    $m = New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
    $enc = New-Object System.Text.UTF8Encoding($false)
    $clean = New-S1SpawnLine $m.run_id 'spawn-1' 'isolated-cold-claude' 'bundles/round1/bundle.json' 'round-1'
    $evil  = New-S1SpawnLine $m.run_id 'spawn-2' 'someone-else' '..\..\outside\evil.json' 'round-9'
    [System.IO.File]::AppendAllText((Join-Path $root 'spawn_ledger.jsonl'), "$clean`n$evil`n", $enc)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
  }
  # -- N-S1F-CONSUME-BADREF-SLOT (F1, slot side): clean ledger, but the SLOT's
  # bundle_ref is rooted => BLOCK SPAWN_INVALID before any comparison.
  Expect-Block 'N-S1F-CONSUME-BADREF-SLOT' 'SPAWN_INVALID' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'C:\outside\evil.json' }
    Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
  }
  # -- N-S1F-DUP-CORRELATION (F2a, the recorded repro): TWO entries matching the
  # same identity+bundle_ref+round (distinct spawn_ids, so each append is
  # individually legal) => the correlation is AMBIGUOUS => BLOCK SPAWN_INVALID,
  # never first-match-wins ("a single prior spawn-ledger entry", spec sec-0).
  Expect-Block 'N-S1F-DUP-CORRELATION' 'AMBIGUOUS' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-2' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
  }
  # -- N-S1F-DUP-SPAWNID-ADD (F2b, the recorded repro): appending a spawn_id
  # that already exists => BLOCK SPAWN_INVALID at the write boundary. Re-pinned
  # (S1-FIX-2 NF2, Director Resolution B) to the SHARED-helper token 'must be
  # UNIQUE' (present in both the old inline and new shared messages) after fix #2
  # absorbed the inline scan into Assert-NeoSpawnLedgerUnique - behavior unchanged
  # (still SPAWN_INVALID BLOCK at the write boundary).
  Expect-Block 'N-S1F-DUP-SPAWNID-ADD' 'must be UNIQUE' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round2/bundle.json' -RoundId 'round-2' -Timestamp $s1TS
  }
  # -- N-S1F-EXTCALL-IN-ATTEMPT-READ (F3a, the recorded repro): a hand-crafted
  # kind='external_call' line in attempt_ledger.jsonl is SCHEMA-VALID (shared
  # enum) but must BLOCK LEDGER_FAILURE on the public read/resume/END-trail
  # path (previously returned clean).
  Expect-Block 'N-S1F-EXTCALL-IN-ATTEMPT-READ' 'does not belong in the attempt ledger' {
    $root = New-S1Root
    $m = New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
    $enc = New-Object System.Text.UTF8Encoding($false)
    $l1 = New-S1AttemptLine $m.run_id 'slice-a' 1 0 'initial'
    $lx = New-S1AttemptLine $m.run_id '__run__' 1 1 'external_call'
    [System.IO.File]::AppendAllText((Join-Path $root 'attempt_ledger.jsonl'), "$l1`n$lx`n", $enc)
    Read-NeoAttemptLedger -RunRoot $root
  }
  # -- N-S1F-INITIAL-IN-EXTCALL-READ (F3b): a hand-crafted kind='initial' line
  # in external_call_ledger.jsonl => BLOCK LEDGER_FAILURE on the external-call
  # read path (shape guard symmetric with the attempt side).
  Expect-Block 'N-S1F-INITIAL-IN-EXTCALL-READ' 'does not belong in the external-call ledger' {
    $root = New-S1Root
    $m = New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
    $enc = New-Object System.Text.UTF8Encoding($false)
    $lx = New-S1AttemptLine $m.run_id 'slice-a' 1 0 'initial'
    [System.IO.File]::AppendAllText((Join-Path $root 'external_call_ledger.jsonl'), "$lx`n", $enc)
    Add-NeoRunExternalCallEntry -RunRoot $root -Timestamp $s1TS
  }
  # -- N-S1F-RUNRESERVED-AT-ATTEMPT-ADD (F3c, the isolated LOW): the reserved
  # '__run__' slice_id is refused at the attempt-ledger WRITE boundary =>
  # BLOCK LEDGER_FAILURE (reservation symmetric with the read side).
  Expect-Block 'N-S1F-RUNRESERVED-AT-ATTEMPT-ADD' 'RESERVED' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId '__run__' -Round 0 -Kind 'initial' -Timestamp $s1TS
  }
  # -- N-S1F-WALLCLOCK-DISK-BOUND (F4 negative, the recorded repro's closure):
  # the crafted-object path no longer exists - the ONLY input is the PERSISTED
  # manifest, and TAMPERED persisted caps (max_wall_clock_hours forged to 0)
  # => STOP CAPS_INVALID via Read-NeoRunManifest, never a trip computed from
  # forged caps.
  Expect-Block 'N-S1F-WALLCLOCK-DISK-BOUND' 'CAPS_INVALID' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    $mPath = Join-Path $root 'run_manifest.json'
    $raw = [System.IO.File]::ReadAllText($mPath)
    $tampered = $raw -replace '"max_wall_clock_hours"\s*:\s*[0-9.]+', '"max_wall_clock_hours": 0'
    if ($tampered -ceq $raw) { throw 'fixture setup failed: tamper regex did not match' }
    [System.IO.File]::WriteAllText($mPath, $tampered, (New-Object System.Text.UTF8Encoding($false)))
    Test-NeoRunWallClock -RunRoot $root -NowUtc '2026-07-06T05:00:00Z'
  }
  # -- N-S1F-WALLCLOCK-DISK-TRIP (F4 positive): the trip is computed from the
  # DISK manifest - same RunRoot, same NowUtc: not tripped at 3h elapsed, then
  # after the PERSISTED started_at_utc is moved 2h earlier (schema-valid
  # tamper), the SAME call trips at 5h vs the 4h cap. Disk state decides.
  Expect-Pass 'N-S1F-WALLCLOCK-DISK-TRIP' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp '2026-07-06T02:00:00Z')
    $hold = Test-NeoRunWallClock -RunRoot $root -NowUtc '2026-07-06T05:00:00Z'
    $mPath = Join-Path $root 'run_manifest.json'
    $raw = [System.IO.File]::ReadAllText($mPath)
    $moved = $raw.Replace('2026-07-06T02:00:00Z', '2026-07-06T00:00:00Z')
    if ($moved -ceq $raw) { throw 'fixture setup failed: origin rewrite did not match' }
    [System.IO.File]::WriteAllText($mPath, $moved, (New-Object System.Text.UTF8Encoding($false)))
    $trip = Test-NeoRunWallClock -RunRoot $root -NowUtc '2026-07-06T05:00:00Z'
    (-not $hold.tripped) -and $trip.tripped -and ($trip.reason -ceq 'CAP_WALL_CLOCK') -and ($trip.cap_hours -eq 4)
  }
  # -- P-S1F-CORRELATION-STILL-PASSES (no over-block): a single clean spawn
  # entry + safe refs still correlates to $true, and a clean attempt ledger
  # still reads back through the hardened read path.
  Expect-Pass 'P-S1F-CORRELATION-STILL-PASSES' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 0 -Kind 'initial' -Timestamp $s1TS)
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    $corr = Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
    $back = Read-NeoAttemptLedger -RunRoot $root -SliceId 'slice-a'
    $corr -and (@($back).Count -eq 1)
  }
  # -- N-S1F2-RUNRESERVED-AT-ATTEMPT-READ (S1-FIX-2 NF1, the recorded repro): a
  # hand-crafted attempt_ledger.jsonl line with the RESERVED slice_id '__run__'
  # and kind='initial' is SCHEMA-VALID and passed the S1-FIX kind guard +
  # monotonicity, reading clean on the public read/resume/END-trail path (the
  # reservation was enforced only at the WRITE param). It must now BLOCK
  # LEDGER_FAILURE on Read-NeoAttemptLedger - reservation symmetric at read too.
  Expect-Block 'N-S1F2-RUNRESERVED-AT-ATTEMPT-READ' 'RESERVED' {
    $root = New-S1Root
    $m = New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
    $enc = New-Object System.Text.UTF8Encoding($false)
    $lx = New-S1AttemptLine $m.run_id '__run__' 1 0 'initial'
    [System.IO.File]::AppendAllText((Join-Path $root 'attempt_ledger.jsonl'), "$lx`n", $enc)
    Read-NeoAttemptLedger -RunRoot $root
  }
  # -- N-S1F2-DUP-SPAWNID-CONSUME (S1-FIX-2 NF2, the recorded repro): a
  # hand-crafted spawn_ledger.jsonl with TWO schema-valid entries sharing
  # spawn_id 'spawn-1' - entry A correlates the slot (identity+bundle+round),
  # entry B does NOT. S1-FIX enforced uniqueness only at the WRITE boundary, so
  # the consume gate saw exactly-one correlated match and returned $true on an
  # invariant-violating ledger. It must now BLOCK SPAWN_INVALID at consume,
  # re-verifying the uniqueness invariant BEFORE the correlation loop.
  Expect-Block 'N-S1F2-DUP-SPAWNID-CONSUME' 'SPAWN_INVALID' {
    $root = New-S1Root
    $m = New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS
    $enc = New-Object System.Text.UTF8Encoding($false)
    $a = New-S1SpawnLine $m.run_id 'spawn-1' 'isolated-cold-claude' 'bundles/round1/bundle.json' 'round-1'
    $b = New-S1SpawnLine $m.run_id 'spawn-1' 'someone-else' 'bundles/round9/other.json' 'round-9'
    [System.IO.File]::AppendAllText((Join-Path $root 'spawn_ledger.jsonl'), "$a`n$b`n", $enc)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
  }
  # -- P-S1F2-NO-OVERBLOCK (no regression on the happy path): a clean attempt
  # ledger (real slice_id) written via the sanctioned add path + a clean
  # single-spawn_id spawn ledger with one correlated safe entry => the NF1
  # reservation guard and the NF2 uniqueness scan do NOT over-block:
  # Read-NeoAttemptLedger returns the entry AND Assert-NeoSpawnCorrelatedSlot
  # returns $true.
  Expect-Pass 'P-S1F2-NO-OVERBLOCK' {
    $root = New-S1Root
    [void](New-NeoRunManifest -RunRoot $root -Caps $s1Caps -Timestamp $s1TS)
    [void](Add-NeoAttemptLedgerEntry -RunRoot $root -SliceId 'slice-a' -Round 0 -Kind 'initial' -Timestamp $s1TS)
    [void](Add-NeoSpawnLedgerEntry -RunRoot $root -SpawnId 'spawn-1' -AuditorIdentity 'isolated-cold-claude' -BundleRef 'bundles/round1/bundle.json' -RoundId 'round-1' -Timestamp $s1TS)
    $slot = [pscustomobject]@{ auditor_identity = 'isolated-cold-claude'; bundle_ref = 'bundles/round1/bundle.json' }
    $corr = Assert-NeoSpawnCorrelatedSlot -RunRoot $root -Slot $slot -RoundId 'round-1'
    $back = Read-NeoAttemptLedger -RunRoot $root -SliceId 'slice-a'
    $corr -and (@($back).Count -eq 1)
  }

} finally {
  # ---- residue cleanup + second-pass proof ----------------------------------
  if (Test-Path -LiteralPath $absDir) { Remove-Item -Recurse -Force -LiteralPath $absDir }
  if (-not $KeepScratch -and (Test-Path -LiteralPath $ScratchRoot)) {
    Remove-Item -Recurse -Force -LiteralPath $ScratchRoot
  }
}

# ---- verdict ----------------------------------------------------------------
$fail = @($script:results | Where-Object { -not $_.pass }).Count
$total = @($script:results).Count
$pass = $total - $fail
Write-Host ("`n=== C2 FIREWALL SUITE: {0}/{1} PASS, {2} FAIL ===" -f $pass, $total, $fail) `
  -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

if ($ProofOut) {
  $proof = [pscustomobject]@{
    suite   = 'orch_supervisor_suite'
    slice   = '4.0-P4-AUTONOMY-C2'
    total   = $total
    passed  = $pass
    failed  = $fail
    results = $script:results
  }
  $dir = Split-Path -Parent $ProofOut
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  ($proof | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ProofOut -Encoding UTF8
}

if ($fail -eq 0) { exit 0 } else { exit 1 }
