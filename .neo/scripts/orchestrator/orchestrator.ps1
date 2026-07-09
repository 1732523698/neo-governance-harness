# orchestrator.ps1 - NEO 4.0-P3-B (B1) operator CLI for the serial master engine.
# ASCII-only (D10). Thin surface over orch_engine.ps1. Writes NO AUDIT_RESULT.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet('init', 'validate', 'status')][string]$Command,
  [string]$ProgramRoot,
  [string]$Path,
  [string]$SchemaId,
  [string]$MasterId = 'master-run',
  [string]$SessionId = 'session-0',
  [string]$Timestamp,
  [string]$SnapshotDir,
  [string]$OrchestrationMode = 'serial'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\_neo_root.ps1"
$NeoRoot = Resolve-NeoRoot $PSScriptRoot
. "$PSScriptRoot\orch_engine.ps1"

$schemaDir = Join-Path $NeoRoot '.neo\schema'
$index = Get-NeoSchemaIndex $schemaDir

switch ($Command) {
  'validate' {
    if (-not $Path)     { throw "validate requires -Path" }
    if (-not $SchemaId) { throw "validate requires -SchemaId" }
    $obj = Read-NeoJsonFile $Path
    $viol = @(Test-NeoSchema -Instance $obj -Schema $index[$SchemaId] -Index $index -Path '$')
    if ($viol.Count -eq 0) { Write-Host "VALID against $SchemaId : $Path" -ForegroundColor Green; exit 0 }
    Write-Host "INVALID against $SchemaId ($($viol.Count)):" -ForegroundColor Red
    $viol | ForEach-Object { Write-Host "  - $_" }
    exit 1
  }
  'init' {
    if (-not $ProgramRoot) { throw "init requires -ProgramRoot" }
    if (-not $Timestamp)   { throw "init requires -Timestamp (caller-supplied ISO-8601; agents do not self-generate time)" }
    $r = Invoke-NeoInit -ProgramRoot $ProgramRoot -Index $index -MasterId $MasterId -SessionId $SessionId `
      -Timestamp $Timestamp -SnapshotDir $SnapshotDir -OrchestrationMode $OrchestrationMode
    Write-Host "INIT ok (serial). Wrote:" -ForegroundColor Green
    Write-Host "  $($r.mc_path)"
    Write-Host "  $($r.si_path)"
    exit 0
  }
  'status' {
    if (-not $ProgramRoot) { throw "status requires -ProgramRoot" }
    $mc = Read-NeoProgramArtifact $ProgramRoot 'MASTER_CHECKPOINT' $index
    $si = Read-NeoProgramArtifact $ProgramRoot 'SUBSESSION_INDEX'  $index
    Write-Host "master_id           : $($mc.master_id)"
    Write-Host "orchestration_mode  : $($mc.orchestration_mode)"
    Write-Host "subsession records  : $(@($si.records).Count)"
    exit 0
  }
}
