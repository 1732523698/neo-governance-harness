# orch_loop_suite.ps1 - NEO 4.0-P4-AUTONOMY C1C3-S3a loop round-core + C1C3-S3b
# multi-round convergence wrapper INDEPENDENT harness. ASCII-only (D10). Kept
# SEPARATE from the module.
#
# Proves orch_loop.ps1 fails closed on the S3a surface (spec sec-5 + C1b/C1c + sec-0
# + the DEF-P8 choke-point contract):
#   - N-S3A-DISPATCH-NF1        : empty ProposedEdits => STOP; .neo/** edit => STOP at
#                                 dispatch; the wrapper carries the DENIED_PATHS contract.
#   - N-S3A-ROUND-CHAIN         : builder-commit / three-branch / gov-tamper /
#                                 risk-escalation each => right reason_code + manifest
#                                 row + ordering proven (enforcement before aggregation).
#   - N-S3A-C1C-JUDGING-FIX-INLOOP : judging-class fix target in-loop => STOP.
#   - N-S3A-SPAWN-UNCORRELATED-INLOOP : auditor-labeled slot w/o correlated spawn entry
#                                 reaching aggregation => BLOCK SPAWN_UNCORRELATED.
#   - N-S3A-HIGH-WITHOUT-C4     : HIGH + slot-satisfied + spawn-correlated + lane
#                                 NOT_WIRED => CANNOT GO; LOW/MED controls => GO.
#   - N-S3A-NOTIFY-FIRES        : every STOP class composes EXACTLY ONE notification
#                                 with the CORRECT gate class; UNKNOWN still composes.
#   - N-S3A-NOTIFY-NEVER-AUTHORITY : notify seam forced to fail => the STOP still lands
#                                 with the same reason_code; failure in the row.
#   - N-S3A-MANIFEST-APPEND-ONLY: second round appends; corrupt line => fail-closed;
#                                 a STOPPED round still has its row (write-ahead).
#   - P-S3A-CLEAN-ROUND         : clean LOW round end-to-end => one row, no notify.
#   - P-S3A-FLOOR-24            : the 24-rel mandatory floor passes against the REAL
#                                 governed tree (lockstep edit + judging-from-birth).
#
# S3b coverage (Invoke-NeoLoopConverge - spec sec-5 184-198 + C3 110-125 + C1 54-56):
#   - P-S3B-GO-BREAKS           : GO round => break; no further dispatch/seam call;
#                                 exactly one caller-recorded row (stop/notify NONE).
#   - P-S3B-NONGO-ONE-FIX       : one non-GO then GO => exactly one fix re-dispatch,
#                                 two rows (recommendation preserved), counts align.
#   - N-S3B-SEAM-NOT-AUTHORITY  : forged verdict/EndReport-shaped seam return changes
#                                 NOTHING (gates read disk); throwing seam => routed
#                                 STOP BUILDER_SEAM_FAILED; null seam => STOP before
#                                 any ledger write or dispatch.
#   - N-S3B-CAP-BOUNDARY-4TH-REFUSED : 3 fixes consumed; 4th non-GO => write-ahead
#                                 entry LANDS (refused, CAP_FIX_ROUNDS), dispatch
#                                 REFUSED (no 4th seam call), STOP row + BREAKER_TRIP,
#                                 manifest row count == attempt-ledger count.
#   - N-S3B-WALLCLOCK-TRIP      : persisted start beyond the 4h cap (vs the REAL
#                                 clock - persisted-state manipulation, no provider)
#                                 => STOP CAP_WALL_CLOCK (BREAKER_TRIP), no dispatch.
#   - N-S3BF-NO-TIME-CHANNEL    : binding -NowUtcProvider on Invoke-NeoLoopConverge
#                                 or Invoke-NeoLoopWallClockGate FAILS with a
#                                 parameter-binding error - the caller time-authority
#                                 channel is GONE, not defaulted (S3b-FIX CX-F1).
#   - N-S3BF-WALLCLOCK-REAL     : the SC repro - manifest started_at = real now
#                                 minus 10h, cap 4h => STOP CAP_WALL_CLOCK
#                                 (BREAKER_TRIP) with a STOP row, BEFORE any
#                                 ledger write.
#   - N-S3B-LEDGER-FAILURE      : corrupt attempt ledger mid-loop => STOP
#                                 LEDGER_FAILURE, no dispatch, NO repair (bytes equal).
#   - N-S3B-FIX-ESCAPES / BUILD-ESCAPES : a fix dispatch into DENIED_PATHS / a build
#                                 outside ApprovedPaths => the frozen guards fire
#                                 INSIDE the wrapper's path.
#   - N-S3B-ONE-ROW-PER-ROUND   : a STOP round inside the wrapper yields EXACTLY ONE
#                                 row (the round core's) - never double-recorded.
#   - N-S3B-RUNID-SINGLE-READ   : ONE run-manifest read per stop-path row (counted);
#                                 a manifest mutated after the dry-run read can no
#                                 longer diverge the row's run_id; a forged -RunId row
#                                 lands but is REJECTED at the very next read; blank
#                                 -RunId = byte-equivalent disk-read fallback.
#   - P-S3B-TRAIL-PRECHECK      : full multi-round scenario => iteration-manifest rows
#                                 == attempt-ledger entries (pre-proving S3c I7/N3).
#
# STRUCTURALLY LIVE-SEND-INCAPABLE (notify_fixture_suite discipline): this suite
# NEVER passes the live switch to any function - grep this file: the live-send
# parameter token appears NOWHERE; every loop context pins notify_live_send=$false
# plus a scratch TestModeDir, so the frozen notify module can only compose to disk
# (zero network). Slice ids carry a per-run GUID tag so the notify module's 10-min
# dedupe window can never mask a compose on suite reruns.
#
# The real .neo/** is NEVER mutated: scratch mirrors + scratch git repos + scratch
# run-roots under $env:TEMP. Writes NO AUDIT_RESULT of its own (the honest frozen
# auditor stub derives fixture verdicts). Residue-clean SECOND PASS. exit 0/1.
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'

$orchDir = Split-Path -Parent $PSScriptRoot   # ...\.neo\scripts\orchestrator
. "$orchDir\orch_loop.ps1"                    # sources govmanifest/diff/io/schema/class/_neo_root
                                              # + supervisor + router + enforce + engine + notify

# git is a hard precondition of the C1b baseline lane (NF-3: no repo => STOP).
$gitOk = $false
try { & git --version *> $null; $gitOk = ($LASTEXITCODE -eq 0) } catch { $gitOk = $false }
if (-not $gitOk) { throw "orch_loop_suite: git is required for the C1b baseline fixtures (NF-3) and was not found on PATH" }

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_loop_s3a_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors orch_govmanifest_suite framing) -----------------
$script:results = @()
function Record($name, $pass, $detail, $kind = 'negative') {
  $script:results += [pscustomobject]@{ guard = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  $ktag = if ($kind -eq 'negative') { 'GUARD' } elseif ($kind -eq 'skip') { 'SKIP ' } else { 'info ' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $ktag, $name, $detail) -ForegroundColor $col
}
function Expect-Block($name, $codeSubstr, $sb) {
  try { & $sb; Record $name $false 'NO BLOCK (guard did not fire)' 'negative' }
  catch {
    $m = $_.Exception.Message
    if ($m -like 'NEO-BLOCK:*') {
      if ($codeSubstr -and ($m -notlike "*$codeSubstr*")) {
        Record $name $false ("BLOCK but wrong reason (want $codeSubstr): " + $m) 'negative'
      } else { Record $name $true $m 'negative' }
    } else { Record $name $false ('threw non-BLOCK: ' + $m) 'negative' }
  }
}
function Expect-Ok($name, $sb) {
  try { $r = & $sb; Record $name $true "$r" 'positive' }
  catch { Record $name $false ('unexpected block/error: ' + $_.Exception.Message) 'positive' }
}
function Expect-Value($name, $want, $sb) {
  try { $r = & $sb
    if ("$r" -eq "$want") { Record $name $true "= $r" 'positive' }
    else { Record $name $false ("got '$r' want '$want'") 'positive' }
  } catch { Record $name $false ('unexpected error: ' + $_.Exception.Message) 'positive' }
}
# A STOP RESULT check: the round function RETURNED a stop (never threw), with the
# expected reason_code, a landed manifest row carrying it, and EXACTLY ONE composed
# notification of the expected gate class in the case's own TestModeDir.
function Expect-StopResult($name, $stop, [string]$wantReason, [string]$wantGate, [string]$runRoot, [string]$notifyDir) {
  try {
    if ($null -eq $stop) { Record $name $false 'stop result is null' 'negative'; return }
    if (-not $stop.stopped) { Record $name $false 'NOT stopped (fail-open)' 'negative'; return }
    if ([string]$stop.reason_code -cne $wantReason) { Record $name $false ("reason_code '" + $stop.reason_code + "' want '" + $wantReason + "'") 'negative'; return }
    if ([string]$stop.gate_class -cne $wantGate) { Record $name $false ("gate_class '" + $stop.gate_class + "' want '" + $wantGate + "'") 'negative'; return }
    # NOTE: assignment form, NOT @(call) - the engine family's ,@() return keeps
    # the entry array whole as ONE stream object; @(call) would nest it.
    $rows = Read-NeoIterationManifest -RunRoot $runRoot
    $last = $rows[$rows.Count - 1]
    if ([string](Get-NeoProp $last 'stop_reason_code') -cne $wantReason) { Record $name $false ("manifest row stop_reason_code '" + (Get-NeoProp $last 'stop_reason_code') + "' want '" + $wantReason + "'") 'negative'; return }
    if ([string](Get-NeoProp $last 'notify_gate_class') -cne $wantGate) { Record $name $false ("manifest row notify_gate_class '" + (Get-NeoProp $last 'notify_gate_class') + "' want '" + $wantGate + "'") 'negative'; return }
    $emls = @(Get-EmlFiles $notifyDir)
    if ($emls.Count -ne 1) { Record $name $false ("composed notification count " + $emls.Count + " want EXACTLY 1") 'negative'; return }
    if ($emls[0].Name -notlike "*_${wantGate}_*") { Record $name $false ("composed file '" + $emls[0].Name + "' does not carry gate class '" + $wantGate + "'") 'negative'; return }
    Record $name $true ("STOP " + $wantReason + " => " + $wantGate + "; row landed (write-ahead); exactly 1 composed notification") 'negative'
  } catch { Record $name $false ('assertion error: ' + $_.Exception.Message) 'negative' }
}
function Get-EmlFiles([string]$dir) {
  if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -like '*.eml.txt' })
}

# ---- shared fixture plumbing ---------------------------------------------------
$TS   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$tag  = [guid]::NewGuid().ToString('N').Substring(0, 8)   # per-run tag (defeats notify dedupe)
$caps = @{ max_fix_rounds_per_slice = 3; max_external_calls = 10; max_wall_clock_hours = 4; max_spend = 100 }
$index = Get-NeoRunSchemaIndex
$stub  = Join-Path $orchDir 'orch_auditor_stub.ps1'
$evidencePath = 'S:/NEO_dev/NEO_SESSION/40-p4-autonomy-c1c3-s3a-loopcore-2026-07-06'

$script:seq = 0
function New-RunRoot {
  $script:seq++
  $r = Join-Path $ScratchRoot ("run{0}" -f $script:seq)
  New-Item -ItemType Directory -Force -Path $r | Out-Null
  [void](New-NeoRunManifest -RunRoot $r -Caps $caps -Timestamp $TS)
  return $r
}
function New-NotifyDir([string]$case) {
  $d = Join-Path $ScratchRoot ("notify_" + $case)
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function New-Ctx([string]$runRoot, [string]$case, [string]$notifyDir, [int]$round = 1, [int]$seq = 1) {
  return @{
    run_root = $runRoot
    slice_id = ("s3a-" + $tag + "-" + $case)
    round = $round
    attempt_seq = $seq
    evidence_path = $evidencePath
    timestamp_utc = $TS
    notify_test_mode_dir = $notifyDir
    notify_live_send = $false
  }
}

# quiet git (fixture-local; NOT the module's Invoke-NeoGit - mirrors orch_diff_suite)
function Invoke-GitQuiet { param([string]$Repo, [string[]]$GitArgs)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & git -C $Repo @GitArgs 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
}
function New-AppRepo([string]$name) {
  $r = Join-Path $ScratchRoot $name
  New-Item -ItemType Directory -Force -Path (Join-Path $r 'app') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $r 'locked') | Out-Null
  # NOTE: content/paths deliberately avoid every engine governed token
  # (money/payment/tax/ledger/auth/secret/migration/gate) so clean rounds derive low.
  Set-Content -LiteralPath (Join-Path $r 'app\widget.txt')  -Value 'hello widget' -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $r 'locked\keep.txt') -Value 'do not touch' -Encoding Ascii
  Invoke-GitQuiet $r @('init', '-q')
  Invoke-GitQuiet $r @('config', 'user.email', 'neo@sandbox.local')
  Invoke-GitQuiet $r @('config', 'user.name', 'neo-fixture')
  Invoke-GitQuiet $r @('config', 'commit.gpgsign', 'false')
  Invoke-GitQuiet $r @('config', 'core.autocrlf', 'false')
  Invoke-GitQuiet $r @('config', 'core.safecrlf', 'false')
  Invoke-GitQuiet $r @('add', '-A')
  Invoke-GitQuiet $r @('commit', '-q', '-m', 'base')
  return $r
}
$approved  = @('app')
$protected = @('locked')

# governed-mirror lite (govmanifest-suite pattern): live classmap + gov schema +
# a small judging fileset; used as the GovernedRoot for the round-checks re-verify.
$liveMap = [System.IO.Path]::GetFullPath((Join-Path $orchDir '..\..\schema\artifact_classes.json'))
$liveGovSchema = [System.IO.Path]::GetFullPath((Join-Path $orchDir '..\..\schema\governance_manifest.schema.json'))
function New-GovMirror([string]$name) {
  $root = Join-Path $ScratchRoot $name
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\schema') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\scripts\orchestrator') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\skills') | Out-Null
  Copy-Item -LiteralPath $liveMap -Destination (Join-Path $root '.neo\schema\artifact_classes.json') -Force
  Copy-Item -LiteralPath $liveGovSchema -Destination (Join-Path $root '.neo\schema\governance_manifest.schema.json') -Force
  Set-Content -LiteralPath (Join-Path $root '.neo\scripts\orchestrator\orch_engine.ps1') -Value '# engine stub' -Encoding Ascii
  return $root
}
function Pin-GovMirror([string]$mirror, [string]$pinName) {
  $pin = Build-NeoGovManifest -GovernedRoot $mirror -DerivedAt $TS
  $pinPath = Join-Path $ScratchRoot $pinName
  Write-NeoJsonFile $pinPath $pin
  return $pinPath
}

# router profile + frozen risk rows (autonomy-eligible: NO explicit_downgrade)
$profileObj = [pscustomobject]@{
  denylist = [pscustomobject]@{ entries = @([pscustomobject]@{ pattern = 'forbidden/**'; is_glob = $true }) }
  risk_tokens = [pscustomobject]@{ auth_tokens = @('zz-custom-token-a'); fin_tokens = @('zz-custom-token-b') }
}
$routerProfile = Resolve-NeoRouterProfile -Profile $profileObj
$rowLow  = [pscustomobject]@{ id = 'r-low';  area = 'general_feature'; risk_class = 'low';    never_batchable = $false; audit_tier = 'lightweight' }
$rowMed  = [pscustomobject]@{ id = 'r-med';  area = 'general_feature'; risk_class = 'medium'; never_batchable = $false; audit_tier = 'isolated' }
$rowHigh = [pscustomobject]@{ id = 'r-high'; area = 'security';        risk_class = 'high';   never_batchable = $true;  audit_tier = 'isolated' }

# convenience: run the C1b chain with the shared defaults
function Invoke-Chain($ctx, [string]$repo, $baseline, [string]$pinPath, [string]$mirror, [string[]]$fixTargets = @()) {
  return (Invoke-NeoLoopRoundChecks -Context $ctx -RepoRoot $repo -Baseline $baseline `
    -ApprovedPaths $approved -ProtectedPaths $protected -PinnedGovManifestPath $pinPath `
    -GovernedRoot $mirror -DerivedAt $TS -RouterProfile $routerProfile -RiskRow $rowLow `
    -ProposedFixTargets $fixTargets)
}

# ---- slot world (compact clone of the orch_enforce_suite E6 fixture world) -----
# S3a-FIX: default = the single passing proof. -NoTests yields an END with NO promised
# tests (the honest stub then DERIVES NEEDS-MORE - promisedCount == 0). The proof
# itself is written by New-SlotWorld and may exit non-zero (=> the stub DERIVES NO-GO).
# The verdict is ALWAYS derived by the stub, never injected; the slot we later fill
# must MATCH that derived verdict or the frozen seam BLOCKs it. (A -NoTests SWITCH is
# used rather than an empty-array parameter because a PS 'if' block returning @()
# collapses to $null - the switch is unambiguous.)
function New-SlotEnd([string]$slug, $slotVal, [switch]$NoTests) {
  $TestsRun = if ($NoTests) { @() } else { @(@{ command = 'run tests'; exit_code = 0; proof_ref = "./NEO_SESSION/$slug/proof.ps1" }) }
  $er = [pscustomobject][ordered]@{
    report_id = "er-$slug"; slug = $slug
    changed_files = @(@{ path = './app/widget.txt'; sha256_after = ('0' * 64); change_kind = 'edit' })
    diff_manifest = @(@{ path = './app/widget.txt'; diff_ref = './diffs/x.patch' })
    tests_run = @($TestsRun)
    skipped_or_unverified = @(); deferrals = @()
    rollback_notes = @{ snapshot_ref = './snapshots/pre'; touched_files = @('./app/widget.txt'); dependency_changes = @(); migration_status = 'none'; cleanup_status = 'clean' }
    touched_flags = @{ touched_constraints = $false; touched_tests_harness = $false; touched_profile_risk = $false }
    auditor_recommendation_slot = $slotVal
  }
  $er | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-NeoEnvelope -ArtifactId "er-$slug" -ArtifactClass 'evidence' `
    -SchemaId 'neo:subsession_end_report' -SchemaVersion '4.0-P4-S3a' -ProducerRole 'builder' -ProducerClass 'strong_producer' `
    -ValidatorRole 'builder' -ValidatorClass 'strong_producer' -ValidatorNAReason 'raw builder evidence pre-audit' `
    -Timestamp $TS -DeclaredPaths @('./app/') -DeclaredSurfaces @('filesystem') -SourcePackets @() -GateRef $null)
  Set-NeoArtifactHash $er
  return $er
}
function New-SlotWorld([string]$name, [string]$runRoot, [switch]$NoSpawnEntry, [string]$RoundId = 'round-1', [string]$Recommendation = 'GO') {
  $auditorId = 'isolated-auditor-cold'
  $root = Join-Path $ScratchRoot $name
  $slug = 'ss-loop'
  $slugDir = Join-Path $root "NEO_SESSION\$slug"
  $auditDir = Join-Path $slugDir 'audit'
  New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
  # S3a-FIX: shape the world so the HONEST deriving stub GENUINELY derives the target
  # verdict (never injected). GO => one passing proof; NO-GO => the SAME promised proof
  # re-runs exit 1; NEEDS-MORE => NO promised tests (stub: promisedCount==0 => NEEDS-MORE).
  # The slot we fill below then MATCHES that derived verdict (the frozen seam re-validates
  # slot.recommendation -ceq the derived verdict, so a mismatch would be a forged/stale
  # BLOCK, not the F1 non-GO path under test).
  $proofExit = if ($Recommendation -ceq 'NO-GO') { 'exit 1' } else { 'exit 0' }
  $noTests = ($Recommendation -ceq 'NEEDS-MORE')   # NEEDS-MORE => no promised tests => stub derives NEEDS-MORE
  $erPath = Join-Path $slugDir 'SUBSESSION_END_REPORT.json'
  Write-NeoJsonFile $erPath (New-SlotEnd $slug $null -NoTests:$noTests)
  $proofP = Join-Path $slugDir 'proof.ps1'; Set-Content -LiteralPath $proofP -Value $proofExit -Encoding UTF8
  $endAudited = Join-Path $auditDir 'END_audited.json'
  Copy-Item -LiteralPath $erPath -Destination $endAudited -Force
  $members = @(
    @{ path = $endAudited; rel = "./NEO_SESSION/$slug/audit/END_audited.json"; role = 'end_report' },
    @{ path = $proofP;     rel = "./NEO_SESSION/$slug/proof.ps1";              role = 'proof' }
  )
  $bundlePath = Join-Path $auditDir 'AUDIT_BUNDLE.json'
  $bundle = New-NeoAuditBundle -BundleId ("b-" + $name) -MemberItems $members -ApprovedPaths @('./app/') `
    -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier 'high' -Timestamp $TS -Index $index -OutPath $bundlePath
  $arPath = Join-Path $auditDir 'AUDIT_RESULT.json'
  # the HONEST frozen deriving stub writes the verdict (derived from the world above).
  & $stub -BundlePath $bundlePath -BundleDir $root -OutPath $arPath -Timestamp $TS -AuditorIdentity $auditorId | Out-Null
  # confirm the stub DERIVED the target verdict (the fixture world is what forces it).
  $derived = [string](Read-NeoJsonFile $arPath).recommendation
  if ($derived -cne $Recommendation) { throw "New-SlotWorld($name): stub derived '$derived' but the fixture targeted '$Recommendation' - world shaping is wrong" }
  $bundleRel = "./NEO_SESSION/$slug/audit/AUDIT_BUNDLE.json"
  # fill the LIVE END's slot on disk OUTSIDE the engine, re-ingest via the engine reader.
  Write-NeoJsonFile $erPath (New-SlotEnd $slug (@{ recommendation = $Recommendation; auditor_identity = $auditorId; bundle_ref = $bundleRel }) -NoTests:$noTests)
  $endLive = Read-NeoEndReport $erPath $index
  if (-not $NoSpawnEntry) {
    [void](Add-NeoSpawnLedgerEntry -RunRoot $runRoot -SpawnId ("sp-" + $name) -AuditorIdentity $auditorId `
      -BundleRef $bundleRel -RoundId $RoundId -Timestamp $TS)
  }
  return @{ root = $root; endLive = $endLive; bundleRel = $bundleRel; auditorId = $auditorId; recommendation = $Recommendation }
}
function Invoke-Agg($ctx, $w, $row, [string]$effClass, [string]$laneStatus = 'NOT_WIRED', [string]$roundId = 'round-1') {
  return (Assert-NeoLoopAuditSatisfied -Context $ctx -RiskRow $row -EffectiveRiskClass $effClass `
    -EndReport $w.endLive -SessionRoot $w.root -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index `
    -RoundId $roundId -ExternalLaneStatus $laneStatus)
}

Write-Host "NEO 4.0-P4-AUTONOMY C1C3-S3a loop round-core + C1C3-S3b convergence wrapper suite" -ForegroundColor Cyan
Write-Host "scratch: $ScratchRoot"

# =============================================================================
# N-S3A-DISPATCH-NF1 : dispatch-time guards + the DENIED_PATHS contract
# =============================================================================
$runND = New-RunRoot
$repoND = New-AppRepo 'repo_nd'

$ndEmptyDir = New-NotifyDir 'nd_empty'
$stopNdEmpty = New-NeoLoopRoundDispatch -Context (New-Ctx $runND 'nd-empty' $ndEmptyDir) -RepoRoot $repoND `
  -ProposedEdits @() -ApprovedPaths $approved -ProtectedPaths $protected -Goal 'round goal' -RiskClass 'low' `
  -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) -TestPlan @('run suite') `
  -StopConditions @('ambiguity') -Timestamp $TS
Expect-StopResult 'N-S3A-DISPATCH-NF1-EMPTY' $stopNdEmpty 'EMPTY_PROPOSED_EDITS' 'ESCALATION_STOP' $runND $ndEmptyDir

$ndDenyDir = New-NotifyDir 'nd_deny'
$stopNdDeny = New-NeoLoopRoundDispatch -Context (New-Ctx $runND 'nd-deny' $ndDenyDir) -RepoRoot $repoND `
  -ProposedEdits @('.neo/scripts/orchestrator/orch_engine.ps1') -ApprovedPaths $approved -ProtectedPaths $protected `
  -Goal 'round goal' -RiskClass 'low' -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) `
  -TestPlan @('run suite') -StopConditions @('ambiguity') -Timestamp $TS
Expect-StopResult 'N-S3A-DISPATCH-NF1-NEO-DENY' $stopNdDeny 'DENIED_PATH' 'ESCALATION_STOP' $runND $ndDenyDir

$ndOkDir = New-NotifyDir 'nd_ok'
$dispOk = New-NeoLoopRoundDispatch -Context (New-Ctx $runND 'nd-ok' $ndOkDir) -RepoRoot $repoND `
  -ProposedEdits @('app/widget.txt') -ApprovedPaths $approved -ProtectedPaths $protected -Goal 'round goal' `
  -RiskClass 'low' -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) -TestPlan @('run suite') `
  -StopConditions @('ambiguity') -Timestamp $TS
Expect-Value 'P-S3A-DISPATCH-OK-NOT-STOPPED' 'False' { [bool]$dispOk.stopped }
Expect-Value 'P-S3A-DISPATCH-CARRIES-DENY'   'True'  { [bool](@($dispOk.denied_paths) -ccontains '.neo/**') }
Expect-Value 'P-S3A-DISPATCH-DENY-HAS-FLOOR' 'True'  { [bool](@($dispOk.denied_paths) -ccontains '.neo/scripts/orchestrator/orch_loop.ps1') }
Expect-Ok    'P-S3A-DISPATCH-PACKET-RECHECKS' {
  [void](Test-NeoBuilderPacketFirewall -Packet $dispOk.packet -RepoRoot $repoND)
  'assembled packet passes the frozen consume-side firewall re-check'
}
Expect-Block 'N-S3A-DENY-RECHECK-CONSUME' 'DENIED_PATH' {
  Assert-NeoLoopDeniedPaths -Rels @('.neo/schema/artifact_classes.json') -DeniedPaths @($dispOk.denied_paths) | Out-Null
}
Expect-Block 'N-S3A-DENY-EMPTY-CONTRACT' 'DENIED_PATH' {
  Assert-NeoLoopDeniedPaths -Rels @('app/widget.txt') -DeniedPaths @() | Out-Null
}
Expect-Value 'P-S3A-DISPATCH-NO-FALSE-NOTIFY' '0' { @(Get-EmlFiles $ndOkDir).Count }

# =============================================================================
# N-S3A-ROUND-CHAIN : per-round enforcement chain, one world per branch
# =============================================================================
$mirrorRC = New-GovMirror 'gov_rc'
$pinRC = Pin-GovMirror $mirrorRC 'pin_rc.json'

# (a) builder commit => BUILDER_COMMIT
$runRC1 = New-RunRoot; $repoRC1 = New-AppRepo 'repo_rc1'; $dirRC1 = New-NotifyDir 'rc1'
$blRC1 = Pin-NeoDispatchBaseline -RepoRoot $repoRC1
Set-Content -LiteralPath (Join-Path $repoRC1 'app\widget.txt') -Value 'edited widget' -Encoding Ascii
Invoke-GitQuiet $repoRC1 @('add', '-A'); Invoke-GitQuiet $repoRC1 @('commit', '-q', '-m', 'forbidden commit')
$stopRC1 = Invoke-Chain (New-Ctx $runRC1 'rc1-commit' $dirRC1) $repoRC1 $blRC1 $pinRC $mirrorRC
Expect-StopResult 'N-S3A-ROUND-CHAIN-BUILDER-COMMIT' $stopRC1 'BUILDER_COMMIT' 'ESCALATION_STOP' $runRC1 $dirRC1

# (b) three-branch: outside approved => OUTSIDE_APPROVED
$runRC2 = New-RunRoot; $repoRC2 = New-AppRepo 'repo_rc2'; $dirRC2 = New-NotifyDir 'rc2'
$blRC2 = Pin-NeoDispatchBaseline -RepoRoot $repoRC2
New-Item -ItemType Directory -Force -Path (Join-Path $repoRC2 'other') | Out-Null
Set-Content -LiteralPath (Join-Path $repoRC2 'other\loose.txt') -Value 'outside scope' -Encoding Ascii
$stopRC2 = Invoke-Chain (New-Ctx $runRC2 'rc2-outside' $dirRC2) $repoRC2 $blRC2 $pinRC $mirrorRC
Expect-StopResult 'N-S3A-ROUND-CHAIN-OUTSIDE' $stopRC2 'OUTSIDE_APPROVED' 'ESCALATION_STOP' $runRC2 $dirRC2

# (b2) three-branch: judging-named file inside approved => JUDGING_OR_PROTECTED
$runRC3 = New-RunRoot; $repoRC3 = New-AppRepo 'repo_rc3'; $dirRC3 = New-NotifyDir 'rc3'
$blRC3 = Pin-NeoDispatchBaseline -RepoRoot $repoRC3
Set-Content -LiteralPath (Join-Path $repoRC3 'app\evil.schema.json') -Value '{"a":1}' -Encoding Ascii
$stopRC3 = Invoke-Chain (New-Ctx $runRC3 'rc3-judging' $dirRC3) $repoRC3 $blRC3 $pinRC $mirrorRC
Expect-StopResult 'N-S3A-ROUND-CHAIN-JUDGING' $stopRC3 'JUDGING_OR_PROTECTED' 'ESCALATION_STOP' $runRC3 $dirRC3

# (c) governance-manifest tamper => GOVERNANCE_MANIFEST_MISMATCH, and ORDERING:
# a GO-looking slot world exists, yet the wrapper-shaped sequence stops at the
# tamper BEFORE aggregation is ever invoked (enforcement before aggregation).
$runRC4 = New-RunRoot; $repoRC4 = New-AppRepo 'repo_rc4'; $dirRC4 = New-NotifyDir 'rc4'
$mirrorRC4 = New-GovMirror 'gov_rc4'
$pinRC4 = Pin-GovMirror $mirrorRC4 'pin_rc4.json'
Set-Content -LiteralPath (Join-Path $mirrorRC4 '.neo\scripts\orchestrator\orch_engine.ps1') -Value '# tampered engine stub' -Encoding Ascii
$blRC4 = Pin-NeoDispatchBaseline -RepoRoot $repoRC4
Set-Content -LiteralPath (Join-Path $repoRC4 'app\widget.txt') -Value 'legit edit' -Encoding Ascii
$wRC4 = New-SlotWorld 'slot_rc4' $runRC4
$ctxRC4 = New-Ctx $runRC4 'rc4-tamper' $dirRC4
$stopRC4 = Invoke-Chain $ctxRC4 $repoRC4 $blRC4 $pinRC4 $mirrorRC4
$aggRC4 = $null
if (-not $stopRC4.stopped) { $aggRC4 = Invoke-Agg $ctxRC4 $wRC4 $rowLow 'low' }   # wrapper shape: aggregation ONLY after clean checks
Expect-StopResult 'N-S3A-ROUND-CHAIN-GOV-TAMPER' $stopRC4 'GOVERNANCE_MANIFEST_MISMATCH' 'ESCALATION_STOP' $runRC4 $dirRC4
Expect-Value 'N-S3A-ROUND-CHAIN-ORDERING' 'True' {
  # the tamper STOP won: aggregation was never reached even with a GO-looking slot ready
  [bool]($stopRC4.stopped -and ($null -eq $aggRC4))
}

# (d) risk escalation on the actual diff => RISK_ESCALATION (wrapper-assigned code;
# the router's escalation refusal is a prose NEO-BLOCK anchored on the stable
# substring 'EXCEEDS frozen row risk' - grounded orch_router.ps1:368)
$runRC5 = New-RunRoot; $repoRC5 = New-AppRepo 'repo_rc5'; $dirRC5 = New-NotifyDir 'rc5'
$blRC5 = Pin-NeoDispatchBaseline -RepoRoot $repoRC5
Set-Content -LiteralPath (Join-Path $repoRC5 'app\widget.txt') -Value 'this change touches payment code' -Encoding Ascii
$stopRC5 = Invoke-Chain (New-Ctx $runRC5 'rc5-escalate' $dirRC5) $repoRC5 $blRC5 $pinRC $mirrorRC
Expect-StopResult 'N-S3A-ROUND-CHAIN-RISK-ESCALATION' $stopRC5 'RISK_ESCALATION' 'ESCALATION_STOP' $runRC5 $dirRC5

# (e) empty actual changed set => EMPTY_CHANGED_SET (fail-closed; disclosed S3a code)
$runRC6 = New-RunRoot; $repoRC6 = New-AppRepo 'repo_rc6'; $dirRC6 = New-NotifyDir 'rc6'
$blRC6 = Pin-NeoDispatchBaseline -RepoRoot $repoRC6
$stopRC6 = Invoke-Chain (New-Ctx $runRC6 'rc6-empty' $dirRC6) $repoRC6 $blRC6 $pinRC $mirrorRC
Expect-StopResult 'N-S3A-ROUND-CHAIN-EMPTY-DIFF' $stopRC6 'EMPTY_CHANGED_SET' 'ESCALATION_STOP' $runRC6 $dirRC6

# =============================================================================
# N-S3A-C1C-JUDGING-FIX-INLOOP : a judging-class fix target in-loop => STOP
# =============================================================================
$runC1 = New-RunRoot; $repoC1 = New-AppRepo 'repo_c1c'; $dirC1 = New-NotifyDir 'c1c'
$blC1 = Pin-NeoDispatchBaseline -RepoRoot $repoC1
Set-Content -LiteralPath (Join-Path $repoC1 'app\widget.txt') -Value 'legit edit two' -Encoding Ascii
$stopC1 = Invoke-Chain (New-Ctx $runC1 'c1c-fix' $dirC1) $repoC1 $blC1 $pinRC $mirrorRC @('.neo/scripts/orchestrator/orch_engine.ps1')
Expect-StopResult 'N-S3A-C1C-JUDGING-FIX-INLOOP' $stopC1 'C1C_JUDGING_FIX_REQUIRED' 'ESCALATION_STOP' $runC1 $dirC1

# =============================================================================
# N-S3A-SPAWN-UNCORRELATED-INLOOP : GO-looking slot, NO correlated spawn entry
# =============================================================================
$runSP = New-RunRoot; $dirSP = New-NotifyDir 'spawn'
$wSP = New-SlotWorld 'slot_uncorr' $runSP -NoSpawnEntry
# a DIFFERENT spawn entry exists (other bundle/round) so the ledger itself is present
[void](Add-NeoSpawnLedgerEntry -RunRoot $runSP -SpawnId 'sp-other' -AuditorIdentity 'someone-else' `
  -BundleRef './NEO_SESSION/other/AUDIT_BUNDLE.json' -RoundId 'round-0' -Timestamp $TS)
$stopSP = Invoke-Agg (New-Ctx $runSP 'spawn-uncorr' $dirSP) $wSP $rowLow 'low'
Expect-StopResult 'N-S3A-SPAWN-UNCORRELATED-INLOOP' $stopSP 'SPAWN_UNCORRELATED' 'ESCALATION_STOP' $runSP $dirSP

# =============================================================================
# N-S3A-HIGH-WITHOUT-C4 : HIGH cannot GO while the external lane is NOT wired;
# LOW/MED controls with the SAME slot inputs => GO.
# =============================================================================
$runHI = New-RunRoot; $dirHI = New-NotifyDir 'high'
$wHI = New-SlotWorld 'slot_high' $runHI
$stopHI = Invoke-Agg (New-Ctx $runHI 'high-noc4' $dirHI) $wHI $rowHigh 'high'
Expect-StopResult 'N-S3A-HIGH-WITHOUT-C4' $stopHI 'EXTERNAL_REQUIRED_UNAVAILABLE' 'ESCALATION_STOP' $runHI $dirHI

$runLO = New-RunRoot; $dirLO = New-NotifyDir 'low_ctl'
$wLO = New-SlotWorld 'slot_low' $runLO
Expect-Value 'P-S3A-LOW-CONTROL-GO' 'True' {
  $agg = Invoke-Agg (New-Ctx $runLO 'low-ctl' $dirLO) $wLO $rowLow 'low'
  [bool]((-not $agg.stopped) -and $agg.go -and ($agg.effective_seam_tier -ceq 'isolated'))
}
Expect-Value 'P-S3A-LOW-CONTROL-NO-NOTIFY' '0' { @(Get-EmlFiles $dirLO).Count }
$runME = New-RunRoot; $dirME = New-NotifyDir 'med_ctl'
$wME = New-SlotWorld 'slot_med' $runME
Expect-Value 'P-S3A-MED-CONTROL-GO' 'True' {
  $agg = Invoke-Agg (New-Ctx $runME 'med-ctl' $dirME) $wME $rowMed 'medium'
  [bool]((-not $agg.stopped) -and $agg.go)
}
# the lane cannot report GO while unwired => EXTERNAL_LANE_INVALID (fail-closed seam)
$runGL = New-RunRoot; $dirGL = New-NotifyDir 'lane_go'
$wGL = New-SlotWorld 'slot_lanego' $runGL
$stopGL = Invoke-Agg (New-Ctx $runGL 'lane-go' $dirGL) $wGL $rowHigh 'high' 'GO'
Expect-StopResult 'N-S3A-LANE-GO-REFUSED' $stopGL 'EXTERNAL_LANE_INVALID' 'ESCALATION_STOP' $runGL $dirGL
# unrecognized lane vocabulary => EXTERNAL_LANE_INVALID
$runGB = New-RunRoot; $dirGB = New-NotifyDir 'lane_bad'
$wGB = New-SlotWorld 'slot_lanebad' $runGB
$stopGB = Invoke-Agg (New-Ctx $runGB 'lane-bad' $dirGB) $wGB $rowLow 'low' 'WAT'
Expect-StopResult 'N-S3A-LANE-UNRECOGNIZED' $stopGB 'EXTERNAL_LANE_INVALID' 'ESCALATION_STOP' $runGB $dirGB

# =============================================================================
# S3a-FIX FINDINGS : load-bearing negatives (each FLIPS on a pre-fix neuter)
# =============================================================================

# ---- N-S3AFIX-NONGO-NOT-GO (F1) : a valid, spawn-correlated NON-GO auditor slot on
# a LOW class => go=$false (NOT go=$true), stopped=$false, recommendation carried; a
# GO slot still => go=$true (control). This is the NORMAL ITERATE signal (spec C1),
# NOT a STOP: no notify, no manifest row from the aggregation (the caller records the
# row, identical contract to a clean-GO round). NEUTER (pre-fix): the GO aggregate
# never checked slot.recommendation, so a NEEDS-MORE/NO-GO slot returned go=$true.
$runNM = New-RunRoot; $dirNM = New-NotifyDir 'nongo_nm'
$wNM = New-SlotWorld 'slot_needsmore' $runNM -Recommendation 'NEEDS-MORE'
$aggNM = Invoke-Agg (New-Ctx $runNM 'nongo-nm' $dirNM) $wNM $rowLow 'low'
Expect-Value 'N-S3AFIX-NONGO-NOT-GO-NEEDSMORE' 'True' {
  [bool]((-not $aggNM.stopped) -and (-not $aggNM.go) -and ([string]$aggNM.recommendation -ceq 'NEEDS-MORE'))
}
Expect-Value 'N-S3AFIX-NONGO-NOT-GO-NM-NO-NOTIFY' '0' { @(Get-EmlFiles $dirNM).Count }
$runNG = New-RunRoot; $dirNG = New-NotifyDir 'nongo_ng'
$wNG = New-SlotWorld 'slot_nogo' $runNG -Recommendation 'NO-GO'
$aggNG = Invoke-Agg (New-Ctx $runNG 'nongo-ng' $dirNG) $wNG $rowLow 'low'
Expect-Value 'N-S3AFIX-NONGO-NOT-GO-NOGO' 'True' {
  [bool]((-not $aggNG.stopped) -and (-not $aggNG.go) -and ([string]$aggNG.recommendation -ceq 'NO-GO'))
}
# control: a GO slot on the same LOW class still aggregates go=$true (recommendation gate
# admits GO). (Already proven by P-S3A-LOW-CONTROL-GO; restated here as the F1 control.)
$runGC = New-RunRoot; $dirGC = New-NotifyDir 'nongo_goctl'
$wGC = New-SlotWorld 'slot_go_ctl' $runGC -Recommendation 'GO'
$aggGC = Invoke-Agg (New-Ctx $runGC 'nongo-goctl' $dirGC) $wGC $rowLow 'low'
Expect-Value 'N-S3AFIX-NONGO-CONTROL-GO' 'True' {
  [bool]((-not $aggGC.stopped) -and $aggGC.go -and ($null -eq $aggGC.recommendation))
}

# ---- N-S3AFIX-HIGH-ROW-NODOWNGRADE (F2) : a HIGH frozen RiskRow with a caller
# EffectiveRiskClass 'low' => the escalate-only clamp lifts effective to 'high' => the
# C4 external-required gate FIRES (EXTERNAL_REQUIRED_UNAVAILABLE in S3a) => NOT go.
# NEUTER (pre-fix): the C4 gate tested only $EffectiveRiskClass, so high row + 'low'
# caller skipped the gate and aggregated GO with no external.
$runHD = New-RunRoot; $dirHD = New-NotifyDir 'high_nodown'
$wHD = New-SlotWorld 'slot_high_down' $runHD -Recommendation 'GO'
$stopHD = Invoke-Agg (New-Ctx $runHD 'high-nodown' $dirHD) $wHD $rowHigh 'low'   # row HIGH, caller LOW (inversion)
Expect-StopResult 'N-S3AFIX-HIGH-ROW-NODOWNGRADE' $stopHD 'EXTERNAL_REQUIRED_UNAVAILABLE' 'ESCALATION_STOP' $runHD $dirHD
# the STOP row records the CLAMPED-UP disclosure in findings_summary (NB-1 effective tier)
Expect-Value 'N-S3AFIX-HIGH-ROW-CLAMP-DISCLOSED' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runHD
  $last = $rows[$rows.Count - 1]
  [bool]([string](Get-NeoProp $last 'findings_summary') -like '*CLAMPED UP*')
}
# control: row low + caller low + GO => go (no clamp, no gate).
$runLD = New-RunRoot; $dirLD = New-NotifyDir 'low_nodown'
$wLD = New-SlotWorld 'slot_low_down' $runLD -Recommendation 'GO'
Expect-Value 'N-S3AFIX-HIGH-ROW-CONTROL-LOW-GO' 'True' {
  $agg = Invoke-Agg (New-Ctx $runLD 'low-nodown' $dirLD) $wLD $rowLow 'low'
  [bool]((-not $agg.stopped) -and $agg.go)
}

# ---- N-S3AFIX-STOP-ROUTES-CHOKE (F4) : a RUNTIME-REACHABLE guard reclassified in F4
# (here: a blank RoundId, and an unknown-casing EffectiveRiskClass) => a routed STOP
# (composed TestModeDir notification + write-ahead manifest row), CLASSIFIER_ERROR /
# ESCALATION_STOP - NOT a bare throw. NEUTER (pre-fix): a bare New-NeoBlock threw with
# no eml + no row. $ctx is validated FIRST so the choke point can run for these.
$runCK = New-RunRoot; $dirCK = New-NotifyDir 'choke_roundid'
$wCK = New-SlotWorld 'slot_choke' $runCK -Recommendation 'GO'
$stopCK = Assert-NeoLoopAuditSatisfied -Context (New-Ctx $runCK 'choke-roundid' $dirCK) -RiskRow $rowLow `
  -EffectiveRiskClass 'low' -EndReport $wCK.endLive -SessionRoot $wCK.root -MasterIdentity 'm1' `
  -BuilderIdentity 'b1' -Index $index -RoundId '   '   # blank RoundId (runtime-reachable)
Expect-StopResult 'N-S3AFIX-STOP-ROUTES-CHOKE-ROUNDID' $stopCK 'CLASSIFIER_ERROR' 'ESCALATION_STOP' $runCK $dirCK
$runCK2 = New-RunRoot; $dirCK2 = New-NotifyDir 'choke_effclass'
$wCK2 = New-SlotWorld 'slot_choke2' $runCK2 -Recommendation 'GO'
$stopCK2 = Assert-NeoLoopAuditSatisfied -Context (New-Ctx $runCK2 'choke-eff' $dirCK2) -RiskRow $rowLow `
  -EffectiveRiskClass 'LOW' -EndReport $wCK2.endLive -SessionRoot $wCK2.root -MasterIdentity 'm1' `
  -BuilderIdentity 'b1' -Index $index -RoundId 'round-1'   # unknown casing (runtime-reachable)
Expect-StopResult 'N-S3AFIX-STOP-ROUTES-CHOKE-EFFCLASS' $stopCK2 'CLASSIFIER_ERROR' 'ESCALATION_STOP' $runCK2 $dirCK2
# a runtime guard in Invoke-NeoLoopRoundChecks (bad RepoRoot) also routes through the choke.
$runCK3 = New-RunRoot; $dirCK3 = New-NotifyDir 'choke_repo'
$blCK3 = $null
$repoCK3 = New-AppRepo 'repo_ck3'; $blCK3 = Pin-NeoDispatchBaseline -RepoRoot $repoCK3
$stopCK3 = Invoke-NeoLoopRoundChecks -Context (New-Ctx $runCK3 'choke-repo' $dirCK3) `
  -RepoRoot (Join-Path $ScratchRoot 'no_such_repo_dir') -Baseline $blCK3 -ApprovedPaths $approved `
  -ProtectedPaths $protected -PinnedGovManifestPath $pinRC -GovernedRoot $mirrorRC -DerivedAt $TS `
  -RouterProfile $routerProfile -RiskRow $rowLow
Expect-StopResult 'N-S3AFIX-STOP-ROUTES-CHOKE-REPOROOT' $stopCK3 'CLASSIFIER_ERROR' 'ESCALATION_STOP' $runCK3 $dirCK3

# ---- N-S3AFIX-DENY-UNION (F3) : a caller DeniedPaths EXTENDS, never REPLACES, the
# mandatory floor. -DeniedPaths @('docs/**') with a '.neo/**' proposed edit => STOP
# DENIED_PATH (the .neo/** floor SURVIVES the caller list); control: a clean 'app/'
# edit WITH the same @('docs/**') caller deny => passes (union is additive, not a
# wholesale block). NEUTER (pre-fix): $deny = @($DeniedPaths) => the caller list
# REPLACED the floor => the .neo/** edit passed.
$runDU = New-RunRoot; $repoDU = New-AppRepo 'repo_du'
$duFloorDir = New-NotifyDir 'du_floor'
$stopDU = New-NeoLoopRoundDispatch -Context (New-Ctx $runDU 'du-floor' $duFloorDir) -RepoRoot $repoDU `
  -ProposedEdits @('.neo/scripts/orchestrator/orch_engine.ps1') -ApprovedPaths $approved -ProtectedPaths $protected `
  -Goal 'round goal' -RiskClass 'low' -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) `
  -TestPlan @('run suite') -StopConditions @('ambiguity') -Timestamp $TS -DeniedPaths @('docs/**')
Expect-StopResult 'N-S3AFIX-DENY-UNION-FLOOR-SURVIVES' $stopDU 'DENIED_PATH' 'ESCALATION_STOP' $runDU $duFloorDir
# the assembled deny set carries BOTH the floor AND the caller extension
$duOkDir = New-NotifyDir 'du_ok'
$dispDU = New-NeoLoopRoundDispatch -Context (New-Ctx $runDU 'du-ok' $duOkDir) -RepoRoot $repoDU `
  -ProposedEdits @('app/widget.txt') -ApprovedPaths $approved -ProtectedPaths $protected -Goal 'round goal' `
  -RiskClass 'low' -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) -TestPlan @('run suite') `
  -StopConditions @('ambiguity') -Timestamp $TS -DeniedPaths @('docs/**')
Expect-Value 'N-S3AFIX-DENY-UNION-CONTROL-CLEAN' 'True' { [bool]((-not $dispDU.stopped) -and (@($dispDU.denied_paths) -ccontains 'docs/**') -and (@($dispDU.denied_paths) -ccontains '.neo/**') -and (@($dispDU.denied_paths) -ccontains '.neo/scripts/orchestrator/orch_loop.ps1')) }
# a caller edit landing on the caller EXTENSION (docs/**) also stops (union works both ways)
$duExtDir = New-NotifyDir 'du_ext'
$stopDUext = New-NeoLoopRoundDispatch -Context (New-Ctx $runDU 'du-ext' $duExtDir) -RepoRoot $repoDU `
  -ProposedEdits @('docs/readme.md') -ApprovedPaths $approved -ProtectedPaths $protected -Goal 'round goal' `
  -RiskClass 'low' -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) -TestPlan @('run suite') `
  -StopConditions @('ambiguity') -Timestamp $TS -DeniedPaths @('docs/**')
Expect-StopResult 'N-S3AFIX-DENY-UNION-EXTENSION-STOPS' $stopDUext 'DENIED_PATH' 'ESCALATION_STOP' $runDU $duExtDir

# ---- N-S3AFIX-PASSTHROUGH (F5) : a caller cannot mislabel a breaker as a human-END
# class (SESSION_END/DECISION_NEEDED) through the STOP path. Without -HumanEndClass
# those codes fail-closed to ESCALATION_STOP; WITH the internal switch (the S3c
# human-END entry) they pass through as themselves. NEUTER (pre-fix): the pass-through
# lookup fired for ANY caller => a breaker mislabeled SESSION_END passed through.
$dirF5 = New-NotifyDir 'f5_passthrough'
Expect-Value 'N-S3AFIX-PASSTHROUGH-STOP-PATH-FAILCLOSED' 'True' {
  $a = Invoke-NeoLoopStopNotify -ReasonCode 'SESSION_END' -SliceId ("s3a-" + $tag + "-f5-se") -Round 1 `
    -Detail 'mislabeled breaker as session end' -EvidencePath $evidencePath -TestModeDir $dirF5
  $b = Invoke-NeoLoopStopNotify -ReasonCode 'DECISION_NEEDED' -SliceId ("s3a-" + $tag + "-f5-dn") -Round 1 `
    -Detail 'mislabeled breaker as decision needed' -EvidencePath $evidencePath -TestModeDir $dirF5
  # both fail-closed to ESCALATION_STOP (NOT their own class), mapped=$false, still sent
  [bool](($a.gate_class -ceq 'ESCALATION_STOP') -and (-not $a.mapped) -and $a.status.sent `
    -and ($b.gate_class -ceq 'ESCALATION_STOP') -and (-not $b.mapped) -and $b.status.sent)
}
$dirF5b = New-NotifyDir 'f5_human_end'
Expect-Value 'N-S3AFIX-PASSTHROUGH-HUMAN-END-DISTINCT' 'True' {
  # the DISTINCT internal path (-HumanEndClass) is the ONLY way the human-END classes
  # pass through as themselves.
  $a = Invoke-NeoLoopStopNotify -ReasonCode 'SESSION_END' -SliceId ("s3a-" + $tag + "-f5b-se") -Round 0 `
    -Detail 'genuine human session end' -EvidencePath $evidencePath -TestModeDir $dirF5b -HumanEndClass
  $b = Invoke-NeoLoopStopNotify -ReasonCode 'DECISION_NEEDED' -SliceId ("s3a-" + $tag + "-f5b-dn") -Round 0 `
    -Detail 'genuine human decision needed' -EvidencePath $evidencePath -TestModeDir $dirF5b -HumanEndClass
  [bool](($a.gate_class -ceq 'SESSION_END') -and $a.mapped -and ($b.gate_class -ceq 'DECISION_NEEDED') -and $b.mapped)
}

# =============================================================================
# N-S3A-NOTIFY-FIRES : gate-class map spot checks + UNKNOWN still composes
# (each STOP case above already proved exactly-one-compose per class)
# =============================================================================
$dirNF1 = New-NotifyDir 'nf_unknown'
Expect-Value 'N-S3A-NOTIFY-UNKNOWN-STILL-FIRES' 'True' {
  $r = Invoke-NeoLoopStopNotify -ReasonCode 'NEVER_SEEN_CODE_ZZZ' -SliceId ("s3a-" + $tag + "-nf-unknown") -Round 1 `
    -Detail 'unmapped code test' -EvidencePath $evidencePath -TestModeDir $dirNF1
  [bool](($r.gate_class -ceq 'ESCALATION_STOP') -and (-not $r.mapped) -and $r.status.sent -and (@(Get-EmlFiles $dirNF1).Count -eq 1))
}
$dirNF2 = New-NotifyDir 'nf_breaker'
Expect-Value 'N-S3A-NOTIFY-BREAKER-CLASS' 'True' {
  $r = Invoke-NeoLoopStopNotify -ReasonCode 'LEDGER_FAILURE' -SliceId ("s3a-" + $tag + "-nf-breaker") -Round 2 `
    -Detail 'ledger failure test' -EvidencePath $evidencePath -TestModeDir $dirNF2
  [bool](($r.gate_class -ceq 'BREAKER_TRIP') -and $r.mapped -and $r.status.sent)
}
$dirNF3 = New-NotifyDir 'nf_pass'
# S3a-FIX CORRECTED-EXPECTATION (F5): pass-through of the human-END classes is now
# reachable ONLY via the distinct internal -HumanEndClass switch (the S3c human-END
# entry). This fixture is updated to pass -HumanEndClass so it still proves the
# pass-through mapping - NOT a silent weakening: the previously-untested public-STOP-
# path misuse (SESSION_END/DECISION_NEEDED WITHOUT the switch => fail-closed to
# ESCALATION_STOP) is now covered by N-S3AFIX-PASSTHROUGH-STOP-PATH-FAILCLOSED above.
Expect-Value 'N-S3A-NOTIFY-PASSTHROUGH-CLASSES' 'True' {
  $a = Invoke-NeoLoopStopNotify -ReasonCode 'DECISION_NEEDED' -SliceId ("s3a-" + $tag + "-nf-dn") -Round 0 `
    -Detail 'decision needed test' -EvidencePath $evidencePath -TestModeDir $dirNF3 -HumanEndClass
  $b = Invoke-NeoLoopStopNotify -ReasonCode 'SESSION_END' -SliceId ("s3a-" + $tag + "-nf-se") -Round 0 `
    -Detail 'session end test' -EvidencePath $evidencePath -TestModeDir $dirNF3 -HumanEndClass
  [bool](($a.gate_class -ceq 'DECISION_NEEDED') -and ($b.gate_class -ceq 'SESSION_END') -and $a.status.sent -and $b.status.sent)
}

# =============================================================================
# N-S3A-NOTIFY-NEVER-AUTHORITY : notify seam forced to fail => STOP unchanged
# (TestModeDir path occupied by a FILE => the compose write fails)
# =============================================================================
$runNA = New-RunRoot
$badDir = Join-Path $ScratchRoot 'notify_na_blocked'
Set-Content -LiteralPath $badDir -Value 'a file where the dir should be' -Encoding Ascii
$repoNA = New-AppRepo 'repo_na'
$stopNA = New-NeoLoopRoundDispatch -Context (New-Ctx $runNA 'na-fail' $badDir) -RepoRoot $repoNA `
  -ProposedEdits @() -ApprovedPaths $approved -ProtectedPaths $protected -Goal 'round goal' -RiskClass 'low' `
  -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) -TestPlan @('run suite') `
  -StopConditions @('ambiguity') -Timestamp $TS
Expect-Value 'N-S3A-NOTIFY-NEVER-AUTHORITY' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runNA
  $last = $rows[$rows.Count - 1]
  [bool]($stopNA.stopped -and ($stopNA.reason_code -ceq 'EMPTY_PROPOSED_EDITS') `
    -and (-not [bool]$stopNA.notify.sent) `
    -and ([string](Get-NeoProp $last 'stop_reason_code') -ceq 'EMPTY_PROPOSED_EDITS') `
    -and (-not [bool](Get-NeoProp $last 'notify_sent')) `
    -and ([string](Get-NeoProp $last 'notify_reason')).Length -gt 0)
}

# =============================================================================
# N-S3A-MANIFEST-APPEND-ONLY : append semantics + fail-closed read + write-ahead
# =============================================================================
$runMF = New-RunRoot
function New-RowFields([string]$slice, [int]$round, [string]$stopCode = 'NONE') {
  return @{
    slice_id = $slice; round = $round; attempt_seq = ($round + 1)
    baseline_head_sha = ('a' * 40); baseline_tree_hash = ('b' * 64)
    changed_count = 1; changed_paths_hash = ('c' * 64)
    classification = 'THREE_BRANCH_CLEAN'; findings_summary = 'NONE'
    auditor_slot_status = 'SATISFIED'; auditor_slot_recommendation = 'GO'
    auditor_identity = 'isolated-auditor-cold'; external_lane_status = 'NOT_WIRED'
    effective_seam_tier = 'isolated'; cap_events = @()
    stop_reason_code = $stopCode; notify_gate_class = 'NONE'
    notify_sent = $false; notify_deduped = $false; notify_refused = $false
    notify_reason = ''; timestamp_utc = $TS
  }
}
$mfSlice = "s3a-" + $tag + "-mf"
[void](Add-NeoIterationManifestEntry -RunRoot $runMF -Fields (New-RowFields $mfSlice 0))
$mfPath = Resolve-NeoRunStatePath $runMF 'iteration_manifest.jsonl'
$mfFirstLine = @([System.IO.File]::ReadAllLines($mfPath))[0]
[void](Add-NeoIterationManifestEntry -RunRoot $runMF -Fields (New-RowFields $mfSlice 1))
Expect-Value 'N-S3A-MANIFEST-APPEND-ONLY' 'True' {
  $lines = @([System.IO.File]::ReadAllLines($mfPath))
  # a second round APPENDS: line 1 is byte-identical, line count grew to exactly 2
  [bool](($lines.Count -eq 2) -and ($lines[0] -ceq $mfFirstLine))
}
Expect-Value 'P-S3A-MANIFEST-READ-ROUNDTRIP' '2' { $r = Read-NeoIterationManifest -RunRoot $runMF -SliceId $mfSlice; $r.Count }
Expect-Block 'N-S3A-MANIFEST-STRAY-FIELD' 'LEDGER_FAILURE' {
  $f = New-RowFields $mfSlice 2; $f['smuggled'] = 'x'
  Add-NeoIterationManifestEntry -RunRoot $runMF -Fields $f | Out-Null
}
Expect-Block 'N-S3A-MANIFEST-MISSING-FIELD' 'LEDGER_FAILURE' {
  $f = New-RowFields $mfSlice 2; $f.Remove('stop_reason_code')
  Add-NeoIterationManifestEntry -RunRoot $runMF -Fields $f | Out-Null
}
Expect-Block 'N-S3A-MANIFEST-FOREIGN-RUNID' 'LEDGER_FAILURE' {
  # caller can never bind a row to a foreign run: run_id is engine-stamped, and a
  # hand-planted foreign-run line is refused by the fail-closed reader.
  $f = New-RowFields $mfSlice 2
  $fake = [ordered]@{}; $fake['schema_id'] = 'neo:iteration_manifest_entry'; $fake['run_id'] = 'neo-run-forged'
  foreach ($k in @('slice_id','round','attempt_seq','baseline_head_sha','baseline_tree_hash','changed_count','changed_paths_hash','classification','findings_summary','auditor_slot_status','auditor_slot_recommendation','auditor_identity','external_lane_status','effective_seam_tier','cap_events','stop_reason_code','notify_gate_class','notify_sent','notify_deduped','notify_refused','notify_reason','timestamp_utc')) { $fake[$k] = $f[$k] }
  [System.IO.File]::AppendAllText($mfPath, ((Get-NeoCanonicalJson ([pscustomobject]$fake)) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
  Read-NeoIterationManifest -RunRoot $runMF | Out-Null
}
# rebuild a clean manifest world for the corrupt-line case (prior case dirtied it)
$runMF2 = New-RunRoot
[void](Add-NeoIterationManifestEntry -RunRoot $runMF2 -Fields (New-RowFields ($mfSlice + '-b') 0))
$mfPath2 = Resolve-NeoRunStatePath $runMF2 'iteration_manifest.jsonl'
[System.IO.File]::AppendAllText($mfPath2, "{not json`n", (New-Object System.Text.UTF8Encoding($false)))
Expect-Block 'N-S3A-MANIFEST-CORRUPT-LINE' 'LEDGER_FAILURE' {
  Read-NeoIterationManifest -RunRoot $runMF2 | Out-Null
}
Expect-Value 'P-S3A-STOPPED-ROUND-HAS-ROW' 'True' {
  # write-ahead shape re-proven from the RC1 world: the STOPPED round's row is ON
  # DISK and carries both the stop code and the notify outcome.
  $rows = Read-NeoIterationManifest -RunRoot $runRC1
  $last = $rows[$rows.Count - 1]
  [bool](($rows.Count -eq 1) -and ([string](Get-NeoProp $last 'stop_reason_code') -ceq 'BUILDER_COMMIT') `
    -and ([string](Get-NeoProp $last 'notify_gate_class') -ceq 'ESCALATION_STOP') -and [bool](Get-NeoProp $last 'notify_sent'))
}

# =============================================================================
# P-S3A-CLEAN-ROUND : a clean LOW round end-to-end => one row, no notify
# =============================================================================
$runOK = New-RunRoot; $repoOK = New-AppRepo 'repo_ok'; $dirOK = New-NotifyDir 'clean'
$ctxOK = New-Ctx $runOK 'clean-round' $dirOK
$dispOK2 = New-NeoLoopRoundDispatch -Context $ctxOK -RepoRoot $repoOK -ProposedEdits @('app/widget.txt') `
  -ApprovedPaths $approved -ProtectedPaths $protected -Goal 'clean round goal' -RiskClass 'low' `
  -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) -TestPlan @('run suite') `
  -StopConditions @('ambiguity') -Timestamp $TS
$blOK = Pin-NeoDispatchBaseline -RepoRoot $repoOK
Set-Content -LiteralPath (Join-Path $repoOK 'app\widget.txt') -Value 'updated widget text' -Encoding Ascii
$chkOK = Invoke-Chain $ctxOK $repoOK $blOK $pinRC $mirrorRC
$wOK = New-SlotWorld 'slot_clean' $runOK
$aggOK = $null
if (-not $chkOK.stopped) { $aggOK = Invoke-Agg $ctxOK $wOK $rowLow ([string]$chkOK.rederive.effective_class) }
Expect-Value 'P-S3A-CLEAN-ROUND' 'True' {
  [bool]((-not $dispOK2.stopped) -and (-not $chkOK.stopped) -and ($null -ne $aggOK) -and $aggOK.go)
}
# the CALLER records the clean round's single row (one-row-per-round contract)
[void](Add-NeoIterationManifestEntry -RunRoot $runOK -Fields (@{
  slice_id = $ctxOK.slice_id; round = 1; attempt_seq = 1
  baseline_head_sha = [string]$chkOK.baseline_head_sha; baseline_tree_hash = [string]$chkOK.baseline_tree_hash
  changed_count = [int]$chkOK.changed_count; changed_paths_hash = [string]$chkOK.changed_paths_hash
  classification = 'THREE_BRANCH_CLEAN'; findings_summary = 'NONE'
  auditor_slot_status = 'SATISFIED'; auditor_slot_recommendation = [string]$aggOK.slot.recommendation
  auditor_identity = [string]$aggOK.slot.auditor_identity; external_lane_status = [string]$aggOK.external_lane_status
  effective_seam_tier = [string]$aggOK.effective_seam_tier; cap_events = @()
  stop_reason_code = 'NONE'; notify_gate_class = 'NONE'
  notify_sent = $false; notify_deduped = $false; notify_refused = $false
  notify_reason = ''; timestamp_utc = $TS
}))
Expect-Value 'P-S3A-CLEAN-ROUND-ONE-ROW'   '1' { $r = Read-NeoIterationManifest -RunRoot $runOK; $r.Count }
Expect-Value 'P-S3A-CLEAN-ROUND-NO-NOTIFY' '0' { @(Get-EmlFiles $dirOK).Count }
Expect-Value 'P-S3A-CLEAN-ROUND-ROW-SHAPE' 'True' {
  $row = (Read-NeoIterationManifest -RunRoot $runOK)[0]
  [bool](([string](Get-NeoProp $row 'stop_reason_code') -ceq 'NONE') `
    -and ([string](Get-NeoProp $row 'effective_seam_tier') -ceq 'isolated') `
    -and ([string](Get-NeoProp $row 'external_lane_status') -ceq 'NOT_WIRED') `
    -and ([int](Get-NeoProp $row 'changed_count') -eq 1))
}

# =============================================================================
# P-S3A-FLOOR-24 : the 24-rel mandatory floor against the REAL governed tree
# + AS18 judging-from-birth probes for the new files
# =============================================================================
$realRoot = Get-NeoGovernedRoot
$realManifest = $null
# (C4: the floor is 25 rels since orch_external.ps1 joined it - name updated 24->25,
# same coverage; disclosed in the C4 END packet.)
Expect-Ok 'P-S3A-FLOOR-25' {
  $script:realManifest = Build-NeoGovManifest -GovernedRoot $realRoot -DerivedAt $TS
  [void](Assert-NeoGovManifestMandatoryMembers -Manifest $script:realManifest -GovernedRoot $realRoot)
  'the 25-rel floor (incl. orch_loop.ps1 + orch_external.ps1) passes V1 against the real governed tree'
}
Expect-Value 'P-S3A-FLOOR-LOOP-MEMBER' 'True' {
  $hit = @($script:realManifest.members | Where-Object { $_.rel -ceq '.neo/scripts/orchestrator/orch_loop.ps1' })
  [bool](($hit.Count -eq 1) -and ($hit[0].class -ceq 'test_harness'))
}
$probeMap = Get-NeoClassMap (Resolve-NeoGovernanceMapPath)
Expect-Value 'P-S3A-AS18-MODULE-JUDGING'  'test_harness'   { Resolve-NeoArtifactClass $probeMap '.neo/scripts/orchestrator/orch_loop.ps1' }
Expect-Value 'P-S3A-AS18-SUITE-JUDGING'   'test_harness'   { Resolve-NeoArtifactClass $probeMap '.neo/scripts/orchestrator/harness/orch_loop_suite.ps1' }
Expect-Value 'P-S3A-AS18-SCHEMA-JUDGING'  'constraint'     { Resolve-NeoArtifactClass $probeMap '.neo/schema/iteration_manifest_entry.schema.json' }
# raw oracle value: UNKNOWN = matches no glob = NON-JUDGING (default_class
# 'implementation' is applied at the AS18 layer, not by the raw resolver)
Expect-Value 'P-S3A-AS18-NEGATIVE-CONTROL' 'UNKNOWN' { Resolve-NeoArtifactClass $probeMap '.neo/scripts/notify/notify_raphael.ps1' }

# =============================================================================
# N-S3AFIX2-HIGH-ROW-CASE (B1) : a HIGH frozen RiskRow spelled in ANY non-lowercase
# casing ('HIGH'/'High'/'HiGh'), caller EffectiveRiskClass 'low', valid correlated GO
# slot => the case-fold canonicalizes rowClass to 'high' => the escalate-only clamp
# lifts effective to canonical 'high' => gate C's case-EXACT -ceq 'high' FIRES =>
# EXTERNAL_REQUIRED_UNAVAILABLE => NOT go. NEUTER (pre-fix): rowClass kept its uppercase
# spelling (case-insensitive ContainsKey passed it through) => 'HIGH' -ceq 'high' = False
# => gate C SKIPPED => a HIGH row + GO slot aggregated go with no external.
$highCasings = @('HIGH', 'High', 'HiGh')
for ($i = 0; $i -lt $highCasings.Count; $i++) {
  $spelling = $highCasings[$i]
  $rowHC = [pscustomobject]@{ id = 'r-high-case'; area = 'security'; risk_class = $spelling; never_batchable = $true; audit_tier = 'isolated' }
  # dir/slice tags are keyed off the INDEX (case-insensitively unique) - NTFS folds
  # 'hc_HIGH'/'hc_High'/'hc_HiGh' to ONE directory, which would pool the notifications.
  $caseTag = ("hc$i")
  $runHC = New-RunRoot; $dirHC = New-NotifyDir $caseTag
  $wHC = New-SlotWorld ('slot_' + $caseTag) $runHC -Recommendation 'GO'
  $stopHC = Invoke-Agg (New-Ctx $runHC ('high-case-' + $caseTag) $dirHC) $wHC $rowHC 'low'
  Expect-StopResult ('N-S3AFIX2-HIGH-ROW-CASE-' + $spelling) $stopHC 'EXTERNAL_REQUIRED_UNAVAILABLE' 'ESCALATION_STOP' $runHC $dirHC
  # the STOP row + disclosure record the CANONICAL LOWERCASE class (never the uppercase spelling)
  Expect-Value ('N-S3AFIX2-HIGH-ROW-CASE-CANON-' + $spelling) 'True' {
    $rows = Read-NeoIterationManifest -RunRoot $runHC
    $last = $rows[$rows.Count - 1]
    $fs = [string](Get-NeoProp $last 'findings_summary')
    # canonical lowercase 'high' disclosed; the raw uppercase spelling never appears
    [bool](($fs -clike "*frozen row class 'high'*") -and ($fs -cnotlike "*$spelling*"))
  }
}
# control: a lowercase 'low' row + caller 'low' + GO slot => go (no clamp, no gate).
$runHCctl = New-RunRoot; $dirHCctl = New-NotifyDir 'hc_control_low'
$wHCctl = New-SlotWorld 'slot_hc_control' $runHCctl -Recommendation 'GO'
Expect-Value 'N-S3AFIX2-HIGH-ROW-CASE-CONTROL-LOW-GO' 'True' {
  $agg = Invoke-Agg (New-Ctx $runHCctl 'hc-control' $dirHCctl) $wHCctl $rowLow 'low'
  [bool]((-not $agg.stopped) -and $agg.go)
}

# =============================================================================
# N-S3AFIX2-ROUNDDATA-NO-FORGE (B2) : Complete-NeoLoopRoundStop with RoundData naming
# an ENGINE-OWNED field (stop_reason_code / notify_gate_class / notify_sent) => BLOCK
# "cannot set engine-owned field"; the persisted STOP row's stop_reason_code +
# notify_* equal the ACTUAL stop/notify, NOT the caller's forgery. NEUTER (pre-fix):
# the implicit ContainsKey merge overwrote those slots => the forged values landed.
# S3a-FIX-3: the block message tightened from "cannot override" to "cannot set" (the
# tight caller allowlist now refuses EVERY engine-owned field, not a curated subset).
$forgeFields = @('stop_reason_code', 'notify_gate_class', 'notify_sent')
foreach ($ff in $forgeFields) {
  $runFG = New-RunRoot; $dirFG = New-NotifyDir ('forge_' + $ff)
  Expect-Block ('N-S3AFIX2-ROUNDDATA-NO-FORGE-' + $ff) 'cannot set engine-owned field' {
    Complete-NeoLoopRoundStop -Context (New-Ctx $runFG ('forge-' + $ff) $dirFG) `
      -ReasonCode 'CLASSIFIER_ERROR' -Detail 'forge attempt' -RoundData @{ $ff = 'FORGED' } | Out-Null
  }
}
# the forge attempt fails-closed BEFORE notify => zero notification AND zero row.
$runFGz = New-RunRoot; $dirFGz = New-NotifyDir 'forge_zero'
Expect-Block 'N-S3AFIX2-ROUNDDATA-NO-FORGE-FAILS-CLOSED' 'cannot set engine-owned field' {
  Complete-NeoLoopRoundStop -Context (New-Ctx $runFGz 'forge-zero' $dirFGz) `
    -ReasonCode 'CLASSIFIER_ERROR' -Detail 'forge attempt' -RoundData @{ notify_reason = 'FORGED' } | Out-Null
}
Expect-Value 'N-S3AFIX2-ROUNDDATA-NO-FORGE-NO-NOTIFY' '0' { @(Get-EmlFiles $dirFGz).Count }
Expect-Value 'N-S3AFIX2-ROUNDDATA-NO-FORGE-NO-ROW' 'True' {
  [bool](-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runFGz 'iteration_manifest.jsonl')))
}
# CORRECTED-EXPECTATION (S3a-FIX-3, disclosed): fix-2's N-S3AFIX2-ROUNDDATA-DATATIER-OK
# asserted a caller CAN override classification via RoundData. classification is now
# ENGINE-OWNED (channel separation), so that expectation is WRONG. It is REPLACED by
# N-S3AFIX3-CLASSIFICATION-ENGINE-ONLY: a caller RoundData naming classification is
# REFUSED "cannot set engine-owned field" (with zero row); the ENGINE channel
# (-EngineData) still sets it faithfully. This is a CORRECTION (classification was
# always engine-computed), not a weakening.
$runDT = New-RunRoot; $dirDT = New-NotifyDir 'classification_refused'
Expect-Block 'N-S3AFIX3-CLASSIFICATION-ENGINE-ONLY-REFUSED' 'cannot set engine-owned field' {
  Complete-NeoLoopRoundStop -Context (New-Ctx $runDT 'classification-refused' $dirDT) `
    -ReasonCode 'CLASSIFIER_ERROR' -Detail 'caller classification' -RoundData @{ classification = 'THREE_BRANCH_CLEAN' } | Out-Null
}
Expect-Value 'N-S3AFIX3-CLASSIFICATION-ENGINE-ONLY-NO-ROW' 'True' {
  [bool](-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runDT 'iteration_manifest.jsonl')))
}
# the ENGINE channel sets classification faithfully (proves the engine path still works).
$runDTe = New-RunRoot; $dirDTe = New-NotifyDir 'classification_engine'
$stopDTe = Complete-NeoLoopRoundStop -Context (New-Ctx $runDTe 'classification-engine' $dirDTe) `
  -ReasonCode 'CLASSIFIER_ERROR' -Detail 'engine classification' -EngineData @{ classification = 'STOPPED_THREE_BRANCH' }
Expect-Value 'N-S3AFIX3-CLASSIFICATION-ENGINE-ONLY-ENGINE-SETS' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runDTe
  $last = $rows[$rows.Count - 1]
  [bool](([string](Get-NeoProp $last 'classification') -ceq 'STOPPED_THREE_BRANCH') `
    -and ([string](Get-NeoProp $last 'stop_reason_code') -ceq 'CLASSIFIER_ERROR') `
    -and ([bool]$stopDTe.stopped))
}

# =============================================================================
# N-S3AFIX2-ATOMIC-NOTIFY-ROW (B3) : notify and manifest row are ATOMIC. A STOP whose
# RoundData carries an UNKNOWN/FORBIDDEN key => BLOCK with ZERO notification composed AND
# zero row (validation runs BEFORE notify). A VALID STOP => EXACTLY ONE notification AND
# EXACTLY ONE row (both land). NEUTER (pre-fix): notify fired at :373 BEFORE the merge
# threw at :394 => the bad-key case composed a notification then threw with NO row.
# -- bad UNKNOWN key => zero notify + zero row (fails BEFORE notify) --
$runAT = New-RunRoot; $dirAT = New-NotifyDir 'atomic_badkey'
Expect-Block 'N-S3AFIX2-ATOMIC-BADKEY-BLOCKS' 'unknown field' {
  Complete-NeoLoopRoundStop -Context (New-Ctx $runAT 'atomic-badkey' $dirAT) `
    -ReasonCode 'CLASSIFIER_ERROR' -Detail 'bad key' -RoundData @{ not_a_real_field = 'x' } | Out-Null
}
Expect-Value 'N-S3AFIX2-ATOMIC-BADKEY-ZERO-NOTIFY' '0' { @(Get-EmlFiles $dirAT).Count }
Expect-Value 'N-S3AFIX2-ATOMIC-BADKEY-ZERO-ROW' 'True' {
  [bool](-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runAT 'iteration_manifest.jsonl')))
}
# -- valid STOP => EXACTLY ONE notify AND EXACTLY ONE row (both land) --
# S3a-FIX-3 corrected-expectation: the valid-STOP RoundData now carries a CALLER-
# SUPPLIABLE key (baseline_head_sha) instead of the (now engine-owned) external_lane_status,
# so the atomic proof stands on a legitimately caller-suppliable field.
$runATok = New-RunRoot; $dirATok = New-NotifyDir 'atomic_ok'
$stopATok = Complete-NeoLoopRoundStop -Context (New-Ctx $runATok 'atomic-ok' $dirATok) `
  -ReasonCode 'CLASSIFIER_ERROR' -Detail 'valid stop' -RoundData @{ baseline_head_sha = ('a' * 40) }
Expect-Value 'N-S3AFIX2-ATOMIC-VALID-ONE-NOTIFY' '1' { @(Get-EmlFiles $dirATok).Count }
Expect-Value 'N-S3AFIX2-ATOMIC-VALID-ONE-ROW' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runATok
  [bool](($rows.Count -eq 1) -and ([string](Get-NeoProp $rows[0] 'stop_reason_code') -ceq 'CLASSIFIER_ERROR') -and [bool]$stopATok.stopped)
}

# =============================================================================
# S3a-FIX-3 : MANIFEST-FIELD-AUTHORITY CLASS-CLOSER (channel separation).
# The verdict-lane / classification / findings_summary fields are ENGINE-COMPUTED and
# reach the row ONLY via the trusted engine channel; a caller RoundData can carry ONLY
# the tight round-diff set { baseline_head_sha, baseline_tree_hash, changed_count,
# changed_paths_hash }. After this, NO manifest field is caller-forgeable.
# =============================================================================

# -- N-S3AFIX3-LANE-NO-FORGE : a caller RoundData naming ANY engine-owned verdict-lane /
# classification / findings_summary field => BLOCK "cannot set engine-owned field", at
# BOTH public entries (Complete-NeoLoopRoundStop AND Assert-NeoLoopAuditSatisfied), with
# a zero row. NEUTER (pre-fix): restore the wide data-tier allowlist => the forged lanes
# land in the row => flips.
$engineOwnedForge = @('external_lane_status', 'auditor_slot_recommendation', 'auditor_slot_status',
  'classification', 'effective_seam_tier', 'findings_summary', 'auditor_identity')
foreach ($ef in $engineOwnedForge) {
  # (i) at the WRITE choke point Complete-NeoLoopRoundStop
  $runLF = New-RunRoot; $dirLF = New-NotifyDir ('lane_forge_stop_' + $ef)
  Expect-Block ('N-S3AFIX3-LANE-NO-FORGE-STOP-' + $ef) 'cannot set engine-owned field' {
    Complete-NeoLoopRoundStop -Context (New-Ctx $runLF ('lane-forge-stop-' + $ef) $dirLF) `
      -ReasonCode 'CLASSIFIER_ERROR' -Detail 'lane forge at stop' -RoundData @{ $ef = 'GO' } | Out-Null
  }
  Expect-Value ('N-S3AFIX3-LANE-NO-FORGE-STOP-NOROW-' + $ef) 'True' {
    [bool](-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runLF 'iteration_manifest.jsonl')))
  }
  # (ii) at the ROUND-STAGE entry Assert-NeoLoopAuditSatisfied (its RoundData is tight-
  # validated at the boundary, BEFORE any guard's own STOP) - proves the split is enforced
  # at EVERY public entry, not one function.
  $runLFa = New-RunRoot; $dirLFa = New-NotifyDir ('lane_forge_agg_' + $ef); $wLFa = New-SlotWorld ('slot_lf_' + $ef) $runLFa
  Expect-Block ('N-S3AFIX3-LANE-NO-FORGE-AGG-' + $ef) 'cannot set engine-owned field' {
    Assert-NeoLoopAuditSatisfied -Context (New-Ctx $runLFa ('lane-forge-agg-' + $ef) $dirLFa) -RiskRow $rowLow `
      -EffectiveRiskClass 'low' -EndReport $wLFa.endLive -SessionRoot $wLFa.root -MasterIdentity 'm1' `
      -BuilderIdentity 'b1' -Index $index -RoundId 'round-1' -ExternalLaneStatus 'NOT_WIRED' `
      -RoundData @{ $ef = 'GO' } | Out-Null
  }
}

# -- N-S3AFIX3-ENGINE-LANES-FAITHFUL : the ENGINE channel still records the real lanes.
# A round that REALLY reaches gate-A SATISFIED then STOPs at gate C (HIGH + NOT_WIRED)
# records auditor_slot_status=SATISFIED + the real recommendation + external_lane_status
# via the engine channel (not forged, DERIVED). A round that STOPs BEFORE gate A (early
# guard: bad EffectiveRiskClass) records those lanes NOT_EVALUATED (honest). Proves the
# engine channel WORKS - not merely that the caller channel is blocked.
$runEL = New-RunRoot; $dirEL = New-NotifyDir 'engine_lane_faithful'; $wEL = New-SlotWorld 'slot_el' $runEL
$stopEL = Invoke-Agg (New-Ctx $runEL 'engine-lane' $dirEL) $wEL $rowHigh 'high'   # HIGH + slot SATISFIED => STOP at gate C
Expect-Value 'N-S3AFIX3-ENGINE-LANES-FAITHFUL-SATISFIED' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runEL
  $last = $rows[$rows.Count - 1]
  [bool](([string]$stopEL.reason_code -ceq 'EXTERNAL_REQUIRED_UNAVAILABLE') `
    -and ([string](Get-NeoProp $last 'auditor_slot_status') -ceq 'SATISFIED') `
    -and ([string](Get-NeoProp $last 'auditor_slot_recommendation') -ceq 'GO') `
    -and ([string](Get-NeoProp $last 'auditor_identity') -ceq 'isolated-auditor-cold') `
    -and ([string](Get-NeoProp $last 'external_lane_status') -ceq 'NOT_WIRED') `
    -and ([string](Get-NeoProp $last 'effective_seam_tier') -ceq 'isolated'))
}
# a STOP BEFORE gate A (early-guard: unknown EffectiveRiskClass) => lanes NOT_EVALUATED.
$runELn = New-RunRoot; $dirELn = New-NotifyDir 'engine_lane_early'; $wELn = New-SlotWorld 'slot_eln' $runELn
$stopELn = Invoke-Agg (New-Ctx $runELn 'engine-lane-early' $dirELn) $wELn $rowLow 'bogus-class'
Expect-Value 'N-S3AFIX3-ENGINE-LANES-FAITHFUL-NOT-EVALUATED' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runELn
  $last = $rows[$rows.Count - 1]
  [bool](([string]$stopELn.reason_code -ceq 'CLASSIFIER_ERROR') `
    -and ([string](Get-NeoProp $last 'auditor_slot_status') -ceq 'NOT_EVALUATED') `
    -and ([string](Get-NeoProp $last 'auditor_slot_recommendation') -ceq 'NOT_EVALUATED') `
    -and ([string](Get-NeoProp $last 'external_lane_status') -ceq 'NOT_EVALUATED') `
    -and ([string](Get-NeoProp $last 'effective_seam_tier') -ceq 'NOT_EVALUATED'))
}

# -- N-S3AFIX3-ROUTED-STOP-NO-FORGE : Assert-NeoLoopAuditSatisfied with a valid Context +
# an early-guard stop (bad EffectiveRiskClass) + caller RoundData carrying FORGED lanes =>
# BLOCK at the entry validation (BEFORE the guard's own STOP), with zero row - never the
# forged GO. NEUTER (pre-fix): restore the pre-validation copy-into-$rd => the
# CLASSIFIER_ERROR row claims GO lanes => flips.
$runRS = New-RunRoot; $dirRS = New-NotifyDir 'routed_stop_forge'; $wRS = New-SlotWorld 'slot_rs' $runRS
Expect-Block 'N-S3AFIX3-ROUTED-STOP-NO-FORGE' 'cannot set engine-owned field' {
  Assert-NeoLoopAuditSatisfied -Context (New-Ctx $runRS 'routed-stop-forge' $dirRS) -RiskRow $rowLow `
    -EffectiveRiskClass 'bogus-class' -EndReport $wRS.endLive -SessionRoot $wRS.root -MasterIdentity 'm1' `
    -BuilderIdentity 'b1' -Index $index -RoundId 'round-1' -ExternalLaneStatus 'NOT_WIRED' `
    -RoundData @{ external_lane_status = 'GO'; auditor_slot_status = 'SATISFIED'; auditor_slot_recommendation = 'GO' } | Out-Null
}
Expect-Value 'N-S3AFIX3-ROUTED-STOP-NO-FORGE-NO-ROW' 'True' {
  [bool](-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runRS 'iteration_manifest.jsonl')))
}

# -- N-S3AFIX3-CALLER-DIFF-OK (control) : a caller RoundData with ONLY the tight round-diff
# set => accepted, recorded faithfully (the legitimate caller path still works).
$runCD = New-RunRoot; $dirCD = New-NotifyDir 'caller_diff_ok'
$stopCD = Complete-NeoLoopRoundStop -Context (New-Ctx $runCD 'caller-diff-ok' $dirCD) `
  -ReasonCode 'CLASSIFIER_ERROR' -Detail 'caller round-diff' `
  -RoundData @{ baseline_head_sha = ('a' * 40); baseline_tree_hash = ('b' * 64); changed_count = 3; changed_paths_hash = ('c' * 64) }
Expect-Value 'N-S3AFIX3-CALLER-DIFF-OK' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runCD
  $last = $rows[$rows.Count - 1]
  [bool](([string](Get-NeoProp $last 'baseline_head_sha') -ceq ('a' * 40)) `
    -and ([string](Get-NeoProp $last 'baseline_tree_hash') -ceq ('b' * 64)) `
    -and ([int](Get-NeoProp $last 'changed_count') -eq 3) `
    -and ([string](Get-NeoProp $last 'changed_paths_hash') -ceq ('c' * 64)) `
    -and ([string](Get-NeoProp $last 'stop_reason_code') -ceq 'CLASSIFIER_ERROR') `
    -and ([bool]$stopCD.stopped))
}

# =============================================================================
# S3a-FIX-4 : ROOT ATOMICITY CLOSE (schema-validate the ASSEMBLED row before notify).
# The B3 "notify iff row" property is closed for EVERY schema-content reason - not just
# unknown KEYS (B3) but schema-invalid VALUES on ALLOWED caller keys. A schema-invalid
# assembled row fails-closed BEFORE notify (0 notify + 0 row); a schema-valid row => notify
# + row (atomic 1+1). NEUTER (pre-fix): remove the pre-notify dry-run row schema-validation
# in Complete-NeoLoopRoundStop => notify fires then the writer's own Assert-NeoValid rejects
# the row => notify=1 / row=0 => every bad-value case below FLIPS.
# =============================================================================

# -- N-S3AFIX4-ATOMIC-BADVALUE-STOP : Complete-NeoLoopRoundStop with an ALLOWED caller key
# carrying a SCHEMA-INVALID VALUE => BLOCK reason_code=LEDGER_FAILURE BEFORE notify, with
# ZERO composed notifications AND ZERO rows (no manifest file). Three sub-cases exercise
# three distinct schema constraints on caller-suppliable fields:
#   changed_count='not-an-integer' (type integer), changed_paths_hash='' (minLength 1),
#   baseline_head_sha='' (minLength 1).
$badValueCases = @(
  @{ tag = 'changed-count-noninteger'; data = @{ changed_count = 'not-an-integer' } },
  @{ tag = 'changed-paths-hash-empty'; data = @{ changed_paths_hash = '' } },
  @{ tag = 'baseline-head-sha-empty';  data = @{ baseline_head_sha = '' } }
)
foreach ($bc in $badValueCases) {
  $runBV = New-RunRoot; $dirBV = New-NotifyDir ('bad_value_stop_' + $bc.tag)
  Expect-Block ('N-S3AFIX4-ATOMIC-BADVALUE-STOP-' + $bc.tag) 'fails schema validation BEFORE notify' {
    Complete-NeoLoopRoundStop -Context (New-Ctx $runBV ('bad-value-stop-' + $bc.tag) $dirBV) `
      -ReasonCode 'CLASSIFIER_ERROR' -Detail 'schema-invalid value on an allowed caller key' `
      -RoundData $bc.data | Out-Null
  }
  Expect-Value ('N-S3AFIX4-ATOMIC-BADVALUE-STOP-ZERO-NOTIFY-' + $bc.tag) '0' { @(Get-EmlFiles $dirBV).Count }
  Expect-Value ('N-S3AFIX4-ATOMIC-BADVALUE-STOP-ZERO-ROW-' + $bc.tag) 'True' {
    [bool](-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runBV 'iteration_manifest.jsonl')))
  }
}

# -- N-S3AFIX4-ATOMIC-BADVALUE-AGG : the SAME malformed changed_count reaching the shared
# stop path via Assert-NeoLoopAuditSatisfied (a valid Context + a bad EffectiveRiskClass
# early stop, with the caller RoundData carrying changed_count='not-an-integer'). The tight
# key-ownership guard at the entry ACCEPTS changed_count (it is caller-suppliable) and
# forwards it as -RoundData into Complete-NeoLoopRoundStop's early-guard STOP => the pre-
# notify dry-run rejects the bad value => BLOCK BEFORE notify (0 notify + 0 row). Proves the
# single shared choke point closes BOTH reach paths. Same neuter flips it.
$runBVa = New-RunRoot; $dirBVa = New-NotifyDir 'bad_value_agg'; $wBVa = New-SlotWorld 'slot_bva' $runBVa
Expect-Block 'N-S3AFIX4-ATOMIC-BADVALUE-AGG' 'fails schema validation BEFORE notify' {
  Assert-NeoLoopAuditSatisfied -Context (New-Ctx $runBVa 'bad-value-agg' $dirBVa) -RiskRow $rowLow `
    -EffectiveRiskClass 'bogus-class' -EndReport $wBVa.endLive -SessionRoot $wBVa.root -MasterIdentity 'm1' `
    -BuilderIdentity 'b1' -Index $index -RoundId 'round-1' -ExternalLaneStatus 'NOT_WIRED' `
    -RoundData @{ changed_count = 'not-an-integer' } | Out-Null
}
Expect-Value 'N-S3AFIX4-ATOMIC-BADVALUE-AGG-ZERO-NOTIFY' '0' { @(Get-EmlFiles $dirBVa).Count }
Expect-Value 'N-S3AFIX4-ATOMIC-BADVALUE-AGG-ZERO-ROW' 'True' {
  [bool](-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runBVa 'iteration_manifest.jsonl')))
}

# -- N-S3AFIX4-ATOMIC-VALID (control) : a VALID stop (legit caller round-diff values +
# engine lanes) => EXACTLY ONE notification AND EXACTLY ONE row (atomic 1+1). The added
# pre-notify validation does NOT break the happy path.
$runVV = New-RunRoot; $dirVV = New-NotifyDir 'valid_atomic'
$stopVV = Complete-NeoLoopRoundStop -Context (New-Ctx $runVV 'valid-atomic' $dirVV) `
  -ReasonCode 'CLASSIFIER_ERROR' -Detail 'valid stop with round-diff + engine lanes' `
  -RoundData @{ baseline_head_sha = ('a' * 40); baseline_tree_hash = ('b' * 64); changed_count = 5; changed_paths_hash = ('c' * 64) } `
  -EngineData @{ classification = 'STOPPED_THREE_BRANCH'; effective_seam_tier = 'isolated' }
Expect-Value 'N-S3AFIX4-ATOMIC-VALID-ONE-NOTIFY' '1' { @(Get-EmlFiles $dirVV).Count }
Expect-Value 'N-S3AFIX4-ATOMIC-VALID-ONE-ROW' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runVV
  [bool](($rows.Count -eq 1) `
    -and ([int](Get-NeoProp $rows[0] 'changed_count') -eq 5) `
    -and ([string](Get-NeoProp $rows[0] 'baseline_head_sha') -ceq ('a' * 40)) `
    -and ([string](Get-NeoProp $rows[0] 'classification') -ceq 'STOPPED_THREE_BRANCH') `
    -and ([string](Get-NeoProp $rows[0] 'effective_seam_tier') -ceq 'isolated') `
    -and ([string](Get-NeoProp $rows[0] 'stop_reason_code') -ceq 'CLASSIFIER_ERROR') `
    -and ([string](Get-NeoProp $rows[0] 'notify_gate_class') -ceq 'ESCALATION_STOP') `
    -and ([bool]$stopVV.stopped))
}

# =============================================================================
# ======================= S3b: MULTI-ROUND CONVERGENCE WRAPPER ================
# =============================================================================
# Shared S3b plumbing: a fresh governed mirror + pin (never tampered by earlier
# cases) and one converge-invocation helper pinning the safe defaults. Every
# scenario drives the seam/provider as scriptblocks; counters and world roots are
# $script:-qualified so the scriptblocks resolve them regardless of the invoking
# scope. NOTE (structural live-send incapability): every context still comes from
# New-Ctx (notify_live_send=$false + scratch TestModeDir) - the live-send token
# appears nowhere in this file.
$mirrorSB = New-GovMirror 'gov_s3b'
$pinSB = Pin-GovMirror $mirrorSB 'pin_s3b.json'
function Get-SlotWorldEr([string]$root) { return (Join-Path $root 'NEO_SESSION\ss-loop\SUBSESSION_END_REPORT.json') }
function Invoke-ConvergeS3B($ctx, [string]$repo, $seam, $provider, $extra = @{}) {
  $cargs = @{
    Context = $ctx; RepoRoot = $repo
    ApprovedPaths = $approved; ProtectedPaths = $protected
    PinnedGovManifestPath = $pinSB; GovernedRoot = $mirrorSB; DerivedAt = $TS
    RouterProfile = $routerProfile; RiskRow = $rowLow
    MasterIdentity = 'm1'; BuilderIdentity = 'b1'; Index = $index
    Goal = 'converge slice goal'; RiskClass = 'low'
    AllowlistItems = @(@{ rel = 'app/widget.txt'; role = 'current_artifact' })
    TestPlan = @('run suite'); StopConditions = @('ambiguity')
    ProposedEdits = @('app/widget.txt')
    BuilderSeam = $seam; AuditProvider = $provider
    # S3b-FIX CX-F1: no NowUtcProvider - the gate reads the REAL clock. New-RunRoot
    # stamps started_at_utc = $TS (suite-start now), so elapsed is ~seconds << 4h cap.
  }
  foreach ($k in @($extra.Keys)) { $cargs[$k] = $extra[$k] }
  return (Invoke-NeoLoopConverge @cargs)
}

# =============================================================================
# P-S3B-GO-BREAKS : a GO round 0 => break; one caller-recorded row; no notify
# =============================================================================
$runGB1 = New-RunRoot; $repoGB1 = New-AppRepo 'repo_s3b_go'; $dirGB1 = New-NotifyDir 's3b_go'
$ctxGB1 = New-Ctx $runGB1 's3b-go' $dirGB1 0 1
$wSBgo = New-SlotWorld 'slot_s3b_go_r0' $runGB1 -RoundId 'round-0' -Recommendation 'GO'
$script:sbGoRoot = $wSBgo.root
$script:sbGoSeam = 0
$seamGo = { param($info) $script:sbGoSeam++; Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit for build attempt ' + $info.round) -Encoding Ascii; return 'seam-return-ignored' }
$provGo = { param($q) return @{ end_report_path = (Get-SlotWorldEr $script:sbGoRoot); session_root = $script:sbGoRoot } }
$resGo = Invoke-ConvergeS3B $ctxGB1 $repoGB1 $seamGo $provGo
Expect-Value 'P-S3B-GO-BREAKS' 'True' { [bool]($resGo.converged -and $resGo.go -and (-not $resGo.stopped)) }
Expect-Value 'P-S3B-GO-BREAKS-ONE-SEAM-CALL' '1' { $script:sbGoSeam }
Expect-Value 'P-S3B-GO-BREAKS-ONE-ROW' '1' { $r = Read-NeoIterationManifest -RunRoot $runGB1; $r.Count }
Expect-Value 'P-S3B-GO-BREAKS-ROW-SHAPE' 'True' {
  $row = (Read-NeoIterationManifest -RunRoot $runGB1)[0]
  [bool](([int](Get-NeoProp $row 'round') -eq 0) `
    -and ([string](Get-NeoProp $row 'stop_reason_code') -ceq 'NONE') `
    -and ([string](Get-NeoProp $row 'notify_gate_class') -ceq 'NONE') `
    -and ([string](Get-NeoProp $row 'auditor_slot_recommendation') -ceq 'GO') `
    -and ([string](Get-NeoProp $row 'effective_seam_tier') -ceq 'isolated') `
    -and ([int](Get-NeoProp $row 'changed_count') -eq 1))
}
Expect-Value 'P-S3B-GO-BREAKS-NO-NOTIFY' '0' { @(Get-EmlFiles $dirGB1).Count }
Expect-Value 'P-S3B-GO-BREAKS-LEDGER-ALIGN' 'True' {
  $led = Read-NeoAttemptLedger -RunRoot $runGB1
  $rows = Read-NeoIterationManifest -RunRoot $runGB1
  [bool](($led.Count -eq 1) -and ([string](Get-NeoProp $led[0] 'kind') -ceq 'initial') `
    -and ([int](Get-NeoProp $led[0] 'round') -eq 0) -and ($rows.Count -eq $led.Count))
}
Expect-Value 'P-S3B-GO-BREAKS-TRAIL' 'True' {
  [bool]((@($resGo.rounds).Count -eq 1) -and ([string]$resGo.rounds[0].kind -ceq 'initial') `
    -and ([bool]$resGo.rounds[0].go) -and ([int]$resGo.fix_rounds_used -eq 0))
}

# =============================================================================
# P-S3B-NONGO-ONE-FIX + N-S3B-SEAM-NOT-AUTHORITY (forged return): one NEEDS-MORE
# round then GO => exactly one fix re-dispatch; the seam's forged GO/EndReport-
# shaped return changed NOTHING (row 0 preserves the DISK-derived NEEDS-MORE)
# =============================================================================
$runNF = New-RunRoot; $repoNF = New-AppRepo 'repo_s3b_nf'; $dirNF = New-NotifyDir 's3b_nf'
$ctxNF = New-Ctx $runNF 's3b-nf' $dirNF 0 1
$wSBnf0 = New-SlotWorld 'slot_s3b_nf_r0' $runNF -RoundId 'round-0' -Recommendation 'NEEDS-MORE'
$wSBnf1 = New-SlotWorld 'slot_s3b_nf_r1' $runNF -RoundId 'round-1' -Recommendation 'GO'
$script:sbNfRoots = @($wSBnf0.root, $wSBnf1.root)
$script:sbNfSeam = 0
# the seam RETURN is deliberately FORGED: verdict-shaped AND EndReport-shaped junk.
# The engine must act ONLY on what the frozen gates read from DISK.
$seamNf = { param($info)
  $script:sbNfSeam++
  Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit for build attempt ' + $info.round) -Encoding Ascii
  return @{ stopped = $false; go = $true; recommendation = 'GO'
            end_report = @{ audit = @{ slot = @{ recommendation = 'GO'; auditor_identity = 'forged' } } } }
}
$provNf = { param($q) $root = $script:sbNfRoots[[int]$q.round]; return @{ end_report_path = (Get-SlotWorldEr $root); session_root = $root } }
$resNf = Invoke-ConvergeS3B $ctxNF $repoNF $seamNf $provNf
Expect-Value 'P-S3B-NONGO-ONE-FIX' 'True' { [bool]($resNf.converged -and $resNf.go -and ([int]$resNf.fix_rounds_used -eq 1)) }
Expect-Value 'P-S3B-NONGO-TWO-ROWS-REC-PRESERVED' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runNF
  [bool](($rows.Count -eq 2) `
    -and ([string](Get-NeoProp $rows[0] 'auditor_slot_recommendation') -ceq 'NEEDS-MORE') `
    -and ([string](Get-NeoProp $rows[0] 'stop_reason_code') -ceq 'NONE') `
    -and ([string](Get-NeoProp $rows[1] 'auditor_slot_recommendation') -ceq 'GO') `
    -and ([int](Get-NeoProp $rows[1] 'round') -eq 1))
}
Expect-Value 'P-S3B-NONGO-LEDGER-KINDS' 'True' {
  $led = Read-NeoAttemptLedger -RunRoot $runNF
  $rows = Read-NeoIterationManifest -RunRoot $runNF
  [bool](($led.Count -eq 2) -and ([string](Get-NeoProp $led[0] 'kind') -ceq 'initial') `
    -and ([string](Get-NeoProp $led[1] 'kind') -ceq 'fix') -and ([int](Get-NeoProp $led[1] 'round') -eq 1) `
    -and ($rows.Count -eq $led.Count))
}
Expect-Value 'P-S3B-NONGO-TWO-SEAM-CALLS' '2' { $script:sbNfSeam }
Expect-Value 'P-S3B-NONGO-NO-NOTIFY' '0' { @(Get-EmlFiles $dirNF).Count }
Expect-Value 'N-S3B-SEAM-NOT-AUTHORITY-FORGED' 'True' {
  # the forged go=$true/EndReport-shaped return did NOT break the loop at round 0:
  # round 0's row carries the DISK-derived NEEDS-MORE and a fix round actually ran.
  $rows = Read-NeoIterationManifest -RunRoot $runNF
  [bool](([string](Get-NeoProp $rows[0] 'auditor_slot_recommendation') -ceq 'NEEDS-MORE') -and ($script:sbNfSeam -eq 2))
}

# =============================================================================
# N-S3B-CAP-BOUNDARY-4TH-REFUSED : 3 fixes consumed; the 4th fix's write-ahead
# entry LANDS refused (CAP_FIX_ROUNDS) and the dispatch NEVER runs (NB-2)
# =============================================================================
$runCB = New-RunRoot; $repoCB = New-AppRepo 'repo_s3b_cap'; $dirCB = New-NotifyDir 's3b_cap'
$ctxCB = New-Ctx $runCB 's3b-cap' $dirCB 0 1
$script:sbCapRoots = @()
foreach ($i in 0..3) {
  $w = New-SlotWorld ("slot_s3b_cap$i") $runCB -RoundId ("round-$i") -Recommendation 'NEEDS-MORE'
  $script:sbCapRoots += $w.root
}
$script:sbCapSeam = 0
$seamCap = { param($info) $script:sbCapSeam++; Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit for build attempt ' + $info.round) -Encoding Ascii }
$provCap = { param($q) $root = $script:sbCapRoots[[int]$q.round]; return @{ end_report_path = (Get-SlotWorldEr $root); session_root = $root } }
$resCap = Invoke-ConvergeS3B $ctxCB $repoCB $seamCap $provCap
Expect-StopResult 'N-S3B-CAP-BOUNDARY-4TH-REFUSED' $resCap.stop 'CAP_FIX_ROUNDS' 'BREAKER_TRIP' $runCB $dirCB
Expect-Value 'N-S3B-CAP-BOUNDARY-NO-4TH-DISPATCH' '4' { $script:sbCapSeam }   # rounds 0-3 only; the 4th fix NEVER reached the seam
Expect-Value 'N-S3B-CAP-BOUNDARY-ENTRY-LANDS' 'True' {
  $led = Read-NeoAttemptLedger -RunRoot $runCB -SliceId $ctxCB.slice_id
  $last = $led[$led.Count - 1]
  [bool](($led.Count -eq 5) -and ([string](Get-NeoProp $last 'kind') -ceq 'fix') `
    -and ([int](Get-NeoProp $last 'round') -eq 4) -and ([bool](Get-NeoProp $last 'refused')) `
    -and ([string](Get-NeoProp $last 'reason') -ceq 'CAP_FIX_ROUNDS'))
}
Expect-Value 'N-S3B-CAP-BOUNDARY-CAP-EVENTS' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runCB -SliceId $ctxCB.slice_id
  $last = $rows[$rows.Count - 1]
  # assignment + pipeline-flatten (NOT @(call) - Get-NeoVal is shape-preserving and
  # @() around it would NEST the returned array; same idiom note as the reader).
  $ev = Get-NeoVal $last 'cap_events'
  $flat = @($ev | ForEach-Object { [string]$_ })
  [bool](($flat.Count -ge 1) -and (($flat -join ' ') -like '*CAP_FIX_ROUNDS*'))
}
Expect-Value 'N-S3B-CAP-BOUNDARY-FIXUSED' '3' { [int]$resCap.fix_rounds_used }
Expect-Value 'P-S3B-TRAIL-PRECHECK' 'True' {
  # pre-proves the S3c I7/N3 invariant on a full multi-round scenario: iteration-
  # manifest rows == attempt-ledger entries for the slice (rounds 0-3 + the STOP row
  # vs initial + 3 fixes + the landed-refused entry).
  $rows = Read-NeoIterationManifest -RunRoot $runCB -SliceId $ctxCB.slice_id
  $led = Read-NeoAttemptLedger -RunRoot $runCB -SliceId $ctxCB.slice_id
  [bool](($rows.Count -eq 5) -and ($led.Count -eq 5))
}

# =============================================================================
# N-S3B-WALLCLOCK-TRIP : persisted start beyond the cap => breaker STOP, no dispatch
# (S3b-FIX CX-F1: persisted-STATE manipulation vs the REAL clock - the manifest
# started_at_utc is 5h in the past; NO provider exists to lie about "now")
# =============================================================================
$runWC = Join-Path $ScratchRoot 'run_s3b_wc'
New-Item -ItemType Directory -Force -Path $runWC | Out-Null
$tsWCpast = (Get-Date).ToUniversalTime().AddHours(-5).ToString('yyyy-MM-ddTHH:mm:ssZ')
[void](New-NeoRunManifest -RunRoot $runWC -Caps $caps -Timestamp $tsWCpast)
$repoWC = New-AppRepo 'repo_s3b_wc'; $dirWC = New-NotifyDir 's3b_wc'
$ctxWC = New-Ctx $runWC 's3b-wc' $dirWC 0 1
$script:sbWcSeam = 0
$seamWc = { param($info) $script:sbWcSeam++ }
$provWc = { param($q) throw 'audit provider must never be reached on a wall-clock trip' }
$resWc = Invoke-ConvergeS3B $ctxWC $repoWC $seamWc $provWc
Expect-StopResult 'N-S3B-WALLCLOCK-TRIP' $resWc.stop 'CAP_WALL_CLOCK' 'BREAKER_TRIP' $runWC $dirWC
Expect-Value 'N-S3B-WALLCLOCK-NO-DISPATCH' 'True' {
  [bool](($script:sbWcSeam -eq 0) -and (-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runWC 'attempt_ledger.jsonl'))))
}

# =============================================================================
# N-S3BF-NO-TIME-CHANNEL (S3b-FIX CX-F1, load-bearing): binding -NowUtcProvider
# on Invoke-NeoLoopConverge or Invoke-NeoLoopWallClockGate FAILS with a genuine
# PARAMETER-BINDING error (never a routed STOP) - the caller time-authority
# channel is GONE, not defaulted. A future re-add of the parameter (even
# defaulted) flips these checks.
# =============================================================================
$runTC = New-RunRoot; $repoTC = New-AppRepo 'repo_s3bf_tc'; $dirTC = New-NotifyDir 's3bf_tc'
$ctxTC = New-Ctx $runTC 's3bf-tc' $dirTC 0 1
Expect-Value 'N-S3BF-NO-TIME-CHANNEL-CONVERGE' 'binding-error' {
  $out = 'call-succeeded (channel still exists)'
  try { [void](Invoke-ConvergeS3B $ctxTC $repoTC ({ param($info) }) ({ param($q) throw 'never reached' }) @{ NowUtcProvider = { '2026-01-01T00:00:00Z' } }) }
  catch {
    if (($_.Exception -is [System.Management.Automation.ParameterBindingException]) -and ($_.Exception.Message -match 'NowUtcProvider')) { $out = 'binding-error' }
    else { $out = 'wrong-error-type: ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message }
  }
  $out
}
Expect-Value 'N-S3BF-NO-TIME-CHANNEL-GATE' 'binding-error' {
  $out = 'call-succeeded (channel still exists)'
  try { [void](Invoke-NeoLoopWallClockGate -Ctx $ctxTC -NowUtcProvider { '2026-01-01T00:00:00Z' }) }
  catch {
    if (($_.Exception -is [System.Management.Automation.ParameterBindingException]) -and ($_.Exception.Message -match 'NowUtcProvider')) { $out = 'binding-error' }
    else { $out = 'wrong-error-type: ' + $_.Exception.GetType().Name + ': ' + $_.Exception.Message }
  }
  $out
}
Expect-Value 'N-S3BF-NO-TIME-CHANNEL-NO-SIDE-EFFECTS' 'True' {
  # a binding failure happens BEFORE the function body: no row, no ledger, no notify.
  [bool]((-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runTC 'iteration_manifest.jsonl'))) `
    -and (-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runTC 'attempt_ledger.jsonl'))) `
    -and (@(Get-EmlFiles $dirTC).Count -eq 0))
}

# =============================================================================
# N-S3BF-WALLCLOCK-REAL (S3b-FIX CX-F1, the SC repro as a fixture): manifest
# started_at_utc = REAL now minus 10h, cap 4h => the gate STOPs CAP_WALL_CLOCK
# (BREAKER_TRIP) with a STOP row + composed notification (TestModeDir), BEFORE
# any attempt-ledger write. With the provider channel gone there is NO way to
# hand the gate a lying "now" - the run's own persisted past is enough to trip.
# =============================================================================
$runWR = Join-Path $ScratchRoot 'run_s3bf_wr'
New-Item -ItemType Directory -Force -Path $runWR | Out-Null
$tsWRpast = (Get-Date).ToUniversalTime().AddHours(-10).ToString('yyyy-MM-ddTHH:mm:ssZ')
[void](New-NeoRunManifest -RunRoot $runWR -Caps $caps -Timestamp $tsWRpast)
$repoWR = New-AppRepo 'repo_s3bf_wr'; $dirWR = New-NotifyDir 's3bf_wr'
$ctxWR = New-Ctx $runWR 's3bf-wr' $dirWR 0 1
$script:sbWrSeam = 0
$seamWr = { param($info) $script:sbWrSeam++ }
$provWr = { param($q) throw 'audit provider must never be reached on a wall-clock trip' }
$resWr = Invoke-ConvergeS3B $ctxWR $repoWR $seamWr $provWr
Expect-StopResult 'N-S3BF-WALLCLOCK-REAL' $resWr.stop 'CAP_WALL_CLOCK' 'BREAKER_TRIP' $runWR $dirWR
Expect-Value 'N-S3BF-WALLCLOCK-REAL-BEFORE-LEDGER' 'True' {
  # the STOP landed BEFORE any ledger write or dispatch: no seam call, no attempt ledger.
  [bool](($script:sbWrSeam -eq 0) -and (-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runWR 'attempt_ledger.jsonl'))))
}
Expect-Value 'N-S3BF-WALLCLOCK-REAL-CAP-EVENTS' 'True' {
  # the trip discloses cap arithmetic measured from the PERSISTED started_at_utc
  # (read from the DISK row - assignment + pipeline-flatten, the reader's idiom).
  $rows = Read-NeoIterationManifest -RunRoot $runWR
  $last = $rows[$rows.Count - 1]
  $ev = Get-NeoVal $last 'cap_events'
  $flat = @($ev | ForEach-Object { [string]$_ })
  [bool](($flat.Count -ge 1) -and (($flat -join ' ') -like '*CAP_WALL_CLOCK*') -and (($flat -join ' ') -like '*PERSISTED started_at_utc*'))
}

# =============================================================================
# N-S3B-LEDGER-FAILURE : corrupt attempt ledger mid-loop => STOP, no dispatch,
# NO repair (the ledger bytes are untouched)
# =============================================================================
$runLE = New-RunRoot; $repoLE = New-AppRepo 'repo_s3b_lf'; $dirLE = New-NotifyDir 's3b_lf'
$ctxLE = New-Ctx $runLE 's3b-lf' $dirLE 0 1
[void](Add-NeoAttemptLedgerEntry -RunRoot $runLE -SliceId ("s3a-$tag-lf-seed") -Round 0 -Kind 'initial' -Timestamp $TS)
$ledPathLE = Resolve-NeoRunStatePath $runLE 'attempt_ledger.jsonl'
[System.IO.File]::AppendAllText($ledPathLE, "{not json`n", (New-Object System.Text.UTF8Encoding($false)))
$ledBytesLE = [System.IO.File]::ReadAllText($ledPathLE)
$script:sbLfSeam = 0
$seamLf = { param($info) $script:sbLfSeam++ }
$provLf = { param($q) throw 'audit provider must never be reached on a ledger failure' }
$resLf = Invoke-ConvergeS3B $ctxLE $repoLE $seamLf $provLf
Expect-StopResult 'N-S3B-LEDGER-FAILURE' $resLf.stop 'LEDGER_FAILURE' 'BREAKER_TRIP' $runLE $dirLE
Expect-Value 'N-S3B-LEDGER-FAILURE-NO-DISPATCH' '0' { $script:sbLfSeam }
Expect-Value 'N-S3B-LEDGER-FAILURE-NO-REPAIR' 'True' { [bool](([System.IO.File]::ReadAllText($ledPathLE)) -ceq $ledBytesLE) }

# =============================================================================
# N-S3B-FIX-ESCAPES-DENIED : the auto-generated fix dispatch lands on a DENIED
# path => the frozen dispatch guard fires INSIDE the wrapper's fix path
# =============================================================================
$runFE = New-RunRoot; $repoFE = New-AppRepo 'repo_s3b_fe'; $dirFE = New-NotifyDir 's3b_fe'
$ctxFE = New-Ctx $runFE 's3b-fe' $dirFE 0 1
$wSBfe = New-SlotWorld 'slot_s3b_fe_r0' $runFE -RoundId 'round-0' -Recommendation 'NEEDS-MORE'
$script:sbFeRoot = $wSBfe.root
$script:sbFeSeam = 0
# the builder edits app/frozen.txt (inside approved => three-branch clean), so the
# auto-generated fix dispatch's ProposedEdits = the ACTUAL changed set = a path the
# caller's deny contract forbids => STOP DENIED_PATH at the fix dispatch.
$seamFe = { param($info) $script:sbFeSeam++; Set-Content -LiteralPath (Join-Path $info.repo_root 'app\frozen.txt') -Value 'do not thaw' -Encoding Ascii }
$provFe = { param($q) return @{ end_report_path = (Get-SlotWorldEr $script:sbFeRoot); session_root = $script:sbFeRoot } }
$resFe = Invoke-ConvergeS3B $ctxFE $repoFE $seamFe $provFe @{ DeniedPaths = @('app/frozen.txt') }
Expect-StopResult 'N-S3B-FIX-ESCAPES-DENIED' $resFe.stop 'DENIED_PATH' 'ESCALATION_STOP' $runFE $dirFE
Expect-Value 'N-S3B-FIX-ESCAPES-NO-FIX-DISPATCH' '1' { $script:sbFeSeam }   # round 0 only; the denied fix never reached the seam
Expect-Value 'N-S3B-FIX-ESCAPES-COUNTS' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runFE
  $led = Read-NeoAttemptLedger -RunRoot $runFE
  [bool](($rows.Count -eq 2) -and ($led.Count -eq 2))   # non-GO row + STOP row == initial + landed fix entry
}

# =============================================================================
# N-S3B-BUILD-ESCAPES-OUTSIDE : a build landing outside ApprovedPaths => the
# frozen three-branch gate fires INSIDE the wrapper's round path
# =============================================================================
$runBE = New-RunRoot; $repoBE = New-AppRepo 'repo_s3b_be'; $dirBE = New-NotifyDir 's3b_be'
$ctxBE = New-Ctx $runBE 's3b-be' $dirBE 0 1
$seamBe = { param($info)
  $d = Join-Path $info.repo_root 'stray'
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  Set-Content -LiteralPath (Join-Path $d 'evil.txt') -Value 'outside approved' -Encoding Ascii
}
$provBe = { param($q) throw 'audit provider must never be reached on a three-branch stop' }
$resBe = Invoke-ConvergeS3B $ctxBE $repoBE $seamBe $provBe
Expect-StopResult 'N-S3B-BUILD-ESCAPES-OUTSIDE' $resBe.stop 'OUTSIDE_APPROVED' 'ESCALATION_STOP' $runBE $dirBE
Expect-Value 'N-S3B-BUILD-ESCAPES-COUNTS' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runBE
  $led = Read-NeoAttemptLedger -RunRoot $runBE
  [bool](($rows.Count -eq 1) -and ($led.Count -eq 1))
}

# =============================================================================
# N-S3B-ONE-ROW-PER-ROUND : a STOP round inside the wrapper yields EXACTLY ONE
# row (the round core's write-ahead row) - the wrapper never double-records
# =============================================================================
$runOR = New-RunRoot; $repoOR = New-AppRepo 'repo_s3b_or'; $dirOR = New-NotifyDir 's3b_or'
$ctxOR = New-Ctx $runOR 's3b-or' $dirOR 0 1
$seamOr = { param($info) }   # deliberate no-op builder => EMPTY_CHANGED_SET inside the round core
$provOr = { param($q) throw 'audit provider must never be reached on an empty diff' }
$resOr = Invoke-ConvergeS3B $ctxOR $repoOR $seamOr $provOr
Expect-StopResult 'N-S3B-STOPROUND-SURFACED' $resOr.stop 'EMPTY_CHANGED_SET' 'ESCALATION_STOP' $runOR $dirOR
Expect-Value 'N-S3B-ONE-ROW-PER-ROUND' '1' { $r = Read-NeoIterationManifest -RunRoot $runOR; $r.Count }
Expect-Value 'P-S3B-STOP-ENVELOPE' 'True' {
  # the converge envelope carries the round core's stop result UNCHANGED
  [bool]($resOr.stopped -and (-not $resOr.converged) -and $resOr.stop.stopped `
    -and ([string]$resOr.stop.reason_code -ceq 'EMPTY_CHANGED_SET'))
}

# =============================================================================
# N-S3B-SEAM-NOT-AUTHORITY : throwing seam => routed STOP with a row; null seam
# => STOP fail-closed BEFORE any ledger write or dispatch
# =============================================================================
$runST = New-RunRoot; $repoST = New-AppRepo 'repo_s3b_st'; $dirST = New-NotifyDir 's3b_st'
$ctxST = New-Ctx $runST 's3b-st' $dirST 0 1
$seamSt = { param($info) throw 'builder sub-process exploded' }
$provSt = { param($q) throw 'audit provider must never be reached on a seam failure' }
$resSt = Invoke-ConvergeS3B $ctxST $repoST $seamSt $provSt
Expect-StopResult 'N-S3B-SEAM-THROWS' $resSt.stop 'BUILDER_SEAM_FAILED' 'ESCALATION_STOP' $runST $dirST
Expect-Value 'N-S3B-SEAM-THROWS-COUNTS' 'True' {
  # the write-ahead initial entry landed BEFORE the seam ran; the STOP row is the
  # round's ONE row => counts stay aligned even on a seam failure.
  $rows = Read-NeoIterationManifest -RunRoot $runST
  $led = Read-NeoAttemptLedger -RunRoot $runST
  [bool](($rows.Count -eq 1) -and ($led.Count -eq 1) -and (($resSt.stop.detail) -like '*builder sub-process exploded*'))
}
$runSN = New-RunRoot; $repoSN = New-AppRepo 'repo_s3b_sn'; $dirSN = New-NotifyDir 's3b_sn'
$ctxSN = New-Ctx $runSN 's3b-sn' $dirSN 0 1
$resSn = Invoke-ConvergeS3B $ctxSN $repoSN $null ({ param($q) throw 'never' })
Expect-StopResult 'N-S3B-SEAM-NULL' $resSn.stop 'BUILDER_SEAM_FAILED' 'ESCALATION_STOP' $runSN $dirSN
Expect-Value 'N-S3B-SEAM-NULL-NO-LEDGER' 'True' {
  # fail-closed BEFORE any attempt was counted or dispatched
  [bool](-not (Test-Path -LiteralPath (Resolve-NeoRunStatePath $runSN 'attempt_ledger.jsonl')))
}

# =============================================================================
# N-S3B-RUNID-SINGLE-READ : ONE run-manifest read per stop-path row; a manifest
# mutated AFTER the dry-run read can no longer diverge the row's run_id; a
# forged -RunId row lands but is REJECTED at the very next read; blank -RunId
# falls back to the byte-equivalent disk read
# =============================================================================
$runRI = New-RunRoot; $dirRI = New-NotifyDir 's3b_runid'
$script:riManifestPath = Resolve-NeoRunStatePath $runRI 'run_manifest.json'
$script:riOrigManifestJson = [System.IO.File]::ReadAllText($script:riManifestPath)
$riOrigRunId = [string](Get-NeoProp (Read-NeoJsonFile $script:riManifestPath) 'run_id')
$script:riOrigRunId = $riOrigRunId
$script:riOrigRM = ${function:Read-NeoRunManifest}
$script:riReads = 0
# COUNTING + TAMPERING shim: counts every Read-NeoRunManifest, and IMMEDIATELY
# AFTER the first (dry-run) read mutates the persisted run_id ON DISK - on the old
# two-read code path the written row would have diverged; the single-read path is
# immune by construction (no second read exists).
${function:Read-NeoRunManifest} = {
  param([Parameter(Mandatory = $true)][string]$RunRoot)
  $script:riReads++
  $res = & $script:riOrigRM -RunRoot $RunRoot
  if ($script:riReads -eq 1) {
    $t = $script:riOrigManifestJson -replace $script:riOrigRunId, 'neo-run-tampered'
    [System.IO.File]::WriteAllText($script:riManifestPath, $t)
  }
  return $res
}
$stopRI = $null
$riShimErr = ''
try { $stopRI = Complete-NeoLoopRoundStop -Context (New-Ctx $runRI 's3b-runid' $dirRI) -ReasonCode 'CLASSIFIER_ERROR' -Detail 'single-read probe' -RoundData @{} }
catch { $riShimErr = $_.Exception.Message }
finally {
  ${function:Read-NeoRunManifest} = $script:riOrigRM
  [System.IO.File]::WriteAllText($script:riManifestPath, $script:riOrigManifestJson)
}
Expect-Value 'N-S3B-RUNID-SINGLE-READ-ONE-READ' '1' { if ($riShimErr) { "shim error: $riShimErr" } else { $script:riReads } }
Expect-Value 'N-S3B-RUNID-SINGLE-READ-IMMUNE' 'True' {
  [bool](($null -ne $stopRI) -and (([string](Get-NeoProp $stopRI.manifest_entry 'run_id')) -ceq $riOrigRunId))
}
Expect-Value 'P-S3B-RUNID-READBACK' '1' { $r = Read-NeoIterationManifest -RunRoot $runRI; $r.Count }
$runRFa = New-RunRoot
Expect-Ok 'P-S3B-RUNID-FORGED-ROW-LANDS' {
  # compensating control (a) is trust, not physics: an engine-internal caller CAN
  # stamp a foreign run_id and the append itself succeeds ...
  [void](Add-NeoIterationManifestEntry -RunRoot $runRFa -Fields (New-RowFields ("s3a-$tag-forge") 0) -RunId 'neo-run-forged')
  'forged -RunId row appended (write-then-verify checks round-trip, not binding)'
}
Expect-Block 'N-S3B-RUNID-FORGED-READ-REJECT' 'LEDGER_FAILURE' {
  # ... and compensating control (b) catches it at the VERY NEXT READ, fail-closed.
  Read-NeoIterationManifest -RunRoot $runRFa | Out-Null
}
$runRFb = New-RunRoot
Expect-Value 'P-S3B-RUNID-BLANK-FALLBACK' '1' {
  # blank -RunId == byte-equivalent prior behavior: the writer reads the persisted
  # manifest itself and the row binds to the REAL run_id (read-back proves it).
  [void](Add-NeoIterationManifestEntry -RunRoot $runRFb -Fields (New-RowFields ("s3a-$tag-blank") 0) -RunId '')
  $r = Read-NeoIterationManifest -RunRoot $runRFb; $r.Count
}

# =============================================================================
# ======================= S3c: END ASSEMBLY (I7/N3 + XC2 + human-END) =========
# =============================================================================
# Proves orch_loop.ps1 END assembly fails closed on the S3c surface (spec sec-5
# 206-211 + the 2026-07-07b STOP-PATH clarifier 216-222 + sec-0 NB-4):
#   - N-S3C-TRAIL-GAP / -ASYMMETRY-EXACT / -PRELEDGER-DISCRIMINATOR / -FORGED-RUNID
#     : the I7/N3 reconciliation (R0-R4) incl. the mechanical pre-ledger class (PA-1).
#   - N-S3C-CAP-CONSISTENCY (PA-6, both directions).
#   - N-S3C-SPAWN-GOV-EVIDENCE (PA-5): audited round spawn + governance evidence exact.
#   - N-S3C-XC2-DELTA / -REF-FORGERY / -MEMBER-OMISSION / -PATH (XC2 X1-X4, PA-3/PA-4/XC1).
#   - N-S3C-OUTCOME-CONSISTENCY (PR-1).
#   - N-S3C-STOP-BEFORE-GO (PR-2): END ASSEMBLES on a never-GO slice (NO_GO_BUNDLE).
#   - N-S3C-ENDGATE-CLASS-DISCIPLINE / -NEVER-AUTHORITY: F5 -HumanEndClass discipline.
#   - P-S3C-CLEAN-END: a full converged run assembles clean => SESSION_END once.
# STRUCTURALLY LIVE-SEND-INCAPABLE: every context is New-Ctx (notify_live_send=$false
# + scratch TestModeDir); the live-send token appears NOWHERE in this file.

# helper: a mechanical PRE-LEDGER STOP row (classification STOPPED + all lanes at the
# honest NOT_EVALUATED sentinels + a non-NONE breaker/boundary stop_reason_code). This
# is the on-disk shape Complete-NeoLoopRoundStop writes for a pre-dispatch STOP.
function New-PreLedgerStopRowFields([string]$slice, [int]$round, [string]$stopCode) {
  return @{
    slice_id = $slice; round = $round; attempt_seq = ($round + 1)
    baseline_head_sha = 'NOT_EVALUATED'; baseline_tree_hash = 'NOT_EVALUATED'
    changed_count = 0; changed_paths_hash = 'NOT_EVALUATED'
    classification = 'STOPPED'; findings_summary = 'pre-ledger stop'
    auditor_slot_status = 'NOT_EVALUATED'; auditor_slot_recommendation = 'NOT_EVALUATED'
    auditor_identity = 'NOT_EVALUATED'; external_lane_status = 'NOT_EVALUATED'
    effective_seam_tier = 'NOT_EVALUATED'; cap_events = @()
    stop_reason_code = $stopCode; notify_gate_class = 'ESCALATION_STOP'
    notify_sent = $false; notify_deduped = $false; notify_refused = $false
    notify_reason = ''; timestamp_utc = $TS
  }
}
# a completed NON-GO (NEEDS-MORE) fix round row: THREE_BRANCH_CLEAN + SATISFIED slot +
# a real non-GO verdict + non-sentinel lanes (the shape S3b's caller-records path writes
# for an iterate round). Used to build cap-boundary trails where only the final round is
# the refused STOP (never multiple GO rounds).
function New-NonGoRowFields([string]$slice, [int]$round) {
  $f = New-RowFields $slice $round
  $f['auditor_slot_recommendation'] = 'NEEDS-MORE'
  return $f
}
# a fresh governed mirror + pin for S3c XC2 governance-evidence checks (untampered).
$mirrorSC = New-GovMirror 'gov_s3c'
$pinSC = Pin-GovMirror $mirrorSC 'pin_s3c.json'

# Build a REAL converged single-round GO run end-to-end (reusing the S3b converge
# helper): attempt ledger (initial round 0) + iteration manifest (GO row) + spawn
# ledger (round-0 correlated) + the on-disk AUDIT_BUNDLE. Returns the run root, the
# GO slice id, the session root (=bundle SessionRoot) and the derived bundle rel.
function New-ConvergedGoRun([string]$case) {
  $run = New-RunRoot; $repo = New-AppRepo ("repo_" + $case); $dir = New-NotifyDir $case
  $ctx = New-Ctx $run $case $dir 0 1
  $slice = $ctx.slice_id
  $w = New-SlotWorld ("slot_" + $case) $run -RoundId 'round-0' -Recommendation 'GO'
  $script:scSeamRoot = $w.root
  $seam = { param($info) Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit ' + $info.round) -Encoding Ascii; return 'ignored' }
  $prov = { param($q) return @{ end_report_path = (Get-SlotWorldEr $script:scSeamRoot); session_root = $script:scSeamRoot } }
  $res = Invoke-ConvergeS3B $ctx $repo $seam $prov
  # a governance_manifest.json under RunRoot is the PA-5 governance evidence.
  $govPin = Build-NeoGovManifest -GovernedRoot $mirrorSC -DerivedAt $TS
  Write-NeoJsonFile (Resolve-NeoRunStatePath $run 'governance_manifest.json') $govPin
  return @{ run = $run; slice = $slice; ctx = $ctx; notifyDir = $dir; sessionRoot = $w.root; bundleRel = $w.bundleRel; res = $res; runId = ([string](Get-NeoProp (Read-NeoRunManifest -RunRoot $run) 'run_id')) }
}
# the bundle's audited members (rels) become the XC2 final surfaces, resolved under
# the session root. Reads the on-disk AUDIT_BUNDLE the converged run produced.
function Get-BundleFinalSurfaces([string]$sessionRoot, [string]$bundleRel) {
  $full = Assert-NeoContained $sessionRoot $bundleRel
  $bundle = Read-NeoJsonFile $full
  $out = @()
  foreach ($m in @($bundle.allowlist)) {
    $rel = [string](Get-NeoProp $m 'path')
    $out += @{ rel = $rel; path = (Assert-NeoContained $sessionRoot $rel) }
  }
  return @($out)
}

# ----------------------------------------------------------------------------
# N-S3C-TRAIL-GAP : attempt-without-row / non-STOP-row-without-entry / round hole
# ----------------------------------------------------------------------------
# (a) an attempt entry with NO manifest row.
$runTG1 = New-RunRoot; $tgSlice1 = "s3c-$tag-tg1"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runTG1 -SliceId $tgSlice1 -Round 0 -Kind 'initial' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runTG1 -Fields (New-RowFields $tgSlice1 0))   # round 0 aligned
[void](Add-NeoAttemptLedgerEntry -RunRoot $runTG1 -SliceId $tgSlice1 -Round 1 -Kind 'fix' -Timestamp $TS)   # round 1 entry, NO row
$runTG1Id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runTG1) 'run_id')
Expect-Block 'N-S3C-TRAIL-GAP-ATTEMPT-NO-ROW' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runTG1 -ExpectedRunId $runTG1Id -SliceIds @($tgSlice1) | Out-Null
}
# (b) a NON-STOP row with NO attempt entry.
$runTG2 = New-RunRoot; $tgSlice2 = "s3c-$tag-tg2"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runTG2 -SliceId $tgSlice2 -Round 0 -Kind 'initial' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runTG2 -Fields (New-RowFields $tgSlice2 0))
[void](Add-NeoIterationManifestEntry -RunRoot $runTG2 -Fields (New-RowFields $tgSlice2 1))   # round-1 GO row, NO attempt entry
$runTG2Id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runTG2) 'run_id')
Expect-Block 'N-S3C-TRAIL-GAP-NONSTOP-ROW-NO-ENTRY' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runTG2 -ExpectedRunId $runTG2Id -SliceIds @($tgSlice2) | Out-Null
}
# (c) a ROUND HOLE (rows at rounds 0 and 2 present, 1 missing). Both are pre-ledger STOP
# rows (no attempt entries needed), so R3 (contiguous 0..N) is what fires, in isolation
# from the attempt-ledger round contract.
$runTG3 = New-RunRoot; $tgSlice3 = "s3c-$tag-tg3"
[void](Add-NeoIterationManifestEntry -RunRoot $runTG3 -Fields (New-PreLedgerStopRowFields $tgSlice3 0 'CAP_WALL_CLOCK'))
[void](Add-NeoIterationManifestEntry -RunRoot $runTG3 -Fields (New-PreLedgerStopRowFields $tgSlice3 2 'CAP_WALL_CLOCK'))   # hole at round 1
$runTG3Id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runTG3) 'run_id')
Expect-Block 'N-S3C-TRAIL-GAP-ROUND-HOLE' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runTG3 -ExpectedRunId $runTG3Id -SliceIds @($tgSlice3) | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3C-TRAIL-ASYMMETRY-EXACT : a legit pre-ledger STOP row PASSES; reason 'NONE' => BLOCK
# ----------------------------------------------------------------------------
# a round-0 wall-clock-trip pre-ledger STOP: manifest STOP row, NO attempt entry.
$runAS = New-RunRoot; $asSlice = "s3c-$tag-as"
[void](Add-NeoIterationManifestEntry -RunRoot $runAS -Fields (New-PreLedgerStopRowFields $asSlice 0 'CAP_WALL_CLOCK'))
$runASId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runAS) 'run_id')
Expect-Value 'N-S3C-TRAIL-ASYMMETRY-EXACT-PASS' 'True' {
  $r = Assert-NeoLoopEndTrail -RunRoot $runAS -ExpectedRunId $runASId -SliceIds @($asSlice)
  [bool]($r.ok -and (@($r.slices[0].pre_ledger_rounds) -contains 0) -and ($null -eq $r.slices[0].go_round))
}
# the SAME row with stop_reason_code 'NONE' => BLOCK (class exact, nothing wider). The
# schema pattern forbids literal 'NONE'? no - 'NONE' matches ^[A-Z][A-Z0-9_]*$, so it
# writes; the R4 semantic guard is what refuses it.
$runAS2 = New-RunRoot; $asSlice2 = "s3c-$tag-as2"
$asBad = New-PreLedgerStopRowFields $asSlice2 0 'NONE'
[void](Add-NeoIterationManifestEntry -RunRoot $runAS2 -Fields $asBad)
$runAS2Id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runAS2) 'run_id')
Expect-Block 'N-S3C-TRAIL-ASYMMETRY-EXACT-NONE-BLOCKS' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runAS2 -ExpectedRunId $runAS2Id -SliceIds @($asSlice2) | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3C-TRAIL-PRELEDGER-DISCRIMINATOR (PA-1): unmatched POST-ledger STOP => BLOCK
# ----------------------------------------------------------------------------
# a STOPPED row with a real reason_code AND filled (non-sentinel) lanes but NO attempt
# entry - this is what an unmatched POST-ledger STOP would look like on disk; the
# mechanical discriminator (lanes-sentinelled clause) refuses it as a gap.
$runPD = New-RunRoot; $pdSlice = "s3c-$tag-pd"
$pdRow = New-PreLedgerStopRowFields $pdSlice 0 'AUDITOR_SLOT_UNSATISFIED'
$pdRow['auditor_slot_status'] = 'BLOCKED'          # a filled lane => NOT the pre-ledger sentinel shape
$runPDId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runPD) 'run_id')
[void](Add-NeoIterationManifestEntry -RunRoot $runPD -Fields $pdRow)
Expect-Block 'N-S3C-TRAIL-PRELEDGER-DISCRIMINATOR' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runPD -ExpectedRunId $runPDId -SliceIds @($pdSlice) | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3C-TRAIL-FORGED-RUNID (PA-2): foreign-run ENTRY => BLOCK; foreign-run ROW => BLOCK
# ----------------------------------------------------------------------------
# foreign-run manifest ROW (forged run_id) => the frozen reader BLOCKs on the run_id bind.
$runFR = New-RunRoot; $frSlice = "s3c-$tag-fr"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runFR -SliceId $frSlice -Round 0 -Kind 'initial' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runFR -Fields (New-RowFields $frSlice 0) -RunId 'neo-run-forged')  # forged row lands
$runFRId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runFR) 'run_id')
Expect-Block 'N-S3C-TRAIL-FORGED-RUNID-ROW' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runFR -ExpectedRunId $runFRId -SliceIds @($frSlice) | Out-Null
}
# a caller-supplied -ExpectedRunId that disagrees with the persisted run manifest => BLOCK
# (PA-2 check==use at the END boundary).
$runFR2 = New-RunRoot; $frSlice2 = "s3c-$tag-fr2"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runFR2 -SliceId $frSlice2 -Round 0 -Kind 'initial' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runFR2 -Fields (New-RowFields $frSlice2 0))
Expect-Block 'N-S3C-TRAIL-FORGED-RUNID-EXPECTED-MISMATCH' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runFR2 -ExpectedRunId 'neo-run-not-this-one' -SliceIds @($frSlice2) | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3C-CAP-CONSISTENCY (PA-6): refused+non-CAP row => BLOCK; CAP_* row w/o refused => BLOCK
# ----------------------------------------------------------------------------
# a refused attempt entry (reason CAP_FIX_ROUNDS) whose paired row carries a non-CAP stop.
$runCC = New-RunRoot; $ccSlice = "s3c-$tag-cc"
# build 3 accepted fix entries so the 4th (round 4) is refused. Round counting: round 0
# initial, rounds 1..3 fix accepted, round 4 fix refused (post_increment > cap 3).
[void](Add-NeoAttemptLedgerEntry -RunRoot $runCC -SliceId $ccSlice -Round 0 -Kind 'initial' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runCC -Fields (New-NonGoRowFields $ccSlice 0))
for ($r = 1; $r -le 3; $r++) {
  [void](Add-NeoAttemptLedgerEntry -RunRoot $runCC -SliceId $ccSlice -Round $r -Kind 'fix' -Timestamp $TS)
  [void](Add-NeoIterationManifestEntry -RunRoot $runCC -Fields (New-NonGoRowFields $ccSlice $r))
}
$ccRef = Add-NeoAttemptLedgerEntry -RunRoot $runCC -SliceId $ccSlice -Round 4 -Kind 'fix' -Timestamp $TS   # refused
# paired row carries a NON-CAP stop_reason_code => PA-6 BLOCK.
$ccBadRow = New-PreLedgerStopRowFields $ccSlice 4 'CLASSIFIER_ERROR'   # STOPPED but not CAP_*
$ccBadRow['attempt_seq'] = [int](Get-NeoProp $ccRef.entry 'seq')
[void](Add-NeoIterationManifestEntry -RunRoot $runCC -Fields $ccBadRow)
$runCCId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runCC) 'run_id')
Expect-Value 'N-S3C-CAP-BOUNDARY-REFUSED' 'True' { [bool]$ccRef.refused }
Expect-Block 'N-S3C-CAP-CONSISTENCY-REFUSED-NONCAP' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runCC -ExpectedRunId $runCCId -SliceIds @($ccSlice) | Out-Null
}
# a CAP_* stop_reason_code row whose attempt entry is NOT refused => BLOCK (other direction).
$runCC2 = New-RunRoot; $ccSlice2 = "s3c-$tag-cc2"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runCC2 -SliceId $ccSlice2 -Round 0 -Kind 'initial' -Timestamp $TS)  # NOT refused
$cc2Row = New-PreLedgerStopRowFields $ccSlice2 0 'CAP_FIX_ROUNDS'   # CAP_* row
$cc2Row['attempt_seq'] = 1
[void](Add-NeoIterationManifestEntry -RunRoot $runCC2 -Fields $cc2Row)
$runCC2Id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runCC2) 'run_id')
Expect-Block 'N-S3C-CAP-CONSISTENCY-CAPROW-NOTREFUSED' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runCC2 -ExpectedRunId $runCC2Id -SliceIds @($ccSlice2) | Out-Null
}
# CONTROL: the proper cap boundary (refused entry + CAP_* STOP row aligned) PASSES.
$runCC3 = New-RunRoot; $ccSlice3 = "s3c-$tag-cc3"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runCC3 -SliceId $ccSlice3 -Round 0 -Kind 'initial' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runCC3 -Fields (New-NonGoRowFields $ccSlice3 0))
for ($r = 1; $r -le 3; $r++) {
  [void](Add-NeoAttemptLedgerEntry -RunRoot $runCC3 -SliceId $ccSlice3 -Round $r -Kind 'fix' -Timestamp $TS)
  [void](Add-NeoIterationManifestEntry -RunRoot $runCC3 -Fields (New-NonGoRowFields $ccSlice3 $r))
}
$cc3Ref = Add-NeoAttemptLedgerEntry -RunRoot $runCC3 -SliceId $ccSlice3 -Round 4 -Kind 'fix' -Timestamp $TS
$cc3Row = New-PreLedgerStopRowFields $ccSlice3 4 'CAP_FIX_ROUNDS'
$cc3Row['attempt_seq'] = [int](Get-NeoProp $cc3Ref.entry 'seq')
[void](Add-NeoIterationManifestEntry -RunRoot $runCC3 -Fields $cc3Row)
$runCC3Id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runCC3) 'run_id')
Expect-Value 'N-S3C-CAP-CONSISTENCY-CONTROL-PASS' 'True' {
  $r = Assert-NeoLoopEndTrail -RunRoot $runCC3 -ExpectedRunId $runCC3Id -SliceIds @($ccSlice3)
  [bool]($r.ok -and ($null -eq $r.slices[0].go_round))
}

# ----------------------------------------------------------------------------
# N-S3C-OUTCOME-CONSISTENCY (PR-1): GO row with NOT_EVALUATED lanes => BLOCK;
#   STOPPED row with mismatched class/reason => BLOCK; legit pre-ledger STOP PASSES
# ----------------------------------------------------------------------------
# a completed round row declaring GO but carrying a NOT_EVALUATED lane.
$runOC = New-RunRoot; $ocSlice = "s3c-$tag-oc"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runOC -SliceId $ocSlice -Round 0 -Kind 'initial' -Timestamp $TS)
$ocRow = New-RowFields $ocSlice 0
$ocRow['effective_seam_tier'] = 'NOT_EVALUATED'    # GO row but a sentinel lane => PR-1 BLOCK
[void](Add-NeoIterationManifestEntry -RunRoot $runOC -Fields $ocRow)
$runOCId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runOC) 'run_id')
Expect-Block 'N-S3C-OUTCOME-CONSISTENCY-GO-NOTEVAL' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runOC -ExpectedRunId $runOCId -SliceIds @($ocSlice) | Out-Null
}
# a STOPPED row carrying RISK_ESCALATION but classification 'STOPPED' (not THREE_BRANCH)
# => PR-1 BLOCK (the escalation fires only after the three-branch stage). Give it an
# attempt entry so it is a post-ledger STOP that must be class-consistent.
$runOC2 = New-RunRoot; $ocSlice2 = "s3c-$tag-oc2"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runOC2 -SliceId $ocSlice2 -Round 0 -Kind 'initial' -Timestamp $TS)
$oc2Row = New-PreLedgerStopRowFields $ocSlice2 0 'RISK_ESCALATION'   # classification STOPPED + RISK_ESCALATION mismatch
[void](Add-NeoIterationManifestEntry -RunRoot $runOC2 -Fields $oc2Row)
$runOC2Id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runOC2) 'run_id')
Expect-Block 'N-S3C-OUTCOME-CONSISTENCY-STOP-CLASS-MISMATCH' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runOC2 -ExpectedRunId $runOC2Id -SliceIds @($ocSlice2) | Out-Null
}
# CONTROL: a legitimately-sentineled pre-ledger STOP row PASSES (already covered by
# ASYMMETRY-EXACT-PASS; this asserts it is NOT flagged by the PR-1 lane check either).
Expect-Value 'N-S3C-OUTCOME-CONSISTENCY-PRELEDGER-CONTROL' 'True' {
  $r = Assert-NeoLoopEndTrail -RunRoot $runAS -ExpectedRunId $runASId -SliceIds @($asSlice)
  [bool]$r.ok
}

# ----------------------------------------------------------------------------
# N-S3CF-PRELEDGER-REASON-SET (S3c-FIX F1): an attempt-less, fully-sentinelled STOP row
#   carrying a POST-ledger-only reason code is a FORGERY => BLOCK. Pre-fix the discriminator
#   accepted ANY non-blank non-'NONE' code; now the code MUST be in the ENUMERATED
#   pre-ledger-CAPABLE set {BUILDER_SEAM_FAILED, CLASSIFIER_ERROR, LEDGER_FAILURE,
#   CAP_WALL_CLOCK, CAPS_INVALID}. Positive control: each pre-ledger code PASSES.
# ----------------------------------------------------------------------------
# (a) the SC repro: SPAWN_UNCORRELATED (a post-GO aggregation code) on an attempt-less
#     sentinelled row => BLOCK (it is NOT pre-ledger-capable).
$runF1 = New-RunRoot; $f1Slice = "s3c-$tag-f1a"
[void](Add-NeoIterationManifestEntry -RunRoot $runF1 -Fields (New-PreLedgerStopRowFields $f1Slice 0 'SPAWN_UNCORRELATED'))
$runF1Id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runF1) 'run_id')
Expect-Block 'N-S3CF-PRELEDGER-REASON-SET' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runF1 -ExpectedRunId $runF1Id -SliceIds @($f1Slice) | Out-Null
}
# (b) a three-branch/aggregation-only code (AUDITOR_SLOT_UNSATISFIED) => BLOCK too.
$runF1b = New-RunRoot; $f1bSlice = "s3c-$tag-f1b"
[void](Add-NeoIterationManifestEntry -RunRoot $runF1b -Fields (New-PreLedgerStopRowFields $f1bSlice 0 'AUDITOR_SLOT_UNSATISFIED'))
$runF1bId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runF1b) 'run_id')
Expect-Block 'N-S3CF-PRELEDGER-REASON-SET-3BR' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runF1b -ExpectedRunId $runF1bId -SliceIds @($f1bSlice) | Out-Null
}
# POSITIVE CONTROL: each ENUMERATED pre-ledger code on an attempt-less sentinelled row
#   PASSES (the row is a legitimate pre-ledger STOP and is recorded in pre_ledger_rounds).
foreach ($plCode in @('BUILDER_SEAM_FAILED', 'CLASSIFIER_ERROR', 'LEDGER_FAILURE', 'CAP_WALL_CLOCK', 'CAPS_INVALID')) {
  $runF1c = New-RunRoot; $f1cSlice = "s3c-$tag-f1c-$plCode"
  [void](Add-NeoIterationManifestEntry -RunRoot $runF1c -Fields (New-PreLedgerStopRowFields $f1cSlice 0 $plCode))
  $runF1cId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runF1c) 'run_id')
  Expect-Value "P-S3CF-PRELEDGER-REASON-SET-CONTROL-$plCode" 'True' {
    $r = Assert-NeoLoopEndTrail -RunRoot $runF1c -ExpectedRunId $runF1cId -SliceIds @($f1cSlice)
    [bool]($r.ok -and (@($r.slices[0].pre_ledger_rounds) -contains 0) -and ($null -eq $r.slices[0].go_round))
  }
}

# ----------------------------------------------------------------------------
# N-S3CF-POST-GO-ROW (S3c-FIX F2): a valid GO round 0 + a forged round-1 row (STOP or
#   non-STOP) => BLOCK. Convergence breaks on the FIRST GO; no further round is emitted, so
#   any row recorded after the GO round is a trail inconsistency.
# ----------------------------------------------------------------------------
# (a) forged post-GO STOP row.
$runF2a = New-RunRoot; $f2aSlice = "s3c-$tag-f2a"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runF2a -SliceId $f2aSlice -Round 0 -Kind 'initial' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runF2a -Fields (New-RowFields $f2aSlice 0))   # GO round 0
[void](Add-NeoIterationManifestEntry -RunRoot $runF2a -Fields (New-PreLedgerStopRowFields $f2aSlice 1 'CAP_WALL_CLOCK'))   # forged post-GO STOP
$runF2aId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runF2a) 'run_id')
Expect-Block 'N-S3CF-POST-GO-ROW-STOP' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runF2a -ExpectedRunId $runF2aId -SliceIds @($f2aSlice) | Out-Null
}
# (b) forged post-GO NON-STOP row (a second completed round after GO). It carries an
#     attempt entry so it is not caught by the pre-ledger clauses - only F2 finality stops it.
$runF2b = New-RunRoot; $f2bSlice = "s3c-$tag-f2b"
[void](Add-NeoAttemptLedgerEntry -RunRoot $runF2b -SliceId $f2bSlice -Round 0 -Kind 'initial' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runF2b -Fields (New-RowFields $f2bSlice 0))   # GO round 0
[void](Add-NeoAttemptLedgerEntry -RunRoot $runF2b -SliceId $f2bSlice -Round 1 -Kind 'fix' -Timestamp $TS)
[void](Add-NeoIterationManifestEntry -RunRoot $runF2b -Fields (New-NonGoRowFields $f2bSlice 1))   # forged post-GO non-STOP round
$runF2bId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runF2b) 'run_id')
Expect-Block 'N-S3CF-POST-GO-ROW-NONSTOP' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runF2b -ExpectedRunId $runF2bId -SliceIds @($f2bSlice) | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3C-SPAWN-GOV-EVIDENCE (PA-5): audited round missing spawn/gov evidence => BLOCK
# ----------------------------------------------------------------------------
# Build a converged GO run, then drive XC2 (which requires the spawn correlation for
# the GO round). CONTROL first: present+readable spawn + gov evidence PASSES.
$goSGE = New-ConvergedGoRun "s3c_sge"
$sgeSurfaces = Get-BundleFinalSurfaces $goSGE.sessionRoot $goSGE.bundleRel
$sgeFS = @(@{ slice_id = $goSGE.slice; session_root = $goSGE.sessionRoot; final_surfaces = $sgeSurfaces })
# S3c-FIX F3: XC2 takes -SliceIds and RE-DERIVES the trail itself (no caller TrailResult).
Expect-Value 'N-S3C-SPAWN-GOV-EVIDENCE-CONTROL-PASS' 'True' {
  $r = Assert-NeoLoopFinalState -RunRoot $goSGE.run -ExpectedRunId $goSGE.runId -SliceIds @($goSGE.slice) -SliceFinalState $sgeFS
  [bool]($r.ok -and ([string]$r.slices[0].xc2 -ceq 'MATCHED'))
}
# missing spawn evidence for the GO round: corrupt the spawn ledger's round_id so the
# correlation for round-0 cannot be found => BLOCK SPAWN_UNCORRELATED.
$goSGE2 = New-ConvergedGoRun "s3c_sge2"
$sge2Surfaces = Get-BundleFinalSurfaces $goSGE2.sessionRoot $goSGE2.bundleRel
$sge2FS = @(@{ slice_id = $goSGE2.slice; session_root = $goSGE2.sessionRoot; final_surfaces = $sge2Surfaces })
# delete the spawn ledger entirely (missing spawn evidence).
Remove-Item -LiteralPath (Resolve-NeoRunStatePath $goSGE2.run 'spawn_ledger.jsonl') -Force
Expect-Block 'N-S3C-SPAWN-GOV-EVIDENCE-MISSING-SPAWN' 'SPAWN_UNCORRELATED' {
  Assert-NeoLoopFinalState -RunRoot $goSGE2.run -ExpectedRunId $goSGE2.runId -SliceIds @($goSGE2.slice) -SliceFinalState $sge2FS | Out-Null
}
# tampered governance-manifest evidence: overwrite governance_manifest.json with an
# invalid body => the frozen reader/validator BLOCKs (PA-5 checkable, not file-exists).
# (This is asserted at the END-gate level below where the gov evidence is read; here we
# prove Assert-NeoLoopEndTrail's own R7-style gov check is not yet reached - the gov
# manifest is validated inside the END gate assembly path in N-S3C-ENDGATE, so we cover
# the tampered-gov case via a direct schema-invalid read.)
$goSGE3 = New-ConvergedGoRun "s3c_sge3"
Set-Content -LiteralPath (Resolve-NeoRunStatePath $goSGE3.run 'governance_manifest.json') -Value '{ "not": "a valid governance manifest" }' -Encoding Ascii
Expect-Block 'N-S3C-SPAWN-GOV-EVIDENCE-TAMPERED-GOV' 'NEO-BLOCK' {
  $gm = Read-NeoJsonFile (Resolve-NeoRunStatePath $goSGE3.run 'governance_manifest.json')
  Assert-NeoValid $gm 'neo:governance_manifest' $index 'GOV_MANIFEST(END evidence)'
}

# ----------------------------------------------------------------------------
# N-S3C-XC2-DELTA : mutate one surface byte after the GO bundle => BLOCK; control PASS
# ----------------------------------------------------------------------------
$goXD = New-ConvergedGoRun "s3c_xd"
$xdSurfaces = Get-BundleFinalSurfaces $goXD.sessionRoot $goXD.bundleRel
$xdFS = @(@{ slice_id = $goXD.slice; session_root = $goXD.sessionRoot; final_surfaces = $xdSurfaces })
Expect-Value 'N-S3C-XC2-CONTROL-UNTOUCHED-PASS' 'True' {
  $r = Assert-NeoLoopFinalState -RunRoot $goXD.run -ExpectedRunId $goXD.runId -SliceIds @($goXD.slice) -SliceFinalState $xdFS
  [bool]($r.ok -and ([string]$r.slices[0].xc2 -ceq 'MATCHED') -and ([int]$r.slices[0].members_checked -ge 1))
}
# mutate one byte of the first audited member on disk => XC2 hash delta => BLOCK.
$xdMemberFull = [string]$xdSurfaces[0].path
Add-Content -LiteralPath $xdMemberFull -Value 'post-audit tamper' -Encoding Ascii
Expect-Block 'N-S3C-XC2-DELTA' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goXD.run -ExpectedRunId $goXD.runId -SliceIds @($goXD.slice) -SliceFinalState $xdFS | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3CF-SURFACE-PATH (S3c-FIX F4): a final_surfaces entry whose `path` does NOT resolve to
#   the session_root-contained location of its own `rel` is misleading evidence => BLOCK.
#   `path` is now LOAD-BEARING (asserted), not decoratively presence-checked-then-ignored.
# ----------------------------------------------------------------------------
$goSP = New-ConvergedGoRun "s3c_sp"
$spSurfaces = @(Get-BundleFinalSurfaces $goSP.sessionRoot $goSP.bundleRel)
# forge the first surface's `path` to a location that disagrees with its `rel` (a bogus
# absolute path), keeping the correct `rel` => F4 BLOCK.
$spBad = @($spSurfaces | ForEach-Object { @{ rel = $_.rel; path = $_.path } })
$spBad[0].path = 'S:/NEO_dev/NEO_SESSION/ss-loop/audit/NOT_THE_REL_LOCATION.txt'
$spBadFS = @(@{ slice_id = $goSP.slice; session_root = $goSP.sessionRoot; final_surfaces = $spBad })
Expect-Block 'N-S3CF-SURFACE-PATH' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goSP.run -ExpectedRunId $goSP.runId -SliceIds @($goSP.slice) -SliceFinalState $spBadFS | Out-Null
}
# CONTROL: the path that MATCHES its rel's contained location PASSES (path load-bearing but
# consistent). (Get-BundleFinalSurfaces already sets path = Assert-NeoContained sessRoot rel.)
$spGoodFS = @(@{ slice_id = $goSP.slice; session_root = $goSP.sessionRoot; final_surfaces = $spSurfaces })
Expect-Value 'P-S3CF-SURFACE-PATH-CONTROL' 'True' {
  $r = Assert-NeoLoopFinalState -RunRoot $goSP.run -ExpectedRunId $goSP.runId -SliceIds @($goSP.slice) -SliceFinalState $spGoodFS
  [bool]($r.ok -and ([string]$r.slices[0].xc2 -ceq 'MATCHED'))
}

# ----------------------------------------------------------------------------
# N-S3CF-XC2-FORGED-TRAIL (S3c-FIX F3): a run whose ledgers show a REAL GO round, invoked
#   via the new -SliceIds signature, RE-DERIVES the trail from disk and runs the REAL XC2
#   (never silently NO_GO_BUNDLE-skips a GO slice). The pre-fix forgery - a caller passing a
#   TrailResult with go_round=$null for a GO slice - is no longer even expressible: XC2 owns
#   the derivation. This asserts a GO run re-derives to a real go_round and MATCHES (not
#   NO_GO_BUNDLE).
# ----------------------------------------------------------------------------
$goFT = New-ConvergedGoRun "s3c_ft"
$ftSurfaces = Get-BundleFinalSurfaces $goFT.sessionRoot $goFT.bundleRel
$ftFS = @(@{ slice_id = $goFT.slice; session_root = $goFT.sessionRoot; final_surfaces = $ftSurfaces })
Expect-Value 'N-S3CF-XC2-FORGED-TRAIL-REDERIVES' 'True' {
  $r = Assert-NeoLoopFinalState -RunRoot $goFT.run -ExpectedRunId $goFT.runId -SliceIds @($goFT.slice) -SliceFinalState $ftFS
  # the self-derived trail carries a REAL go_round for the slice, and XC2 MATCHED it (a
  # never-NO_GO_BUNDLE outcome on a real GO slice); the trail is returned for evidence.
  [bool]($r.ok -and ([string]$r.slices[0].xc2 -ceq 'MATCHED') -and ($null -ne $r.trail) -and ($null -ne $r.trail.slices[0].go_round))
}

# ----------------------------------------------------------------------------
# N-S3C-XC2-REF-FORGERY (PA-3): caller ref stale/wrong => BLOCK
# ----------------------------------------------------------------------------
$goRF = New-ConvergedGoRun "s3c_rf"
$rfSurfaces = Get-BundleFinalSurfaces $goRF.sessionRoot $goRF.bundleRel
# a caller-supplied bundle_ref that does not match the spawn-ledger-derived ref => BLOCK.
$rfFS = @(@{ slice_id = $goRF.slice; session_root = $goRF.sessionRoot; final_surfaces = $rfSurfaces; caller_bundle_ref = './NEO_SESSION/ss-loop/audit/WRONG_BUNDLE.json' })
Expect-Block 'N-S3C-XC2-REF-FORGERY' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goRF.run -ExpectedRunId $goRF.runId -SliceIds @($goRF.slice) -SliceFinalState $rfFS | Out-Null
}
# CONTROL: the caller ref that MATCHES the derived ref PASSES.
$rfFS2 = @(@{ slice_id = $goRF.slice; session_root = $goRF.sessionRoot; final_surfaces = $rfSurfaces; caller_bundle_ref = $goRF.bundleRel })
Expect-Value 'N-S3C-XC2-REF-FORGERY-CONTROL-PASS' 'True' {
  $r = Assert-NeoLoopFinalState -RunRoot $goRF.run -ExpectedRunId $goRF.runId -SliceIds @($goRF.slice) -SliceFinalState $rfFS2
  [bool]($r.ok -and ([string]$r.slices[0].xc2 -ceq 'MATCHED'))
}

# ----------------------------------------------------------------------------
# N-S3C-XC2-MEMBER-OMISSION (PA-4): audited member omitted from final list => BLOCK
# ----------------------------------------------------------------------------
$goMO = New-ConvergedGoRun "s3c_mo"
$moSurfaces = @(Get-BundleFinalSurfaces $goMO.sessionRoot $goMO.bundleRel)
# omit the first audited member from the final surface list => BLOCK (no surface-omission).
$moPartial = @($moSurfaces | Select-Object -Skip 1)
$moFS = @(@{ slice_id = $goMO.slice; session_root = $goMO.sessionRoot; final_surfaces = $moPartial })
Expect-Block 'N-S3C-XC2-MEMBER-OMISSION' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goMO.run -ExpectedRunId $goMO.runId -SliceIds @($goMO.slice) -SliceFinalState $moFS | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3C-XC2-PATH : XC1 containment battery on the final-state paths
# ----------------------------------------------------------------------------
$goXP = New-ConvergedGoRun "s3c_xp"
# a traversal spelling in a final surface rel => Assert-NeoSafeRel BLOCK.
$xpBadTrav = @(@{ slice_id = $goXP.slice; session_root = $goXP.sessionRoot; final_surfaces = @(@{ rel = '../escape.txt'; path = 'x' }) })
Expect-Block 'N-S3C-XC2-PATH-TRAVERSAL' 'NEO-BLOCK' {
  Assert-NeoLoopFinalState -RunRoot $goXP.run -ExpectedRunId $goXP.runId -SliceIds @($goXP.slice) -SliceFinalState $xpBadTrav | Out-Null
}
# a rooted/absolute rel => Assert-NeoSafeRel BLOCK.
$xpBadAbs = @(@{ slice_id = $goXP.slice; session_root = $goXP.sessionRoot; final_surfaces = @(@{ rel = 'S:/abs/path.txt'; path = 'x' }) })
Expect-Block 'N-S3C-XC2-PATH-ABSOLUTE' 'NEO-BLOCK' {
  Assert-NeoLoopFinalState -RunRoot $goXP.run -ExpectedRunId $goXP.runId -SliceIds @($goXP.slice) -SliceFinalState $xpBadAbs | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3C-STOP-BEFORE-GO (PR-2): never-GO slice => END ASSEMBLES, XC2 records NO_GO_BUNDLE
# ----------------------------------------------------------------------------
# a run whose only round is a round-0 wall-clock-trip pre-ledger STOP (no GO bundle).
$runSB = New-RunRoot; $sbSlice = "s3c-$tag-sbg"; $dirSB = New-NotifyDir 's3c_sbg'
[void](Add-NeoIterationManifestEntry -RunRoot $runSB -Fields (New-PreLedgerStopRowFields $sbSlice 0 'CAP_WALL_CLOCK'))
# governance evidence present (not load-bearing for a never-GO slice's XC2, but the END
# gate assembles the full result).
Write-NeoJsonFile (Resolve-NeoRunStatePath $runSB 'governance_manifest.json') (Build-NeoGovManifest -GovernedRoot $mirrorSC -DerivedAt $TS)
$runSBId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runSB) 'run_id')
$sbFinal = Assert-NeoLoopFinalState -RunRoot $runSB -ExpectedRunId $runSBId -SliceIds @($sbSlice) -SliceFinalState @()
Expect-Value 'N-S3C-STOP-BEFORE-GO-XC2-NOGOBUNDLE' 'True' {
  [bool]($sbFinal.ok -and ([string]$sbFinal.slices[0].xc2 -ceq 'NO_GO_BUNDLE'))
}
# the END gate ASSEMBLES + surfaces DECISION_NEEDED once (TestModeDir). The converge
# envelope for a surfaced STOP.
$sbEnv = @{ stopped = $true; converged = $false; go = $false; stop = @{ stopped = $true }; rounds = @(); fix_rounds_used = 0 }
$ctxSB = New-Ctx $runSB 's3c-sbg' $dirSB 0 1
$sbGate = Invoke-NeoLoopEndGate -Context $ctxSB -RunRoot $runSB -ExpectedRunId $runSBId -SliceIds @($sbSlice) -ConvergeEnvelope $sbEnv -SliceFinalState @()
Expect-Value 'N-S3C-STOP-BEFORE-GO-ASSEMBLES' 'True' {
  [bool]($sbGate.assembly_ok -and ([string]$sbGate.human_class -ceq 'DECISION_NEEDED') -and ([string]$sbGate.gate_class -ceq 'DECISION_NEEDED'))
}
Expect-Value 'N-S3C-STOP-BEFORE-GO-ONE-NOTIFY' '1' { @(Get-EmlFiles $dirSB).Count }
# NEGATIVE: a caller asserting a GO bundle ref for that never-GO slice => BLOCK (PA-3).
$sbBadFS = @(@{ slice_id = $sbSlice; session_root = $goSGE.sessionRoot; final_surfaces = @(); caller_bundle_ref = './NEO_SESSION/ss-loop/audit/AUDIT_BUNDLE.json' })
Expect-Block 'N-S3C-STOP-BEFORE-GO-FORGED-GOREF' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $runSB -ExpectedRunId $runSBId -SliceIds @($sbSlice) -SliceFinalState $sbBadFS | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3C-ENDGATE-CLASS-DISCIPLINE : SESSION_END only on clean assembly; DECISION_NEEDED
#   only on surfaced STOP; a FAILED assembly => ESCALATION_STOP (never a human class).
# ----------------------------------------------------------------------------
# clean converged run => SESSION_END once.
$goCD = New-ConvergedGoRun "s3c_cd"; $dirCD = New-NotifyDir 's3c_cd'
$cdSurfaces = Get-BundleFinalSurfaces $goCD.sessionRoot $goCD.bundleRel
$cdFS = @(@{ slice_id = $goCD.slice; session_root = $goCD.sessionRoot; final_surfaces = $cdSurfaces })
$ctxCD = New-Ctx $goCD.run 's3c-cd' $dirCD 0 1
$cdEnv = @{ stopped = $false; converged = $true; go = $true; rounds = @($goCD.res.rounds); fix_rounds_used = 0; final = $goCD.res.final }
$cdGate = Invoke-NeoLoopEndGate -Context $ctxCD -RunRoot $goCD.run -ExpectedRunId $goCD.runId -SliceIds @($goCD.slice) -ConvergeEnvelope $cdEnv -SliceFinalState $cdFS
Expect-Value 'N-S3C-ENDGATE-SESSION-END-CLEAN' 'True' {
  [bool]($cdGate.assembly_ok -and ([string]$cdGate.human_class -ceq 'SESSION_END') -and ([string]$cdGate.gate_class -ceq 'SESSION_END'))
}
Expect-Value 'N-S3C-ENDGATE-SESSION-END-ONE-NOTIFY' '1' { @(Get-EmlFiles $dirCD).Count }
# a FAILED assembly (XC2 delta) => ESCALATION_STOP, NEVER a human class. Mutate a member.
$goFA = New-ConvergedGoRun "s3c_fa"; $dirFA = New-NotifyDir 's3c_fa'
$faSurfaces = @(Get-BundleFinalSurfaces $goFA.sessionRoot $goFA.bundleRel)
Add-Content -LiteralPath ([string]$faSurfaces[0].path) -Value 'tamper' -Encoding Ascii
$faFS = @(@{ slice_id = $goFA.slice; session_root = $goFA.sessionRoot; final_surfaces = $faSurfaces })
$ctxFA = New-Ctx $goFA.run 's3c-fa' $dirFA 0 1
$faEnv = @{ stopped = $false; converged = $true; go = $true; rounds = @($goFA.res.rounds); fix_rounds_used = 0; final = $goFA.res.final }
$faGate = Invoke-NeoLoopEndGate -Context $ctxFA -RunRoot $goFA.run -ExpectedRunId $goFA.runId -SliceIds @($goFA.slice) -ConvergeEnvelope $faEnv -SliceFinalState $faFS
Expect-Value 'N-S3C-ENDGATE-FAILED-ESCALATION' 'True' {
  [bool]((-not $faGate.assembly_ok) -and ($null -eq $faGate.human_class) -and ([string]$faGate.gate_class -ceq 'ESCALATION_STOP'))
}
Expect-Value 'N-S3C-ENDGATE-FAILED-NOT-HUMAN-CLASS' 'True' {
  # the composed notification carries ESCALATION_STOP, never a human class.
  $emls = @(Get-EmlFiles $dirFA)
  [bool](($emls.Count -eq 1) -and ($emls[0].Name -like '*_ESCALATION_STOP_*'))
}
# GREP-STYLE: no path OUTSIDE Invoke-NeoLoopEndGate passes -HumanEndClass (structural).
Expect-Value 'N-S3C-ENDGATE-ONLY-HUMANCLASS-SITE' 'True' {
  $modText = [System.IO.File]::ReadAllText((Join-Path $orchDir 'orch_loop.ps1'))
  # exactly one occurrence of the -HumanEndClass switch being PASSED (the call site);
  # plus its param declaration + the internal handling in the choke point. Count the
  # call-site pass token specifically.
  $passes = ([regex]::Matches($modText, '-HumanEndClass\b')).Count
  # occurrences: (1) param decl in Invoke-NeoLoopStopNotify; (2) the F5 handling comment
  # references; (3) the single pass in Invoke-NeoLoopEndGate. The BINDING check is that
  # the ONLY function that PASSES it is Invoke-NeoLoopEndGate - verified behaviorally
  # above (a loop STOP never yields a human class). Here we assert the pass token exists
  # exactly where expected and Complete-NeoLoopRoundStop does NOT contain it.
  $stopFn = [regex]::Match($modText, 'function Complete-NeoLoopRoundStop.*?\n}', 'Singleline').Value
  [bool](($passes -ge 1) -and ($stopFn -notmatch '-HumanEndClass'))
}

# ----------------------------------------------------------------------------
# N-S3C-ENDGATE-NEVER-AUTHORITY : notify failure => the END result still returns intact
# ----------------------------------------------------------------------------
# force the notify seam to fail by shimming Send-NeoGateNotification to throw; the choke
# point swallows it (convenience-never-authority) and the END result returns intact.
$goNA = New-ConvergedGoRun "s3c_na"; $dirNA = New-NotifyDir 's3c_na'
$naSurfaces = Get-BundleFinalSurfaces $goNA.sessionRoot $goNA.bundleRel
$naFS = @(@{ slice_id = $goNA.slice; session_root = $goNA.sessionRoot; final_surfaces = $naSurfaces })
$ctxNA = New-Ctx $goNA.run 's3c-na' $dirNA 0 1
$naEnv = @{ stopped = $false; converged = $true; go = $true; rounds = @($goNA.res.rounds); fix_rounds_used = 0; final = $goNA.res.final }
$script:naOrigSend = ${function:Send-NeoGateNotification}
${function:Send-NeoGateNotification} = { param() throw 'forced notify failure (fixture)' }
$naGate = $null; $naErr = ''
try { $naGate = Invoke-NeoLoopEndGate -Context $ctxNA -RunRoot $goNA.run -ExpectedRunId $goNA.runId -SliceIds @($goNA.slice) -ConvergeEnvelope $naEnv -SliceFinalState $naFS }
catch { $naErr = $_.Exception.Message }
finally { ${function:Send-NeoGateNotification} = $script:naOrigSend }
Expect-Value 'N-S3C-ENDGATE-NEVER-AUTHORITY' 'True' {
  # the END gate returned an intact result (assembly_ok true, human_class SESSION_END,
  # trail + final_state present) despite the notify seam throwing.
  [bool](($naErr -eq '') -and ($null -ne $naGate) -and $naGate.assembly_ok `
    -and ([string]$naGate.human_class -ceq 'SESSION_END') -and ($null -ne $naGate.trail) -and ($null -ne $naGate.final_state))
}

# ----------------------------------------------------------------------------
# P-S3C-CLEAN-END : a full converged run assembles clean (trail 1:1 + XC2 + SESSION_END)
# ----------------------------------------------------------------------------
$goCE = New-ConvergedGoRun "s3c_ce"; $dirCE = New-NotifyDir 's3c_ce'
$ceSurfaces = Get-BundleFinalSurfaces $goCE.sessionRoot $goCE.bundleRel
$ceFS = @(@{ slice_id = $goCE.slice; session_root = $goCE.sessionRoot; final_surfaces = $ceSurfaces })
$ctxCE = New-Ctx $goCE.run 's3c-ce' $dirCE 0 1
$ceEnv = @{ stopped = $false; converged = $true; go = $true; rounds = @($goCE.res.rounds); fix_rounds_used = 0; final = $goCE.res.final }
$ceGate = Invoke-NeoLoopEndGate -Context $ctxCE -RunRoot $goCE.run -ExpectedRunId $goCE.runId -SliceIds @($goCE.slice) -ConvergeEnvelope $ceEnv -SliceFinalState $ceFS
Expect-Value 'P-S3C-CLEAN-END-TRAIL-1TO1' 'True' {
  $t = $ceGate.trail
  [bool]($t.ok -and ($t.slices[0].attempt_count -eq $t.slices[0].row_count) -and ($null -ne $t.slices[0].go_round))
}
Expect-Value 'P-S3C-CLEAN-END-XC2-MATCHED' 'True' {
  [bool]([string]$ceGate.final_state.slices[0].xc2 -ceq 'MATCHED')
}
Expect-Value 'P-S3C-CLEAN-END-SESSION-END-ONCE' 'True' {
  [bool](([string]$ceGate.human_class -ceq 'SESSION_END') -and (@(Get-EmlFiles $dirCE).Count -eq 1))
}

# =============================================================================
# ===== S3c-FIX-2: SLICE-UNIVERSE class-closer (evidence-derived, not caller) ==
# =============================================================================
# The round-1 F3 fix stopped the caller forging a TrailResult digest, but the validated
# slice SET was still the caller's -SliceIds - a caller on a 2-slice run omitting a GO
# slice silently skipped that slice's trail + XC2. The fix DISCOVERS the universe from run
# evidence (the run_id-bound UNFILTERED union of the iteration manifest + attempt ledger)
# and asserts the effective validated set EQUALS it (omission => BLOCK; extra => BLOCK),
# plus a stray SliceFinalState descriptor (slice absent from the universe) => BLOCK.
#
# Build ONE real 2-slice run under a SINGLE run_id: slice 's_go' is a real converged GO run
# (its own bundle + GO trail, via New-ConvergedGoRun); slice 's_stop' is a valid no-GO
# PRE-LEDGER STOP trail seeded into the SAME run root (shared run_id => both discovered).
# The frozen readers bind every row/entry to the persisted run_id, so the union genuinely
# discovers both slices.
$goU = New-ConvergedGoRun "s3cf2_u"
$uStopSlice = "s3c-$tag-f2stop"
# s_stop: a mechanical pre-ledger STOP row (no attempt entry) in goU's run root.
[void](Add-NeoIterationManifestEntry -RunRoot $goU.run -Fields (New-PreLedgerStopRowFields $uStopSlice 0 'CAP_WALL_CLOCK'))
$uGoSurfaces = @(Get-BundleFinalSurfaces $goU.sessionRoot $goU.bundleRel)
# the s_go final-state descriptor (UN-mutated - a clean GO surface set).
$uGoFS = @{ slice_id = $goU.slice; session_root = $goU.sessionRoot; final_surfaces = $uGoSurfaces }
# the s_stop descriptor: never-GO => NO_GO_BUNDLE (empty final_surfaces).
$uStopFS = @{ slice_id = $uStopSlice; session_root = $goU.sessionRoot; final_surfaces = @() }
$uEnv = @{ stopped = $true; converged = $false; go = $false; stop = @{ stopped = $true }; rounds = @(); fix_rounds_used = 0 }

# ----------------------------------------------------------------------------
# N-S3CF2-SLICEID-OMITS-GO : a caller slice set OMITTING the discovered GO slice => BLOCK
#   (s_go's trail + XC2 are NOT silently skipped). Prove the omission ITSELF blocks even
#   when s_go's surface is mutated (which, under the old code, would have gone unchecked).
# ----------------------------------------------------------------------------
$dirUO = New-NotifyDir 's3cf2_uo'
# mutate s_go's kept surface: under the OLD caller-trusted universe, omitting s_go would
# have skipped this mutation silently. Now the omission blocks BEFORE any per-slice work.
Add-Content -LiteralPath ([string]$uGoSurfaces[0].path) -Value 'omit-mutation' -Encoding Ascii
$uoStopFS = @{ slice_id = $uStopSlice; session_root = $goU.sessionRoot; final_surfaces = @() }
$ctxUO = New-Ctx $goU.run 's3c-uo' $dirUO 0 1
# the END gate catches an assembly BLOCK (the omission) and routes ESCALATION_STOP, NEVER a
# human class - it does NOT re-throw (same contract as N-S3C-ENDGATE-FAILED-ESCALATION). So
# the omission surfaces as assembly_ok=$false + gate_class=ESCALATION_STOP + human_class=$null,
# and the underlying slice-universe reason is preserved in assembly_fail_code/detail.
$uoGate = Invoke-NeoLoopEndGate -Context $ctxUO -RunRoot $goU.run -ExpectedRunId $goU.runId `
  -SliceIds @($uStopSlice) -ConvergeEnvelope $uEnv -SliceFinalState @($uoStopFS)
Expect-Value 'N-S3CF2-SLICEID-OMITS-GO' 'True' {
  # caller passed ONLY s_stop; the discovered universe includes s_go => the assembly FAILS
  # (s_go's XC2 is NOT silently skipped), routed to ESCALATION_STOP, no human class.
  [bool]((-not $uoGate.assembly_ok) -and ($null -eq $uoGate.human_class) `
    -and ([string]$uoGate.gate_class -ceq 'ESCALATION_STOP') `
    -and ([string]$uoGate.assembly_fail_detail -match 'slice-universe') `
    -and ([string]$uoGate.assembly_fail_detail -match 'OMITS discovered run slice'))
}
# direct XC2 boundary (Assert-NeoLoopFinalState) refuses the omission identically.
Expect-Block 'N-S3CF2-SLICEID-OMITS-GO-XC2' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goU.run -ExpectedRunId $goU.runId `
    -SliceIds @($uStopSlice) -SliceFinalState @($uoStopFS) | Out-Null
}
# and the trail validator itself refuses it at its own boundary (universe gate).
Expect-Block 'N-S3CF2-SLICEID-OMITS-GO-TRAIL' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $goU.run -ExpectedRunId $goU.runId -SliceIds @($uStopSlice) | Out-Null
}
# (goU's s_go surface is now mutated - it is used ONLY for omit/extra/stray BLOCK cases,
# which never re-hash it; the clean full-universe P case below uses a SEPARATE fresh run.)

# ----------------------------------------------------------------------------
# N-S3CF2-SLICEID-EXTRA : a caller slice set naming a slice NOT present in the run => BLOCK
# ----------------------------------------------------------------------------
Expect-Block 'N-S3CF2-SLICEID-EXTRA' 'LEDGER_FAILURE' {
  # caller names both real slices PLUS a phantom slice the run never recorded.
  Assert-NeoLoopEndTrail -RunRoot $goU.run -ExpectedRunId $goU.runId `
    -SliceIds @($goU.slice, $uStopSlice, 's3c-phantom-never-ran') | Out-Null
}
Expect-Block 'N-S3CF2-SLICEID-EXTRA-XC2' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goU.run -ExpectedRunId $goU.runId `
    -SliceIds @($goU.slice, $uStopSlice, 's3c-phantom-never-ran') `
    -SliceFinalState @($uGoFS, $uStopFS) | Out-Null
}

# ----------------------------------------------------------------------------
# N-S3CF2-SLICEFINALSTATE-STRAY : a SliceFinalState descriptor for a slice_id ABSENT from
#   the run => BLOCK (the full discovered set is named, so the universe gate PASSES; the
#   stray descriptor is what BLOCKs - the reverse direction of GO-slice-without-descriptor).
# ----------------------------------------------------------------------------
$strayFS = @{ slice_id = 's3c-stray-not-in-run'; session_root = $goU.sessionRoot; final_surfaces = @() }
Expect-Block 'N-S3CF2-SLICEFINALSTATE-STRAY' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goU.run -ExpectedRunId $goU.runId `
    -SliceIds @($goU.slice, $uStopSlice) `
    -SliceFinalState @($uGoFS, $uStopFS, $strayFS) | Out-Null
}

# ----------------------------------------------------------------------------
# P-S3CF2-FULL-UNIVERSE-CONTROL : the FULL discovered set validates clean end-to-end
#   (s_go XC2 MATCHED; s_stop NO_GO_BUNDLE) AND the GO-slice mutation that the omit-case
#   would have skipped is PROVEN caught when the universe is complete. Uses a FRESH clean
#   2-slice run so s_go's surface is un-mutated.
# ----------------------------------------------------------------------------
$goP = New-ConvergedGoRun "s3cf2_p"
$pStopSlice = "s3c-$tag-f2pstop"
[void](Add-NeoIterationManifestEntry -RunRoot $goP.run -Fields (New-PreLedgerStopRowFields $pStopSlice 0 'CAP_WALL_CLOCK'))
Write-NeoJsonFile (Resolve-NeoRunStatePath $goP.run 'governance_manifest.json') (Build-NeoGovManifest -GovernedRoot $mirrorSC -DerivedAt $TS)
$pGoSurfaces = @(Get-BundleFinalSurfaces $goP.sessionRoot $goP.bundleRel)
$pGoFS = @{ slice_id = $goP.slice; session_root = $goP.sessionRoot; final_surfaces = $pGoSurfaces }
$pStopFS = @{ slice_id = $pStopSlice; session_root = $goP.sessionRoot; final_surfaces = @() }
$dirP = New-NotifyDir 's3cf2_p'
$ctxP = New-Ctx $goP.run 's3c-p' $dirP 0 1
$pEnv = @{ stopped = $true; converged = $false; go = $false; stop = @{ stopped = $true }; rounds = @(); fix_rounds_used = 0 }
$pFinal = Assert-NeoLoopFinalState -RunRoot $goP.run -ExpectedRunId $goP.runId `
  -SliceIds @($goP.slice, $pStopSlice) -SliceFinalState @($pGoFS, $pStopFS)
Expect-Value 'P-S3CF2-FULL-UNIVERSE-XC2-BOTH' 'True' {
  # index the per-slice results; s_go MATCHED, s_stop NO_GO_BUNDLE.
  $bySlice = @{}; foreach ($s in @($pFinal.slices)) { $bySlice[[string]$s.slice_id] = [string]$s.xc2 }
  [bool]($pFinal.ok -and ($bySlice[$goP.slice] -ceq 'MATCHED') -and ($bySlice[$pStopSlice] -ceq 'NO_GO_BUNDLE'))
}
$pGate = Invoke-NeoLoopEndGate -Context $ctxP -RunRoot $goP.run -ExpectedRunId $goP.runId `
  -SliceIds @($goP.slice, $pStopSlice) -ConvergeEnvelope $pEnv -SliceFinalState @($pGoFS, $pStopFS)
Expect-Value 'P-S3CF2-FULL-UNIVERSE-ASSEMBLES' 'True' {
  [bool]($pGate.assembly_ok -and ([string]$pGate.human_class -ceq 'DECISION_NEEDED'))
}
# PROOF the mutation IS caught when the universe is complete: mutate s_go's surface on the
# FULL-set call => XC2 delta BLOCKs (the exact bytes the omit-case would have skipped).
Add-Content -LiteralPath ([string]$pGoSurfaces[0].path) -Value 'full-set-mutation' -Encoding Ascii
Expect-Block 'P-S3CF2-FULL-UNIVERSE-MUTATION-CAUGHT' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goP.run -ExpectedRunId $goP.runId `
    -SliceIds @($goP.slice, $pStopSlice) -SliceFinalState @($pGoFS, $pStopFS) | Out-Null
}

# =============================================================================
# S3c-FIX-3: SLICE-ID COLLECTION CASE-SENSITIVITY (check==use close)
# =============================================================================
# The round-2 discovery DESIGN is correct, but the universe dedup/compare collections were
# PowerShell-default @{} (ContainsKey CASE-INSENSITIVE) while the per-slice ledger reads are
# case-SENSITIVE (frozen reader filters slice_id -ceq $SliceId). Two slice_ids differing ONLY
# by case COLLAPSED into one universe member => a caller could OMIT a case-variant GO slice
# (its trail + XC2 silently skipped, its mutation kept). The fix constructs the 5 slice-id
# collections with [System.StringComparer]::Ordinal so membership EXACTLY matches the -ceq
# reads. These fixtures prove the collapse is gone (both a case-DISTINCT universe validated
# AND an omission of a case-variant slice refused). Modeled on the S3c-FIX-2 universe fixtures
# (New-ConvergedGoRun + a seeded pre-ledger-STOP case-variant slice); no new helper/schema.
#
# Build ONE run: GO slice = $goCC.slice (real converged GO), and a pre-ledger STOP slice that
# is the CASE-VARIANT of that GO id (same letters, case flipped) seeded into the SAME run root.
$goCC = New-ConvergedGoRun "s3cf3_cc"
$ccGoSlice = [string]$goCC.slice
$ccStopSlice = $ccGoSlice.ToUpperInvariant()   # case-variant: ordinally distinct, case-insensitively equal
# guard: the two ids MUST differ ordinally but collide case-insensitively, else the fixture
# is not exercising the bug (a run whose auto-id had no lowercase letters would be a no-op).
Expect-Value 'P-S3CF3-CASE-VARIANT-WELLFORMED' 'True' {
  [bool](($ccStopSlice -cne $ccGoSlice) -and ($ccStopSlice -ieq $ccGoSlice))
}
[void](Add-NeoIterationManifestEntry -RunRoot $goCC.run -Fields (New-PreLedgerStopRowFields $ccStopSlice 0 'CAP_WALL_CLOCK'))
$ccGoSurfaces = @(Get-BundleFinalSurfaces $goCC.sessionRoot $goCC.bundleRel)
$ccGoFS   = @{ slice_id = $ccGoSlice;   session_root = $goCC.sessionRoot; final_surfaces = $ccGoSurfaces }
$ccStopFS = @{ slice_id = $ccStopSlice; session_root = $goCC.sessionRoot; final_surfaces = @() }

# ----------------------------------------------------------------------------
# N-S3CF3-CASE-COLLISION : caller -SliceIds = @(<stop-variant>) ONLY, with the GO slice's kept
#   surface MUTATED. Under the OLD default @{}, discovery collapsed {GO, stop-variant} to a
#   single member matching @(<stop-variant>) => the GO slice was silently skipped and its
#   mutation kept. With ordinal collections the two are DISTINCT universe members => the
#   omission of the GO slice is REFUSED at every boundary; the mutation is NOT kept.
# ----------------------------------------------------------------------------
# mutate the GO slice's kept surface (the bytes the old collapse would have skipped).
Add-Content -LiteralPath ([string]$ccGoSurfaces[0].path) -Value 'case-collision-mutation' -Encoding Ascii
# the trail validator (universe gate) refuses the omission of the case-variant GO slice.
Expect-Block 'N-S3CF3-CASE-COLLISION-TRAIL' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $goCC.run -ExpectedRunId $goCC.runId -SliceIds @($ccStopSlice) | Out-Null
}
# the XC2 boundary refuses it identically (discovery keeps both members distinct).
Expect-Block 'N-S3CF3-CASE-COLLISION-XC2' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goCC.run -ExpectedRunId $goCC.runId `
    -SliceIds @($ccStopSlice) -SliceFinalState @($ccStopFS) | Out-Null
}
# and the END gate surfaces the omission as ESCALATION_STOP (assembly fail), never a human class.
$dirCC = New-NotifyDir 's3cf3_cc'
$ctxCC = New-Ctx $goCC.run 's3c-cc' $dirCC 0 1
$ccEnv = @{ stopped = $true; converged = $false; go = $false; stop = @{ stopped = $true }; rounds = @(); fix_rounds_used = 0 }
$ccGate = Invoke-NeoLoopEndGate -Context $ctxCC -RunRoot $goCC.run -ExpectedRunId $goCC.runId `
  -SliceIds @($ccStopSlice) -ConvergeEnvelope $ccEnv -SliceFinalState @($ccStopFS)
Expect-Value 'N-S3CF3-CASE-COLLISION-ENDGATE' 'True' {
  [bool]((-not $ccGate.assembly_ok) -and ($null -eq $ccGate.human_class) `
    -and ([string]$ccGate.gate_class -ceq 'ESCALATION_STOP') `
    -and ([string]$ccGate.assembly_fail_detail -match 'slice-universe') `
    -and ([string]$ccGate.assembly_fail_detail -match 'OMITS discovered run slice'))
}

# ----------------------------------------------------------------------------
# P-S3CF3-CASE-DISTINCT-FULL : the FULL case-distinct universe {GO, stop-variant} validates
#   end-to-end on a FRESH clean run (GO XC2 MATCHED; stop-variant NO_GO_BUNDLE), proving the
#   two case-differing ids are kept DISTINCT; then a GO-surface mutation on the full-set call
#   is PROVEN caught (the exact delta the collapse would have masked).
# ----------------------------------------------------------------------------
$goCP = New-ConvergedGoRun "s3cf3_cp"
$cpGoSlice = [string]$goCP.slice
$cpStopSlice = $cpGoSlice.ToUpperInvariant()
[void](Add-NeoIterationManifestEntry -RunRoot $goCP.run -Fields (New-PreLedgerStopRowFields $cpStopSlice 0 'CAP_WALL_CLOCK'))
Write-NeoJsonFile (Resolve-NeoRunStatePath $goCP.run 'governance_manifest.json') (Build-NeoGovManifest -GovernedRoot $mirrorSC -DerivedAt $TS)
$cpGoSurfaces = @(Get-BundleFinalSurfaces $goCP.sessionRoot $goCP.bundleRel)
$cpGoFS   = @{ slice_id = $cpGoSlice;   session_root = $goCP.sessionRoot; final_surfaces = $cpGoSurfaces }
$cpStopFS = @{ slice_id = $cpStopSlice; session_root = $goCP.sessionRoot; final_surfaces = @() }
$cpFinal = Assert-NeoLoopFinalState -RunRoot $goCP.run -ExpectedRunId $goCP.runId `
  -SliceIds @($cpGoSlice, $cpStopSlice) -SliceFinalState @($cpGoFS, $cpStopFS)
Expect-Value 'P-S3CF3-CASE-DISTINCT-BOTH' 'True' {
  # ordinal-keyed index so the two case-differing ids stay distinct in the test's own assertion too.
  $ccBySlice = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
  foreach ($s in @($cpFinal.slices)) { $ccBySlice[[string]$s.slice_id] = [string]$s.xc2 }
  [bool]($cpFinal.ok -and (@($ccBySlice.Keys).Count -eq 2) `
    -and ($ccBySlice[$cpGoSlice] -ceq 'MATCHED') -and ($ccBySlice[$cpStopSlice] -ceq 'NO_GO_BUNDLE'))
}
# PROOF the GO mutation IS caught once the full case-distinct universe is named.
Add-Content -LiteralPath ([string]$cpGoSurfaces[0].path) -Value 'case-distinct-full-mutation' -Encoding Ascii
Expect-Block 'P-S3CF3-CASE-DISTINCT-MUTATION-CAUGHT' 'LEDGER_FAILURE' {
  Assert-NeoLoopFinalState -RunRoot $goCP.run -ExpectedRunId $goCP.runId `
    -SliceIds @($cpGoSlice, $cpStopSlice) -SliceFinalState @($cpGoFS, $cpStopFS) | Out-Null
}

# =============================================================================
# S3c-FIX-4: SLICE-UNIVERSE -ceq-DISTINCTNESS GUARD (check==use root close)
# =============================================================================
# The round-3 fix made the 5 slice-id collections ordinal (case-collision dead), but the
# FROZEN reader filters (Read-NeoIterationManifest / Read-NeoAttemptLedger) compare slice_id
# with PowerShell -ceq, which is culture-LOOSE: an ordinally-DISTINCT pair can still be -ceq
# EQUAL (e.g. 'ss' vs the sharp-s 'ss-as-single-glyph'). So the ordinal universe could treat
# such a pair as two distinct members while the -ceq reader MERGES them - the invariant "the
# ordinal collections match the -ceq reads" was not fully true (it failed CLOSED: the merge
# only ADDS rows). The FIX adds ONE pairwise guard at the END of Get-NeoLoopRunSliceUniverse:
# for the already-ordinal-distinct universe, if any two members are -ceq EQUAL => BLOCK. This
# makes the discovered universe BOTH ordinal- AND -ceq-distinct, so ordinal set-equality and
# the reader -ceq filter can never disagree (check==use closed at root, fail-closed).
#
# GROUND the -ceq-colliding pair IN THIS RUNTIME (do NOT fake it): 'ss' (U+0073 U+0073) vs
# the sharp-s U+00DF. Assert [ordinal]::Equals=False AND (-ceq)=True BEFORE use so the fixture
# genuinely exercises the gap; if that pair is not -ceq-colliding here, the fixture would be a
# no-op and the guard-fires assertion below would (correctly) fail loudly.
$ceqA = 'ss'
$ceqB = [string]([char]0x00DF)   # sharp-s
Expect-Value 'P-S3CF4-CEQ-PAIR-WELLFORMED' 'True' {
  # ordinally DISTINCT but -ceq EQUAL: exactly the gap the guard closes.
  [bool]((-not [System.String]::Equals($ceqA, $ceqB, [System.StringComparison]::Ordinal)) -and ($ceqA -ceq $ceqB))
}
# ----------------------------------------------------------------------------
# N-S3CF4-CEQ-COLLIDING-UNIVERSE : a run recording two slice-ids that are ORDINALLY DISTINCT
#   but -ceq EQUAL => discovery BLOCKs. Seed both as pre-ledger STOP rows (round 0) into ONE
#   run root (shared run_id => both discovered by the unfiltered union). Neither id can be an
#   auto-generated GO id, so both are seeded directly. The guard fires at the tail of
#   Get-NeoLoopRunSliceUniverse - so the universe reader, the trail validator, and the XC2
#   boundary (all of which discover through it) each refuse the run.
# ----------------------------------------------------------------------------
$runCEQ = New-RunRoot
[void](Add-NeoIterationManifestEntry -RunRoot $runCEQ -Fields (New-PreLedgerStopRowFields $ceqA 0 'CAP_WALL_CLOCK'))
[void](Add-NeoIterationManifestEntry -RunRoot $runCEQ -Fields (New-PreLedgerStopRowFields $ceqB 0 'CAP_WALL_CLOCK'))
$runCEQId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runCEQ) 'run_id')
# both ordinal-distinct slice_ids genuinely land + are discovered UNMERGED-ordinally (the
# guard is what refuses them, not a dedup collapse): confirm the two rows are on disk.
Expect-Value 'P-S3CF4-CEQ-BOTH-ROWS-LANDED' 'True' {
  $rows = Read-NeoIterationManifest -RunRoot $runCEQ
  $ids = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
  foreach ($r in @($rows)) { $ids[[string](Get-NeoProp $r 'slice_id')] = $true }
  [bool]((@($rows).Count -eq 2) -and $ids.ContainsKey($ceqA) -and $ids.ContainsKey($ceqB))
}
# the universe reader itself BLOCKs on the -ceq collision.
Expect-Block 'N-S3CF4-CEQ-COLLIDING-UNIVERSE' 'LEDGER_FAILURE' {
  Get-NeoLoopRunSliceUniverse -RunRoot $runCEQ -ExpectedRunId $runCEQId | Out-Null
}
# and the trail validator (which discovers through the universe gate) refuses it identically.
Expect-Block 'N-S3CF4-CEQ-COLLIDING-UNIVERSE-TRAIL' 'LEDGER_FAILURE' {
  Assert-NeoLoopEndTrail -RunRoot $runCEQ -ExpectedRunId $runCEQId -SliceIds @($ceqA, $ceqB) | Out-Null
}

# ----------------------------------------------------------------------------
# P-S3CF4-ORDINAL-AND-CEQ-DISTINCT-CONTROL : a normal run whose slice-ids are BOTH ordinal-
#   AND -ceq-distinct ('sa'/'sb') discovers clean (the guard does not over-block realistic
#   slices). Confirms 'sa' -ceq 'sb' = False so the pair is genuinely -ceq-distinct.
# ----------------------------------------------------------------------------
$ctlA = 'sa'; $ctlB = 'sb'
Expect-Value 'P-S3CF4-CONTROL-PAIR-WELLFORMED' 'True' {
  # ordinally distinct AND -ceq distinct: the guard must NOT fire on this realistic pair.
  [bool]((-not [System.String]::Equals($ctlA, $ctlB, [System.StringComparison]::Ordinal)) -and ($ctlA -cne $ctlB))
}
$runCTL = New-RunRoot
[void](Add-NeoIterationManifestEntry -RunRoot $runCTL -Fields (New-PreLedgerStopRowFields $ctlA 0 'CAP_WALL_CLOCK'))
[void](Add-NeoIterationManifestEntry -RunRoot $runCTL -Fields (New-PreLedgerStopRowFields $ctlB 0 'CAP_WALL_CLOCK'))
$runCTLId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runCTL) 'run_id')
Expect-Value 'P-S3CF4-ORDINAL-AND-CEQ-DISTINCT-CONTROL' 'True' {
  # the guard passes: the full 2-member universe is returned (both ids present, ordinal-keyed).
  $u = Get-NeoLoopRunSliceUniverse -RunRoot $runCTL -ExpectedRunId $runCTLId
  $uset = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
  foreach ($x in @($u)) { $uset[[string]$x] = $true }
  [bool]((@($u).Count -eq 2) -and $uset.ContainsKey($ctlA) -and $uset.ContainsKey($ctlB))
}
# re-ground: the round-3 case-variant fixtures use ASCII case-variant ids (e.g. 's'/'S');
# confirm ('s' -ceq 'S') = False so they are BOTH ordinal- AND -ceq-distinct and remain valid
# under the new guard (no round-3 fixture line is touched - this is a read-only re-ground).
Expect-Value 'P-S3CF4-CASE-VARIANTS-STAY-CEQ-DISTINCT' 'True' {
  [bool](('s' -cne 'S') -and ($ccGoSlice -cne $ccStopSlice) -and ($cpGoSlice -cne $cpStopSlice))
}

# ----------------------------------------------------------------------------
# P-S3C-AS18 : the module + suite still resolve judging-class; negative control UNKNOWN
# ----------------------------------------------------------------------------
$liveMapS3c = Get-NeoClassMap $liveMap
Expect-Value 'P-S3C-AS18-MODULE-JUDGING' 'test_harness' { Resolve-NeoArtifactClass $liveMapS3c '.neo/scripts/orchestrator/orch_loop.ps1' }
Expect-Value 'P-S3C-AS18-SUITE-JUDGING' 'test_harness' { Resolve-NeoArtifactClass $liveMapS3c '.neo/scripts/orchestrator/harness/orch_loop_suite.ps1' }
Expect-Value 'P-S3C-AS18-NEGATIVE-CONTROL' 'UNKNOWN' { Resolve-NeoArtifactClass $liveMapS3c 'app/some_unregistered_file.txt' }

# =============================================================================
# ======================= C4: EXTERNAL-MODEL CHANNEL (WIRED LANE) ==============
# =============================================================================
# Loop-suite side of the C4 fixture set (dispatch 3.E; the adapter/derivation-level
# fixtures live in orch_external_suite.ps1). STRUCTURAL LIVE-INCAPABILITY: the live
# invoker is TRIPWIRED for this whole section - every external path runs through a
# stub -InvokerSeam; the tripwire count is asserted zero at the end.
$script:c4LiveTrip = 0
$script:c4OrigInvoker = ${function:Invoke-NeoExternalCodex}
${function:Invoke-NeoExternalCodex} = { param($PacketDir, $OutFile, $TimeoutSec) $script:c4LiveTrip++; throw 'TRIPWIRE: live codex invoker reached from the loop suite (structurally forbidden)' }

# fixture attestation (APPROVED/IN FORCE + a REVOKED twin) + fixture credential -
# the adapter's default paths are NEVER exercised here (explicit fixture paths only).
$c4AttOk = Join-Path $ScratchRoot 'c4_attestation_ok.md'
Set-Content -LiteralPath $c4AttOk -Value @('# fixture DEF-P7 twin', 'STATUS: **APPROVED / IN FORCE (fixture stamp)**') -Encoding Ascii
$c4Cred = Join-Path $ScratchRoot 'c4_auth_fixture.json'
Set-Content -LiteralPath $c4Cred -Value '{}' -Encoding Ascii
# canned CLI outputs (stub seams write them; the pinned banner id from the dispatch).
# C4-FIX-3 fidelity: emit the FAITHFUL full-transcript duplicate-final shape (grounded on
# real codex_verdict_round{1,2,10}.txt) - header/model -> ^user$ -> prompt -> a reasoning
# ^codex$ -> an ^exec$ tool-output block -> the FINAL ^codex$ turn with VERDICT/FINDINGS ->
# 'tokens used' -> the SAME VERDICT/FINDINGS again (codex duplicates its final message).
# The parser binds the verdict to the assistant-final region (after the last ^codex$) and
# all-agrees the duplicate => this GO lane still forms (behavior-preserving for the GO lane).
$script:c4StubGo = { param($io) Set-Content -LiteralPath $io.out_file -Value @('OpenAI Codex v0.142.5', '--------', 'workdir: C:\fixture\packet', 'model: gpt-5.5', 'provider: openai', 'approval: never', 'sandbox: read-only', 'session id: fixture-0000', '--------', 'user', 'Perform the audit per the packet.', 'codex', 'Reading the packet, then applying the rubric.', 'exec', 'bash -lc "cat packet.txt"', 'exec succeeded', 'codex', 'VERDICT: GO', 'FINDINGS: fixture clean', 'tokens used', '12,345', 'VERDICT: GO', 'FINDINGS: fixture clean') -Encoding Ascii; return @{ ok = $true; class = 'OK'; detail = 'stub' } }

# plant the FULL evidence set for a current-round external GO: run-ledger entry,
# per-slice consumed entry, and the round-bound verdict record (all schema-valid).
function New-ExternalGoLedgers([string]$runRoot, [string]$sliceId, [string]$roundId, $world, [string]$verdict = 'GO') {
  $bundleFull = Assert-NeoContained $world.root $world.bundleRel
  $bh = Get-NeoSha256File $bundleFull
  $runRes = Add-NeoRunExternalCallEntry -RunRoot $runRoot -Timestamp $TS
  [void](Add-NeoExternalSliceCallEntry -RunRoot $runRoot -SliceId $sliceId -RoundId $roundId -BundleDiffHash $bh `
    -Timestamp $TS -Shape 'consumed' -PostIncrementCount ([int]$runRes.post_increment_count))
  $rec = [pscustomobject]@{
    run_id = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runRoot) 'run_id')
    slice_id = $sliceId; round_id = $roundId; bundle_diff_hash = $bh
    verdict = $verdict; findings_summary = 'fixture findings'
    model_id = 'gpt-5.5'; timestamp_utc = $TS
    attestation_ref = 'fixture#sha256:' + ('e' * 64)
    post_increment_count = [int]$runRes.post_increment_count; slice_call_seq = 1; stamped_by = 'm1'
  }
  $rec | Add-Member -NotePropertyName 'record_sha256' -NotePropertyValue (Get-NeoBodyHash $rec @('record_sha256'))
  Assert-NeoValid $rec 'neo:external_audit_verdict' $index 'C4-fixture verdict record'
  [void](Add-NeoRunJsonlLine (Resolve-NeoRunStatePath $runRoot 'external_verdict_ledger.jsonl') $rec 'external_verdict_ledger')
  return $bh
}

# ---- P-C4-GATEC-EVIDENCE-GO : the WIRED acceptance (flips the S3a placeholder at
# orch_loop.ps1 gate C, old :983-986 'GO refused as impossible while unwired'):
# HIGH row + validated current-round external GO on disk + lane claim 'GO' =>
# aggregation GO (gate C re-derives from disk at consumption; check==use).
$runXG = New-RunRoot; $dirXG = New-NotifyDir 'c4_go'
$ctxXG = New-Ctx $runXG 'c4-go' $dirXG
$wXG = New-SlotWorld 'slot_c4_go' $runXG
[void](New-ExternalGoLedgers $runXG $ctxXG.slice_id 'round-1' $wXG)
Expect-Value 'P-C4-GATEC-EVIDENCE-GO' 'True' {
  $agg = Invoke-Agg $ctxXG $wXG $rowHigh 'high' 'GO'
  [bool]((-not $agg.stopped) -and $agg.go -and ([string]$agg.external_lane_status -ceq 'GO'))
}
Expect-Value 'P-C4-GATEC-EVIDENCE-GO-NO-NOTIFY' '0' { @(Get-EmlFiles $dirXG).Count }

# ---- N-C4-GATEC-FORGED-GO-NO-RECORD (dispatch 3.E.7) : a bare caller 'GO' with NO
# validating on-disk record => NOT aggregated GO (fail-closed STOP); the manifest row
# records the DERIVED status (MISSING), never the forged claim.
$runXF = New-RunRoot; $dirXF = New-NotifyDir 'c4_forged'
$ctxXF = New-Ctx $runXF 'c4-forged' $dirXF
$wXF = New-SlotWorld 'slot_c4_forged' $runXF
$stopXF = Invoke-Agg $ctxXF $wXF $rowHigh 'high' 'GO'
Expect-StopResult 'N-C4-GATEC-FORGED-GO-NO-RECORD' $stopXF 'EXTERNAL_LANE_INVALID' 'ESCALATION_STOP' $runXF $dirXF
Expect-Value 'N-C4-GATEC-FORGED-GO-ROW-DERIVED-LANE' 'MISSING' {
  $rows = Read-NeoIterationManifest -RunRoot $runXF
  [string](Get-NeoProp $rows[$rows.Count - 1] 'external_lane_status')
}

# ---- N-C4-GATEC-NOGO-VERDICT-CLAIMED-GO : a full evidence set whose verdict is
# NO-GO + a forged 'GO' claim => derived NO_GO != GO => fail-closed STOP (proves the
# derivation is CONSULTED, not merely file-presence).
$runXN = New-RunRoot; $dirXN = New-NotifyDir 'c4_nogo'
$ctxXN = New-Ctx $runXN 'c4-nogo' $dirXN
$wXN = New-SlotWorld 'slot_c4_nogo' $runXN
[void](New-ExternalGoLedgers $runXN $ctxXN.slice_id 'round-1' $wXN 'NO-GO')
$stopXN = Invoke-Agg $ctxXN $wXN $rowHigh 'high' 'GO'
Expect-StopResult 'N-C4-GATEC-NOGO-VERDICT-CLAIMED-GO' $stopXN 'EXTERNAL_LANE_INVALID' 'ESCALATION_STOP' $runXN $dirXN
Expect-Value 'N-C4-GATEC-NOGO-ROW-DERIVED-LANE' 'NO_GO' {
  $rows = Read-NeoIterationManifest -RunRoot $runXN
  [string](Get-NeoProp $rows[$rows.Count - 1] 'external_lane_status')
}

# ---- N-C4-GATEC-STALE-ROUND (dispatch 3.E.1 at the consumption boundary) : the full
# evidence set bound to round-0 while the CURRENT round is round-1 => derived STALE
# (treated missing) => the forged GO claim STOPs; HIGH blocks.
$runXS = New-RunRoot; $dirXS = New-NotifyDir 'c4_stale'
$ctxXS = New-Ctx $runXS 'c4-stale' $dirXS
$wXS = New-SlotWorld 'slot_c4_stale' $runXS
[void](New-ExternalGoLedgers $runXS $ctxXS.slice_id 'round-0' $wXS)
$stopXS = Invoke-Agg $ctxXS $wXS $rowHigh 'high' 'GO'
Expect-StopResult 'N-C4-GATEC-STALE-ROUND' $stopXS 'EXTERNAL_LANE_INVALID' 'ESCALATION_STOP' $runXS $dirXS
Expect-Value 'N-C4-GATEC-STALE-ROW-DERIVED-LANE' 'STALE' {
  $rows = Read-NeoIterationManifest -RunRoot $runXS
  [string](Get-NeoProp $rows[$rows.Count - 1] 'external_lane_status')
}

# ---- N-C4-HIGH-NONGO-LANES-BLOCK : EVERY non-GO recognized lane on an effective-
# HIGH round => EXTERNAL_REQUIRED_UNAVAILABLE (the '=> HIGH blocks' completion for
# the adapter-level fixture set; manual-external fallback wording preserved).
foreach ($lane in @('MISSING', 'STALE', 'UNPARSEABLE', 'NO_GO')) {
  $runHL = New-RunRoot; $dirHL = New-NotifyDir ('c4_hl_' + $lane.ToLowerInvariant())
  $wHL = New-SlotWorld ('slot_c4_hl_' + $lane.ToLowerInvariant()) $runHL
  $stopHL = Invoke-Agg (New-Ctx $runHL ('c4-hl-' + $lane.ToLowerInvariant()) $dirHL) $wHL $rowHigh 'high' $lane
  Expect-StopResult ('N-C4-HIGH-LANE-' + $lane + '-BLOCKS') $stopHL 'EXTERNAL_REQUIRED_UNAVAILABLE' 'ESCALATION_STOP' $runHL $dirHL
}

# ---- N-C4-SLOT-TRANSPLANT-SPAWNGATE (dispatch 3.E.6, HONESTLY SCOPED per sec-0) :
# a CONSTRUCTED ATTACK - a slot world with a VALID on-disk external GO but NO
# correlated spawn-ledger entry (the auditor-slot fill synthesized without the cold
# spawn) => the FROZEN spawn-correlation gate refuses BEFORE gate C ever sees the
# external GO. HONEST CLAIM LINE: this proves the no-spawn-entry attack only. The
# sibling case - a supervisor that ALSO forges a correlated spawn entry - is OUTSIDE
# the enforceable model (the ledger is supervisor-writable: TAMPER-EVIDENT, not
# tamper-proof, sec-0/NB-4); the spawn ledger + verdict record + both external-call
# ledgers all ride in END evidence instead. Never claimed as absolute prevention.
$runXT = New-RunRoot; $dirXT = New-NotifyDir 'c4_transplant'
$ctxXT = New-Ctx $runXT 'c4-transplant' $dirXT
$wXT = New-SlotWorld 'slot_c4_transplant' $runXT -NoSpawnEntry
[void](New-ExternalGoLedgers $runXT $ctxXT.slice_id 'round-1' $wXT)
$stopXT = Invoke-Agg $ctxXT $wXT $rowHigh 'high' 'GO'
Expect-Value 'N-C4-SLOT-TRANSPLANT-SPAWNGATE' 'True' {
  [bool](([bool]$stopXT.stopped) -and ([string]$stopXT.reason_code -clike 'SPAWN_*'))
}

# ---- P-C4-CONVERGE-LOWMED-FASTLANE (dispatch 3.E.10) : a LOW converge round with a
# TRIPWIRE external provider => converges GO, the provider is NEVER invoked (no
# external call, no egress, no budget burn - structural), the recorded lane is the
# honest 'MISSING', and NO external ledger file exists under the run root.
$runFL = New-RunRoot; $repoFL = New-AppRepo 'repo_c4_fastlane'; $dirFL = New-NotifyDir 'c4_fastlane'
$ctxFL = New-Ctx $runFL 'c4-fastlane' $dirFL 0 1
$wFL = New-SlotWorld 'slot_c4_fastlane' $runFL -RoundId 'round-0'
$script:c4FlRoot = $wFL.root
$script:c4FlTrip = 0
$provFL = { param($q) return @{ end_report_path = (Get-SlotWorldEr $script:c4FlRoot); session_root = $script:c4FlRoot } }
$seamFL = { param($info) Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value 'c4 fastlane edit' -Encoding Ascii }
$extTrip = { param($info) $script:c4FlTrip++; throw 'TRIPWIRE: external provider invoked on a LOW round (fast lane violated)' }
$resFL = Invoke-ConvergeS3B $ctxFL $repoFL $seamFL $provFL @{ ExternalProvider = $extTrip }
Expect-Value 'P-C4-CONVERGE-LOWMED-FASTLANE' 'True' { [bool]($resFL.converged -and $resFL.go -and (-not $resFL.stopped)) }
Expect-Value 'P-C4-CONVERGE-LOWMED-FASTLANE-ZERO-SEAM' '0' { $script:c4FlTrip }
Expect-Value 'P-C4-CONVERGE-LOWMED-FASTLANE-ROW-LANE' 'MISSING' {
  $rows = Read-NeoIterationManifest -RunRoot $runFL
  [string](Get-NeoProp $rows[$rows.Count - 1] 'external_lane_status')
}
Expect-Value 'P-C4-CONVERGE-LOWMED-FASTLANE-NO-LEDGERS' 'True' {
  [bool]((-not (Test-Path -LiteralPath (Join-Path $runFL 'external_call_ledger.jsonl'))) `
    -and (-not (Test-Path -LiteralPath (Join-Path $runFL 'external_slice_call_ledger.jsonl'))) `
    -and (-not (Test-Path -LiteralPath (Join-Path $runFL 'external_verdict_ledger.jsonl'))))
}

# ---- N-C4-CONVERGE-HIGH-NO-PROVIDER : a HIGH round with a null/absent external
# provider seam => routed fail-closed STOP EXTERNAL_REQUIRED_UNAVAILABLE (a HIGH
# round has NO default external channel; manual-external fallback).
$runHN = New-RunRoot; $repoHN = New-AppRepo 'repo_c4_noprov'; $dirHN = New-NotifyDir 'c4_noprov'
$ctxHN = New-Ctx $runHN 'c4-noprov' $dirHN 0 1
$wHN = New-SlotWorld 'slot_c4_noprov' $runHN -RoundId 'round-0'
$script:c4HnRoot = $wHN.root
$provHN = { param($q) return @{ end_report_path = (Get-SlotWorldEr $script:c4HnRoot); session_root = $script:c4HnRoot } }
$seamHN = { param($info) Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value 'c4 noprov edit' -Encoding Ascii }
$resHN = Invoke-ConvergeS3B $ctxHN $repoHN $seamHN $provHN @{ RiskRow = $rowHigh; RiskClass = 'high' }
Expect-StopResult 'N-C4-CONVERGE-HIGH-NO-PROVIDER' $resHN.stop 'EXTERNAL_REQUIRED_UNAVAILABLE' 'ESCALATION_STOP' $runHN $dirHN

# ---- N-C4-CONVERGE-HIGH-PROVIDER-THREW : the seam THROWING on a HIGH round =>
# routed fail-closed STOP (the seam return/throw is never authority).
$runHT = New-RunRoot; $repoHT = New-AppRepo 'repo_c4_provthrew'; $dirHT = New-NotifyDir 'c4_provthrew'
$ctxHT = New-Ctx $runHT 'c4-provthrew' $dirHT 0 1
$wHT = New-SlotWorld 'slot_c4_provthrew' $runHT -RoundId 'round-0'
$script:c4HtRoot = $wHT.root
$provHT = { param($q) return @{ end_report_path = (Get-SlotWorldEr $script:c4HtRoot); session_root = $script:c4HtRoot } }
$seamHT = { param($info) Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value 'c4 provthrew edit' -Encoding Ascii }
$extHT = { param($info) throw 'external channel exploded (fixture)' }
$resHT = Invoke-ConvergeS3B $ctxHT $repoHT $seamHT $provHT @{ RiskRow = $rowHigh; RiskClass = 'high'; ExternalProvider = $extHT }
Expect-StopResult 'N-C4-CONVERGE-HIGH-PROVIDER-THREW' $resHT.stop 'EXTERNAL_REQUIRED_UNAVAILABLE' 'ESCALATION_STOP' $runHT $dirHT

# ---- P-C4-CONVERGE-HIGH-EXTERNAL-GO : the END-TO-END positive - a HIGH round whose
# external provider runs the REAL adapter (Invoke-NeoExternalAudit) under a STUB
# invoker seam (fixture attestation + fixture credential; the live invoker stays
# tripwired) => write-ahead budget entries land at BOTH levels, the packet builds
# from the REAL round bundle, the verdict record lands round-bound, the wrapper
# derives GO from DISK, gate C re-derives GO => the HIGH round CONVERGES.
$runHG = New-RunRoot; $repoHG = New-AppRepo 'repo_c4_highgo'; $dirHG = New-NotifyDir 'c4_highgo'
$ctxHG = New-Ctx $runHG 'c4-highgo' $dirHG 0 1
$wHG = New-SlotWorld 'slot_c4_highgo' $runHG -RoundId 'round-0'
$script:c4HgRoot = $wHG.root
$script:c4HgBundleRel = $wHG.bundleRel
$script:c4HgAtt = $c4AttOk
$script:c4HgCred = $c4Cred
$provHG = { param($q) return @{ end_report_path = (Get-SlotWorldEr $script:c4HgRoot); session_root = $script:c4HgRoot } }
$seamHG = { param($info) Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value 'c4 highgo edit' -Encoding Ascii }
$extHG = { param($info)
  return (Invoke-NeoExternalAudit -RunRoot $info.run_root -SliceId $info.slice_id -RoundId $info.round_id `
    -SessionRoot $info.session_root -BundleRef $script:c4HgBundleRel -Timestamp $info.timestamp_utc `
    -StampedBy 'm1' -AttestationPath $script:c4HgAtt -CredentialPath $script:c4HgCred -InvokerSeam $script:c4StubGo)
}
$resHG = Invoke-ConvergeS3B $ctxHG $repoHG $seamHG $provHG @{ RiskRow = $rowHigh; RiskClass = 'high'; ExternalProvider = $extHG }
Expect-Value 'P-C4-CONVERGE-HIGH-EXTERNAL-GO' 'True' { [bool]($resHG.converged -and $resHG.go -and (-not $resHG.stopped)) }
Expect-Value 'P-C4-CONVERGE-HIGH-GO-ROW-LANE' 'GO' {
  $rows = Read-NeoIterationManifest -RunRoot $runHG
  [string](Get-NeoProp $rows[$rows.Count - 1] 'external_lane_status')
}
Expect-Value 'P-C4-CONVERGE-HIGH-GO-BUDGET-BOTH-LEVELS' 'True' {
  $runId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $runHG) 'run_id')
  # assignment form, NOT @(call) - the ,@() reader return convention (see :136).
  $runLed = Read-NeoRunLedgerEntries -Path (Join-Path $runHG 'external_call_ledger.jsonl') -SchemaId 'neo:attempt_ledger_entry' -Index $index -Label 'external_call_ledger' -ExpectedRunId $runId
  $slLed = Read-NeoExternalSliceCallEntries -RunRoot $runHG -Index $index -ExpectedRunId $runId
  $vLed = Read-NeoExternalVerdictEntries -Path (Join-Path $runHG 'external_verdict_ledger.jsonl') -Index $index
  [bool](($runLed.Count -eq 1) -and (-not [bool](Get-NeoProp $runLed[0] 'refused')) `
    -and ($slLed.Count -eq 1) -and (-not [bool](Get-NeoProp $slLed[0] 'refused')) `
    -and (([string](Get-NeoProp $slLed[0] 'run_ledger_ref_kind')) -ceq 'CONSUMED') `
    -and ($vLed.Count -eq 1) -and (([string](Get-NeoProp $vLed[0] 'verdict')) -ceq 'GO') `
    -and (([string](Get-NeoProp $vLed[0] 'model_id')) -ceq 'gpt-5.5'))
}

# ---- STRUCTURAL (dispatch 3.D preservation) : no codex invocation inside
# orch_loop.ps1 - the module text carries NO live-invoker call and NO codex token;
# the ONLY external functions it calls are the shared derivation + containment
# helpers. Plus: the whole C4 section ran without the tripwire firing (no suite
# path reached the live invoker) - restore the invoker afterwards.
Expect-Value 'P-C4-STRUCTURAL-NO-INVOKER-IN-LOOP' 'True' {
  $modText = [System.IO.File]::ReadAllText((Join-Path $orchDir 'orch_loop.ps1'))
  [bool](($modText -notmatch 'Invoke-NeoExternalCodex') -and ($modText -notmatch 'codex\s+exec'))
}
Expect-Value 'P-C4-STRUCTURAL-TRIPWIRE-NEVER-FIRED' '0' { $script:c4LiveTrip }
${function:Invoke-NeoExternalCodex} = $script:c4OrigInvoker

# ---- AS18 judging-from-birth probes for the C4 files (existing globs, no map edit).
Expect-Value 'P-C4-AS18-EXTERNAL-JUDGING' 'test_harness' { Resolve-NeoArtifactClass (Get-NeoClassMap $liveMap) '.neo/scripts/orchestrator/orch_external.ps1' }
Expect-Value 'P-C4-AS18-EXTERNAL-SUITE-JUDGING' 'test_harness' { Resolve-NeoArtifactClass (Get-NeoClassMap $liveMap) '.neo/scripts/orchestrator/harness/orch_external_suite.ps1' }
Expect-Value 'P-C4-AS18-VERDICT-SCHEMA-JUDGING' 'constraint' { Resolve-NeoArtifactClass (Get-NeoClassMap $liveMap) '.neo/schema/external_audit_verdict.schema.json' }
Expect-Value 'P-C4-AS18-SLICE-ENTRY-SCHEMA-JUDGING' 'constraint' { Resolve-NeoArtifactClass (Get-NeoClassMap $liveMap) '.neo/schema/external_slice_call_entry.schema.json' }

# =============================================================================
# SUMMARY + RESIDUE-CLEAN SECOND PASS
# =============================================================================
$total = @($script:results).Count
$failed = @($script:results | Where-Object { -not $_.pass })
$skips = @($script:results | Where-Object { $_.kind -eq 'skip' })
$passCount = $total - $failed.Count

Write-Host ""
Write-Host ("Results: {0}/{1} PASS ({2} skip-disclosed)" -f $passCount, $total, $skips.Count) -ForegroundColor Cyan

if ($ProofOut) {
  $proof = [pscustomobject]@{
    suite     = 'orch_loop_suite'
    timestamp = $TS
    run_tag   = $tag
    total     = $total
    passed    = $passCount
    failed    = $failed.Count
    skipped   = $skips.Count
    results   = $script:results
  }
  $proofDir = Split-Path -Parent $ProofOut
  if ($proofDir -and -not (Test-Path -LiteralPath $proofDir)) { New-Item -ItemType Directory -Force -Path $proofDir | Out-Null }
  $proof | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ProofOut -Encoding Ascii
  Write-Host "proof: $ProofOut"
}

if (-not $KeepScratch) {
  Remove-Item -Recurse -Force -LiteralPath $ScratchRoot -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $ScratchRoot) {
    Write-Host "RESIDUE: scratch root still present after removal: $ScratchRoot" -ForegroundColor Red
    exit 1
  }
  Write-Host "residue-clean: scratch (mirrors + repos + run-roots + notify dirs) removed"
}

if ($failed.Count -gt 0) { exit 1 } else { exit 0 }
