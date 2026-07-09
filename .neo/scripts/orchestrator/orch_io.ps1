# orch_io.ps1 - NEO 4.0-P3-B (B1) evidence I/O + provenance + snapshot library.
# ASCII-only (D10). Dot-source; defines functions only.
. "$PSScriptRoot\orch_schema.ps1"
. "$PSScriptRoot\orch_class.ps1"

# Canonical program-artifact names (exact <NAME>.json runtime homes; A-BRIDGE 5).
$script:NeoProgramNames = @{
  'PROJECT_SPEC'       = 'neo:project_spec'
  'CONSTRAINT_PACKAGE' = 'neo:constraint_package'
  'ARCHITECTURE'       = 'neo:architecture'
  'RISK_REGISTER'      = 'neo:risk_register'
  'SUBSESSION_INDEX'   = 'neo:subsession_index'
  'MASTER_CHECKPOINT'  = 'neo:master_checkpoint'
  'HANDOFF_PACKET'     = 'neo:handoff_packet'
}

function New-NeoBlock([string]$msg) { throw "NEO-BLOCK: $msg" }

# Envelope content_hash is computed over the artifact body with BOTH the envelope
# and any self_hash excluded. Excluding self_hash too breaks the mutual dependency
# for input_packet-family artifacts (which carry self_hash AND _provenance.content_hash);
# for artifacts without a self_hash it is a harmless no-op. Verification uses the
# identical exclusion set, so the hash is internally self-consistent by construction.
$script:NeoHashExclude = @('_provenance', 'self_hash')

# --- fail-closed schema gate: throws NEO-BLOCK on any violation ---------------
function Assert-NeoValid($Instance, [string]$SchemaId, $Index, [string]$Label) {
  if (-not $Index.ContainsKey($SchemaId)) { New-NeoBlock "unknown schema id '$SchemaId' for $Label" }
  $viol = @(Test-NeoSchema -Instance $Instance -Schema $Index[$SchemaId] -Index $Index -Path '$')
  if ($viol.Count -gt 0) {
    $shown = ($viol | Select-Object -First 12) -join ' ; '
    New-NeoBlock "$Label failed schema '$SchemaId' ($($viol.Count) violation(s)): $shown"
  }
}

# --- JSON file read/write (evidence) -----------------------------------------
function Read-NeoJsonFile([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { New-NeoBlock "evidence file missing: $path" }
  try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
  catch { New-NeoBlock "evidence file is invalid JSON: $path" }
}

function Write-NeoJsonFile([string]$path, $obj) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  # structure-preserving writer (NOT ConvertTo-Json): keeps single-element arrays
  # as arrays so files round-trip for schema validation and body-hashing.
  (ConvertTo-NeoPrettyJson $obj 0) | Set-Content -LiteralPath $path -Encoding UTF8
}

# --- program-home path resolver (exact names; NEVER a *.PLACEHOLDER glob) -----
function Get-NeoProgramPath([string]$ProgramRoot, [string]$Name) {
  if (-not $script:NeoProgramNames.ContainsKey($Name)) { New-NeoBlock "not a program artifact name: $Name" }
  return (Join-Path $ProgramRoot ("$Name.json"))
}

function Read-NeoProgramArtifact([string]$ProgramRoot, [string]$Name, $Index) {
  $p = Get-NeoProgramPath $ProgramRoot $Name
  $obj = Read-NeoJsonFile $p
  Assert-NeoValid $obj $script:NeoProgramNames[$Name] $Index $Name
  Assert-NeoArtifactHash $obj $Name
  return $obj
}

# --- snapshot before overwrite (rollback boundary, D8 / DEF-DESTRUCTIVE) ------
function Save-NeoSnapshot([string]$path, [string]$SnapshotDir) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }   # nothing to snapshot (create, not overwrite)
  if (-not (Test-Path -LiteralPath $SnapshotDir)) { New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null }
  $stamp = (Get-Date).ToString('yyyyMMddHHmmssfff')
  $dest = Join-Path $SnapshotDir ((Split-Path -Leaf $path) + ".$stamp.snap")
  Copy-Item -LiteralPath $path -Destination $dest -Force
  return $dest
}

# Write a program artifact fail-closed: validate, snapshot-if-overwrite, write.
function Write-NeoProgramArtifact {
  param([string]$ProgramRoot, [string]$Name, $Obj, $Index, [string]$SnapshotDir)
  Assert-NeoValid $Obj $script:NeoProgramNames[$Name] $Index $Name
  $p = Get-NeoProgramPath $ProgramRoot $Name
  if ($SnapshotDir) { [void](Save-NeoSnapshot $p $SnapshotDir) }
  Write-NeoJsonFile $p $Obj
  return $p
}

# --- provenance envelope ------------------------------------------------------
# created_at / updated_at are CALLER-SUPPLIED (agents never self-generate time).
function New-NeoEnvelope {
  param(
    [string]$ArtifactId, [string]$ArtifactClass, [string]$SchemaId, [string]$SchemaVersion,
    [string]$ProducerRole, [string]$ProducerClass,
    [string]$ValidatorRole, [string]$ValidatorClass, [string]$ValidatorNAReason,
    [string]$Timestamp, [string[]]$DeclaredPaths, [string[]]$DeclaredSurfaces,
    $SourcePackets, $GateRef
  )
  if ([string]::IsNullOrEmpty($Timestamp)) { New-NeoBlock "envelope requires a caller-supplied Timestamp (agents do not self-generate time)" }
  if (-not (Test-NeoKnownEnvelopeClass $ArtifactClass)) { New-NeoBlock "unknown artifact_class '$ArtifactClass' => BLOCK (A7)" }
  $validator = @{ role = $ValidatorRole; model_class = $ValidatorClass; model_name = $null }
  if ($ValidatorNAReason) { $validator['not_applicable_reason'] = $ValidatorNAReason }
  $surfaces = @(); if ($DeclaredSurfaces) { $surfaces = @($DeclaredSurfaces) }
  $paths = @(); if ($DeclaredPaths) { $paths = @($DeclaredPaths) }
  $pkts = @(); if ($SourcePackets) { $pkts = @($SourcePackets) }
  $gate = $null; if ($PSBoundParameters.ContainsKey('GateRef')) { $gate = $GateRef }
  return [pscustomobject]@{
    artifact_id       = $ArtifactId
    artifact_class    = $ArtifactClass
    schema_id         = $SchemaId
    schema_version    = $SchemaVersion
    producer_identity = @{ role = $ProducerRole; model_class = $ProducerClass; model_name = $null }
    validator_identity = $validator
    created_at        = $Timestamp
    updated_at        = $Timestamp
    content_hash      = @{ algo = 'sha256'; value = 'UNSET' }
    scope_boundary    = @{ declared_paths = $paths; declared_surfaces = $surfaces }
    source_input_packets = $pkts
    gate_ref          = $gate
  }
}

# Compute + stamp the envelope self-hash (body excludes _provenance and self_hash).
function Set-NeoArtifactHash($artifact) {
  if (-not (Test-NeoHasProp $artifact '_provenance')) { New-NeoBlock "artifact has no _provenance to hash" }
  $h = Get-NeoBodyHash $artifact $script:NeoHashExclude
  $prov = Get-NeoProp $artifact '_provenance'
  $ch = Get-NeoProp $prov 'content_hash'
  if ($ch -is [hashtable]) { $ch['value'] = $h } else { $ch.value = $h }
}

function Assert-NeoArtifactHash($artifact, [string]$Label) {
  if (-not (Test-NeoHasProp $artifact '_provenance')) { New-NeoBlock "$Label has no _provenance" }
  $prov = Get-NeoProp $artifact '_provenance'
  $ch = Get-NeoProp $prov 'content_hash'
  $stored = Get-NeoProp $ch 'value'
  $actual = Get-NeoBodyHash $artifact $script:NeoHashExclude
  if ($stored -cne $actual) { New-NeoBlock "$Label content_hash mismatch (stored=$stored actual=$actual) => BLOCK (A6/A7)" }
}

# input_packet self_hash: sha256 of the packet body excluding only self_hash
# (includes the finalized _provenance). Call AFTER Set-NeoArtifactHash.
function Set-NeoPacketSelfHash($packet) {
  $h = Get-NeoBodyHash $packet @('self_hash')
  if ($packet -is [hashtable]) { $packet['self_hash'] = $h } else { $packet.self_hash = $h }
}

function Assert-NeoPacketSelfHash($packet, [string]$Label) {
  $stored = Get-NeoProp $packet 'self_hash'
  $actual = Get-NeoBodyHash $packet @('self_hash')
  if ($stored -cne $actual) { New-NeoBlock "$Label self_hash mismatch (stored=$stored actual=$actual) => BLOCK (A6/A7)" }
}
