# orch_fixture_suite.ps1 - NEO 4.0-P3-B (B1) INDEPENDENT harness (v4 5.7).
# ASCII-only (D10). Kept SEPARATE from the engine it tests.
#
# Proves each B1 enforcement FAILS CLOSED: every seeded-defect fixture asserts the
# engine BLOCKS the bad input at exactly one guard, so removing that guard flips
# the assertion. Plus one END-TO-END serial run producing schema-valid evidence
# validated against the INSTALLED spine. Writes NO AUDIT_RESULT (the engine never
# can); the isolated-auditor STUB (separate script) is the only result writer.
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'

$orchDir = Split-Path -Parent $PSScriptRoot   # ...\.neo\scripts\orchestrator
. "$orchDir\..\_neo_root.ps1"
$NeoRoot = Resolve-NeoRoot $orchDir
. "$orchDir\orch_engine.ps1"

$schemaDir = Join-Path $NeoRoot '.neo\schema'
$index = Get-NeoSchemaIndex $schemaDir
$stub = Join-Path $orchDir 'orch_auditor_stub.ps1'
$TS = '2026-07-03T00:00:00Z'

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_orch_b1_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing --------------------------------------------------------
# kind = 'negative' -> a fail-closed GUARD (load-bearing; must BLOCK bad input).
# kind = 'positive' -> a happy-path / info check (NOT a guard; must succeed).
$script:results = @()
function Record($name, $pass, $detail, $kind = 'negative') {
  $script:results += [pscustomobject]@{ guard = $name; pass = [bool]$pass; detail = "$detail"; kind = $kind }
  $tag = if ($pass) { 'PASS' } else { 'FAIL' }
  $col = if ($pass) { 'Green' } else { 'Red' }
  $ktag = if ($kind -eq 'negative') { 'GUARD' } else { 'info ' }
  Write-Host ("  [{0}][{1}] {2} - {3}" -f $tag, $ktag, $name, $detail) -ForegroundColor $col
}
function Expect-Block($name, $sb) {
  try { & $sb; Record $name $false 'NO BLOCK (guard did not fire)' 'negative' }
  catch {
    if ($_.Exception.Message -like 'NEO-BLOCK:*') { Record $name $true $_.Exception.Message 'negative' }
    else { Record $name $false ('threw non-BLOCK: ' + $_.Exception.Message) 'negative' }
  }
}
# For Test-NeoSchema, which RETURNS violations (does not throw). Passes iff the
# malformed/mismatched schema yields at least one violation (fail-closed).
function Expect-SchemaViolation($name, $schema, $inst) {
  try {
    $v = @(Test-NeoSchema -Instance $inst -Schema $schema -Index $index)
    if ($v.Count -gt 0) { Record $name $true ('BLOCKED: ' + $v[0]) 'negative' }
    else { Record $name $false 'NO VIOLATION (schema defect swallowed / not detected)' 'negative' }
  } catch { Record $name $false ('threw: ' + $_.Exception.Message) 'negative' }
}
function Expect-Ok($name, $sb) {
  try { $r = & $sb; Record $name $true "$r" 'positive' }
  catch { Record $name $false ('unexpected block/error: ' + $_.Exception.Message) 'positive' }
}

# ---- fixture builders (valid unless a defect is seeded) ---------------------
function New-Env($id, $class, $schemaId, $prole, $pclass, $naReason) {
  $ea = @{
    ArtifactId = $id; ArtifactClass = $class; SchemaId = $schemaId; SchemaVersion = '4.0-P3-B'
    ProducerRole = $prole; ProducerClass = $pclass; ValidatorRole = $prole; ValidatorClass = 'validator'
    Timestamp = $TS; DeclaredPaths = @('./program/'); DeclaredSurfaces = @('filesystem'); SourcePackets = @(); GateRef = $null
  }
  if ($naReason) { $ea['ValidatorNAReason'] = $naReason; $ea['ValidatorClass'] = $pclass }
  return (New-NeoEnvelope @ea)
}
function New-FixtureSpec([switch]$Invalid) {
  $b = [ordered]@{
    spec_id = 'spec-1'; spec_version = '1.0'; intent = 'fixture app'
    in_scope = @('feature-a', 'feature-b'); out_of_scope = @('nothing')
    acceptance_criteria = @(@{ id = 'AC1'; statement = 'does X'; verifiable_by = 'harness:test-x' })
  }
  if ($Invalid) { $b.Remove('acceptance_criteria') }   # seeded defect: drop a REQUIRED field
  $o = [pscustomobject]$b
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'spec-1' 'evidence' 'neo:project_spec' 'spec-author' 'strong_producer' $null)
  Set-NeoArtifactHash $o; return $o
}
function New-FixtureConstraint {
  $o = [pscustomobject][ordered]@{
    package_id = 'cp-1'; package_version = '1.0'
    constraints = @(@{ id = 'C1'; statement = 'must do X'; kind = 'functional'; severity = 'high' })
    test_harness_ref = @{ artifact_id = 'th-1'; content_hash = 'h1' }
    profile_risk_ref = @{ artifact_id = 'pr-1'; content_hash = 'h2' }
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'cp-1' 'constraint' 'neo:constraint_package' 'constraint-editor' 'strong_producer' $null)
  Set-NeoArtifactHash $o; return $o
}
function New-FixtureArch {
  $o = [pscustomobject][ordered]@{
    architecture_id = 'arch-1'; architecture_version = '1.0'
    components = @(@{ id = 'comp1'; responsibility = 'core'; owns_paths = @('./src/') })
    interfaces = @(@{ id = 'if1'; between = @('comp1', 'comp2'); contract = 'iface' })
    disjoint_scope_map = @(@{ group = 'g1'; paths = @('./src/'); proven_disjoint = $false })
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'arch-1' 'evidence' 'neo:architecture' 'architect' 'strong_producer' $null)
  Set-NeoArtifactHash $o; return $o
}
function New-FixtureRisk {
  $o = [pscustomobject][ordered]@{
    register_id = 'rr-1'; register_version = '1.0'
    risks = @(@{ id = 'r1'; area = 'general_feature'; risk_class = 'low'; never_batchable = $false; audit_tier = 'lightweight' })
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'rr-1' 'profile_risk' 'neo:risk_register' 'risk-author' 'strong_producer' $null)
  Set-NeoArtifactHash $o; return $o
}
function New-FixtureEndReport($slug, $proofRef) {
  # $proofRef optional: overrides the promised tests_run.proof_ref (default preserves the
  # original single-proof convention, so all pre-N3 fixtures are byte-for-byte unchanged).
  if (-not $proofRef) { $proofRef = "./NEO_SESSION/$slug/proof.ps1" }
  $o = [pscustomobject][ordered]@{
    report_id = "er-$slug"; slug = $slug
    changed_files = @(@{ path = './src/feature_a.txt'; sha256_after = ('0' * 64); change_kind = 'create' })
    diff_manifest = @(@{ path = './src/feature_a.txt'; diff_ref = './diffs/feature_a.patch' })
    tests_run = @(@{ command = 'run tests'; exit_code = 0; proof_ref = $proofRef })
    skipped_or_unverified = @()
    deferrals = @()
    rollback_notes = @{ snapshot_ref = './snapshots/pre'; touched_files = @('./src/feature_a.txt'); dependency_changes = @(); migration_status = 'none'; cleanup_status = 'clean' }
    touched_flags = @{ touched_constraints = $false; touched_tests_harness = $false; touched_profile_risk = $false }
    auditor_recommendation_slot = $null
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env "er-$slug" 'evidence' 'neo:subsession_end_report' 'builder' 'cheap_producer' 'raw builder evidence pre-audit')
  Set-NeoArtifactHash $o; return $o
}
function Build-ValidProgram($programRoot) {
  New-Item -ItemType Directory -Force -Path $programRoot | Out-Null
  Write-NeoJsonFile (Get-NeoProgramPath $programRoot 'PROJECT_SPEC')       (New-FixtureSpec)
  Write-NeoJsonFile (Get-NeoProgramPath $programRoot 'CONSTRAINT_PACKAGE') (New-FixtureConstraint)
  Write-NeoJsonFile (Get-NeoProgramPath $programRoot 'ARCHITECTURE')       (New-FixtureArch)
  Write-NeoJsonFile (Get-NeoProgramPath $programRoot 'RISK_REGISTER')      (New-FixtureRisk)
}
function Build-MiniBundle($dir, $risk) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $pf = Join-Path $dir 'proof.txt'; Set-Content -LiteralPath $pf -Value 'exit=0' -Encoding UTF8
  $members = @(@{ path = $pf; rel = './proof.txt'; role = 'proof' })
  $bp = Join-Path $dir 'AUDIT_BUNDLE.json'
  $b = New-NeoAuditBundle -BundleId ('b-' + (Split-Path -Leaf $dir)) -MemberItems $members `
    -ApprovedPaths @('./x/') -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier $risk -Timestamp $TS -Index $index -OutPath $bp
  return @{ bundle = $b; path = $bp; dir = $dir }
}
# LABELLED ADVERSARIAL FIXTURE WRITER (test-only; twin of the enforce suite's Write-AuditResult
# and the pilot's New-PilotAdversarialAuditResult). It composes a possibly-LYING AUDIT_RESULT --
# a rehash_check claim that may contradict the real member re-hash -- used ONLY to prove the
# engine's Read-NeoAuditResult independent-rehash / schema-prose guards fire. This is NOT the
# honest auditor (orch_auditor_stub.ps1 derives its verdict and cannot lie), and NO engine-library
# file references it. -ForceAllMatched ('' honest | 'true' | 'false') overrides the claimed match.
function Write-AdversarialAuditResult($path, $bundleDir, $bundle, $rec, $auditorId, $forceAllMatched = '') {
  $mismatches = @()
  foreach ($m in @($bundle.allowlist)) {
    $rel = [string]$m.path
    $mp = Assert-NeoContained $bundleDir $rel
    if ((-not (Test-Path -LiteralPath $mp)) -or ((Get-NeoSha256File $mp) -cne ([string]$m.content_hash))) { $mismatches += $rel }
  }
  $allMatched = ($mismatches.Count -eq 0)
  if ($forceAllMatched -eq 'true')  { $allMatched = $true }
  if ($forceAllMatched -eq 'false') { $allMatched = $false }
  $env = New-Env 'ar-adv' 'evidence' 'neo:audit_result' 'isolated-auditor' 'auditor' $null
  $r = [pscustomobject]@{
    result_id        = 'ar-adv'
    recommendation   = $rec
    findings         = @()
    rehash_check     = @{ all_members_matched = $allMatched; mismatches = @($mismatches) }
    auditor_identity = $auditorId
    _provenance      = $env
  }
  Set-NeoArtifactHash $r
  Assert-NeoValid $r 'neo:audit_result' $index 'AUDIT_RESULT(adversarial-fixture)'
  Write-NeoJsonFile $path $r
  return $path
}

Write-Host "NEO 4.0-P3-B (B1) fixture suite" -ForegroundColor Cyan
Write-Host "scratch: $ScratchRoot"

# =========================== G1 schema-invalid -> reject =====================
$g1 = Join-Path $ScratchRoot 'g1\program'
New-Item -ItemType Directory -Force -Path $g1 | Out-Null
Write-NeoJsonFile (Get-NeoProgramPath $g1 'PROJECT_SPEC')       (New-FixtureSpec -Invalid)
Write-NeoJsonFile (Get-NeoProgramPath $g1 'CONSTRAINT_PACKAGE') (New-FixtureConstraint)
Write-NeoJsonFile (Get-NeoProgramPath $g1 'ARCHITECTURE')       (New-FixtureArch)
Write-NeoJsonFile (Get-NeoProgramPath $g1 'RISK_REGISTER')      (New-FixtureRisk)
Expect-Block 'G1-schema-invalid-rejected' { Invoke-NeoInit -ProgramRoot $g1 -Index $index -MasterId 'm' -SessionId 's' -Timestamp $TS | Out-Null }

# =========================== G2 concurrent -> refuse =========================
$g2 = Join-Path $ScratchRoot 'g2\program'
Build-ValidProgram $g2
Invoke-NeoInit -ProgramRoot $g2 -Index $index -MasterId 'm' -SessionId 's' -Timestamp $TS | Out-Null
Expect-Block 'G2a-concurrent-init-refused' { Invoke-NeoInit -ProgramRoot $g2 -Index $index -MasterId 'm' -SessionId 's' -Timestamp $TS -OrchestrationMode 'concurrent' | Out-Null }
Expect-Block 'G2b-concurrent-mode-schema-enum' {
  $mc = Read-NeoProgramArtifact $g2 'MASTER_CHECKPOINT' $index
  $mc.orchestration_mode = 'concurrent'; Set-NeoArtifactHash $mc
  Assert-NeoValid $mc 'neo:master_checkpoint' $index 'MC-concurrent'
}

# =========================== G3 engine cannot self-approve ===================
$g3a = Join-Path $ScratchRoot 'g3a'; $mb3a = Build-MiniBundle $g3a 'high'
$ar3a = Join-Path $g3a 'AUDIT_RESULT.json'
& $stub -BundlePath $mb3a.path -BundleDir $mb3a.dir -OutPath $ar3a -Timestamp $TS -AuditorIdentity 'm1' | Out-Null
Expect-Block 'G3a-auditor-identity-eq-master' { Read-NeoAuditResult -AuditResultPath $ar3a -Bundle $mb3a.bundle -BundleDir $mb3a.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index | Out-Null }

$g3b = Join-Path $ScratchRoot 'g3b'; $mb3b = Build-MiniBundle $g3b 'high'
$ar3b = Join-Path $g3b 'AUDIT_RESULT.json'
& $stub -BundlePath $mb3b.path -BundleDir $mb3b.dir -OutPath $ar3b -Timestamp $TS -AuditorIdentity 'auditor-x' -ProducerRole 'master-orchestrator' | Out-Null
Expect-Block 'G3b-audit-result-producer-is-master' { Read-NeoAuditResult -AuditResultPath $ar3b -Bundle $mb3b.bundle -BundleDir $mb3b.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index | Out-Null }

$libFiles = @('orch_schema.ps1', 'orch_class.ps1', 'orch_io.ps1', 'orch_engine.ps1', 'orchestrator.ps1')
$noStubRef = $true
foreach ($f in $libFiles) {
  # ignore comment lines (a comment may mention the stub); only CODE references count.
  $code = @(Get-Content -LiteralPath (Join-Path $orchDir $f) | Where-Object { $_ -notmatch '^\s*#' })
  if (($code -join "`n") -match 'auditor_stub') { $noStubRef = $false }
}
Record 'G3c-struct-engine-never-invokes-auditor' $noStubRef 'no engine CODE line references/invokes orch_auditor_stub'
$engineHasResultLiteral = $false
foreach ($f in $libFiles) { if ((Get-Content -Raw -LiteralPath (Join-Path $orchDir $f)) -match 'rehash_check\s*=') { $engineHasResultLiteral = $true } }
$stubHasResultLiteral = ((Get-Content -Raw -LiteralPath $stub) -match 'rehash_check\s*=')
Record 'G3d-struct-audit_result-literal-only-in-stub' ((-not $engineHasResultLiteral) -and $stubHasResultLiteral) 'AUDIT_RESULT object literal exists only in the separate stub'

# =========================== G4 unknown class -> block =======================
$map = Get-NeoClassMap (Join-Path $schemaDir 'artifact_classes.json')
Expect-Block 'G4a-unknown-class-blocked' { Assert-NeoResolvableClass $map './program/PROJECT_SPEC.json' | Out-Null }
Expect-Block 'G4b-bogus-envelope-class-blocked' { New-Env 'x' 'totally_unknown' 'neo:project_spec' 'r' 'cheap_producer' $null | Out-Null }
$known = Resolve-NeoArtifactClass $map './s/coder_report.json'
Record 'G4c-known-class-resolves' ($known -eq 'evidence') "coder_report.json -> $known (default_class NOT used)" 'positive'

# =========================== G6 rehash-mismatch -> NO-GO =====================
# G6a/G6b use the LABELLED adversarial fixture writer (the honest deriving stub cannot lie:
# it would correctly derive NO-GO). These prove the engine's independent re-hash / schema-prose
# guards catch a LYING AUDIT_RESULT.
$g6a = Join-Path $ScratchRoot 'g6a'; $mb6a = Build-MiniBundle $g6a 'high'
Add-Content -LiteralPath (Join-Path $g6a 'proof.txt') -Value 'TAMPER'   # mutate AFTER hashing
$ar6a = Join-Path $g6a 'AUDIT_RESULT.json'
# LIE: claim all_members_matched=true + GO despite the tamper.
Write-AdversarialAuditResult $ar6a $mb6a.dir $mb6a.bundle 'GO' 'isolated-auditor-cold' 'true' | Out-Null
Expect-Block 'G6a-tampered-bundle-claimed-match' { Read-NeoAuditResult -AuditResultPath $ar6a -Bundle $mb6a.bundle -BundleDir $mb6a.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index | Out-Null }

$g6b = Join-Path $ScratchRoot 'g6b'; $mb6b = Build-MiniBundle $g6b 'high'
$ar6b = Join-Path $g6b 'AUDIT_RESULT.json'
# LIE: all_members_matched=false but recommendation=GO (schema-prose: must be NO-GO).
Write-AdversarialAuditResult $ar6b $mb6b.dir $mb6b.bundle 'GO' 'isolated-auditor-cold' 'false' | Out-Null
Expect-Block 'G6b-all_matched-false-but-GO' { Read-NeoAuditResult -AuditResultPath $ar6b -Bundle $mb6b.bundle -BundleDir $mb6b.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index | Out-Null }

# ===== F1: preflight schema-support (malformed schema can never silently pass) =====
# F1a: an UNSUPPORTED keyword inside the `if` CONDITION subschema. The instance takes
# the other branch, so the OLD code read the schema error as "if-condition unmet" and
# silently passed. Fixed: preflight BLOCKS.
$schemaF1a = @{
  type       = 'object'
  properties = @{ status = @{ type = 'string' } }
  if         = @{ properties = @{ status = @{ const = 'special' } }; unknownKeyword = @{ foo = 1 } }
  then       = @{ required = @('extra') }
}
Expect-SchemaViolation 'F1a-unsupported-keyword-in-if' $schemaF1a (@{ status = 'ordinary' })

# F1b: an UNRESOLVABLE $ref inside `then`, with the instance taking the ELSE/skip path
# so `then` is never evaluated. OLD code never touched it -> silent pass. Fixed:
# preflight validates the whole graph regardless of branch -> BLOCK.
$schemaF1b = @{
  type       = 'object'
  properties = @{ status = @{ type = 'string' } }
  if         = @{ properties = @{ status = @{ const = 'special' } } }
  then       = @{ '$ref' = 'neo:nonexistent_schema_id' }
}
Expect-SchemaViolation 'F1b-unresolvable-ref-in-then' $schemaF1b (@{ status = 'ordinary' })

# ===== F3: JSON-type-aware enum/const equality (string "5" != number 5) =====
$schemaF3 = @{ type = 'string'; enum = @(5) }   # enum member is the NUMBER 5
Expect-SchemaViolation 'F3-enum-mixed-type-not-equal' $schemaF3 '5'   # instance is STRING "5"
# positive control: number 5 vs enum [5] IS equal (numeric path still works) -> no violation
$schemaF3b = @{ enum = @(5) }
$f3ok = @(Test-NeoSchema -Instance 5 -Schema $schemaF3b -Index $index)
Record 'F3-numeric-equal-control' ($f3ok.Count -eq 0) 'number 5 matches enum [5] (no regression)' 'positive'

# ===== F2: bundle path traversal rejected (assembly + consume + stub) =====
# F2a: assembly rejects a parent-traversal member rel.
Expect-Block 'F2a-assembly-parent-traversal' {
  $d = Join-Path $ScratchRoot 'f2a'; New-Item -ItemType Directory -Force -Path $d | Out-Null
  $pf = Join-Path $d 'proof.txt'; Set-Content -LiteralPath $pf -Value 'x' -Encoding UTF8
  New-NeoAuditBundle -BundleId 'bad' -MemberItems @(@{ path = $pf; rel = '../escape'; role = 'x' }) `
    -ApprovedPaths @('./x/') -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier 'high' -Timestamp $TS -Index $index | Out-Null
}
# F2b: assembly rejects rooted / drive-qualified / UNC / backslash variants.
foreach ($bad in @('/etc/passwd', 'C:\windows\x', '\\host\share\x', 'a\..\b')) {
  Expect-Block ("F2b-assembly-unsafe[" + $bad + "]") {
    $d = Join-Path $ScratchRoot ('f2b_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $pf = Join-Path $d 'proof.txt'; Set-Content -LiteralPath $pf -Value 'x' -Encoding UTF8
    New-NeoAuditBundle -BundleId 'bad' -MemberItems @(@{ path = $pf; rel = $bad; role = 'x' }) `
      -ApprovedPaths @('./x/') -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier 'high' -Timestamp $TS -Index $index | Out-Null
  }
}
# F2c: consume rejects a hand-crafted bundle whose member rel escapes the root.
$g2c = Join-Path $ScratchRoot 'f2c'; $mb2c = Build-MiniBundle $g2c 'high'
$ar2c = Join-Path $g2c 'AUDIT_RESULT.json'
& $stub -BundlePath $mb2c.path -BundleDir $mb2c.dir -OutPath $ar2c -Timestamp $TS | Out-Null
$evil = Read-NeoJsonFile $mb2c.path
$evil.allowlist[0].path = '../../../escape'
Expect-Block 'F2c-consume-parent-traversal' {
  Read-NeoAuditResult -AuditResultPath $ar2c -Bundle $evil -BundleDir $mb2c.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index | Out-Null
}
# F2d: the auditor STUB rejects a crafted member rel too (twin guard).
Expect-Block 'F2d-stub-parent-traversal' {
  $d = Join-Path $ScratchRoot 'f2d'; $mb2d = Build-MiniBundle $d 'high'
  $b = Read-NeoJsonFile $mb2d.path
  $b.allowlist[0].path = '../../escape'
  Write-NeoJsonFile $mb2d.path $b
  & $stub -BundlePath $mb2d.path -BundleDir $mb2d.dir -OutPath (Join-Path $d 'AUDIT_RESULT.json') -Timestamp $TS
  if ($LASTEXITCODE -ne 0) { throw "NEO-BLOCK: stub rejected crafted rel (exit $LASTEXITCODE)" }
}

# =========================== E2E happy serial run ============================
Expect-Ok 'E2E-serial-run-GO' {
  $e2e = Join-Path $ScratchRoot 'e2e'
  $prog = Join-Path $e2e 'program'
  Build-ValidProgram $prog
  $init = Invoke-NeoInit -ProgramRoot $prog -Index $index -MasterId 'm1' -SessionId 's1' -Timestamp $TS -SnapshotDir (Join-Path $e2e 'snapshots')
  Read-NeoProgramArtifact $prog 'MASTER_CHECKPOINT' $index | Out-Null   # re-validate from disk
  Read-NeoProgramArtifact $prog 'SUBSESSION_INDEX'  $index | Out-Null
  if ($init.master_checkpoint.orchestration_mode -ne 'serial') { throw 'mode not serial' }

  $slug = 'ss-001'; $slugDir = Join-Path $e2e ('NEO_SESSION\' + $slug)
  New-Item -ItemType Directory -Force -Path $slugDir | Out-Null
  $specP = Get-NeoProgramPath $prog 'PROJECT_SPEC'
  $conP = Get-NeoProgramPath $prog 'CONSTRAINT_PACKAGE'
  $riskP = Get-NeoProgramPath $prog 'RISK_REGISTER'
  $allow = @(
    @{ path = $specP; rel = './program/PROJECT_SPEC.json'; role = 'project_spec' },
    @{ path = $conP;  rel = './program/CONSTRAINT_PACKAGE.json'; role = 'constraint_package' }
  )
  $sp = New-NeoStartPacket -PacketId 'pkt-1' -Goal 'build feature A' -TestPlan @('run tests') `
    -StopConditions @('scope_breach', 'ambiguity') -RiskClass 'low' -AllowlistItems $allow `
    -ApprovedPaths @('./src/') -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') `
    -ReferencedArtifacts @((Get-NeoArtifactRef $init.master_checkpoint)) -Timestamp $TS -Index $index
  $spPath = Join-Path $slugDir 'SUBSESSION_START_PACKET.json'
  Write-NeoJsonFile $spPath $sp

  $erPath = Join-Path $slugDir 'SUBSESSION_END_REPORT.json'
  Write-NeoJsonFile $erPath (New-FixtureEndReport $slug)
  Read-NeoEndReport $erPath $index | Out-Null

  # a RUNNABLE proof (exit 0) so the cold auditor's NON-CACHED re-run genuinely verifies it.
  $proofP = Join-Path $slugDir 'proof.ps1'; Set-Content -LiteralPath $proofP -Value 'exit 0' -Encoding UTF8
  $auditDir = Join-Path $slugDir 'audit'
  $members = @(
    @{ path = $specP;  rel = './program/PROJECT_SPEC.json'; role = 'spec' },
    @{ path = $conP;   rel = './program/CONSTRAINT_PACKAGE.json'; role = 'constraint' },
    @{ path = $riskP;  rel = './program/RISK_REGISTER.json'; role = 'risk' },
    @{ path = $spPath; rel = "./NEO_SESSION/$slug/SUBSESSION_START_PACKET.json"; role = 'start_packet' },
    @{ path = $erPath; rel = "./NEO_SESSION/$slug/SUBSESSION_END_REPORT.json"; role = 'end_report' },
    @{ path = $proofP; rel = "./NEO_SESSION/$slug/proof.ps1"; role = 'proof' }
  )
  $bundlePath = Join-Path $auditDir 'AUDIT_BUNDLE.json'
  $bundle = New-NeoAuditBundle -BundleId 'bundle-1' -MemberItems $members -ApprovedPaths @('./src/') `
    -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier 'low' -Timestamp $TS -Index $index -OutPath $bundlePath

  $arPath = Join-Path $auditDir 'AUDIT_RESULT.json'
  & $stub -BundlePath $bundlePath -BundleDir $e2e -OutPath $arPath -Timestamp $TS | Out-Null
  $consumed = Read-NeoAuditResult -AuditResultPath $arPath -Bundle $bundle -BundleDir $e2e -MasterIdentity 'm1' -BuilderIdentity 'builder-ss-001' -Index $index
  if ($consumed.recommendation -ne 'GO') { throw "expected GO, got $($consumed.recommendation)" }
  if ($consumed.engine_rehash_mismatches.Count -ne 0) { throw 'unexpected rehash mismatch' }
  return 'init+dispatch+ingest+assemble+consume all schema-valid; recommendation=GO'
}

# ============ PROMISED-TEST BINDING negatives (load-bearing GUARDS) ============
# The honest stub's GO must mean "every SUBSESSION_END_REPORT.tests_run entry re-bound to a
# runnable proof member AND re-ran exit 0". These two guards prove GO is NOT reachable when a
# promised test is uncovered or failing. Neutering the binding branch in orch_auditor_stub.ps1
# flips both to GO (see the fix's neuter-on-copy evidence). Fail-closed matching: proof_ref
# -ceq member.path (role='proof').
function Get-StubVerdict($slug, $proofBody, $promisedProofRef) {
  # $proofBody -eq $null -> OMIT the proof member (uncovered promise). Otherwise write a
  # runnable proof.ps1 with that body and include it as a role='proof' member.
  # $promisedProofRef optional: overrides ONLY the PROMISED tests_run.proof_ref while the
  # member keeps rel ./NEO_SESSION/<slug>/proof.ps1 (used by N4 to seed a case-only mismatch).
  $bdir = Join-Path $ScratchRoot ('bind_' + $slug)
  $sdir = Join-Path $bdir ('NEO_SESSION\' + $slug); New-Item -ItemType Directory -Force -Path $sdir | Out-Null
  $erPath = Join-Path $sdir 'SUBSESSION_END_REPORT.json'
  Write-NeoJsonFile $erPath (New-FixtureEndReport $slug $promisedProofRef)   # default proof_ref = ./NEO_SESSION/<slug>/proof.ps1
  $members = @(@{ path = $erPath; rel = "./NEO_SESSION/$slug/SUBSESSION_END_REPORT.json"; role = 'end_report' })
  if ($null -ne $proofBody) {
    $proofP = Join-Path $sdir 'proof.ps1'; Set-Content -LiteralPath $proofP -Value $proofBody -Encoding UTF8
    $members += @{ path = $proofP; rel = "./NEO_SESSION/$slug/proof.ps1"; role = 'proof' }
  }
  $auditDir = Join-Path $sdir 'audit'
  $bp = Join-Path $auditDir 'AUDIT_BUNDLE.json'
  New-NeoAuditBundle -BundleId ('bind-' + $slug) -MemberItems $members -ApprovedPaths @('./src/') `
    -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier 'low' -Timestamp $TS -Index $index -OutPath $bp | Out-Null
  $arPath = Join-Path $auditDir 'AUDIT_RESULT.json'
  & $stub -BundlePath $bp -BundleDir $bdir -OutPath $arPath -Timestamp $TS | Out-Null
  return (Read-NeoJsonFile $arPath).recommendation
}
$v1 = Get-StubVerdict 'ss-uncov' $null      # promise present, NO matching proof member
Record 'N1-promised-test-uncovered-NEEDS-MORE' ($v1 -eq 'NEEDS-MORE') ("uncovered promised test (no bound proof member) => derived $v1 (never GO)") 'negative'
$v2 = Get-StubVerdict 'ss-failp' 'exit 3'    # promise bound to a proof that re-runs non-zero
Record 'N2-promised-test-failing-NO-GO' ($v2 -eq 'NO-GO') ("bound promised test proof re-ran exit 3 => derived $v2 (never GO)") 'negative'

# N3: TWO intact role='end_report' members. Real report FIRST (promises failproof.ps1, exit 3);
# crafted report LAST (promises passproof.ps1, exit 0). All members hash-clean. Last-wins
# order-selection would enumerate ONLY the crafted report and derive GO -- the confirmed
# false-GO this fix closes. Multiplicity is unverifiable: the stub must refuse to pick either
# candidate => NEEDS-MORE (never GO). Neutering the multiplicity guard in orch_auditor_stub.ps1
# flips this to GO (see the fix's neuter-on-copy evidence).
$n3slug = 'ss-x'
$n3dir = Join-Path $ScratchRoot ('bind_' + $n3slug)
$n3s = Join-Path $n3dir ('NEO_SESSION\' + $n3slug); New-Item -ItemType Directory -Force -Path $n3s | Out-Null
$n3erA = Join-Path $n3s 'SUBSESSION_END_REPORT.json'
Write-NeoJsonFile $n3erA (New-FixtureEndReport $n3slug "./NEO_SESSION/$n3slug/failproof.ps1")
$n3erB = Join-Path $n3s 'SUBSESSION_END_REPORT_2.json'
Write-NeoJsonFile $n3erB (New-FixtureEndReport $n3slug "./NEO_SESSION/$n3slug/passproof.ps1")
$n3fp = Join-Path $n3s 'failproof.ps1'; Set-Content -LiteralPath $n3fp -Value 'exit 3' -Encoding UTF8
$n3pp = Join-Path $n3s 'passproof.ps1'; Set-Content -LiteralPath $n3pp -Value 'exit 0' -Encoding UTF8
$n3members = @(
  @{ path = $n3erA; rel = "./NEO_SESSION/$n3slug/SUBSESSION_END_REPORT.json";   role = 'end_report' },
  @{ path = $n3fp;  rel = "./NEO_SESSION/$n3slug/failproof.ps1";                role = 'proof' },
  @{ path = $n3pp;  rel = "./NEO_SESSION/$n3slug/passproof.ps1";                role = 'proof' },
  @{ path = $n3erB; rel = "./NEO_SESSION/$n3slug/SUBSESSION_END_REPORT_2.json"; role = 'end_report' }   # crafted, LAST
)
$n3bp = Join-Path (Join-Path $n3s 'audit') 'AUDIT_BUNDLE.json'
New-NeoAuditBundle -BundleId ('bind-' + $n3slug) -MemberItems $n3members -ApprovedPaths @('./src/') `
  -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier 'low' -Timestamp $TS -Index $index -OutPath $n3bp | Out-Null
$n3ar = Join-Path (Join-Path $n3s 'audit') 'AUDIT_RESULT.json'
& $stub -BundlePath $n3bp -BundleDir $n3dir -OutPath $n3ar -Timestamp $TS | Out-Null
$v3 = (Read-NeoJsonFile $n3ar).recommendation
Record 'N3-two-end_report-members-NEEDS-MORE' ($v3 -eq 'NEEDS-MORE') ("two intact end_report members (crafted last) => derived $v3 (never GO; no order-selection)") 'negative'

# N4: promised proof_ref differs from the runnable proof member's rel ONLY in case
# (PROOF.PS1 vs proof.ps1). The documented matching contract is -ceq (case-sensitive); a
# case-INSENSITIVE lookup would bind the promise to a differently-cased rel -- on a
# case-sensitive filesystem that is a DIFFERENT file (false GO). With ORDINAL lookup tables
# the case-only mismatch is simply UNCOVERED => NEEDS-MORE (never binds, never GO).
# Reverting the stub's hashtables to default (case-insensitive) flips this to GO.
$v4 = Get-StubVerdict 'ss-case' 'exit 0' './NEO_SESSION/ss-case/PROOF.PS1'
Record 'N4-proof_ref-case-mismatch-NEEDS-MORE' ($v4 -eq 'NEEDS-MORE') ("case-only proof_ref mismatch (PROOF.PS1 vs proof.ps1) => derived $v4 (uncovered, never bound)") 'negative'

# ---- summary + residue-clean ------------------------------------------------
# HONEST FRAMING: the load-bearing count is the NEGATIVE fail-closed guards. The
# POSITIVE/info checks (E2E happy run, known-class-resolves, numeric-equal control)
# confirm no regression but are NOT guards and are reported separately.
$neg = @($script:results | Where-Object { $_.kind -eq 'negative' })
$pos = @($script:results | Where-Object { $_.kind -eq 'positive' })
$negFail = @($neg | Where-Object { -not $_.pass }).Count
$posFail = @($pos | Where-Object { -not $_.pass }).Count
$fail = $negFail + $posFail
Write-Host ""
Write-Host ("NEGATIVE fail-closed GUARDS (load-bearing): {0}/{1} pass" -f ($neg.Count - $negFail), $neg.Count) -ForegroundColor $(if ($negFail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("POSITIVE / info checks (no-regression):     {0}/{1} pass" -f ($pos.Count - $posFail), $pos.Count) -ForegroundColor $(if ($posFail -eq 0) { 'Green' } else { 'Red' })
Write-Host ("RESULT: {0} pass / {1} fail (of {2})" -f ($script:results.Count - $fail), $fail, $script:results.Count) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

if ($ProofOut) {
  $report = [pscustomobject]@{
    suite = 'NEO-4.0-P3-B1-FIX'; timestamp = $TS
    negative_guards = $neg.Count; negative_pass = ($neg.Count - $negFail)
    positive_checks = $pos.Count; positive_pass = ($pos.Count - $posFail)
    fail = $fail; results = $script:results
  }
  ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ProofOut -Encoding UTF8
  Write-Host "proof written: $ProofOut"
}

$residueClean = $true
if (-not $KeepScratch) {
  Remove-Item -Recurse -Force -LiteralPath $ScratchRoot
  $residueClean = -not (Test-Path -LiteralPath $ScratchRoot)
  Write-Host ("residue-clean: {0} (scratch removed)" -f $residueClean)
}

if ($fail -eq 0 -and $residueClean) { exit 0 } else { exit 1 }
