# orch_class.ps1 - NEO 4.0-P3-B (B1) artifact-class oracle (routing layer).
# ASCII-only (D10). Dot-source; defines functions only.
#
# Wraps the LIVE .neo/schema/artifact_classes.json as a read-only oracle.
# CROWN JEWEL (#5/#6, A4/A7): the routing layer resolves a path to its class by
# first-matching glob; an UNMATCHED path resolves to 'UNKNOWN' => the caller
# BLOCKS. It DELIBERATELY DOES NOT consume the map's default_class:implementation
# (flagged conflict C1 in D6/D10): "no matching rule" is UNKNOWN, never
# cheap-editable-by-default. The live map file is never edited by this engine.

function Get-NeoClassMap([string]$MapPath) {
  if (-not (Test-Path -LiteralPath $MapPath)) { throw "NEO-BLOCK: artifact_classes map not found: $MapPath" }
  try { return (Get-Content -LiteralPath $MapPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
  catch { throw "NEO-BLOCK: artifact_classes map is invalid JSON: $MapPath" }
}

function Test-NeoGlobMatch([string]$value, [string]$glob) {
  # Case-insensitive wildcard match (* and ?), same semantics as the spine glob rules.
  return ($value -like $glob)
}

# Returns the resolved class name, or 'UNKNOWN' when no rule glob matches.
# UNKNOWN is fail-closed at the call site; default_class is intentionally ignored.
function Resolve-NeoArtifactClass {
  param($ClassMap, [string]$Path)
  if ([string]::IsNullOrEmpty($Path)) { return 'UNKNOWN' }
  $norm = ($Path -replace '\\', '/')
  $leaf = $norm
  $slash = $norm.LastIndexOf('/')
  if ($slash -ge 0) { $leaf = $norm.Substring($slash + 1) }

  foreach ($rule in @($ClassMap.rules)) {
    foreach ($g in @($rule.globs)) {
      if ((Test-NeoGlobMatch $leaf $g) -or (Test-NeoGlobMatch $norm $g)) {
        return [string]$rule.class
      }
    }
  }
  return 'UNKNOWN'
}

# The 4.0 additive envelope classes plus the live 5. A declared artifact_class
# outside this set is fail-closed (also caught by the schema enum, defence in depth).
$script:NeoEnvelopeClasses = @(
  'implementation','constraint','test_harness','profile_risk','evidence',
  'input_packet','audit_bundle','handoff_packet','master_checkpoint'
)

function Test-NeoKnownEnvelopeClass([string]$class) {
  return ($script:NeoEnvelopeClasses -contains $class)
}

# Fail-closed resolution: UNKNOWN (unmatched path) throws NEO-BLOCK. This is the
# routing-layer guard the cheap-producer edit path (B2) is built on; here it is
# available and independently testable. It NEVER falls through to default_class.
function Assert-NeoResolvableClass($ClassMap, [string]$Path) {
  $c = Resolve-NeoArtifactClass $ClassMap $Path
  if ($c -eq 'UNKNOWN') {
    throw "NEO-BLOCK: artifact class UNKNOWN for '$Path' => BLOCK (A4/A7; routing layer does not default to implementation)"
  }
  return $c
}
