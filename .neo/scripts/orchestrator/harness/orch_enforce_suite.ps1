# orch_enforce_suite.ps1 - NEO 4.0-P3-B2a INDEPENDENT enforcement harness (v4 5.7).
# ASCII-only (D10). Kept SEPARATE from the engine it tests.
#
# Proves E1 (tiered audit, D4), E2 (human-gate binding, D5), E3 (model-routing, D6) each
# FAIL CLOSED, and that each guard is LOAD-BEARING: neutering the single guard line on a
# COPY flips the fixture from BLOCK to fail-open (pass). Plus an extended serial E2E that
# runs a GATED + TIERED + ROUTED sub-session end-to-end to GO. Writes NO AUDIT_RESULT from
# the engine (the isolated-auditor stub is the only writer). Tests bind a FIXTURE-LOCAL
# ledger, NEVER .neo/gates/HUMAN_GATE_LEDGER.json.
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
$map = Get-NeoClassMap (Join-Path $schemaDir 'artifact_classes.json')
$stub = Join-Path $orchDir 'orch_auditor_stub.ps1'
$TS = '2026-07-03T00:00:00Z'

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_orch_b2a_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors the B1 suite framing) -------------------------
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
function Expect-Ok($name, $sb) {
  try { $r = & $sb; Record $name $true "$r" 'positive' }
  catch { Record $name $false ('unexpected block/error: ' + $_.Exception.Message) 'positive' }
}

# ---- NEUTER-ON-COPY: prove a guard is load-bearing --------------------------
# Copy the whole orchestrator .ps1 chain to a scratch dir, patch the ONE guard line on the
# copy, dot-source the neutered chain, re-run the SAME defect fixture, then RESTORE the real
# functions. Load-bearing iff the neutered version does NOT block (flips to fail-open).
function Expect-NeuterFlip($name, $file, $find, $replace, $fixture) {
  $neuterDir = Join-Path $ScratchRoot ('neuter_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $neuterDir | Out-Null
  Get-ChildItem -LiteralPath $orchDir -Filter *.ps1 -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $neuterDir $_.Name) -Force }
  $tgt = Join-Path $neuterDir $file
  $txt = Get-Content -LiteralPath $tgt -Raw
  if (-not $txt.Contains($find)) { Record $name $false "neuter target string not present in $file (fixture/guard drift)" 'negative'; return }
  $patched = $txt.Replace($find, $replace)
  if ($patched -ceq $txt) { Record $name $false "neuter replace was a no-op in $file" 'negative'; return }
  Set-Content -LiteralPath $tgt -Value $patched -Encoding UTF8 -NoNewline

  $blockedAfter = $true
  try {
    . (Join-Path $neuterDir 'orch_engine.ps1')     # load NEUTERED chain (functions redefined)
    try { & $fixture; $blockedAfter = $false } catch { $blockedAfter = $true }
  } finally {
    . "$orchDir\orch_engine.ps1"                    # RESTORE the real functions
  }
  # Load-bearing iff the neutered version flipped BLOCK -> pass.
  $verdict = if (-not $blockedAfter) { 'FAIL-OPEN (guard was load-bearing)' } else { 'still blocked (another guard caught it / not load-bearing)' }
  Record $name (-not $blockedAfter) ("neuter removed the guard => fixture " + $verdict) 'negative'
}

# ---- fixture builders -------------------------------------------------------
function Row($area, $rc, $nb, $tier, $downgrade) {
  $o = [ordered]@{ id = 'r1'; area = $area; risk_class = $rc; never_batchable = $nb; audit_tier = $tier }
  if ($null -ne $downgrade) { $o['explicit_downgrade'] = $downgrade }
  return [pscustomobject]$o
}
function RoutingEntry($pc, $vc, $rationale, $taskRisk = 'low') {
  return [pscustomobject]@{
    task_id = 't1'; task_risk = $taskRisk; producer_model = 'prod-model'; producer_class = $pc
    validator_model = 'val-model'; validator_class = $vc; validator_adequacy_rationale = $rationale
  }
}
function Write-FixtureLedger($path, $entries) {
  $led = [pscustomobject]@{
    human_gate_ledger_schema_id = 'neo:human_gate_ledger'
    root_of_trust               = 'provisional-dev'
    note                        = 'FIXTURE-LOCAL ledger for the B2a enforce suite. NEVER the live governed-gates ledger.'
    entries                     = @($entries)
  }
  Write-NeoJsonFile $path $led
  return $path
}
function New-Env($id, $class, $schemaId, $prole, $pclass, $vclass, $naReason) {
  $ea = @{
    ArtifactId = $id; ArtifactClass = $class; SchemaId = $schemaId; SchemaVersion = '4.0-P3-B'
    ProducerRole = $prole; ProducerClass = $pclass; ValidatorRole = $prole; ValidatorClass = $vclass
    Timestamp = $TS; DeclaredPaths = @('./program/'); DeclaredSurfaces = @('filesystem'); SourcePackets = @(); GateRef = $null
  }
  if ($naReason) { $ea['ValidatorNAReason'] = $naReason }
  return (New-NeoEnvelope @ea)
}
# A valid AUDIT_RESULT with a CHOSEN producer model_class (to exercise the E1 consume tier check).
function Write-AuditResult($path, $bundleDir, $bundle, $prodClass, $rec, $auditorId) {
  $mismatches = @()
  foreach ($m in @($bundle.allowlist)) {
    $rel = [string]$m.path
    $mp = Assert-NeoContained $bundleDir $rel
    if ((Get-NeoSha256File $mp) -cne ([string]$m.content_hash)) { $mismatches += $rel }
  }
  $env = New-Env 'ar-fx' 'evidence' 'neo:audit_result' 'isolated-auditor' $prodClass $prodClass $null
  $r = [pscustomobject]@{
    result_id        = 'ar-fx'
    recommendation   = $rec
    findings         = @()
    rehash_check     = @{ all_members_matched = ($mismatches.Count -eq 0); mismatches = @($mismatches) }
    auditor_identity = $auditorId
    _provenance      = $env
  }
  Set-NeoArtifactHash $r
  Assert-NeoValid $r 'neo:audit_result' $index 'AUDIT_RESULT(fixture)'
  Write-NeoJsonFile $path $r
  return $path
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

Write-Host "NEO 4.0-P3-B2a enforce suite (E1 tier / E2 gate / E3 routing)" -ForegroundColor Cyan
Write-Host "scratch: $ScratchRoot"

# paths that resolve through the class oracle (default_class NOT consumed):
$P_IMPL    = './app/new_session.ps1'        # implementation (explicit impl glob)
$P_JUDGE   = './x/rubric.schema.json'       # constraint (judging: *.schema.json)
$P_UNKNOWN = './program/PROJECT_SPEC.json'  # UNKNOWN (matches no glob) => BLOCK

# ============================ E1 TIERED AUDIT ================================
# E1a: MEDIUM + audit_tier=lightweight + explicit_downgrade=null => BLOCK (+neuter-flip)
Expect-Block 'E1a-medium-lightweight-no-downgrade' { Resolve-NeoAuditTier -RiskRow (Row 'general_feature' 'medium' $false 'lightweight' $null) | Out-Null }
Expect-NeuterFlip 'E1a-neuter-flip' 'orch_enforce.ps1' 'if (-not (Test-NeoDowngradeComplete $dg))' 'if ($false)' `
  { Resolve-NeoAuditTier -RiskRow (Row 'general_feature' 'medium' $false 'lightweight' $null) | Out-Null }
# E1b positive controls: complete downgrade -> lightweight; medium default -> isolated; high -> isolated; low -> lightweight; release -> full_isolated
$dgOk = [pscustomobject]@{ reason = 'perf spike, low blast radius'; authority = 'Raphael'; timestamp = '2026-07-03'; scope = './app/x' }
Expect-Ok 'E1-medium-lightweight-with-downgrade' { $t = Resolve-NeoAuditTier -RiskRow (Row 'general_feature' 'medium' $false 'lightweight' $dgOk); if ($t -ne 'lightweight') { throw "got $t" }; "tier=$t" }
Expect-Ok 'E1-medium-default-isolated' { $t = Resolve-NeoAuditTier -RiskRow (Row 'general_feature' 'medium' $false 'isolated' $null); if ($t -ne 'isolated') { throw "got $t" }; "tier=$t" }
Expect-Ok 'E1-low-lightweight'         { $t = Resolve-NeoAuditTier -RiskRow (Row 'general_feature' 'low' $false 'lightweight' $null); if ($t -ne 'lightweight') { throw "got $t" }; "tier=$t" }
Expect-Ok 'E1-release-full_isolated'   { $t = Resolve-NeoAuditTier -RiskRow (Row 'general_feature' 'low' $false 'lightweight' $null) -IsDevProdRelease; if ($t -ne 'full_isolated') { throw "got $t" }; "tier=$t" }
# high with a lightweight row => BLOCK (high is never lightweight)
Expect-Block 'E1-high-lightweight-row-blocked' { Resolve-NeoAuditTier -RiskRow (Row 'security' 'high' $true 'lightweight' $null) | Out-Null }
# missing risk_class => BLOCK
Expect-Block 'E1-missing-risk_class' { Resolve-NeoAuditTier -RiskRow (Row 'general_feature' '' $false 'isolated' $null) | Out-Null }

# E1c CONSUME: isolated tier requires an auditor-class AUDIT_RESULT (+neuter-flip on W3)
$e1c = Join-Path $ScratchRoot 'e1c'; $mbE1c = Build-MiniBundle $e1c 'high'
$arValidator = Write-AuditResult (Join-Path $e1c 'AR_validator.json') $mbE1c.dir $mbE1c.bundle 'validator' 'GO' 'isolated-auditor-x'
Expect-Block 'E1c-isolated-tier-nonauditor-result' {
  Read-NeoAuditResult -AuditResultPath $arValidator -Bundle $mbE1c.bundle -BundleDir $mbE1c.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index -RequiredTier 'isolated' | Out-Null
}
Expect-NeuterFlip 'E1c-neuter-flip' 'orch_engine.ps1' "if (`$prodClass -cne 'auditor')" 'if ($false)' {
  Read-NeoAuditResult -AuditResultPath $arValidator -Bundle $mbE1c.bundle -BundleDir $mbE1c.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index -RequiredTier 'isolated' | Out-Null
}
# positive: an auditor-class result satisfies the isolated tier
$arAuditor = Write-AuditResult (Join-Path $e1c 'AR_auditor.json') $mbE1c.dir $mbE1c.bundle 'auditor' 'GO' 'isolated-auditor-x'
Expect-Ok 'E1c-isolated-tier-auditor-ok' {
  $c = Read-NeoAuditResult -AuditResultPath $arAuditor -Bundle $mbE1c.bundle -BundleDir $mbE1c.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index -RequiredTier 'isolated'
  if ($c.recommendation -ne 'GO') { throw "got $($c.recommendation)" }; 'auditor-class result accepted for isolated tier'
}

# ---- B2a-FIX F3: a non-empty unknown -RequiredTier must BLOCK (case-exact), never silently
# skip the auditor mandate. N4 load-bearing: neuter the tier-vocabulary guard => 'isolate'
# slips past block (0) and the (auditor-class) result is consumed => FAIL-OPEN.
Expect-Block 'W3-unknown-tier' { Read-NeoAuditResult -AuditResultPath $arAuditor -Bundle $mbE1c.bundle -BundleDir $mbE1c.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index -RequiredTier 'isolate' | Out-Null }
Expect-NeuterFlip 'W3-unknown-tier-neuter-flip' 'orch_engine.ps1' "if (`$RequiredTier -and (@('lightweight', 'isolated', 'full_isolated') -cnotcontains `$RequiredTier))" 'if ($false)' `
  { Read-NeoAuditResult -AuditResultPath $arAuditor -Bundle $mbE1c.bundle -BundleDir $mbE1c.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index -RequiredTier 'isolate' | Out-Null }
# W3 positive controls: lightweight/empty tier legitimately skip the auditor requirement.
Expect-Ok 'W3-lightweight-tier-skips-auditor' { $c = Read-NeoAuditResult -AuditResultPath $arValidator -Bundle $mbE1c.bundle -BundleDir $mbE1c.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index -RequiredTier 'lightweight'; if ($c.recommendation -ne 'GO') { throw "got $($c.recommendation)" }; 'lightweight: validator-class result accepted' }
Expect-Ok 'W3-empty-tier-skips-auditor' { $c = Read-NeoAuditResult -AuditResultPath $arValidator -Bundle $mbE1c.bundle -BundleDir $mbE1c.dir -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index; if ($c.recommendation -ne 'GO') { throw "got $($c.recommendation)" }; 'empty tier: validator-class result accepted' }

# ============================ E2 HUMAN-GATE BINDING =========================
$ledPath = Write-FixtureLedger (Join-Path $ScratchRoot 'HGL_fixture.json') @(
  [pscustomobject]@{ gate_ref = '2026-07-03-B2A-SEC-START'; gate_kind = 'human_start_approval'; authorized_by = 'Raphael'; recorded_at = '2026-07-03'; app_slug = 'demo-app'; authorized_paths = @('./app/') }
)
$led = Read-NeoGateLedger $ledPath
$secRow = Row 'security' 'high' $true 'isolated' $null
$genRow = Row 'general_feature' 'low' $false 'lightweight' $null

# E2-unmatched (covers missing): sensitive area, gate_ref not in ledger => BLOCK (+neuter-flip)
Expect-Block 'E2-unmatched-gate_ref' { Assert-NeoGateBound -RiskRow $secRow -GateRef 'ghost-gate' -Ledger $led | Out-Null }
Expect-NeuterFlip 'E2-unmatched-neuter-flip' 'orch_enforce.ps1' 'if ($null -eq $match) { New-NeoBlock "gate-binding: gate_ref' 'if ($false) { New-NeoBlock "gate-binding: gate_ref' `
  { Assert-NeoGateBound -RiskRow $secRow -GateRef 'ghost-gate' -Ledger $led | Out-Null }
# E2-missing gate_ref (empty) also blocks via the same barrier
Expect-Block 'E2-missing-gate_ref' { Assert-NeoGateBound -RiskRow $secRow -GateRef '' -Ledger $led | Out-Null }

# E2-batched-sensitive: sensitive area presented as batched => BLOCK (+neuter-flip; valid gate so it flips)
Expect-Block 'E2-sensitive-batched' { Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./app/new_session.ps1') -Batched | Out-Null }
Expect-NeuterFlip 'E2-batched-neuter-flip' 'orch_enforce.ps1' 'if ($Batched) { New-NeoBlock "gate-binding: sensitive area' 'if ($false) { New-NeoBlock "gate-binding: sensitive area' `
  { Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./app/new_session.ps1') -Batched | Out-Null }

# E2-unmatched-scope: gate found but authorized_paths do not cover the scope => BLOCK (+neuter-flip)
Expect-Block 'E2-unmatched-scope' { Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./other/secret.txt') | Out-Null }
Expect-NeuterFlip 'E2-scope-neuter-flip' 'orch_enforce.ps1' 'if (-not $covered) { New-NeoBlock "gate-binding: scope path' 'if ($false) { New-NeoBlock "gate-binding: scope path' `
  { Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./other/secret.txt') | Out-Null }

# E2-expired: gate found + covered but recorded_at + MaxAgeDays < AsOf => BLOCK (+neuter-flip)
Expect-Block 'E2-expired-gate' { Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./app/x') -AsOf '2026-08-01' -MaxAgeDays 7 | Out-Null }
Expect-NeuterFlip 'E2-expired-neuter-flip' 'orch_enforce.ps1' 'if ($recDate.AddDays($MaxAgeDays) -lt $asOfDate)' 'if ($false)' `
  { Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./app/x') -AsOf '2026-08-01' -MaxAgeDays 7 | Out-Null }

# E2 positives: valid sensitive gate binds; general_feature may be batched; general_feature with neither => BLOCK
Expect-Ok 'E2-sensitive-valid-gate-binds' { $g = Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./app/new_session.ps1'); if ($null -eq $g) { throw 'expected a bound gate' }; 'gate bound' }
Expect-Ok 'E2-general_feature-batched-ok' { $g = Assert-NeoGateBound -RiskRow $genRow -Batched; 'batched+logged allowed' }
Expect-Block 'E2-general_feature-neither-declared' { Assert-NeoGateBound -RiskRow $genRow | Out-Null }

# ---- B2a-FIX F1: sensitivity is fail-closed (only 'general_feature' is batchable-eligible) ----
# N1 E2-unknown-area-batched: an UNKNOWN area with never_batchable=false must NOT default open.
Expect-Block 'E2-unknown-area-batched' { Assert-NeoGateBound -RiskRow (Row 'totally_unknown' 'low' $false 'lightweight' $null) -Batched | Out-Null }
Expect-NeuterFlip 'E2-unknown-area-neuter-flip' 'orch_enforce.ps1' "(`$area -cne 'general_feature')" '($false)' `
  { Assert-NeoGateBound -RiskRow (Row 'totally_unknown' 'low' $false 'lightweight' $null) -Batched | Out-Null }
# N2 E2-blank-area: a blank/missing area cannot be classified => BLOCK (neuter flips to a valid bind).
Expect-Block 'E2-blank-area' { Assert-NeoGateBound -RiskRow (Row '' 'low' $false 'lightweight' $null) -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./app/x') | Out-Null }
Expect-NeuterFlip 'E2-blank-area-neuter-flip' 'orch_enforce.ps1' 'if ([string]::IsNullOrWhiteSpace($area))' 'if ($false)' `
  { Assert-NeoGateBound -RiskRow (Row '' 'low' $false 'lightweight' $null) -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @('./app/x') | Out-Null }

# ---- B2a-FIX F2: a bound gate must authorize a NON-EMPTY declared scope ----
# N3 E2-sensitive-empty-scope: valid gate but EMPTY ScopePaths => BLOCK (neuter flips: coverage no-ops -> binds).
Expect-Block 'E2-sensitive-empty-scope' { Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @() | Out-Null }
Expect-NeuterFlip 'E2-empty-scope-neuter-flip' 'orch_enforce.ps1' 'if (($null -ne $match) -and ($scopes.Count -eq 0))' 'if ($false)' `
  { Assert-NeoGateBound -RiskRow $secRow -GateRef '2026-07-03-B2A-SEC-START' -Ledger $led -AppSlug 'demo-app' -ScopePaths @() | Out-Null }

# ============================ E3 MODEL-ROUTING ==============================
# E3a: cheap-producer edits judging-class => BLOCK (+neuter-flip)
Expect-Block 'E3a-cheap-edits-judging' { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_JUDGE -ProducerClass 'cheap_producer' -TaskRisk 'low' -RoutingEntry (RoutingEntry 'cheap_producer' 'auditor' 'auditor reviews the rubric') | Out-Null }
Expect-NeuterFlip 'E3a-neuter-flip' 'orch_enforce.ps1' "if (`$judging -and (`$ProducerClass -eq 'cheap_producer')) {" 'if ($false) {' `
  { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_JUDGE -ProducerClass 'cheap_producer' -TaskRisk 'low' -RoutingEntry (RoutingEntry 'cheap_producer' 'auditor' 'auditor reviews the rubric') | Out-Null }

# E3b: unknown class => BLOCK (+neuter-flip on the class oracle)
Expect-Block 'E3b-unknown-class' { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_UNKNOWN -ProducerClass 'strong_producer' -TaskRisk 'low' -RoutingEntry (RoutingEntry 'strong_producer' 'auditor' 'strong+auditor') | Out-Null }
Expect-NeuterFlip 'E3b-neuter-flip' 'orch_class.ps1' "if (`$c -eq 'UNKNOWN') {" 'if ($false) {' `
  { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_UNKNOWN -ProducerClass 'strong_producer' -TaskRisk 'low' -RoutingEntry (RoutingEntry 'strong_producer' 'auditor' 'strong+auditor') | Out-Null }

# E3c: empty validator_adequacy_rationale => BLOCK (+neuter-flip)
Expect-Block 'E3c-empty-rationale' { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_IMPL -ProducerClass 'strong_producer' -TaskRisk 'low' -RoutingEntry (RoutingEntry 'strong_producer' 'auditor' '') | Out-Null }
Expect-NeuterFlip 'E3c-neuter-flip' 'orch_enforce.ps1' 'if ([string]::IsNullOrWhiteSpace($rationale))' 'if ($false)' `
  { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_IMPL -ProducerClass 'strong_producer' -TaskRisk 'low' -RoutingEntry (RoutingEntry 'strong_producer' 'auditor' '') | Out-Null }

# E3d: validator < producer capability => BLOCK (strong producer + plain validator) (+neuter-flip)
Expect-Block 'E3d-validator-lt-producer' { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_IMPL -ProducerClass 'strong_producer' -TaskRisk 'medium' -RoutingEntry (RoutingEntry 'strong_producer' 'validator' 'plain validator' 'medium') | Out-Null }
Expect-NeuterFlip 'E3d-neuter-flip' 'orch_enforce.ps1' 'if ($vr -lt $pr)' 'if ($false)' `
  { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_IMPL -ProducerClass 'strong_producer' -TaskRisk 'medium' -RoutingEntry (RoutingEntry 'strong_producer' 'validator' 'plain validator' 'medium') | Out-Null }

# E3e: cheap-producer on non-low task_risk => BLOCK (+neuter-flip)
Expect-Block 'E3e-cheap-nonlow-risk' { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_IMPL -ProducerClass 'cheap_producer' -TaskRisk 'high' -RoutingEntry (RoutingEntry 'cheap_producer' 'validator' 'cheap validated' 'high') | Out-Null }
Expect-NeuterFlip 'E3e-neuter-flip' 'orch_enforce.ps1' "if ((`$ProducerClass -eq 'cheap_producer') -and (`$TaskRisk -ne 'low')) {" 'if ($false) {' `
  { Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_IMPL -ProducerClass 'cheap_producer' -TaskRisk 'high' -RoutingEntry (RoutingEntry 'cheap_producer' 'validator' 'cheap validated' 'high') | Out-Null }

# E3 positive: cheap + low + implementation + validator => allowed
Expect-Ok 'E3-cheap-low-impl-ok' { $r = Assert-NeoRouteEdit -ClassMap $map -TargetPath $P_IMPL -ProducerClass 'cheap_producer' -TaskRisk 'low' -RoutingEntry (RoutingEntry 'cheap_producer' 'validator' 'validator adequate for low-risk impl'); if ($r.class -ne 'implementation') { throw "class=$($r.class)" }; "class=$($r.class)" }

# ============================ STRUCTURAL (coordinate-not-validate) ==========
# G3c/G3d extended to orch_enforce.ps1: no auditor-stub reference; no AUDIT_RESULT rehash_check literal.
$enfCode = @(Get-Content -LiteralPath (Join-Path $orchDir 'orch_enforce.ps1') | Where-Object { $_ -notmatch '^\s*#' })
Record 'S1-enforce-no-auditor_stub-ref' (-not (($enfCode -join "`n") -match 'auditor_stub')) 'orch_enforce.ps1 has no auditor-stub code reference'
Record 'S1-enforce-no-rehash_check-literal' (-not ((Get-Content -Raw -LiteralPath (Join-Path $orchDir 'orch_enforce.ps1')) -match 'rehash_check\s*=')) 'orch_enforce.ps1 writes no AUDIT_RESULT rehash_check literal'
# This suite binds a FIXTURE-LOCAL ledger, never the live one. Detect an ACTUAL live-ledger
# path in CODE (not comments). The search token is assembled at runtime so the literal
# '.neo/gates' string never appears on a code line here (which would self-match). All fixture
# ledgers live under scratch, so a genuine .neo/gates reference is the only positive signal.
$suiteCode = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'orch_enforce_suite.ps1') | Where-Object { $_ -notmatch '^\s*#' })
$gatesTok = [regex]::Escape('.neo') + '[\\/]+' + ('ga' + 'tes')
$liveBind = $false
foreach ($l in $suiteCode) { if ($l -match $gatesTok) { $liveBind = $true } }
Record 'S2-suite-never-binds-live-ledger' (-not $liveBind) 'no code line references the live governed-gates ledger path (all ledgers are fixture-local under scratch)'

# ============================ EXTENDED E2E (gated + tiered + routed -> GO) ===
Expect-Ok 'E2E-gated-tiered-routed-GO' {
  $e2e = Join-Path $ScratchRoot 'e2e'
  $prog = Join-Path $e2e 'program'
  New-Item -ItemType Directory -Force -Path $prog | Out-Null

  # minimal valid program inputs (spec/constraint/arch/risk), risk register carries the security-high row
  $spec = [pscustomobject][ordered]@{ spec_id = 'spec-1'; spec_version = '1.0'; intent = 'demo app'; in_scope = @('feat'); out_of_scope = @('none'); acceptance_criteria = @(@{ id = 'AC1'; statement = 'does X'; verifiable_by = 'harness:x' }) }
  $spec | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'spec-1' 'evidence' 'neo:project_spec' 'spec-author' 'strong_producer' 'strong_producer' $null); Set-NeoArtifactHash $spec
  $con = [pscustomobject][ordered]@{ package_id = 'cp-1'; package_version = '1.0'; constraints = @(@{ id = 'C1'; statement = 'must X'; kind = 'functional'; severity = 'high' }); test_harness_ref = @{ artifact_id = 'th'; content_hash = 'h' }; profile_risk_ref = @{ artifact_id = 'pr'; content_hash = 'h' } }
  $con | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'cp-1' 'constraint' 'neo:constraint_package' 'constraint-editor' 'strong_producer' 'strong_producer' $null); Set-NeoArtifactHash $con
  $arch = [pscustomobject][ordered]@{ architecture_id = 'a1'; architecture_version = '1.0'; components = @(@{ id = 'c1'; responsibility = 'core'; owns_paths = @('./app/') }); interfaces = @(@{ id = 'i1'; between = @('c1', 'c2'); contract = 'x' }); disjoint_scope_map = @(@{ group = 'g'; paths = @('./app/'); proven_disjoint = $false }) }
  $arch | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'a1' 'evidence' 'neo:architecture' 'architect' 'strong_producer' 'strong_producer' $null); Set-NeoArtifactHash $arch
  $risk = [pscustomobject][ordered]@{ register_id = 'rr-1'; register_version = '1.0'; risks = @(
      @{ id = 'r-sec'; area = 'security'; risk_class = 'high'; never_batchable = $true; audit_tier = 'isolated' },
      @{ id = 'r-gen'; area = 'general_feature'; risk_class = 'low'; never_batchable = $false; audit_tier = 'lightweight' }
    ) }
  $risk | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env 'rr-1' 'profile_risk' 'neo:risk_register' 'risk-author' 'strong_producer' 'strong_producer' $null); Set-NeoArtifactHash $risk
  Write-NeoJsonFile (Get-NeoProgramPath $prog 'PROJECT_SPEC') $spec
  Write-NeoJsonFile (Get-NeoProgramPath $prog 'CONSTRAINT_PACKAGE') $con
  Write-NeoJsonFile (Get-NeoProgramPath $prog 'ARCHITECTURE') $arch
  Write-NeoJsonFile (Get-NeoProgramPath $prog 'RISK_REGISTER') $risk

  $init = Invoke-NeoInit -ProgramRoot $prog -Index $index -MasterId 'm1' -SessionId 's1' -Timestamp $TS -SnapshotDir (Join-Path $e2e 'snapshots')

  # the sub-session is the SECURITY/HIGH row: explicit gate + isolated tier + routed impl edit
  $secReg = ($risk.risks | Where-Object { $_.id -eq 'r-sec' })
  $secRow2 = [pscustomobject]$secReg
  $ledE2E = Read-NeoGateLedger (Write-FixtureLedger (Join-Path $e2e 'HGL.json') @(
      [pscustomobject]@{ gate_ref = '2026-07-03-B2A-SEC-START'; gate_kind = 'human_start_approval'; authorized_by = 'Raphael'; recorded_at = '2026-07-03'; app_slug = 'demo-app'; authorized_paths = @('./app/') }
    ))
  $edits = @(@{ path = './app/new_session.ps1'; producer_class = 'strong_producer'; task_risk = 'high'; routing_entry = (RoutingEntry 'strong_producer' 'auditor' 'auditor validates a high-risk security edit' 'high') })

  $slug = 'ss-sec-001'; $slugDir = Join-Path $e2e ('NEO_SESSION\' + $slug)
  New-Item -ItemType Directory -Force -Path $slugDir | Out-Null
  $specP = Get-NeoProgramPath $prog 'PROJECT_SPEC'; $conP = Get-NeoProgramPath $prog 'CONSTRAINT_PACKAGE'; $riskP = Get-NeoProgramPath $prog 'RISK_REGISTER'
  $allow = @(@{ path = $specP; rel = './program/PROJECT_SPEC.json'; role = 'project_spec' })

  $disp = Invoke-NeoGovernedDispatch -RiskRow $secRow2 -ClassMap $map -Ledger $ledE2E `
    -GateRef '2026-07-03-B2A-SEC-START' -AppSlug 'demo-app' -ScopePaths @('./app/new_session.ps1') -ProposedEdits $edits `
    -PacketId 'pkt-sec-1' -Goal 'harden auth' -TestPlan @('run tests') -StopConditions @('scope_breach') `
    -RiskClass 'high' -AllowlistItems $allow -ApprovedPaths @('./app/') -ProtectedPaths @('./.neo/') `
    -Surfaces @('filesystem') -ReferencedArtifacts @((Get-NeoArtifactRef $init.master_checkpoint)) -Timestamp $TS -Index $index
  if ($disp.audit_tier -ne 'isolated') { throw "tier=$($disp.audit_tier) (expected isolated)" }
  $spPath = Join-Path $slugDir 'SUBSESSION_START_PACKET.json'; Write-NeoJsonFile $spPath $disp.start_packet

  # END report + proof
  $er = [pscustomobject][ordered]@{
    report_id = "er-$slug"; slug = $slug
    changed_files = @(@{ path = './app/new_session.ps1'; sha256_after = ('0' * 64); change_kind = 'edit' })
    diff_manifest = @(@{ path = './app/new_session.ps1'; diff_ref = './diffs/x.patch' })
    tests_run = @(@{ command = 'run tests'; exit_code = 0; proof_ref = "./NEO_SESSION/$slug/proof.ps1" })
    skipped_or_unverified = @(); deferrals = @()
    rollback_notes = @{ snapshot_ref = './snapshots/pre'; touched_files = @('./app/new_session.ps1'); dependency_changes = @(); migration_status = 'none'; cleanup_status = 'clean' }
    touched_flags = @{ touched_constraints = $false; touched_tests_harness = $false; touched_profile_risk = $false }
    auditor_recommendation_slot = $null
  }
  $er | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env "er-$slug" 'evidence' 'neo:subsession_end_report' 'builder' 'strong_producer' 'strong_producer' 'raw builder evidence pre-audit'); Set-NeoArtifactHash $er
  $erPath = Join-Path $slugDir 'SUBSESSION_END_REPORT.json'; Write-NeoJsonFile $erPath $er
  Read-NeoEndReport $erPath $index | Out-Null

  # a RUNNABLE proof (exit 0) so the cold auditor's NON-CACHED re-run genuinely verifies it.
  $proofP = Join-Path $slugDir 'proof.ps1'; Set-Content -LiteralPath $proofP -Value 'exit 0' -Encoding UTF8
  $auditDir = Join-Path $slugDir 'audit'
  $members = @(
    @{ path = $specP; rel = './program/PROJECT_SPEC.json'; role = 'spec' },
    @{ path = $spPath; rel = "./NEO_SESSION/$slug/SUBSESSION_START_PACKET.json"; role = 'start_packet' },
    @{ path = $erPath; rel = "./NEO_SESSION/$slug/SUBSESSION_END_REPORT.json"; role = 'end_report' },
    @{ path = $proofP; rel = "./NEO_SESSION/$slug/proof.ps1"; role = 'proof' }
  )
  $bundlePath = Join-Path $auditDir 'AUDIT_BUNDLE.json'
  $bundle = New-NeoAuditBundle -BundleId 'bundle-sec-1' -MemberItems $members -ApprovedPaths @('./app/') -ProtectedPaths @('./.neo/') -Surfaces @('filesystem') -RiskTier 'high' -Timestamp $TS -Index $index -OutPath $bundlePath

  # isolated auditor (separate stub) DERIVES + writes the AUDIT_RESULT (auditor-class); engine consumes with the selected tier
  $arPath = Join-Path $auditDir 'AUDIT_RESULT.json'
  & $stub -BundlePath $bundlePath -BundleDir $e2e -OutPath $arPath -Timestamp $TS -AuditorIdentity 'isolated-auditor-cold' | Out-Null
  $consumed = Read-NeoAuditResult -AuditResultPath $arPath -Bundle $bundle -BundleDir $e2e -MasterIdentity 'm1' -BuilderIdentity ('builder-' + $slug) -Index $index -RequiredTier $disp.audit_tier
  if ($consumed.recommendation -ne 'GO') { throw "expected GO, got $($consumed.recommendation)" }

  # record the sub-session in the index carrying the applied tier (coordination; no E4 logic)
  $rec = [pscustomobject][ordered]@{
    slug = $slug
    start_packet_ref = @{ packet_id = 'pkt-sec-1'; content_hash = (Get-NeoProp (Get-NeoProp $disp.start_packet.input_packet '_provenance') 'content_hash').value }
    risk_class = 'high'; status = 'ended_pass'
    end_report_ref = @{ artifact_id = "er-$slug"; content_hash = (Get-NeoProp (Get-NeoProp $er '_provenance') 'content_hash').value }
    audit_tier_applied = $disp.audit_tier
    last_green = @{ proof_ref = "./NEO_SESSION/$slug/proof.ps1"; content_hash = (Get-NeoSha256File $proofP); summary = 'gated+tiered+routed slice green' }
    depends_on = @()
  }
  $si = $init.subsession_index
  Add-NeoIndexRecord -SubIndex $si -Record $rec -Index $index -Timestamp $TS | Out-Null

  return "gated(sec)->routed(impl,strong+auditor)->tier=isolated->consume GO; index records audit_tier_applied=$($disp.audit_tier)"
}

# ============================ E6 AUDITOR-SLOT SEAM (slice-2) =================
# Fixture worlds for Assert-NeoAuditorSlotSatisfied. Each world is a fresh sandbox root with a
# builder END (slot null), a runnable proof, an IMMUTABLE audit-time END copy that the bundle
# freezes, an AUDIT_BUNDLE + a verdict artifact (honest DERIVING stub by default; the suite's
# chosen-content fixture writer for forged cases), and a live END whose slot is then filled
# OUTSIDE the engine (the suite acting as the master/coordinator). The seam itself only READS.
$rowHighE6 = Row 'security' 'high' $true 'isolated' $null
$rowLowE6  = Row 'general_feature' 'low' $false 'lightweight' $null

function New-SlotEnd([string]$slug, $slotVal) {
  $er = [pscustomobject][ordered]@{
    report_id = "er-$slug"; slug = $slug
    changed_files = @(@{ path = './app/new_session.ps1'; sha256_after = ('0' * 64); change_kind = 'edit' })
    diff_manifest = @(@{ path = './app/new_session.ps1'; diff_ref = './diffs/x.patch' })
    tests_run = @(@{ command = 'run tests'; exit_code = 0; proof_ref = "./NEO_SESSION/$slug/proof.ps1" })
    skipped_or_unverified = @(); deferrals = @()
    rollback_notes = @{ snapshot_ref = './snapshots/pre'; touched_files = @('./app/new_session.ps1'); dependency_changes = @(); migration_status = 'none'; cleanup_status = 'clean' }
    touched_flags = @{ touched_constraints = $false; touched_tests_harness = $false; touched_profile_risk = $false }
    auditor_recommendation_slot = $slotVal
  }
  $er | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-Env "er-$slug" 'evidence' 'neo:subsession_end_report' 'builder' 'strong_producer' 'strong_producer' 'raw builder evidence pre-audit')
  Set-NeoArtifactHash $er
  return $er
}
# Fill the LIVE END's slot on disk OUTSIDE the engine, then re-ingest through the engine reader.
function Set-SlotOnDisk([string]$erPath, [string]$slug, $slotVal) {
  Write-NeoJsonFile $erPath (New-SlotEnd $slug $slotVal)
  return (Read-NeoEndReport $erPath $index)
}
function Build-SlotWorld {
  param([string]$Name,
        [string]$FixtureRec = '',            # '' => the honest DERIVING stub writes the verdict
        [string]$FixtureAuditor = 'isolated-auditor-cold',
        [string]$SlotRec = 'GO', [string]$SlotAuditor = 'isolated-auditor-cold',
        [switch]$DecoyMiscasedEnd, [switch]$LoneMiscasedEnd, [switch]$ForeignEndInBundle,
        [switch]$LeaveSlotNull)
  $root = Join-Path $ScratchRoot $Name
  $slug = 'ss-slot'
  $slugDir = Join-Path $root "NEO_SESSION\$slug"
  $auditDir = Join-Path $slugDir 'audit'
  New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
  $erPath = Join-Path $slugDir 'SUBSESSION_END_REPORT.json'
  Write-NeoJsonFile $erPath (New-SlotEnd $slug $null)
  $proofP = Join-Path $slugDir 'proof.ps1'; Set-Content -LiteralPath $proofP -Value 'exit 0' -Encoding UTF8
  # immutable audit-time END copy: the bundle freezes THIS; the live END gets the slot later.
  $endAudited = Join-Path $auditDir 'END_audited.json'
  Copy-Item -LiteralPath $erPath -Destination $endAudited -Force
  $endRel = "./NEO_SESSION/$slug/audit/END_audited.json"
  if ($ForeignEndInBundle) { Write-NeoJsonFile $endAudited (New-SlotEnd 'ss-foreign' $null) }   # a FOREIGN subsession's END frozen instead
  $members = @()
  if ($LoneMiscasedEnd) { $members += @{ path = $endAudited; rel = $endRel; role = 'End_Report' } }
  else { $members += @{ path = $endAudited; rel = $endRel; role = 'end_report' } }
  if ($DecoyMiscasedEnd) {
    $decoy = Join-Path $auditDir 'END_decoy.json'; Copy-Item -LiteralPath $endAudited -Destination $decoy -Force
    $members += @{ path = $decoy; rel = "./NEO_SESSION/$slug/audit/END_decoy.json"; role = 'End_Report' }
  }
  $members += @{ path = $proofP; rel = "./NEO_SESSION/$slug/proof.ps1"; role = 'proof' }
  $bundlePath = Join-Path $auditDir 'AUDIT_BUNDLE.json'
  $bundle = New-NeoAuditBundle -BundleId "b-$($Name -replace '[\\/]', '-')" -MemberItems $members -ApprovedPaths @('./app/') -ProtectedPaths @('./.neo/') `
    -Surfaces @('filesystem') -RiskTier 'high' -Timestamp $TS -Index $index -OutPath $bundlePath
  $arPath = Join-Path $auditDir 'AUDIT_RESULT.json'
  if ($FixtureRec) { Write-AuditResult $arPath $root $bundle 'auditor' $FixtureRec $FixtureAuditor | Out-Null }
  else { & $stub -BundlePath $bundlePath -BundleDir $root -OutPath $arPath -Timestamp $TS -AuditorIdentity $FixtureAuditor | Out-Null }
  $bundleRel = "./NEO_SESSION/$slug/audit/AUDIT_BUNDLE.json"
  $endLive = $null
  if ($LeaveSlotNull) { $endLive = Read-NeoEndReport $erPath $index }
  else { $endLive = Set-SlotOnDisk $erPath $slug (@{ recommendation = $SlotRec; auditor_identity = $SlotAuditor; bundle_ref = $bundleRel }) }
  return @{ root = $root; slug = $slug; erPath = $erPath; endLive = $endLive; bundleRel = $bundleRel; arPath = $arPath; auditDir = $auditDir; bundlePath = $bundlePath }
}
function Invoke-Seam($w, $row) {
  Assert-NeoAuditorSlotSatisfied -RiskRow $row -EndReport $w.endLive -SessionRoot $w.root -MasterIdentity 'm1' -BuilderIdentity 'b1' -Index $index
}

# --- happy world (honest deriving stub => GO), shared by the positives + inline-slot negatives
$wHappy = Build-SlotWorld 'e6_happy'
Expect-Ok 'E6-P1-high-valid-bound-slot-passes' {
  $r = Invoke-Seam $wHappy $rowHighE6
  if (-not $r.satisfied) { throw 'not satisfied' }
  if (-not $r.required) { throw 'expected required=true for high/isolated' }
  if ($r.recommendation -cne 'GO') { throw "got $($r.recommendation)" }
  'high-risk slot present, bound, contained, re-validated, matching => passes (verdict GO returned)'
}
Expect-Ok 'E6-P3-low-present-valid-slot-validates' {
  $r = Invoke-Seam $wHappy $rowLowE6
  if (-not $r.satisfied) { throw 'not satisfied' }
  if ($r.required) { throw 'expected required=false for low/lightweight' }
  'a PRESENT slot is fully validated even when the tier does not require one'
}

# --- S1: high risk + null slot => cannot pass (the D4 prose, now engine-enforced)
$wNull = Build-SlotWorld 'e6_null' -LeaveSlotNull
Expect-Block 'E6-S1-high-null-slot' { Invoke-Seam $wNull $rowHighE6 | Out-Null }
Expect-NeuterFlip 'E6-S1-neuter-flip' 'orch_enforce.ps1' 'if ($required) { New-NeoBlock "auditor-slot: audit_tier' 'if ($false) { New-NeoBlock "auditor-slot: audit_tier' `
  { Invoke-Seam $wNull $rowHighE6 | Out-Null }
Expect-Ok 'E6-P2-low-null-slot-passes' {
  $r = Invoke-Seam $wNull $rowLowE6
  if ($r.required) { throw 'expected required=false' }
  'lightweight tier + null slot => no over-block'
}

# --- S2/S3/S4: forged slot - the verdict artifact re-validates to something ELSE
$wNoGo = Build-SlotWorld 'e6_nogo' -FixtureRec 'NO-GO' -SlotRec 'GO'
Expect-Block 'E6-S2-forged-GO-vs-NO-GO' { Invoke-Seam $wNoGo $rowHighE6 | Out-Null }
$wNeeds = Build-SlotWorld 'e6_needs' -FixtureRec 'NEEDS-MORE' -SlotRec 'GO'
Expect-Block 'E6-S3-forged-GO-vs-NEEDS-MORE' { Invoke-Seam $wNeeds $rowHighE6 | Out-Null }
Expect-NeuterFlip 'E6-S23-rec-match-neuter-flip' 'orch_enforce.ps1' 'if (([string]$validated.recommendation) -cne $slotRec)' 'if ($false)' `
  { Invoke-Seam $wNoGo $rowHighE6 | Out-Null }
$wAud = Build-SlotWorld 'e6_aud' -FixtureRec 'GO' -FixtureAuditor 'some-other-auditor' -SlotRec 'GO' -SlotAuditor 'isolated-auditor-cold'
Expect-Block 'E6-S4-auditor-identity-mismatch' { Invoke-Seam $wAud $rowHighE6 | Out-Null }
Expect-NeuterFlip 'E6-S4-neuter-flip' 'orch_enforce.ps1' 'if (([string]$validated.auditor_identity) -cne $slotAud)' 'if ($false)' `
  { Invoke-Seam $wAud $rowHighE6 | Out-Null }

# --- S5: traversal/rooted bundle_ref. The neuter fixture ISOLATES the seam's own guard line:
# the evil dir (OUTSIDE the session root) holds byte-copies of the real bundle+verdict whose
# member rels still resolve INSIDE the root, so with the seam's line neutered every downstream
# guard passes and the fixture flips - proving the seam's own containment call is load-bearing.
$wTrav = Build-SlotWorld 'e6trav/root'
$evilDir = Join-Path $ScratchRoot 'e6trav\evil'
New-Item -ItemType Directory -Force -Path $evilDir | Out-Null
Copy-Item -LiteralPath $wTrav.bundlePath -Destination (Join-Path $evilDir 'AUDIT_BUNDLE.json') -Force
Copy-Item -LiteralPath $wTrav.arPath -Destination (Join-Path $evilDir 'AUDIT_RESULT.json') -Force
$wTrav.endLive = Set-SlotOnDisk $wTrav.erPath $wTrav.slug (@{ recommendation = 'GO'; auditor_identity = 'isolated-auditor-cold'; bundle_ref = '../evil/AUDIT_BUNDLE.json' })
Expect-Block 'E6-S5-bundle_ref-traversal' { Invoke-Seam $wTrav $rowHighE6 | Out-Null }
Expect-NeuterFlip 'E6-S5-neuter-flip' 'orch_enforce.ps1' 'Assert-NeoSafeRel $slotRef; $bundleFull = Assert-NeoContained $SessionRoot $slotRef' '$bundleFull = [System.IO.Path]::GetFullPath((Join-Path $SessionRoot ($slotRef -replace ''^\./'', '''')))' `
  { Invoke-Seam $wTrav $rowHighE6 | Out-Null }
# rooted/drive-qualified variant (behavioral; the SAME guard line's load-bearing is E6-S5-neuter-flip)
Expect-Block 'E6-S5b-bundle_ref-rooted' {
  Invoke-Seam @{ root = $wHappy.root; endLive = (New-SlotEnd 'ss-slot' (@{ recommendation = 'GO'; auditor_identity = 'a'; bundle_ref = 'C:/evil/AUDIT_BUNDLE.json' })) } $rowHighE6 | Out-Null
}

# --- S6: malformed slot shapes (behavioral). HONEST NEUTER NOTE: these shape guards are the
# EARLIEST line of defense; neutering any one of them is MASKED downstream (rec-not-enum /
# blank-auditor fall to the independently neuter-proven match guards; blank-ref falls to the
# frozen safe-rel guard). They are defense-in-depth, not solely load-bearing - reported as such.
Expect-Block 'E6-S6a-slot-rec-not-enum' { Invoke-Seam @{ root = $wHappy.root; endLive = (New-SlotEnd 'ss-slot' (@{ recommendation = 'MAYBE'; auditor_identity = 'a'; bundle_ref = $wHappy.bundleRel })) } $rowHighE6 | Out-Null }
Expect-Block 'E6-S6b-slot-auditor-blank' { Invoke-Seam @{ root = $wHappy.root; endLive = (New-SlotEnd 'ss-slot' (@{ recommendation = 'GO'; auditor_identity = ''; bundle_ref = $wHappy.bundleRel })) } $rowHighE6 | Out-Null }
Expect-Block 'E6-S6c-slot-bundle_ref-blank' { Invoke-Seam @{ root = $wHappy.root; endLive = (New-SlotEnd 'ss-slot' (@{ recommendation = 'GO'; auditor_identity = 'a'; bundle_ref = '' })) } $rowHighE6 | Out-Null }

# --- S7: blank risk + null slot => BLOCK inside the REUSED tier oracle (never assume low).
# Load-bearing ownership: the frozen E1-missing-risk_class guard + E1a neuter pair.
Expect-Block 'E6-S7-blank-risk-null-slot' { Invoke-Seam $wNull (Row 'security' '' $true 'isolated' $null) | Out-Null }
# --- S8: a forged slot on a LOW-risk row still blocks (present slot validated though not required)
Expect-Block 'E6-S8-low-risk-forged-slot-blocked' { Invoke-Seam $wNoGo $rowLowE6 | Out-Null }

# --- S9/S10: absent verdict artifact / absent bundle file (behavioral; neutering the Test-Path
# guards is masked by the frozen Read-NeoJsonFile missing-file BLOCK - honest note, fail-closed either way)
$wNoAr = Build-SlotWorld 'e6_noar'
Remove-Item -LiteralPath $wNoAr.arPath -Force
Expect-Block 'E6-S9-missing-sibling-result' { Invoke-Seam $wNoAr $rowHighE6 | Out-Null }
Expect-Block 'E6-S10-missing-bundle-file' {
  Invoke-Seam @{ root = $wHappy.root; endLive = (New-SlotEnd 'ss-slot' (@{ recommendation = 'GO'; auditor_identity = 'a'; bundle_ref = './NEO_SESSION/ss-slot/audit/NOPE.json' })) } $rowHighE6 | Out-Null
}

# --- E1/E2 addendum: authoritative-end_report integrity (fix-2 carried assembler-mislabel residual)
# E1a: canonical member (real END) + miscased decoy => case-insensitive count=2 => BLOCK. The honest
# stub counts case-EXACTLY (1) and derives GO - exactly the enumeration dodge the seam closes.
$wDodge = Build-SlotWorld 'e6_dodge' -DecoyMiscasedEnd
Expect-Block 'E6-E1a-two-end-members-dodge' { Invoke-Seam $wDodge $rowHighE6 | Out-Null }
Expect-NeuterFlip 'E6-E1a-neuter-flip' 'orch_enforce.ps1' 'if ($endMembers.Count -ne 1)' 'if ($false)' `
  { Invoke-Seam $wDodge $rowHighE6 | Out-Null }
# E1b: a LONE miscased end_report member => BLOCK (only the exact canonical label is authoritative).
# The honest stub sees ZERO canonical members => NEEDS-MORE, so the slot carries NEEDS-MORE (matching).
$wMiscase = Build-SlotWorld 'e6_miscase' -LoneMiscasedEnd -SlotRec 'NEEDS-MORE'
Expect-Block 'E6-E1b-lone-miscased-end-member' { Invoke-Seam $wMiscase $rowHighE6 | Out-Null }
Expect-NeuterFlip 'E6-E1b-neuter-flip' 'orch_enforce.ps1' "if (`$emRole -cne 'end_report')" 'if ($false)' `
  { Invoke-Seam $wMiscase $rowHighE6 | Out-Null }
# E2: the bundle froze a FOREIGN subsession's END (internally hash-consistent, verdict GO) but it is
# not THIS subsession's END => slot-invariant body id mismatch => BLOCK (transplant/craft defense).
$wForeign = Build-SlotWorld 'e6_foreign' -ForeignEndInBundle -FixtureRec 'GO'
Expect-Block 'E6-E2-foreign-end-in-bundle' { Invoke-Seam $wForeign $rowHighE6 | Out-Null }
Expect-NeuterFlip 'E6-E2-neuter-flip' 'orch_enforce.ps1' 'if ($bundEndId -cne $liveEndId)' 'if ($false)' `
  { Invoke-Seam $wForeign $rowHighE6 | Out-Null }

# ---- summary + residue-clean ------------------------------------------------
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
    suite = 'NEO-4.0-P3-B2a-ENFORCE'; timestamp = $TS
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
