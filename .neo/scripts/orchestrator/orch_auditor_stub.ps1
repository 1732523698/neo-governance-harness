# orch_auditor_stub.ps1 - NEO 4.0 ISOLATED-AUDITOR SEAM (DERIVING TEST-FIXTURE).
# ASCII-only (D10).
#
# ############################################################################
# # THIS IS A SEAM/FIXTURE, NOT THE ENGINE. It stands in for the separately-  #
# # spawned, fresh-context COLD auditor that a real NEO session runs out of   #
# # band. It is the ONLY component permitted to WRITE an AUDIT_RESULT. The     #
# # orchestrator engine library                                               #
# # (orch_engine/orch_io/orch_schema/orch_class/orchestrator) has NO code path #
# # that writes an AUDIT_RESULT or a GO -- so the engine cannot self-approve   #
# # (v4 5.1). Keeping this writer OUTSIDE the engine is the architectural      #
# # separation, and NO engine-library file references this script.            #
# ############################################################################
#
# The verdict is DERIVED, never injected. This fixture GENUINELY:
#   (1) re-hashes every allowlisted bundle member independently, and
#   (2) re-runs each promised test NON-CACHED (a fresh powershell.exe per
#       runnable proof member), then
#   (3) derives GO / NEEDS-MORE / NO-GO from those results ALONE.
# There is deliberately NO -Recommendation and NO -ForceAllMatched parameter:
# no caller can force a verdict. Adversarial "lying" AUDIT_RESULTs (claims that
# contradict reality) are produced by clearly-labelled test-only fixture writers
# in the suites, never here -- and the engine's Read-NeoAuditResult catches them.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$BundlePath,
  [Parameter(Mandatory = $true)][string]$BundleDir,
  [Parameter(Mandatory = $true)][string]$OutPath,
  [Parameter(Mandatory = $true)][string]$Timestamp,
  [string]$AuditorIdentity = 'isolated-auditor-cold-context',
  [string]$ProducerRole = 'isolated-auditor',
  [string]$ResultId
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\orch_io.ps1"

$schemaDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\schema')).Path ''
$index = Get-NeoSchemaIndex $schemaDir

$bundle = Read-NeoJsonFile $BundlePath
Assert-NeoValid $bundle 'neo:input_packet' $index 'AUDIT_BUNDLE(input to auditor)'

# The auditor re-hashes every allowlisted member independently, then BINDS every PROMISED
# test in the SUBSESSION_END_REPORT (tests_run) to a runnable proof MEMBER and re-runs THAT
# member non-cached. GO is thus earned only when every promised test actually re-ran and
# passed. Every member rel AND every tests_run.proof_ref is validated + contained BEFORE any
# join/read/exec (F2: reject rooted/drive/UNC/backslash/../empty => BLOCK).
#
# MATCHING CONVENTION (owned here; unambiguous + fail-closed): a tests_run entry binds to an
# allowlist member iff proof_ref -ceq member.path (case-sensitive, exact bundle-relative rel)
# AND that member's role -ceq 'proof'. Zero match => uncovered (NEEDS-MORE). >1 match
# (duplicate proof rel) => ambiguous (NEEDS-MORE). Neither ever earns GO. The lookup tables
# below are ORDINAL (case-sensitive) so .ContainsKey genuinely honors the -ceq contract: a
# case-only proof_ref mismatch is UNCOVERED (NEEDS-MORE), never a bind to a different file.
#
# SINGLETON MULTIPLICITY (same fail-closed rule, end_report instance): the SUBSESSION_END_REPORT
# member must be UNIQUE among intact members. Zero => NEEDS-MORE (cannot enumerate promises).
# TWO OR MORE => ambiguous: the authoritative report is unverifiable, so NO candidate is
# enumerated (never last-wins, never allowlist-order selection, never merge) => NEEDS-MORE.
$ProofTimeoutMs = 60000   # 60s hard ceiling per non-cached proof re-run; a hung proof => exit 124 => FAIL (never GO).

# ---- pass 1: re-hash EVERY member; index intact runnable proof members + the end_report member.
$mismatches   = @()   # hash/missing failures only (drives all_members_matched)
$proofMembers = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)   # rel -> local path, INTACT role='proof' *.ps1 only (ORDINAL: honors -ceq)
$proofDupRels = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)   # rel -> $true when the same proof rel appears >1x (ambiguous => fail-closed)
$endReportPath  = $null   # local path of THE intact role='end_report' member; usable ONLY when count == 1
$endReportCount = 0       # intact role='end_report' members seen; >=2 => ambiguous => fail-closed
$endReportRels  = @()     # their rels, for the ambiguity finding
foreach ($m in @($bundle.allowlist)) {
  $relRaw = [string]$m.path
  Assert-NeoSafeRel $relRaw
  $mp = Assert-NeoContained $BundleDir $relRaw
  if (-not (Test-Path -LiteralPath $mp)) { $mismatches += ($relRaw + ' (missing)'); continue }
  if ((Get-NeoSha256File $mp) -cne ([string]$m.content_hash)) { $mismatches += $relRaw; continue }
  $role = [string]$m.role
  if (($role -ceq 'proof') -and ($mp -like '*.ps1')) {
    if ($proofMembers.ContainsKey($relRaw)) { $proofDupRels[$relRaw] = $true }
    $proofMembers[$relRaw] = $mp
  }
  if ($role -ceq 'end_report') { $endReportCount++; $endReportRels += $relRaw; $endReportPath = $mp }
}
$allMatched = ($mismatches.Count -eq 0)
$endReportAmbiguous = ($endReportCount -ge 2)
if ($endReportAmbiguous) { $endReportPath = $null }   # NEVER select by allowlist order; no candidate is authoritative

# ---- pass 2: bind each PROMISED test (tests_run) to a proof member + re-run it NON-CACHED.
$testFailures  = @()   # promised tests that re-ran non-zero / timed out / errored => NO-GO
$uncovered     = @()   # promised tests with no unambiguous intact proof member => NEEDS-MORE
$promisedCount = 0
$noEndReport   = ($endReportCount -eq 0)
if ($endReportCount -eq 1) {   # ambiguous (>=2) enumerates NOTHING: no candidate's promises are trusted
  $endReport = Read-NeoJsonFile $endReportPath   # same bytes just re-hashed intact
  $testsRun  = @($endReport.tests_run)
  $promisedCount = $testsRun.Count
  foreach ($t in $testsRun) {
    $pref  = [string]$t.proof_ref
    Assert-NeoSafeRel $pref   # unsafe/rooted/traversal proof_ref => BLOCK (throws before any exec)
    $label = 'test[' + [string]$t.command + ' -> ' + $pref + ']'
    if ($proofDupRels.ContainsKey($pref)) { $uncovered += ($label + ' (ambiguous: duplicate proof member rel)'); continue }
    if (-not $proofMembers.ContainsKey($pref)) { $uncovered += ($label + ' (no matching runnable proof member)'); continue }
    $mp = $proofMembers[$pref]
    $code = 1
    try {
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = 'powershell.exe'
      $psi.Arguments = '-NoProfile -File "' + $mp + '"'
      $psi.UseShellExecute = $false
      $psi.CreateNoWindow = $true
      $proc = [System.Diagnostics.Process]::Start($psi)
      if ($proc.WaitForExit($ProofTimeoutMs)) { $code = $proc.ExitCode }
      else { try { $proc.Kill() } catch {}; $code = 124 }   # hung proof => timeout sentinel => FAIL
    } catch { $code = 1 }   # any read/exec failure => promised test failed
    if ($code -ne 0) { $testFailures += ($label + " (exit $code)") }
  }
}

# DERIVE the verdict (default-case-is-the-threat: only a bundle where EVERY promised test
# re-bound to a real proof member AND re-ran exit 0, with every member intact, earns GO):
#   any re-hash mismatch                                   => NO-GO
#   any promised test re-ran non-zero / timed out / errored => NO-GO
#   any promised test with no unambiguous proof member     => NEEDS-MORE (cannot verify)
#   two+ end_report members (ambiguous: which is real?)    => NEEDS-MORE (cannot verify)
#   no end_report member, OR tests_run empty/absent        => NEEDS-MORE (cannot verify)
#   else                                                   => GO
if (-not $allMatched)              { $recommendation = 'NO-GO' }
elseif ($testFailures.Count -gt 0) { $recommendation = 'NO-GO' }
elseif ($uncovered.Count -gt 0)    { $recommendation = 'NEEDS-MORE' }
elseif ($endReportAmbiguous)       { $recommendation = 'NEEDS-MORE' }
elseif ($noEndReport)              { $recommendation = 'NEEDS-MORE' }
elseif ($promisedCount -eq 0)      { $recommendation = 'NEEDS-MORE' }
else                               { $recommendation = 'GO' }

$find = @()
if ($mismatches.Count -gt 0) {
  $find += @{ severity = 'blocking'; statement = ("bundle member re-hash mismatch: " + ($mismatches -join ', ')); evidence_ref = './audit/AUDIT_BUNDLE.json' }
}
if ($testFailures.Count -gt 0) {
  $find += @{ severity = 'blocking'; statement = ("promised test proof re-run failed/timed-out (non-zero): " + ($testFailures -join ', ')); evidence_ref = './audit/AUDIT_BUNDLE.json' }
}
if ($uncovered.Count -gt 0) {
  $find += @{ severity = 'high'; statement = ("promised test not bound to a runnable proof member; cannot verify: " + ($uncovered -join ', ')); evidence_ref = './audit/AUDIT_BUNDLE.json' }
}
if ($endReportAmbiguous) {
  # DEDICATED ambiguity finding (distinct from the no-end_report case below).
  $find += @{ severity = 'high'; statement = ("multiple intact role='end_report' members in bundle (" + ($endReportRels -join ', ') + "); authoritative SUBSESSION_END_REPORT unverifiable; no candidate enumerated => NEEDS-MORE"); evidence_ref = './audit/AUDIT_BUNDLE.json' }
}
if (($recommendation -eq 'NEEDS-MORE') -and ($find.Count -eq 0)) {
  $stmt = if ($noEndReport) { 'no SUBSESSION_END_REPORT member in bundle; cannot enumerate promised tests => NEEDS-MORE' }
          else { 'SUBSESSION_END_REPORT.tests_run empty/absent; no promised test to verify => NEEDS-MORE' }
  $find += @{ severity = 'high'; statement = $stmt; evidence_ref = './audit/AUDIT_BUNDLE.json' }
}

if (-not $ResultId) { $ResultId = 'audit-result-' + (Split-Path -Leaf $BundleDir) }

$env = New-NeoEnvelope -ArtifactId $ResultId -ArtifactClass 'evidence' `
  -SchemaId 'neo:audit_result' -SchemaVersion '4.0-P3-B' `
  -ProducerRole $ProducerRole -ProducerClass 'auditor' `
  -ValidatorRole $ProducerRole -ValidatorClass 'auditor' `
  -Timestamp $Timestamp -DeclaredPaths @('./NEO_SESSION/') -DeclaredSurfaces @('filesystem') `
  -SourcePackets @() -GateRef $null

$result = [pscustomobject]@{
  result_id       = $ResultId
  recommendation  = $recommendation
  findings        = $find
  rehash_check    = @{ all_members_matched = $allMatched; mismatches = @($mismatches) }
  auditor_identity = $AuditorIdentity
  _provenance     = $env
}
Set-NeoArtifactHash $result
Assert-NeoValid $result 'neo:audit_result' $index 'AUDIT_RESULT(produced)'
Write-NeoJsonFile $OutPath $result
Write-Host "isolated-auditor fixture: DERIVED AUDIT_RESULT ($recommendation) -> $OutPath"
