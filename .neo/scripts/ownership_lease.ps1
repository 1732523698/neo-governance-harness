# ownership_lease.ps1 - NEO 3.1 P1-S6 section 4.8 ownership lease (concurrency-prevention substrate).
# ASCII-only, PowerShell 5.1.
#
# Gives NEO a real prevention layer so two sessions/processes cannot edit the same governed custody surface
# at once (the risk that grows under 4.0's hybrid master-dispatches-many-sub-sessions model). A session must
# HOLD a live lease for its scope before editing the governed surface; a concurrent acquire on a HELD scope is
# REFUSED; a stale/expired lease is safely reclaimable (logged, never a silent steal).
#
# TWO LAYERS (each does what only it can):
#   OS NAMED MUTEX (real, OS-enforced) - Global\NEO_LEASE_<scope> (falls back to Local\ if Global is denied)
#     guards the acquire/release/reclaim CRITICAL SECTION: two processes cannot execute it simultaneously, so
#     acquisition is atomic (no TOCTOU double-acquire) and a genuinely simultaneous second acquirer is refused
#     by the OS. HONEST LIMIT: a mutex lives only while a process holds a handle; NEO tool-calls are separate
#     short-lived processes, so the mutex CANNOT span a whole session - it secures the operation, not the span.
#   LEASE FILE (.neo\gates\OWNERSHIP_LEASE.json) - the session-SPANNING ownership token {holder,scope,
#     acquired_at,expiry,...}; persists across processes. It is principal-writable -> tamper-EVIDENT, not
#     tamper-PROOF. Session-long refusal of a 2nd session = the file check (a live unexpired lease exists),
#     made race-free by the mutex.
#
# COOPERATIVE / S7 RESIDUAL: S6 stops two sessions that both USE this protocol. A non-cooperating process that
# edits the surface WITHOUT calling acquire is NOT blocked (the mutex/lease cannot compel a rogue writer to
# check). Non-bypassability (only the current holder's identity may WRITE the surface) is Option A / S7 ACLs.
#
# ACTIONS: acquire | release | check | status | reclaim. Exit 0 = success/held; exit 1 = refused/not-held/fail
# (fail-closed on absent/malformed/wrong-schema lease file).

[CmdletBinding()]
param(
  [ValidateSet('acquire','release','check','status','reclaim')][string]$Action = 'status',
  [string]$Scope = 'GOVERNED-ROOT',
  [string]$Holder = '',
  [int]$TtlMinutes = 120,
  [string]$LeaseFile = '',
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Lease file resolves from the .neo script-root authority (not an app tree), mirroring verify_app_slice's
# -HumanGateLedger precedent; -LeaseFile overrides for fixtures/trusted operators only.
$script:neoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(-not $LeaseFile){ $LeaseFile = Join-Path $script:neoRoot '.neo\gates\OWNERSHIP_LEASE.json' }
if(-not $Holder){ $Holder = "$env:USERNAME@$env:COMPUTERNAME" }

function Say($m){ if(-not $Quiet){ Write-Host $m } }
function Now-Utc(){ return [DateTime]::UtcNow }
function Iso([DateTime]$t){ return $t.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ') }
function Is-Live($entry){
  if($null -eq $entry){ return $false }
  try { $exp = [DateTimeOffset]::Parse([string]$entry.expiry).UtcDateTime } catch { return $false }
  return ($exp -gt (Now-Utc))
}

function New-LeaseMutex([string]$scope){
  $san = ($scope -replace '[^A-Za-z0-9_]','_')
  foreach($ns in @('Global','Local')){
    try {
      $created = $false
      $m = New-Object System.Threading.Mutex($false, ("$ns\NEO_LEASE_" + $san), [ref]$created)
      return @{ Mutex = $m; Namespace = $ns }
    } catch { continue }
  }
  throw "could not create a named mutex for scope '$scope' (Global and Local both denied)"
}

# Run a body inside the OS-mutex-guarded critical section for a scope. Abandoned mutex (a holder crashed
# mid-critical-section) is caught and treated as owned -> NO DEADLOCK. Mutex is always released + disposed.
function Invoke-CriticalSection([string]$scope,[scriptblock]$body){
  $mx = New-LeaseMutex $scope
  $entered = $false
  try {
    try { $entered = $mx.Mutex.WaitOne([TimeSpan]::FromSeconds(15)) }
    catch [System.Threading.AbandonedMutexException] { $entered = $true }
    if(-not $entered){ throw "could not enter lease critical section for scope '$scope' within 15s (contended)" }
    return (& $body $mx.Namespace)
  } finally {
    if($entered){ try { $mx.Mutex.ReleaseMutex() } catch {} }
    $mx.Mutex.Dispose()
  }
}

function Load-Lease([string]$path){
  if(-not (Test-Path -LiteralPath $path)){ throw "lease file absent: $path" }
  try { $d = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
  catch { throw "lease file parse error ($path): $($_.Exception.Message)" }
  if($d.ownership_lease_schema_id -ne 'neo:ownership_lease'){ throw "not a neo:ownership_lease instance: $path" }
  return $d
}
function Save-Lease([string]$path,$data){
  $arr = @($data.leases)
  $entryLines = @()
  foreach($e in $arr){ $entryLines += ('    ' + ($e | ConvertTo-Json -Depth 6 -Compress)) }
  $leasesJson = if($arr.Count -eq 0){ '[]' } else { "[`r`n" + ($entryLines -join ",`r`n") + "`r`n  ]" }
  $noteJson = ([string]$data.note | ConvertTo-Json)
  $rot = if([string]::IsNullOrWhiteSpace([string]$data.root_of_trust)){ 'provisional-dev' } else { [string]$data.root_of_trust }
  $lines = @(
    '{',
    '  "ownership_lease_schema_id": "neo:ownership_lease",',
    ('  "root_of_trust": "' + $rot + '",'),
    ('  "note": ' + $noteJson + ','),
    ('  "leases": ' + $leasesJson),
    '}'
  )
  Set-Content -LiteralPath $path -Value ($lines -join "`r`n") -Encoding ascii
}

# Conflict rule (Q2): same-scope held by another -> conflict; GOVERNED-ROOT conflicts with ANY other live
# lease (both directions); disjoint sub-scopes -> NO conflict (parallel). Only LIVE leases conflict.
function Get-Conflict($leases,[string]$scope,[string]$holder){
  foreach($e in $leases){
    if(-not (Is-Live $e)){ continue }
    if(($e.scope -eq $scope) -and ($e.holder -eq $holder)){ continue }   # my own same-scope -> refresh
    if($e.scope -eq $scope){ return "scope '$scope' is HELD by '$($e.holder)' until $($e.expiry)" }
    if($scope -eq 'GOVERNED-ROOT'){ return "GOVERNED-ROOT requested but sub-scope '$($e.scope)' is HELD by '$($e.holder)'" }
    if($e.scope -eq 'GOVERNED-ROOT'){ return "scope '$scope' blocked: GOVERNED-ROOT is HELD by '$($e.holder)'" }
  }
  return $null
}

function Do-Acquire($ns){
  $data = Load-Lease $LeaseFile
  $leases = @($data.leases)
  $existingSame = @($leases | Where-Object { $_.scope -eq $Scope }) | Select-Object -First 1
  $reclaimNote = $null
  if($existingSame -and (-not (Is-Live $existingSame)) -and ($existingSame.holder -ne $Holder)){
    $reclaimNote = "reclaimed expired lease from '$($existingSame.holder)' (was expiry $($existingSame.expiry)) at $(Iso (Now-Utc))"
  }
  $conflict = Get-Conflict $leases $Scope $Holder
  if($conflict){ Say "[LEASE] ACQUIRE REFUSED (mutex-guarded; namespace=$ns): $conflict"; return 1 }
  $t = Now-Utc
  $entry = [ordered]@{
    scope       = $Scope
    holder      = $Holder
    pid         = $PID
    host        = "$env:USERNAME@$env:COMPUTERNAME"
    acquired_at = (Iso $t)
    expiry      = (Iso ($t.AddMinutes($TtlMinutes)))
  }
  if($reclaimNote){ $entry['reclaimed_from'] = $reclaimNote }
  $kept = @($leases | Where-Object { $_.scope -ne $Scope })
  $data.leases = @($kept + $entry)
  Save-Lease $LeaseFile $data
  $suffix = if($reclaimNote){ " ($reclaimNote)" } else { '' }
  Say "[LEASE] ACQUIRED scope='$Scope' holder='$Holder' ttl=${TtlMinutes}m expiry=$($entry.expiry) (mutex namespace=$ns)$suffix"
  return 0
}

function Do-Release($ns){
  $data = Load-Lease $LeaseFile
  $leases = @($data.leases)
  $existing = @($leases | Where-Object { $_.scope -eq $Scope }) | Select-Object -First 1
  if(-not $existing){ Say "[LEASE] RELEASE no-op: no lease for scope '$Scope' (idempotent)"; return 0 }
  if($existing.holder -ne $Holder){ Say "[LEASE] RELEASE REFUSED: '$Holder' does not hold scope '$Scope' (held by '$($existing.holder)') - cannot release another's lease"; return 1 }
  $data.leases = @($leases | Where-Object { $_.scope -ne $Scope })
  Save-Lease $LeaseFile $data
  Say "[LEASE] RELEASED scope='$Scope' holder='$Holder' (mutex namespace=$ns)"
  return 0
}

function Do-Reclaim($ns){
  $data = Load-Lease $LeaseFile
  $leases = @($data.leases)
  $existing = @($leases | Where-Object { $_.scope -eq $Scope }) | Select-Object -First 1
  if(-not $existing){ Say "[LEASE] RECLAIM no-op: nothing to reclaim for scope '$Scope'"; return 0 }
  if((Is-Live $existing) -and ($existing.holder -ne $Holder)){
    Say "[LEASE] RECLAIM REFUSED: scope '$Scope' lease is LIVE (held by '$($existing.holder)' until $($existing.expiry)) - a LIVE lease is never stolen"; return 1
  }
  $data.leases = @($leases | Where-Object { $_.scope -ne $Scope })
  Save-Lease $LeaseFile $data
  Say "[LEASE] RECLAIMED+CLEARED scope='$Scope' (was held by '$($existing.holder)', expiry $($existing.expiry); logged, not a silent steal) (mutex namespace=$ns)"
  return 0
}

function Do-Check(){
  $data = Load-Lease $LeaseFile   # fail-closed on absent/malformed/wrong-schema
  $existing = @(@($data.leases) | Where-Object { $_.scope -eq $Scope }) | Select-Object -First 1
  if($existing -and (Is-Live $existing) -and ($existing.holder -eq $Holder)){
    Say "[LEASE] HELD scope='$Scope' holder='$Holder' expiry=$($existing.expiry)"; return 0
  }
  $who = if($existing){ "held by '$($existing.holder)'" + $(if(Is-Live $existing){" (live)"}else{" (expired)"}) } else { 'no lease' }
  Say "[LEASE] NOT HELD scope='$Scope' holder='$Holder' ($who) - unheld edit refused"
  return 1
}

function Do-Status(){
  $data = Load-Lease $LeaseFile
  $leases = @($data.leases)
  Say "[LEASE] status: $($leases.Count) lease(s) in $LeaseFile (root_of_trust=$($data.root_of_trust))"
  foreach($e in $leases){ $live = if(Is-Live $e){'LIVE'}else{'EXPIRED'}; Say ("  [{0,-7}] scope='{1}' holder='{2}' expiry={3}" -f $live,$e.scope,$e.holder,$e.expiry) }
  return 0
}

try {
  switch($Action){
    'acquire' { $rc = Invoke-CriticalSection $Scope { param($ns) Do-Acquire $ns } }
    'release' { $rc = Invoke-CriticalSection $Scope { param($ns) Do-Release $ns } }
    'reclaim' { $rc = Invoke-CriticalSection $Scope { param($ns) Do-Reclaim $ns } }
    'check'   { $rc = Do-Check }
    'status'  { $rc = Do-Status }
    default   { Say "[LEASE] unknown action '$Action'"; $rc = 1 }
  }
  exit [int]$rc
} catch {
  Write-Host "[LEASE] FAIL: $($_.Exception.Message) (fail-closed)"
  exit 1
}
