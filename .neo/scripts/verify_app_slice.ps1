# verify_app_slice.ps1 - NEO v2.6 central verification net for real-app / fixture-app slices.
# ASCII-only, PowerShell 5.1.
#
# Consumes an app profile (modules\<app_slug>\NEO_APP_PROFILE.md) plus a slice directory of
# declared changes + command evidence, runs the AS1..AS15 check net, and PRODUCES a validated
# APP_END_EVIDENCE.json bundle. check_app_end_evidence.ps1 validates the bundle independently.
#
# Modes:
#   fixture (default) - runs against fixture trees inside S:\NEO. Fixture PASS validates the
#                       adapter mechanics ONLY; it never certifies an external app.
#   real              - requires BOUNDARY_APPROVED: yes in the profile AND -BoundaryApproved.
#                       Real-app execution needs explicit Raphael boundary sign-off per path.
#
# Slice directory contract:
#   CHANGED_FILES.txt      one path per line, relative to AppRoot; deletions prefixed DELETED:
#   SLICE_DECLARATION.txt  DECLARED_TIER: RTn / FAST_LANE: yes|no
#   HEAD_SHA.txt           optional; fixture default FIXTURE-NO-GIT
#   command_evidence.json  [{name,cmd,cwd,exit_code,timestamp,output_path}]
#   DEP_GUARD.md / ROLLBACK_PROOF.md / CLIENT_VERIFICATION.md / HUMAN_ACCEPTANCE.md /
#   CUSTOM_CHECKS.md / SMOKE.md  as required by the checks below.
#
# Exit 0 only when no gating check FAILs.

param(
  [Parameter(Mandatory=$true)][string]$AppRoot,
  [Parameter(Mandatory=$true)][string]$Profile,
  [Parameter(Mandatory=$true)][string]$SliceDir,
  [Parameter(Mandatory=$true)][string]$EvidenceOut,
  [ValidateSet('fixture','real')][string]$Mode = 'fixture',
  [switch]$BoundaryApproved,
  # 3.1 P1-S4 (RT4-R1 / section 4.7 gate binding): the human-gate ledger AS4 binds an UNLOCK_RECORD
  # to. DEFAULT resolves to the NEO script-root authority (.neo\gates\HUMAN_GATE_LEDGER.json) so an app
  # tree cannot supply its own permissive ledger; only a trusted operator/harness may override the path
  # (like -Profile / -BoundaryApproved). A missing/invalid ledger fails AS4 closed.
  [string]$HumanGateLedger = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
$neoRoot = Resolve-NeoRoot $PSScriptRoot
$script:checks = New-Object System.Collections.ArrayList
$script:failCount = 0

# NEO script-root (the dir that contains .neo\), resolved from THIS script's location (never -AppRoot)
# so authority artifacts (class map, human-gate ledger) cannot be supplied by the app tree under test.
$script:neoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(-not $HumanGateLedger){ $HumanGateLedger = Join-Path $script:neoRoot '.neo\gates\HUMAN_GATE_LEDGER.json' }

# Cached artifact-class-map loader + resolver (first matching rule wins; unmatched -> default_class),
# shared by AS4 (3.1-C class-scoped authorization). Returns $null when the map is absent/unparseable so
# the caller fails closed. Mirrors AS18's resolution (from script root, not -AppRoot).
$script:CMcache = $null
function Get-ClassMap {
  if($script:CMcache){ return $script:CMcache }
  $cmPath = Join-Path $script:neoRoot '.neo\schema\artifact_classes.json'
  if(-not (Test-Path -LiteralPath $cmPath)){ return $null }
  try { $script:CMcache = Get-Content -LiteralPath $cmPath -Raw | ConvertFrom-Json } catch { return $null }
  return $script:CMcache
}
function Resolve-ArtifactClass([string]$Norm,$CM){
  $leaf = ($Norm -split '/')[-1]
  foreach($rule in $CM.rules){
    foreach($g in @($rule.globs)){
      $gg = ($g -replace '\\','/')
      if(($Norm -like $gg) -or ($leaf -like $gg)){ return $rule.class }
    }
  }
  return $CM.default_class
}

function Add-Check([string]$Id,[string]$Name,[string]$Status,[string]$Detail){
  [void]$script:checks.Add(@{ id=$Id; name=$Name; status=$Status; detail=$Detail })
  if($Status -eq 'FAIL'){ $script:failCount++ }
}

# ---------- load profile (NEO 3.0 port: the validated JSON spine is the SOLE authority) ----------
# 3.0 change (Session 5 port): the per-app profile authority is the validated JSON spine
# (.neo\schema\NEO_APP_PROFILE.schema.json). The legacy Markdown profile is now a generated,
# NON-authoritative VIEW. Given either sibling path in -Profile (.md or .json), resolve and load
# the JSON authority. ONLY this ingestion block changed in the port: every AS check below consumes
# the SAME local variables this block produces, with identical values (proven byte-for-behavior in
# .neo\_v3.0\session5\MIGRATION_FAITHFULNESS.md). The downstream check logic is untouched.
if([System.IO.Path]::GetExtension($Profile) -ieq '.json'){ $profileJson = $Profile }
else { $profileJson = [System.IO.Path]::ChangeExtension($Profile, '.json') }
if(-not (Test-Path -LiteralPath $profileJson)){ Write-Host "FATAL: authoritative JSON profile not found: $profileJson"; exit 1 }
try { $P = Get-Content -LiteralPath $profileJson -Raw | ConvertFrom-Json }
catch { Write-Host "FATAL: profile JSON parse error ($profileJson): $($_.Exception.Message)"; exit 1 }
# fail-closed validated-load guards (authority invariants the schema pins as const):
if($P.binding.profile_schema_id -ne 'neo:app_profile'){ Write-Host "FATAL: profile is not a neo:app_profile instance: $profileJson"; exit 1 }
if($P.binding.generated_view_is_authoritative -eq $true){ Write-Host "FATAL: a generated VIEW may never be authority (binding.generated_view_is_authoritative=true): $profileJson"; exit 1 }
function J-Arr($v){ if($null -eq $v){ return ,@() } return ,@($v) }
$appSlug   = $P.identity.app_slug
$appName   = $P.identity.app_name
$boundaryOk = [bool]$P.boundary_approval.boundary_approved
$denyList  = J-Arr ($P.denylist.entries | ForEach-Object { $_.pattern })
$tokens    = J-Arr $P.residue_tokens
$i18nDir   = $P.i18n.dir
$i18nLocales = if($P.i18n -and $P.i18n.locales){ ($P.i18n.locales -join ',') } else { $null }
$asciiGlobs = J-Arr $P.charset.ascii_globs
$migDir    = $P.migrations.migrations_dir
$depFiles  = J-Arr $P.dependencies.dep_files
$authTokens = J-Arr $P.risk_tokens.auth_tokens
$finTokens = J-Arr $P.risk_tokens.fin_tokens
$cmdTypecheck = ($P.commands.named | Where-Object { $_.key -eq 'CMD_TYPECHECK' } | Select-Object -First 1).command
$cmdBuild  = ($P.commands.named | Where-Object { $_.key -eq 'CMD_BUILD' } | Select-Object -First 1).command
$customChecks = J-Arr $P.custom_checks
$i18nStyle = if($P.i18n){ $P.i18n.style } else { $null }
if(-not $i18nStyle){ $i18nStyle = 'flat_json' }
$scopedDeny = J-Arr ($P.scoped_deny_imports | ForEach-Object { "$($_.source) => $($_.forbidden_symbols -join ', ')" })

# deny entries may be exact paths or globs (entries containing *)
function Test-DenyMatch([string]$NormPath,[string]$DenyEntry){
  $d = $DenyEntry -replace '\\','/'
  if($d -like '*[*]*'){ return $NormPath -like ($d -replace '\*\*','*') }
  return $NormPath -eq $d
}
if(-not $appSlug){ Write-Host "FATAL: profile missing APP_SLUG"; exit 1 }

if(-not (Test-Path -LiteralPath $AppRoot)){ Write-Host "FATAL: AppRoot not found: $AppRoot"; exit 1 }
if(-not (Test-Path -LiteralPath $SliceDir)){ Write-Host "FATAL: SliceDir not found: $SliceDir"; exit 1 }
$AppRoot = (Resolve-Path -LiteralPath $AppRoot).Path

# ---------- AS1 mode / boundary ----------
$fixtureWarning = 'Fixture PASS validates adapter mechanics only. It does not certify external app execution.'
if($Mode -eq 'real'){
  $rootedInNeo = $AppRoot -like "$neoRoot\*"
  if(-not $boundaryOk){
    Add-Check 'AS1' 'Mode/boundary gate' 'FAIL' 'real mode requires BOUNDARY_APPROVED: yes in the app profile (explicit Raphael sign-off per path)'
  } elseif(-not $BoundaryApproved){
    Add-Check 'AS1' 'Mode/boundary gate' 'FAIL' 'real mode requires the -BoundaryApproved switch (deliberate operator act)'
  } else {
    Add-Check 'AS1' 'Mode/boundary gate' 'PASS' "real mode, boundary sign-off recorded in profile; AppRoot inside NEO root = $rootedInNeo"
  }
} else {
  Add-Check 'AS1' 'Mode/boundary gate' 'PASS' "fixture mode. $fixtureWarning"
  Write-Host "[WARN] $fixtureWarning"
}

# ---------- changed files + slice declaration ----------
$cfPath = Join-Path $SliceDir 'CHANGED_FILES.txt'
$changedRaw = @()
$gitDir = Join-Path $AppRoot '.git'
$headSha = 'FIXTURE-NO-GIT'; $branch = 'fixture'
$shaPath = Join-Path $SliceDir 'HEAD_SHA.txt'
if(Test-Path -LiteralPath $shaPath){ $headSha = (Get-Content -LiteralPath $shaPath | Select-Object -First 1).Trim() }
if(Test-Path -LiteralPath $gitDir){
  Push-Location $AppRoot
  try {
    $headSha = (& git rev-parse HEAD 2>$null).Trim()
    $branch  = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    $changedRaw = @(& git status --porcelain | ForEach-Object {
      $code = $_.Substring(0,2); $p = $_.Substring(3).Trim()
      if($code -match 'D'){ "DELETED:$p" } else { $p }
    })
  } finally { Pop-Location }
  Add-Check 'AS2' 'Git/changed-set proof' 'PASS' "branch=$branch HEAD=$headSha changed=$($changedRaw.Count) (git porcelain)"
} elseif(Test-Path -LiteralPath $cfPath){
  $changedRaw = @(Get-Content -LiteralPath $cfPath | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
  $missing = @()
  foreach($f in $changedRaw){
    if($f -notlike 'DELETED:*'){
      if(-not (Test-Path -LiteralPath (Join-Path $AppRoot ($f -replace '/','\')))){ $missing += $f }
    }
  }
  if($missing.Count -gt 0){
    Add-Check 'AS2' 'Git/changed-set proof' 'FAIL' ("declared changed files missing on disk: " + ($missing -join ', '))
  } else {
    Add-Check 'AS2' 'Git/changed-set proof' 'PASS' "no git (fixture); CHANGED_FILES.txt verified on disk; HEAD=$headSha; changed=$($changedRaw.Count)"
  }
} else {
  Add-Check 'AS2' 'Git/changed-set proof' 'FAIL' 'no .git and no CHANGED_FILES.txt - cannot prove what was checked'
}
$changed = @($changedRaw | Where-Object { $_ -notlike 'DELETED:*' })
$deleted = @($changedRaw | Where-Object { $_ -like 'DELETED:*' } | ForEach-Object { $_.Substring(8) })

$declPath = Join-Path $SliceDir 'SLICE_DECLARATION.txt'
$declaredTier = ''; $fastLaneRequested = $false
if(Test-Path -LiteralPath $declPath){
  foreach($l in (Get-Content -LiteralPath $declPath)){
    if($l -match '^DECLARED_TIER:\s*(RT[1-4])'){ $declaredTier = $Matches[1] }
    if($l -match '^FAST_LANE:\s*yes'){ $fastLaneRequested = $true }
  }
}

function Get-FileText([string]$Rel){
  $p = Join-Path $AppRoot ($Rel -replace '/','\')
  if(Test-Path -LiteralPath $p){ return [System.IO.File]::ReadAllText($p) }
  return ''
}

# human acceptance evidence is consumed by AS6 (dynamic i18n keys), AS11 and AS14
$humanAccPath = Join-Path $SliceDir 'HUMAN_ACCEPTANCE.md'
$humanAcceptance = @()
# "$_" strips Get-Content's provider note-properties (PSPath/PSDrive/...) - leaving them on
# makes ConvertTo-Json -Depth 10 serialize the whole provider graph (multi-GB hang, PS 5.1)
if(Test-Path -LiteralPath $humanAccPath){ $humanAcceptance = @(Get-Content -LiteralPath $humanAccPath | Where-Object { $_.Trim() -ne '' } | ForEach-Object { "$_" }) }

# command evidence is loaded ONCE here (3.1 P1-S4: also consumed by AS4's invariant-test bind, which
# runs before AS13). AS13 reuses $cmdEntries and reports the parse error captured in $cmdEvParseError.
$cmdEvPath = Join-Path $SliceDir 'command_evidence.json'
$cmdEntries = @()
$cmdEvParseError = $null
if(Test-Path -LiteralPath $cmdEvPath){
  try { $cmdEntries = @((Get-Content -LiteralPath $cmdEvPath -Raw | ConvertFrom-Json)) } catch { $cmdEvParseError = $_.Exception.Message }
}

# ---------- AS3 changed-file scope classifier ----------
$buckets = New-Object System.Collections.ArrayList
function Add-Bucket([string]$b){ if($script:buckets -notcontains $b){ [void]$script:buckets.Add($b) } }
# 3.1 P1-S1 (AS10 prose-precision): `-match` is case-insensitive, so the old bare `DROP\s+` matched
# English prose ("drop the...", "Drop down") in non-DDL files. Require a DDL object keyword after DROP
# so real DDL ("DROP TABLE", "drop view ...", "DROP INDEX IF EXISTS") still classifies while prose does
# not. SQL keywords stay case-insensitive on purpose (lowercase DDL is valid).
$ddlRegex = 'CREATE\s+TABLE|ALTER\s+TABLE|DROP\s+(TABLE|VIEW|INDEX|POLICY|FUNCTION|TRIGGER|SCHEMA|DATABASE|SEQUENCE|TYPE|COLUMN|CONSTRAINT|MATERIALIZED)|CREATE\s+POLICY|ENABLE\s+ROW\s+LEVEL\s+SECURITY|SECURITY\s+DEFINER|CREATE\s+FUNCTION'
$authHits = @{}; $finHits = @{}
foreach($f in $changed){
  $norm = $f -replace '\\','/'
  $txt = Get-FileText $f
  $isDeny = $false
  foreach($d in $denyList){ if(Test-DenyMatch $norm $d){ $isDeny = $true } }
  if($isDeny){ Add-Bucket 'locked_shared' }
  if($migDir -and $norm -like (($migDir -replace '\\','/') + '/*')){ Add-Bucket 'schema_migration' }
  elseif($txt -match $ddlRegex){ Add-Bucket 'schema_migration' }
  $isDep = $false
  foreach($df in $depFiles){ if($norm -eq $df -or $norm -like ('*/' + $df)){ $isDep = $true } }
  if($isDep -or $norm -match '(^|/)(next\.config|tsconfig|\.env|webpack\.config|vercel\.json|Dockerfile)'){ Add-Bucket 'dependency_config' }
  if($norm -like 'backend/*'){ Add-Bucket 'backend_api' }
  elseif($norm -like 'frontend/*'){
    if($txt -match 'useState|useReducer|useEffect|useMemo|reducer\('){ Add-Bucket 'client_logic' } else { Add-Bucket 'frontend_ui' }
  }
  elseif($norm -match '\.(md|txt)$'){ Add-Bucket 'docs_only' }
  foreach($t in $authTokens){ if($txt -match [regex]::Escape($t)){ Add-Bucket 'auth_permission'; $authHits[$f] = $t } }
  foreach($t in $finTokens){ if($txt -match ('(?i)' + [regex]::Escape($t))){ Add-Bucket 'financial_logic'; $finHits[$f] = $t } }
}
if($buckets.Count -eq 0){ Add-Bucket 'docs_only' }
$tierRank = @{ 'RT1'=1; 'RT2'=2; 'RT3'=3; 'RT4'=4 }
$derived = 'RT1'
$rt3Buckets = @('locked_shared','schema_migration','dependency_config','backend_api','auth_permission','financial_logic')
$rt2Buckets = @('frontend_ui','client_logic')
foreach($b in $buckets){
  if($rt3Buckets -contains $b -and $tierRank[$derived] -lt 3){ $derived = 'RT3' }
  elseif($rt2Buckets -contains $b -and $tierRank[$derived] -lt 2){ $derived = 'RT2' }
}
# 3.1 P1-S2 (3.1-E capability-dominant tiering): capability buckets impose a MINIMUM tier FLOOR that
# DOMINATES the stage/declared derivation. derived_tier = max(existing derivation, capability floor).
# Fixes NF-3: a slice carrying a schema migration AND/OR a balance-mutating (financial) surface can no
# longer be classified below RT4. Floors are calibrated to NEO_RISK_TIERS.md: financial_logic and
# schema_migration are payment/destructive-irreversible surfaces -> RT4 floor; auth_permission is
# security-sensitive business logic -> RT3 floor. The floor only ever RAISES the derived tier (max),
# never lowers it, so the upgrade-only invariant below is preserved. Buckets absent from the table
# (locked_shared/dependency_config/backend_api/frontend_ui/client_logic/docs_only) keep their existing
# derivation unchanged - the net behavioral change is exactly the two RT4 floors.
$capabilityFloor = @{ 'financial_logic' = 'RT4'; 'schema_migration' = 'RT4'; 'auth_permission' = 'RT3' }
foreach($b in $buckets){
  if($capabilityFloor.ContainsKey($b) -and $tierRank[$derived] -lt $tierRank[$capabilityFloor[$b]]){ $derived = $capabilityFloor[$b] }
}
if($declaredTier -eq ''){
  Add-Check 'AS3' 'Scope classifier (upgrade-only)' 'FAIL' 'no DECLARED_TIER in SLICE_DECLARATION.txt'
  $declaredTier = $derived
} elseif($tierRank[$declaredTier] -lt $tierRank[$derived]){
  Add-Check 'AS3' 'Scope classifier (upgrade-only)' 'FAIL' "declared $declaredTier is BELOW derived $derived (buckets: $($buckets -join ',')) - classifier may only upgrade risk"
} else {
  Add-Check 'AS3' 'Scope classifier (upgrade-only)' 'PASS' "buckets=$($buckets -join ',') derived=$derived declared=$declaredTier"
}

# ---------- AS4 denylist (3.1-C RT4-R1: adds PASS-WITH-AUTH for a human-gate-bound invariant-preserving edit) ----------
# Historic behaviour is UNCHANGED for the two prior outcomes: no denylist touch -> PASS; a denylist touch
# with no valid authorization -> FAIL. RT4-R1 adds a THIRD outcome, PASS-WITH-AUTH, reachable ONLY when a
# locked touch is authorized by a non-fabricable, HUMAN-gate-bound UNLOCK_RECORD (SliceDir\UNLOCK_RECORD.json)
# that binds to a recorded entry in the host-held human-gate ledger. ALL of these must hold, else FAIL
# (fail-closed): (1) a well-formed record + valid ledger both load; (2) app_slug matches; (3) the record's
# gate_ref RESOLVES to a ledger entry whose gate_kind is a HUMAN gate and whose authorized_by is a human,
# not a role/agent (this is the self-unlock-backdoor + self-issue block); (4) issuer/authority in the record
# match the ledger entry; (5) every touched denylisted path is covered by an authorization AND named in the
# ledger entry, its declared artifact_class equals the S3 class map, its expected_post_sha equals the on-disk
# re-pin, and (OQ1) its expected_prior_sha equals the denylist recorded_sha when present; (6) the named
# invariant behavioral test PASSED in command evidence. PROVISIONAL-DEV: the ledger is not yet under a
# host-held root-of-trust (section 4.9/S5) + Option A ACL (S6), so this is tamper-EVIDENT not tamper-PROOF;
# RT4-R1 PASS-WITH-AUTH is not trusted in PROD until S5 anchors the ledger. The record's binding fields must
# say so. The DEV->PROD push gate is the backstop.
$denyHits = @()
$denyEntryByNorm = @{}
foreach($f in ($changed + $deleted)){
  $norm = $f -replace '\\','/'
  foreach($de in @($P.denylist.entries)){
    if(Test-DenyMatch $norm ($de.pattern)){
      if($denyHits -notcontains $norm){ $denyHits += $norm }
      $denyEntryByNorm[$norm] = $de
    }
  }
}
$forbiddenTouched = $false
$as4AuthExceptions = @()
$roleNames = @('neo_builder','neo_director','neo_auditor','builder','director','auditor','role','agent','producer','orchestrator','system')
if($denyHits.Count -eq 0){
  Add-Check 'AS4' 'Forbidden-path / locked-file denylist' 'PASS' "no changed file on the $($denyList.Count)-entry denylist"
} else {
  $as4Fail = $null
  # (1a) load the AUTHORITY: the human-gate ledger (script-root default; app tree cannot supply it)
  $ledger = $null
  if(-not (Test-Path -LiteralPath $HumanGateLedger)){
    $as4Fail = "LOCKED path(s) touched (" + ($denyHits -join ', ') + ") and no human-gate ledger to authorize it: $HumanGateLedger (fail-closed)"
  } else {
    try { $ledger = Get-Content -LiteralPath $HumanGateLedger -Raw | ConvertFrom-Json }
    catch { $as4Fail = "human-gate ledger parse error ($HumanGateLedger): $($_.Exception.Message) (fail-closed)" }
    if((-not $as4Fail) -and ($ledger.human_gate_ledger_schema_id -ne 'neo:human_gate_ledger')){
      $as4Fail = "human-gate ledger is not a neo:human_gate_ledger instance (fail-closed): $HumanGateLedger"
    }
  }
  # (1b) load the REQUEST: the UNLOCK_RECORD from the slice
  $rec = $null
  if(-not $as4Fail){
    $urPath = Join-Path $SliceDir 'UNLOCK_RECORD.json'
    if(-not (Test-Path -LiteralPath $urPath)){
      $as4Fail = "LOCKED files touched with NO UNLOCK_RECORD (unauthorized): " + ($denyHits -join ', ')
    } else {
      try { $rec = Get-Content -LiteralPath $urPath -Raw | ConvertFrom-Json }
      catch { $as4Fail = "UNLOCK_RECORD.json is not valid JSON: $($_.Exception.Message) (fail-closed)" }
    }
  }
  # (1c) structural validation of the record (schema id + required fields present)
  if(-not $as4Fail -and ($rec.unlock_record_schema_id -ne 'neo:unlock_record')){
    $as4Fail = "UNLOCK_RECORD is not a neo:unlock_record instance (fail-closed)"
  }
  if(-not $as4Fail){
    foreach($rf in @('gate_ref','authorized_by','issued_by_gate','app_slug','invariant_test_id','authorizations','binding')){
      if($null -eq $rec.PSObject.Properties[$rf]){ $as4Fail = "UNLOCK_RECORD missing required field '$rf' (fail-closed)"; break }
    }
  }
  # (2) app_slug bind (a fixture/other-app authorization cannot authorize this app)
  if(-not $as4Fail -and ($rec.app_slug -ne $appSlug)){
    $as4Fail = "UNLOCK_RECORD app_slug '$($rec.app_slug)' != profile app_slug '$appSlug' (fail-closed)"
  }
  # provisional-dev honesty: binding must be labelled and never claim un-forgeability silently
  if(-not $as4Fail){
    if($rec.binding.root_of_trust -notin @('provisional-dev','host-anchored')){ $as4Fail = "UNLOCK_RECORD.binding.root_of_trust must be 'provisional-dev' or 'host-anchored' (fail-closed)" }
    elseif([string]::IsNullOrWhiteSpace([string]$rec.binding.prod_gate)){ $as4Fail = "UNLOCK_RECORD.binding.prod_gate assertion required (RT4-R1 not trusted in PROD until section 4.9 anchors the ledger) (fail-closed)" }
  }
  # (2b) P1-S5 labeling-integrity cross-check (section 4.9 hardening; ADD-ONLY - can only ADD a FAIL). A record
  # may not self-declare a stronger root-of-trust than the ledger it resolves against: rec.binding.root_of_trust
  # MUST EQUAL ledger.root_of_trust. So a 'host-anchored'-labeled record against a 'provisional-dev' ledger FAILS
  # (a dev record cannot claim the ledger is host-anchored past the ledger's own custody label). The byte-level
  # anchoring of the ledger itself is proven out-of-band by verify_root_of_trust.ps1 (the section 4.9 pre-gate).
  # provisional-dev==provisional-dev is UNCHANGED (still PASS-WITH-AUTH, still NOT trusted in PROD).
  if(-not $as4Fail){
    $ledgerRot = [string]$ledger.root_of_trust
    if([string]$rec.binding.root_of_trust -ne $ledgerRot){
      $as4Fail = "UNLOCK_RECORD.binding.root_of_trust '$($rec.binding.root_of_trust)' != ledger root_of_trust '$ledgerRot' (labeling-integrity cross-check: a record cannot claim a trust tier the ledger does not declare; host-anchored-vs-provisional-dev is fail-closed)"
    }
  }
  # (3) resolve the ledger entry named by gate_ref -> THE human-gate binding
  $gEntry = $null
  if(-not $as4Fail){
    $gEntry = @($ledger.entries) | Where-Object { $_.gate_ref -eq $rec.gate_ref } | Select-Object -First 1
    if(-not $gEntry){ $as4Fail = "UNLOCK_RECORD.gate_ref '$($rec.gate_ref)' NOT found in the human-gate ledger (self-unlock backdoor blocked; fail-closed)" }
  }
  # (3b) the ledger entry must be a HUMAN gate, not a role/agent self-grant
  if(-not $as4Fail){
    if($gEntry.gate_kind -notin @('human_end_keep','human_start_approval')){ $as4Fail = "ledger gate '$($rec.gate_ref)' gate_kind '$($gEntry.gate_kind)' is not a human gate (fail-closed)" }
    elseif([string]::IsNullOrWhiteSpace([string]$gEntry.authorized_by) -or ($roleNames -contains ([string]$gEntry.authorized_by).ToLower())){ $as4Fail = "ledger gate '$($rec.gate_ref)' authorized_by '$($gEntry.authorized_by)' is empty or a role/agent, not a human (self-issued -> NO PASS)" }
    elseif($gEntry.app_slug -and ($gEntry.app_slug -ne $appSlug)){ $as4Fail = "ledger gate '$($rec.gate_ref)' app_slug '$($gEntry.app_slug)' != profile app_slug '$appSlug' (fail-closed)" }
  }
  # (4) record<->ledger consistency: issuer + authority must match the recorded gate; record authority not a role
  if(-not $as4Fail){
    if($rec.issued_by_gate -ne $gEntry.gate_kind){ $as4Fail = "UNLOCK_RECORD.issued_by_gate '$($rec.issued_by_gate)' != ledger gate_kind '$($gEntry.gate_kind)' (fail-closed)" }
    elseif(([string]$rec.authorized_by).ToLower() -ne ([string]$gEntry.authorized_by).ToLower()){ $as4Fail = "UNLOCK_RECORD.authorized_by '$($rec.authorized_by)' != ledger authorized_by '$($gEntry.authorized_by)' (fail-closed)" }
    elseif($roleNames -contains ([string]$rec.authorized_by).ToLower()){ $as4Fail = "UNLOCK_RECORD.authorized_by '$($rec.authorized_by)' is a role/agent, not a human (self-issued -> NO PASS)" }
  }
  # (6) the named invariant behavioral test must be PRESENT + PASSING (interlock with AS15 invariant_preserved)
  if(-not $as4Fail){
    $itest = @($cmdEntries) | Where-Object { $_.name -eq $rec.invariant_test_id -and $_.status -eq 'pass' -and $_.exit_code -eq 0 } | Select-Object -First 1
    if(-not $itest){ $as4Fail = "UNLOCK_RECORD.invariant_test_id '$($rec.invariant_test_id)' has no PASSING command-evidence entry (invariant not proven; fail-closed)" }
  }
  # (5) per-path binds: coverage (scope guard) + ledger-named + artifact_class (S3 map) + expected_post_sha (re-pin) + OQ1 prior_sha
  $CM = Get-ClassMap
  if(-not $as4Fail -and ((-not $CM) -or ($CM.class_map_schema_id -ne 'neo:artifact_classes'))){
    $as4Fail = "artifact class map absent/invalid; cannot class-scope the authorization (fail-closed)"
  }
  if(-not $as4Fail){
    $ledgerPaths = @($gEntry.authorized_paths | ForEach-Object { ($_ -replace '\\','/') })
    foreach($dn in $denyHits){
      $az = @($rec.authorizations) | Where-Object { ($_.path -replace '\\','/') -eq $dn } | Select-Object -First 1
      if(-not $az){ $as4Fail = "denylisted path '$dn' touched but NOT covered by any UNLOCK_RECORD authorization (scope guard; fail-closed)"; break }
      if($ledgerPaths -notcontains $dn){ $as4Fail = "denylisted path '$dn' not named in ledger gate '$($rec.gate_ref)' authorized_paths (fail-closed)"; break }
      $cls = Resolve-ArtifactClass $dn $CM
      if($az.artifact_class -ne $cls){ $as4Fail = "authorization for '$dn' declares artifact_class '$($az.artifact_class)' but the class map resolves '$cls' (fail-closed)"; break }
      $full = Join-Path $AppRoot ($dn -replace '/','\')
      if(-not (Test-Path -LiteralPath $full)){
        if(([string]$az.expected_post_sha).ToUpper() -ne 'DELETED'){ $as4Fail = "authorized path '$dn' absent on disk but expected_post_sha is not 'DELETED' (fail-closed)"; break }
      } else {
        $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLower()
        if(([string]$az.expected_post_sha).ToLower() -ne $actual){ $as4Fail = "authorized path '$dn' expected_post_sha '$($az.expected_post_sha)' != actual re-pin SHA '$actual' (fail-closed)"; break }
      }
      $de = $denyEntryByNorm[$dn]
      if($de -and ($de.PSObject.Properties['recorded_sha']) -and (-not [string]::IsNullOrWhiteSpace([string]$de.recorded_sha))){
        if([string]::IsNullOrWhiteSpace([string]$az.expected_prior_sha)){ $as4Fail = "denylist entry for '$dn' has a recorded (locked) SHA but the authorization omits expected_prior_sha (OQ1 bind; fail-closed)"; break }
        if(([string]$az.expected_prior_sha).ToLower() -ne ([string]$de.recorded_sha).ToLower()){ $as4Fail = "authorization expected_prior_sha for '$dn' != denylist recorded_sha (unlocking a different locked version; fail-closed)"; break }
      }
      $as4AuthExceptions += [ordered]@{ path=$dn; artifact_class=$az.artifact_class; expected_post_sha=([string]$az.expected_post_sha).ToLower(); gate_ref=$rec.gate_ref; authorized_by=$gEntry.authorized_by; issued_by_gate=$gEntry.gate_kind; invariant_test_id=$rec.invariant_test_id; root_of_trust=$rec.binding.root_of_trust }
    }
  }
  if($as4Fail){
    $forbiddenTouched = $true
    $as4AuthExceptions = @()
    Add-Check 'AS4' 'Forbidden-path / locked-file denylist' 'FAIL' $as4Fail
  } else {
    Add-Check 'AS4' 'Forbidden-path / locked-file denylist' 'PASS-WITH-AUTH' ("authorized invariant-preserving edit of [" + ($denyHits -join ', ') + "] bound to HUMAN gate '" + $rec.gate_ref + "' (" + $gEntry.gate_kind + " by " + $gEntry.authorized_by + "); root_of_trust=" + $rec.binding.root_of_trust + " -- PROVISIONAL-DEV: NOT trusted in PROD until section 4.9 anchors the ledger")
  }
}

# ---------- AS5 residue tokens ----------
$tokenHits = @()
$allFiles = Get-ChildItem -LiteralPath $AppRoot -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' }
foreach($af in $allFiles){
  $txt = [System.IO.File]::ReadAllText($af.FullName)
  foreach($t in $tokens){ if($txt -match [regex]::Escape($t)){ $tokenHits += "$($af.FullName.Substring($AppRoot.Length+1)) [$t]" } }
}
if($tokenHits.Count -gt 0){ Add-Check 'AS5' 'Residue token grep (whole tree)' 'FAIL' ($tokenHits -join '; ') }
else { Add-Check 'AS5' 'Residue token grep (whole tree)' 'PASS' "$($tokens.Count) tokens, 0 hits across $($allFiles.Count) files" }

# ---------- AS6 i18n parity (style: flat_json | ts_namespace_dirs) ----------
$i18nStatus = 'not_applicable'
$i18nFull = if($i18nDir){ Join-Path $AppRoot ($i18nDir -replace '/','\') } else { $null }

function Get-KeyPaths($obj,[string]$prefix){
  $out = @()
  foreach($p in $obj.PSObject.Properties){
    $key = if($prefix){ "$prefix.$($p.Name)" } else { $p.Name }
    if($p.Value -is [System.Management.Automation.PSCustomObject]){ $out += @(Get-KeyPaths $p.Value $key) } else { $out += $key }
  }
  return $out
}

# Flatten a TypeScript dictionary file into nested key paths. FAILS CLOSED: parsed=false on
# brace imbalance. Flags dynamic/computed keys ([expr]: ...) - those need explicit human evidence.
function Get-TsDictPaths([string]$Path){
  $txt = [System.IO.File]::ReadAllText($Path)
  $txt = [regex]::Replace($txt,'/\*[\s\S]*?\*/','')
  $txt = [regex]::Replace($txt,'(?m)//.*$','')
  $keys = @(); $dynamic = $false; $parsed = $true
  $depth = 0
  $stack = New-Object System.Collections.ArrayList
  foreach($line in ($txt -split "`r?`n")){
    $t = $line.Trim()
    if($t -eq ''){ continue }
    if($t -match '\[[^\]]*\]\s*:'){ $dynamic = $true }
    # strip string literals so braces inside values do not skew depth tracking
    $s = $t -replace "'[^']*'","''" -replace '"[^"]*"','""' -replace '`[^`]*`','``'
    $opens  = ([regex]::Matches($s,'\{')).Count
    $closes = ([regex]::Matches($s,'\}')).Count
    $km = [regex]::Match($s,'^(?:export\s+(?:const|let|var)\s+)?([A-Za-z0-9_$]+|''[^'']*''|"[^"]*")\s*[:=]')
    if($km.Success){
      $kname = $km.Groups[1].Value.Trim("'",'"')
      if(($opens - $closes) -gt 0){
        [void]$stack.Add(@{ n = $kname; d = $depth })
      } else {
        $parts = @($stack | ForEach-Object { $_.n }) + $kname
        $keys += ($parts -join '.')
      }
    }
    $depth += ($opens - $closes)
    if($depth -lt 0){ $parsed = $false; break }
    while($stack.Count -gt 0 -and $stack[$stack.Count-1].d -ge $depth){ $stack.RemoveAt($stack.Count-1) }
  }
  if($depth -ne 0){ $parsed = $false }
  return @{ keys = $keys; dynamic = $dynamic; parsed = $parsed }
}

if($i18nFull -and (Test-Path -LiteralPath $i18nFull) -and $i18nLocales){
  $locales = $i18nLocales -split ',' | ForEach-Object { $_.Trim() }
  $parityFail = @(); $dynamicHits = @()

  if($i18nStyle -eq 'ts_namespace_dirs'){
    # one folder per locale; per-namespace *.ts dictionary files
    $nsSets = @{}
    foreach($loc in $locales){
      $ld = Join-Path $i18nFull $loc
      if(-not (Test-Path -LiteralPath $ld)){ $parityFail += "missing locale dir '$loc'"; continue }
      $nsSets[$loc] = @(Get-ChildItem -LiteralPath $ld -Filter *.ts -File | ForEach-Object { $_.Name } | Sort-Object)
    }
    if($parityFail.Count -eq 0){
      $ref = $locales[0]
      foreach($loc in $locales[1..($locales.Count-1)]){
        $missNs  = @($nsSets[$ref] | Where-Object { $nsSets[$loc] -notcontains $_ })
        $extraNs = @($nsSets[$loc] | Where-Object { $nsSets[$ref] -notcontains $_ })
        if($missNs.Count -gt 0){ $parityFail += "namespace file(s) in $ref missing from ${loc}: $($missNs -join ',')" }
        if($extraNs.Count -gt 0){ $parityFail += "extra namespace file(s) in $loc not in ${ref}: $($extraNs -join ',')" }
      }
      foreach($ns in $nsSets[$ref]){
        $perLocale = @{}
        $nsOk = $true
        foreach($loc in $locales){
          if($nsSets[$loc] -notcontains $ns){ $nsOk = $false; continue }
          $r = Get-TsDictPaths (Join-Path (Join-Path $i18nFull $loc) $ns)
          if(-not $r.parsed){ $parityFail += "malformed dictionary (fails closed): $loc/$ns"; $nsOk = $false; continue }
          if($r.dynamic){ $dynamicHits += "$loc/$ns" }
          $perLocale[$loc] = $r.keys
        }
        if($nsOk){
          foreach($loc in $locales[1..($locales.Count-1)]){
            $miss  = @($perLocale[$ref] | Where-Object { $perLocale[$loc] -notcontains $_ })
            $extra = @($perLocale[$loc] | Where-Object { $perLocale[$ref] -notcontains $_ })
            if($miss.Count -gt 0){ $parityFail += "${ns}: keys in $ref missing from ${loc}: $($miss -join ',')" }
            if($extra.Count -gt 0){ $parityFail += "${ns}: extra keys in $loc not in ${ref}: $($extra -join ',')" }
          }
        }
      }
    }
    if($dynamicHits.Count -gt 0){
      $accepted = $humanAcceptance | Where-Object { $_ -match 'I18N_DYNAMIC_KEYS_ACCEPTED' }
      if(-not $accepted){
        $parityFail += ("dynamic/computed keys cannot be safely flattened (" + (($dynamicHits | Select-Object -Unique) -join ', ') + ") - require explicit I18N_DYNAMIC_KEYS_ACCEPTED in HUMAN_ACCEPTANCE.md")
      }
    }
  } else {
    # flat_json: one <locale>.json per locale
    $keySets = @{}
    foreach($loc in $locales){
      $lp = Join-Path $i18nFull "$loc.json"
      if(-not (Test-Path -LiteralPath $lp)){ $parityFail += "missing locale file $loc.json"; continue }
      try { $keySets[$loc] = @(Get-KeyPaths (Get-Content -LiteralPath $lp -Raw | ConvertFrom-Json) '') }
      catch { $parityFail += "malformed locale file (fails closed): $loc.json" }
    }
    if($parityFail.Count -eq 0 -and $keySets.Count -gt 1){
      $ref = $locales[0]
      foreach($loc in $locales[1..($locales.Count-1)]){
        $diff1 = @($keySets[$ref] | Where-Object { $keySets[$loc] -notcontains $_ })
        $diff2 = @($keySets[$loc] | Where-Object { $keySets[$ref] -notcontains $_ })
        if($diff1.Count -gt 0){ $parityFail += "keys in $ref missing from ${loc}: $($diff1 -join ',')" }
        if($diff2.Count -gt 0){ $parityFail += "keys in $loc missing from ${ref}: $($diff2 -join ',')" }
      }
    }
  }

  if($parityFail.Count -gt 0){ $i18nStatus = 'fail'; Add-Check 'AS6' "i18n parity ($i18nStyle)" 'FAIL' ($parityFail -join '; ') }
  else {
    $dynNote = if($dynamicHits.Count -gt 0){ " (dynamic keys present, explicitly human-accepted)" } else { "" }
    $i18nStatus = 'pass'; Add-Check 'AS6' "i18n parity ($i18nStyle)" 'PASS' ("namespace sets + flattened key paths identical across: " + ($locales -join ', ') + $dynNote)
  }
} else {
  Add-Check 'AS6' 'i18n parity' 'NA' 'no i18n dir in this slice/app tree'
}

# ---------- AS7 charset / ASCII ----------
$asciiViolations = @()
foreach($f in $changed){
  $leaf = Split-Path $f -Leaf
  $match = $false
  foreach($g in $asciiGlobs){ if($leaf -like $g){ $match = $true } }
  if($match){
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $AppRoot ($f -replace '/','\')))
    foreach($b in $bytes){ if($b -gt 127){ $asciiViolations += $f; break } }
  }
}
if($asciiViolations.Count -gt 0){ Add-Check 'AS7' 'Charset (ASCII where required)' 'FAIL' ("non-ASCII bytes in: " + ($asciiViolations -join ', ')) }
else { Add-Check 'AS7' 'Charset (ASCII where required)' 'PASS' "all changed files matching ($($asciiGlobs -join ',')) are ASCII" }

# ---------- AS8 secret-shaped scan ----------
$secretRegexes = @(
  '(?i)(api[_-]?key|secret|password|service_role)\s*[:=]\s*["'']?[A-Za-z0-9+/_\-\.]{16,}',
  'eyJ[A-Za-z0-9_\-]{20,}',
  'sk-[A-Za-z0-9]{20,}',
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
$secretHits = @()
foreach($f in $changed){
  $txt = Get-FileText $f
  foreach($rx in $secretRegexes){ if($txt -match $rx){ $secretHits += "$f" } }
}
$secretStatus = 'pass'
if($secretHits.Count -gt 0){ $secretStatus = 'fail'; Add-Check 'AS8' 'Secret-shaped scan (heuristic)' 'FAIL' ("secret-shaped content in: " + (($secretHits | Select-Object -Unique) -join ', ')) }
else { Add-Check 'AS8' 'Secret-shaped scan (heuristic)' 'PASS' 'no secret-shaped values in changed files (heuristic; NOT complete prevention)' }

# ---------- AS9 dependency drift / DEP-GUARD ----------
$depChanged = @()
foreach($f in ($changed + $deleted)){
  $norm = $f -replace '\\','/'
  foreach($df in $depFiles){ if($norm -eq $df -or $norm -like ('*/' + $df)){ $depChanged += $f } }
}
$depGuardPath = Join-Path $SliceDir 'DEP_GUARD.md'
$depGuardProof = ''
if($depChanged.Count -gt 0){
  if(Test-Path -LiteralPath $depGuardPath){
    $depGuardProof = $depGuardPath
    Add-Check 'AS9' 'Dependency drift vs DEP-GUARD' 'PASS' ("dep files changed (" + ($depChanged -join ', ') + ") WITH DEP_GUARD.md evidence")
  } else {
    Add-Check 'AS9' 'Dependency drift vs DEP-GUARD' 'FAIL' ("dependency/lockfile drift WITHOUT DEP-GUARD evidence: " + ($depChanged -join ', ') + " (RT3 default / RT4 sensitive; approval BEFORE install)")
  }
} else { Add-Check 'AS9' 'Dependency drift vs DEP-GUARD' 'PASS' 'no dependency/package/lockfile change' }

# ---------- AS10 migration detection + rollback proof ----------
$migFiles = @()
foreach($f in $changed){
  $norm = $f -replace '\\','/'
  if($migDir -and $norm -like (($migDir -replace '\\','/') + '/*')){ $migFiles += $f }
  elseif((Get-FileText $f) -match $ddlRegex){ $migFiles += $f }
}
$rollbackPath = Join-Path $SliceDir 'ROLLBACK_PROOF.md'
$rollbackProof = ''
if($migFiles.Count -gt 0){
  if(Test-Path -LiteralPath $rollbackPath){
    $rollbackProof = $rollbackPath
    Add-Check 'AS10' 'Migration detection + rollback proof' 'PASS' ("migration/DDL surface (" + ($migFiles -join ', ') + ") WITH written rollback proof")
  } else {
    Add-Check 'AS10' 'Migration detection + rollback proof' 'FAIL' ("migration/DDL change WITHOUT rollback proof: " + ($migFiles -join ', '))
  }
} else { Add-Check 'AS10' 'Migration detection + rollback proof' 'PASS' 'no migration files or DDL tokens in changed set' }

# ---------- AS11 auth / owner-scope detector ----------
if($authHits.Count -gt 0){
  $hitDesc = ($authHits.GetEnumerator() | ForEach-Object { "$($_.Key) [$($_.Value)]" }) -join '; '
  if($humanAcceptance.Count -gt 0){
    Add-Check 'AS11' 'Auth/owner-scope detector' 'PASS' "auth-sensitive tokens present ($hitDesc) WITH explicit human evidence in HUMAN_ACCEPTANCE.md"
  } else {
    Add-Check 'AS11' 'Auth/owner-scope detector' 'FAIL' "auth-sensitive tokens ($hitDesc) require explicit human evidence (HUMAN_ACCEPTANCE.md missing)"
  }
} else { Add-Check 'AS11' 'Auth/owner-scope detector' 'PASS' 'no auth/ownership risk tokens in changed files' }

# ---------- AS12 fast lane (reduced evidence lane, not reduced authority lane) ----------
$fastEligible = $true; $fastBlockers = @()
foreach($b in $buckets){ if($b -notin @('frontend_ui','docs_only')){ $fastEligible = $false; $fastBlockers += "bucket:$b" } }
foreach($f in $changed){
  $norm = $f -replace '\\','/'
  if($norm -match '(?i)(config|generated|\.gen\.|/routes?/|router|navigation)'){ $fastEligible = $false; $fastBlockers += "path:$f" }
  $txt = Get-FileText $f
  if($txt -match '(?i)(toFixed|NumberFormat|Math\.round|currency|toLocale(Date|Time)?String|parseFloat)'){ $fastEligible = $false; $fastBlockers += "format/round/date/currency:$f" }
}
foreach($d in $deleted){ if($d -match '(?i)(test|spec|__snapshots__)'){ $fastEligible = $false; $fastBlockers += "test-deletion:$d" } }
if($finHits.Count -gt 0 -or $authHits.Count -gt 0){ $fastEligible = $false; $fastBlockers += 'money/auth tokens present' }
if($fastLaneRequested -and -not $fastEligible){
  Add-Check 'AS12' 'RT1/RT2 fast lane guardrails' 'FAIL' ("fast lane REQUESTED but not eligible - blockers: " + (($fastBlockers | Select-Object -Unique) -join '; ') + ". Fast lane reduces evidence, never authority; no bypass.")
} elseif($fastLaneRequested){
  Add-Check 'AS12' 'RT1/RT2 fast lane guardrails' 'PASS' 'fast lane requested AND classifier-proven eligible (cosmetic frontend/docs only); END bundle + human gate still required'
} else {
  Add-Check 'AS12' 'RT1/RT2 fast lane guardrails' 'PASS' "fast lane not requested (eligible=$fastEligible)"
}

# ---------- AS13 command evidence (self-claim guard) ----------
# $cmdEntries + $cmdEvParseError were loaded once near the top (also used by AS4).
if($cmdEvParseError){ Add-Check 'AS13' 'Command evidence' 'FAIL' "command_evidence.json is not valid JSON: $cmdEvParseError" }
$codeChanged = ($buckets | Where-Object { $_ -ne 'docs_only' }).Count -gt 0
$requiredCmds = @()
if($codeChanged -and $cmdTypecheck){ $requiredCmds += 'typecheck' }
if((($buckets -contains 'backend_api') -or ($buckets -contains 'frontend_ui') -or ($buckets -contains 'client_logic')) -and $cmdBuild -and -not ($fastLaneRequested -and $fastEligible)){ $requiredCmds += 'build' }
$cmdProblems = @()
$evNames = @()
foreach($e in $cmdEntries){
  $evNames += $e.name
  foreach($field in @('name','cmd','cwd','exit_code','timestamp','output_path','status')){
    if($null -eq $e.PSObject.Properties[$field]){ $cmdProblems += "entry '$($e.name)' missing field '$field'" }
  }
  if($e.status -eq 'pass' -and $e.exit_code -ne 0){ $cmdProblems += "entry '$($e.name)' claims pass but exit_code=$($e.exit_code)" }
  if($e.output_path){
    $op = $e.output_path
    if(-not (Test-Path -LiteralPath $op)){ $op2 = Join-Path $SliceDir $e.output_path; if(Test-Path -LiteralPath $op2){ $op = $op2 } else { $cmdProblems += "entry '$($e.name)' output artifact not found: $($e.output_path)" } }
  }
}
foreach($rc in $requiredCmds){
  $found = $cmdEntries | Where-Object { $_.name -eq $rc -and $_.status -eq 'pass' -and $_.exit_code -eq 0 }
  if(-not $found){ $cmdProblems += "required command '$rc' has no passing evidence entry (a 'passed' narrative without exit-code evidence does not count)" }
}
if($cmdProblems.Count -gt 0){ Add-Check 'AS13' 'Command evidence (cmd+cwd+exit0+timestamp+artifact)' 'FAIL' ($cmdProblems -join '; ') }
else { Add-Check 'AS13' 'Command evidence (cmd+cwd+exit0+timestamp+artifact)' 'PASS' "required=[$($requiredCmds -join ',')] all backed by exit-code-0 evidence with artifacts" }

# ---------- AS14 client-side-logic verification ----------
$clientMoney = $false
foreach($f in $changed){
  $norm = $f -replace '\\','/'
  if($norm -like 'frontend/*'){
    $txt = Get-FileText $f
    $hasState = $txt -match 'useState|useReducer|reducer\('
    $hasMoney = $false
    foreach($t in $finTokens){ if($txt -match ('(?i)' + [regex]::Escape($t))){ $hasMoney = $true } }
    if($hasState -and $hasMoney){ $clientMoney = $true }
  }
}
$cvPath = Join-Path $SliceDir 'CLIENT_VERIFICATION.md'
$cvKind = 'none'; $cvEvidence = ''; $cvDegraded = $false
if(Test-Path -LiteralPath $cvPath){
  foreach($l in (Get-Content -LiteralPath $cvPath)){
    if($l -match '^KIND:\s*(reducer_function_test|component_unit_test|playwright_browser|manual_browser_proof)'){ $cvKind = $Matches[1] }
    if($l -match '^EVIDENCE:\s*(.+)$'){ $cvEvidence = $Matches[1].Trim() }
  }
}
if($clientMoney){
  if($cvKind -eq 'none'){
    Add-Check 'AS14' 'Client-side money-logic verification' 'FAIL' 'client-side React state touches money logic but no verification evidence (need reducer/unit/Playwright test, or manual proof + human acceptance)'
  } elseif($cvKind -eq 'manual_browser_proof'){
    $cvDegraded = $true
    $accepted = $humanAcceptance | Where-Object { $_ -match 'CLIENT_DEGRADED_ACCEPTED' }
    if($accepted){
      Add-Check 'AS14' 'Client-side money-logic verification' 'PASS' 'manual browser proof = DEGRADED evidence for money-affecting state; explicit human acceptance recorded'
    } else {
      Add-Check 'AS14' 'Client-side money-logic verification' 'FAIL' 'manual browser proof for money-affecting state is DEGRADED evidence and requires explicit CLIENT_DEGRADED_ACCEPTED in HUMAN_ACCEPTANCE.md'
    }
  } else {
    Add-Check 'AS14' 'Client-side money-logic verification' 'PASS' "verified via $cvKind ($cvEvidence)"
  }
} else { Add-Check 'AS14' 'Client-side money-logic verification' 'PASS' 'no client-side money-state surface in changed files' }

# ---------- AS15 custom checks from profile ----------
$customPath = Join-Path $SliceDir 'CUSTOM_CHECKS.md'
$customLines = @()
if(Test-Path -LiteralPath $customPath){ $customLines = @(Get-Content -LiteralPath $customPath) }
$customMissing = @()
$customIds = @()
foreach($cc in $customChecks){
  # 3.1-C (P1-S4): a custom check may be a STRING (legacy 'assert' mode) or an OBJECT declaring
  # mode='invariant_preserved'. For invariant_preserved a bare prose 'id: PASS' line is INSUFFICIENT:
  # only a PASSING command-evidence entry (the behavioral test) satisfies it. This fixes the F1 friction.
  if($cc -is [string]){ $ccId = $cc; $ccMode = 'assert'; $ccTestId = $cc }
  else { $ccId = [string]$cc.id; $ccMode = if($cc.mode){ [string]$cc.mode } else { 'assert' }; $ccTestId = if($cc.test_id){ [string]$cc.test_id } else { $ccId } }
  $customIds += $ccId
  $inFile = $customLines | Where-Object { $_ -match ('^' + [regex]::Escape($ccId) + ':\s*PASS') }
  $inCmd  = $cmdEntries  | Where-Object { $_.name -eq $ccTestId -and $_.status -eq 'pass' -and $_.exit_code -eq 0 }
  if($ccMode -eq 'invariant_preserved'){
    if(-not $inCmd){ $customMissing += "$ccId (invariant_preserved: needs a PASSING command-evidence test '$ccTestId'; a prose 'PASS' does NOT satisfy)" }
  } else {
    if(-not ($inFile -or $inCmd)){ $customMissing += $ccId }
  }
}
if($customMissing.Count -gt 0){ Add-Check 'AS15' 'Profile custom checks all present' 'FAIL' ("custom checks declared by the app profile but absent/unsatisfied: " + ($customMissing -join ', ')) }
else { Add-Check 'AS15' 'Profile custom checks all present' 'PASS' ("profile custom checks all evidenced: " + ($customIds -join ', ')) }

# ---------- AS17 scoped forbidden imports (SCRIPT-ENFORCED; never self-attested) ----------
# Inspects actual import edges in each SCOPED_DENY_IMPORT source: static import, dynamic
# import(), require(). Normalizes case, backslashes and aliases; matches forbidden tokens
# against imported symbol names AND module-specifier last segments. 'index' entries act as the
# conservative barrel blocker (the scoped source may not import any barrel that could
# re-export the forbidden writers). A CUSTOM_CHECKS.md self-attestation can NEVER satisfy or
# bypass this check.
if($scopedDeny.Count -gt 0){
  $as17Problems = @(); $scopedChecked = 0
  foreach($sd in $scopedDeny){
    if($sd -notmatch '^(.+?)\s*=>\s*(.+)$'){ $as17Problems += "malformed SCOPED_DENY_IMPORT directive: $sd"; continue }
    $srcRel = $Matches[1].Trim()
    $targets = @($Matches[2] -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    $srcPath = Join-Path $AppRoot ($srcRel -replace '/','\')
    if(-not (Test-Path -LiteralPath $srcPath)){ continue }
    $scopedChecked++
    $stxt = [System.IO.File]::ReadAllText($srcPath)
    $stxt = [regex]::Replace($stxt,'/\*[\s\S]*?\*/','')
    $stxt = [regex]::Replace($stxt,'(?m)//.*$','')
    $edges = @()
    foreach($m in [regex]::Matches($stxt,'(?m)import\s+(?:type\s+)?([^;]*?)\s+from\s+[''"]([^''"]+)[''"]')){
      $edges += @{ kind='static-import'; symbols=$m.Groups[1].Value; module=$m.Groups[2].Value }
    }
    foreach($m in [regex]::Matches($stxt,'import\s*\(\s*[''"]([^''"]+)[''"]\s*\)')){
      $edges += @{ kind='dynamic-import'; symbols=''; module=$m.Groups[1].Value }
    }
    foreach($m in [regex]::Matches($stxt,'require\s*\(\s*[''"]([^''"]+)[''"]\s*\)')){
      $edges += @{ kind='require'; symbols=''; module=$m.Groups[1].Value }
    }
    foreach($e in $edges){
      $mod = ($e.module.ToLower() -replace '\\','/').TrimEnd('/')
      $lastSeg = ($mod -split '/')[-1] -replace '\.(ts|tsx|js|jsx)$',''
      $symNames = @()
      if($e.symbols){
        $inner = $e.symbols
        if($inner -match '\{([^}]*)\}'){ $inner = $Matches[1] }
        $symNames = @($inner -split ',' | ForEach-Object { (($_ -split '\s+as\s+')[0]).Trim().ToLower() } | Where-Object { $_ })
      }
      foreach($t in $targets){
        if($lastSeg -eq $t){ $as17Problems += "$srcRel $($e.kind) of module '$($e.module)' hits forbidden target '$t'" }
        elseif($symNames -contains $t){ $as17Problems += "$srcRel imports forbidden symbol '$t' from '$($e.module)'" }
      }
    }
  }
  if($as17Problems.Count -gt 0){
    Add-Check 'AS17' 'Scoped forbidden imports (deposit-branch isolation)' 'FAIL' (($as17Problems | Select-Object -Unique) -join '; ')
  } elseif($scopedChecked -eq 0){
    Add-Check 'AS17' 'Scoped forbidden imports (deposit-branch isolation)' 'PASS' 'scoped source files not present in this tree (nothing to inspect)'
  } else {
    Add-Check 'AS17' 'Scoped forbidden imports (deposit-branch isolation)' 'PASS' "$scopedChecked scoped source(s) inspected: no forbidden static/dynamic/require import edges (case/slash/alias-normalized, barrel-blocked)"
  }
} else {
  Add-Check 'AS17' 'Scoped forbidden imports (deposit-branch isolation)' 'NA' 'no SCOPED_DENY_IMPORT directives in profile'
}

# ---------- AS18 producer/validator custody (3.1-F artifact-class separation) ----------
# Custody control (crown jewel: producer/validator separation). Forbids ONE gated slice from
# co-modifying an implementation-class artifact AND a judging-class artifact (constraint / test_harness
# / profile_risk) that grades that slice - i.e. self-grading. A legitimately combined change must be
# split into a separately-gated constraint-edit slice (judging-only changed set + a declared
# CONSTRAINT_EDIT_GATE.md carrying GATE_REF). The class map is the NEO-level authority
# .neo\schema\artifact_classes.json (resolved from this script's own location, NOT from -AppRoot, so an
# app tree cannot supply its own permissive map). FAILS CLOSED: an absent / unparseable / wrong-id class
# map is a FAIL, never a pass. evidence-class files are neutral (neither impl nor judging).
$as18Fail = $null
$CM = $null
$judgeFiles = @()
$implFiles = @()
$gateRef = ''
$neoRootForClasses = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$classMapPath = Join-Path $neoRootForClasses '.neo\schema\artifact_classes.json'
if(-not (Test-Path -LiteralPath $classMapPath)){
  $as18Fail = "artifact class map not found: $classMapPath (producer/validator custody fails closed)"
} else {
  try { $CM = Get-Content -LiteralPath $classMapPath -Raw | ConvertFrom-Json }
  catch { $as18Fail = "artifact class map parse error ($classMapPath): $($_.Exception.Message) (fails closed)" }
}
if((-not $as18Fail) -and ($CM.class_map_schema_id -ne 'neo:artifact_classes')){
  $as18Fail = "class map is not a neo:artifact_classes instance (fails closed): $classMapPath"
}
if((-not $as18Fail) -and (-not $CM.default_class)){
  $as18Fail = "class map missing default_class (fails closed): $classMapPath"
}
if(-not $as18Fail){
  $judgingClasses = @('constraint','test_harness','profile_risk')
  foreach($f in ($changed + $deleted)){
    $norm = ($f -replace '^DELETED:','') -replace '\\','/'
    $leaf = ($norm -split '/')[-1]
    $cls = $CM.default_class
    :ruleLoop foreach($rule in $CM.rules){
      foreach($g in @($rule.globs)){
        $gg = ($g -replace '\\','/')
        if(($norm -like $gg) -or ($leaf -like $gg)){ $cls = $rule.class; break ruleLoop }
      }
    }
    if($judgingClasses -contains $cls){ $judgeFiles += "$norm [$cls]" }
    elseif($cls -eq 'implementation'){ $implFiles += $norm }
    # evidence-class: neutral for the co-modification rule
  }
  $gatePath = Join-Path $SliceDir 'CONSTRAINT_EDIT_GATE.md'
  $gatePresent = Test-Path -LiteralPath $gatePath
  if($gatePresent){ foreach($l in (Get-Content -LiteralPath $gatePath)){ if($l -match '^GATE_REF:\s*(.+)$'){ $gateRef = $Matches[1].Trim() } } }
  if($judgeFiles.Count -gt 0 -and $implFiles.Count -gt 0){
    $as18Fail = ("producer/validator custody VIOLATION: one gated slice co-modifies implementation [" + ($implFiles -join ', ') + "] AND judging artifact(s) [" + ($judgeFiles -join ', ') + "] that grade it (self-grading). Split the judging change into a separately-gated constraint-edit slice.")
  } elseif($judgeFiles.Count -gt 0 -and (-not $gatePresent -or $gateRef -eq '')){
    $as18Fail = ("judging artifact(s) [" + ($judgeFiles -join ', ') + "] changed without a declared CONSTRAINT_EDIT_GATE.md (GATE_REF:<id>): constraint/harness/profile edits must be separately gated, never folded into an implementation slice.")
  }
}
if($as18Fail){
  Add-Check 'AS18' 'Producer/validator custody (artifact-class separation)' 'FAIL' $as18Fail
} elseif($judgeFiles.Count -gt 0){
  Add-Check 'AS18' 'Producer/validator custody (artifact-class separation)' 'PASS' "separately-gated constraint edit: judging-only changed set (" + ($judgeFiles -join ', ') + ") under GATE_REF=$gateRef"
} else {
  Add-Check 'AS18' 'Producer/validator custody (artifact-class separation)' 'PASS' 'no implementation+judging co-modification in changed set'
}

# ---------- smoke (recorded; gating only via fast-lane/test-sufficiency above) ----------
$smokePath = Join-Path $SliceDir 'SMOKE.md'
$smokePerformed = $false; $smokeResult = 'not_performed'; $smokeEvidence = ''
if(Test-Path -LiteralPath $smokePath){
  foreach($l in (Get-Content -LiteralPath $smokePath)){
    if($l -match '^RESULT:\s*(pass|fail)'){ $smokePerformed = $true; $smokeResult = $Matches[1] }
    if($l -match '^EVIDENCE:\s*(.+)$'){ $smokeEvidence = $Matches[1].Trim() }
  }
  if($smokeResult -eq 'fail'){ Add-Check 'AS16' 'Recorded smoke result' 'FAIL' 'SMOKE.md records a FAILING smoke - cannot bundle a failing smoke as green' }
}

# ---------- build evidence bundle ----------
$unresolved = @()
foreach($c in $checks){ if($c.status -eq 'FAIL'){ $unresolved += "$($c.id): $($c.detail)" } }
$evidence = [ordered]@{
  app_slug = $appSlug
  app_name = $appName
  app_root = $AppRoot
  mode = $Mode
  fixture_pre_commit = ($Mode -eq 'fixture' -and $headSha -eq 'FIXTURE-NO-GIT')
  head_sha = $headSha
  branch = $branch
  changed_files = @($changedRaw)
  classification = [ordered]@{
    buckets = @($buckets)
    derived_tier = $derived
    declared_tier = $declaredTier
    fast_lane_requested = $fastLaneRequested
    fast_lane_eligible = $fastEligible
  }
  forbidden_paths_touched = $forbiddenTouched
  authorized_exceptions = @($as4AuthExceptions)
  migrations = [ordered]@{ present = ($migFiles.Count -gt 0); files = @($migFiles); rollback_proof = $rollbackProof; staging_apply_evidence = '' }
  dependency_changes = [ordered]@{ present = ($depChanged.Count -gt 0); files = @($depChanged); dep_guard_proof = $depGuardProof }
  commands = @($cmdEntries | ForEach-Object { [ordered]@{ name=$_.name; cmd=$_.cmd; cwd=$_.cwd; exit_code=[int]$_.exit_code; timestamp=$_.timestamp; output_path=$_.output_path; status=$_.status } })
  i18n_parity = $i18nStatus
  secret_scan = $secretStatus
  smoke = [ordered]@{ performed = $smokePerformed; result = $smokeResult; evidence = $smokeEvidence }
  client_verification = [ordered]@{ required = $clientMoney; kind = $cvKind; evidence = $cvEvidence; degraded = $cvDegraded }
  checks = @($checks | ForEach-Object { [ordered]@{ id=$_.id; name=$_.name; status=$_.status; detail=$_.detail } })
  unresolved_risks = @($unresolved)
  human_acceptance = @($humanAcceptance)
  auditor_findings = @()
  generated_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  generator = 'verify_app_slice.ps1 v2.6'
}
# 3.1 P1-S1 (CF-EVIDENCE-OVERWRITE): never clobber a prior evidence file, and always leave an
# immutable timestamped per-run copy. A failing pre-fix run must survive a later run. The canonical
# $EvidenceOut is still refreshed to the latest run so existing consumers + golden replay read
# byte-identical content (in fixture/replay $EvidenceOut never pre-exists, so no archive is created
# and exactly one canonical + one per-run file are written; replay is unperturbed).
$evJson  = $evidence | ConvertTo-Json -Depth 10
$evDir   = Split-Path -Parent $EvidenceOut
$evBase  = [System.IO.Path]::GetFileNameWithoutExtension($EvidenceOut)
$evExt   = [System.IO.Path]::GetExtension($EvidenceOut)
$runStamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')
# 1) preserve any PRIOR canonical evidence before refreshing it (never overwrite a prior run)
if(Test-Path -LiteralPath $EvidenceOut){
  $priorStamp = (Get-Item -LiteralPath $EvidenceOut).LastWriteTimeUtc.ToString('yyyyMMddTHHmmssfff')
  $archive = Join-Path $evDir ("$evBase.$priorStamp.prior$evExt")
  $n = 0; while(Test-Path -LiteralPath $archive){ $n++; $archive = Join-Path $evDir ("$evBase.$priorStamp.prior_$n$evExt") }
  Move-Item -LiteralPath $EvidenceOut -Destination $archive
}
# 2) write the immutable timestamped per-run evidence (unique; never overwritten)
$perRun = Join-Path $evDir ("$evBase.$runStamp$evExt")
$m = 0; while(Test-Path -LiteralPath $perRun){ $m++; $perRun = Join-Path $evDir ("$evBase.$runStamp`_$m$evExt") }
$evJson | Out-File -LiteralPath $perRun -Encoding ascii
# 3) refresh the canonical latest pointer (existing consumers + golden replay read this)
$evJson | Out-File -LiteralPath $EvidenceOut -Encoding ascii

# ---------- report ----------
Write-Host ""
Write-Host "verify_app_slice: $appSlug  mode=$Mode  tier(declared/derived)=$declaredTier/$derived"
foreach($c in $checks){ Write-Host ("[{0,-4}] {1,-5} {2} - {3}" -f $c.id, $c.status, $c.name, $c.detail) }
Write-Host ""
if($Mode -eq 'fixture'){ Write-Host "[WARN] $fixtureWarning" }
if($script:failCount -gt 0){
  Write-Host "RESULT: RED - $($script:failCount) FAIL. Evidence written to $EvidenceOut (failures recorded as unresolved_risks)."
  exit 1
} else {
  Write-Host "RESULT: GREEN - all applicable checks pass. Evidence: $EvidenceOut"
  exit 0
}
