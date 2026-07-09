<#
.SYNOPSIS
  NEO session audit net. Gates on EVIDENCE ARTIFACTS, never on agent claims.
.DESCRIPTION
  Runs checks C1-C10 (see .neo\DEFINITIONS.md) over a NEO_SESSION\<id> folder.
  Status per check: PASS | FAIL | NA (not applicable this phase) | PENDING (artifact not yet produced).
  Exit code is non-zero if ANY check is FAIL. Partial green = red.

  v2.5 note: C1 now performs FULL schema validation (enum + type + range + nested required +
  unknown-key rejection) in pure PowerShell against session_contract.schema.json - no package
  installs. C11 still uses the original required-arrays check (Test-RequiredFromSchema).
.EXAMPLE
  .\verify_session.ps1 -SessionPath S:\NEO\NEO_SESSION\2026-06-09_hello-module
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SessionPath,
  [string]$SchemaDir,
  [ValidateSet('Auto', 'Fresh', 'EndGate')][string]$Mode = 'Auto'
)

$ErrorActionPreference = 'Stop'
if (-not $SchemaDir) { $SchemaDir = (Join-Path $PSScriptRoot '..\schema') }

if (-not (Test-Path -LiteralPath $SessionPath)) { throw "Session path not found: $SessionPath" }

$script:results = @()
function Add-Result($id, $name, $status, $detail) {
  $script:results += [pscustomobject]@{ Check = $id; Name = $name; Status = $status; Detail = $detail }
}
function Read-Json($path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
  catch { return '__PARSE_ERROR__' }
}
# Pure-PowerShell required-field check driven by a JSON Schema's "required" arrays (1 level deep).
function Test-HasKey($obj, $key) {
  if ($null -eq $obj) { return $false }
  return (@($obj.PSObject.Properties.Name) -contains $key)
}
function Test-RequiredFromSchema($obj, $schema) {
  # Required = the KEY must be present. A present-but-null value is allowed (schema decides type).
  $missing = @()
  if ($schema.required) {
    foreach ($req in $schema.required) {
      if (-not (Test-HasKey $obj $req)) { $missing += $req }
    }
  }
  if ($schema.properties) {
    foreach ($p in $schema.properties.PSObject.Properties) {
      $propSchema = $p.Value
      $propName = $p.Name
      if ($propSchema.required -and (Test-HasKey $obj $propName) -and ($obj.$propName -is [psobject])) {
        foreach ($req in $propSchema.required) {
          if (-not (Test-HasKey $obj.$propName $req)) { $missing += "$propName.$req" }
        }
      }
    }
  }
  return $missing
}
# ---- v2.5 C1 hardening: full recursive JSON Schema validation (draft-07 subset used by NEO) ----
# Covers: type (incl. union arrays), enum, required (recursive at every depth), properties recursion,
# additionalProperties false (unknown-key rejection) or sub-schema, items, minimum, minLength, minItems.
# ASCII-only by design (PS 5.1).
function Test-JsonType($value, [string]$t) {
  switch ($t) {
    'string'  { return ($value -is [string]) }
    'boolean' { return ($value -is [bool]) }
    'object'  { return ($value -is [System.Management.Automation.PSCustomObject]) }
    'array'   { return ((($value -is [System.Array]) -or ($value -is [System.Collections.IList])) -and -not ($value -is [string])) }
    'null'    { return ($null -eq $value) }
    'integer' {
      if ($value -is [bool]) { return $false }
      if (($value -is [int]) -or ($value -is [long]) -or ($value -is [int16]) -or ($value -is [byte])) { return $true }
      if (($value -is [double]) -or ($value -is [single]) -or ($value -is [decimal])) {
        return ([math]::Floor([double]$value) -eq [double]$value)
      }
      return $false
    }
    'number'  {
      if ($value -is [bool]) { return $false }
      return (($value -is [int]) -or ($value -is [long]) -or ($value -is [int16]) -or ($value -is [byte]) -or
              ($value -is [double]) -or ($value -is [single]) -or ($value -is [decimal]))
    }
    default   { return $true }
  }
}
function Test-JsonSchemaErrors($value, $schema, [string]$path) {
  $errors = @()
  if ($null -eq $schema) { return $errors }
  if (Test-HasKey $schema 'type') {
    $types = @($schema.type)
    $typeOk = $false
    foreach ($t in $types) { if (Test-JsonType $value $t) { $typeOk = $true; break } }
    if (-not $typeOk) {
      $actual = 'null'
      if ($null -ne $value) { $actual = $value.GetType().Name }
      $errors += ("{0}: type mismatch (expected {1}, got {2})" -f $path, ($types -join '|'), $actual)
      return $errors
    }
  }
  if ($null -eq $value) { return $errors }
  if (Test-HasKey $schema 'enum') {
    $enumOk = $false
    foreach ($e in @($schema.enum)) { if ($value -eq $e) { $enumOk = $true; break } }
    if (-not $enumOk) {
      $errors += ("{0}: value '{1}' not in enum [{2}]" -f $path, $value, (@($schema.enum) -join ', '))
    }
  }
  if ($value -is [string]) {
    if ((Test-HasKey $schema 'minLength') -and ($value.Length -lt [int]$schema.minLength)) {
      $errors += ("{0}: string length {1} below minLength {2}" -f $path, $value.Length, $schema.minLength)
    }
    return $errors
  }
  if (($value -is [int]) -or ($value -is [long]) -or ($value -is [int16]) -or ($value -is [byte]) -or
      ($value -is [double]) -or ($value -is [single]) -or ($value -is [decimal])) {
    if ((Test-HasKey $schema 'minimum') -and ([double]$value -lt [double]$schema.minimum)) {
      $errors += ("{0}: value {1} below minimum {2}" -f $path, $value, $schema.minimum)
    }
    return $errors
  }
  $isArrayVal = ((($value -is [System.Array]) -or ($value -is [System.Collections.IList])) -and -not ($value -is [string]))
  if ($isArrayVal) {
    if ((Test-HasKey $schema 'minItems') -and (@($value).Count -lt [int]$schema.minItems)) {
      $errors += ("{0}: array has {1} item(s), minItems {2}" -f $path, @($value).Count, $schema.minItems)
    }
    if (Test-HasKey $schema 'items') {
      $idx = 0
      foreach ($item in @($value)) {
        $errors += @(Test-JsonSchemaErrors $item $schema.items ("{0}[{1}]" -f $path, $idx))
        $idx++
      }
    }
    return $errors
  }
  if ($value -is [System.Management.Automation.PSCustomObject]) {
    if (Test-HasKey $schema 'required') {
      foreach ($req in @($schema.required)) {
        if (-not (Test-HasKey $value $req)) { $errors += ("{0}: missing required key '{1}'" -f $path, $req) }
      }
    }
    $knownProps = @()
    if (Test-HasKey $schema 'properties') { $knownProps = @($schema.properties.PSObject.Properties.Name) }
    foreach ($prop in $value.PSObject.Properties) {
      $pName = $prop.Name
      $pPath = ("{0}.{1}" -f $path, $pName)
      if ($knownProps -contains $pName) {
        $errors += @(Test-JsonSchemaErrors $prop.Value $schema.properties.$pName $pPath)
      } else {
        $ap = $null
        if (Test-HasKey $schema 'additionalProperties') { $ap = $schema.additionalProperties }
        if ($ap -is [bool]) {
          if (-not $ap) { $errors += ("{0}: unknown key (additionalProperties=false)" -f $pPath) }
        } elseif ($null -ne $ap) {
          $errors += @(Test-JsonSchemaErrors $prop.Value $ap $pPath)
        }
      }
    }
  }
  return $errors
}

# Convert a NEO glob to a -like wildcard (treat ** as *).
function Test-PathGlob($path, $glob) {
  $p = $path -replace '\\', '/'
  $g = ($glob -replace '\\', '/') -replace '\*\*', '*'
  return ($p -like $g)
}
# Extract changed file paths from unified-diff patch text.
function Get-DiffPaths($patchText) {
  $paths = @()
  foreach ($line in ($patchText -split "`n")) {
    if ($line -match '^\+\+\+ b/(.+)$') { $paths += $Matches[1].Trim() }
    elseif ($line -match '^diff --git a/(.+) b/(.+)$') { $paths += $Matches[2].Trim() }
  }
  return ($paths | Where-Object { $_ -and $_ -ne '/dev/null' } | Select-Object -Unique)
}
# Classify each changed file in a patch as created / modified / deleted / renamed.
function Get-DiffClassified($patchText) {
  $result = @()
  $sections = [regex]::Split($patchText, '(?m)^diff --git ')
  foreach ($sec in $sections) {
    if (-not $sec.Trim()) { continue }
    $kind = 'modified'; $path = $null
    if ($sec -match '^a/\S+ b/(?<b>\S+)') { $path = $Matches['b'] }
    if ($sec -match '(?m)^\+\+\+ b/(.+)$') { $path = $Matches[1].Trim() }
    if ($sec -match '(?m)^new file mode') { $kind = 'created' }
    elseif (($sec -match '(?m)^deleted file mode') -or ($sec -match '(?m)^\+\+\+ /dev/null')) {
      $kind = 'deleted'; if ($sec -match '(?m)^--- a/(.+)$') { $path = $Matches[1].Trim() }
    }
    elseif ($sec -match '(?m)^rename ') {
      $kind = 'renamed'; if ($sec -match '(?m)^rename to (.+)$') { $path = $Matches[1].Trim() }
    }
    if ($path) { $result += [pscustomobject]@{ path = ($path -replace '\\', '/'); kind = $kind } }
  }
  return $result
}

# ---- session artifacts ----
$contractPath   = Join-Path $SessionPath 'session_contract.json'
$startPacket    = Join-Path $SessionPath 'start_packet.md'
$diffsDir       = Join-Path $SessionPath 'diffs'
$changedDir     = Join-Path $SessionPath 'changed_files'
$verResultsDir  = Join-Path $SessionPath 'verifier_results'
$residuePath    = Join-Path $SessionPath 'verifier_residue_report.json'
$residueAltPath = Join-Path $SessionPath 'residue_manifest.json'
$auditorReport  = Join-Path $SessionPath 'auditor_report.md'
$auditorFinds   = Join-Path $SessionPath 'auditor_findings.json'
$endSummary     = Join-Path $SessionPath 'ambassador_end_summary.md'
$routingLog     = Join-Path $SessionPath 'model_routing_log.json'
$stopReason     = Join-Path $SessionPath 'stop_reason.json'

$contract = Read-Json $contractPath
$isEnd = Test-Path -LiteralPath $endSummary
# Effective END-gate mode: forced by -Mode, else auto-detected from presence of the END summary.
$endMode = $false
if ($Mode -eq 'EndGate') { $endMode = $true }
elseif ($Mode -eq 'Auto' -and $isEnd) { $endMode = $true }
# (-Mode Fresh forces non-END even if an END summary exists — useful for mid-session re-checks/tests.)
$isEnd = $endMode
$diffFiles = @()
if (Test-Path -LiteralPath $diffsDir) {
  $diffFiles = @(Get-ChildItem -LiteralPath $diffsDir -Filter '*.patch' -File -ErrorAction SilentlyContinue)
}
$hasEdits = $diffFiles.Count -gt 0

# ===== C1 - CONTRACT SCHEMA / REQUIRED FIELDS =====
if ($null -eq $contract) {
  Add-Result 'C1' 'Contract present & valid' 'FAIL' "session_contract.json not found at $contractPath"
}
elseif ($contract -eq '__PARSE_ERROR__') {
  Add-Result 'C1' 'Contract present & valid' 'FAIL' 'session_contract.json is not valid JSON'
}
else {
  $schema = Read-Json (Join-Path $SchemaDir 'session_contract.schema.json')
  if ($null -eq $schema -or $schema -eq '__PARSE_ERROR__') {
    Add-Result 'C1' 'Contract present & valid' 'FAIL' 'session_contract.schema.json missing/invalid'
  } else {
    # v2.5: full recursive validation replaces the required-arrays-only check for C1.
    $schemaErrors = @(Test-JsonSchemaErrors $contract $schema 'contract')
    if ($schemaErrors.Count -gt 0) {
      $shown = @($schemaErrors | Select-Object -First 8)
      $detail = ($shown -join '; ')
      $more = $schemaErrors.Count - $shown.Count
      if ($more -gt 0) { $detail += (" (+{0} more)" -f $more) }
      Add-Result 'C1' 'Contract present & valid' 'FAIL' $detail
    } else {
      Add-Result 'C1' 'Contract present & valid' 'PASS' 'Full schema validation passed (enum, type, range, nested required, unknown-key)'
    }
  }
}

# ===== C2 - START GATE PREDATES FIRST EDIT =====
if (-not (Test-Path -LiteralPath $startPacket)) {
  if ($hasEdits) { Add-Result 'C2' 'START gate before edits' 'FAIL' 'Edits exist but no start_packet.md' }
  else { Add-Result 'C2' 'START gate before edits' 'PENDING' 'No start_packet.md yet (session not started)' }
}
elseif (-not $hasEdits) {
  Add-Result 'C2' 'START gate before edits' 'PASS' 'start_packet exists; no edits yet'
}
else {
  $startTime = (Get-Item -LiteralPath $startPacket).LastWriteTimeUtc
  $earliestEdit = ($diffFiles | Sort-Object LastWriteTimeUtc | Select-Object -First 1).LastWriteTimeUtc
  if ($startTime -le $earliestEdit) {
    Add-Result 'C2' 'START gate before edits' 'PASS' "start_packet ($startTime) <= first edit ($earliestEdit)"
  } else {
    Add-Result 'C2' 'START gate before edits' 'FAIL' "Edit predates START packet (start=$startTime, firstEdit=$earliestEdit)"
  }
}

# ===== C3 - SCOPE: edited paths subset of approved, disjoint from protected =====
if (-not $hasEdits) {
  Add-Result 'C3' 'Scope (approved/protected)' 'NA' 'No diffs to check'
}
elseif ($null -eq $contract -or $contract -eq '__PARSE_ERROR__') {
  Add-Result 'C3' 'Scope (approved/protected)' 'FAIL' 'Cannot check scope without a valid contract'
}
else {
  $allPaths = @()
  foreach ($df in $diffFiles) { $allPaths += Get-DiffPaths (Get-Content -LiteralPath $df.FullName -Raw) }
  $allPaths = $allPaths | Select-Object -Unique
  $violations = @()
  foreach ($pth in $allPaths) {
    $inApproved = $false
    foreach ($g in $contract.approved_paths) { if (Test-PathGlob $pth $g) { $inApproved = $true; break } }
    $inProtected = $false
    foreach ($g in $contract.protected_paths) { if (Test-PathGlob $pth $g) { $inProtected = $true; break } }
    if (-not $inApproved) { $violations += "$pth (not in approved_paths)" }
    if ($inProtected) { $violations += "$pth (in protected_paths)" }
  }
  if ($violations.Count -gt 0) {
    Add-Result 'C3' 'Scope (approved/protected)' 'FAIL' ($violations -join '; ')
  } else {
    Add-Result 'C3' 'Scope (approved/protected)' 'PASS' "$($allPaths.Count) changed path(s) all in scope"
  }
}

# ===== C4 - DESTRUCTIVE OP REQUIRES SNAPSHOT =====
if (-not $hasEdits) {
  Add-Result 'C4' 'Destructive op snapshot' 'NA' 'No diffs to check'
}
else {
  $destructiveSeen = @()
  foreach ($df in $diffFiles) {
    $t = Get-Content -LiteralPath $df.FullName -Raw
    if ($t -match 'deleted file mode' -or $t -match '\+\+\+ /dev/null' -or $t -match '^rename from ') {
      $destructiveSeen += $df.Name
    }
  }
  if ($destructiveSeen.Count -eq 0) {
    Add-Result 'C4' 'Destructive op snapshot' 'NA' 'No destructive ops detected in diffs'
  } else {
    $snapDir = Join-Path $SessionPath 'snapshots'
    if ((Test-Path -LiteralPath $snapDir) -and (Get-ChildItem -LiteralPath $snapDir -File -ErrorAction SilentlyContinue).Count -gt 0) {
      Add-Result 'C4' 'Destructive op snapshot' 'PASS' ("Destructive in: " + ($destructiveSeen -join ', ') + " - snapshots/ present")
    } else {
      Add-Result 'C4' 'Destructive op snapshot' 'FAIL' ("Destructive ops without snapshots/: " + ($destructiveSeen -join ', '))
    }
  }
}

# ===== C3b - CODER REPORT RECONCILIATION (report must be truthful vs the diff) =====
$coderReport = Read-Json (Join-Path $SessionPath 'coder_report.json')
if ($null -eq $coderReport) {
  Add-Result 'C3b' 'Coder report reconciliation' 'NA' 'No coder_report.json'
}
elseif ($coderReport -eq '__PARSE_ERROR__') {
  Add-Result 'C3b' 'Coder report reconciliation' 'FAIL' 'coder_report.json invalid JSON'
}
elseif (-not $hasEdits) {
  Add-Result 'C3b' 'Coder report reconciliation' 'FAIL' 'coder_report.json present but no diffs to reconcile against'
}
else {
  $cls = @()
  foreach ($df in $diffFiles) { $cls += Get-DiffClassified (Get-Content -LiteralPath $df.FullName -Raw -Encoding UTF8) }
  function Norm-Path($p) { return (($p -replace '\\', '/') -replace '^\./', '') }
  $dCreated = @($cls | Where-Object { $_.kind -eq 'created' } | ForEach-Object { Norm-Path $_.path } | Select-Object -Unique)
  $dDeleted = @($cls | Where-Object { $_.kind -eq 'deleted' } | ForEach-Object { Norm-Path $_.path } | Select-Object -Unique)
  $dRenamed = @($cls | Where-Object { $_.kind -eq 'renamed' } | ForEach-Object { Norm-Path $_.path } | Select-Object -Unique)
  $dModified = @($cls | Where-Object { $_.kind -eq 'modified' } | ForEach-Object { Norm-Path $_.path } | Select-Object -Unique)
  function Compare-ReportSet($reportArr, $diffArr, $label) {
    $r = @(@($reportArr) | ForEach-Object { Norm-Path $_ })
    $d = @($diffArr)
    $out = @()
    $under = @($d | Where-Object { $r -notcontains $_ })
    $over = @($r | Where-Object { $_ -and ($d -notcontains $_) })
    if ($under.Count) { $out += "$label under-reported: " + ($under -join ',') }
    if ($over.Count) { $out += "$label over-reported: " + ($over -join ',') }
    return $out
  }
  $problems = @()
  $problems += Compare-ReportSet $coderReport.files_created $dCreated 'files_created'
  $problems += Compare-ReportSet $coderReport.files_modified $dModified 'files_modified'
  $problems += Compare-ReportSet $coderReport.files_deleted $dDeleted 'files_deleted'
  $destructiveInDiff = (($dDeleted.Count + $dRenamed.Count) -gt 0)
  if ($destructiveInDiff -and (@($coderReport.destructive_ops_used).Count -eq 0)) { $problems += 'destructive op in diff but destructive_ops_used empty' }
  if ($destructiveInDiff -and (@($coderReport.snapshots_created).Count -eq 0)) { $problems += 'destructive op in diff but snapshots_created empty' }
  if (-not $coderReport.diff_path) { $problems += 'diff_path missing' }
  else {
    $dp = Join-Path $SessionPath ($coderReport.diff_path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $dp)) { $problems += "diff_path points to non-existent patch ($($coderReport.diff_path))" }
  }
  if ($problems.Count -gt 0) { Add-Result 'C3b' 'Coder report reconciliation' 'FAIL' ($problems -join '; ') }
  else { Add-Result 'C3b' 'Coder report reconciliation' 'PASS' "report matches diff (created=$($dCreated.Count) modified=$($dModified.Count) deleted=$($dDeleted.Count))" }
}

# ===== C5 - RESIDUE: manifest + per-surface snapshots + 2nd run =====
$residue = Read-Json $residuePath
if ($null -eq $residue) { $residue = Read-Json $residueAltPath }
$surfacesUsed = $false
if ($contract -and $contract -ne '__PARSE_ERROR__' -and $contract.external_accounts_registry.Count -gt 0) { $surfacesUsed = $true }
if ($null -eq $residue -or $residue -eq '__PARSE_ERROR__') {
  if ($isEnd -or $surfacesUsed) {
    Add-Result 'C5' 'Residue (2-layer + 2nd run)' 'FAIL' 'Residue report missing/invalid but END gate or state surfaces in use'
  } else {
    Add-Result 'C5' 'Residue (2-layer + 2nd run)' 'PENDING' 'No residue report yet (verifier not run)'
  }
}
else {
  $problems = @()
  # Undeclared external use guard
  if ($contract -and $contract -ne '__PARSE_ERROR__') {
    if ($contract.external_accounts_registry.Count -gt 0 -and ($contract.state_surfaces -notcontains 'external_account')) {
      $problems += 'external_accounts_registry non-empty but external_account not in state_surfaces'
    }
    # state_surfaces must match between contract and report
    $cs = @($contract.state_surfaces) | Sort-Object
    $rs = @($residue.state_surfaces) | Sort-Object
    if (($cs -join ',') -ne ($rs -join ',')) {
      $problems += "state_surfaces mismatch (contract=[$($cs -join ',')] report=[$($rs -join ',')])"
    }
    # every declared surface needs a clean snapshot
    foreach ($surface in $contract.state_surfaces) {
      $snap = $residue.snapshots.$surface
      if ($null -eq $snap) { $problems += "missing snapshot for declared surface '$surface'" }
      elseif (-not $snap.diff_clean) { $problems += "snapshot for '$surface' not diff_clean" }
    }
  }
  if (-not $residue.manifest_cleanup_complete) { $problems += 'manifest_cleanup_complete=false' }
  if (-not $residue.second_run_pass) { $problems += 'second_run_pass=false' }
  if ($problems.Count -gt 0) {
    Add-Result 'C5' 'Residue (2-layer + 2nd run)' 'FAIL' ($problems -join '; ')
  } else {
    Add-Result 'C5' 'Residue (2-layer + 2nd run)' 'PASS' 'Manifest clean + per-surface snapshots clean + 2nd run pass'
  }
}

# ===== C6 - TESTS: promised cmd, non-cached, exit 0 =====
$verSummary = Read-Json (Join-Path $verResultsDir 'summary.json')
$testsRun = ($verSummary -and $verSummary -ne '__PARSE_ERROR__')
if (-not $testsRun) {
  if ($isEnd) { Add-Result 'C6' 'Tests (promised, non-cached, exit0)' 'FAIL' 'No verifier_results/summary.json at END gate' }
  else { Add-Result 'C6' 'Tests (promised, non-cached, exit0)' 'PENDING' 'No verifier_results/summary.json yet' }
}
else {
  $problems = @()
  if ($contract -and $contract -ne '__PARSE_ERROR__') {
    $promised = @($contract.test_plan) | Sort-Object
    $actual = @($verSummary.tests_command) | Sort-Object
    if (($promised -join '||') -ne ($actual -join '||')) {
      $problems += "test command drift (promised=[$($promised -join '; ')] actual=[$($actual -join '; ')])"
    }
  }
  if ($verSummary.cached -eq $true) { $problems += 'tests/typecheck ran from cache (green-from-cache)' }
  if ($null -ne $verSummary.typecheck_exit -and $verSummary.typecheck_exit -ne 0) { $problems += "typecheck_exit=$($verSummary.typecheck_exit)" }
  if ($null -ne $verSummary.tests_exit -and $verSummary.tests_exit -ne 0) { $problems += "tests_exit=$($verSummary.tests_exit)" }
  if ($problems.Count -gt 0) {
    Add-Result 'C6' 'Tests (promised, non-cached, exit0)' 'FAIL' ($problems -join '; ')
  } else {
    Add-Result 'C6' 'Tests (promised, non-cached, exit0)' 'PASS' 'Promised cmd, non-cached, exits 0'
  }
}

# ===== C7 - AUDITOR: required only when a trigger fired =====
$auditTriggered = $false
$triggerReason = ''
if ($contract -and $contract -ne '__PARSE_ERROR__') {
  if ($isEnd -and ($contract.fresh_audit_required_when -contains 'end_gate')) { $auditTriggered = $true; $triggerReason = 'end_gate' }
  if ($contract.graduation_target -and ($contract.fresh_audit_required_when -contains 'graduation_candidate')) { $auditTriggered = $true; $triggerReason = 'graduation_candidate' }
}
if (-not $auditTriggered) {
  Add-Result 'C7' 'Auditor (fresh, cited findings)' 'NA' 'No fresh-audit trigger fired this phase'
}
else {
  $problems = @()
  if (-not (Test-Path -LiteralPath $auditorReport)) { $problems += 'auditor_report.md missing' }
  $finds = Read-Json $auditorFinds
  if ($null -eq $finds) { $problems += 'auditor_findings.json missing' }
  elseif ($finds -eq '__PARSE_ERROR__') { $problems += 'auditor_findings.json invalid JSON' }
  else {
    # New structured shape: object with fresh-context + input attestation + findings[].
    if ($finds.auditor_context_fresh -ne $true) { $problems += 'auditor_context_fresh != true' }
    if ($finds.forbidden_inputs_seen -ne $false) { $problems += 'forbidden_inputs_seen != false (auditor saw forbidden input)' }
    $allowedInputs = @('session_contract.json', 'changed_files', 'git_diff.patch', 'test_results.txt', 'typecheck_results.txt', 'verifier_residue_report.json', 'known_constraints.md')
    foreach ($ia in @($finds.input_artifacts)) {
      $base = ($ia -replace '/', '\').Split('\')[-1]
      if (($allowedInputs -notcontains $base) -and ($allowedInputs -notcontains $ia)) { $problems += "input_artifact '$ia' not in allowlist" }
    }
    if (@('GO', 'NEEDS-MORE', 'NO-GO') -notcontains $finds.recommendation) { $problems += "recommendation '$($finds.recommendation)' invalid" }

    # --- OBJECTIVE cross-check vs AUDITOR_INPUT/input_manifest.json (authoritative; self-fields are secondary) ---
    $aiDir = Join-Path $SessionPath 'AUDITOR_INPUT'
    $manifest = Read-Json (Join-Path $aiDir 'input_manifest.json')
    if ($null -eq $manifest -or $manifest -eq '__PARSE_ERROR__') {
      $problems += 'AUDITOR_INPUT/input_manifest.json missing/invalid (run assemble_auditor_input.ps1)'
    } else {
      $forbiddenPat = '(?i)(coder.?chat|history|self.?eval|why.*safe)'
      $manifestRel = @()
      foreach ($rec in @($manifest.files)) {
        $manifestRel += ($rec.relative_path -replace '\\', '/')
        if ($allowedInputs -notcontains $rec.allowlist_category) { $problems += "manifest file '$($rec.relative_path)' category not in allowlist" }
        if ($rec.relative_path -match $forbiddenPat) { $problems += "manifest contains forbidden artifact '$($rec.relative_path)'" }
        $disk = Join-Path $aiDir ($rec.relative_path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $disk)) { $problems += "manifest file missing on disk: $($rec.relative_path)" }
        else { $h = (Get-FileHash -LiteralPath $disk -Algorithm SHA256).Hash; if ($h -ne $rec.sha256) { $problems += "artifact changed since assembly: $($rec.relative_path)" } }
      }
      # no EXTRA files in AUDITOR_INPUT beyond the manifest
      if (Test-Path -LiteralPath $aiDir) {
        $aiResolved = (Resolve-Path -LiteralPath $aiDir).Path
        foreach ($af in (Get-ChildItem -LiteralPath $aiDir -Recurse -File -ErrorAction SilentlyContinue)) {
          if ($af.Name -eq 'input_manifest.json') { continue }
          $arel = $af.FullName.Substring($aiResolved.Length).TrimStart('\', '/').Replace('\', '/')
          if ($manifestRel -notcontains $arel) { $problems += "extra file in AUDITOR_INPUT (not in manifest): $arel" }
        }
      }
      # auditor's declared inputs must all be categories present in the manifest
      $manifestCats = @(@($manifest.files | ForEach-Object { $_.allowlist_category }) | Select-Object -Unique)
      foreach ($ia in @($finds.input_artifacts)) {
        $base = ($ia -replace '/', '\').Split('\')[-1]
        if (($manifestCats -notcontains $ia) -and ($manifestCats -notcontains $base)) { $problems += "declared input '$ia' not present in assembled manifest" }
      }
    }

    $allowedEvidence = @('file_line', 'diff_hunk', 'test_output', 'residue_report', 'contract')
    $i = 0
    foreach ($f in @($finds.findings)) {
      $i++
      foreach ($req in @('id', 'severity', 'evidence_type', 'claim')) {
        if ($null -eq $f.$req) { $problems += "finding[$i] missing '$req'" }
      }
      if ($f.evidence_type -and ($allowedEvidence -notcontains $f.evidence_type)) {
        $problems += "finding[$i] bad evidence_type '$($f.evidence_type)'"
      }
      # citation must resolve for file_line evidence
      if ($f.evidence_type -eq 'file_line' -and $f.path) {
        $cited = Join-Path $SessionPath ('changed_files\' + ($f.path -replace '/', '\'))
        $citedAlt = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path ($f.path -replace '/', '\')
        $target = $null
        if (Test-Path -LiteralPath $cited) { $target = $cited }
        elseif (Test-Path -LiteralPath $citedAlt) { $target = $citedAlt }
        if (-not $target) { $problems += "finding[$i] cites non-existent path '$($f.path)'" }
        elseif ($null -ne $f.line_end) {
          $lc = (Get-Content -LiteralPath $target).Count
          if ($f.line_end -gt $lc) { $problems += "finding[$i] line_end $($f.line_end) > file length $lc" }
        }
      }
    }
  }
  if ($problems.Count -gt 0) {
    Add-Result 'C7' 'Auditor (fresh, cited findings)' 'FAIL' ("trigger=$triggerReason; " + ($problems -join '; '))
  } else {
    Add-Result 'C7' 'Auditor (fresh, cited findings)' 'PASS' "trigger=$triggerReason; fresh, input-allowlisted, recommendation valid, citations resolve"
  }
}

# ===== C8 - MODEL ROUTING + 3-surface dispatch reconciliation =====
# Three surfaces must agree: orchestrator_dispatch_log.jsonl <-> model_routing_log.json <-> subagent_prompts/
$subPromptsDir = Join-Path $SessionPath 'subagent_prompts'
$promptFiles = @()
if (Test-Path -LiteralPath $subPromptsDir) { $promptFiles = @(Get-ChildItem -LiteralPath $subPromptsDir -File -ErrorAction SilentlyContinue) }
$promptNames = @($promptFiles | ForEach-Object { $_.Name })

$dispatchLogPath = Join-Path $SessionPath 'orchestrator_dispatch_log.jsonl'
$dispatchEntries = @(); $dispatchParseErr = $false
if (Test-Path -LiteralPath $dispatchLogPath) {
  foreach ($line in (Get-Content -LiteralPath $dispatchLogPath -Encoding UTF8)) {
    $tl = $line.Trim(); if (-not $tl) { continue }
    try { $dispatchEntries += ($tl | ConvertFrom-Json) } catch { $dispatchParseErr = $true }
  }
}

$routing = Read-Json $routingLog
$routingActive = ($routing -and ($routing -ne '__PARSE_ERROR__') -and ($routing.routing_mode -ne 'not_applicable_foundation_only'))
$dispatchEvidence = ($promptNames.Count -gt 0) -or ($dispatchEntries.Count -gt 0) -or ($routingActive -and @($routing.entries).Count -gt 0)

function Test-PromptRef($pp) {
  if (-not $pp) { return $false }
  $bn = ($pp -replace '/', '\').Split('\')[-1]
  return ($promptNames -contains $bn)
}

if (-not $dispatchEvidence) {
  if ($routing -eq '__PARSE_ERROR__') { Add-Result 'C8' 'Routing + dispatch reconciliation' 'FAIL' 'model_routing_log.json invalid JSON' }
  elseif ($null -ne $routing -and $routing.routing_mode -eq 'not_applicable_foundation_only') { Add-Result 'C8' 'Routing + dispatch reconciliation' 'PASS' 'routing_mode=not_applicable_foundation_only; no dispatch' }
  else { Add-Result 'C8' 'Routing + dispatch reconciliation' 'NA' 'No dispatch recorded' }
}
else {
  $problems = @()
  if ($dispatchParseErr) { $problems += 'orchestrator_dispatch_log.jsonl has invalid JSON line(s)' }
  if ($null -eq $routing) { $problems += 'dispatch evidence present but model_routing_log.json missing' }
  elseif ($routing -eq '__PARSE_ERROR__') { $problems += 'model_routing_log.json invalid JSON' }
  elseif ($routing.routing_mode -eq 'not_applicable_foundation_only') { $problems += 'routing_mode=not_applicable_foundation_only but dispatch evidence present' }
  else {
    $routingByTask = @{}; foreach ($e in @($routing.entries)) { if ($e.task_id) { $routingByTask[$e.task_id] = $e } }
    $dispatchByTask = @{}; foreach ($d in $dispatchEntries) { if ($d.task_id) { $dispatchByTask[$d.task_id] = $d } }
    # policy validation per routing entry
    foreach ($e in @($routing.entries)) {
      if ($null -eq $e.task_classification -or $null -eq $e.model_used) { $problems += "routing '$($e.task_id)' missing task_classification/model_used"; continue }
      $expected = $null
      if ($contract -and $contract -ne '__PARSE_ERROR__') { $expected = $contract.model_routing_policy.($e.task_classification) }
      if (-not $expected) { $problems += "routing '$($e.task_id)': classification '$($e.task_classification)' has no policy mapping"; continue }
      if ($e.model_used -ne $expected -and -not (($e.override -eq $true) -and $e.override_reason)) {
        $problems += "routing '$($e.task_id)': '$($e.task_classification)'->policy '$expected' but used '$($e.model_used)' (no approved override)"
      }
    }
    # dispatch <-> routing consistency + prompt presence
    foreach ($tid in $dispatchByTask.Keys) {
      $d = $dispatchByTask[$tid]
      if ($routingByTask.ContainsKey($tid)) {
        $r = $routingByTask[$tid]
        if ($d.task_classification -ne $r.task_classification) { $problems += "task '$tid': classification differs dispatch='$($d.task_classification)' vs routing='$($r.task_classification)'" }
        if ($d.model_used -ne $r.model_used) { $problems += "task '$tid': model_used differs dispatch='$($d.model_used)' vs routing='$($r.model_used)'" }
      } else { $problems += "dispatch task '$tid' has no model_routing_log entry" }
      if ((@('dispatched', 'completed') -contains $d.status) -and -not (Test-PromptRef $d.prompt_path)) { $problems += "dispatch task '$tid' status '$($d.status)' but prompt file missing ($($d.prompt_path))" }
    }
    # prompt file with no dispatch entry
    foreach ($pf in $promptNames) {
      $ref = $false
      foreach ($d in $dispatchEntries) { if ($d.prompt_path -and ((($d.prompt_path -replace '/', '\').Split('\')[-1]) -eq $pf)) { $ref = $true; break } }
      if (-not $ref) { $problems += "prompt file '$pf' has no orchestrator_dispatch_log entry" }
    }
    # routing task with no prompt_path anywhere
    foreach ($tid in $routingByTask.Keys) {
      $hasPrompt = ($dispatchByTask.ContainsKey($tid) -and (Test-PromptRef $dispatchByTask[$tid].prompt_path))
      if (-not $hasPrompt) { $problems += "routing task '$tid' has no prompt_path / prompt file" }
    }
  }
  if ($problems.Count -gt 0) { Add-Result 'C8' 'Routing + dispatch reconciliation' 'FAIL' ($problems -join '; ') }
  else { Add-Result 'C8' 'Routing + dispatch reconciliation' 'PASS' "reconciled: $(@($routing.entries).Count) routed / $($dispatchEntries.Count) dispatched / $($promptNames.Count) prompts" }
}

# ===== C9 - SECRET-SHAPED VALUE SCAN (heuristic, always) =====
$secretTargets = @()
if (Test-Path -LiteralPath $diffsDir) { $secretTargets += (Get-ChildItem -LiteralPath $diffsDir -File -Recurse -ErrorAction SilentlyContinue) }
if (Test-Path -LiteralPath $verResultsDir) { $secretTargets += (Get-ChildItem -LiteralPath $verResultsDir -File -Recurse -ErrorAction SilentlyContinue) }
foreach ($f in @($stopReason, $routingLog, $auditorReport, $endSummary, $startPacket, (Join-Path $SessionPath 'checkpoint.json'))) {
  if (Test-Path -LiteralPath $f) { $secretTargets += (Get-Item -LiteralPath $f) }
}
$secretPatterns = @(
  'sk-[A-Za-z0-9]{16,}',
  'AKIA[0-9A-Z]{16}',
  '-----BEGIN [A-Z ]*PRIVATE KEY-----',
  '(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*["''][A-Za-z0-9/_+\-]{16,}["'']',
  'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'
)
$hits = @()
foreach ($f in ($secretTargets | Select-Object -Unique)) {
  $txt = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
  if (-not $txt) { continue }
  foreach ($pat in $secretPatterns) {
    if ([regex]::IsMatch($txt, $pat)) { $hits += "$($f.Name) ~ /$pat/" }
  }
}
if ($hits.Count -gt 0) {
  Add-Result 'C9' 'Secret-shaped scan (heuristic)' 'FAIL' ("Possible secret VALUE: " + (($hits | Select-Object -Unique) -join '; '))
} else {
  Add-Result 'C9' 'Secret-shaped scan (heuristic)' 'PASS' 'No secret-shaped values (heuristic; NOT complete prevention)'
}

# ===== C10 - END SUMMARY required fields =====
if (-not $isEnd) {
  Add-Result 'C10' 'END summary required fields' 'PENDING' 'No ambassador_end_summary.md yet (not at END)'
}
else {
  $txt = Get-Content -LiteralPath $endSummary -Raw -Encoding UTF8
  $required = @(
    @('status verdict', '(?i)status\b[\s\S]{0,40}?(needs-more|no-go|go)'),
    @('blocking failures section', '(?i)blocking failures'),
    @('warnings section', '(?i)warnings?\b'),
    @('what changed', '(?i)what changed'),
    @('what was tested', '(?i)what was tested'),
    @('what failed/skipped', '(?i)failed or was skipped|failed/skipped|fail[\s\S]{0,20}skip'),
    @('residue status', '(?i)residue'),
    @('budget/scope deviations', '(?i)budget|scope'),
    @('known limitations/unverified', '(?i)known limitation|unverified'),
    @('decision question', '(?i)keep\s*/\s*iterate\s*/\s*toss')
  )
  $missing = @()
  foreach ($r in $required) { if (-not [regex]::IsMatch($txt, $r[1])) { $missing += $r[0] } }
  if ($missing.Count -gt 0) {
    Add-Result 'C10' 'END summary required fields' 'FAIL' ("Missing: " + ($missing -join ', '))
  } else {
    Add-Result 'C10' 'END summary required fields' 'PASS' 'All required fields present'
  }
  if (Test-Path -LiteralPath $stopReason) {
    $sr = Read-Json $stopReason
    if ($sr -eq '__PARSE_ERROR__') { Add-Result 'C10b' 'stop_reason valid' 'FAIL' 'stop_reason.json invalid JSON' }
  }
}

# ===== C11 - CHECKPOINT VALID (if present) =====
$checkpoint = Read-Json (Join-Path $SessionPath 'checkpoint.json')
if ($null -eq $checkpoint) {
  Add-Result 'C11' 'Checkpoint valid (if present)' 'NA' 'No checkpoint.json'
}
elseif ($checkpoint -eq '__PARSE_ERROR__') {
  Add-Result 'C11' 'Checkpoint valid (if present)' 'FAIL' 'checkpoint.json invalid JSON'
}
else {
  $cpSchema = Read-Json (Join-Path $SchemaDir 'checkpoint.schema.json')
  if ($null -eq $cpSchema -or $cpSchema -eq '__PARSE_ERROR__') { Add-Result 'C11' 'Checkpoint valid (if present)' 'FAIL' 'checkpoint.schema.json missing/invalid' }
  else {
    $cpMissing = Test-RequiredFromSchema $checkpoint $cpSchema
    if ($cpMissing.Count -gt 0) { Add-Result 'C11' 'Checkpoint valid (if present)' 'FAIL' ("Missing required: " + ($cpMissing -join ', ')) }
    else { Add-Result 'C11' 'Checkpoint valid (if present)' 'PASS' 'Required fields present' }
  }
}

# ===== C13 - GRADUATION CONTRACT (only if graduation_target != null) =====
if ($contract -and ($contract -ne '__PARSE_ERROR__') -and $contract.graduation_target) {
  $ccr = Read-Json (Join-Path $SessionPath 'contract_check_report.json')
  if ($null -eq $ccr) { Add-Result 'C13' 'Graduation contract check' 'FAIL' 'graduation_target set but no contract_check_report.json (run contract_check.ps1)' }
  elseif ($ccr -eq '__PARSE_ERROR__') { Add-Result 'C13' 'Graduation contract check' 'FAIL' 'contract_check_report.json invalid JSON' }
  elseif ($ccr.status -ne 'PASS') { Add-Result 'C13' 'Graduation contract check' 'FAIL' "contract_check status=$($ccr.status): $(@($ccr.problems) -join '; ')" }
  else { Add-Result 'C13' 'Graduation contract check' 'PASS' "graduation candidate conforms ($($contract.graduation_target))" }
}
else {
  Add-Result 'C13' 'Graduation contract check' 'NA' 'not a graduation candidate (graduation_target null)'
}

# ===== END-GATE STRICTNESS (ChatGPT-required) =====
# At END: PENDING is RED. NA on a mandatory check is RED unless the contract justifies it.
if ($endMode) {
  $mandatoryAtEnd = @('C5', 'C6', 'C7', 'C10')
  foreach ($r in $script:results) {
    if ($r.Status -eq 'PENDING') {
      $r.Status = 'FAIL'
      $r.Detail = "END-gate: PENDING not allowed. " + $r.Detail
    }
    elseif ($r.Status -eq 'NA' -and ($mandatoryAtEnd -contains $r.Check)) {
      $just = $null
      if ($contract -and $contract -ne '__PARSE_ERROR__' -and (Test-HasKey $contract 'na_justifications')) {
        $just = $contract.na_justifications.($r.Check)
      }
      if ($just) {
        $r.Detail = "END-gate NA justified by contract: $just | " + $r.Detail
      } else {
        $r.Status = 'FAIL'
        $r.Detail = "END-gate: NA on mandatory check without na_justifications['$($r.Check)']. " + $r.Detail
      }
    }
  }
}

# ===== C12 - END summary NO-SANITIZE mapping (the gate's own enforcement, END only) =====
if ($endMode -and (Test-Path -LiteralPath $endSummary)) {
  $sumTxt = (Get-Content -LiteralPath $endSummary -Raw -Encoding UTF8).ToLower()
  # fail IDs from THIS run's results (post-strictness), + PM consistency, + high/critical auditor paths
  $failIDs = @(@($script:results | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object { $_.Check }) | Select-Object -Unique)
  $warnIDs = @(); $auditPaths = @()
  $pmcR = Read-Json (Join-Path $SessionPath 'pm_consistency_report.json')
  if ($pmcR -and $pmcR -ne '__PARSE_ERROR__') {
    foreach ($f in @($pmcR.findings)) {
      $fid = ($f.Rule -split '\s+')[0]
      if ($f.Status -eq 'FAIL') { $failIDs += $fid } elseif ($f.Status -eq 'WARN') { $warnIDs += $fid }
    }
  }
  $findsR = Read-Json (Join-Path $SessionPath 'auditor_findings.json')
  if ($findsR -and $findsR -ne '__PARSE_ERROR__') {
    $fl = $findsR.findings; if ($null -eq $fl) { $fl = $findsR }
    foreach ($f in @($fl)) { if (@('high', 'critical') -contains $f.severity) { $auditPaths += $f.path } }
  }
  $failIDs = @($failIDs | Select-Object -Unique); $warnIDs = @($warnIDs | Select-Object -Unique); $auditPaths = @($auditPaths | Select-Object -Unique)
  $statusGO = $false
  $sm = [regex]::Match($sumTxt, 'status\b[\s\S]{0,40}?(needs-more|no-go|go)')
  if ($sm.Success -and $sm.Groups[1].Value -eq 'go') { $statusGO = $true }
  $hasFail = ($failIDs.Count -gt 0) -or ($auditPaths.Count -gt 0)
  $c12 = @()
  if ($hasFail -and $statusGO) { $c12 += 'Status=GO despite failures/high-severity findings' }
  if ($hasFail) {
    if (-not [regex]::IsMatch($sumTxt, 'blocking failures')) { $c12 += 'no Blocking failures section' }
    foreach ($id in $failIDs) { if (-not [regex]::IsMatch($sumTxt, [regex]::Escape([string]$id).ToLower())) { $c12 += "FAIL '$id' not surfaced" } }
    foreach ($p in $auditPaths) { if ($p -and -not $sumTxt.Contains(([string]$p).ToLower())) { $c12 += "high/critical finding '$p' not surfaced" } }
  }
  if ($warnIDs.Count -gt 0) {
    if (-not [regex]::IsMatch($sumTxt, 'warnings?\b')) { $c12 += 'no Warnings section' }
    foreach ($id in $warnIDs) { if (-not [regex]::IsMatch($sumTxt, [regex]::Escape([string]$id).ToLower())) { $c12 += "WARN '$id' not surfaced" } }
  }
  if ($c12.Count -gt 0) { Add-Result 'C12' 'END summary no-sanitize mapping' 'FAIL' ($c12 -join '; ') }
  else { Add-Result 'C12' 'END summary no-sanitize mapping' 'PASS' 'all FAIL/WARN/high-severity ids surfaced; status consistent' }
}
else { Add-Result 'C12' 'END summary no-sanitize mapping' 'NA' 'not END phase' }

# ---- persist machine-readable result so NEO_AMBASSADOR can map check IDs (A3 strict mapping) ----
$auditResult = [pscustomobject]@{
  session_path = $SessionPath
  mode         = $Mode
  end_mode     = $endMode
  checks       = @($script:results)
}
$auditResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $SessionPath 'audit_result.json') -Encoding UTF8

# ---- report ----
Write-Host ""
Write-Host "NEO session audit: $SessionPath"
$phaseLabel = 'IN-PROGRESS / START'
if ($endMode) { $phaseLabel = 'END' }
Write-Host ("Phase: " + $phaseLabel + "   (Mode=$Mode)")
$script:results | Format-Table -AutoSize Check, Status, Name, Detail

$failCount = @($script:results | Where-Object { $_.Status -eq 'FAIL' }).Count
$pendCount = @($script:results | Where-Object { $_.Status -eq 'PENDING' }).Count
Write-Host ""
if ($failCount -gt 0) {
  Write-Host "RESULT: RED - $failCount FAIL. (Partial green = red.)" -ForegroundColor Red
  exit 1
} elseif ($pendCount -gt 0) {
  Write-Host "RESULT: INCOMPLETE - 0 FAIL, $pendCount PENDING (artifacts not yet produced)." -ForegroundColor Yellow
  exit 0
} else {
  Write-Host "RESULT: GREEN - all applicable checks pass." -ForegroundColor Green
  exit 0
}

