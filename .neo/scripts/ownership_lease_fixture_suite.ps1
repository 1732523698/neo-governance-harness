# ownership_lease_fixture_suite.ps1 - NEO 3.1 P1-S6 permanent negative-fixture suite for the section 4.8
# ownership lease (ownership_lease.ps1). ASCII-only, PowerShell 5.1. Sibling to custody_fixture_suite.ps1
# (same self-clean discipline).
#
# Makes the lease's fail-closed + mutual-exclusion behavior into STANDING regression tests. It edits NO
# engine/lint/frozen file and never touches the REAL .neo\gates\OWNERSHIP_LEASE.json - only fixture copies
# under NEO_SESSION\lease_fixture. Uses UNIQUE fresh scope ids per case so OS mutex names never collide.
#
# Cases (L-numbers per the P1-S6 plan):
#   L1a CORE file-level:  A holds scope -> B acquire same scope REFUSED
#   L1b CORE REAL OS:     two child PROCESSES race the SAME fresh scope's mutex -> exactly ONE acquires
#   L1c CONTROL no-mutex: same race WITHOUT the mutex (raw TOCTOU) -> BOTH believe-acquire (double-acquire)
#                         => proves the OS mutex is what prevents L1b's double-acquire
#   L2  unheld edit:      check by a non-holder -> refused (must hold the lease before editing)
#   L3a expired reclaim:  an EXPIRED lease is reclaimable by a new holder + LOGGED (reclaimed_from)
#   L3b live not-stolen:  a LIVE lease -> acquire REFUSED and reclaim REFUSED (no silent steal, no deadlock)
#   L4a tampered file:    malformed lease file -> acquire fail-closed
#   L4b wrong schema:     wrong ownership_lease_schema_id -> acquire fail-closed
#   L4c tamper fails-CLOSED not open: malformed file + two concurrent acquirers -> BOTH refused (no sneak-through)
#   L5a disjoint parallel: two DISJOINT scopes acquired concurrently by different holders -> both succeed
#   L5b GOVERNED-ROOT:    GOVERNED-ROOT is exclusive against any sub-scope (both directions)
#   L4d (DESIGN-DEFERRED): a well-formed FORGED lease entry is indistinguishable from a real one at the file
#                         layer (tamper-evident only); non-forgeability is Option A / S7. Recorded, not counted.
#
# Exit 0 only when every enforced case classifies as expected AND residue is clean.

param([switch]$KeepArtifacts,[string]$NeoRoot)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_neo_root.ps1"
if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
$ol       = Join-Path $NeoRoot '.neo\scripts\ownership_lease.ps1'
$srcLease = Join-Path $NeoRoot '.neo\gates\OWNERSHIP_LEASE.json'
$base     = Join-Path $NeoRoot 'NEO_SESSION\lease_fixture'

$script:failures = 0
$script:passes   = 0
$script:deferred = 0
$script:results  = New-Object System.Collections.ArrayList

function Report([string]$case,[bool]$ok,[string]$detail){
  $tag = if($ok){'PASS'}else{'FAIL'}
  [void]$script:results.Add(("[{0}] {1,-22} {2}" -f $tag,$case,$detail))
  if($ok){ $script:passes++ } else { $script:failures++ }
}
function ReportDeferred([string]$case,[string]$detail){
  [void]$script:results.Add(("[DESIGN-DEFERRED] {0,-22} {1}" -f $case,$detail)); $script:deferred++
}
function Fresh(){ return ('sc_' + [guid]::NewGuid().ToString('N').Substring(0,12)) }
function New-LeaseCopy([string]$name){
  $p = Join-Path $base ($name + '.json')
  Copy-Item -LiteralPath $srcLease -Destination $p -Force
  Set-ItemProperty -LiteralPath $p -Name IsReadOnly -Value $false
  return $p
}
function IsoOff([int]$min){ return ([DateTime]::UtcNow.AddMinutes($min)).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ') }
function Write-LeaseFile([string]$path,$entries){
  $lines = @('{','  "ownership_lease_schema_id": "neo:ownership_lease",','  "root_of_trust": "provisional-dev",','  "note": "fixture lease file",')
  $arr = @($entries)
  if($arr.Count -eq 0){ $lines += '  "leases": []' }
  else { $el = @($arr | ForEach-Object { '    ' + ($_ | ConvertTo-Json -Depth 6 -Compress) }); $lines += ('  "leases": [' + "`r`n" + ($el -join ",`r`n") + "`r`n  ]") }
  $lines += '}'
  Set-Content -LiteralPath $path -Value ($lines -join "`r`n") -Encoding ascii
}
function OL([string[]]$a){
  $h = @{}; for($i=0; $i -lt $a.Count; $i += 2){ $h[[string]$a[$i].TrimStart('-')] = $a[$i+1] }
  & $ol @h *>$null; return $LASTEXITCODE
}
function Count-Scope([string]$path,[string]$scope){
  $d = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  return @(@($d.leases) | Where-Object { $_.scope -eq $scope }).Count
}
function Holder-Of([string]$path,[string]$scope){
  $d = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  $e = @(@($d.leases) | Where-Object { $_.scope -eq $scope }) | Select-Object -First 1
  if($e){ return [string]$e.holder } else { return '<none>' }
}

if(-not (Test-Path -LiteralPath $ol)){ Write-Host "FATAL: ownership_lease.ps1 not found at $ol"; exit 1 }
if(Test-Path -LiteralPath $base){ Remove-Item -LiteralPath $base -Recurse -Force }
New-Item -ItemType Directory -Force -Path $base | Out-Null
Write-Host "=== ownership_lease_fixture_suite (P1-S6 section 4.8) NeoRoot=$NeoRoot ==="

# ---------- L1a CORE file-level: held scope -> 2nd acquire refused ----------
$lf = New-LeaseCopy 'l1a'; $s = Fresh
$e1 = OL @('-Action','acquire','-Scope',$s,'-Holder','A','-LeaseFile',$lf,'-TtlMinutes','60')
$e2 = OL @('-Action','acquire','-Scope',$s,'-Holder','B','-LeaseFile',$lf)
Report 'L1a-held_refuses_2nd' (($e1 -eq 0) -and ($e2 -eq 1) -and ((Holder-Of $lf $s) -eq 'A')) "A acquire=$e1(want0), B acquire=$e2(want1), holder=$(Holder-Of $lf $s)(wantA)"

# ---------- L1b CORE REAL OS: two child processes race the SAME fresh scope's mutex ----------
$lf = New-LeaseCopy 'l1b'; $s = Fresh
$startTicks = ([DateTime]::UtcNow.AddSeconds(2)).Ticks
$sb = { param($olPath,$scope,$holder,$leaseFile,$st)
  while([DateTime]::UtcNow.Ticks -lt $st){ Start-Sleep -Milliseconds 3 }
  & $olPath -Action acquire -Scope $scope -Holder $holder -LeaseFile $leaseFile -TtlMinutes 60 *>$null
  $LASTEXITCODE }
$j1 = Start-Job -ScriptBlock $sb -ArgumentList $ol,$s,'P1',$lf,$startTicks
$j2 = Start-Job -ScriptBlock $sb -ArgumentList $ol,$s,'P2',$lf,$startTicks
$r1 = @(Receive-Job -Job $j1 -Wait)[-1]; $r2 = @(Receive-Job -Job $j2 -Wait)[-1]
Remove-Job $j1,$j2 -Force
$oneWon = ((@($r1,$r2) | Where-Object { $_ -eq 0 }).Count -eq 1) -and ((@($r1,$r2) | Where-Object { $_ -eq 1 }).Count -eq 1)
Report 'L1b-real_mutex_race' ($oneWon -and ((Count-Scope $lf $s) -eq 1)) "two PROCESSES race same scope: exits=($r1,$r2) exactlyOne0=$oneWon, leaseCount=$(Count-Scope $lf $s)(want1) -> real OS mutual exclusion"

# ---------- L1c CONTROL no-mutex: same race WITHOUT the mutex -> double-acquire (TOCTOU) ----------
$lf = New-LeaseCopy 'l1c'; $s = Fresh
$startTicks = ([DateTime]::UtcNow.AddSeconds(2)).Ticks
$sbNoMutex = { param($scope,$leaseFile,$holder,$st)
  while([DateTime]::UtcNow.Ticks -lt $st){ Start-Sleep -Milliseconds 3 }
  $d = Get-Content -LiteralPath $leaseFile -Raw | ConvertFrom-Json
  $sawEmpty = (@(@($d.leases) | Where-Object { $_.scope -eq $scope }).Count -eq 0)
  Start-Sleep -Milliseconds 350   # widen the TOCTOU window so both read-empty before either writes
  # the concurrent unguarded write may collide (that is the point); tolerate it - the proof is that BOTH
  # believed the scope was free (sawEmpty), i.e. the mutex-less path double-acquires.
  if($sawEmpty){ try { $d.leases = @(@($d.leases) + ([ordered]@{ scope=$scope; holder=$holder; acquired_at='x'; expiry='9999-01-01T00:00:00Z' })); ($d | ConvertTo-Json -Depth 6) | Out-File -LiteralPath $leaseFile -Encoding ascii -ErrorAction SilentlyContinue } catch {} }
  $sawEmpty }
$j1 = Start-Job -ScriptBlock $sbNoMutex -ArgumentList $s,$lf,'P1',$startTicks
$j2 = Start-Job -ScriptBlock $sbNoMutex -ArgumentList $s,$lf,'P2',$startTicks
$c1 = @(Receive-Job -Job $j1 -Wait)[-1]; $c2 = @(Receive-Job -Job $j2 -Wait)[-1]
Remove-Job $j1,$j2 -Force
$doubleAcq = ([bool]$c1 -and [bool]$c2)
Report 'L1c-nomutex_double_acq' $doubleAcq "no-mutex control: bothBelievedAcquire=($c1,$c2) doubleAcquire=$doubleAcq -> confirms the OS mutex is what makes L1b safe"

# ---------- L2 unheld edit/check refused ----------
$lf = New-LeaseCopy 'l2'; $s = Fresh
[void](OL @('-Action','acquire','-Scope',$s,'-Holder','A','-LeaseFile',$lf,'-TtlMinutes','60'))
$hA = OL @('-Action','check','-Scope',$s,'-Holder','A','-LeaseFile',$lf)
$hB = OL @('-Action','check','-Scope',$s,'-Holder','B','-LeaseFile',$lf)
Report 'L2-unheld_check_refused' (($hA -eq 0) -and ($hB -eq 1)) "holder check=$hA(want0), non-holder check=$hB(want1) -> unheld edit refused"

# ---------- L3a expired lease reclaimable + logged ----------
$lf = New-LeaseCopy 'l3a'; $s = Fresh
Write-LeaseFile $lf @([ordered]@{ scope=$s; holder='GHOST'; pid=999; host='crashed'; acquired_at=(IsoOff -70); expiry=(IsoOff -10) })
$rec = OL @('-Action','acquire','-Scope',$s,'-Holder','B','-LeaseFile',$lf,'-TtlMinutes','60')
$d = Get-Content -LiteralPath $lf -Raw | ConvertFrom-Json
$e = @(@($d.leases) | Where-Object { $_.scope -eq $s }) | Select-Object -First 1
$logged = ($e -and $e.holder -eq 'B' -and $e.PSObject.Properties['reclaimed_from'] -and ([string]$e.reclaimed_from -match 'GHOST'))
Report 'L3a-expired_reclaim' (($rec -eq 0) -and $logged) "acquire-over-expired=$rec(want0), newHolder=$($e.holder)(wantB), reclaimed_from logged=$logged (no deadlock)"

# ---------- L3b live lease never stolen ----------
$lf = New-LeaseCopy 'l3b'; $s = Fresh
Write-LeaseFile $lf @([ordered]@{ scope=$s; holder='A'; pid=111; host='live'; acquired_at=(IsoOff -1); expiry=(IsoOff 120) })
$acqSteal = OL @('-Action','acquire','-Scope',$s,'-Holder','B','-LeaseFile',$lf)
$recSteal = OL @('-Action','reclaim','-Scope',$s,'-Holder','B','-LeaseFile',$lf)
Report 'L3b-live_not_stolen' (($acqSteal -eq 1) -and ($recSteal -eq 1) -and ((Holder-Of $lf $s) -eq 'A')) "live acquire=$acqSteal(want1), live reclaim=$recSteal(want1), holder still=$(Holder-Of $lf $s)(wantA) -> no silent steal"

# ---------- L4a malformed lease file -> fail-closed ----------
$lf = New-LeaseCopy 'l4a'; $s = Fresh
Set-Content -LiteralPath $lf -Value '{ not : valid json ' -Encoding ascii
$mAcq = OL @('-Action','acquire','-Scope',$s,'-Holder','A','-LeaseFile',$lf)
Report 'L4a-malformed_failclosed' ($mAcq -eq 1) "acquire on malformed lease=$mAcq(want1 fail-closed)"

# ---------- L4b wrong schema id -> fail-closed ----------
$lf = New-LeaseCopy 'l4b'; $s = Fresh
Set-Content -LiteralPath $lf -Value ('{ "ownership_lease_schema_id": "neo:not_a_lease", "root_of_trust": "provisional-dev", "leases": [] }') -Encoding ascii
$wAcq = OL @('-Action','acquire','-Scope',$s,'-Holder','A','-LeaseFile',$lf)
Report 'L4b-wrongschema_failclosed' ($wAcq -eq 1) "acquire on wrong-schema lease=$wAcq(want1 fail-closed)"

# ---------- L4c tamper fails CLOSED not open: malformed + two concurrent acquirers -> BOTH refused ----------
$lf = New-LeaseCopy 'l4c'; $s = Fresh
Set-Content -LiteralPath $lf -Value '{ broken ' -Encoding ascii
$startTicks = ([DateTime]::UtcNow.AddSeconds(2)).Ticks
$j1 = Start-Job -ScriptBlock $sb -ArgumentList $ol,$s,'P1',$lf,$startTicks
$j2 = Start-Job -ScriptBlock $sb -ArgumentList $ol,$s,'P2',$lf,$startTicks
$t1 = @(Receive-Job -Job $j1 -Wait)[-1]; $t2 = @(Receive-Job -Job $j2 -Wait)[-1]
Remove-Job $j1,$j2 -Force
Report 'L4c-tamper_failsclosed' (([int]$t1 -eq 1) -and ([int]$t2 -eq 1)) "malformed file + concurrent acquire: exits=($t1,$t2) both1 -> tamper fails CLOSED (never sneaks a concurrent acquire through)"

# ---------- L5a disjoint scopes acquired concurrently -> both succeed ----------
$lf = New-LeaseCopy 'l5a'; $p = Fresh; $q = Fresh
$aP = OL @('-Action','acquire','-Scope',$p,'-Holder','A','-LeaseFile',$lf,'-TtlMinutes','60')
$bQ = OL @('-Action','acquire','-Scope',$q,'-Holder','B','-LeaseFile',$lf,'-TtlMinutes','60')
$bP = OL @('-Action','acquire','-Scope',$p,'-Holder','B','-LeaseFile',$lf)
Report 'L5a-disjoint_parallel' (($aP -eq 0) -and ($bQ -eq 0) -and ($bP -eq 1)) "A/P=$aP(0), B/Q=$bQ(0) concurrent OK; B/P=$bP(1) same-scope refused"

# ---------- L5b GOVERNED-ROOT exclusive against any sub-scope (both directions) ----------
$lf = New-LeaseCopy 'l5b1'; $sub = Fresh
[void](OL @('-Action','acquire','-Scope',$sub,'-Holder','A','-LeaseFile',$lf,'-TtlMinutes','60'))
$rootBlocked = OL @('-Action','acquire','-Scope','GOVERNED-ROOT','-Holder','B','-LeaseFile',$lf)
$lf2 = New-LeaseCopy 'l5b2'; $sub2 = Fresh
[void](OL @('-Action','acquire','-Scope','GOVERNED-ROOT','-Holder','A','-LeaseFile',$lf2,'-TtlMinutes','60'))
$subBlocked = OL @('-Action','acquire','-Scope',$sub2,'-Holder','B','-LeaseFile',$lf2)
Report 'L5b-governed_root_excl' (($rootBlocked -eq 1) -and ($subBlocked -eq 1)) "GOVERNED-ROOT while sub held=$rootBlocked(1); sub while ROOT held=$subBlocked(1) -> whole-surface exclusive"

# ---------- L4d honest limit (design-deferred to S7) ----------
ReportDeferred 'L4d-forged_indistinct' "a well-formed FORGED lease entry is indistinguishable from a real one at the file layer (the OS mutex secures the acquire op, not the file's session-long contents). Non-forgeability (only the holder's identity may WRITE the surface/lease) is Option A / S7 filesystem ACLs. S6 is tamper-EVIDENT, cooperative prevention."

# ---------- summary + cleanup ----------
Write-Host ""
foreach($line in $script:results){ Write-Host $line }
Write-Host ""
Write-Host ("Summary: {0} pass, {1} fail, {2} design-deferred (S7; not counted)." -f $script:passes,$script:failures,$script:deferred)

if(-not $KeepArtifacts){
  Remove-Item -LiteralPath $base -Recurse -Force
  if(Test-Path -LiteralPath $base){ Write-Host "[RESIDUE] WARNING: base dir still present after cleanup"; $script:failures++ }
  else { Write-Host "Fixtures removed (NEO_SESSION restored). Second clean pass: 0 residue. Use -KeepArtifacts to inspect." }
}

if($script:failures -gt 0){ Write-Host "=== ownership_lease_fixture_suite: RED - $($script:failures) case(s) misclassified ==="; exit 1 }
Write-Host "=== ownership_lease_fixture_suite: PASS ($($script:passes) fail-closed/mutual-exclusion proofs; $($script:deferred) design-deferred) ==="
exit 0
