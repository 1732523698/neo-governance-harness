# =============================================================================
# orch_run_suite.ps1 - NEO 4.0-P4-AUTONOMY INTEGRATE negative-fixture suite
# =============================================================================
# Proves the one-call run surface (orch_run.ps1) per integrate dispatch 3.D:
#   1  gate-not-ready BOTH paths (+ readiness-guard neuter-flip)
#   2  approval binding + explicit decision + EXACTLY-ONE raw multiplicity
#      (+ decision-check AND multiplicity-check neuter-flips)
#   3  post-gate pin drift at execute entry (gov + app)
#   4  app-pin tamper => STOP, ALL windows (round-0 pre-dispatch / mid-run
#      profile / mid-run risk-register / END-entry converged) + THE CROSS-CASE
#      (the STOP reaches DECISION_NEEDED with the MISMATCH disclosure) + the
#      path-conditionality neuter-flip + the clean transparent control
#   5  frozen-plan/universe carry PATH-CONDITIONAL (EXTRA / OMISSION /
#      not_reached disclosure + its neuter-flip)
#   6  STOP-path END assembly end-to-end + the FIXED reduction contract
#   6b disposition tri-state at BOTH boundaries (public helper driven directly;
#      transition-boundary behavioral proof via an envelope-forging converge
#      override; tri-state neuter-flip)
#   7  orch_loop-not-sourced carry proof (child processes)
#   8  prepare-path purity (structural + behavioral)
#   9  caps/manifest fail-closed through the frozen readers (+ structural
#      no-default-caps scan)
#   10 serial-discipline structural scan
#   11 multi-slice serial order + halt-on-stop (+ two-GO control)
#   12 STRUCTURALLY INCAPABLE of a real codex call (tripwire + single stubbed
#      plan-audit helper + structural scans)
#   13 residue-clean second pass; fixture app-root worlds carry their OWN
#      .neo\schema classmap + governance_manifest schema
# ASCII-only (D10). Scratch under TEMP only; run this suite in its OWN
# powershell.exe per run (it drives orch_clarity surfaces - the C5 suite's
# single-run-per-process discipline is inherited). Writes NO AUDIT_RESULT.
# exit 0/1.
# =============================================================================
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'

$orchDir = Split-Path -Parent $PSScriptRoot   # ...\.neo\scripts\orchestrator
. "$orchDir\orch_run.ps1"                     # sources BOTH chains (clarity + loop)

# ---- STRUCTURAL TRIPWIRE (dispatch 3.D.12): the live invoker is unreachable ----
# script:-qualified so the override lands in the SUITE's script scope (where the
# dot-sourced module's own definition lives) even when armed from inside a
# function - an unqualified function-drive assignment inside a function would
# create a LOCAL definition that evaporates on return (the scoping trap).
$script:liveTrip = 0
function Set-Tripwire {
  ${function:script:Invoke-NeoExternalCodex} = { param($PacketDir, $OutFile, $TimeoutSec)
    $script:liveTrip++; throw 'TRIPWIRE: live codex invoker reached (structurally forbidden in this suite)' }
}
Set-Tripwire

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_run_integrate_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors the orch_govmanifest_suite framing) --------------
$script:results = @()
function Record($name, $pass, $detail, $kind = 'negative') {
  $script:results += [pscustomobject]@{ guard = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  $ktag = if ($kind -eq 'negative') { 'GUARD' } elseif ($kind -eq 'skip') { 'SKIP ' } else { 'info ' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $ktag, $name, $detail) -ForegroundColor $col
}
function Expect-Block($name, $codeSubstr, $sb) {
  try { & $sb | Out-Null; Record $name $false 'NO BLOCK (guard did not fire)' 'negative' }
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
  try { $r = & $sb; Record $name $true ("= " + [string]$r) 'positive' }
  catch { Record $name $false ('unexpected error: ' + $_.Exception.Message) 'positive' }
}
function Expect-Value($name, $want, $sb) {
  try {
    $r = [string](& $sb)
    if ($r -ceq [string]$want) { Record $name $true ("= " + $r) 'positive' }
    else { Record $name $false ("got '$r' want '$want'") 'positive' }
  } catch { Record $name $false ('unexpected error: ' + $_.Exception.Message) 'positive' }
}
function Get-EmlFiles([string]$dir) {
  if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { return @() }
  return @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -like '*.eml.txt' })
}

# ---- shared fixture plumbing ----------------------------------------------------
$TS = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$index = Get-NeoRunSchemaIndex
$capsDefault = @{ max_fix_rounds_per_slice = 3; max_external_calls = 25; max_wall_clock_hours = 4; max_spend = 100 }
$stubExe = Join-Path $orchDir 'orch_auditor_stub.ps1'
$evidenceDir = Join-Path $ScratchRoot 'evidence'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$script:seq = 0
function New-RunRoot {
  $script:seq++
  $r = Join-Path $ScratchRoot ("run{0}" -f $script:seq)
  New-Item -ItemType Directory -Force -Path $r | Out-Null
  [void](New-NeoRunManifest -RunRoot $r -Caps $capsDefault -Timestamp $TS)
  return $r
}
function New-NotifyDir([string]$case) {
  $d = Join-Path $ScratchRoot ("notify_" + $case)
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

# fixture attestation + credential twins (NEVER the live files; the C4/C5 precedent).
$attOk = Join-Path $ScratchRoot 'att_ok.md'
Set-Content -LiteralPath $attOk -Value @('# fixture attestation twin', 'STATUS: **APPROVED / IN FORCE (fixture)**') -Encoding Ascii
$credOk = Join-Path $ScratchRoot 'auth_fixture.json'
Set-Content -LiteralPath $credOk -Value '{}' -Encoding Ascii

$repoRoot = Resolve-NeoRoot $orchDir
$liveMap = Join-Path $repoRoot '.neo\schema\artifact_classes.json'
$liveGovSchema = Join-Path $repoRoot '.neo\schema\governance_manifest.schema.json'

# governed-root mirror: the floor is derived DYNAMICALLY from the module's own
# $script:NeoGovDefaultMandatoryRels (forward-compatible: this mirror stays a
# positive V1 control across future floor lockstep bumps - the C5 hard-coded-
# mirror lesson). *.json floor members get valid-JSON placeholders (the mirror
# schema dir is INDEXED by the reverify F4 path); the two LIVE schema members
# are copied verbatim so the mirror's oracle is the real rule.
$script:govSeq = 0
function New-GovMirror {
  $script:govSeq++
  $root = Join-Path $ScratchRoot ("gov{0}" -f $script:govSeq)
  foreach ($rel in @($script:NeoGovDefaultMandatoryRels)) {
    $full = Join-Path $root (([string]$rel) -replace '/', '\')
    $parent = Split-Path -Parent $full
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    if (([string]$rel) -like '*.json') { Set-Content -LiteralPath $full -Value '{"a":1}' -Encoding Ascii }
    else { Set-Content -LiteralPath $full -Value ("# floor member " + $rel) -Encoding Ascii }
  }
  Copy-Item -LiteralPath $liveMap -Destination (Join-Path $root '.neo\schema\artifact_classes.json') -Force
  Copy-Item -LiteralPath $liveGovSchema -Destination (Join-Path $root '.neo\schema\governance_manifest.schema.json') -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\scripts\orchestrator\harness') | Out-Null
  return $root
}

# quiet git (fixture-local; mirrors orch_loop_suite/orch_diff_suite)
function Invoke-GitQuiet { param([string]$Repo, [string[]]$GitArgs)
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & git -C $Repo @GitArgs 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
}
# app-root mirror: its OWN .neo\schema classmap + governance_manifest schema
# (dispatch 3.D.13 - the New-NeoClarityAppPin onboarding precondition), the app
# profile, a risk register (pinned by EXPLICIT hash), builder surfaces, and a
# git repo (the frozen loop's NF-3 repo requirement). Content avoids every
# engine governed token so clean rounds derive low.
$script:appSeq = 0
function New-AppMirror {
  $script:appSeq++
  $root = Join-Path $ScratchRoot ("app{0}" -f $script:appSeq)
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\schema') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root 'app') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root 'locked') | Out-Null
  Copy-Item -LiteralPath $liveMap -Destination (Join-Path $root '.neo\schema\artifact_classes.json') -Force
  Copy-Item -LiteralPath $liveGovSchema -Destination (Join-Path $root '.neo\schema\governance_manifest.schema.json') -Force
  Set-Content -LiteralPath (Join-Path $root 'NEO_APP_PROFILE.json') -Value '{"fixture":"app profile"}' -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root 'risk_register.json')   -Value '{"fixture":"risk register"}' -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root 'app\widget.txt')       -Value 'hello widget' -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root 'locked\keep.txt')      -Value 'do not touch' -Encoding Ascii
  Invoke-GitQuiet $root @('init', '-q')
  Invoke-GitQuiet $root @('config', 'user.email', 'neo@sandbox.local')
  Invoke-GitQuiet $root @('config', 'user.name', 'neo-fixture')
  Invoke-GitQuiet $root @('config', 'commit.gpgsign', 'false')
  Invoke-GitQuiet $root @('config', 'core.autocrlf', 'false')
  Invoke-GitQuiet $root @('add', '-A')
  Invoke-GitQuiet $root @('commit', '-q', '-m', 'base')
  return $root
}
$script:worldSeq = 0
function New-World([string]$case) {
  $script:worldSeq++
  $session = Join-Path $ScratchRoot ("session{0}" -f $script:worldSeq)
  New-Item -ItemType Directory -Force -Path $session | Out-Null
  return @{
    run = (New-RunRoot); session = $session; notify = (New-NotifyDir $case)
    gov = (New-GovMirror); app = (New-AppMirror)
  }
}

# ---- default plan inputs (fresh copies per call) ---------------------------------
function New-DefSlices([switch]$Two) {
  $s = @(@{ slice_id = 'sA'; approved_paths = @('app'); protected_paths = @('locked')
            acceptance_harness_paths = @('harness/sA_fixture_suite.ps1'); risk_row_ref = 'r1' })
  if ($Two) {
    $s += @{ slice_id = 'sB'; approved_paths = @('app'); protected_paths = @('locked')
             acceptance_harness_paths = @('harness/sB_fixture_suite.ps1'); risk_row_ref = 'r1' }
  }
  return ,$s
}
# row shape = the frozen clarity_freeze_record schema's EXACT member set
# (row_id + risk_class + optional audit_tier; additionalProperties:false).
function New-DefRows { return ,@( @{ row_id = 'r1'; risk_class = 'low'; audit_tier = 'lightweight' } ) }
$script:profileObj = [pscustomobject]@{
  denylist = [pscustomobject]@{ entries = @([pscustomobject]@{ pattern = 'forbidden/**'; is_glob = $true }) }
  risk_tokens = [pscustomobject]@{ auth_tokens = @('zz-custom-token-a'); fin_tokens = @('zz-custom-token-b') }
}
$script:routerProfile = Resolve-NeoRouterProfile -Profile $script:profileObj
function New-DefRegister {
  return ,@( @{ item_id = 'amb-1'; surface = 'presentation wording'; classification = 'documented_default'
                documented_default = 'plain ASCII output' } )
}
function New-DefDispatch {
  return @{
    goal = 'converge slice goal'
    allowlist_items = @(@{ rel = 'app/widget.txt'; role = 'current_artifact' })
    test_plan = @('run suite'); stop_conditions = @('ambiguity')
    proposed_edits = @('app/widget.txt')
  }
}

# ---- counting stub seams + the faithful codex CLI output builder (C5 pattern) ----
# FIX-ROUND-1: NO GetNewClosure anywhere in this suite (a GetNewClosure block
# binds to a dynamic module that cannot resolve script-scope functions in a
# clean process - the manager-verified 56/79 divergence). Stubs are PLAIN
# bound scriptblocks reading well-known $script: state.
$global:NeoRunSeamCalls = 0
function New-CodexOutput([string]$HeaderModel, [string[]]$BodyLines) {
  $hdr = @('OpenAI Codex v0.142.5', '--------', 'workdir: C:\fixture\packet')
  if ($null -ne $HeaderModel) { $hdr += ('model: ' + $HeaderModel) }
  $hdr += @('provider: openai', 'approval: never', 'sandbox: read-only', 'session id: fixture-0000', '--------')
  $lead = @('user', 'Perform the plan audit per the packet.', 'codex', 'Reading the packet.', 'exec', 'bash -lc "cat packet.txt"', 'exec succeeded')
  $final = @('codex') + $BodyLines
  $tail = @('tokens used', '12,345') + $BodyLines
  return @($hdr + $lead + $final + $tail)
}
$script:StubGoLines   = New-CodexOutput 'gpt-5.5' @('VERDICT: GO', 'FINDINGS: plan fixture clean')
$script:StubNoGoLines = New-CodexOutput 'gpt-5.5' @('VERDICT: NO-GO', 'FINDINGS: plan fixture defect')
$stubGo = { param($io)
  $global:NeoRunSeamCalls++
  Set-Content -LiteralPath $io.out_file -Value $script:StubGoLines -Encoding Ascii
  return @{ ok = $true; class = 'OK'; detail = 'stub' } }
$stubNoGo = { param($io)
  $global:NeoRunSeamCalls++
  Set-Content -LiteralPath $io.out_file -Value $script:StubNoGoLines -Encoding Ascii
  return @{ ok = $true; class = 'OK'; detail = 'stub' } }

# THE ONE prepare entry point for this suite (STRUCTURAL-SINGLE-PREPARE-HELPER):
# ALWAYS a stub plan-audit invoker seam + the fixture attestation/credential twins.
function Invoke-PrepareFix($w, $seam, [hashtable]$over = @{}) {
  $a = @{
    RunRoot = $w.run; SessionRoot = $w.session
    InstructionDigestRef = ('fixture-instruction#sha256:' + ('a' * 64))
    AmbiguityRegister = (New-DefRegister); SlicePlan = (New-DefSlices); RiskRows = (New-DefRows)
    Profile = $script:profileObj; AttestedGapRecords = @()
    GovernedRoot = $w.gov; AppRoot = $w.app; RiskRegisterRel = 'risk_register.json'
    StampedBy = 'fixture-supervisor'; Timestamp = $TS
    PlanAuditAttestationPath = $attOk; PlanAuditCredentialPath = $credOk
    PlanAuditInvokerSeam = $seam; NotifyTestModeDir = $w.notify; Index = $index
  }
  foreach ($k in @($over.Keys)) { $a[$k] = $over[$k] }
  return (Invoke-NeoRunPrepare @a)
}

# ---- the approval-ledger fixture writers (the MANAGER-role act; engine READS) ----
function New-GateEntry([string]$ref, [string]$kind = 'human_start_approval', [string]$by = 'raphael', [string]$at = $TS) {
  # schema-shaped: ALL SIX required keys of the neo:human_gate_ledger entry.
  return [ordered]@{ gate_ref = $ref; gate_kind = $kind; authorized_by = $by
                     recorded_at = $at; app_slug = 'fixture-app'; authorized_paths = @('app') }
}
$script:ledSeq = 0
function Write-Approval($entries) {
  $script:ledSeq++
  $p = Join-Path $ScratchRoot ("gate_ledger{0}.json" -f $script:ledSeq)
  (@{ entries = @($entries) } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $p -Encoding Ascii
  return $p
}
function Get-ExpectedRef($w, [string]$seg = 'NONE') {
  $man = Read-NeoRunManifest -RunRoot $w.run
  $freeze = Get-NeoClarityLatestFreeze -RunRoot $w.run -Index $index
  $pr = [string](Get-NeoProp $freeze 'plan_round')
  $paths = Get-NeoClarityPlanAuditPaths $w.session $pr
  return (Get-NeoRunStartGateRef -RunId ([string](Get-NeoProp $man 'run_id')) -PlanRound $pr `
    -FreezeRecordSha256 ([string](Get-NeoProp $freeze 'record_sha256')) `
    -BundleDiffHash (Get-NeoSha256File $paths.bundle_full) -AutonomySegment $seg)
}

# ---- AUTO-mode fixture plumbing (slice 1d; SCRATCH twins ONLY - never the
# real .neo\AUTO_MODE_ATTESTATION.md) ----------------------------------------
$script:attAutoSeq = 0
function New-AutoAttestation([string]$declRoot, [string]$tier = 'LOW', [string]$flavor = 'ok') {
  $script:attAutoSeq++
  $p = Join-Path $ScratchRoot ("att_auto{0}_{1}.md" -f $script:attAutoSeq, $flavor)
  $lines = @('# fixture AUTO attestation twin (SCRATCH copy; fixture-declared envelope)')
  if ($flavor -cne 'unsigned') { $lines += 'STATUS: **APPROVED / IN FORCE (fixture twin)**' }
  if ($flavor -ceq 'revoked') { $lines += 'STATUS: REVOKED (fixture twin revocation)' }
  if ($flavor -cne 'noroots') { $lines += ("  roots: DEV-only fixture envelope. The run root must live under '" + $declRoot + "'.") }
  $lines += ('  max_risk_tier: ' + $tier + '. Every risk row of the slice plan must fit.')
  $lines += '  plan_audit: converged GO required.'
  Set-Content -LiteralPath $p -Value $lines -Encoding Ascii
  return $p
}
function Write-AutoRecord($w, [string]$attPath, [hashtable]$over = @{}) {
  $man = Read-NeoRunManifest -RunRoot $w.run
  $rec = [ordered]@{
    schema_id = 'neo:run_autonomy_mode'; run_id = [string](Get-NeoProp $man 'run_id')
    autonomy_mode = 'auto'; declared_by = 'raphael-fixture-manager'; declared_at = $TS
    attestation_sha256 = (Get-NeoSha256File $attPath)
  }
  foreach ($k in @($over.Keys)) {
    if ($null -eq $over[$k]) { $rec.Remove($k) } else { $rec[$k] = $over[$k] }
  }
  $p = Join-Path $w.run 'autonomy_mode.json'
  ($rec | ConvertTo-Json) | Set-Content -LiteralPath $p -Encoding Ascii
  return (Get-NeoSha256File $p)
}
function Write-AutoRecordRaw($w, [string]$text) {
  $p = Join-Path $w.run 'autonomy_mode.json'
  Set-Content -LiteralPath $p -Value $text -Encoding Ascii
  return (Get-NeoSha256File $p)
}
# fully-prepared AUTO world: valid twin + record BEFORE prepare; the attested
# approval entry (the MANAGER-role act citing the standing attestation) bound
# to the 6-segment hash-bearing tuple.
function New-AutoPreparedWorld([string]$case, [switch]$Two) {
  $w = New-World $case
  $att = New-AutoAttestation $ScratchRoot
  $seg = Write-AutoRecord $w $att
  $slices = if ($Two) { New-DefSlices -Two } else { New-DefSlices }
  $pkg = Invoke-PrepareFix $w $stubGo @{ SlicePlan = $slices; AutonomyAttestationPath = $att }
  $ref = Get-ExpectedRef $w $seg
  $sliceIds = @('sA'); if ($Two) { $sliceIds = @('sA', 'sB') }
  $entry = New-GateEntry $ref 'attested_start_approval' 'Raphael (standing AUTO attestation fixture-twin)'
  return @{ w = $w; pkg = $pkg; ref = $ref; seg = $seg; att = $att; sliceIds = $sliceIds
            approval = (Write-Approval @($entry)) }
}

# fully-prepared world: prepare (freeze -> stub plan audit -> gate) + a VALID
# single approval bound to the exact surfaced plan.
function New-PreparedWorld([string]$case, [switch]$Two) {
  $w = New-World $case
  $slices = if ($Two) { New-DefSlices -Two } else { New-DefSlices }
  $pkg = Invoke-PrepareFix $w $stubGo @{ SlicePlan = $slices }
  $ref = Get-ExpectedRef $w
  $sliceIds = @('sA'); if ($Two) { $sliceIds = @('sA', 'sB') }
  return @{ w = $w; pkg = $pkg; ref = $ref; sliceIds = $sliceIds
            approval = (Write-Approval @(New-GateEntry $ref)) }
}

# ---- slot worlds (compact clone of the orch_loop_suite S3b pattern) --------------
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
    -SchemaId 'neo:subsession_end_report' -SchemaVersion '4.0-P4-INTEGRATE' -ProducerRole 'builder' -ProducerClass 'strong_producer' `
    -ValidatorRole 'builder' -ValidatorClass 'strong_producer' -ValidatorNAReason 'raw builder evidence pre-audit' `
    -Timestamp $TS -DeclaredPaths @('./app/') -DeclaredSurfaces @('filesystem') -SourcePackets @() -GateRef $null)
  Set-NeoArtifactHash $er
  return $er
}
$script:slotSeq = 0
function New-SlotWorld([string]$name, [string]$runRoot, [string]$RoundId = 'round-0', [string]$Recommendation = 'GO') {
  $script:slotSeq++
  # auditor identity UNIQUE per spawn (the real cold-spawn model): XC2's spawn
  # correlation is (round_id + auditor_identity) exactly-one - two slices' GO
  # rounds in ONE run root share 'round-0' (the frozen XC2 hard-codes the
  # 'round-' prefix at orch_loop:2314), so the identity is what disambiguates.
  $auditorId = ('isolated-auditor-cold-' + $script:slotSeq)
  $root = Join-Path $ScratchRoot ("slot{0}_{1}" -f $script:slotSeq, $name)
  # slug UNIQUE per slot world: two worlds registered in ONE run root must
  # not collide on the spawn-ledger bundle_ref rel (spawn correlation).
  $slug = ('ss-run' + $script:slotSeq)
  $slugDir = Join-Path $root "NEO_SESSION\$slug"
  $auditDir = Join-Path $slugDir 'audit'
  New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
  $proofExit = if ($Recommendation -ceq 'NO-GO') { 'exit 1' } else { 'exit 0' }
  $noTests = ($Recommendation -ceq 'NEEDS-MORE')
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
  $bundle = New-NeoAuditBundle -BundleId ("b-" + $script:slotSeq + "-" + $name) -MemberItems $members -ApprovedPaths @('./app/') `
    -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier 'high' -Timestamp $TS -Index $index -OutPath $bundlePath
  $arPath = Join-Path $auditDir 'AUDIT_RESULT.json'
  & $stubExe -BundlePath $bundlePath -BundleDir $root -OutPath $arPath -Timestamp $TS -AuditorIdentity $auditorId | Out-Null
  $derived = [string](Read-NeoJsonFile $arPath).recommendation
  if ($derived -cne $Recommendation) { throw "New-SlotWorld(${name}): stub derived '$derived' but the fixture targeted '$Recommendation'" }
  $bundleRel = "./NEO_SESSION/$slug/audit/AUDIT_BUNDLE.json"
  Write-NeoJsonFile $erPath (New-SlotEnd $slug (@{ recommendation = $Recommendation; auditor_identity = $auditorId; bundle_ref = $bundleRel }) -NoTests:$noTests)
  [void](Add-NeoSpawnLedgerEntry -RunRoot $runRoot -SpawnId ("sp-" + $script:slotSeq + "-" + $name) -AuditorIdentity $auditorId `
    -BundleRef $bundleRel -RoundId $RoundId -Timestamp $TS)
  return @{ root = $root; erPath = $erPath; bundleRel = $bundleRel }
}
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

# the ONE execute entry point (per-fixture notify dir; stub seams only).
function Invoke-ExecuteFix($pw, $seam, $provider, [string]$case, [hashtable]$over = @{}) {
  $dir = New-NotifyDir ("exec_" + $case)
  $dispatch = @{}
  foreach ($sid in @($pw.sliceIds)) { $dispatch[$sid] = New-DefDispatch }
  $a = @{
    RunRoot = $pw.w.run; SessionRoot = $pw.w.session; GovernedRoot = $pw.w.gov; AppRoot = $pw.w.app
    ApprovalLedgerPath = $pw.approval; RouterProfile = $script:routerProfile
    MasterIdentity = 'm1'; BuilderIdentity = 'b1'
    SliceDispatch = $dispatch; EvidencePath = $evidenceDir; Timestamp = $TS
    NotifyTestModeDir = $dir; Index = $index
    BuilderSeam = $seam; AuditProvider = $provider
  }
  foreach ($k in @($over.Keys)) { $a[$k] = $over[$k] }
  $r = Invoke-NeoRunExecute @a
  return @{ result = $r; notify = $dir }
}

# fabricated iteration rows (frozen writer; the orch_loop_suite trail pattern).
function New-StopRowFields([string]$slice, [int]$round, [string]$stopCode) {
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

# in-process module patcher (neuter-flip proofs): copy orch_run.ps1 with an
# EXACT-match patch, absolute-root the dot-source dir, source it (redefines the
# public surfaces), run the scenario, then RE-SOURCE the real module + re-arm
# the tripwire. The patch MUST bind or the fixture is invalid.
function New-PatchedRunModule([string]$name, [string]$find, [string]$replace) {
  $src = [System.IO.File]::ReadAllText((Join-Path $orchDir 'orch_run.ps1'))
  if ($src.IndexOf($find) -lt 0) { throw ("neuter patch text not found for " + $name) }
  $patched = $src.Replace($find, $replace)
  $patched = $patched.Replace('$script:NeoRunDir = $PSScriptRoot', ('$script:NeoRunDir = ' + "'" + $orchDir + "'"))
  $p = Join-Path $ScratchRoot ("patched_" + $name + '.ps1')
  [System.IO.File]::WriteAllText($p, $patched, (New-Object System.Text.UTF8Encoding($false)))
  return $p
}
# NOTE (the scoping trap, proven in this build): restoring the REAL module MUST
# be a TOP-LEVEL dot-source statement (`. $realModule`), NEVER a call into a
# helper function - a dot-source inside a function defines the functions in the
# helper's local scope and the script scope silently keeps the PATCHED module.
$realModule = Join-Path $orchDir 'orch_run.ps1'

Write-Host "NEO 4.0-P4-AUTONOMY INTEGRATE - orch_run one-call run surface suite" -ForegroundColor Cyan
Write-Host "scratch: $ScratchRoot"

# =============================================================================
# SECTION A - the public helpers driven directly (3.D.6b tri-state + gate ref)
# =============================================================================
Write-Host "=== SECTION A: gate-ref + disposition tri-state (helper boundary) ===" -ForegroundColor Cyan
Expect-Value 'P-RUN-GATEREF-DETERMINISTIC' ('NEO-RUN-START|rid|2|' + ('a' * 64) + '|' + ('b' * 64) + '|NONE') {
  Get-NeoRunStartGateRef -RunId 'rid' -PlanRound '2' -FreezeRecordSha256 ('a' * 64) -BundleDiffHash ('b' * 64) -AutonomySegment 'NONE'
}
Expect-Value 'P-RUN-GATEREF-AUTO-SEGMENT' ('NEO-RUN-START|rid|2|' + ('a' * 64) + '|' + ('b' * 64) + '|' + ('c' * 64)) {
  Get-NeoRunStartGateRef -RunId 'rid' -PlanRound '2' -FreezeRecordSha256 ('a' * 64) -BundleDiffHash ('b' * 64) -AutonomySegment ('c' * 64)
}
Expect-Block 'N-RUN-GATEREF-BLANK-PART' 'RUN_START_APPROVAL' {
  Get-NeoRunStartGateRef -RunId 'rid' -PlanRound ' ' -FreezeRecordSha256 ('a' * 64) -BundleDiffHash ('b' * 64) -AutonomySegment 'NONE'
}
Expect-Block 'N-RUN-GATEREF-SEPARATOR-IN-PART' 'RUN_START_APPROVAL' {
  Get-NeoRunStartGateRef -RunId 'r|d' -PlanRound '2' -FreezeRecordSha256 ('a' * 64) -BundleDiffHash ('b' * 64) -AutonomySegment 'NONE'
}
Expect-Block 'N-RUN-GATEREF-SEGMENT-SHAPE' 'RUN_START_APPROVAL' {
  # a case-variant token is neither NONE nor a lowercase sha256 => refused
  Get-NeoRunStartGateRef -RunId 'rid' -PlanRound '2' -FreezeRecordSha256 ('a' * 64) -BundleDiffHash ('b' * 64) -AutonomySegment 'none'
}
Expect-Block 'N-RUN-GATEREF-SEGMENT-BLANK' 'RUN_START_APPROVAL' {
  Get-NeoRunStartGateRef -RunId 'rid' -PlanRound '2' -FreezeRecordSha256 ('a' * 64) -BundleDiffHash ('b' * 64) -AutonomySegment ' '
}
Expect-Value 'P-RUN-TRISTATE-STOPPED' 'stopped' { (Assert-NeoRunConvergeDisposition -Envelope @{ stopped = $true; converged = $false }).shape }
Expect-Value 'P-RUN-TRISTATE-CONVERGED' 'converged' { (Assert-NeoRunConvergeDisposition -Envelope @{ stopped = $false; converged = $true }).shape }
Expect-Block 'N-RUN-TRISTATE-BOTH-TRUE' 'RUN_DISPOSITION' { Assert-NeoRunConvergeDisposition -Envelope @{ stopped = $true; converged = $true } }
Expect-Block 'N-RUN-TRISTATE-BOTH-FALSE' 'RUN_DISPOSITION' { Assert-NeoRunConvergeDisposition -Envelope @{ stopped = $false; converged = $false } }
Expect-Block 'N-RUN-TRISTATE-STOPPED-MISSING' 'RUN_DISPOSITION' { Assert-NeoRunConvergeDisposition -Envelope @{ converged = $true } }
Expect-Block 'N-RUN-TRISTATE-CONVERGED-MISSING' 'RUN_DISPOSITION' { Assert-NeoRunConvergeDisposition -Envelope @{ stopped = $false } }
Expect-Block 'N-RUN-TRISTATE-NON-BOOLEAN' 'RUN_DISPOSITION' { Assert-NeoRunConvergeDisposition -Envelope @{ stopped = 'true'; converged = $false } }
Expect-Block 'N-RUN-TRISTATE-NULL' 'RUN_DISPOSITION' { Assert-NeoRunConvergeDisposition -Envelope $null }

# =============================================================================
# SECTION B - approval binding + explicit decision + EXACTLY-ONE (3.D.2)
# =============================================================================
Write-Host "=== SECTION B: START-approval binding (the human decision) ===" -ForegroundColor Cyan
$refB = 'NEO-RUN-START|ridB|1|' + ('c' * 64) + '|' + ('d' * 64)
$refBstale = 'NEO-RUN-START|ridB|2|' + ('e' * 64) + '|' + ('f' * 64)   # a revised plan's ref

# missing (zero bound entries)
Expect-Block 'N-RUN-APPROVAL-MISSING' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refBstale)) -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
}
# stale: bound to plan_round 1 while the CURRENT expected ref is round 2
Expect-Block 'N-RUN-APPROVAL-STALE-ROUND' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB)) -ExpectedGateRef $refBstale -AutonomySegment 'NONE' -Index $index
}
# hash mismatch: same round, different freeze hash
Expect-Block 'N-RUN-APPROVAL-HASH-MISMATCH' 'RUN_START_APPROVAL' {
  $wrongHash = 'NEO-RUN-START|ridB|1|' + ('9' * 64) + '|' + ('d' * 64)
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $wrongHash)) -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
}
# correctly-BOUND record with a non-approval decision => refuse EACH.
# FIX-ROUND-1: plain scriptblock + $script:-scoped per-iteration value (NO
# GetNewClosure - the block must resolve the suite's script-scope helpers in
# a clean process; Expect-Block invokes it synchronously inside the iteration).
foreach ($bad in @(
    @('WRONG-GATE-CLASS', 'human_end_keep'),
    @('BLANK-DECISION', ''),
    @('UNKNOWN-TOKEN', 'approved'),
    @('CASING-VARIANT', 'Human_Start_Approval'),
    @('PENDING-TOKEN', 'pending'))) {
  $script:curKind = [string]$bad[1]
  Expect-Block ("N-RUN-APPROVAL-" + [string]$bad[0]) 'RUN_START_APPROVAL' {
    Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB $script:curKind)) -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
  }
}
# blank authorized_by on an otherwise valid approval => refuse
Expect-Block 'N-RUN-APPROVAL-BLANK-PRINCIPAL' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'human_start_approval' ' ')) -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
}
# MULTIPLICITY (EXACTLY-ONE on RAW tuple-bound entries BEFORE decision
# filtering). FIX-ROUND-1: same NO-GetNewClosure pattern as above.
foreach ($combo in @(
    @('APPROVE-APPROVE', 'human_start_approval'),
    @('APPROVE-DENY', 'human_end_keep'),
    @('APPROVE-PENDING', 'pending'),
    @('APPROVE-UNKNOWN', 'approved'),
    @('APPROVE-BLANK', ''),
    @('APPROVE-CASEVAR', 'Human_Start_Approval'))) {
  $script:curSecondKind = [string]$combo[1]
  Expect-Block ("N-RUN-APPROVAL-MULTI-" + [string]$combo[0]) 'RUN_START_APPROVAL' {
    Read-NeoRunStartApproval -LedgerPath (Write-Approval @((New-GateEntry $refB), (New-GateEntry $refB $script:curSecondKind))) `
      -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
  }
}
# control: a valid SINGLE bound record with the exact token => proceeds
Expect-Value 'P-RUN-APPROVAL-VALID-SINGLE' 'raphael' {
  [string](Get-NeoProp (Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB)) -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index) 'authorized_by')
}
# NEUTER-FLIP 1: gate_kind decision/pairing check neutered => the DENIED record
# passes AND a cross-paired record passes (fail-open both ways)
$patch1 = New-PatchedRunModule 'kindcheck' '  if ($kind -cne $expectedKind) {' '  if ($false) {'
. $patch1; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-DECISION-FAILS-OPEN' 'True' {
  $e = Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'human_end_keep')) -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
  [bool]($null -ne $e)   # the denied record was ACCEPTED - the guard is load-bearing
}
Expect-Value 'N-RUN-NEUTER-PAIRING-FAILS-OPEN' 'True' {
  # NF-A10 neuter proof: with the pairing guard gone, an attested-kind entry is
  # accepted for an INTERACTIVE (segment NONE) run - the guard is load-bearing.
  $e = Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'attested_start_approval')) -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
  [bool]($null -ne $e)
}
. $realModule; Set-Tripwire
# NEUTER-FLIP 2: multiplicity check neutered => approve+deny picks an entry (fail-open)
$patch2 = New-PatchedRunModule 'multiplicity' '  if (@($matched).Count -ge 2) {' '  if ($false) {'
. $patch2; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-MULTIPLICITY-FAILS-OPEN' 'True' {
  $e = Read-NeoRunStartApproval -LedgerPath (Write-Approval @((New-GateEntry $refB), (New-GateEntry $refB 'human_end_keep'))) `
    -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
  [bool]($null -ne $e)   # a conflicted ledger produced an ENGINE PICK - the guard is load-bearing
}
. $realModule; Set-Tripwire

# ---- NF-A10: mode<->kind pairing at the reader boundary (spec 3B; both
# cross-pairings REFUSE; only the case-exact correct pairing passes) -----------
Expect-Block 'N-RUN-A10-CROSS-AUTO-CHAIN-HUMAN-KIND' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'human_start_approval')) `
    -ExpectedGateRef $refB -AutonomySegment ('f' * 64) -Index $index
}
Expect-Block 'N-RUN-A10-CROSS-INTERACTIVE-ATTESTED-KIND' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'attested_start_approval')) `
    -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
}
Expect-Block 'N-RUN-A10-ATTESTED-CASING-VARIANT' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'Attested_Start_Approval')) `
    -ExpectedGateRef $refB -AutonomySegment ('f' * 64) -Index $index
}
Expect-Value 'P-RUN-A10-ATTESTED-PAIRING-VALID' 'raphael' {
  [string](Get-NeoProp (Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'attested_start_approval')) `
    -ExpectedGateRef $refB -AutonomySegment ('f' * 64) -Index $index) 'authorized_by')
}
# EXACTLY-ONE raw multiplicity is UNTOUCHED by the pairing (mixed kinds on the
# same tuple still refuse BEFORE any kind filtering)
Expect-Block 'N-RUN-A10-MULTI-MIXED-KINDS-RAW-COUNT' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @((New-GateEntry $refB 'attested_start_approval'), (New-GateEntry $refB 'human_start_approval'))) `
    -ExpectedGateRef $refB -AutonomySegment ('f' * 64) -Index $index
}

# =============================================================================
# SECTION C - PREPARE path (3.D.1b + 3.D.8)
# =============================================================================
Write-Host "=== SECTION C: prepare path (freeze -> plan audit -> gate) ===" -ForegroundColor Cyan
# C1 happy path: the presentation package + ONE APPROVAL_NEEDED notification +
# behavioral purity (no attempt-ledger write, no spawn write, no seam surface).
$wC1 = New-World 'prep_ok'
$pkgC1 = Invoke-PrepareFix $wC1 $stubGo
Expect-Value 'P-RUN-PREPARE-PACKAGE-READY' 'True' {
  [bool]((([string]$pkgC1.state -ceq 'READY') -or ([string]$pkgC1.state -ceq 'READY_WITH_DISCLOSURE')) `
    -and (@($pkgC1.slice_list).Count -eq 1) -and ($null -ne $pkgC1.manifest_coverage) -and ($null -ne $pkgC1.plan_verdict))
}
Expect-Value 'P-RUN-PREPARE-ONE-APPROVAL-NEEDED-NOTIFY' '1' { @(Get-EmlFiles $wC1.notify).Count }
Expect-Value 'N-RUN-PREPARE-PURITY-NO-ATTEMPT-LEDGER' 'False' {
  Test-Path -LiteralPath (Resolve-NeoRunStatePath $wC1.run 'attempt_ledger.jsonl')
}
Expect-Value 'N-RUN-PREPARE-PURITY-NO-SPAWN-LEDGER' 'False' {
  Test-Path -LiteralPath (Resolve-NeoRunStatePath $wC1.run 'spawn_ledger.jsonl')
}
# C2 gate-not-ready PROPAGATES through prepare: a NO-GO plan verdict with no
# disposition => the frozen CLARITY_GATE_NOT_READY BLOCK reaches the caller;
# NO presentation package, NO swallow-wrap/fabrication.
$wC2 = New-World 'prep_nogo'
Expect-Block 'N-RUN-PREPARE-BLOCKED-PROPAGATES' 'CLARITY_GATE_NOT_READY' {
  Invoke-PrepareFix $wC2 $stubNoGo
}
# C3 STRUCTURAL purity of the prepare function body: no catch (nothing can
# swallow the BLOCK), no slice dispatch, no ledger write, no seam parameter.
$runSrc = [System.IO.File]::ReadAllText((Join-Path $orchDir 'orch_run.ps1'))
$prepStart = $runSrc.IndexOf('function Invoke-NeoRunPrepare')
$prepEnd = $runSrc.IndexOf('# (5) END ASSEMBLY')
$prepBody = $runSrc.Substring($prepStart, $prepEnd - $prepStart)
Expect-Value 'N-RUN-PREPARE-STRUCTURAL-NO-CATCH' 'True' {
  [bool](($prepBody -notmatch '\bcatch\b') -and ($prepBody -notmatch '\btry\b'))
}
Expect-Value 'N-RUN-PREPARE-STRUCTURAL-NO-DISPATCH' 'True' {
  [bool](($prepBody -notmatch 'Invoke-NeoLoopConverge') -and ($prepBody -notmatch 'Add-NeoAttemptLedgerEntry') `
    -and ($prepBody -notmatch 'BuilderSeam'))
}
# C4 caller-created manifest: prepare on a run root with NO manifest => frozen STOP
$wC4 = New-World 'prep_noman'
Remove-Item -LiteralPath (Resolve-NeoRunStatePath $wC4.run 'run_manifest.json') -Force
Expect-Block 'N-RUN-PREPARE-NO-MANIFEST' 'manifest' { Invoke-PrepareFix $wC4 $stubGo }

# =============================================================================
# SECTION D - EXECUTE entry guards (3.D.1a + 3.D.3 + 3.D.9)
# =============================================================================
Write-Host "=== SECTION D: execute entry (readiness / approval / pin drift / caps) ===" -ForegroundColor Cyan
# D1 BLOCKED readiness (freeze exists, NO plan audit): refuses BEFORE any
# attempt-ledger write or builder-seam invocation.
$wD1 = New-World 'exec_notready'
[void](New-NeoClarityFreezeRecord -RunRoot $wD1.run -SessionRoot $wD1.session `
  -InstructionDigestRef ('fixture-instruction#sha256:' + ('a' * 64)) -AmbiguityRegister (New-DefRegister) `
  -SlicePlan (New-DefSlices) -RiskRows (New-DefRows) -Profile $script:profileObj -AttestedGapRecords @() `
  -GovernedRoot $wD1.gov -AppRoot $wD1.app -RiskRegisterRel 'risk_register.json' `
  -StampedBy 'fixture-supervisor' -Timestamp $TS -Index $index)
$script:d1Seam = 0
$seamD1 = { param($info) $script:d1Seam++; return 'x' }
$provD1 = { param($q) return @{ end_report_path = 'never'; session_root = 'never' } }
$pwD1 = @{ w = $wD1; sliceIds = @('sA'); approval = (Write-Approval @(New-GateEntry 'NEO-RUN-START|x|1|y|z')) }
Expect-Block 'N-RUN-EXEC-GATE-NOT-READY' 'RUN_EXECUTE_NOT_READY' { Invoke-ExecuteFix $pwD1 $seamD1 $provD1 'd1' }
Expect-Value 'N-RUN-EXEC-NOT-READY-NO-LEDGER' 'False' {
  Test-Path -LiteralPath (Resolve-NeoRunStatePath $wD1.run 'attempt_ledger.jsonl')
}
Expect-Value 'N-RUN-EXEC-NOT-READY-SEAM-NEVER-RAN' '0' { $script:d1Seam }
# D1-NEUTER: readiness guard removed => execution proceeds PAST it (fail-open:
# it now dies later, at the approval read on the blank bundle hash).
$patch3 = New-PatchedRunModule 'readiness' `
  "  if ((`$state -cne 'READY') -and (`$state -cne 'READY_WITH_DISCLOSURE')) {" '  if ($false) {'
. $patch3; Set-Tripwire
$d1nMsg = ''
try { Invoke-ExecuteFix $pwD1 $seamD1 $provD1 'd1n' | Out-Null } catch { $d1nMsg = $_.Exception.Message }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-READINESS-FAILS-OPEN' 'True' {
  # fail-open proof: the neutered execute got PAST the readiness guard (its
  # refusal code is gone) and died DOWNSTREAM instead (the blank bundle hash).
  [bool](($d1nMsg -ne '') -and ($d1nMsg -notlike '*RUN_EXECUTE_NOT_READY*'))
}
# D2 post-gate pin drift at execute entry (gov pin, then app pin)
$pwD2 = New-PreparedWorld 'exec_pindrift'
$pathsD2 = Get-NeoClarityPlanAuditPaths $pwD2.w.session '1'
$govPinBytes = [System.IO.File]::ReadAllBytes([string]$pathsD2.gov_pin_full)
Add-Content -LiteralPath ([string]$pathsD2.gov_pin_full) -Value ' ' -Encoding Ascii
Expect-Block 'N-RUN-EXEC-GOV-PIN-DRIFT' 'RUN_PIN_DRIFT' { Invoke-ExecuteFix $pwD2 $seamD1 $provD1 'd2a' }
[System.IO.File]::WriteAllBytes([string]$pathsD2.gov_pin_full, $govPinBytes)
Add-Content -LiteralPath ([string]$pathsD2.app_pin_full) -Value ' ' -Encoding Ascii
Expect-Block 'N-RUN-EXEC-APP-PIN-DRIFT' 'RUN_PIN_DRIFT' { Invoke-ExecuteFix $pwD2 $seamD1 $provD1 'd2b' }
# D3 caps/manifest fail-closed through the frozen readers
$wD3run = Join-Path $ScratchRoot 'bare_run_d3'
New-Item -ItemType Directory -Force -Path $wD3run | Out-Null
$pwD3 = @{ w = @{ run = $wD3run; session = $pwD2.w.session; gov = $pwD2.w.gov; app = $pwD2.w.app; notify = $pwD2.w.notify }
           sliceIds = @('sA'); approval = $pwD2.approval }
Expect-Block 'N-RUN-EXEC-NO-MANIFEST' 'manifest' { Invoke-ExecuteFix $pwD3 $seamD1 $provD1 'd3a' }
Set-Content -LiteralPath (Join-Path $wD3run 'run_manifest.json') `
  -Value '{"schema_id":"neo:run_manifest","run_id":"neo-run-bad","started_at_utc":"2026-01-01T00:00:00Z","caps":{"max_fix_rounds_per_slice":3}}' -Encoding Ascii
Expect-Block 'N-RUN-EXEC-CAPS-INVALID' '' { Invoke-ExecuteFix $pwD3 $seamD1 $provD1 'd3b' }
Expect-Value 'N-RUN-STRUCTURAL-NO-DEFAULT-CAPS' 'True' {
  [bool]($runSrc -notmatch 'max_fix_rounds_per_slice\s*=')
}

# =============================================================================
# SECTION E - app-pin tamper => STOP, ALL WINDOWS + the cross-case (3.D.4)
# =============================================================================
Write-Host "=== SECTION E: the app-pin carry (every window) ===" -ForegroundColor Cyan
# E-pre CLEAN-PROCESS WRAPPER PROOF (FIX-ROUND-1 + FIX-ROUND-2/CX-1 regression
# fixtures): a CHILD process that sources ONLY orch_run.ps1 (NO suite helpers
# exist there) builds TWO mini app worlds and drives:
#   (1) A/B INDEPENDENCE - the exact SC repro order: wrapper A created BEFORE
#       wrapper B; B's world is then TAMPERED; invoking A must verify A's OWN
#       clean pins and return A's inner result (the round-1 single-slot defect
#       would have re-pointed A to B's config: a throw or inner-B);
#   (2) wrapper B stays bound to B (its tampered world => APP_PIN_MISMATCH);
#   (3) registry-entry REMOVED => fail-closed APP_PIN_SEAM_CONFIG throw (other
#       valid entries exist - NEVER a fallback, never a silent wrong-config verify);
#   (4) the round-1 transparency + tamper semantics still hold on wrapper A.
$childWrapper = @'
param([string]$OrchDir, [string]$Scratch)
$ErrorActionPreference = 'Stop'
. (Join-Path $OrchDir 'orch_run.ps1')
$TS = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$repoRoot = Resolve-NeoRoot $OrchDir
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
function New-MiniApp([string]$name, [string]$reg) {
  $app = Join-Path $Scratch $name
  New-Item -ItemType Directory -Force -Path (Join-Path $app '.neo\schema') | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot '.neo\schema\artifact_classes.json') -Destination (Join-Path $app '.neo\schema\artifact_classes.json') -Force
  Copy-Item -LiteralPath (Join-Path $repoRoot '.neo\schema\governance_manifest.schema.json') -Destination (Join-Path $app '.neo\schema\governance_manifest.schema.json') -Force
  Set-Content -LiteralPath (Join-Path $app 'NEO_APP_PROFILE.json') -Value ('{"fixture":"app profile ' + $name + '"}') -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $app 'risk_register.json') -Value $reg -Encoding Ascii
  return $app
}
$appA = New-MiniApp 'appA' '{"fixture":"risk register A"}'
$appB = New-MiniApp 'appB' '{"fixture":"risk register B"}'
$pinA = Join-Path $Scratch 'pinA.json'
$pinB = Join-Path $Scratch 'pinB.json'
[void](New-NeoClarityAppPin -AppRoot $appA -DerivedAt $TS -PinOutPath $pinA -RiskRegisterRel 'risk_register.json')
[void](New-NeoClarityAppPin -AppRoot $appB -DerivedAt $TS -PinOutPath $pinB -RiskRegisterRel 'risk_register.json')
$regShaA = Get-NeoSha256File (Join-Path $appA 'risk_register.json')
$regShaB = Get-NeoSha256File (Join-Path $appB 'risk_register.json')
$script:innerA = 0
$script:innerB = 0
$inA = { param($i) $script:innerA++; return 'inner-A' }
$inB = { param($i) $script:innerB++; return 'inner-B' }
$wrapA = New-NeoRunAppPinBuilderSeam -InnerSeam $inA -AppRoot $appA -AppPinPath $pinA `
  -RiskRegisterRel 'risk_register.json' -RiskRegisterPinSha256 $regShaA -DerivedAt $TS
$wrapB = New-NeoRunAppPinBuilderSeam -InnerSeam $inB -AppRoot $appB -AppPinPath $pinB `
  -RiskRegisterRel 'risk_register.json' -RiskRegisterPinSha256 $regShaB -DerivedAt $TS
Add-Content -LiteralPath (Join-Path $appB 'NEO_APP_PROFILE.json') -Value ' ' -Encoding Ascii
$retA = & $wrapA (@{ packet = 'x'; round = 0; kind = 'initial'; repo_root = $appA; denied_paths = @() })
Write-Output ('WRAPPER-A: innerA=' + $script:innerA + ' innerB=' + $script:innerB + ' ret=' + [string]$retA)
try {
  & $wrapB (@{ packet = 'x'; round = 0; kind = 'initial'; repo_root = $appB; denied_paths = @() }) | Out-Null
  Write-Output 'WRAPPER-B: NO-THROW'
} catch {
  Write-Output ('WRAPPER-B: THREW ' + $_.Exception.Message)
}
$keysBefore = @($script:NeoRunAppPinRegistry.Keys)
$wrapC = New-NeoRunAppPinBuilderSeam -InnerSeam $inA -AppRoot $appA -AppPinPath $pinA `
  -RiskRegisterRel 'risk_register.json' -RiskRegisterPinSha256 $regShaA -DerivedAt $TS
$newKey = @(@($script:NeoRunAppPinRegistry.Keys) | Where-Object { $keysBefore -cnotcontains $_ })[0]
[void]$script:NeoRunAppPinRegistry.Remove($newKey)
try {
  & $wrapC (@{ packet = 'x'; round = 0; kind = 'initial'; repo_root = $appA; denied_paths = @() }) | Out-Null
  Write-Output 'WRAPPER-REMOVED: NO-THROW'
} catch {
  Write-Output ('WRAPPER-REMOVED: THREW ' + $_.Exception.Message)
}
Add-Content -LiteralPath (Join-Path $appA 'NEO_APP_PROFILE.json') -Value ' ' -Encoding Ascii
try {
  & $wrapA (@{ packet = 'x'; round = 1; kind = 'fix'; repo_root = $appA; denied_paths = @() }) | Out-Null
  Write-Output 'WRAPPER-TAMPER: NO-THROW'
} catch {
  Write-Output ('WRAPPER-TAMPER: THREW ' + $_.Exception.Message)
}
'@
$childWrapperPath = Join-Path $ScratchRoot 'child_wrapper.ps1'
Set-Content -LiteralPath $childWrapperPath -Value $childWrapper -Encoding Ascii
$outWP = & powershell -NoProfile -File $childWrapperPath -OrchDir $orchDir -Scratch (Join-Path $ScratchRoot 'childwrap') 2>&1 | Out-String
Expect-Value 'N-RUN-WRAPPER-CLEANPROC-TRANSPARENT' 'True' {
  # A created BEFORE B, B tampered, A invoked: A verified A's OWN clean pins
  # and delegated to A's OWN inner (innerB untouched) - the exact SC repro.
  [bool]($outWP -like '*WRAPPER-A: innerA=1 innerB=0 ret=inner-A*')
}
Expect-Value 'N-RUN-WRAPPER-AB-INDEPENDENCE' 'True' {
  # B stays bound to B: its tampered world => APP_PIN_MISMATCH, inner-B never ran.
  [bool](($outWP -like '*WRAPPER-B: THREW*APP_PIN_MISMATCH*') -and ($outWP -notlike '*WRAPPER-B: NO-THROW*'))
}
Expect-Value 'N-RUN-WRAPPER-REGISTRY-REMOVED-FAILS-CLOSED' 'True' {
  # binding loss => the distinct fail-closed throw; other valid entries existed
  # in the registry and were NEVER used as a fallback.
  [bool](($outWP -like '*WRAPPER-REMOVED: THREW*APP_PIN_SEAM_CONFIG*') -and ($outWP -notlike '*WRAPPER-REMOVED: NO-THROW*'))
}
Expect-Value 'N-RUN-WRAPPER-CLEANPROC-TAMPER-THROWS' 'True' {
  [bool](($outWP -like '*WRAPPER-TAMPER: THREW*APP_PIN_MISMATCH*') -and ($outWP -notlike '*not recognized*'))
}
# the WRITE-ONCE registry guard, driven directly (+ its neuter-flip):
Expect-Value 'P-RUN-SEAMREG-WRITE-ONCE-FIRST' 'True' {
  [bool](Register-NeoRunAppPinSeamConfig -Id 'fixture-dup-id-1' -Config @{ id = 'fixture-dup-id-1' })
}
Expect-Block 'N-RUN-SEAMREG-WRITE-ONCE-REFUSES' 'APP_PIN_SEAM_CONFIG' {
  Register-NeoRunAppPinSeamConfig -Id 'fixture-dup-id-1' -Config @{ id = 'overwrite-attempt' }
}
$patch7 = New-PatchedRunModule 'writeonce' '  if ($script:NeoRunAppPinRegistry.ContainsKey($Id)) {' '  if ($false) {'
. $patch7; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-SEAMREG-WRITE-ONCE' 'True' {
  # fail-open proof: with the guard neutered, a duplicate id OVERWRITES silently.
  [void](Register-NeoRunAppPinSeamConfig -Id 'fixture-dup-id-neuter' -Config @{ id = 'first' })
  [void](Register-NeoRunAppPinSeamConfig -Id 'fixture-dup-id-neuter' -Config @{ id = 'second' })
  [bool]([string]$script:NeoRunAppPinRegistry['fixture-dup-id-neuter'].id -ceq 'second')
}
. $realModule; Set-Tripwire
# E0 CLEAN CONTROL: wrapper transparent; one GO slice end-to-end => SESSION_END
$pwE0 = New-PreparedWorld 'exec_clean'
$slotE0 = New-SlotWorld 'e0' $pwE0.w.run
$script:e0Seam = 0
$seamE0 = { param($info) $script:e0Seam++
  Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit round ' + $info.round) -Encoding Ascii
  return 'seam-return-ignored' }
$script:e0Root = $slotE0.root
$script:e0Er = $slotE0.erPath
$provE0 = { param($q) return @{ end_report_path = $script:e0Er; session_root = $script:e0Root } }
$sfsE0 = @(@{ slice_id = 'sA'; session_root = $slotE0.root; final_surfaces = (Get-BundleFinalSurfaces $slotE0.root $slotE0.bundleRel) })
$rE0 = Invoke-ExecuteFix $pwE0 $seamE0 $provE0 'e0' @{ SliceFinalState = $sfsE0 }
Expect-Value 'P-RUN-E2E-CLEAN-SESSION-END' 'True' {
  $g = $rE0.result.end_gate
  [bool]($g.assembly_ok -and ([string]$g.human_class -ceq 'SESSION_END') -and ([string]$rE0.result.path -ceq 'converged'))
}
Expect-Value 'P-RUN-E2E-CLEAN-WRAPPER-TRANSPARENT' 'True' {
  [bool](($script:e0Seam -eq 1) -and ([string]$rE0.result.app_pin_end_disclosure.result -ceq 'MATCH') `
    -and (@($rE0.result.not_reached).Count -eq 0) -and (@($rE0.result.slice_envelopes).Count -eq 1))
}
Expect-Value 'P-RUN-E2E-CLEAN-APPROVAL-ECHO' 'True' {
  [bool](([string]$rE0.result.start_approval.gate_ref -ceq [string]$pwE0.ref) -and ([string]$rE0.result.start_approval.authorized_by -ceq 'raphael'))
}
# E-c END-entry CONVERGED tamper: reuse the CLEAN world post-run; tamper the
# profile AFTER the final GO round; direct END assembly => BLOCK.
$dirEc = New-NotifyDir 'e_c_end'
Add-Content -LiteralPath (Join-Path $pwE0.w.app 'NEO_APP_PROFILE.json') -Value ' ' -Encoding Ascii
Expect-Block 'N-RUN-END-ENTRY-CONVERGED-TAMPER-BLOCKS' 'RUN_END_APP_PIN' {
  Invoke-NeoRunEndAssembly -RunRoot $pwE0.w.run -SessionRoot $pwE0.w.session -AppRoot $pwE0.w.app `
    -SliceEnvelopes @($rE0.result.slice_envelopes) -SliceFinalState $sfsE0 -EvidencePath $evidenceDir `
    -Timestamp $TS -NotifyTestModeDir $dirEc -Index $index
}
Expect-Value 'N-RUN-END-ENTRY-CONVERGED-ESCALATION-NOTIFIED' '1' { @(Get-EmlFiles $dirEc).Count }
# E-a ROUND-0 PRE-DISPATCH + THE CROSS-CASE: tamper AFTER the execute-entry
# check window (the pins are session-side files; the LIVE app root is what the
# seam preamble re-verifies) => the caller seam NEVER runs; the ROUTED
# BUILDER_SEAM_FAILED STOP flows END-TO-END - tamper STILL in place - to
# DECISION_NEEDED with the MISMATCH disclosure in the END evidence.
$pwEa = New-PreparedWorld 'exec_tamper_r0'
Add-Content -LiteralPath (Join-Path $pwEa.w.app 'NEO_APP_PROFILE.json') -Value ' ' -Encoding Ascii
$script:eaSeam = 0
$seamEa = { param($info) $script:eaSeam++; return 'x' }
$rEa = Invoke-ExecuteFix $pwEa $seamEa $provD1 'ea'
Expect-Value 'N-RUN-TAMPER-R0-SEAM-NEVER-INVOKED' '0' { $script:eaSeam }
Expect-Value 'N-RUN-TAMPER-R0-ROUTED-STOP' 'True' {
  $env0 = @($rEa.result.slice_envelopes)[0].envelope
  $row = (Read-NeoIterationManifest -RunRoot $pwEa.w.run)[0]
  [bool](([bool]$env0.stopped) -and ([string]$env0.stop.reason_code -ceq 'BUILDER_SEAM_FAILED') `
    -and ([string]$env0.stop.detail -like '*APP_PIN_MISMATCH*') `
    -and ([string](Get-NeoProp $row 'stop_reason_code') -ceq 'BUILDER_SEAM_FAILED'))
}
Expect-Value 'N-RUN-TAMPER-CROSS-CASE-DECISION-NEEDED' 'True' {
  $g = $rEa.result.end_gate
  [bool]($g.assembly_ok -and ([string]$g.human_class -ceq 'DECISION_NEEDED') `
    -and ([string]$rEa.result.app_pin_end_disclosure.result -ceq 'MISMATCH') `
    -and ([string]$rEa.result.app_pin_end_disclosure.detail -like '*APP_PIN_MISMATCH*') `
    -and ([string]$rEa.result.path -ceq 'stop'))
}
# E-b MID-RUN (round 0 -> round 1 window, via the audit-provider hook which
# runs AFTER round 0's checks): profile tamper, then the round-1 seam preamble
# STOPs and the round-1 builder never runs.
$pwEb = New-PreparedWorld 'exec_tamper_mid'
$slotEb0 = New-SlotWorld 'eb0' $pwEb.w.run -RoundId 'round-0' -Recommendation 'NEEDS-MORE'
$script:ebSeam = 0
$seamEb = { param($info) $script:ebSeam++
  Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit round ' + $info.round) -Encoding Ascii
  return 'x' }
$script:ebRoot = $slotEb0.root
$script:ebEr = $slotEb0.erPath
$script:ebApp = $pwEb.w.app
$provEb = { param($q)
  if ([int]$q.round -eq 0) {
    Add-Content -LiteralPath (Join-Path $script:ebApp 'NEO_APP_PROFILE.json') -Value ' ' -Encoding Ascii
    return @{ end_report_path = $script:ebEr; session_root = $script:ebRoot }
  }
  return @{ end_report_path = 'never'; session_root = 'never' } }
$rEb = Invoke-ExecuteFix $pwEb $seamEb $provEb 'eb'
Expect-Value 'N-RUN-TAMPER-MIDRUN-PROFILE-STOP' 'True' {
  $env0 = @($rEb.result.slice_envelopes)[0].envelope
  [bool](([bool]$env0.stopped) -and ([string]$env0.stop.reason_code -ceq 'BUILDER_SEAM_FAILED') `
    -and ([string]$env0.stop.detail -like '*APP_PIN_MISMATCH*') -and ($script:ebSeam -eq 1) `
    -and ([string]$rEb.result.end_gate.human_class -ceq 'DECISION_NEEDED'))
}
# E-b2 MID-RUN risk-register content change => same routed STOP naming the register
$pwEr = New-PreparedWorld 'exec_tamper_reg'
$slotEr0 = New-SlotWorld 'er0' $pwEr.w.run -RoundId 'round-0' -Recommendation 'NEEDS-MORE'
$script:erSeam = 0
$seamEr = { param($info) $script:erSeam++
  Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit round ' + $info.round) -Encoding Ascii
  return 'x' }
$script:erRoot = $slotEr0.root
$script:erEr = $slotEr0.erPath
$script:erApp = $pwEr.w.app
$provEr = { param($q)
  if ([int]$q.round -eq 0) {
    Set-Content -LiteralPath (Join-Path $script:erApp 'risk_register.json') -Value '{"fixture":"CHANGED register"}' -Encoding Ascii
    return @{ end_report_path = $script:erEr; session_root = $script:erRoot }
  }
  return @{ end_report_path = 'never'; session_root = 'never' } }
$rEr = Invoke-ExecuteFix $pwEr $seamEr $provEr 'er'
Expect-Value 'N-RUN-TAMPER-MIDRUN-REGISTER-STOP' 'True' {
  $env0 = @($rEr.result.slice_envelopes)[0].envelope
  [bool](([bool]$env0.stopped) -and ([string]$env0.stop.reason_code -ceq 'BUILDER_SEAM_FAILED') `
    -and ([string]$env0.stop.detail -like '*APP_PIN_MISMATCH*') -and ([string]$env0.stop.detail -like '*risk register*') `
    -and ($script:erSeam -eq 1))
}
# E-d NEUTER the path-conditionality (END-entry blocks UNCONDITIONALLY): the
# E-a-style STOP flow must now FAIL to reach the human (proving the
# conditionality is load-bearing for the STOP-path addendum).
$patch4 = New-PatchedRunModule 'pathcond' `
  '  if ((-not $isStopPath) -and ($null -ne $appPinErr)) {' '  if ($null -ne $appPinErr) {'
. $patch4; Set-Tripwire
$pwEd = New-PreparedWorld 'exec_tamper_neuter'
Add-Content -LiteralPath (Join-Path $pwEd.w.app 'NEO_APP_PROFILE.json') -Value ' ' -Encoding Ascii
Expect-Block 'N-RUN-NEUTER-PATHCOND-STOP-DEADLOCKS' 'RUN_END_APP_PIN' {
  Invoke-ExecuteFix $pwEd $seamEa $provD1 'ed'
}
. $realModule; Set-Tripwire

# =============================================================================
# SECTION F - frozen-plan/universe carry, PATH-CONDITIONAL (3.D.5)
# =============================================================================
Write-Host "=== SECTION F: the completeness carry (EXTRA / OMISSION / not_reached) ===" -ForegroundColor Cyan
# F-a CONVERGED path, planned-never-dispatched => EXTRA BLOCK (the frozen carry)
$pwFa = New-PreparedWorld 'end_extra' -Two
$slotFa = New-SlotWorld 'fa' $pwFa.w.run
$pathsFa = Get-NeoClarityPlanAuditPaths $pwFa.w.session '1'
$script:faRoot = $slotFa.root
$script:faEr = $slotFa.erPath
$envFa = Invoke-NeoLoopConverge -Context @{ run_root = $pwFa.w.run; slice_id = 'sA'; round = 0; attempt_seq = 1
    evidence_path = $evidenceDir; timestamp_utc = $TS; notify_test_mode_dir = $pwFa.w.notify; notify_live_send = $false } `
  -RepoRoot $pwFa.w.app -ApprovedPaths @('app') -ProtectedPaths @('locked') `
  -PinnedGovManifestPath ([string]$pathsFa.gov_pin_full) -GovernedRoot $pwFa.w.gov -DerivedAt $TS `
  -RouterProfile $script:routerProfile -RiskRow (New-DefRows)[0] -MasterIdentity 'm1' -BuilderIdentity 'b1' `
  -Index $index -Goal 'g' -RiskClass 'low' -AllowlistItems @(@{ rel = 'app/widget.txt'; role = 'current_artifact' }) `
  -TestPlan @('run suite') -StopConditions @('ambiguity') -ProposedEdits @('app/widget.txt') `
  -BuilderSeam { param($info) Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value 'edit' -Encoding Ascii; 'x' } `
  -AuditProvider { param($q) return @{ end_report_path = $script:faEr; session_root = $script:faRoot } }
$dirFa = New-NotifyDir 'f_a_end'
Expect-Block 'N-RUN-UNIVERSE-CONVERGED-EXTRA-BLOCK' 'LEDGER_FAILURE' {
  Invoke-NeoRunEndAssembly -RunRoot $pwFa.w.run -SessionRoot $pwFa.w.session -AppRoot $pwFa.w.app `
    -SliceEnvelopes @(@{ slice_id = 'sA'; envelope = $envFa }, @{ slice_id = 'sB'; envelope = @{ stopped = $false; converged = $true } }) `
    -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir $dirFa -Index $index
}
Expect-Value 'N-RUN-UNIVERSE-EXTRA-ESCALATION-NOTIFIED' '1' { @(Get-EmlFiles $dirFa).Count }
# F-b BOTH paths, recorded-but-unplanned => OMISSION BLOCK (STOP-path direction)
$wFb = New-World 'end_omission'
[void](New-NeoClarityFreezeRecord -RunRoot $wFb.run -SessionRoot $wFb.session `
  -InstructionDigestRef ('fixture-instruction#sha256:' + ('a' * 64)) -AmbiguityRegister (New-DefRegister) `
  -SlicePlan (New-DefSlices) -RiskRows (New-DefRows) -Profile $script:profileObj -AttestedGapRecords @() `
  -GovernedRoot $wFb.gov -AppRoot $wFb.app -RiskRegisterRel 'risk_register.json' `
  -StampedBy 'fixture-supervisor' -Timestamp $TS -Index $index)
[void](Add-NeoIterationManifestEntry -RunRoot $wFb.run -Fields (New-StopRowFields 'sA' 0 'CAP_WALL_CLOCK'))
[void](Add-NeoIterationManifestEntry -RunRoot $wFb.run -Fields (New-StopRowFields 'sX' 0 'CAP_WALL_CLOCK'))
$dirFb = New-NotifyDir 'f_b_end'
Expect-Block 'N-RUN-UNIVERSE-STOP-OMISSION-BLOCK' 'RUN_UNIVERSE_OMISSION' {
  Invoke-NeoRunEndAssembly -RunRoot $wFb.run -SessionRoot $wFb.session -AppRoot $wFb.app `
    -SliceEnvelopes @(@{ slice_id = 'sA'; envelope = @{ stopped = $true; converged = $false } }) `
    -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir $dirFb -Index $index
}
# F-c STOP path: planned-but-never-reached DISCLOSED (not blocked) - end-to-end
# through execute; doubles as 3.D.11 halt-on-stop (slice 2 never dispatches).
$pwFc = New-PreparedWorld 'end_notreached' -Two
$script:fcSeam = 0
$seamFc = { param($info) $script:fcSeam++; throw 'builder infrastructure exploded (fixture)' }
$rFc = Invoke-ExecuteFix $pwFc $seamFc $provD1 'fc'
Expect-Value 'N-RUN-STOP-NOT-REACHED-DISCLOSED' 'True' {
  [bool]((@($rFc.result.not_reached).Count -eq 1) -and ([string]@($rFc.result.not_reached)[0] -ceq 'sB') `
    -and ([string]$rFc.result.end_gate.human_class -ceq 'DECISION_NEEDED') `
    -and ([string]$rFc.result.path -ceq 'stop'))
}
Expect-Value 'N-RUN-HALT-ON-STOP-SLICE2-NEVER-DISPATCHED' 'True' {
  [bool](($script:fcSeam -eq 1) -and (@($rFc.result.slice_envelopes).Count -eq 1) `
    -and (-not (@($rFc.result.recorded_slice_ids) -ccontains 'sB')))
}
# F-c NEUTER: the not_reached disclosure removed => the evidence silently drops
# the never-reached slice (the fixture's assert would FAIL - load-bearing proof).
$patch5 = New-PatchedRunModule 'notreached' `
  '      if (-not (@($recorded) -ccontains [string]$p)) { $notReached += [string]$p }' '      # NEUTERED'
. $patch5; Set-Tripwire
$pwFn = New-PreparedWorld 'end_notreached_neuter' -Two
$script:fnSeam = 0
$seamFn = { param($info) $script:fnSeam++; throw 'builder infrastructure exploded (fixture)' }
$rFn = Invoke-ExecuteFix $pwFn $seamFn $provD1 'fn'
Expect-Value 'N-RUN-NEUTER-DISCLOSURE-DROPS-LIST' '0' { @($rFn.result.not_reached).Count }
. $realModule; Set-Tripwire

# =============================================================================
# SECTION F2 - FIX-ROUND-2 / CX-2: STOP-path envelopes bound to the RECORDED
# universe (caller-supplied authority at the END boundary is refused)
# =============================================================================
Write-Host "=== SECTION F2: CX-2 recorded-universe binding (STOP path) ===" -ForegroundColor Cyan
# world helper: a 2-slice frozen world with NO plan audit (end assembly never
# reads the bundle); recorded rows are fabricated per fixture (order controls
# the last-recorded slice - the frozen universe is first-seen ordered).
function New-FrozenWorld([string]$case) {
  $w = New-World $case
  [void](New-NeoClarityFreezeRecord -RunRoot $w.run -SessionRoot $w.session `
    -InstructionDigestRef ('fixture-instruction#sha256:' + ('a' * 64)) -AmbiguityRegister (New-DefRegister) `
    -SlicePlan (New-DefSlices -Two) -RiskRows (New-DefRows) -Profile $script:profileObj -AttestedGapRecords @() `
    -GovernedRoot $w.gov -AppRoot $w.app -RiskRegisterRel 'risk_register.json' `
    -StampedBy 'fixture-supervisor' -Timestamp $TS -Index $index)
  return $w
}
$envConv = @{ stopped = $false; converged = $true }
$envStop = @{ stopped = $true; converged = $false }
# (i-a) THE EXACT CX-2 PROBE: disk records ONLY sA; the caller appends a
# crafted stopped envelope for planned-but-NEVER-RECORDED sB as last => BLOCK.
$wX1 = New-FrozenWorld 'cx2_fabricated_stop'
[void](Add-NeoIterationManifestEntry -RunRoot $wX1.run -Fields (New-StopRowFields 'sA' 0 'CAP_WALL_CLOCK'))
Expect-Block 'N-RUN-CX2-FABRICATED-STOP-UNRECORDED' 'RUN_STOP_UNIVERSE' {
  Invoke-NeoRunEndAssembly -RunRoot $wX1.run -SessionRoot $wX1.session -AppRoot $wX1.app `
    -SliceEnvelopes @(@{ slice_id = 'sA'; envelope = $envConv }, @{ slice_id = 'sB'; envelope = $envStop }) `
    -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir (New-NotifyDir 'cx2_a') -Index $index
}
# (i-b) an UNRECORDED slice in a NON-last position is refused by the SAME
# membership binding (this is also the neuter-flip scenario below).
Expect-Block 'N-RUN-CX2-UNRECORDED-NONLAST' 'RUN_STOP_UNIVERSE' {
  Invoke-NeoRunEndAssembly -RunRoot $wX1.run -SessionRoot $wX1.session -AppRoot $wX1.app `
    -SliceEnvelopes @(@{ slice_id = 'sB'; envelope = $envConv }, @{ slice_id = 'sA'; envelope = $envStop }) `
    -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir (New-NotifyDir 'cx2_b') -Index $index
}
# (ii) the last envelope's slice is RECORDED but is NOT the LAST-RECORDED
# slice => BLOCK (the gate envelope must be the honest stopping slice's).
$wX2 = New-FrozenWorld 'cx2_last_mismatch'
[void](Add-NeoIterationManifestEntry -RunRoot $wX2.run -Fields (New-StopRowFields 'sA' 0 'CAP_WALL_CLOCK'))
[void](Add-NeoIterationManifestEntry -RunRoot $wX2.run -Fields (New-StopRowFields 'sB' 0 'CAP_WALL_CLOCK'))
Expect-Block 'N-RUN-CX2-LAST-NOT-LAST-RECORDED' 'RUN_STOP_UNIVERSE' {
  Invoke-NeoRunEndAssembly -RunRoot $wX2.run -SessionRoot $wX2.session -AppRoot $wX2.app `
    -SliceEnvelopes @(@{ slice_id = 'sB'; envelope = $envConv }, @{ slice_id = 'sA'; envelope = $envStop }) `
    -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir (New-NotifyDir 'cx2_c') -Index $index
}
# (iii) the LEGITIMATE stop control: last envelope = the actual last recorded
# slice => proceeds through the frozen end gate to DECISION_NEEDED.
$wX3 = New-FrozenWorld 'cx2_legit_control'
[void](Add-NeoIterationManifestEntry -RunRoot $wX3.run -Fields (New-StopRowFields 'sA' 0 'CAP_WALL_CLOCK'))
[void](Add-NeoIterationManifestEntry -RunRoot $wX3.run -Fields (New-StopRowFields 'sB' 0 'CAP_WALL_CLOCK'))
$rX3 = Invoke-NeoRunEndAssembly -RunRoot $wX3.run -SessionRoot $wX3.session -AppRoot $wX3.app `
  -SliceEnvelopes @(@{ slice_id = 'sA'; envelope = $envConv }, @{ slice_id = 'sB'; envelope = $envStop }) `
  -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir (New-NotifyDir 'cx2_d') -Index $index
Expect-Value 'P-RUN-CX2-LEGIT-STOP-CONTROL' 'True' {
  [bool](([string]$rX3.end_gate.human_class -ceq 'DECISION_NEEDED') -and ([string]$rX3.path -ceq 'stop') `
    -and ((@($rX3.recorded_slice_ids) -join ',') -ceq 'sA,sB'))
}
# (iv) NEUTER the recorded-membership guard => the fabricated-envelope
# scenario (i-b) FAILS OPEN (the last-recorded check does not catch it:
# sA IS the last recorded slice there) - the membership guard is load-bearing.
$patch8 = New-PatchedRunModule 'cx2membership' `
  '      if (-not (@($recorded) -ccontains $sidB)) {' '      if ($false) {'
. $patch8; Set-Tripwire
$wX4 = New-FrozenWorld 'cx2_membership_neuter'
[void](Add-NeoIterationManifestEntry -RunRoot $wX4.run -Fields (New-StopRowFields 'sA' 0 'CAP_WALL_CLOCK'))
$rX4 = $null; $x4Msg = ''
try {
  $rX4 = Invoke-NeoRunEndAssembly -RunRoot $wX4.run -SessionRoot $wX4.session -AppRoot $wX4.app `
    -SliceEnvelopes @(@{ slice_id = 'sB'; envelope = $envConv }, @{ slice_id = 'sA'; envelope = $envStop }) `
    -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir (New-NotifyDir 'cx2_e') -Index $index
} catch { $x4Msg = $_.Exception.Message }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-CX2-MEMBERSHIP-FAILS-OPEN' 'True' {
  # fail-open proof: with the membership guard neutered, the crafted envelope
  # for never-recorded sB sailed through to END assembly (no RUN_STOP_UNIVERSE).
  [bool](($x4Msg -notlike '*RUN_STOP_UNIVERSE*') -and ($null -ne $rX4) -and ([string]$rX4.path -ceq 'stop'))
}

# =============================================================================
# SECTION G - reduction contract + tri-state at BOTH boundaries (3.D.6 + 6b)
# =============================================================================
Write-Host "=== SECTION G: STOP-path END + the reduction contract ===" -ForegroundColor Cyan
# G-a slice-1 GO + slice-2 STOP => END consumes slice-2's stop envelope
# UNCHANGED with SliceIds = the RECORDED ids; DECISION_NEEDED end-to-end.
$pwGa = New-PreparedWorld 'reduction_stop' -Two
$slotGa = New-SlotWorld 'ga' $pwGa.w.run
$script:gaCalls = 0
$seamGa = { param($info)
  $script:gaCalls++
  if ($script:gaCalls -ge 2) { throw 'slice-2 builder exploded (fixture)' }
  Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit ' + $info.round) -Encoding Ascii
  return 'x' }
$script:gaRoot = $slotGa.root
$script:gaEr = $slotGa.erPath
$provGa = { param($q) return @{ end_report_path = $script:gaEr; session_root = $script:gaRoot } }
# sA reached GO: its XC2 descriptor is required even on the STOP path (PR-2:
# only never-GO slices carry the NO_GO_BUNDLE marker instead).
$sfsGa = @(@{ slice_id = 'sA'; session_root = $slotGa.root; final_surfaces = (Get-BundleFinalSurfaces $slotGa.root $slotGa.bundleRel) })
$rGa = Invoke-ExecuteFix $pwGa $seamGa $provGa 'ga' @{ SliceFinalState = $sfsGa }
Expect-Value 'N-RUN-REDUCTION-STOP-ENVELOPE-UNCHANGED' 'True' {
  $envs = @($rGa.result.slice_envelopes)
  [bool](($envs.Count -eq 2) -and ([string]$envs[0].slice_id -ceq 'sA') -and ([bool]$envs[0].envelope.converged) `
    -and ([string]$envs[1].slice_id -ceq 'sB') -and ([bool]$envs[1].envelope.stopped) `
    -and ([string]$envs[1].envelope.stop.reason_code -ceq 'BUILDER_SEAM_FAILED') `
    -and ([string]$rGa.result.end_gate.human_class -ceq 'DECISION_NEEDED') `
    -and ((@($rGa.result.recorded_slice_ids) -ccontains 'sA') -and (@($rGa.result.recorded_slice_ids) -ccontains 'sB')))
}
# G-b CONVERGED-path reduction refuses a malformed per-slice envelope BEFORE the
# end gate (no end-gate notification fires).
$dirGb = New-NotifyDir 'g_b_end'
Expect-Block 'N-RUN-REDUCTION-MALFORMED-REFUSED' 'RUN_DISPOSITION' {
  Invoke-NeoRunEndAssembly -RunRoot $pwGa.w.run -SessionRoot $pwGa.w.session -AppRoot $pwGa.w.app `
    -SliceEnvelopes @(@{ slice_id = 'sA'; envelope = @{ stopped = $false; converged = $true } }, `
                      @{ slice_id = 'sB'; envelope = @{ stopped = $false; converged = $false } }) `
    -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir $dirGb -Index $index
}
Expect-Value 'N-RUN-REDUCTION-MALFORMED-NO-ENDGATE' '0' { @(Get-EmlFiles $dirGb).Count }
# a STOP anywhere but LAST is a sequence no honest run produces => BLOCK
Expect-Block 'N-RUN-REDUCTION-STOP-NOT-LAST' 'RUN_DISPOSITION' {
  Invoke-NeoRunEndAssembly -RunRoot $pwGa.w.run -SessionRoot $pwGa.w.session -AppRoot $pwGa.w.app `
    -SliceEnvelopes @(@{ slice_id = 'sA'; envelope = @{ stopped = $true; converged = $false } }, `
                      @{ slice_id = 'sB'; envelope = @{ stopped = $false; converged = $true } }) `
    -EvidencePath $evidenceDir -Timestamp $TS -NotifyTestModeDir $dirGb -Index $index
}
# G-c TRANSITION boundary behavioral proof (3.D.6b): a converge override forges
# a malformed envelope; slice N+1 must NEVER be dispatched and the end gate
# must NEVER be called.
$pwGc = New-PreparedWorld 'transition_forge' -Two
$script:gcConverge = 0
${function:Invoke-NeoLoopConverge} = { param($Context, $RepoRoot, $ApprovedPaths, $ProtectedPaths,
    $PinnedGovManifestPath, $GovernedRoot, $DerivedAt, $RouterProfile, $RiskRow, $MasterIdentity,
    $BuilderIdentity, $Index, $Goal, $RiskClass, $AllowlistItems, $TestPlan, $StopConditions,
    $ProposedEdits, $DeclaredSurfaces, $DeniedPaths, $ProposedFixTargets, $RoundIdPrefix,
    $PacketIdPrefix, $BuilderSeam, $AuditProvider, $ExternalProvider)
  $script:gcConverge++
  return @{ stopped = $false; converged = $false } }
$rGcBlocked = $null
try { Invoke-ExecuteFix $pwGc $seamD1 $provD1 'gc' | Out-Null } catch { $rGcBlocked = $_.Exception.Message }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-TRANSITION-MALFORMED-BLOCKS' 'True' {
  [bool](($null -ne $rGcBlocked) -and ($rGcBlocked -like '*RUN_DISPOSITION*'))
}
Expect-Value 'N-RUN-TRANSITION-SLICE2-NEVER-DISPATCHED' '1' { $script:gcConverge }
# G-c NEUTER: tri-state XOR removed => the both-false envelope is treated as
# CONVERGED and slice 2 IS dispatched (fail-open; the guard is load-bearing).
$patch6 = New-PatchedRunModule 'tristate' '  if ($s -eq $c) {' '  if ($false) {'
. $patch6; Set-Tripwire
$script:gnConverge = 0
${function:Invoke-NeoLoopConverge} = { param($Context, $RepoRoot, $ApprovedPaths, $ProtectedPaths,
    $PinnedGovManifestPath, $GovernedRoot, $DerivedAt, $RouterProfile, $RiskRow, $MasterIdentity,
    $BuilderIdentity, $Index, $Goal, $RiskClass, $AllowlistItems, $TestPlan, $StopConditions,
    $ProposedEdits, $DeclaredSurfaces, $DeniedPaths, $ProposedFixTargets, $RoundIdPrefix,
    $PacketIdPrefix, $BuilderSeam, $AuditProvider, $ExternalProvider)
  $script:gnConverge++
  return @{ stopped = $false; converged = $false } }
$pwGn = New-PreparedWorld 'transition_neuter' -Two
$gnMsg = ''
try { Invoke-ExecuteFix $pwGn $seamD1 $provD1 'gn' | Out-Null } catch { $gnMsg = $_.Exception.Message }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-TRISTATE-FAILS-OPEN' 'True' {
  [bool](($script:gnConverge -eq 2) -and ($gnMsg -notlike '*RUN_DISPOSITION*'))
}

# =============================================================================
# SECTION H - the orch_loop-not-sourced carry proof (3.D.7; child processes)
# =============================================================================
Write-Host "=== SECTION H: the two-chain meeting point (child processes) ===" -ForegroundColor Cyan
$childCommon = @'
param([string]$Mode, [string]$OrchDir, [string]$Scratch)
$ErrorActionPreference = 'Stop'
if ($Mode -ceq 'clarityOnly') { . (Join-Path $OrchDir 'orch_clarity.ps1') } else { . (Join-Path $OrchDir 'orch_run.ps1') }
$TS = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$index = Get-NeoRunSchemaIndex
$repoRoot = Resolve-NeoRoot $OrchDir
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
$run = Join-Path $Scratch 'run'; New-Item -ItemType Directory -Force -Path $run | Out-Null
[void](New-NeoRunManifest -RunRoot $run -Caps @{ max_fix_rounds_per_slice = 3; max_external_calls = 25; max_wall_clock_hours = 4; max_spend = 100 } -Timestamp $TS)
$session = Join-Path $Scratch 'session'; New-Item -ItemType Directory -Force -Path $session | Out-Null
$gov = Join-Path $Scratch 'gov'
foreach ($rel in @($script:NeoGovDefaultMandatoryRels)) {
  $full = Join-Path $gov (([string]$rel) -replace '/', '\')
  $parent = Split-Path -Parent $full
  if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  if (([string]$rel) -like '*.json') { Set-Content -LiteralPath $full -Value '{"a":1}' -Encoding Ascii }
  else { Set-Content -LiteralPath $full -Value ("# " + $rel) -Encoding Ascii }
}
Copy-Item -LiteralPath (Join-Path $repoRoot '.neo\schema\artifact_classes.json') -Destination (Join-Path $gov '.neo\schema\artifact_classes.json') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot '.neo\schema\governance_manifest.schema.json') -Destination (Join-Path $gov '.neo\schema\governance_manifest.schema.json') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $gov '.neo\scripts\orchestrator\harness') | Out-Null
$app = Join-Path $Scratch 'app'
New-Item -ItemType Directory -Force -Path (Join-Path $app '.neo\schema') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot '.neo\schema\artifact_classes.json') -Destination (Join-Path $app '.neo\schema\artifact_classes.json') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot '.neo\schema\governance_manifest.schema.json') -Destination (Join-Path $app '.neo\schema\governance_manifest.schema.json') -Force
Set-Content -LiteralPath (Join-Path $app 'NEO_APP_PROFILE.json') -Value '{"fixture":"app profile"}' -Encoding Ascii
Set-Content -LiteralPath (Join-Path $app 'risk_register.json') -Value '{"fixture":"risk register"}' -Encoding Ascii
$slices = @(@{ slice_id = 'sA'; approved_paths = @('app'); protected_paths = @('locked')
               acceptance_harness_paths = @('harness/sA_fixture_suite.ps1'); risk_row_ref = 'r1' })
$rows = @(@{ row_id = 'r1'; risk_class = 'low'; audit_tier = 'lightweight' })
$profile = [pscustomobject]@{
  denylist = [pscustomobject]@{ entries = @([pscustomobject]@{ pattern = 'forbidden/**'; is_glob = $true }) }
  risk_tokens = [pscustomobject]@{ auth_tokens = @('zz-a'); fin_tokens = @('zz-b') } }
$register = @(@{ item_id = 'amb-1'; surface = 'presentation wording'; classification = 'documented_default'; documented_default = 'plain ASCII output' })
[void](New-NeoClarityFreezeRecord -RunRoot $run -SessionRoot $session -InstructionDigestRef ('fx#sha256:' + ('a' * 64)) `
  -AmbiguityRegister $register -SlicePlan $slices -RiskRows $rows -Profile $profile -AttestedGapRecords @() `
  -GovernedRoot $gov -AppRoot $app -RiskRegisterRel 'risk_register.json' -StampedBy 'fx' -Timestamp $TS -Index $index)
if ($Mode -cne 'clarityOnly') {
  # record evidence for the planned slice so the carry's set-equality holds
  [void](Add-NeoIterationManifestEntry -RunRoot $run -Fields @{
    slice_id = 'sA'; round = 0; attempt_seq = 1
    baseline_head_sha = 'NOT_EVALUATED'; baseline_tree_hash = 'NOT_EVALUATED'
    changed_count = 0; changed_paths_hash = 'NOT_EVALUATED'
    classification = 'STOPPED'; findings_summary = 'pre-ledger stop'
    auditor_slot_status = 'NOT_EVALUATED'; auditor_slot_recommendation = 'NOT_EVALUATED'
    auditor_identity = 'NOT_EVALUATED'; external_lane_status = 'NOT_EVALUATED'
    effective_seam_tier = 'NOT_EVALUATED'; cap_events = @()
    stop_reason_code = 'CAP_WALL_CLOCK'; notify_gate_class = 'ESCALATION_STOP'
    notify_sent = $false; notify_deduped = $false; notify_refused = $false
    notify_reason = ''; timestamp_utc = $TS })
}
$runId = [string](Get-NeoProp (Read-NeoRunManifest -RunRoot $run) 'run_id')
try {
  $u = Assert-NeoClarityPlanSliceUniverse -RunRoot $run -ExpectedRunId $runId -Index $index
  Write-Output ('CARRY-RESULT: OK universe=[' + (@($u) -join ',') + ']')
} catch {
  Write-Output ('CARRY-RESULT: BLOCK ' + $_.Exception.Message)
}
'@
$childPath = Join-Path $ScratchRoot 'child_carry.ps1'
Set-Content -LiteralPath $childPath -Value $childCommon -Encoding Ascii
$outH1 = & powershell -NoProfile -File $childPath -Mode 'clarityOnly' -OrchDir $orchDir -Scratch (Join-Path $ScratchRoot 'childw1') 2>&1 | Out-String
Expect-Value 'N-RUN-CARRY-CLARITY-ONLY-BLOCKS' 'True' {
  [bool](($outH1 -like '*CARRY-RESULT: BLOCK*') -and ($outH1 -like '*CLARITY_UNIVERSE*') -and ($outH1 -like '*must be sourced by the caller*'))
}
$outH2 = & powershell -NoProfile -File $childPath -Mode 'full' -OrchDir $orchDir -Scratch (Join-Path $ScratchRoot 'childw2') 2>&1 | Out-String
Expect-Value 'P-RUN-CARRY-MEETING-POINT-PASSES' 'True' {
  # NOTE: .Contains (ordinal) not -like: '[sA]' inside a -like pattern is a
  # wildcard character class, never the literal bracket text.
  [bool](($outH2 -like '*CARRY-RESULT: OK*') -and $outH2.Contains('universe=[sA]'))
}

# =============================================================================
# SECTION I - serial order control + structural scans (3.D.10/11/12)
# =============================================================================
Write-Host "=== SECTION I: serial control + structural scans ===" -ForegroundColor Cyan
# I1 two-GO control: slice 2 dispatches AFTER slice 1 converges; SESSION_END.
$pwI1 = New-PreparedWorld 'serial_two_go' -Two
$slotIA = New-SlotWorld 'iA' $pwI1.w.run
$slotIB = New-SlotWorld 'iB' $pwI1.w.run
$script:iRoots = @{ sA = $slotIA.root; sB = $slotIB.root }
$script:iErs = @{ sA = $slotIA.erPath; sB = $slotIB.erPath }
$script:iOrder = @()
$seamI = { param($info)
  Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit ' + [string](Get-Date -Format 'HHmmssfff')) -Encoding Ascii
  return 'x' }
$provI = { param($q)
  $script:iOrder += [string]$q.slice_id
  $root = [string]$script:iRoots[[string]$q.slice_id]
  return @{ end_report_path = [string]$script:iErs[[string]$q.slice_id]; session_root = $root } }
$sfsI = @(
  @{ slice_id = 'sA'; session_root = $slotIA.root; final_surfaces = (Get-BundleFinalSurfaces $slotIA.root $slotIA.bundleRel) },
  @{ slice_id = 'sB'; session_root = $slotIB.root; final_surfaces = (Get-BundleFinalSurfaces $slotIB.root $slotIB.bundleRel) })
$rI1 = Invoke-ExecuteFix $pwI1 $seamI $provI 'i1' @{ SliceFinalState = $sfsI }
Expect-Value 'P-RUN-SERIAL-TWO-GO-SESSION-END' 'True' {
  [bool](([string]$rI1.result.end_gate.human_class -ceq 'SESSION_END') -and (@($rI1.result.slice_envelopes).Count -eq 2) `
    -and ([string]$rI1.result.path -ceq 'converged') -and (@($rI1.result.not_reached).Count -eq 0))
}
Expect-Value 'P-RUN-SERIAL-PLAN-ORDER' 'sA,sB' { @($script:iOrder) -join ',' }
Expect-Value 'P-RUN-SERIAL-LEDGER-ORDER' 'True' {
  $led = Read-NeoAttemptLedger -RunRoot $pwI1.w.run
  [bool](([string](Get-NeoProp $led[0] 'slice_id') -ceq 'sA') -and ([string](Get-NeoProp $led[$led.Count - 1] 'slice_id') -ceq 'sB'))
}
# I2 STRUCTURAL: no parallel constructs in orch_run.ps1 (the orch_external
# STRUCTURAL-* pattern) + no live-invoker token + no re-implementation tokens.
Expect-Value 'N-RUN-STRUCTURAL-SERIAL-ONLY' 'True' {
  [bool](($runSrc -notmatch 'Start-Job') -and ($runSrc -notmatch 'Start-Process') -and ($runSrc -notmatch 'Runspace') `
    -and ($runSrc -notmatch 'BeginInvoke') -and ($runSrc -notmatch '-AsJob') -and ($runSrc -notmatch 'ForEach-Object\s+-Parallel'))
}
Expect-Value 'N-RUN-STRUCTURAL-NO-LIVE-INVOKER' 'True' {
  [bool]($runSrc -notmatch 'Invoke-NeoExternalCodex')
}
# I3 STRUCTURAL: this suite cannot reach the live channel: the tripwire never
# fired; the ONE prepare helper is the single Invoke-NeoRunPrepare call site;
# the suite text never sets the live-send switch.
$suiteSrc = [System.IO.File]::ReadAllText($PSCommandPath)
Expect-Value 'N-RUN-SUITE-TRIPWIRE-NEVER-FIRED' '0' { $script:liveTrip }
Expect-Value 'N-RUN-SUITE-SINGLE-PREPARE-HELPER' 'True' {
  $hits = [regex]::Matches($suiteSrc, 'Invoke-NeoRunPrepare\s+@a')
  [bool](($hits.Count -eq 1) -and ($suiteSrc -notmatch 'NotifyLiveSend\s*=\s*\$true') -and ($suiteSrc -notmatch '-NotifyLiveSend:\s*\$true'))
}

# =============================================================================
# SECTION J - AUTO MODE (slice 1d; NEO_AUTOMODE_DESIGN_v1 rev5 NF-A1..NF-A10)
# =============================================================================
Write-Host "=== SECTION J: AUTO mode (toggle + engine wiring) ===" -ForegroundColor Cyan
function Get-BlockMsg($sb) { try { & $sb | Out-Null; return 'NO-BLOCK' } catch { return [string]$_.Exception.Message } }

# ---- J1 NF-A3: two-lane routing --------------------------------------------------
# lane (i): record ABSENT => interactive; the tuple binds the literal NONE.
$wJ1 = New-World 'a3_absent'
$pkgJ1 = Invoke-PrepareFix $wJ1 $stubGo
Expect-Value 'P-RUN-A3-ABSENT-INTERACTIVE-TUPLE-NONE' 'True' {
  [bool](((Get-ExpectedRef $wJ1) -clike '*|NONE') -and ([string]$pkgJ1.autonomy_mode_display -clike '*INTERACTIVE*'))
}
Expect-Value 'P-RUN-A3-DISPLAY-LINE-INTERACTIVE' 'True' {
  # the C5 package display line exists on the plain section-C world too
  [bool]([string]$pkgC1.autonomy_mode_display -clike '*INTERACTIVE*')
}
# lane (ii): record PRESENT but invalid => PARK + NOTIFY at prepare; NO START
# package in EITHER mode (the silent-interactive-downgrade outcome abolished).
foreach ($bad in @(
    @('BLANK-MODE',   @{ autonomy_mode = '' }),
    @('UNKNOWN-MODE', @{ autonomy_mode = 'hands-off' }),
    @('CASE-Auto',    @{ autonomy_mode = 'Auto' }),
    @('CASE-AUTO',    @{ autonomy_mode = 'AUTO' }),
    @('RUNID-MISMATCH', @{ run_id = 'neo-run-other' }),
    @('SCHEMA-MISSING-KEY', @{ declared_by = $null }))) {
  $script:curBadName = [string]$bad[0]
  $script:curBadOver = $bad[1]
  $wJb = New-World ('a3_' + $script:curBadName.ToLower())
  $attJb = New-AutoAttestation $ScratchRoot
  [void](Write-AutoRecord $wJb $attJb $script:curBadOver)
  $script:curBadWorld = $wJb
  $script:curBadAtt = $attJb
  Expect-Block ("N-RUN-A3-PRESENT-" + $script:curBadName) 'RUN_AUTONOMY_PARK' {
    Invoke-PrepareFix $script:curBadWorld $stubGo @{ AutonomyAttestationPath = $script:curBadAtt }
  }
}
# unparseable record => the same park lane
$wJu = New-World 'a3_unparseable'
$attJu = New-AutoAttestation $ScratchRoot
[void](Write-AutoRecordRaw $wJu '{ this is not json')
Expect-Block 'N-RUN-A3-PRESENT-UNPARSEABLE' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wJu $stubGo @{ AutonomyAttestationPath = $attJu }
}
Expect-Value 'N-RUN-A3-PARK-NOTIFIED-NO-C5-SURFACE' 'True' {
  # the parked prepare fired the ESCALATION park notice and NEVER the
  # APPROVAL_NEEDED gate surface (no C5 package against a hash-bearing tuple)
  $emls = @(Get-EmlFiles $wJu.notify)
  [bool](($emls.Count -eq 1) -and ($emls[0].Name -like '*ESCALATION_STOP*') -and (-not ($emls[0].Name -like '*APPROVAL_NEEDED*')))
}

# ---- J2 NF-A8: attestation ENGINE fixtures (record PRESENT) -----------------------
$wA8 = New-World 'a8_absent'
$attA8ok = New-AutoAttestation $ScratchRoot
[void](Write-AutoRecord $wA8 $attA8ok)
Expect-Block 'N-RUN-A8-ATTESTATION-ABSENT' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8 $stubGo @{ AutonomyAttestationPath = (Join-Path $ScratchRoot 'no_such_attestation.md') }
}
$wA8u = New-World 'a8_unsigned'
$attA8u = New-AutoAttestation $ScratchRoot 'LOW' 'unsigned'
[void](Write-AutoRecord $wA8u $attA8u)
Expect-Block 'N-RUN-A8-ATTESTATION-UNSIGNED-TEMPLATE' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8u $stubGo @{ AutonomyAttestationPath = $attA8u }
}
$wA8r = New-World 'a8_revoked'
$attA8r = New-AutoAttestation $ScratchRoot 'LOW' 'revoked'
[void](Write-AutoRecord $wA8r $attA8r)
Expect-Block 'N-RUN-A8-ATTESTATION-REVOKED' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8r $stubGo @{ AutonomyAttestationPath = $attA8r }
}
$wA8h = New-World 'a8_hashmismatch'
$attA8h = New-AutoAttestation $ScratchRoot
[void](Write-AutoRecord $wA8h $attA8h @{ attestation_sha256 = ('e' * 64) })
Expect-Block 'N-RUN-A8-ATTESTATION-HASH-MISMATCH' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8h $stubGo @{ AutonomyAttestationPath = $attA8h }
}
$wA8n = New-World 'a8_noroots'
$attA8n = New-AutoAttestation $ScratchRoot 'LOW' 'noroots'
[void](Write-AutoRecord $wA8n $attA8n)
Expect-Block 'N-RUN-A8-ENVELOPE-UNPARSEABLE-NO-ROOT' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8n $stubGo @{ AutonomyAttestationPath = $attA8n }
}
$wA8t = New-World 'a8_badtier'
$attA8t = New-AutoAttestation $ScratchRoot 'WEIRD'
[void](Write-AutoRecord $wA8t $attA8t)
Expect-Block 'N-RUN-A8-ENVELOPE-UNPARSEABLE-TIER' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8t $stubGo @{ AutonomyAttestationPath = $attA8t }
}
$wA8x = New-World 'a8_tierbreach'
$attA8x = New-AutoAttestation $ScratchRoot 'LOW'
[void](Write-AutoRecord $wA8x $attA8x)
Expect-Block 'N-RUN-A8-ENVELOPE-TIER-ABOVE-MAX' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8x $stubGo @{ AutonomyAttestationPath = $attA8x
    RiskRows = @(@{ row_id = 'r1'; risk_class = 'medium' }) }
}
$wA8g = New-World 'a8_nogo'
$attA8g = New-AutoAttestation $ScratchRoot
[void](Write-AutoRecord $wA8g $attA8g)
Expect-Block 'N-RUN-A8-PLAN-AUDIT-NON-GO' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8g $stubGo @{ AutonomyAttestationPath = $attA8g; PlanAuditInvokerSeam = $stubNoGo }
}
$wA8d = New-World 'a8_nondev'
$attA8d = New-AutoAttestation (Join-Path $ScratchRoot 'elsewhere_root')
[void](Write-AutoRecord $wA8d $attA8d)
Expect-Block 'N-RUN-A8-ENVELOPE-NON-DECLARED-ROOT' 'RUN_AUTONOMY_PARK' {
  Invoke-PrepareFix $wA8d $stubGo @{ AutonomyAttestationPath = $attA8d }
}

# ---- J3 the clean AUTO-KEEP e2e (NF-A5 + NF-A4 runtime + the display line) --------
$pwK = New-AutoPreparedWorld 'auto_keep_clean'
Expect-Value 'P-RUN-A-DISPLAY-LINE-AUTO' 'True' {
  [bool](([string]$pwK.pkg.autonomy_mode_display -clike '*AUTO*') -and ([string]$pwK.pkg.autonomy_mode_display -clike ('*' + $pwK.seg + '*')))
}
$slotK = New-SlotWorld 'jk' $pwK.w.run
$script:jkSeam = 0
$seamK = { param($info) $script:jkSeam++
  Add-Content -LiteralPath (Join-Path $info.repo_root 'app\widget.txt') -Value ('edit round ' + $info.round) -Encoding Ascii
  return 'x' }
$script:jkRoot = $slotK.root
$script:jkEr = $slotK.erPath
$provK = { param($q) return @{ end_report_path = $script:jkEr; session_root = $script:jkRoot } }
$sfsK = @(@{ slice_id = 'sA'; session_root = $slotK.root; final_surfaces = (Get-BundleFinalSurfaces $slotK.root $slotK.bundleRel) })
$ledgerHashPreK = Get-NeoSha256File $pwK.approval
$rK = Invoke-ExecuteFix $pwK $seamK $provK 'jk' @{ SliceFinalState = $sfsK; AutonomyAttestationPath = $pwK.att }
$keepPathK = Join-Path $pwK.w.run 'engine_auto_keep.json'
Expect-Value 'P-RUN-A-AUTO-KEEP-E2E' 'True' {
  $g = $rK.result.end_gate
  [bool](($g.assembly_ok) -and ([string]$g.human_class -ceq 'SESSION_END') -and ([string]$rK.result.path -ceq 'converged') `
    -and (-not [bool]$rK.result.parked) -and ([string]$rK.result.auto.decision -ceq 'auto_keep') `
    -and (Test-Path -LiteralPath $keepPathK -PathType Leaf))
}
Expect-Value 'P-RUN-A5-KEEP-RECORD-SCHEMA-VALID' 'True' {
  $rec = Read-NeoJsonFile $keepPathK
  Assert-NeoValid $rec 'neo:engine_auto_keep' $index 'ENGINE_AUTO_KEEP(fixture read)'
  [bool]($true)
}
Expect-Value 'P-RUN-A5-KEEP-RECORD-FIELD-BINDING' 'True' {
  $rec = Read-NeoJsonFile $keepPathK
  $man = Read-NeoRunManifest -RunRoot $pwK.w.run
  $freeze = Get-NeoClarityLatestFreeze -RunRoot $pwK.w.run -Index $index
  [bool](([string]$rec.decided_by -ceq 'engine_auto') -and ([string]$rec.human_review -ceq 'pending') `
    -and ([string]$rec.run_id -ceq [string](Get-NeoProp $man 'run_id')) `
    -and ([string]$rec.freeze_record_sha256 -ceq [string](Get-NeoProp $freeze 'record_sha256')) `
    -and ([string]$rec.autonomy_sha256 -ceq [string]$pwK.seg) `
    -and (-not [string]::IsNullOrWhiteSpace([string]$rec.notify_outcome)))
}
Expect-Value 'P-RUN-A-KEEP-NOTIFY-AUTO-KEPT-LINE' 'True' {
  # the SESSION_END mail carries the AUTO-KEPT disclosure line
  $hit = $false
  foreach ($f in @(Get-EmlFiles $rK.notify)) {
    $txt = [System.IO.File]::ReadAllText($f.FullName)
    if (($f.Name -like '*SESSION_END*') -and ($txt -like '*AUTO-KEPT (engine-decided)*')) { $hit = $true }
  }
  [bool]$hit
}
Expect-Value 'N-RUN-A4-RUNTIME-NO-HUMAN-LEDGER-WRITE' 'True' {
  # the auto-keep path wrote ZERO human-ledger bytes: the approval ledger is
  # byte-identical and no human-gate ledger appeared under the run root
  [bool](((Get-NeoSha256File $pwK.approval) -ceq $ledgerHashPreK) `
    -and (@(Get-ChildItem -LiteralPath $pwK.w.run -Recurse -File | Where-Object { $_.Name -like '*HUMAN_GATE_LEDGER*' }).Count -eq 0))
}
Expect-Value 'N-RUN-A4-STATIC-NO-ENGINE-LEDGER-WRITER' 'True' {
  # static: orch_run.ps1 never references the human-gate ledger schema id and
  # carries no writer for it (INV-A1)
  $freshSrc = [System.IO.File]::ReadAllText($realModule)
  [bool](($freshSrc -notmatch 'human_gate_ledger') -and ($freshSrc -notmatch 'HUMAN_GATE_LEDGER'))
}

# ---- J4 NF-A6: downstream human-keep consumers refuse engine_auto_keep ------------
Expect-Block 'N-RUN-A6-KEEP-RECORD-NOT-A-LEDGER' 'entries' {
  Read-NeoRunStartApproval -LedgerPath $keepPathK -ExpectedGateRef $pwK.ref -AutonomySegment $pwK.seg -Index $index
}
Expect-Block 'N-RUN-A6-ENGINE-AUTO-KIND-REFUSED-INTERACTIVE' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'engine_auto')) `
    -ExpectedGateRef $refB -AutonomySegment 'NONE' -Index $index
}
Expect-Block 'N-RUN-A6-ENGINE-AUTO-KIND-REFUSED-AUTO' 'RUN_START_APPROVAL' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @(New-GateEntry $refB 'engine_auto')) `
    -ExpectedGateRef $refB -AutonomySegment ('f' * 64) -Index $index
}

# ---- J5 NF-A2: EVERY enumerated non-clean class => park, never auto-keep ----------
# override-driven END forges (the G-c function-override pattern): the consumer
# is proven against each enumerated class without rebuilding heavy worlds.
$convergeStubGo = { param($Context, $RepoRoot, $ApprovedPaths, $ProtectedPaths,
    $PinnedGovManifestPath, $GovernedRoot, $DerivedAt, $RouterProfile, $RiskRow, $MasterIdentity,
    $BuilderIdentity, $Index, $Goal, $RiskClass, $AllowlistItems, $TestPlan, $StopConditions,
    $ProposedEdits, $DeclaredSurfaces, $DeniedPaths, $ProposedFixTargets, $RoundIdPrefix,
    $PacketIdPrefix, $BuilderSeam, $AuditProvider, $ExternalProvider)
  return @{ stopped = $false; converged = $true } }
# NOTE the scoping trap (header of this suite): overrides land via
# ${function:script:...} so they survive the helper's return; the RESTORE
# (`. $realModule`) is ALWAYS a TOP-LEVEL statement after each scenario.
function Invoke-AutoForgedEnd([string]$case, $endOverride) {
  $pw = New-AutoPreparedWorld ('a2_' + $case)
  ${function:script:Invoke-NeoLoopConverge} = $convergeStubGo
  ${function:script:Invoke-NeoRunEndAssembly} = $endOverride
  $r = $null; $msg = ''
  try { $r = Invoke-ExecuteFix $pw $seamD1 $provD1 ('a2_' + $case) @{ AutonomyAttestationPath = $pw.att } }
  catch { $msg = [string]$_.Exception.Message }
  return @{ pw = $pw; r = $r; msg = $msg; keep = (Join-Path $pw.w.run 'engine_auto_keep.json') }
}
# (1) failed assembly (the ESCALATION lane)
$a2a = Invoke-AutoForgedEnd 'assemblyfail' { param($RunRoot, $SessionRoot, $AppRoot, $SliceEnvelopes, $SliceFinalState, $EvidencePath, $Timestamp, $NotifyTestModeDir, $NotifyLiveSend, $Index)
  return @{ run_id = 'forged'; path = 'converged'
            end_gate = @{ assembly_ok = $false; human_class = $null; converged = $true; stop_present = $false
                          assembly_fail_code = 'LEDGER_FAILURE'; assembly_fail_detail = 'forged assembly failure (fixture)' } } }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-A2-ASSEMBLY-FAILED-PARKED' 'True' {
  [bool](([bool]$a2a.r.result.parked) -and ([string]$a2a.r.result.auto.park_class -ceq 'END_ASSEMBLY_FAILED') `
    -and (-not (Test-Path -LiteralPath $a2a.keep)) -and (@(Get-EmlFiles $a2a.r.notify).Count -ge 1))
}
# (2) stopped envelope / DECISION_NEEDED lane (covers every C3 breaker trip
# class, enforcement BLOCK, and classifier ambiguity - all route to a surfaced
# STOP disposition)
$a2b = Invoke-AutoForgedEnd 'stopped' { param($RunRoot, $SessionRoot, $AppRoot, $SliceEnvelopes, $SliceFinalState, $EvidencePath, $Timestamp, $NotifyTestModeDir, $NotifyLiveSend, $Index)
  return @{ run_id = 'forged'; path = 'stop'
            end_gate = @{ assembly_ok = $true; human_class = 'DECISION_NEEDED'; converged = $false; stop_present = $true } } }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-A2-STOPPED-ENVELOPE-PARKED' 'True' {
  [bool](([bool]$a2b.r.result.parked) -and ([string]$a2b.r.result.auto.park_class -ceq 'RUN_NOT_CONVERGED') `
    -and (-not (Test-Path -LiteralPath $a2b.keep)))
}
# (3) human class not SESSION_END ((c)/(d) deliberately redundant)
$a2c = Invoke-AutoForgedEnd 'humanclass' { param($RunRoot, $SessionRoot, $AppRoot, $SliceEnvelopes, $SliceFinalState, $EvidencePath, $Timestamp, $NotifyTestModeDir, $NotifyLiveSend, $Index)
  return @{ run_id = 'forged'; path = 'converged'
            end_gate = @{ assembly_ok = $true; human_class = 'DECISION_NEEDED'; converged = $true; stop_present = $false } } }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-A2-HUMAN-CLASS-PARKED' 'True' {
  [bool](([bool]$a2c.r.result.parked) -and ([string]$a2c.r.result.auto.park_class -ceq 'RUN_HUMAN_CLASS') `
    -and (-not (Test-Path -LiteralPath $a2c.keep)))
}
# (4) the PROPAGATED-THROW lane: RUN_DISPOSITION
$a2d = Invoke-AutoForgedEnd 'throwdisp' { param($RunRoot, $SessionRoot, $AppRoot, $SliceEnvelopes, $SliceFinalState, $EvidencePath, $Timestamp, $NotifyTestModeDir, $NotifyLiveSend, $Index)
  New-NeoBlock 'reason_code=RUN_DISPOSITION forged end-assembly throw (fixture)' }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-A2-THROW-DISPOSITION-CAUGHT-PARKED' 'True' {
  [bool](($a2d.msg -ceq '') -and ([bool]$a2d.r.result.parked) -and ([string]$a2d.r.result.auto.park_class -ceq 'END_THROW') `
    -and ($a2d.r.result.auto.park_detail -like '*RUN_DISPOSITION*') -and (-not (Test-Path -LiteralPath $a2d.keep)) `
    -and (@(Get-EmlFiles $a2d.r.notify).Count -ge 1))
}
# (5) the PROPAGATED-THROW lane: RUN_UNIVERSE_OMISSION
$a2e = Invoke-AutoForgedEnd 'throwuniv' { param($RunRoot, $SessionRoot, $AppRoot, $SliceEnvelopes, $SliceFinalState, $EvidencePath, $Timestamp, $NotifyTestModeDir, $NotifyLiveSend, $Index)
  New-NeoBlock 'reason_code=RUN_UNIVERSE_OMISSION forged universe throw (fixture)' }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-A2-THROW-UNIVERSE-CAUGHT-PARKED' 'True' {
  [bool](([bool]$a2e.r.result.parked) -and ($a2e.r.result.auto.park_detail -like '*RUN_UNIVERSE_OMISSION*') `
    -and (-not (Test-Path -LiteralPath $a2e.keep)))
}
# (6) INTERACTIVE mode: the SAME throw RE-THROWS UNCHANGED (byte-identical
# manual behavior; part of the NF-A7 runtime zero-delta)
$pwA2i = New-PreparedWorld 'a2_interactive_rethrow'
${function:Invoke-NeoLoopConverge} = $convergeStubGo
${function:Invoke-NeoRunEndAssembly} = { param($RunRoot, $SessionRoot, $AppRoot, $SliceEnvelopes, $SliceFinalState, $EvidencePath, $Timestamp, $NotifyTestModeDir, $NotifyLiveSend, $Index)
  New-NeoBlock 'reason_code=RUN_DISPOSITION forged end-assembly throw (fixture)' }
$a2iMsg = ''
try { Invoke-ExecuteFix $pwA2i $seamD1 $provD1 'a2i' | Out-Null } catch { $a2iMsg = [string]$_.Exception.Message }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-A2-INTERACTIVE-RETHROWN-UNCHANGED' 'True' {
  [bool](($a2iMsg -like 'NEO-BLOCK:*') -and ($a2iMsg -like '*RUN_DISPOSITION*') -and ($a2iMsg -notlike '*PARKED*'))
}
# (7) a REAL non-clean run (no overrides): builder infrastructure explodes =>
# routed STOP => DECISION_NEEDED end evidence => parked, never auto-keep
$pwA2r = New-AutoPreparedWorld 'a2_real_stop'
$script:a2rSeam = 0
$seamA2r = { param($info) $script:a2rSeam++; throw 'builder infrastructure exploded (fixture)' }
$rA2r = Invoke-ExecuteFix $pwA2r $seamA2r $provD1 'a2r' @{ AutonomyAttestationPath = $pwA2r.att }
Expect-Value 'N-RUN-A2-REAL-STOP-PARKED' 'True' {
  [bool](([bool]$rA2r.result.parked) -and ([string]$rA2r.result.auto.park_class -ceq 'RUN_NOT_CONVERGED') `
    -and ([string]$rA2r.result.end_gate.human_class -ceq 'DECISION_NEEDED') `
    -and (-not (Test-Path -LiteralPath (Join-Path $pwA2r.w.run 'engine_auto_keep.json'))))
}

# ---- J6 NF-A9: post-gate tamper, BOTH flip directions + the entry window ----------
# (i) AUTO -> record REWRITTEN mid-run (valid alternate chain, different hash)
$pwN9a = New-AutoPreparedWorld 'a9_flip'
$slotN9a = New-SlotWorld 'n9a' $pwN9a.w.run
$script:n9aRoot = $slotN9a.root
$script:n9aEr = $slotN9a.erPath
$script:n9aW = $pwN9a.w
$script:n9aAtt = $pwN9a.att
$provN9a = { param($q)
  if ([int]$q.round -eq 0) {
    [void](Write-AutoRecord $script:n9aW $script:n9aAtt @{ declared_by = 'tampered-after-gate' })
    return @{ end_report_path = $script:n9aEr; session_root = $script:n9aRoot }
  }
  return @{ end_report_path = 'never'; session_root = 'never' } }
$sfsN9a = @(@{ slice_id = 'sA'; session_root = $slotN9a.root; final_surfaces = (Get-BundleFinalSurfaces $slotN9a.root $slotN9a.bundleRel) })
$rN9a = Invoke-ExecuteFix $pwN9a $seamK $provN9a 'n9a' @{ SliceFinalState = $sfsN9a; AutonomyAttestationPath = $pwN9a.att }
Expect-Value 'N-RUN-A9-AUTO-FLIPPED-ESCALATION-PARK' 'True' {
  [bool](([bool]$rN9a.result.parked) -and ([string]$rN9a.result.auto.park_class -ceq 'RUN_AUTONOMY_TAMPER') `
    -and (-not (Test-Path -LiteralPath (Join-Path $pwN9a.w.run 'engine_auto_keep.json'))))
}
# (ii) AUTO -> record REMOVED mid-run (never a silent interactive downgrade)
$pwN9b = New-AutoPreparedWorld 'a9_removed'
$slotN9b = New-SlotWorld 'n9b' $pwN9b.w.run
$script:n9bRoot = $slotN9b.root
$script:n9bEr = $slotN9b.erPath
$script:n9bRun = $pwN9b.w.run
$provN9b = { param($q)
  if ([int]$q.round -eq 0) {
    Remove-Item -LiteralPath (Join-Path $script:n9bRun 'autonomy_mode.json') -Force
    return @{ end_report_path = $script:n9bEr; session_root = $script:n9bRoot }
  }
  return @{ end_report_path = 'never'; session_root = 'never' } }
$sfsN9b = @(@{ slice_id = 'sA'; session_root = $slotN9b.root; final_surfaces = (Get-BundleFinalSurfaces $slotN9b.root $slotN9b.bundleRel) })
$rN9b = Invoke-ExecuteFix $pwN9b $seamK $provN9b 'n9b' @{ SliceFinalState = $sfsN9b; AutonomyAttestationPath = $pwN9b.att }
Expect-Value 'N-RUN-A9-AUTO-REMOVED-ESCALATION-PARK' 'True' {
  [bool](([bool]$rN9b.result.parked) -and ([string]$rN9b.result.auto.park_class -ceq 'RUN_AUTONOMY_TAMPER') `
    -and ($rN9b.result.auto.park_detail -like '*GONE*') `
    -and (-not (Test-Path -LiteralPath (Join-Path $pwN9b.w.run 'engine_auto_keep.json'))))
}
# (iii) INTERACTIVE -> a valid record ADDED mid-run => END recompute mismatch
# vs the tuple-bound NONE => ESCALATION park (never a silent mode adoption)
$pwN9c = New-PreparedWorld 'a9_added'
$slotN9c = New-SlotWorld 'n9c' $pwN9c.w.run
$script:n9cRoot = $slotN9c.root
$script:n9cEr = $slotN9c.erPath
$script:n9cW = $pwN9c.w
$script:n9cAtt = New-AutoAttestation $ScratchRoot
$provN9c = { param($q)
  if ([int]$q.round -eq 0) {
    [void](Write-AutoRecord $script:n9cW $script:n9cAtt)
    return @{ end_report_path = $script:n9cEr; session_root = $script:n9cRoot }
  }
  return @{ end_report_path = 'never'; session_root = 'never' } }
$sfsN9c = @(@{ slice_id = 'sA'; session_root = $slotN9c.root; final_surfaces = (Get-BundleFinalSurfaces $slotN9c.root $slotN9c.bundleRel) })
Expect-Block 'N-RUN-A9-INTERACTIVE-ADDED-ESCALATION-PARK' 'RUN_AUTONOMY_TAMPER' {
  Invoke-ExecuteFix $pwN9c $seamK $provN9c 'n9c' @{ SliceFinalState = $sfsN9c; AutonomyAttestationPath = $script:n9cAtt }
}
# (iv) the ENTRY window: a record added AFTER the NONE-bound approval but
# BEFORE execute recomputes a hash-bearing tuple that matches NO entry
$pwN9d = New-PreparedWorld 'a9_pregate'
$attN9d = New-AutoAttestation $ScratchRoot
[void](Write-AutoRecord $pwN9d.w $attN9d)
Expect-Block 'N-RUN-A9-PREGATE-FLIP-ENTRY-REFUSES' 'RUN_START_APPROVAL' {
  Invoke-ExecuteFix $pwN9d $seamD1 $provD1 'n9d' @{ AutonomyAttestationPath = $attN9d }
}
# (v) 5->6 segment CUTOVER: an approval recorded on the OLD 5-segment tuple
# finds no 6-segment match and REFUSES (fail-closed cutover)
$pwN9e = New-PreparedWorld 'a9_cutover'
$oldRef = ([string]$pwN9e.ref) -creplace '\|NONE$', ''
$pwN9e.approval = Write-Approval @(New-GateEntry $oldRef)
Expect-Block 'N-RUN-CUTOVER-5SEG-APPROVAL-REFUSED' 'RUN_START_APPROVAL' {
  Invoke-ExecuteFix $pwN9e $seamD1 $provD1 'n9e'
}

# ---- J7 NF-A7: one-decision-read-site (static allowlist + toggle-blind floor) -----
Expect-Value 'N-RUN-A7-STATIC-ALLOWLIST' 'True' {
  $freshSrc = [System.IO.File]::ReadAllText($realModule)
  $freshLines = [System.IO.File]::ReadAllLines($realModule)
  # (a) the raw filename appears EXACTLY once: the leaf-constant definition
  $rawHits = [regex]::Matches($freshSrc, 'autonomy_mode\.json')
  $rawOk = (($rawHits.Count -eq 1) -and ($freshSrc -match "NeoRunAutonomyLeaf\s+=\s+'autonomy_mode\.json'"))
  # (b) every accessor-name line matches the enumerated allowlist: the doc
  # comment, the function definition, and EXACTLY five governed call sites
  # (prepare entry, prepare full, execute entry, END interactive probe, END
  # auto recompute)
  $acc = @($freshLines | Where-Object { $_ -match 'Get-NeoRunAutonomyMode' })
  $def = @($acc | Where-Object { $_ -match '^function Get-NeoRunAutonomyMode' })
  $doc = @($acc | Where-Object { $_ -match '^#' })
  $calls = @($acc | Where-Object { $_ -match '^\s*(\[void\]\(|\$\w+ = )Get-NeoRunAutonomyMode -RunRoot \$RunRoot -SessionRoot \$SessionRoot -Stage ' })
  $callsOk = (($calls.Count -eq 5) -and (($def.Count + $doc.Count + $calls.Count) -eq $acc.Count) -and ($def.Count -eq 1))
  [bool]($rawOk -and $callsOk)
}
Expect-Value 'N-RUN-A7-FLOOR-MODULES-TOGGLE-BLIND' 'True' {
  # NEITHER the accessor name NOR the raw filename appears in ANY frozen
  # engine module: the floor machinery cannot even see the toggle
  $ok = $true
  foreach ($mod in @('orch_clarity.ps1', 'orch_loop.ps1', 'orch_enforce.ps1', 'orch_external.ps1',
      'orch_supervisor.ps1', 'orch_schema.ps1', 'orch_io.ps1', 'orch_class.ps1', 'orch_router.ps1',
      'orch_govmanifest.ps1', 'orch_diff.ps1', 'orchestrator.ps1')) {
    $src = [System.IO.File]::ReadAllText((Join-Path $orchDir $mod))
    if (($src -match 'Get-NeoRunAutonomyMode') -or ($src -match 'autonomy_mode\.json')) { $ok = $false }
  }
  [bool]$ok
}

# ---- J8 NF-A1a..m: the floor stays HARD, toggle ON (byte-identical outcomes) ------
# METHOD: each row's toggle-blind guard is driven TWICE with IDENTICAL inputs -
# once with NO auto chain in the world, once with a VALID AUTO chain present -
# and the outcomes must be byte-identical (the runtime half of NF-A7's
# zero-delta; the static half is J7). Static-property rows (d/h/i/j/k) are
# structural scans - toggle-blind by construction.
$wF = New-World 'floor_ctx'
$attF = New-AutoAttestation $ScratchRoot
# --- capture OFF (no chain on disk anywhere in this world) ---
$offA = Get-BlockMsg { Assert-NeoSafeRel 'S:/NEO/evil.txt' }
$offB = [string](Get-NeoExternalAttestationRefusal (Join-Path $ScratchRoot 'no_such_def_p7.md'))
$offC = Get-BlockMsg { Assert-NeoContained $wF.app '..\outside.txt' }
$offE = Get-BlockMsg { Assert-NeoClarityRowMapping -SlicePlan (New-DefSlices) -RiskRows @(@{ row_id = 'r1'; risk_class = 'weird' }) }
$offG = Get-NeoExternalLaneStatus -RunRoot $wF.run -SliceId 'sX' -RoundId '0' -BundleDiffHash ('a' * 64) -Index $index
$offM = Get-BlockMsg { Assert-NeoClarityJudgingRegistrations -SlicePlan @(@{ slice_id = 'sX'; acceptance_harness_paths = @('app/widget.txt') }) -GovernedRoot $wF.gov }
$govPinF = Join-Path $ScratchRoot 'floor_gov_pin.json'
[void](New-NeoClarityGovManifestPin -GovernedRoot $wF.gov -DerivedAt $TS -PinOutPath $govPinF)
# tamper a NON-schema floor member (the classmap copy must stay parseable for
# the judging-registration probes in this same world)
$tamperRelF = [string]@(@($script:NeoGovDefaultMandatoryRels) | Where-Object { ([string]$_) -notlike '*schema*' })[0]
Add-Content -LiteralPath (Join-Path $wF.gov ($tamperRelF -replace '/', '\')) -Value ' ' -Encoding Ascii
$offL = Get-BlockMsg { Assert-NeoGovManifestReverify -PinnedPath $govPinF -Current (Build-NeoGovManifest -GovernedRoot $wF.gov -DerivedAt $TS) -GovernedRoot $wF.gov }
# --- toggle ON: a VALID AUTO chain lands in the world ---
[void](Write-AutoRecord $wF $attF)
$onA = Get-BlockMsg { Assert-NeoSafeRel 'S:/NEO/evil.txt' }
$onB = [string](Get-NeoExternalAttestationRefusal (Join-Path $ScratchRoot 'no_such_def_p7.md'))
$onC = Get-BlockMsg { Assert-NeoContained $wF.app '..\outside.txt' }
$onE = Get-BlockMsg { Assert-NeoClarityRowMapping -SlicePlan (New-DefSlices) -RiskRows @(@{ row_id = 'r1'; risk_class = 'weird' }) }
$onG = Get-NeoExternalLaneStatus -RunRoot $wF.run -SliceId 'sX' -RoundId '0' -BundleDiffHash ('a' * 64) -Index $index
$onM = Get-BlockMsg { Assert-NeoClarityJudgingRegistrations -SlicePlan @(@{ slice_id = 'sX'; acceptance_harness_paths = @('app/widget.txt') }) -GovernedRoot $wF.gov }
$onL = Get-BlockMsg { Assert-NeoGovManifestReverify -PinnedPath $govPinF -Current (Build-NeoGovManifest -GovernedRoot $wF.gov -DerivedAt $TS) -GovernedRoot $wF.gov }
Expect-Value 'N-RUN-A1a-PROD-WRITE-BLOCKS-UNDER-AUTO' 'True' {
  [bool](($onA -ceq $offA) -and ($onA -cne 'NO-BLOCK') -and ($onA -like 'NEO-BLOCK:*'))
}
Expect-Value 'N-RUN-A1b-EXTERNAL-ACCOUNT-GATE-UNDER-AUTO' 'True' {
  [bool](($onB -ceq $offB) -and ($onB -like '*refused*'))
}
Expect-Value 'N-RUN-A1c-DESTRUCTIVE-OUTSIDE-SCOPE-UNDER-AUTO' 'True' {
  [bool](($onC -ceq $offC) -and ($onC -cne 'NO-BLOCK') -and ($onC -like 'NEO-BLOCK:*'))
}
Expect-Value 'N-RUN-A1d-SERIAL-ONLY-STRUCTURAL' 'True' {
  $freshSrc = [System.IO.File]::ReadAllText($realModule)
  [bool](($freshSrc -notmatch 'Start-Job') -and ($freshSrc -notmatch 'Start-Process') -and ($freshSrc -notmatch 'Runspace') `
    -and ($freshSrc -notmatch 'BeginInvoke') -and ($freshSrc -notmatch '-AsJob') -and ($freshSrc -notmatch 'ForEach-Object\s+-Parallel'))
}
Expect-Value 'N-RUN-A1e-CLASSIFIER-UNKNOWN-BLOCKS-UNDER-AUTO' 'True' {
  [bool](($onE -ceq $offE) -and ($onE -cne 'NO-BLOCK') -and ($onE -like 'NEO-BLOCK:*'))
}
Expect-Value 'N-RUN-A1g-EXTERNAL-LANE-MISSING-UNDER-AUTO' 'True' {
  [bool](([string]$onG.status -ceq [string]$offG.status) -and ([string]$onG.status -ceq 'MISSING') `
    -and ([string]$onG.reason -ceq [string]$offG.reason))
}
Expect-Value 'N-RUN-A1h-NO-CREDENTIAL-CONTENT-READ' 'True' {
  $freshSrc = [System.IO.File]::ReadAllText($realModule)
  [bool](($freshSrc -notmatch 'Get-Content[^\r\n]*redential') -and ($freshSrc -notmatch 'ReadAll\w+\([^\r\n]*redential'))
}
Expect-Value 'N-RUN-A1i-NO-NETWORK-SIDE-EFFECTS' 'True' {
  $freshSrc = [System.IO.File]::ReadAllText($realModule)
  [bool](($freshSrc -notmatch 'Invoke-WebRequest') -and ($freshSrc -notmatch 'Invoke-RestMethod') `
    -and ($freshSrc -notmatch 'SmtpClient') -and ($freshSrc -notmatch 'WebClient') `
    -and ($freshSrc -notmatch 'HttpClient') -and ($freshSrc -notmatch 'System\.Net\.Sockets'))
}
Expect-Value 'N-RUN-A1j-NO-DEPENDENCY-INSTALL' 'True' {
  $freshSrc = [System.IO.File]::ReadAllText($realModule)
  [bool](($freshSrc -notmatch 'Install-Module') -and ($freshSrc -notmatch 'Install-Package') `
    -and ($freshSrc -notmatch 'winget') -and ($freshSrc -notmatch 'choco') `
    -and ($freshSrc -notmatch 'pip install') -and ($freshSrc -notmatch 'npm install'))
}
Expect-Value 'N-RUN-A1k-NO-ARBITRARY-PROCESS-LAUNCH' 'True' {
  $freshSrc = [System.IO.File]::ReadAllText($realModule)
  [bool](($freshSrc -notmatch 'Diagnostics\.Process') -and ($freshSrc -notmatch 'cmd(\.exe)? /c') `
    -and ($freshSrc -notmatch '& powershell'))
}
Expect-Value 'N-RUN-A1l-GOV-MANIFEST-TAMPER-BLOCKS-UNDER-AUTO' 'True' {
  [bool](($onL -ceq $offL) -and ($onL -cne 'NO-BLOCK') -and ($onL -like 'NEO-BLOCK:*'))
}
Expect-Value 'N-RUN-A1m-JUDGING-PATH-GUARD-UNDER-AUTO' 'True' {
  [bool](($onM -ceq $offM) -and ($onM -cne 'NO-BLOCK') -and ($onM -like '*CLARITY_REGISTRATION*'))
}
# A1f (cold-auditor/XC2 machinery): a GO slice with NO final-state descriptor
# fails END assembly IDENTICALLY in both modes; AUTO additionally parks.
$pwF1 = New-PreparedWorld 'a1f_int'
$slotF1 = New-SlotWorld 'f1int' $pwF1.w.run
$script:f1Root = $slotF1.root
$script:f1Er = $slotF1.erPath
$provF1 = { param($q) return @{ end_report_path = $script:f1Er; session_root = $script:f1Root } }
$rF1 = Invoke-ExecuteFix $pwF1 $seamK $provF1 'a1f_int'
$pwF2 = New-AutoPreparedWorld 'a1f_auto'
$slotF2 = New-SlotWorld 'f2auto' $pwF2.w.run
$script:f2Root = $slotF2.root
$script:f2Er = $slotF2.erPath
$provF2 = { param($q) return @{ end_report_path = $script:f2Er; session_root = $script:f2Root } }
$rF2 = Invoke-ExecuteFix $pwF2 $seamK $provF2 'a1f_auto' @{ AutonomyAttestationPath = $pwF2.att }
Expect-Value 'N-RUN-A1f-AUDITOR-BINDING-IDENTICAL-UNDER-AUTO' 'True' {
  $gInt = $rF1.result.end_gate
  $gAuto = $rF2.result.end_gate
  [bool]((-not [bool]$gInt.assembly_ok) -and (-not [bool]$gAuto.assembly_ok) `
    -and ([string]$gAuto.assembly_fail_code -ceq [string]$gInt.assembly_fail_code) `
    -and ([bool]$rF2.result.parked) -and ([string]$rF2.result.auto.park_class -ceq 'END_ASSEMBLY_FAILED') `
    -and (-not (Test-Path -LiteralPath (Join-Path $pwF2.w.run 'engine_auto_keep.json'))))
}

# ---- J9 NEUTER-FLIPS (the new guards can FAIL - red-side proofs) ------------------
# (i) attestation stamp check neutered => an UNSIGNED template ACTIVATES AUTO
$patchA1 = New-PatchedRunModule 'autostamp' '  if (-not $inForce) {' '  if ($false) {'
. $patchA1; Set-Tripwire
$wNs = New-World 'neuter_stamp'
$attNs = New-AutoAttestation $ScratchRoot 'LOW' 'unsigned'
[void](Write-AutoRecord $wNs $attNs)
$pkgNs = Invoke-PrepareFix $wNs $stubGo @{ AutonomyAttestationPath = $attNs }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-STAMP-UNSIGNED-ACTIVATES' 'True' {
  # fail-open proof: the unsigned template surfaced an AUTO package
  [bool]([string]$pkgNs.autonomy_mode_display -clike '*AUTO*')
}
# (ii) the interactive tamper probe neutered => a mid-run added record is
# silently ADOPTED-IGNORED (the silent-adoption outcome the real guard abolishes)
$patchA2 = New-PatchedRunModule 'tamperprobe' '    if ($null -ne $probeTamper) {' '    if ($false) {'
. $patchA2; Set-Tripwire
$pwNp = New-PreparedWorld 'neuter_probe'
$slotNp = New-SlotWorld 'np' $pwNp.w.run
$script:npRoot = $slotNp.root
$script:npEr = $slotNp.erPath
$script:npW = $pwNp.w
$script:npAtt = New-AutoAttestation $ScratchRoot
$provNp = { param($q)
  if ([int]$q.round -eq 0) {
    [void](Write-AutoRecord $script:npW $script:npAtt)
    return @{ end_report_path = $script:npEr; session_root = $script:npRoot }
  }
  return @{ end_report_path = 'never'; session_root = 'never' } }
$sfsNp = @(@{ slice_id = 'sA'; session_root = $slotNp.root; final_surfaces = (Get-BundleFinalSurfaces $slotNp.root $slotNp.bundleRel) })
$rNp = $null; $npMsg = ''
try { $rNp = Invoke-ExecuteFix $pwNp $seamK $provNp 'np' @{ SliceFinalState = $sfsNp; AutonomyAttestationPath = $script:npAtt } }
catch { $npMsg = [string]$_.Exception.Message }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-TAMPER-PROBE-FAILS-OPEN' 'True' {
  [bool](($npMsg -ceq '') -and ($null -ne $rNp) -and ([string]$rNp.result.end_gate.human_class -ceq 'SESSION_END'))
}
# (iii) the (d) SESSION_END check neutered => a non-clean forged run AUTO-KEEPS
$patchA3 = New-PatchedRunModule 'noncleankeep' `
  "  } elseif ([string](Get-NeoProp `$gate 'human_class') -cne 'SESSION_END') {" '  } elseif ($false) {'
. $patchA3; Set-Tripwire
$pwNk = New-AutoPreparedWorld 'neuter_keep'
${function:Invoke-NeoLoopConverge} = $convergeStubGo
${function:Invoke-NeoRunEndAssembly} = { param($RunRoot, $SessionRoot, $AppRoot, $SliceEnvelopes, $SliceFinalState, $EvidencePath, $Timestamp, $NotifyTestModeDir, $NotifyLiveSend, $Index)
  return @{ run_id = 'forged'; path = 'converged'
            end_gate = @{ assembly_ok = $true; human_class = 'DECISION_NEEDED'; converged = $true; stop_present = $false } } }
$rNk = Invoke-ExecuteFix $pwNk $seamD1 $provD1 'nk' @{ AutonomyAttestationPath = $pwNk.att }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-NONCLEAN-AUTO-KEEPS' 'True' {
  # fail-open proof: with (d) neutered, a DECISION_NEEDED run auto-kept
  [bool](([string]$rNk.result.auto.decision -ceq 'auto_keep') `
    -and (Test-Path -LiteralPath (Join-Path $pwNk.w.run 'engine_auto_keep.json')))
}

# =============================================================================
# SECTION J10 - ITERATE ROUND (codex NO-GO findings: HIGH-1/MED-1 conflicted
# START authority; HIGH-2/MED-2 never-PROD envelope; cold LOW-1 hash guard)
# =============================================================================
Write-Host "=== SECTION J10: iterate round (conflicted authority + never-PROD) ===" -ForegroundColor Cyan
# ---- FIX-1: CONFLICTED START AUTHORITY (one plan identity = ONE autonomy
# identity; an entry on the same 5-segment prefix with a different 6th
# segment REFUSES - the post-gate mode-flip forgery class) ---------------------
$refC6none = $refB + '|NONE'
$refC6hash = $refB + '|' + ('f' * 64)
Expect-Block 'N-RUN-A9-CONFLICTED-AUTHORITY-DIRECT' 'CONFLICTED START AUTHORITY' {
  Read-NeoRunStartApproval -LedgerPath (Write-Approval @((New-GateEntry $refC6none), (New-GateEntry $refC6hash 'attested_start_approval'))) `
    -ExpectedGateRef $refC6none -AutonomySegment 'NONE' -Index $index
}
# FORWARD e2e (the codex HIGH-1 attack verbatim): interactive-prepared run with
# the legitimate recorded human answer on the NONE tuple; attacker writes a
# valid autonomy record + a FORGED attested entry on the recomputed hash tuple;
# execute must REFUSE naming the conflict - never go hands-off.
$pwCf = New-PreparedWorld 'a9_conflict_fwd'
$attCf = New-AutoAttestation $ScratchRoot
$segCf = Write-AutoRecord $pwCf.w $attCf
$refCfAuto = Get-ExpectedRef $pwCf.w $segCf
$pwCf.approval = Write-Approval @((New-GateEntry $pwCf.ref), (New-GateEntry $refCfAuto 'attested_start_approval'))
Expect-Block 'N-RUN-A9-CONFLICTED-FORWARD-E2E' 'CONFLICTED START AUTHORITY' {
  Invoke-ExecuteFix $pwCf $seamD1 $provD1 'cf' @{ AutonomyAttestationPath = $attCf }
}
# REVERSE e2e: auto-prepared run (attested entry recorded); attacker removes
# the record + forges a human entry on the NONE tuple; execute (now
# interactive) must REFUSE with the same conflicted-authority message.
$pwCr = New-AutoPreparedWorld 'a9_conflict_rev'
$refCrNone = Get-ExpectedRef $pwCr.w 'NONE'
Remove-Item -LiteralPath (Join-Path $pwCr.w.run 'autonomy_mode.json') -Force
$pwCr.approval = Write-Approval @((New-GateEntry $pwCr.ref 'attested_start_approval'), (New-GateEntry $refCrNone))
Expect-Block 'N-RUN-A9-CONFLICTED-REVERSE-E2E' 'CONFLICTED START AUTHORITY' {
  Invoke-ExecuteFix $pwCr $seamD1 $provD1 'cr' @{ AutonomyAttestationPath = $pwCr.att }
}
# NEUTER-FLIP: with the conflicted scan gone, the forged-second-authority
# ledger is ACCEPTED (fail-open) - the guard is load-bearing.
$patchA4 = New-PatchedRunModule 'conflictscan' `
  '    if ($er.StartsWith($prefix5, [System.StringComparison]::Ordinal) -and ($er -cne $ExpectedGateRef)) {' '    if ($false) {'
. $patchA4; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-CONFLICTED-FAILS-OPEN' 'True' {
  $e = Read-NeoRunStartApproval -LedgerPath (Write-Approval @((New-GateEntry $refC6none), (New-GateEntry $refC6hash 'attested_start_approval'))) `
    -ExpectedGateRef $refC6none -AutonomySegment 'NONE' -Index $index
  [bool]($null -ne $e)
}
. $realModule; Set-Tripwire
# legitimate iterate rounds unaffected: a different plan_round is a DIFFERENT
# 5-segment prefix and does NOT trip the conflicted scan
Expect-Value 'P-RUN-A9-CONFLICTED-DIFFERENT-ROUND-OK' 'raphael' {
  $otherRound = 'NEO-RUN-START|ridB|2|' + ('c' * 64) + '|' + ('d' * 64) + '|' + ('f' * 64)
  [string](Get-NeoProp (Read-NeoRunStartApproval -LedgerPath (Write-Approval @((New-GateEntry $refC6none), (New-GateEntry $otherRound 'attested_start_approval'))) `
    -ExpectedGateRef $refC6none -AutonomySegment 'NONE' -Index $index) 'authorized_by')
}
# ---- FIX-2: NEVER-PROD envelope assertion (AUTO is DEV-only; the PROD tree
# can never be an AUTO envelope). STRING/PATH RESOLUTION ONLY - nothing is
# created, read, or written under the real S:\NEO. ----------------------------
$wPr = New-World 'a8_prodroot'
$attPr = New-AutoAttestation 'S:\NEO'
[void](Write-AutoRecord $wPr $attPr)
Expect-Block 'N-RUN-A8-ENVELOPE-PROD-ROOT-PARKED' 'the PROD tree can never be an AUTO envelope' {
  Invoke-PrepareFix $wPr $stubGo @{ AutonomyAttestationPath = $attPr }
}
Expect-Value 'P-RUN-A8-DEV-ROOT-NOT-PROD-PREFIX' 'False' {
  # segment-safety of the prefix compare: the DEV root does NOT live under
  # the PROD prefix 'S:\NEO\'
  $prod = ([System.IO.Path]::GetFullPath('S:\NEO')).TrimEnd('\') + '\'
  $dev = ([System.IO.Path]::GetFullPath('S:\NEO_dev')).TrimEnd('\') + '\'
  [string]($dev.StartsWith($prod, [System.StringComparison]::OrdinalIgnoreCase))
}
# NEUTER-FLIP: with the never-PROD assertion gone, the PROD-declared envelope
# proceeds PAST it (it then dies at the weaker generic containment check with
# NO PROD naming - the explicit PROD refusal is load-bearing).
$patchA5 = New-PatchedRunModule 'neverprod' `
  '    if ($pairVal.StartsWith($prodFull, [System.StringComparison]::OrdinalIgnoreCase)) {' '    if ($false) {'
. $patchA5; Set-Tripwire
$wPr2 = New-World 'a8_prodroot_neuter'
$attPr2 = New-AutoAttestation 'S:\NEO'
[void](Write-AutoRecord $wPr2 $attPr2)
$pr2Msg = ''
try { Invoke-PrepareFix $wPr2 $stubGo @{ AutonomyAttestationPath = $attPr2 } | Out-Null } catch { $pr2Msg = [string]$_.Exception.Message }
. $realModule; Set-Tripwire
Expect-Value 'N-RUN-NEUTER-NEVERPROD-FAILS-OPEN' 'True' {
  [bool](($pr2Msg -notlike '*PROD tree can never*') -and ($pr2Msg -like '*OUTSIDE the attestation-declared root*'))
}

# =============================================================================
# SUMMARY + RESIDUE-CLEAN SECOND PASS (3.D.13)
# =============================================================================
$total = @($script:results).Count
$failed = @($script:results | Where-Object { -not $_.pass })
$skips = @($script:results | Where-Object { $_.kind -eq 'skip' })
$passCount = $total - $failed.Count

Write-Host ""
Write-Host ("Results: {0}/{1} PASS ({2} skip-disclosed)" -f $passCount, $total, $skips.Count) -ForegroundColor Cyan

if ($ProofOut) {
  $proof = [pscustomobject]@{
    suite     = 'orch_run_suite'
    slice     = '4.0-P4-AUTONOMY-INTEGRATE'
    total     = $total
    passed    = $passCount
    failed    = $failed.Count
    skipped   = $skips.Count
    results   = $script:results
    generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  $proof | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ProofOut -Encoding Ascii
}

# residue-clean second pass: remove ALL scratch worlds, then PROVE the root is gone.
if (-not $KeepScratch) {
  Remove-Item -Recurse -Force -LiteralPath $ScratchRoot -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $ScratchRoot) {
    Write-Host "RESIDUE: scratch root survived cleanup: $ScratchRoot" -ForegroundColor Red
    $failed = @($failed) + [pscustomobject]@{ guard = 'RESIDUE-CLEAN'; pass = $false }
  } else {
    Write-Host "residue-clean: scratch + all worlds removed" -ForegroundColor Green
  }
}

if ($failed.Count -gt 0) { exit 1 } else { exit 0 }
