# orch_govmanifest_suite.ps1 - NEO 4.0-P4-AUTONOMY C1C3-S2b INDEPENDENT
# governance-hash-manifest harness. ASCII-only (D10). Kept SEPARATE from the module.
#
# Proves orch_govmanifest.ps1 fails closed on the C1b I3/NF-2 + V1 + C1c surface:
#   - RULE-DERIVED manifest includes EXACTLY the judging files (impl .py/.txt excluded;
#     orch_*.ps1 / *.schema.json / SKILL.md / NEO_APP_PROFILE.json included).
#   - V1 mandatory-member: a removed/renamed/non-judging mandatory member => BLOCK.
#   - RE-VERIFY: content tamper / member add / member remove / profile-empty => BLOCK.
#   - C1c: a proposed fix on a judging class => BLOCK.
#   - manifest corrupt/unreadable => BLOCK (fail-closed, never treat-as-empty).
#   - clean re-verify (pin==current) => passes (no false mismatch).
#
# S2b-FIX (fail-closed hardening) additions:
#   - F1 junctioned classmap outside governed root => BLOCK PATH_ESCAPE.
#   - F2 right-leaf/wrong-location mandatory member does NOT satisfy => BLOCK.
#   - F3 -MandatoryMembers (renamed from -MandatoryLeaves) is ADDITIVE: @() still
#     enforces the floor; a caller subset never vacates the floor.
#   - F4 pinned manifest schema-validated BEFORE compare (wrong schema_id / class => BLOCK).
#   - F5 duplicate + case-variant rels => BLOCK (ordinal compare, no collapse).
#   - F6 C1c fail-closed tri-state: judging=>BLOCK, exactly 'implementation'=>allow,
#     unknown/typo/blank=>BLOCK C1C_UNKNOWN_CHANGE_CLASS.
#   - F7 unsafe rel + empty members[] => BLOCK.
#
# The real .neo/** is NEVER mutated: every case builds an ISOLATED SCRATCH governed-
# mirror under $env:TEMP (its own .neo\schema\artifact_classes.json copied from the LIVE
# map + .claude marker so Resolve-NeoRoot resolves the mirror). Writes NO AUDIT_RESULT.
# Residue-clean SECOND PASS removes every mirror. exit 0/1.
[CmdletBinding()]
param(
  [string]$ScratchRoot,
  [string]$ProofOut,
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'

$orchDir = Split-Path -Parent $PSScriptRoot   # ...\.neo\scripts\orchestrator
. "$orchDir\orch_govmanifest.ps1"             # dot-sources orch_diff -> orch_io/orch_schema/orch_class/_neo_root

# The LIVE class map (copied verbatim into each scratch mirror so the mirror's oracle
# is byte-identical to the engine's - the derivation rule under test is the real rule).
$liveMap = Join-Path $orchDir '..\..\schema\artifact_classes.json'
$liveMap = [System.IO.Path]::GetFullPath($liveMap)
if (-not (Test-Path -LiteralPath $liveMap -PathType Leaf)) { throw "live class map not found: $liveMap" }

# The LIVE governance_manifest schema (copied into each mirror's .neo\schema so the
# mirror can schema-validate a pinned manifest through Get-NeoSchemaIndex - the F4
# path). Read-only; never edited.
$liveGovSchema = Join-Path $orchDir '..\..\schema\governance_manifest.schema.json'
$liveGovSchema = [System.IO.Path]::GetFullPath($liveGovSchema)
if (-not (Test-Path -LiteralPath $liveGovSchema -PathType Leaf)) { throw "live governance_manifest schema not found: $liveGovSchema" }

if (-not $ScratchRoot) { $ScratchRoot = Join-Path $env:TEMP ('neo_govman_s2b_' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $ScratchRoot) { Remove-Item -Recurse -Force -LiteralPath $ScratchRoot }
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

# ---- result plumbing (mirrors orch_diff_suite framing) ----------------------
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

# ---- scratch governed-mirror builder ----------------------------------------
# Builds a self-contained NEO governed mirror: .neo\schema\artifact_classes.json (copy
# of the LIVE map) + .claude marker + a representative judging + non-judging fileset.
# Returns the mirror root (an absolute path). Everything under $ScratchRoot.
$script:mirrorSeq = 0
function New-NeoGovMirror {
  param([switch]$Bare)
  $script:mirrorSeq++
  $root = Join-Path $ScratchRoot ("mirror{0}" -f $script:mirrorSeq)
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\schema') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.neo\scripts\orchestrator\harness') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\skills\NEO_DIRECTOR') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\skills\NEO_BUILDER')  | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\skills\NEO_AUDITOR')  | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\skills\NEO_SYSTEM')   | Out-Null
  # copy the LIVE class map verbatim (the oracle under test)
  Copy-Item -LiteralPath $liveMap -Destination (Join-Path $root '.neo\schema\artifact_classes.json') -Force
  # copy the LIVE governance_manifest schema so the mirror can schema-validate pins (F4)
  Copy-Item -LiteralPath $liveGovSchema -Destination (Join-Path $root '.neo\schema\governance_manifest.schema.json') -Force
  if ($Bare) { return $root }
  # populate a representative governed fileset.
  #
  # S2b-FIX-2 F1 fallout (pattern-group removal): the mandatory floor is now the
  # EXPLICIT 27-rel set (no existential "at least one per group"; C4 added
  # orch_external.ps1, 24 -> 25; C5 added orch_clarity.ps1, 25 -> 26; INTEGRATE
  # added orch_run.ps1, 26 -> 27). A mirror that is a POSITIVE V1 control must
  # therefore contain EVERY one of the 27 floor rels, or V1 correctly BLOCKS. Plant
  # the full floor below so positive controls stay valid; negative starved cases
  # remove ONE floor rel after building.
  #   JUDGING - THE FULL 27-REL MANDATORY FLOOR (must be INCLUDED + pass V1):
  #   (a) 18 engine scripts (test_harness):
  foreach ($orch in @(
      'orch_auditor_stub.ps1','orch_clarity.ps1','orch_class.ps1','orch_diff.ps1','orch_enforce.ps1',
      'orch_engine.ps1','orch_external.ps1','orch_govmanifest.ps1','orch_io.ps1','orch_loop.ps1','orch_rollover.ps1',
      'orch_run.ps1','orch_router.ps1','orch_schema.ps1','orch_supervisor.ps1','orchestrator.ps1')) {
    Set-Content -LiteralPath (Join-Path $root ".neo\scripts\orchestrator\$orch") -Value "# $orch" -Encoding Ascii
  }
  Set-Content -LiteralPath (Join-Path $root '.neo\scripts\_neo_root.ps1')                        -Value '# _neo_root'         -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\scripts\verify_app_slice.ps1')                 -Value '# verify_app_slice'  -Encoding Ascii
  #   (b) 3 core role bodies (constraint) - ONLY the 3 the classmap registers judging:
  Set-Content -LiteralPath (Join-Path $root '.claude\skills\NEO_DIRECTOR\SKILL.md')              -Value '# director role'    -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.claude\skills\NEO_BUILDER\SKILL.md')               -Value '# builder role'     -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.claude\skills\NEO_AUDITOR\SKILL.md')               -Value '# auditor role'     -Encoding Ascii
  #   (c) constraint/risk (2):
  #       artifact_classes.json already copied above (the live map).
  Set-Content -LiteralPath (Join-Path $root '.neo\NEO_RISK_TIERS.md')                            -Value '# risk tiers'       -Encoding Ascii
  #   (d) 4 core governance/ledger schemas (constraint) - governance_manifest already copied:
  Set-Content -LiteralPath (Join-Path $root '.neo\schema\run_manifest.schema.json')              -Value '{"a":1}'            -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\schema\attempt_ledger_entry.schema.json')      -Value '{"a":1}'            -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\schema\spawn_ledger_entry.schema.json')        -Value '{"a":1}'            -Encoding Ascii
  #   JUDGING but NON-MANDATORY (discovered members - proves optional coverage):
  Set-Content -LiteralPath (Join-Path $root 'NEO_APP_PROFILE.json')                              -Value '{"tokens":["x"]}'   -Encoding Ascii
  #   NON-JUDGING (must be EXCLUDED from the manifest entirely):
  #   NEO_SYSTEM + NEO_QA_SCENARIO role bodies resolve non-judging by design (router +
  #   lazy manager). Present in the mirror, but NOT manifest members, NOT mandatory.
  New-Item -ItemType Directory -Force -Path (Join-Path $root '.claude\skills\NEO_QA_SCENARIO') | Out-Null
  Set-Content -LiteralPath (Join-Path $root '.claude\skills\NEO_SYSTEM\SKILL.md')                -Value '# system router (non-judging)' -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.claude\skills\NEO_QA_SCENARIO\SKILL.md')           -Value '# qa manager (non-judging)'    -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\scripts\some_impl.py')                         -Value 'print(1)'           -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root 'notes.txt')                                         -Value 'hello'              -Encoding Ascii
  Set-Content -LiteralPath (Join-Path $root '.neo\scripts\new_session.ps1')                      -Value '# scaffolder impl'  -Encoding Ascii
  return $root
}
$script:nowTs = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# =============================================================================
# P-S2B-DERIVE : rule-derived manifest includes EXACTLY the judging files
# =============================================================================
$m1 = New-NeoGovMirror
$man1 = Build-NeoGovManifest -GovernedRoot $m1 -DerivedAt $script:nowTs
$rels = @($man1.members | ForEach-Object { $_.rel })
$leaves = @($man1.members | ForEach-Object { ($_.rel -split '/')[-1] })

Expect-Value 'P-S2B-DERIVE-INCL-root'    'True' { [bool]($leaves -contains '_neo_root.ps1') }
Expect-Value 'P-S2B-DERIVE-INCL-vas'     'True' { [bool]($leaves -contains 'verify_app_slice.ps1') }
Expect-Value 'P-S2B-DERIVE-INCL-orchps'  'True' { [bool]($leaves -contains 'orch_engine.ps1') }
Expect-Value 'P-S2B-DERIVE-INCL-schema'  'True' { [bool]($leaves -contains 'run_manifest.schema.json') }
Expect-Value 'P-S2B-DERIVE-INCL-classmap' 'True' { [bool]($leaves -contains 'artifact_classes.json') }
Expect-Value 'P-S2B-DERIVE-INCL-risk'    'True' { [bool]($leaves -contains 'NEO_RISK_TIERS.md') }
Expect-Value 'P-S2B-DERIVE-INCL-profile' 'True' { [bool]($leaves -contains 'NEO_APP_PROFILE.json') }
Expect-Value 'P-S2B-DERIVE-INCL-skill'   'True' { [bool]($leaves -contains 'SKILL.md') }
Expect-Value 'P-S2B-DERIVE-EXCL-py'      'True' { [bool]($leaves -notcontains 'some_impl.py') }
Expect-Value 'P-S2B-DERIVE-EXCL-txt'     'True' { [bool]($leaves -notcontains 'notes.txt') }
Expect-Value 'P-S2B-DERIVE-EXCL-newsess' 'True' { [bool]($leaves -notcontains 'new_session.ps1') }
# every included member resolves a judging class + deterministic (sorted) ordering
$allJudging = @($man1.members | Where-Object { @('constraint','test_harness','profile_risk') -notcontains $_.class })
Expect-Value 'P-S2B-DERIVE-ALL-JUDGING'  '0'    { [string]$allJudging.Count }
$sortedRels = @($rels | Sort-Object -Culture '')
Expect-Value 'P-S2B-DERIVE-SORTED'       'True' { [bool](($rels -join '|') -eq ($sortedRels -join '|')) }

# =============================================================================
# N-S2B-MANDATORY-MISSING : remove a mandatory member => BLOCK
# =============================================================================
$m2 = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $m2 '.neo\scripts\_neo_root.ps1') -Force
$man2 = Build-NeoGovManifest -GovernedRoot $m2 -DerivedAt $script:nowTs
Expect-Block 'N-S2B-MANDATORY-MISSING' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $man2 -GovernedRoot $m2
}
# positive control: full mirror passes V1
Expect-Ok 'P-S2B-MANDATORY-OK' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $man1 -GovernedRoot $m1
}

# =============================================================================
# N-S2B-MANDATORY-NONJUDGING : a mandatory leaf added to the list but resolving
# non-judging => BLOCK (the spec's grounded orch_* example, generalized)
# =============================================================================
Expect-Block 'N-S2B-MANDATORY-NONJUDGING' 'MANDATORY_MEMBER_MISSING' {
  # 'notes.txt' is present in the tree but non-judging; force it mandatory.
  # F3 rename: -MandatoryLeaves -> -MandatoryMembers (additive full-rel). 'notes.txt'
  # is the mirror-root rel of the non-judging file.
  Assert-NeoGovManifestMandatoryMembers -Manifest $man1 -GovernedRoot $m1 -MandatoryMembers @('notes.txt')
}

# =============================================================================
# N-S2B-TAMPER-CONTENT : flip one member's bytes between pin and re-verify => BLOCK
# =============================================================================
$m3 = New-NeoGovMirror
$pin3 = Build-NeoGovManifest -GovernedRoot $m3 -DerivedAt $script:nowTs
Set-Content -LiteralPath (Join-Path $m3 '.neo\scripts\orchestrator\orch_engine.ps1') -Value '# TAMPERED body' -Encoding Ascii
$cur3 = Build-NeoGovManifest -GovernedRoot $m3 -DerivedAt $script:nowTs
Expect-Block 'N-S2B-TAMPER-CONTENT' 'GOVERNANCE_MANIFEST_MISMATCH' {
  Compare-NeoGovManifest -Pinned $pin3 -Current $cur3
}

# =============================================================================
# N-S2B-TAMPER-ADD : a judging member ADDED after pin => BLOCK
# =============================================================================
$m4 = New-NeoGovMirror
$pin4 = Build-NeoGovManifest -GovernedRoot $m4 -DerivedAt $script:nowTs
Set-Content -LiteralPath (Join-Path $m4 '.neo\scripts\orchestrator\orch_added.ps1') -Value '# new judging file' -Encoding Ascii
$cur4 = Build-NeoGovManifest -GovernedRoot $m4 -DerivedAt $script:nowTs
Expect-Block 'N-S2B-TAMPER-ADD' 'GOVERNANCE_MANIFEST_MISMATCH' {
  Compare-NeoGovManifest -Pinned $pin4 -Current $cur4
}

# =============================================================================
# N-S2B-TAMPER-REMOVE : a judging member REMOVED after pin => BLOCK
# =============================================================================
$m5 = New-NeoGovMirror
$pin5 = Build-NeoGovManifest -GovernedRoot $m5 -DerivedAt $script:nowTs
Remove-Item -LiteralPath (Join-Path $m5 '.neo\schema\run_manifest.schema.json') -Force
$cur5 = Build-NeoGovManifest -GovernedRoot $m5 -DerivedAt $script:nowTs
Expect-Block 'N-S2B-TAMPER-REMOVE' 'GOVERNANCE_MANIFEST_MISMATCH' {
  Compare-NeoGovManifest -Pinned $pin5 -Current $cur5
}

# =============================================================================
# N-S2B-PROFILE-EMPTIED : edit NEO_APP_PROFILE.json (judging profile_risk) between
# pin and re-verify => BLOCK MISMATCH (proves re-derive-starvation catch)
# =============================================================================
$m6 = New-NeoGovMirror
$pin6 = Build-NeoGovManifest -GovernedRoot $m6 -DerivedAt $script:nowTs
Set-Content -LiteralPath (Join-Path $m6 'NEO_APP_PROFILE.json') -Value '{"tokens":[]}' -Encoding Ascii
$cur6 = Build-NeoGovManifest -GovernedRoot $m6 -DerivedAt $script:nowTs
Expect-Block 'N-S2B-PROFILE-EMPTIED' 'GOVERNANCE_MANIFEST_MISMATCH' {
  Compare-NeoGovManifest -Pinned $pin6 -Current $cur6
}

# =============================================================================
# N-S2B-C1C : a proposed fix targeting a judging class => BLOCK C1C_JUDGING_FIX_REQUIRED
# =============================================================================
Expect-Block 'N-S2B-C1C-harness'    'C1C_JUDGING_FIX_REQUIRED' { Assert-NeoNoJudgingFix -ChangeClass 'test_harness' -TargetRel '.neo/scripts/orchestrator/orch_engine.ps1' }
Expect-Block 'N-S2B-C1C-constraint' 'C1C_JUDGING_FIX_REQUIRED' { Assert-NeoNoJudgingFix -ChangeClass 'constraint'   -TargetRel '.neo/schema/foo.schema.json' }
Expect-Block 'N-S2B-C1C-profile'    'C1C_JUDGING_FIX_REQUIRED' { Assert-NeoNoJudgingFix -ChangeClass 'profile_risk' -TargetRel 'NEO_APP_PROFILE.json' }
# S2b-FIX F6 fallout: blank ChangeClass now blocks with C1C_UNKNOWN_CHANGE_CLASS
# (fail-closed tri-state), not the pre-fix C1C_JUDGING_FIX_REQUIRED. Blank still BLOCKS.
Expect-Block 'N-S2B-C1C-empty'      'C1C_UNKNOWN_CHANGE_CLASS' { Assert-NeoNoJudgingFix -ChangeClass '' }
# positive control: an implementation-class fix is ALLOWED (no block)
Expect-Ok 'P-S2B-C1C-impl-ok' { Assert-NeoNoJudgingFix -ChangeClass 'implementation' -TargetRel 'app/src/foo.py' }

# =============================================================================
# N-S2B-MANIFEST-CORRUPT : unreadable/invalid pinned manifest => BLOCK (fail-closed)
# =============================================================================
$m7 = New-NeoGovMirror
$cur7 = Build-NeoGovManifest -GovernedRoot $m7 -DerivedAt $script:nowTs
# (a) missing pinned file
$missingPin = Join-Path $ScratchRoot 'no_such_manifest.json'
Expect-Block 'N-S2B-MANIFEST-CORRUPT-missing' 'GOVERNANCE_MANIFEST_MISMATCH' {
  Assert-NeoGovManifestReverify -PinnedPath $missingPin -Current $cur7
}
# (b) invalid JSON pinned file
# S2b-FIX F4 fallout: a parse failure now surfaces reason_code=MANIFEST_CORRUPT
# (dispatch F4 explicitly allows MANIFEST_CORRUPT for parse/read failure); still a
# fail-closed BLOCK, never treat-as-empty.
$badPin = Join-Path $ScratchRoot 'bad_manifest.json'
Set-Content -LiteralPath $badPin -Value '{ this is not json' -Encoding Ascii
Expect-Block 'N-S2B-MANIFEST-CORRUPT-invalid' 'MANIFEST_CORRUPT' {
  Assert-NeoGovManifestReverify -PinnedPath $badPin -Current $cur7
}
# (c) null pinned object directly to Compare => BLOCK (never treat-as-empty)
Expect-Block 'N-S2B-MANIFEST-CORRUPT-null' 'GOVERNANCE_MANIFEST_MISMATCH' {
  Compare-NeoGovManifest -Pinned $null -Current $cur7
}

# =============================================================================
# P-S2B-CLEAN-REVERIFY : identical tree pin==current => passes (no false mismatch)
# =============================================================================
$m8 = New-NeoGovMirror
$pin8 = Build-NeoGovManifest -GovernedRoot $m8 -DerivedAt $script:nowTs
$cur8 = Build-NeoGovManifest -GovernedRoot $m8 -DerivedAt $script:nowTs
Expect-Ok 'P-S2B-CLEAN-REVERIFY' { Compare-NeoGovManifest -Pinned $pin8 -Current $cur8 }
# round-trip through a persisted JSON pin file (validates the on-disk re-verify path)
$pinFile = Join-Path $ScratchRoot 'pinned8.json'
$pin8 | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $pinFile -Encoding Ascii
Expect-Ok 'P-S2B-CLEAN-REVERIFY-file' { Assert-NeoGovManifestReverify -PinnedPath $pinFile -Current $cur8 }

# #############################################################################
# S2b-FIX (GOVMANIFEST FAIL-CLOSED HARDENING) fixtures - each load-bearing.
# #############################################################################

# small helper: a schema-valid governance manifest object from explicit members.
function New-NeoTestManifest {
  param([string]$Root, $MemberList)
  return [pscustomobject]@{
    schema_id     = 'neo:governance_manifest'
    governed_root = $Root
    derived_at    = $script:nowTs
    members       = @($MemberList)
  }
}
$script:hex64 = ('a' * 64)

# =============================================================================
# N-S2BF-CLASSMAP-ESCAPE : a junctioned .neo\schema (classmap outside the
# governed root) => BLOCK PATH_ESCAPE. If junction creation is unavailable
# (no privilege), the case SKIPs (disclosed) rather than false-passing.
# =============================================================================
$mCE = New-NeoGovMirror -Bare
# real target OUTSIDE the mirror holding a planted classmap
$outside = Join-Path $ScratchRoot ('outside_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $outside | Out-Null
Copy-Item -LiteralPath $liveMap -Destination (Join-Path $outside 'artifact_classes.json') -Force
# replace the mirror's .neo\schema dir with a junction to $outside
$schemaDir = Join-Path $mCE '.neo\schema'
Remove-Item -Recurse -Force -LiteralPath $schemaDir
$mkJunctionOk = $true
try { cmd /c mklink /J "$schemaDir" "$outside" | Out-Null }
catch { $mkJunctionOk = $false }
if (-not (Test-Path -LiteralPath (Join-Path $schemaDir 'artifact_classes.json'))) { $mkJunctionOk = $false }
if ($mkJunctionOk) {
  Expect-Block 'N-S2BF-CLASSMAP-ESCAPE' 'PATH_ESCAPE' {
    Get-NeoGovLiveClassMap -GovernedRoot $mCE
  }
} else {
  Record 'N-S2BF-CLASSMAP-ESCAPE' $true 'SKIP: junction creation unavailable (no SeCreateSymbolicLink/privilege) - disclosed' 'skip'
}

# =============================================================================
# N-S2BF-MANDATORY-WRONGLOC : right leaf at the WRONG rel does NOT satisfy the
# floor member => BLOCK (F2 - full-canonical-rel match, not leaf).
# =============================================================================
$mWL = New-NeoGovMirror
# relocate verify_app_slice.ps1 to a WRONG location (right leaf, wrong rel).
Remove-Item -LiteralPath (Join-Path $mWL '.neo\scripts\verify_app_slice.ps1') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $mWL 'app\fixtures') | Out-Null
Set-Content -LiteralPath (Join-Path $mWL 'app\fixtures\verify_app_slice.ps1') -Value '# WRONG LOCATION decoy (still resolves judging by leaf glob)' -Encoding Ascii
$manWL = Build-NeoGovManifest -GovernedRoot $mWL -DerivedAt $script:nowTs
Expect-Block 'N-S2BF-MANDATORY-WRONGLOC' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manWL -GovernedRoot $mWL
}
# positive control: the decoy IS present in the manifest by its wrong rel (proving the
# leaf resolves judging, so ONLY the full-rel match saves us).
Expect-Value 'P-S2BF-WRONGLOC-DECOY-PRESENT' 'True' {
  [bool](@($manWL.members | Where-Object { $_.rel -ceq 'app/fixtures/verify_app_slice.ps1' }).Count -ge 1)
}

# =============================================================================
# N-S2BF-MANDATORY-EMPTY-LIST : -MandatoryMembers @() STILL enforces the floor
# => BLOCK when a floor member is missing (F3 - @() can never vacate the floor).
# =============================================================================
$mEL = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $mEL '.neo\scripts\_neo_root.ps1') -Force
$manEL = Build-NeoGovManifest -GovernedRoot $mEL -DerivedAt $script:nowTs
Expect-Block 'N-S2BF-MANDATORY-EMPTY-LIST' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manEL -GovernedRoot $mEL -MandatoryMembers @()
}

# =============================================================================
# N-S2BF-MANDATORY-SUBSET : caller list ADDS; the floor is STILL checked (F3).
#   (a) caller adds a present judging rel + a floor member missing => BLOCK.
#   (b) full floor intact + caller add present => OK (additive, no false block).
# =============================================================================
$mSS = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $mSS '.neo\NEO_RISK_TIERS.md') -Force   # floor member gone
$manSS = Build-NeoGovManifest -GovernedRoot $mSS -DerivedAt $script:nowTs
Expect-Block 'N-S2BF-MANDATORY-SUBSET-FLOOR' 'MANDATORY_MEMBER_MISSING' {
  # caller adds a present judging member; floor STILL enforced => still BLOCK on the missing floor member.
  Assert-NeoGovManifestMandatoryMembers -Manifest $manSS -GovernedRoot $mSS -MandatoryMembers @('NEO_APP_PROFILE.json')
}
Expect-Ok 'P-S2BF-MANDATORY-SUBSET-OK' {
  # full mirror ($m1): floor intact + caller add (NEO_APP_PROFILE.json) present + judging => OK.
  Assert-NeoGovManifestMandatoryMembers -Manifest $man1 -GovernedRoot $m1 -MandatoryMembers @('NEO_APP_PROFILE.json')
}

# =============================================================================
# N-S2BF-PIN-INVALID-SCHEMA : a pinned manifest with wrong schema_id / invalid
# class => BLOCK on schema validation BEFORE compare (F4).
# =============================================================================
$mPS = New-NeoGovMirror
$curPS = Build-NeoGovManifest -GovernedRoot $mPS -DerivedAt $script:nowTs
# (a) wrong schema_id
$badSchemaPin = Join-Path $ScratchRoot 'pin_wrong_schema.json'
(New-NeoTestManifest -Root ([string]$curPS.governed_root) -MemberList @(
    [pscustomobject]@{ rel = '.neo/scripts/orchestrator/orch_engine.ps1'; class = 'test_harness'; content_hash = $script:hex64 }
)) | ForEach-Object { $_.schema_id = 'neo:NOT_A_MANIFEST'; $_ } |
  ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $badSchemaPin -Encoding Ascii
Expect-Block 'N-S2BF-PIN-INVALID-SCHEMA-id' 'GOVERNANCE_MANIFEST_MISMATCH' {
  Assert-NeoGovManifestReverify -PinnedPath $badSchemaPin -Current $curPS
}
# (b) invalid member class (not one of the 3 judging classes)
$badClassPin = Join-Path $ScratchRoot 'pin_bad_class.json'
(New-NeoTestManifest -Root ([string]$curPS.governed_root) -MemberList @(
    [pscustomobject]@{ rel = '.neo/scripts/orchestrator/orch_engine.ps1'; class = 'implementation'; content_hash = $script:hex64 }
)) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $badClassPin -Encoding Ascii
Expect-Block 'N-S2BF-PIN-INVALID-SCHEMA-class' 'GOVERNANCE_MANIFEST_MISMATCH' {
  Assert-NeoGovManifestReverify -PinnedPath $badClassPin -Current $curPS
}

# =============================================================================
# N-S2BF-DUP-REL : a manifest with a case-EXACT duplicate rel => BLOCK (F5).
# =============================================================================
$dupRoot = [string]$man1.governed_root
$manDup = New-NeoTestManifest -Root $dupRoot -MemberList @(
    [pscustomobject]@{ rel = '.neo/scripts/orchestrator/orch_engine.ps1'; class = 'test_harness'; content_hash = $script:hex64 }
    [pscustomobject]@{ rel = '.neo/scripts/orchestrator/orch_engine.ps1'; class = 'test_harness'; content_hash = ('b' * 64) }
)
Expect-Block 'N-S2BF-DUP-REL' 'DUPLICATE rel' {
  Compare-NeoGovManifest -Pinned $manDup -Current $man1
}

# =============================================================================
# N-S2BF-CASE-VARIANT-REL : two rels differing only by case (A/skill.md vs
# a/SKILL.md) => BLOCK (F5 - no silent case-insensitive collapse).
# =============================================================================
$manCV = New-NeoTestManifest -Root $dupRoot -MemberList @(
    [pscustomobject]@{ rel = 'A/skill.md'; class = 'constraint'; content_hash = $script:hex64 }
    [pscustomobject]@{ rel = 'a/SKILL.md'; class = 'constraint'; content_hash = ('b' * 64) }
)
Expect-Block 'N-S2BF-CASE-VARIANT-REL' 'CASE-VARIANT' {
  Compare-NeoGovManifest -Pinned $manCV -Current $man1
}

# =============================================================================
# N-S2BF-C1C-UNKNOWN : unknown/typo ChangeClass => BLOCK C1C_UNKNOWN_CHANGE_CLASS
# (F6 - no default-open). Blank keeps blocking too.
# =============================================================================
Expect-Block 'N-S2BF-C1C-UNKNOWN'  'C1C_UNKNOWN_CHANGE_CLASS' { Assert-NeoNoJudgingFix -ChangeClass 'UNKNOWN' }
Expect-Block 'N-S2BF-C1C-profile'  'C1C_UNKNOWN_CHANGE_CLASS' { Assert-NeoNoJudgingFix -ChangeClass 'profile' -TargetRel 'NEO_APP_PROFILE.json' }
Expect-Block 'N-S2BF-C1C-wat'      'C1C_UNKNOWN_CHANGE_CLASS' { Assert-NeoNoJudgingFix -ChangeClass 'wat' }
Expect-Block 'N-S2BF-C1C-blank'    'C1C_UNKNOWN_CHANGE_CLASS' { Assert-NeoNoJudgingFix -ChangeClass '   ' }
# positive control: EXACTLY 'implementation' => allow.
Expect-Ok 'P-S2BF-C1C-IMPL' { Assert-NeoNoJudgingFix -ChangeClass 'implementation' -TargetRel 'app/src/foo.py' }

# =============================================================================
# N-S2BF-UNSAFE-REL : a member rel with parent traversal '../x' => BLOCK (F7).
# =============================================================================
$manUnsafe = New-NeoTestManifest -Root $dupRoot -MemberList @(
    [pscustomobject]@{ rel = '../x/orch_engine.ps1'; class = 'test_harness'; content_hash = $script:hex64 }
)
Expect-Block 'N-S2BF-UNSAFE-REL' 'unsafe' {
  Compare-NeoGovManifest -Pinned $manUnsafe -Current $man1
}

# =============================================================================
# N-S2BF-EMPTY-MEMBERS : an EMPTY members[] => BLOCK (F7 - a governed tree
# always has judging members).
# =============================================================================
$manEmpty = New-NeoTestManifest -Root $dupRoot -MemberList @()
Expect-Block 'N-S2BF-EMPTY-MEMBERS' 'EMPTY members' {
  Compare-NeoGovManifest -Pinned $manEmpty -Current $man1
}

# =============================================================================
# P-S2BF-PIN-VALID-SCHEMA : a well-formed pinned manifest round-trips schema
# validation + clean compare (F4 positive - no false block).
# =============================================================================
$mPV = New-NeoGovMirror
$pinPV = Build-NeoGovManifest -GovernedRoot $mPV -DerivedAt $script:nowTs
$curPV = Build-NeoGovManifest -GovernedRoot $mPV -DerivedAt $script:nowTs
$pvFile = Join-Path $ScratchRoot 'pin_valid.json'
$pinPV | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $pvFile -Encoding Ascii
Expect-Ok 'P-S2BF-PIN-VALID-SCHEMA' { Assert-NeoGovManifestReverify -PinnedPath $pvFile -Current $curPV }

# #############################################################################
# S2b-FIX-2 (MANDATORY FLOOR: explicit full-rel, NO existential group) fixtures.
# Closes F1: the mandatory floor was existential/leaf-globbed ("at least one per
# group"), so a tree missing ONE required engine script / role body / schema still
# passed V1. Now every mandatory member is an EXPLICIT FULL CANONICAL REL; a tree
# missing ANY one => BLOCK MANDATORY_MEMBER_MISSING. NEO_SYSTEM + NEO_QA_SCENARIO
# are NON-JUDGING (router + lazy manager) => optional, absence must NOT false-block.
# #############################################################################

# =============================================================================
# N-S2BF2-ENGINE-STARVED : a mirror missing ONE required engine script (others
# present) => BLOCK MANDATORY_MEMBER_MISSING (the existential gap closed - the
# surviving orch_*.ps1 siblings NO LONGER satisfy the floor for the missing one).
# =============================================================================
$mES = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $mES '.neo\scripts\orchestrator\orch_enforce.ps1') -Force
$manES = Build-NeoGovManifest -GovernedRoot $mES -DerivedAt $script:nowTs
Expect-Block 'N-S2BF2-ENGINE-STARVED' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manES -GovernedRoot $mES
}
# prove the surviving siblings ARE still present (so ONLY explicit-rel enforcement blocks)
Expect-Value 'P-S2BF2-ENGINE-STARVED-SIBLINGS' 'True' {
  [bool](@($manES.members | Where-Object { $_.rel -ceq '.neo/scripts/orchestrator/orch_engine.ps1' }).Count -ge 1)
}

# =============================================================================
# N-S2BF2-ROLE-STARVED : a mirror missing ONE core role SKILL.md (NEO_AUDITOR -
# a MANDATORY role body) while the other role bodies remain => BLOCK.
# =============================================================================
$mRS = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $mRS '.claude\skills\NEO_AUDITOR\SKILL.md') -Force
$manRS = Build-NeoGovManifest -GovernedRoot $mRS -DerivedAt $script:nowTs
Expect-Block 'N-S2BF2-ROLE-STARVED' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manRS -GovernedRoot $mRS
}
# sibling role bodies (DIRECTOR/BUILDER) still present - existential would have passed.
Expect-Value 'P-S2BF2-ROLE-STARVED-SIBLINGS' 'True' {
  [bool](@($manRS.members | Where-Object { $_.rel -ceq '.claude/skills/NEO_BUILDER/SKILL.md' }).Count -ge 1)
}

# =============================================================================
# N-S2BF2-SCHEMA-STARVED : a mirror missing ONE core governance schema
# (governance_manifest.schema.json) while other schemas remain => BLOCK.
# =============================================================================
$mSS2 = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $mSS2 '.neo\schema\governance_manifest.schema.json') -Force
$manSS2 = Build-NeoGovManifest -GovernedRoot $mSS2 -DerivedAt $script:nowTs
Expect-Block 'N-S2BF2-SCHEMA-STARVED' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manSS2 -GovernedRoot $mSS2
}
# sibling schemas (run_manifest / ledgers / classmap) still present.
Expect-Value 'P-S2BF2-SCHEMA-STARVED-SIBLINGS' 'True' {
  [bool](@($manSS2.members | Where-Object { $_.rel -ceq '.neo/schema/run_manifest.schema.json' }).Count -ge 1)
}

# =============================================================================
# P-S2BF2-QA-OPTIONAL : a mirror WITHOUT NEO_QA_SCENARIO/SKILL.md but with the
# FULL mandatory floor => PASSES V1 (QA is optional non-judging; no false-block).
# =============================================================================
$mQA = New-NeoGovMirror
$qaPath = Join-Path $mQA '.claude\skills\NEO_QA_SCENARIO\SKILL.md'
if (Test-Path -LiteralPath $qaPath) { Remove-Item -LiteralPath $qaPath -Force }
$manQA = Build-NeoGovManifest -GovernedRoot $mQA -DerivedAt $script:nowTs
Expect-Ok 'P-S2BF2-QA-OPTIONAL' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manQA -GovernedRoot $mQA
}
# ALSO confirm NEO_SYSTEM-absent still passes (both are optional non-judging).
$mSY = New-NeoGovMirror
$syPath = Join-Path $mSY '.claude\skills\NEO_SYSTEM\SKILL.md'
if (Test-Path -LiteralPath $syPath) { Remove-Item -LiteralPath $syPath -Force }
$manSY = Build-NeoGovManifest -GovernedRoot $mSY -DerivedAt $script:nowTs
Expect-Ok 'P-S2BF2-SYSTEM-OPTIONAL' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manSY -GovernedRoot $mSY
}
# and confirm neither NEO_SYSTEM nor NEO_QA_SCENARIO is EVER a manifest member (non-judging)
Expect-Value 'P-S2BF2-SYSTEM-QA-NOT-MEMBERS' 'True' {
  [bool](@($man1.members | Where-Object { $_.rel -like '*NEO_SYSTEM/SKILL.md' -or $_.rel -like '*NEO_QA_SCENARIO/SKILL.md' }).Count -eq 0)
}

# =============================================================================
# P-S2BF2-FLOOR-OK : the FULL 27-rel floor present => passes V1 (no false-block).
# This is the real-tree-shaped positive control for the explicit floor.
# (C4: orch_external.ps1 joined the floor - 24 -> 25, the S3a 23->24 precedent;
# C5: orch_clarity.ps1 joined - 25 -> 26; INTEGRATE: orch_run.ps1 joined - 26 -> 27.)
# =============================================================================
$mFO = New-NeoGovMirror
$manFO = Build-NeoGovManifest -GovernedRoot $mFO -DerivedAt $script:nowTs
Expect-Ok 'P-S2BF2-FLOOR-OK' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manFO -GovernedRoot $mFO
}
# every one of the 27 floor rels is present + judging in a full mirror.
Expect-Value 'P-S2BF2-FLOOR-ALL-27-PRESENT' 'True' {
  $need = @(
    '.neo/scripts/orchestrator/orch_auditor_stub.ps1','.neo/scripts/orchestrator/orch_clarity.ps1',
    '.neo/scripts/orchestrator/orch_class.ps1',
    '.neo/scripts/orchestrator/orch_diff.ps1','.neo/scripts/orchestrator/orch_enforce.ps1',
    '.neo/scripts/orchestrator/orch_engine.ps1','.neo/scripts/orchestrator/orch_external.ps1',
    '.neo/scripts/orchestrator/orch_govmanifest.ps1',
    '.neo/scripts/orchestrator/orch_io.ps1','.neo/scripts/orchestrator/orch_loop.ps1',
    '.neo/scripts/orchestrator/orch_rollover.ps1','.neo/scripts/orchestrator/orch_run.ps1',
    '.neo/scripts/orchestrator/orch_router.ps1','.neo/scripts/orchestrator/orch_schema.ps1',
    '.neo/scripts/orchestrator/orch_supervisor.ps1','.neo/scripts/orchestrator/orchestrator.ps1',
    '.neo/scripts/_neo_root.ps1','.neo/scripts/verify_app_slice.ps1',
    '.claude/skills/NEO_DIRECTOR/SKILL.md','.claude/skills/NEO_BUILDER/SKILL.md',
    '.claude/skills/NEO_AUDITOR/SKILL.md','.neo/schema/artifact_classes.json',
    '.neo/NEO_RISK_TIERS.md','.neo/schema/governance_manifest.schema.json',
    '.neo/schema/run_manifest.schema.json','.neo/schema/attempt_ledger_entry.schema.json',
    '.neo/schema/spawn_ledger_entry.schema.json')
  $have = @($manFO.members | ForEach-Object { [string]$_.rel })
  $missing = @($need | Where-Object { $have -notcontains $_ })
  [bool]($missing.Count -eq 0)
}
# C4 floor-join controls: the new engine module is a floor member (starving it
# BLOCKs) + resolves judging from birth via the existing orch_*.ps1 glob.
$mXS = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $mXS '.neo\scripts\orchestrator\orch_external.ps1') -Force
$manXS = Build-NeoGovManifest -GovernedRoot $mXS -DerivedAt $script:nowTs
Expect-Block 'N-C4-EXTERNAL-STARVED' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manXS -GovernedRoot $mXS
}
Expect-Value 'P-C4-EXTERNAL-FLOOR-MEMBER' 'True' {
  $hit = @($manFO.members | Where-Object { $_.rel -ceq '.neo/scripts/orchestrator/orch_external.ps1' })
  [bool](($hit.Count -eq 1) -and ($hit[0].class -ceq 'test_harness'))
}
# C5 floor-join controls (the C4 precedent, one member later): the new clarity
# module is a floor member (starving it BLOCKs - the 26th member is load-bearing)
# + resolves judging from birth via the existing orch_*.ps1 glob (no classmap edit).
$mXC = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $mXC '.neo\scripts\orchestrator\orch_clarity.ps1') -Force
$manXC = Build-NeoGovManifest -GovernedRoot $mXC -DerivedAt $script:nowTs
Expect-Block 'N-C5-CLARITY-STARVED' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manXC -GovernedRoot $mXC
}
Expect-Value 'P-C5-CLARITY-FLOOR-MEMBER' 'True' {
  $hit = @($manFO.members | Where-Object { $_.rel -ceq '.neo/scripts/orchestrator/orch_clarity.ps1' })
  [bool](($hit.Count -eq 1) -and ($hit[0].class -ceq 'test_harness'))
}
# INTEGRATE floor-join controls (the C4/C5 precedent, one member later): the new
# run-surface module is a floor member (starving it BLOCKs - the 27th member is
# load-bearing) + resolves judging from birth via the existing orch_*.ps1 glob
# (no classmap edit).
$mXR = New-NeoGovMirror
Remove-Item -LiteralPath (Join-Path $mXR '.neo\scripts\orchestrator\orch_run.ps1') -Force
$manXR = Build-NeoGovManifest -GovernedRoot $mXR -DerivedAt $script:nowTs
Expect-Block 'N-INTEGRATE-RUN-STARVED' 'MANDATORY_MEMBER_MISSING' {
  Assert-NeoGovManifestMandatoryMembers -Manifest $manXR -GovernedRoot $mXR
}
Expect-Value 'P-INTEGRATE-RUN-FLOOR-MEMBER' 'True' {
  $hit = @($manFO.members | Where-Object { $_.rel -ceq '.neo/scripts/orchestrator/orch_run.ps1' })
  [bool](($hit.Count -eq 1) -and ($hit[0].class -ceq 'test_harness'))
}

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
    suite     = 'orch_govmanifest_suite'
    slice     = '4.0-P4-AUTONOMY-C1C3-S2b'
    total     = $total
    passed    = $passCount
    failed    = $failed.Count
    skipped   = $skips.Count
    results   = $script:results
    generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  $proof | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ProofOut -Encoding Ascii
}

# residue-clean second pass: remove ALL scratch mirrors, then PROVE the root is gone.
if (-not $KeepScratch) {
  Remove-Item -Recurse -Force -LiteralPath $ScratchRoot -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $ScratchRoot) {
    Write-Host "RESIDUE: scratch root survived cleanup: $ScratchRoot" -ForegroundColor Red
    $failed = @($failed) + [pscustomobject]@{ guard = 'RESIDUE-CLEAN'; pass = $false }
  } else {
    Write-Host "residue-clean: scratch + all mirrors removed" -ForegroundColor Green
  }
}

if ($failed.Count -gt 0) { exit 1 } else { exit 0 }
