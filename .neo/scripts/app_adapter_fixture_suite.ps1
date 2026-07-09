# app_adapter_fixture_suite.ps1 - NEO v2.6 fixture proof harness for the app adapter.
# ASCII-only, PowerShell 5.1.
#
# Builds a self-contained fixture app tree under NEO_SESSION\app_adapter_fixture\, then proves:
#   GREEN: verify_app_slice.ps1 exit 0 AND check_app_end_evidence.ps1 exit 0 on a clean slice.
#   FAIL-CLOSED (verify side, each must exit 1 with the targeted check failing):
#     N01 deny_hit            locked/forbidden file touched            -> AS4
#     N02 residue_token       residue token left in tree               -> AS5
#     N03 dep_no_guard        dep file drift without DEP-GUARD         -> AS9
#     N04 migration_no_rb     migration/DDL without rollback proof     -> AS10
#     N05 client_money        client money state without verification  -> AS14
#     N06 (renamed I1; see i18n block below)
#     N07 secret_residue      secret-shaped value in changed file      -> AS8
#     N08 non_ascii           non-ASCII in ASCII-required file         -> AS7
#     N09 build_claimed       build claimed pass with exit_code 1      -> AS13
#     N10 custom_missing      profile custom check absent              -> AS15
#     N11 fast_lane_bypass    fast lane requested over format logic    -> AS12
#     N12 downgrade           declared tier below derived              -> AS3
#   A-2 additions (i18n ts-dictionary negatives -> AS6; scoped-import negatives -> AS17):
#     N13 deny_glob           changed file under a DENY glob           -> AS4
#     I1  missing nested key in one locale                             -> AS6
#     I2  extra key in one locale                                      -> AS6
#     I3  namespace file missing in one locale                         -> AS6
#     I4  malformed .ts dictionary (fails closed)                      -> AS6
#     I5  dynamic/computed key without human acceptance                -> AS6
#     I5A dynamic key WITH I18N_DYNAMIC_KEYS_ACCEPTED (positive)       -> exit 0
#     M1  direct forbidden symbol import                               -> AS17
#     M2  relative-path forbidden module import                        -> AS17
#     M3  alias (@/) forbidden import                                  -> AS17
#     M4  dynamic import() of forbidden module                         -> AS17
#     M5  barrel re-export bypass (import './index')                   -> AS17
#     M6  case/backslash variation on Windows                          -> AS17
#     M7  self-attested CUSTOM_CHECK cannot bypass enforced check      -> AS17
#   FAIL-CLOSED (checker side, tampered evidence, each must exit 1):
#     C01 stale_sha           fixture_pre_commit forged off            -> E3
#     C02 omitted_file        changed file dropped from evidence       -> E4
#     C03 forged_artifact     pass claim pointing at missing artifact  -> E2
#     C04 unknown_key         schema violation (extra key)             -> E1
#
# A suite proven only on a happy fixture is not proven. Exit 0 only when ALL cases classify.

# 3.1 P1-S4 (BR2): additive -NeoRoot param so the golden driver can exercise a DEV mirror
# (<NEO_ROOT>) without editing any of the 32 frozen cases. DEFAULT stays 'S:\NEO' so the
# golden replay/classification is byte-for-behaviour unperturbed. The profile also resolves under
# -NeoRoot so a dev run uses the dev profile mirror.
param([switch]$KeepArtifacts,[string]$NeoRoot)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$scripts = Join-Path $NeoRoot '.neo\scripts'
$verify  = Join-Path $scripts 'verify_app_slice.ps1'
$checker = Join-Path $scripts 'check_app_end_evidence.ps1'
$profile = Join-Path $NeoRoot 'modules\unified-analytics-rental-platform\NEO_APP_PROFILE.md'
$base    = Join-Path $NeoRoot 'NEO_SESSION\app_adapter_fixture'
$script:failures = 0
$script:results = New-Object System.Collections.ArrayList

function Report([string]$case,[bool]$ok,[string]$detail){
  $tag = if($ok){'PASS'}else{'FAIL'}
  [void]$script:results.Add(("[{0}] {1,-18} {2}" -f $tag,$case,$detail))
  if(-not $ok){ $script:failures++ }
}

function Write-TsDict([string]$Path,[string]$Export,[hashtable]$Flat){
  # $Flat: ordered key -> value; keys with '.' become one level of nesting (a.b only)
  $lines = @("export const $Export = {")
  $groups = @{}
  foreach($k in $Flat.Keys){
    if($k -like '*.*'){
      $p = $k -split '\.',2
      if(-not $groups.ContainsKey($p[0])){ $groups[$p[0]] = @{} }
      $groups[$p[0]][$p[1]] = $Flat[$k]
    } else { $lines += "  ${k}: '$($Flat[$k])'," }
  }
  foreach($g in $groups.Keys){
    $lines += "  ${g}: {"
    foreach($sk in $groups[$g].Keys){ $lines += "    ${sk}: '$($groups[$g][$sk])'," }
    $lines += "  },"
  }
  $lines += "};"
  Set-Content -LiteralPath $Path -Value ($lines -join "`r`n") -Encoding ascii
}

function New-FixtureTree([string]$name){
  $root = Join-Path $base $name
  $app  = Join-Path $root 'app'
  $slice = Join-Path $root 'slice'
  $dirs = @("$app\frontend\src\components","$app\backend\src\logic","$app\database\migrations",$slice)
  foreach($loc in @('en','fr','zh-CN')){ $dirs += "$app\frontend\src\i18n\dictionaries\$loc" }
  foreach($d in $dirs){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
  Set-Content -LiteralPath "$app\frontend\src\components\Banner.tsx" -Value "export const Banner = () => <div>Welcome</div>;" -Encoding ascii
  Set-Content -LiteralPath "$app\frontend\src\components\Footer.tsx" -Value "export const Footer = () => <footer>Contact us</footer>;" -Encoding ascii
  $i18n = "$app\frontend\src\i18n\dictionaries"
  Write-TsDict "$i18n\en\common.ts" 'common' ([ordered]@{ 'greeting'='Hello'; 'menu.home'='Home'; 'menu.about'='About' })
  Write-TsDict "$i18n\fr\common.ts" 'common' ([ordered]@{ 'greeting'='Bonjour'; 'menu.home'='Accueil'; 'menu.about'='A propos' })
  Write-TsDict "$i18n\zh-CN\common.ts" 'common' ([ordered]@{ 'greeting'='NiHao'; 'menu.home'='ZhuYe'; 'menu.about'='GuanYu' })
  Write-TsDict "$i18n\en\house.ts" 'house' ([ordered]@{ 'title'='Houses'; 'state.vacant'='Vacant'; 'state.occupied'='Occupied' })
  Write-TsDict "$i18n\fr\house.ts" 'house' ([ordered]@{ 'title'='Maisons'; 'state.vacant'='Libre'; 'state.occupied'='Occupee' })
  Write-TsDict "$i18n\zh-CN\house.ts" 'house' ([ordered]@{ 'title'='FangWu'; 'state.vacant'='KongZhi'; 'state.occupied'='YiZhu' })
  Set-Content -LiteralPath "$app\backend\src\logic\payments.ts" -Value "// LOCKED financial surface - byte-unchanged" -Encoding ascii
  Set-Content -LiteralPath "$app\backend\src\logic\depositsHeld.ts" -Value "import { recordHeldRow } from './heldRowsStore';`r`nexport const holdRow = (id: string) => recordHeldRow(id);" -Encoding ascii
  Set-Content -LiteralPath "$app\database\migrations\001_init.sql" -Value "-- baseline migration (untouched)" -Encoding ascii
  Set-Content -LiteralPath "$app\package.json" -Value '{"name":"fixture-app","version":"1.0.0"}' -Encoding ascii
  Set-Content -LiteralPath "$slice\CHANGED_FILES.txt" -Value "frontend/src/components/Banner.tsx`r`nfrontend/src/components/Footer.tsx" -Encoding ascii
  Set-Content -LiteralPath "$slice\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT2`r`nFAST_LANE: no" -Encoding ascii
  Set-Content -LiteralPath "$slice\typecheck.log" -Value "tsc --noEmit completed with no errors (fixture artifact)" -Encoding ascii
  Set-Content -LiteralPath "$slice\build.log" -Value "next build completed (fixture artifact)" -Encoding ascii
  $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  $cmdEv = @(
    @{ name='typecheck'; cmd='npm run typecheck'; cwd='frontend'; exit_code=0; timestamp=$ts; output_path='typecheck.log'; status='pass' },
    @{ name='build'; cmd='npm run build'; cwd='frontend'; exit_code=0; timestamp=$ts; output_path='build.log'; status='pass' }
  )
  $cmdEv | ConvertTo-Json | Out-File -LiteralPath "$slice\command_evidence.json" -Encoding ascii
  $cc = @(
    "oldest_first_allocation_untouched: PASS (payments.ts byte-identical to baseline)",
    "locked_dashboard_untouched: PASS (dashboard surface not in changed set)",
    "deposit_confirm_makes_zero_payment_pool_rows: PASS (AC1 fingerprint verified in fixture)",
    "deposits_held_only: PASS (liability isolation verified in fixture)",
    "new_tenant_first_transfer_held: PASS (C10 scenario verified in fixture)",
    "outflow_exact_tenant_stays_ignored: PASS (C11 scenario verified in fixture)"
  )
  Set-Content -LiteralPath "$slice\CUSTOM_CHECKS.md" -Value ($cc -join "`r`n") -Encoding ascii
  return @{ root=$root; app=$app; slice=$slice }
}

function Run-Verify($fx,[string]$evOut){
  $out = (& $verify -AppRoot $fx.app -Profile $profile -SliceDir $fx.slice -EvidenceOut $evOut -Mode fixture *>&1 | Out-String)
  return @{ code=$LASTEXITCODE; out=$out }
}
function Run-Checker([string]$evPath,[string]$sliceDir){
  $out = (& $checker -Evidence $evPath -Profile $profile -SliceDir $sliceDir *>&1 | Out-String)
  return @{ code=$LASTEXITCODE; out=$out }
}
function Expect-VerifyFail([string]$case,$fx,[string]$checkId){
  $ev = Join-Path $fx.root 'APP_END_EVIDENCE.json'
  $r = Run-Verify $fx $ev
  $hit = $r.out -match ('\[' + $checkId + '\s*\]\s*FAIL')
  Report $case (($r.code -eq 1) -and $hit) "expect exit1 + $checkId FAIL; got exit=$($r.code), ${checkId}FailSeen=$hit"
}

if(Test-Path -LiteralPath $base){ Remove-Item -LiteralPath $base -Recurse -Force }
New-Item -ItemType Directory -Force -Path $base | Out-Null

Write-Host "=== app_adapter_fixture_suite (v2.6) ==="

# ---------- GREEN ----------
$fx = New-FixtureTree 'green'
$evPath = Join-Path $fx.root 'APP_END_EVIDENCE.json'
$r = Run-Verify $fx $evPath
Report 'GREEN-verify' ($r.code -eq 0) "expect exit0; got $($r.code)"
if($r.code -eq 0){
  $c = Run-Checker $evPath $fx.slice
  Report 'GREEN-checker' ($c.code -eq 0) "expect exit0; got $($c.code)"
  $warnSeen = $c.out -match 'does not certify external app execution'
  Report 'GREEN-fixture-warn' $warnSeen "fixture non-certification warning emitted=$warnSeen"
} else {
  Report 'GREEN-checker' $false 'skipped: green verify did not pass'
  Write-Host $r.out
}
$greenEvidenceRaw = if(Test-Path -LiteralPath $evPath){ Get-Content -LiteralPath $evPath -Raw } else { '' }
$greenSlice = $fx.slice

# ---------- N01 deny_hit ----------
$fx = New-FixtureTree 'n01_deny'
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "backend/src/logic/payments.ts"
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT4`r`nFAST_LANE: no" -Encoding ascii
Expect-VerifyFail 'N01-deny_hit' $fx 'AS4'

# ---------- N02 residue_token ----------
$fx = New-FixtureTree 'n02_residue'
Add-Content -LiteralPath "$($fx.app)\frontend\src\components\Banner.tsx" -Value "// NEO_SCRATCH_temp marker left behind"
Expect-VerifyFail 'N02-residue_token' $fx 'AS5'

# ---------- N03 dep_no_guard ----------
$fx = New-FixtureTree 'n03_dep'
Set-Content -LiteralPath "$($fx.app)\package.json" -Value '{"name":"fixture-app","version":"1.0.1","dependencies":{"left-pad":"1.0.0"}}' -Encoding ascii
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "package.json"
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT3`r`nFAST_LANE: no" -Encoding ascii
Expect-VerifyFail 'N03-dep_no_guard' $fx 'AS9'

# ---------- N04 migration without rollback ----------
$fx = New-FixtureTree 'n04_mig'
Set-Content -LiteralPath "$($fx.app)\database\migrations\002_add_table.sql" -Value "CREATE TABLE fixture_things (id INT);" -Encoding ascii
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "database/migrations/002_add_table.sql"
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT3`r`nFAST_LANE: no" -Encoding ascii
Expect-VerifyFail 'N04-migration_no_rb' $fx 'AS10'

# ---------- N05 client money state without verification ----------
$fx = New-FixtureTree 'n05_client'
Set-Content -LiteralPath "$($fx.app)\frontend\src\components\Wallet.tsx" -Value "import { useState } from 'react'; export const Wallet = () => { const [balance, setBalance] = useState(0); return <div>{balance}</div>; };" -Encoding ascii
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "frontend/src/components/Wallet.tsx"
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT3`r`nFAST_LANE: no" -Encoding ascii
Expect-VerifyFail 'N05-client_money' $fx 'AS14'

# ---------- N06 renamed to I1 (ts-dictionary i18n negatives live in the I-block below) ----------

# ---------- N07 secret residue ----------
$fx = New-FixtureTree 'n07_secret'
Set-Content -LiteralPath "$($fx.app)\frontend\src\components\Banner.tsx" -Value 'const api_key = "ABCDEF1234567890ABCDEF12"; export const Banner = () => <div>Welcome</div>;' -Encoding ascii
Expect-VerifyFail 'N07-secret' $fx 'AS8'

# ---------- N08 non-ASCII in ASCII-required file ----------
$fx = New-FixtureTree 'n08_ascii'
$ps1Path = "$($fx.app)\tool.ps1"
$bytes = [System.Text.Encoding]::ASCII.GetBytes('Write-Host "caf') + @(0xE9) + [System.Text.Encoding]::ASCII.GetBytes('"')
[System.IO.File]::WriteAllBytes($ps1Path, $bytes)
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "tool.ps1"
Expect-VerifyFail 'N08-non_ascii' $fx 'AS7'

# ---------- N09 build claimed pass with exit 1 ----------
$fx = New-FixtureTree 'n09_build'
$ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$cmdEv = @(
  @{ name='typecheck'; cmd='npm run typecheck'; cwd='frontend'; exit_code=0; timestamp=$ts; output_path='typecheck.log'; status='pass' },
  @{ name='build'; cmd='npm run build'; cwd='frontend'; exit_code=1; timestamp=$ts; output_path='build.log'; status='pass' }
)
$cmdEv | ConvertTo-Json | Out-File -LiteralPath "$($fx.slice)\command_evidence.json" -Encoding ascii
Expect-VerifyFail 'N09-build_claimed' $fx 'AS13'

# ---------- N10 custom check missing ----------
$fx = New-FixtureTree 'n10_custom'
Remove-Item -LiteralPath "$($fx.slice)\CUSTOM_CHECKS.md" -Force
Expect-VerifyFail 'N10-custom_missing' $fx 'AS15'

# ---------- N11 fast lane over formatting logic ----------
$fx = New-FixtureTree 'n11_fastlane'
Set-Content -LiteralPath "$($fx.app)\frontend\src\components\Banner.tsx" -Value "export const Banner = (v) => <div>{v.toFixed(2)}</div>;" -Encoding ascii
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT2`r`nFAST_LANE: yes" -Encoding ascii
Expect-VerifyFail 'N11-fastlane_bypass' $fx 'AS12'

# ---------- N12 classifier downgrade ----------
$fx = New-FixtureTree 'n12_downgrade'
New-Item -ItemType Directory -Force -Path "$($fx.app)\backend\src\util" | Out-Null
Set-Content -LiteralPath "$($fx.app)\backend\src\util\strings.ts" -Value "export const upper = (s: string) => s.toUpperCase();" -Encoding ascii
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "backend/src/util/strings.ts"
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT1`r`nFAST_LANE: no" -Encoding ascii
Expect-VerifyFail 'N12-downgrade' $fx 'AS3'

# ---------- N13 deny GLOB hit ----------
$fx = New-FixtureTree 'n13_denyglob'
New-Item -ItemType Directory -Force -Path "$($fx.app)\frontend\src\components\dashboard" | Out-Null
Set-Content -LiteralPath "$($fx.app)\frontend\src\components\dashboard\Tile.tsx" -Value "export const Tile = () => <div>tile</div>;" -Encoding ascii
Add-Content -LiteralPath "$($fx.slice)\CHANGED_FILES.txt" -Value "frontend/src/components/dashboard/Tile.tsx"
Set-Content -LiteralPath "$($fx.slice)\SLICE_DECLARATION.txt" -Value "DECLARED_TIER: RT4`r`nFAST_LANE: no" -Encoding ascii
Expect-VerifyFail 'N13-deny_glob' $fx 'AS4'

# ---------- I1 missing nested key in one locale ----------
$fx = New-FixtureTree 'i1_missingkey'
Write-TsDict "$($fx.app)\frontend\src\i18n\dictionaries\fr\common.ts" 'common' ([ordered]@{ 'greeting'='Bonjour'; 'menu.home'='Accueil' })
Expect-VerifyFail 'I1-missing_nested' $fx 'AS6'

# ---------- I2 extra key in one locale ----------
$fx = New-FixtureTree 'i2_extrakey'
Write-TsDict "$($fx.app)\frontend\src\i18n\dictionaries\zh-CN\common.ts" 'common' ([ordered]@{ 'greeting'='NiHao'; 'menu.home'='ZhuYe'; 'menu.about'='GuanYu'; 'menu.extra'='DuoYu' })
Expect-VerifyFail 'I2-extra_key' $fx 'AS6'

# ---------- I3 namespace file missing in one locale ----------
$fx = New-FixtureTree 'i3_missingns'
Remove-Item -LiteralPath "$($fx.app)\frontend\src\i18n\dictionaries\fr\house.ts" -Force
Expect-VerifyFail 'I3-missing_namespace' $fx 'AS6'

# ---------- I4 malformed dictionary (fails closed) ----------
$fx = New-FixtureTree 'i4_malformed'
Set-Content -LiteralPath "$($fx.app)\frontend\src\i18n\dictionaries\zh-CN\house.ts" -Value "export const house = {`r`n  title: 'FangWu',`r`n  state: {`r`n    vacant: 'KongZhi',`r`n};" -Encoding ascii
Expect-VerifyFail 'I4-malformed_dict' $fx 'AS6'

# ---------- I5 dynamic key WITHOUT human acceptance ----------
$fx = New-FixtureTree 'i5_dynamic'
Add-Content -LiteralPath "$($fx.app)\frontend\src\i18n\dictionaries\en\common.ts" -Value "export const dyn = {`r`n  [``k`${i}``]: 'v',`r`n};"
Expect-VerifyFail 'I5-dynamic_key' $fx 'AS6'

# ---------- I5A dynamic key WITH explicit acceptance (positive) ----------
$fx = New-FixtureTree 'i5a_dynamic_ok'
Add-Content -LiteralPath "$($fx.app)\frontend\src\i18n\dictionaries\en\common.ts" -Value "export const dyn = {`r`n  [``k`${i}``]: 'v',`r`n};"
Set-Content -LiteralPath "$($fx.slice)\HUMAN_ACCEPTANCE.md" -Value "I18N_DYNAMIC_KEYS_ACCEPTED: Raphael reviewed dynamic dictionary keys (fixture)" -Encoding ascii
$ev5a = Join-Path $fx.root 'APP_END_EVIDENCE.json'
$r5a = Run-Verify $fx $ev5a
Report 'I5A-dynamic_accepted' ($r5a.code -eq 0) "expect exit0 with acceptance; got $($r5a.code)"

# ---------- M1 direct forbidden symbol import ----------
$fx = New-FixtureTree 'm1_direct'
Set-Content -LiteralPath "$($fx.app)\backend\src\logic\depositsHeld.ts" -Value "import { allocateOldestFirst } from './allocators';`r`nexport const x = allocateOldestFirst;" -Encoding ascii
Expect-VerifyFail 'M1-direct_symbol' $fx 'AS17'

# ---------- M2 relative-path forbidden module ----------
$fx = New-FixtureTree 'm2_relative'
Set-Content -LiteralPath "$($fx.app)\backend\src\logic\depositsHeld.ts" -Value "import helper from '../logic/charges';`r`nexport const x = helper;" -Encoding ascii
Expect-VerifyFail 'M2-relative_path' $fx 'AS17'

# ---------- M3 alias forbidden import ----------
$fx = New-FixtureTree 'm3_alias'
Set-Content -LiteralPath "$($fx.app)\backend\src\logic\depositsHeld.ts" -Value "import { suggestAllocation } from '@/logic/paymentsAllocationSuggest';`r`nexport const x = suggestAllocation;" -Encoding ascii
Expect-VerifyFail 'M3-alias' $fx 'AS17'

# ---------- M4 dynamic import of forbidden module ----------
$fx = New-FixtureTree 'm4_dynamic'
Set-Content -LiteralPath "$($fx.app)\backend\src\logic\depositsHeld.ts" -Value "export const load = async () => { const p = await import('./pool'); return p; };" -Encoding ascii
Expect-VerifyFail 'M4-dynamic_import' $fx 'AS17'

# ---------- M5 barrel re-export bypass ----------
$fx = New-FixtureTree 'm5_barrel'
Set-Content -LiteralPath "$($fx.app)\backend\src\logic\depositsHeld.ts" -Value "import { helpers } from './index';`r`nexport const x = helpers;" -Encoding ascii
Expect-VerifyFail 'M5-barrel_bypass' $fx 'AS17'

# ---------- M6 case/backslash variation ----------
$fx = New-FixtureTree 'm6_caseslash'
Set-Content -LiteralPath "$($fx.app)\backend\src\logic\depositsHeld.ts" -Value "import { x } from '.\Pool';`r`nexport const y = x;" -Encoding ascii
Expect-VerifyFail 'M6-case_slash' $fx 'AS17'

# ---------- M7 self-attested custom check cannot bypass the enforced check ----------
$fx = New-FixtureTree 'm7_selfattest'
Set-Content -LiteralPath "$($fx.app)\backend\src\logic\depositsHeld.ts" -Value "import { allocateOldestFirst } from './allocators';`r`nexport const x = allocateOldestFirst;" -Encoding ascii
Add-Content -LiteralPath "$($fx.slice)\CUSTOM_CHECKS.md" -Value "deposit_branch_no_payment_writers: PASS (self-attested - must NOT bypass AS17)"
Expect-VerifyFail 'M7-selfattest_no_bypass' $fx 'AS17'

# ---------- checker-side tamper cases (mutate the GREEN evidence) ----------
if($greenEvidenceRaw -ne ''){
  $tamperDir = Join-Path $base 'tamper'
  New-Item -ItemType Directory -Force -Path $tamperDir | Out-Null

  # C01 stale sha: forge fixture_pre_commit off so head_sha must match a live HEAD (none exists)
  $ev = $greenEvidenceRaw | ConvertFrom-Json
  $ev.fixture_pre_commit = $false
  $p = Join-Path $tamperDir 'c01.json'; $ev | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $greenSlice
  Report 'C01-stale_sha' (($c.code -eq 1) -and ($c.out -match '\[E3 FAIL\]')) "expect exit1 + E3 FAIL; got exit=$($c.code)"

  # C02 omitted changed file
  $ev = $greenEvidenceRaw | ConvertFrom-Json
  $ev.changed_files = @($ev.changed_files | Select-Object -First 1)
  $p = Join-Path $tamperDir 'c02.json'; $ev | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $greenSlice
  Report 'C02-omitted_file' (($c.code -eq 1) -and ($c.out -match '\[E4 FAIL\]')) "expect exit1 + E4 FAIL; got exit=$($c.code)"

  # C03 forged artifact path on a pass claim
  $ev = $greenEvidenceRaw | ConvertFrom-Json
  $ev.commands[0].output_path = 'no_such_artifact.log'
  $p = Join-Path $tamperDir 'c03.json'; $ev | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $greenSlice
  Report 'C03-forged_artifact' (($c.code -eq 1) -and ($c.out -match '\[E2 FAIL\]')) "expect exit1 + E2 FAIL; got exit=$($c.code)"

  # C04 unknown top-level key
  $ev = $greenEvidenceRaw | ConvertFrom-Json
  $ev | Add-Member -NotePropertyName 'sneaky_extra' -NotePropertyValue 'x'
  $p = Join-Path $tamperDir 'c04.json'; $ev | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $p -Encoding ascii
  $c = Run-Checker $p $greenSlice
  Report 'C04-unknown_key' (($c.code -eq 1) -and ($c.out -match '\[E1 FAIL\]')) "expect exit1 + E1 FAIL; got exit=$($c.code)"
} else {
  Report 'C01-C04' $false 'skipped: no green evidence to tamper'
}

# ---------- summary + cleanup ----------
Write-Host ""
foreach($line in $script:results){ Write-Host $line }
Write-Host ""
if(-not $KeepArtifacts){
  Remove-Item -LiteralPath $base -Recurse -Force
  Write-Host "Fixtures removed (NEO_SESSION restored). Use -KeepArtifacts to inspect."
}
if($script:failures -gt 0){
  Write-Host "=== app_adapter_fixture_suite: RED - $($script:failures) case(s) misclassified ==="
  exit 1
}
Write-Host "=== app_adapter_fixture_suite: PASS (green + I5A positive + 19 verify negatives (N/I/M) + 4 checker tamper negatives all classify) ==="
exit 0
