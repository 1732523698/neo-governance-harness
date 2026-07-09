# orch_pilot.ps1 - NEO 4.0-P3-C THROWAWAY PILOT library (fixture/artifact builders only).
# ASCII-only (D10). Dot-source AFTER the real engine (orch_engine.ps1). This file
# REIMPLEMENTS NO orchestration logic: it only builds schema-valid synthetic inputs and
# adversarial fixtures, then hands them to the REAL installed engine functions that the
# runner (orch_pilot_run.ps1) calls. Every artifact is validated by the engine against the
# INSTALLED .neo/schema spine. Writes NO AUDIT_RESULT except via a clearly-labelled
# adversarial FIXTURE helper (twin of the frozen B2a suite's Write-AuditResult) used ONLY
# to prove the isolated-tier REJECT guard fires; the honest AUDIT_RESULT writer stays the
# separate orch_auditor_stub.ps1 (the engine still cannot self-approve).

# ---- provenance envelope helper (thin wrapper over the REAL New-NeoEnvelope) ------------
function New-PilotEnv {
  param([string]$Id, [string]$Class, [string]$SchemaId, [string]$PRole, [string]$PClass, [string]$VClass, [string]$NAReason, [string]$TS)
  $ea = @{
    ArtifactId = $Id; ArtifactClass = $Class; SchemaId = $SchemaId; SchemaVersion = '4.0-P3-B'
    ProducerRole = $PRole; ProducerClass = $PClass; ValidatorRole = $PRole; ValidatorClass = $VClass
    Timestamp = $TS; DeclaredPaths = @('./program/'); DeclaredSurfaces = @('filesystem'); SourcePackets = @(); GateRef = $null
  }
  if ($NAReason) { $ea['ValidatorNAReason'] = $NAReason }
  return (New-NeoEnvelope @ea)
}

# ---- synthetic program inputs (schema-valid) --------------------------------------------
function New-PilotSpec([string]$TS) {
  $o = [pscustomobject][ordered]@{
    spec_id = 'spec-p3c'; spec_version = '1.0'; intent = 'disposable synthetic pilot app (P3-C)'
    in_scope = @('low-feature', 'med-feature', 'sec-feature', 'fail-feature', 'dependent-feature')
    out_of_scope = @('production use')
    acceptance_criteria = @(@{ id = 'AC1'; statement = 'whole orchestration loop proven end to end'; verifiable_by = 'harness:orch_pilot' })
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-PilotEnv 'spec-p3c' 'evidence' 'neo:project_spec' 'spec-author' 'strong_producer' 'strong_producer' $null $TS)
  Set-NeoArtifactHash $o; return $o
}
function New-PilotConstraint([string]$TS) {
  $o = [pscustomobject][ordered]@{
    package_id = 'cp-p3c'; package_version = '1.0'
    constraints = @(@{ id = 'C1'; statement = 'every dispatch must pass enforcement'; kind = 'functional'; severity = 'high' })
    test_harness_ref = @{ artifact_id = 'th-p3c'; content_hash = 'h-th' }
    profile_risk_ref = @{ artifact_id = 'pr-p3c'; content_hash = 'h-pr' }
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-PilotEnv 'cp-p3c' 'constraint' 'neo:constraint_package' 'constraint-editor' 'strong_producer' 'strong_producer' $null $TS)
  Set-NeoArtifactHash $o; return $o
}
function New-PilotArch([string]$TS) {
  $o = [pscustomobject][ordered]@{
    architecture_id = 'arch-p3c'; architecture_version = '1.0'
    components = @(@{ id = 'c1'; responsibility = 'core'; owns_paths = @('./app/') })
    interfaces = @(@{ id = 'i1'; between = @('c1', 'c2'); contract = 'iface' })
    disjoint_scope_map = @(@{ group = 'g1'; paths = @('./app/'); proven_disjoint = $false })
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-PilotEnv 'arch-p3c' 'evidence' 'neo:architecture' 'architect' 'strong_producer' 'strong_producer' $null $TS)
  Set-NeoArtifactHash $o; return $o
}
# Four representative risk surfaces, one per pilot stage P2..P5.
function New-PilotRisk([string]$TS) {
  $o = [pscustomobject][ordered]@{
    register_id = 'rr-p3c'; register_version = '1.0'
    risks = @(
      @{ id = 'r-low';  area = 'general_feature'; risk_class = 'low';    never_batchable = $false; audit_tier = 'lightweight' },
      @{ id = 'r-med';  area = 'general_feature'; risk_class = 'medium'; never_batchable = $false; audit_tier = 'isolated'    },
      @{ id = 'r-sec';  area = 'security';        risk_class = 'high';   never_batchable = $true;  audit_tier = 'isolated'    },
      @{ id = 'r-fail'; area = 'deploy';          risk_class = 'high';   never_batchable = $true;  audit_tier = 'isolated'    }
    )
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-PilotEnv 'rr-p3c' 'profile_risk' 'neo:risk_register' 'risk-author' 'strong_producer' 'strong_producer' $null $TS)
  Set-NeoArtifactHash $o; return $o
}
function Build-PilotProgram([string]$ProgramRoot, [string]$TS, $Index) {
  New-Item -ItemType Directory -Force -Path $ProgramRoot | Out-Null
  # Write-NeoProgramArtifact re-validates each input against the INSTALLED spine before writing.
  Write-NeoProgramArtifact -ProgramRoot $ProgramRoot -Name 'PROJECT_SPEC'       -Obj (New-PilotSpec $TS)       -Index $Index | Out-Null
  Write-NeoProgramArtifact -ProgramRoot $ProgramRoot -Name 'CONSTRAINT_PACKAGE' -Obj (New-PilotConstraint $TS) -Index $Index | Out-Null
  Write-NeoProgramArtifact -ProgramRoot $ProgramRoot -Name 'ARCHITECTURE'       -Obj (New-PilotArch $TS)       -Index $Index | Out-Null
  Write-NeoProgramArtifact -ProgramRoot $ProgramRoot -Name 'RISK_REGISTER'      -Obj (New-PilotRisk $TS)       -Index $Index | Out-Null
}

# Extract one risk row (as a pscustomobject) from a written RISK_REGISTER by id.
function Get-PilotRiskRow($Risk, [string]$Id) {
  $r = @($Risk.risks | Where-Object { $_.id -eq $Id })
  if ($r.Count -ne 1) { throw "pilot: risk row '$Id' not found (got $($r.Count))" }
  return [pscustomobject]$r[0]
}

# A schema-valid SUBSESSION_END_REPORT for a sub-session (exit!=0 marks a failed session).
function New-PilotEndReport([string]$Slug, [string]$ChangedPath, [string]$ChangeKind, [int]$Exit, [string]$TS) {
  $o = [pscustomobject][ordered]@{
    report_id = "er-$Slug"; slug = $Slug
    changed_files = @(@{ path = $ChangedPath; sha256_after = ('0' * 64); change_kind = $ChangeKind })
    diff_manifest = @(@{ path = $ChangedPath; diff_ref = "./diffs/$Slug.patch" })
    tests_run = @(@{ command = 'run pilot tests'; exit_code = $Exit; proof_ref = "./NEO_SESSION/$Slug/proof.ps1" })
    skipped_or_unverified = @()
    deferrals = @()
    rollback_notes = @{ snapshot_ref = "./NEO_SESSION/$Slug/snapshots/pre"; touched_files = @($ChangedPath); dependency_changes = @(); migration_status = 'none'; cleanup_status = 'clean' }
    touched_flags = @{ touched_constraints = $false; touched_tests_harness = $false; touched_profile_risk = $false }
    auditor_recommendation_slot = $null
  }
  $o | Add-Member -NotePropertyName '_provenance' -NotePropertyValue (New-PilotEnv "er-$Slug" 'evidence' 'neo:subsession_end_report' 'builder' 'strong_producer' 'strong_producer' 'raw builder evidence pre-audit' $TS)
  Set-NeoArtifactHash $o; return $o
}

# FIXTURE-LOCAL human-gate ledger (NEVER .neo/gates/HUMAN_GATE_LEDGER.json).
function Write-PilotLedger([string]$Path, $Entries) {
  $led = [pscustomobject]@{
    human_gate_ledger_schema_id = 'neo:human_gate_ledger'
    root_of_trust               = 'provisional-dev'
    note                        = 'FIXTURE-LOCAL ledger for the P3-C pilot. NEVER the live governed-gates ledger.'
    entries                     = @($Entries)
  }
  Write-NeoJsonFile $Path $led
  return $Path
}

# A MODEL_ROUTING_LOG-shaped routing entry (twin of the frozen suites' RoutingEntry).
function New-PilotRoutingEntry([string]$PC, [string]$VC, [string]$Rationale, [string]$TaskRisk = 'low') {
  return [pscustomobject]@{
    task_id = 't-p3c'; task_risk = $TaskRisk; producer_model = 'prod-model'; producer_class = $PC
    validator_model = 'val-model'; validator_class = $VC; validator_adequacy_rationale = $Rationale
  }
}

# ADVERSARIAL FIXTURE (labelled): a schema-valid AUDIT_RESULT with a CHOSEN producer
# model_class, used ONLY to prove the isolated-tier consume guard (W3) rejects a
# non-auditor-class result. This is a TEST fixture (twin of the frozen B2a suite's
# Write-AuditResult), NOT engine code and NOT the honest auditor: the engine still has no
# self-approval path, and the honest GO verdict is always produced by orch_auditor_stub.ps1.
function New-PilotAdversarialAuditResult {
  param([string]$Path, [string]$BundleDir, $Bundle, [string]$ProducerClass, [string]$Recommendation, [string]$AuditorId, [string]$TS, $Index)
  $mismatches = @()
  foreach ($m in @($Bundle.allowlist)) {
    $rel = [string]$m.path
    $mp = Assert-NeoContained $BundleDir $rel
    if ((Get-NeoSha256File $mp) -cne ([string]$m.content_hash)) { $mismatches += $rel }
  }
  $env = New-PilotEnv 'ar-adv' 'evidence' 'neo:audit_result' 'isolated-auditor' $ProducerClass $ProducerClass $null $TS
  $r = [pscustomobject]@{
    result_id        = 'ar-adv'
    recommendation   = $Recommendation
    findings         = @()
    rehash_check     = @{ all_members_matched = ($mismatches.Count -eq 0); mismatches = @($mismatches) }
    auditor_identity = $AuditorId
    _provenance      = $env
  }
  Set-NeoArtifactHash $r
  Assert-NeoValid $r 'neo:audit_result' $Index 'AUDIT_RESULT(adversarial-fixture)'
  Write-NeoJsonFile $Path $r
  return $Path
}

# ---- OUTSIDE-ENGINE auditor-slot filler (slice-2) ----------------------------------------
# MASTER/COORDINATOR action, not engine code (v4 5.1): copies the already-CONSUMED verdict
# (the return of the engine's Read-NeoAuditResult) into the builder END's
# auditor_recommendation_slot and re-stamps the artifact hash. The engine itself never
# authors this slot - it only READS it back through the fail-closed seam
# (Assert-NeoAuditorSlotSatisfied), which re-validates the verdict artifact the bundle_ref
# points at before the slot counts for anything.
function Set-PilotAuditorSlot {
  param([string]$ErPath, $Consumed, [string]$BundleRel)
  $er = Read-NeoJsonFile $ErPath
  $er.auditor_recommendation_slot = [pscustomobject]@{
    recommendation   = [string]$Consumed.recommendation
    auditor_identity = [string]$Consumed.auditor_identity
    bundle_ref       = $BundleRel
  }
  Set-NeoArtifactHash $er
  Write-NeoJsonFile $ErPath $er
  return $er
}
