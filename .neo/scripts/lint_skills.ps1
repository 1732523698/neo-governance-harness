<#
  lint_skills.ps1  (NEO v1.1 + v2.0 governance-core + v2.5 hardening + 3.0 Session-8 three-role cutover
                    + 3.0 Session-9 legacy quarantine)
  Entry-layer / token-efficiency / governance lints for the NEO skill system. ASCII-only (PS 5.1 safe).
  Implements:
    E - Routing integrity : NEO_SYSTEM phase->role arrows name only the 3 ACTIVE role skills
        (NEO_DIRECTOR / NEO_BUILDER / NEO_AUDITOR), each exactly once, no self-route, all resolve.
    F - Entry-load sanity : NEO_SYSTEM under the line budget and does not embed role bodies/doctrine.
    G - No duplicated doctrine : the 3 ACTIVE role SKILL.md bodies do not restate
        NEO_DOCTRINE.md headings/phrases.
    H - v2.0 governance core : the 3 app-governance artifacts exist and carry their anchors;
        NEO_SYSTEM routes by tier (references the artifacts + RT1..RT4) but embeds NO artifact body;
        unknown-skill guard allowlists the 3 active roles + NEO_SYSTEM + explicitly restored approved
        managers ($restoredManagers, each a Raphael-gated restoration); anything else FAILS closed -
        any quarantined legacy role or NON-restored manager re-appearing in discovery is a QUARANTINE
        BREACH (the 7 legacy roles + 5 managers were quarantined to .neo\_legacy_quarantine in Session
        9; NEO_QA_SCENARIO restored 2026-07-05, Raphael-gated); no malformed S:\NEO paths;
        DEP-GUARD present; frozen-core integrity (8 v1 scripts + 4 schemas unchanged + the 3 ACTIVE
        role skills pinned).
    ASCII - every non-frozen .ps1 is ASCII-only (frozen v1 scripts are reported, not gated).
  Exit code: 0 if all gating checks PASS, 1 if any gating check FAILs.
  This script edits nothing; it only reads and reports.

  SESSION-8 NOTE: this is the first session to rewrite the router+lint to the 3-role surface. The H6
  ROLE manifest (8->3) is a RE-PIN that requires Raphael's recorded authorization (S2 gate). Until that
  authorization is relayed, the role-manifest SHA values are the AWAITING_REPIN_AUTH sentinel and H6
  FAILS on them by design (integrity not yet pinned). The 8 frozen SCRIPTS + 4 frozen SCHEMAS are NOT
  re-pinned and stay byte-identical. Final full re-pin is Session 11.

  SESSION-9 NOTE: the S8 H6 re-pin authorization was relayed and the 3 promoted SHAs are pinned (H6
  passes). Session 9 QUARANTINES the 7 legacy roles + 5 managers OUT of .claude\skills (moved, not
  deleted, to .neo\_legacy_quarantine). The unknown-skill guard (H4a) is therefore TIGHTENED to the 4
  live folders only; Check G now scans only the 3 active role bodies. No frozen-core change; the 3
  active-role pins are unchanged (no re-pin this session). Final full re-pin is still Session 11.
#>
[CmdletBinding()]
param(
  [string]$NeoRoot,
  [int]$MaxSystemLines = 160
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$fail = 0
function Say-Pass($m){ Write-Host "[PASS] $m" }
function Say-Fail($m){ Write-Host "[FAIL] $m"; $script:fail = 1 }
function Say-Info($m){ Write-Host "[INFO] $m" }

$skillsDir   = Join-Path $NeoRoot ".claude\skills"
$systemSkill = Join-Path $skillsDir "NEO_SYSTEM\SKILL.md"
$doctrine    = Join-Path $NeoRoot ".neo\NEO_DOCTRINE.md"
$scriptsDir  = Join-Path $NeoRoot ".neo\scripts"

# 3.0 three-role surface: the ONLY active, routed roles.
$activeRoles = @("NEO_DIRECTOR","NEO_BUILDER","NEO_AUDITOR")
# Session-9: the 7 legacy roles + 5 managers were QUARANTINED (moved) out of .claude\skills into
# .neo\_legacy_quarantine. They are no longer in the discovery path and are no longer tolerated by the
# unknown-skill guard (H4a) -- any reappearance in .claude\skills now FAILS closed. The legacy folder
# names are retained ONLY as the quarantine set for the residue/no-reappearance check below.
$quarantinedLegacy = @("NEO_PM","NEO_AMBASSADOR","NEO_ORCHESTRATOR","NEO_CODER",
                       "NEO_VERIFIER","NEO_GOVERNOR","NEO_CONTRACT_CHECK")

$frozenScripts = @("ambassador_check.ps1","assemble_auditor_input.ps1","contract_check.ps1",
                   "governor.ps1","new_session.ps1","pm_consistency.ps1","verifier.ps1",
                   "verify_session.ps1")

# Doctrine signature strings that must live ONLY in NEO_DOCTRINE.md (G), not in role bodies.
$docSignatures = @(
  "Authority is scripts and artifacts",
  "Two human gates (START and END)",
  "Roles recommend; the human decides",
  "is the sole human surface",
  "Summarize, never sanitize",
  "Isolation and the hard external boundary",
  "Secret safety",
  "Stop, don't expand",
  "Resumability, and honesty about limits",
  "ASCII-only PowerShell"
)

function Get-Body([string]$path){
  # Return the file text below the closing '---' of YAML frontmatter (or whole file if none).
  $lines = Get-Content -LiteralPath $path
  $fence = 0; $start = 0
  for($i=0; $i -lt $lines.Count; $i++){
    if($lines[$i] -match '^---\s*$'){ $fence++; if($fence -eq 2){ $start = $i+1; break } }
  }
  if($fence -ge 2){ return ($lines[$start..($lines.Count-1)] -join "`n") }
  return ($lines -join "`n")
}

function Test-Ascii([string]$path){
  # True if every byte is <= 0x7F.
  $bytes = [System.IO.File]::ReadAllBytes($path)
  foreach($b in $bytes){ if($b -gt 127){ return $false } }
  return $true
}

Write-Host "=== NEO lint_skills (v1.1 + v2.0 + v2.5 + 3.0-S8 three-role) ==="
Write-Host ("NeoRoot: " + $NeoRoot)
Write-Host ""

# ---------------------------------------------------------------- Check E: routing integrity
Write-Host "-- Check E: routing integrity (phase->role map, 3 active roles) --"
if(-not (Test-Path -LiteralPath $systemSkill)){
  Say-Fail "NEO_SYSTEM/SKILL.md not found at $systemSkill"
} else {
  $sysText = Get-Content -LiteralPath $systemSkill -Raw
  $matches = [regex]::Matches($sysText, '->\s*(NEO_[A-Z_]+)')
  $targets = @()
  foreach($m in $matches){ $targets += $m.Groups[1].Value }
  if($targets.Count -eq 0){ Say-Fail "no '-> NEO_*' routing arrows found in NEO_SYSTEM" }
  foreach($t in $targets){
    if($t -eq "NEO_SYSTEM"){ Say-Fail "routing map points at NEO_SYSTEM itself (router must not route to itself)" }
    elseif($activeRoles -notcontains $t){ Say-Fail "routing map names non-active role '$t' (3.0 routes ONLY to the 3 active roles)" }
    elseif(-not (Test-Path -LiteralPath (Join-Path $skillsDir "$t\SKILL.md"))){ Say-Fail "routing target '$t' has no SKILL.md on disk" }
  }
  foreach($r in $activeRoles){
    $n = ($targets | Where-Object { $_ -eq $r }).Count
    if($n -eq 0){ Say-Fail "active role '$r' is missing from the routing map" }
    elseif($n -gt 1){ Say-Fail "active role '$r' appears $n times in the routing map (must be exactly once)" }
  }
  if($script:fail -eq 0){ Say-Pass ("routing map: " + $targets.Count + " arrows, all 3 active roles present exactly once, all resolve to real skills") }
}
Write-Host ""

# ---------------------------------------------------------------- Check F: entry-load sanity
Write-Host "-- Check F: entry-load sanity (NEO_SYSTEM size + no embedded bodies/doctrine) --"
if(Test-Path -LiteralPath $systemSkill){
  $sysLines = (Get-Content -LiteralPath $systemSkill).Count
  if($sysLines -ge $MaxSystemLines){ Say-Fail "NEO_SYSTEM is $sysLines lines (budget < $MaxSystemLines)" }
  else { Say-Pass "NEO_SYSTEM is $sysLines lines (budget < $MaxSystemLines)" }

  $sysBody = Get-Body $systemSkill
  $bodyMarkers = @("Owns exactly this","Must NOT do (hand off")
  $embedRole = $false
  foreach($mk in $bodyMarkers){ if($sysBody -like "*$mk*"){ Say-Fail "NEO_SYSTEM embeds a role-body section ('$mk') - it must route, not restate"; $embedRole = $true } }
  if([regex]::IsMatch($sysBody, '(?m)^##\s+D\d')){ Say-Fail "NEO_SYSTEM embeds doctrine headings ('## D<n>') - reference NEO_DOCTRINE.md instead"; $embedRole = $true }
  if(-not $embedRole){ Say-Pass "NEO_SYSTEM embeds no role-body sections and no doctrine headings" }
}
Write-Host ""

# ---------------------------------------------------------------- Check G: no duplicated doctrine
Write-Host "-- Check G: no duplicated doctrine in the 3 active role bodies --"
$gHits = 0
foreach($r in $activeRoles){
  $rp = Join-Path $skillsDir "$r\SKILL.md"
  if(-not (Test-Path -LiteralPath $rp)){ Say-Fail "active role file missing: $rp"; continue }
  $body = Get-Body $rp
  foreach($sig in $docSignatures){
    if($body.Contains($sig)){ Say-Fail "$r body restates doctrine: '$sig'"; $gHits++ }
  }
}
if($gHits -eq 0){ Say-Pass "no doctrine signature phrases found in any active role body" }
Write-Host ""

# ---------------------------------------------------------------- ASCII: v1.1 .ps1 must be ASCII
Write-Host "-- Check ASCII: v1.1-created .ps1 is ASCII-only (frozen v1 scripts reported only) --"
$allPs1 = Get-ChildItem -LiteralPath $scriptsDir -Filter *.ps1 -File | Sort-Object Name
foreach($p in $allPs1){
  $isFrozen = $frozenScripts -contains $p.Name
  $ascii = Test-Ascii $p.FullName
  if($isFrozen){
    if($ascii){ Say-Info ("frozen (not gated): " + $p.Name + " - ASCII clean") }
    else      { Say-Info ("frozen (not gated): " + $p.Name + " - contains non-ASCII bytes (pre-existing; read-only this session)") }
  } else {
    if($ascii){ Say-Pass ("v1.1 script ASCII-clean: " + $p.Name) }
    else      { Say-Fail ("v1.1 script has non-ASCII bytes: " + $p.Name) }
  }
}
Write-Host ""

# ---------------------------------------------------------------- Check H: v2.0 governance core
Write-Host "-- Check H: v2.0 governance core (artifacts, tier routing, frozen-core integrity) --"
$neoDir     = Join-Path $NeoRoot ".neo"
$appDoc     = Join-Path $neoDir "NEO_APP.md"
$tiersDoc   = Join-Path $neoDir "NEO_RISK_TIERS.md"
$releaseDoc = Join-Path $neoDir "NEO_RELEASE_DISCIPLINE.md"

# H1 - the three v2.0 artifacts exist
$v2files = [ordered]@{ "NEO_APP.md" = $appDoc; "NEO_RISK_TIERS.md" = $tiersDoc; "NEO_RELEASE_DISCIPLINE.md" = $releaseDoc }
foreach($k in $v2files.Keys){
  if(Test-Path -LiteralPath $v2files[$k]){ Say-Pass "v2.0 artifact present: $k" }
  else { Say-Fail "v2.0 artifact MISSING: $k" }
}

# H2 - each artifact carries its machine-checkable anchors (single source of truth markers)
$anchorReq = [ordered]@{
  $appDoc     = @("ANCHOR:APP-TEMPLATE")
  $tiersDoc   = @("ANCHOR:RT-MATRIX","ANCHOR:RT1","ANCHOR:RT2","ANCHOR:RT3","ANCHOR:RT4")
  $releaseDoc = @("ANCHOR:RELEASE-CORE","ANCHOR:DEP-GUARD")
}
foreach($f in $anchorReq.Keys){
  if(Test-Path -LiteralPath $f){
    $t = Get-Content -LiteralPath $f -Raw
    foreach($a in $anchorReq[$f]){
      if(-not ($t -like "*$a*")){ Say-Fail ("anchor '$a' missing from " + (Split-Path $f -Leaf)) }
    }
  }
}
if(Test-Path -LiteralPath $releaseDoc){
  $rt = Get-Content -LiteralPath $releaseDoc -Raw
  if($rt -like "*DEP-GUARD*"){ Say-Pass "DEP-GUARD present in NEO_RELEASE_DISCIPLINE.md (named DEP-GUARD, not C11)" }
  else { Say-Fail "DEP-GUARD missing from NEO_RELEASE_DISCIPLINE.md" }
}

# H3 - NEO_SYSTEM routes by tier: references all 3 artifacts + RT1..RT4, embeds NO artifact body
if(Test-Path -LiteralPath $systemSkill){
  $sys = Get-Content -LiteralPath $systemSkill -Raw
  $missingRef = @()
  foreach($ref in @("NEO_APP.md","NEO_RISK_TIERS.md","NEO_RELEASE_DISCIPLINE.md","RT1","RT4")){
    if(-not ($sys -like "*$ref*")){ $missingRef += $ref }
  }
  foreach($mr in $missingRef){ Say-Fail "NEO_SYSTEM does not reference '$mr'" }
  if($sys -like "*ANCHOR:*"){ Say-Fail "NEO_SYSTEM contains an artifact ANCHOR token (must reference, not embed bodies)" }
  elseif($missingRef.Count -eq 0){ Say-Pass "NEO_SYSTEM references the 3 artifacts + RT1..RT4 and embeds no artifact body" }
}

# H4 - manager governance (v2.5: STRUCTURAL approved-allowlist). Session-9: the 5 managers were
# QUARANTINED out of .claude\skills (preserved in .neo\_legacy_quarantine, Director-hosted planning
# skills). They are no longer in discovery, so H4b normally finds none present (INFO). H4b is retained
# as defense-in-depth: if a manager folder ever reappears in discovery it is BOTH rejected by the
# tightened H4a (quarantine breach) AND structurally validated here.
$approvedManagers = @("NEO_PRODUCT_SPEC","NEO_QA_SCENARIO","NEO_ENV_MANAGER","NEO_MIGRATION_MANAGER","NEO_RELEASE_MANAGER")

# H4a - unknown-skill guard (Session-9 TIGHTENED; Slice-0b RECONCILED): the discovery path must
# contain ONLY the 3 ACTIVE routed roles (NEO_DIRECTOR/NEO_BUILDER/NEO_AUDITOR) + NEO_SYSTEM (the
# router) + explicitly restored approved managers ($restoredManagers, each a Raphael-gated
# restoration). Managers are Director-hosted PLANNING skills preserved in .neo\_legacy_quarantine,
# NOT in discovery unless explicitly restored; the 7 legacy roles were quarantined the same way.
# ANY other folder -- a quarantined legacy role, a NON-restored manager, or anything else --
# appearing in .claude\skills FAILS closed (no transitional tolerance).
$restoredManagers = @("NEO_QA_SCENARIO")  # each entry REQUIRES a Raphael-gated restoration + gated lint edit (this line IS the record)
$knownFolders = $activeRoles + @("NEO_SYSTEM") + $restoredManagers
$unknownSeen = 0
$reappeared = @()
foreach($d in @(Get-ChildItem -LiteralPath $skillsDir -Directory | ForEach-Object { $_.Name })){
  if($knownFolders -notcontains $d){
    Say-Fail "unknown skill folder '$d' (post-quarantine discovery admits ONLY: 3 active roles + NEO_SYSTEM + explicitly restored approved managers)"; $unknownSeen++
    if(($quarantinedLegacy -contains $d) -or ($approvedManagers -contains $d)){ $reappeared += $d }
  }
}
if($unknownSeen -eq 0){ Say-Pass "unknown-skill guard: .claude\skills contains ONLY allowed folders (3 active roles + NEO_SYSTEM + explicitly restored approved managers: $($restoredManagers -join ', '))" }
if($reappeared.Count -gt 0){ Say-Fail ("QUARANTINE BREACH: quarantined skill(s) reappeared in discovery: " + ($reappeared -join ", ")) }

# H4b - per-manager structural checks (managers are built one at a time; absent = INFO).
$mgrSections = @("## Scope","## Trigger","## Allowed","## Forbidden","## Handoff","## Negative test")
$mgrNegativeReq = [ordered]@{
  "NEO_PRODUCT_SPEC"      = @("write app code","self-approv")
  "NEO_QA_SCENARIO"       = @("runnable evidence","sanitiz")
  "NEO_ENV_MANAGER"       = @("secret value","production environment")
  "NEO_MIGRATION_MANAGER" = @("snapshot","rollback","explicit human approval")
  "NEO_RELEASE_MANAGER"   = @("DEP-GUARD","explicit human approval")
}
$mgrRefReq = [ordered]@{
  "NEO_PRODUCT_SPEC"      = @("NEO_APP.md","NEO_RISK_TIERS.md")
  "NEO_QA_SCENARIO"       = @("NEO_APP.md")
  "NEO_ENV_MANAGER"       = @("NEO_APP.md","NEO_RELEASE_DISCIPLINE.md")
  "NEO_MIGRATION_MANAGER" = @("NEO_RISK_TIERS.md","NEO_RELEASE_DISCIPLINE.md")
  "NEO_RELEASE_MANAGER"   = @("NEO_RELEASE_DISCIPLINE.md")
}
$ssotSignatures = @("ANCHOR:","Evidence required BEFORE any install","| RT1 | reversible") + $docSignatures
$builtManagers = 0
foreach($m in $approvedManagers){
  $mp = Join-Path $skillsDir "$m\SKILL.md"
  if(-not (Test-Path -LiteralPath $mp)){ Say-Info "approved manager not in discovery (quarantined Session-9, Director-hosted): $m"; continue }
  $builtManagers++
  $mraw = Get-Content -LiteralPath $mp -Raw
  $mProblems = @()
  foreach($sec in $mgrSections){ if(-not ($mraw -like "*$sec*")){ $mProblems += "missing section '$sec'" } }
  foreach($ban in @("app code","secret")){
    if(-not ([regex]::IsMatch($mraw,'(?i)'+[regex]::Escape($ban)))){ $mProblems += "Forbidden coverage missing mandatory ban topic '$ban'" }
  }
  foreach($neg in $mgrNegativeReq[$m]){
    if(-not ([regex]::IsMatch($mraw,'(?i)'+[regex]::Escape($neg)))){ $mProblems += "negative test does not cover '$neg'" }
  }
  foreach($ref in $mgrRefReq[$m]){
    if(-not ($mraw -like "*$ref*")){ $mProblems += "does not reference SSOT artifact '$ref'" }
  }
  foreach($sig in $ssotSignatures){
    if($mraw.Contains($sig)){ $mProblems += "restates SSOT/doctrine content ('$sig') - reference, never restate" }
  }
  if(-not ([regex]::IsMatch($mraw,'(?i)governance'))){ $mProblems += "does not declare itself a governance/planning skill" }
  if($mProblems.Count -gt 0){ foreach($pb in $mProblems){ Say-Fail "$m : $pb" } }
  else { Say-Pass "$m structural + negative-test checks pass (governance-only, SSOT referenced not restated)" }
}
Say-Info ("approved managers present in discovery: " + $builtManagers + " / " + $approvedManagers.Count + " (expected: the explicitly restored managers only - " + ($restoredManagers -join ', ') + "; all others quarantined, Director-hosted)")

# H4c - NEO_SYSTEM manager-routing anti-monolith check. After the 3.0 cutover the router hosts no
# '=> NEO_X' manager arrows (managers are Director-hosted). If any are present they must still obey
# the one-at-a-time, pointers-only, no-body rules.
if(Test-Path -LiteralPath $systemSkill){
  $sysRaw = Get-Content -LiteralPath $systemSkill -Raw
  $mgrArrows = @()
  foreach($mm in [regex]::Matches($sysRaw,'=>\s*(NEO_[A-Z_]+)')){ $mgrArrows += $mm.Groups[1].Value }
  if($mgrArrows.Count -eq 0){
    Say-Info "NEO_SYSTEM carries no '=> NEO_*' manager arrows (3.0: managers are NEO_DIRECTOR-hosted, not entry-routed)"
  } else {
    $h4cFail = 0
    foreach($t in $mgrArrows){
      if($approvedManagers -notcontains $t){ Say-Fail "NEO_SYSTEM manager arrow targets non-approved '$t'"; $h4cFail++ }
      elseif(-not (Test-Path -LiteralPath (Join-Path $skillsDir "$t\SKILL.md"))){ Say-Fail "NEO_SYSTEM routes to manager '$t' but its SKILL.md is missing"; $h4cFail++ }
    }
    foreach($m in $approvedManagers){
      $n = @($mgrArrows | Where-Object { $_ -eq $m }).Count
      if($n -gt 1){ Say-Fail "manager '$m' appears $n times in NEO_SYSTEM manager routing (must be at most once)"; $h4cFail++ }
    }
    if([regex]::IsMatch($sysRaw,'(?i)load (all|every) (NEO_|manager)')){ Say-Fail "NEO_SYSTEM contains a load-all-managers instruction"; $h4cFail++ }
    foreach($bodyMark in @("## Negative test","## Handoff")){
      if($sysRaw -like "*$bodyMark*"){ Say-Fail "NEO_SYSTEM embeds a manager-body section ('$bodyMark')"; $h4cFail++ }
    }
    if($h4cFail -eq 0){ Say-Pass ("NEO_SYSTEM manager routing: pointers only, lazy one-at-a-time, no bodies") }
  }
  $sysLineCount = (Get-Content -LiteralPath $systemSkill).Count
  if($sysLineCount -gt 140){ Say-Info "NEO_SYSTEM is $sysLineCount lines ( > 140 target; hard budget < $MaxSystemLines still enforced by Check F)" }
}

# H5 - malformed S:\NEO paths (missing backslash) in v2.0 docs
$pathScan = @($systemSkill, $appDoc, $tiersDoc, $releaseDoc)
$malformed = 0
foreach($f in $pathScan){
  if(Test-Path -LiteralPath $f){
    $t = Get-Content -LiteralPath $f -Raw
    if($t.Contains("NEO.neo") -or $t.Contains("NEO.claude")){ Say-Fail ("malformed S:\NEO path (missing backslash) in " + (Split-Path $f -Leaf)); $malformed++ }
  }
}
if($malformed -eq 0){ Say-Pass "no malformed S:\NEO paths in v2.0 docs" }

# H6 - frozen-core integrity: 8 v1 scripts + 4 schemas unchanged + the 3 ACTIVE role skills pinned.
# The 8 scripts + 4 schemas are NOT re-pinned (byte-identical, carried from prior sessions).
$frozenManifest = [ordered]@{
  ".neo\scripts\ambassador_check.ps1"        = "180D20D7DD3FAE8A7A08236026A2102E09E1C7794EAE15A2B2F7482F6CDB752F"
  ".neo\scripts\assemble_auditor_input.ps1"  = "203C7BA20CEA3B31E034E046F49EE733F227F5094EB14B1DF7B1F06A8DC80AD2"
  ".neo\scripts\contract_check.ps1"          = "BA8483B61FF3BB4A497A16077969ABB7F61B2142AC69AC24C42EEB35060D7D74"
  ".neo\scripts\governor.ps1"                = "9D2CE34D70181ADE0C8E2C1F27050225F16E95C7BB94B005E7AF795D62B30BEB"
  ".neo\scripts\new_session.ps1"             = "E2D5C3F3E5ED1D1A556783356D3207C2419D0252E03E4B4D5CB75A01D87B9BF4"
  ".neo\scripts\pm_consistency.ps1"          = "732E69AEA961DE5D2A8F25FBD79DF6492F8F42EB17CBCBC195E3C71027A568D6"
  ".neo\scripts\verifier.ps1"                = "B97E44E35C520E718751C06DB40EDB84353C15F5609E83608A657DDD10DEFF42"
  ".neo\scripts\verify_session.ps1"          = "29ABE03446B0BCE3A44D13E5E657499FE35933B44D509E3C7D43AA90D14BAC80"
  ".neo\schema\checkpoint.schema.json"       = "6C836D0CCA7AD6B98D6F05814D19B0B237EDFF65B2D86D2048639CB0C45F89A3"
  ".neo\schema\module_contract.schema.json"  = "928A98973B31B1271B44499009778A0F13C1243EE3410C2106A85081270E7C5B"
  ".neo\schema\residue_report.schema.json"   = "423F4F375E9F75D5B9C74D87AEEE85BE2C294F6B0F187ABC38AC52AAD14930DE"
  ".neo\schema\session_contract.schema.json" = "07957079AEFC1A8D8B38C1D5D68FBCAA13B59C714DEC7DFD6D6E2E8CEC324ACF"
}
# ----- 3.0 ROLE manifest (3 active). Session-8 pinned the 8->3 re-pin; Session-11 (final acceptance)
# re-pinned the 3 role bodies after the CF-S8-HEADER cosmetic cleanup (removed "(3.0 staged draft)"
# from each H1 title - cosmetic-only, Check G intact). Final pin authorized by Raphael via session
# control, 2026-06-27. The AWAITING_REPIN_AUTH sentinel is retained so any future de-pin fails closed.
$REPIN_SENTINEL = "AWAITING_REPIN_AUTH"
$roleManifest = [ordered]@{
  "NEO_DIRECTOR" = "90BB4F3774E3790A3510F39AFD04555E18D1BEEBC80C2E4D2EFB939A754E8715"
  "NEO_BUILDER"  = "C2F1C6D3D845580817508706786AB80AED6D63E4B2FD9C4FBAF69A76AF569121"
  "NEO_AUDITOR"  = "F3C69822205B48371B4CB36EA125AE44AB6FAD9F7ACC23C57D09ACD77CA11D26"
}
# ----- 3.0 Session-11 PROMOTED manifest: previously inventory-asserted / provisional / CF-UNPINNED
# artifacts promoted to mechanical SHA-256 enforcement (final pin authorized by Raphael via session
# control, 2026-06-27). Checked exactly like $frozenManifest. lint_skills.ps1 itself is RECORD-ONLY
# (self-pin is circular) and recorded in .neo\_v3.0\session11\FINAL_PIN_RECORD.md, not here.
$promotedManifest = [ordered]@{
  ".neo\schema\NEO_APP_PROFILE.schema.json"                 = "43026F99CB22E04BFAA35A03BE47FFDDF16124D3B3A734B31B18BE8DEA74F1D9"
  ".neo\schema\app_end_evidence.schema.json"                = "9BB87D44B8FFD5577C6ECCEEC9810C90CF48EC4CC9CC1031FFC14EF7D6F581D2"
  ".neo\schema\artifact_classes.json"                       = "2FB1615E5CA36625F6CE9596CE4144CEB84C13BE7C84BD7DE201708196BE060B"
  ".neo\schema\artifact_provenance.json"                    = "7F017F1C276D51EB6B899898296BEE30D2BDF061EB03BC052AF4A1507DB759CB"
  ".neo\scripts\_neo_root.ps1"                              = "F297C714764CC30B498B8163207E04410D38B74EF13E462114EA251E7AB52036"
  ".neo\scripts\verify_app_slice.ps1"                       = "E6A9A6EED034B846A263F37045F7012263A9D1C68C86D128AADEF8D5BA89AD00"
  ".neo\scripts\check_app_end_evidence.ps1"                 = "A778D58B139D450A200808CA366E56AA5691D527F103FD9BBDB6FC419B79EB87"
  ".neo\scripts\slice_bundle_tool.ps1"                      = "C7F22E9BDF7494DC3FBB3AF825BEEC1BDB8F3E0DE988E008725A79F37774B550"
  ".neo\scripts\custody_fixture_suite.ps1"                  = "38F1EC29F9A69A382714F3C5009BAC6CA31D28DB61377F7D876250B955575CC0"
  ".neo\scripts\role_governance_fixture_suite.ps1"          = "D3FEDC6EE9FF75E5D9E73AE6B63D5A8418489CA82B25209B42AA346B080C8F28"
  ".neo\scripts\app_adapter_fixture_suite.ps1"              = "DCC1EEC8B06DCF864BB7F009631CA41E4C709E7A6064808FBAF2BE2D429902A1"
  ".neo\_legacy_quarantine\NEO_AMBASSADOR\SKILL.md"         = "89E3FDD5FBC9429BD19381ACEAC218C0C08EC8E13820905971DB5E93382B5CE3"
  ".neo\_legacy_quarantine\NEO_CODER\SKILL.md"              = "782A0893AE73647359EF71B1981AE19DD7CDCC410A38521BED73A7AD7CC568A3"
  ".neo\_legacy_quarantine\NEO_CONTRACT_CHECK\SKILL.md"     = "A29B6287B77C2E804051DD7130D4849E395666B4772225EC5ACD091BB3FD6373"
  ".neo\_legacy_quarantine\NEO_ENV_MANAGER\SKILL.md"        = "A538262661169D2137CBAEDCCC72666923A8A99A956FC805CB4E67F5CBDF7836"
  ".neo\_legacy_quarantine\NEO_GOVERNOR\SKILL.md"           = "5563274FCAA88014A06F06E77474D7A678296E7CF987A202E420E719E82C445F"
  ".neo\_legacy_quarantine\NEO_MIGRATION_MANAGER\SKILL.md"  = "CF768CFFDC7E25A789D7DD3F542205764F34B9C1AEBB50EFB64776CB5EDFB52F"
  ".neo\_legacy_quarantine\NEO_ORCHESTRATOR\SKILL.md"       = "5CC6EC9575932DC8B97F6F674A680E2F3A487B7F42153611B578D0EBA244DBFA"
  ".neo\_legacy_quarantine\NEO_PM\SKILL.md"                 = "056C30AD55EC512A56011F97975F39FAE988018DF59FE99697649262736968F1"
  ".neo\_legacy_quarantine\NEO_PRODUCT_SPEC\SKILL.md"       = "4860DB560F605AC78C936FB6BF45445A429EFA193510DABD6FE5D9077760B0DE"
  ".neo\_legacy_quarantine\NEO_QA_SCENARIO\SKILL.md"        = "945F54463DA8034D572AB82309AE117C39B9E441AD32227440AFF9AC67D8E7EC"
  ".neo\_legacy_quarantine\NEO_RELEASE_MANAGER\SKILL.md"    = "F6745C0EFFE3CD63C976FC8387ABF855C9BD49F0637E3D42FC2468410E85B141"
  ".neo\_legacy_quarantine\NEO_VERIFIER\SKILL.md"           = "A0361DFB03BC6AE6832649098A3926C3BE75C443637CA545A39A4C7A7FEE5F47"
}
$intFail = 0
foreach($rel in $frozenManifest.Keys){
  $full = Join-Path $NeoRoot $rel
  if(-not (Test-Path -LiteralPath $full)){ Say-Fail "frozen file missing: $rel"; $intFail++; continue }
  $h = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
  if($h -ne $frozenManifest[$rel]){ Say-Fail "frozen file CHANGED (SHA-256 mismatch): $rel"; $intFail++ }
}
foreach($r in $roleManifest.Keys){
  $full = Join-Path $skillsDir "$r\SKILL.md"
  if(-not (Test-Path -LiteralPath $full)){ Say-Fail "active role skill missing: $r"; $intFail++; continue }
  if($roleManifest[$r] -eq $REPIN_SENTINEL){ Say-Fail "H6 role manifest AWAITING re-pin authorization (S2 gate): $r not yet pinned (3.0 8->3 re-pin)"; $intFail++; continue }
  $h = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
  if($h -ne $roleManifest[$r]){ Say-Fail "active role skill CHANGED (SHA-256 mismatch): $r"; $intFail++ }
}
foreach($rel in $promotedManifest.Keys){
  $full = Join-Path $NeoRoot $rel
  if(-not (Test-Path -LiteralPath $full)){ Say-Fail "promoted file missing: $rel"; $intFail++; continue }
  $h = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
  if($h -ne $promotedManifest[$rel]){ Say-Fail "promoted file CHANGED (SHA-256 mismatch): $rel"; $intFail++ }
}
Say-Info "custody: the 7 legacy roles + 5 managers were QUARANTINED to .neo\_legacy_quarantine (Session-9); out of discovery. Session-11 (final acceptance) SHA-256-pinned all 12 archived SKILL.md in the promoted manifest."
if($intFail -eq 0){ Say-Pass "frozen-core integrity: 8 scripts + 4 schemas unchanged + 3 active role skills + 22 promoted artifacts (4 schemas + 3 engine + 3 suites/producer + 12 archive) SHA-256 pinned" }
Write-Host ""

# ---------------------------------------------------------------- Check I: v2.5 Phase B additions
Write-Host "-- Check I: v2.5 session-packet templates + permanent C1 golden matrix --"
$templatesDir = Join-Path $NeoRoot ".neo\templates"
foreach($tn in @("start_packet.template.md","closeout_packet.template.md")){
  $tp = Join-Path $templatesDir $tn
  if(-not (Test-Path -LiteralPath $tp)){ Say-Fail "v2.5 template MISSING: $tn" }
  elseif((Get-Item -LiteralPath $tp).Length -lt 200){ Say-Fail "v2.5 template suspiciously small (<200 bytes): $tn" }
  else { Say-Pass "v2.5 template present: $tn" }
}
$gmPath = Join-Path $scriptsDir "c1_golden_matrix.ps1"
if(Test-Path -LiteralPath $gmPath){ Say-Pass "permanent C1 golden matrix present: c1_golden_matrix.ps1" }
else { Say-Fail "permanent C1 golden matrix MISSING: c1_golden_matrix.ps1" }
Write-Host ""

# ---------------------------------------------------------------- result
if($script:fail -eq 0){ Write-Host "=== lint_skills: ALL GATING CHECKS PASS ==="; exit 0 }
else { Write-Host "=== lint_skills: FAIL (see [FAIL] lines above) ==="; exit 1 }
