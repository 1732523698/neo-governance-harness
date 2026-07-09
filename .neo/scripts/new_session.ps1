<#
.SYNOPSIS
  Scaffold a new NEO session evidence folder from the contract template.
.DESCRIPTION
  Creates S:\NEO\NEO_SESSION\<SessionId>\ with the standard evidence subfolders and a
  session_contract.json seeded from the template (session_id filled in). Writes a start_packet
  stub. Does NOT write role skills or do any online/network/package work.
.EXAMPLE
  .\new_session.ps1 -SessionId 2026-06-09_hello-module -Goal "Build a trivial echo module"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SessionId,
  [string]$Goal = "REPLACE_ME"
)

$ErrorActionPreference = 'Stop'

$SandboxRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$TemplatePath = Join-Path $SandboxRoot '.neo\templates\session_contract.template.json'
$SessionRoot = Join-Path $SandboxRoot ('NEO_SESSION\' + $SessionId)

if (Test-Path -LiteralPath $SessionRoot) {
  throw "Session folder already exists: $SessionRoot"
}
if (-not (Test-Path -LiteralPath $TemplatePath)) {
  throw "Template not found: $TemplatePath"
}

$subdirs = @('changed_files', 'diffs', 'subagent_prompts', 'verifier_results')
New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null
foreach ($s in $subdirs) {
  New-Item -ItemType Directory -Force -Path (Join-Path $SessionRoot $s) | Out-Null
}

# Seed the contract from the template. session_id is an exact token; goal is matched by regex so it
# stays robust if the template's placeholder wording changes.
$contractText = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
$contractText = $contractText.Replace('"session_id": "REPLACE_ME"', '"session_id": "' + $SessionId + '"')
if ($Goal -ne 'REPLACE_ME') {
  $goalEscaped = $Goal.Replace('\', '\\').Replace('"', '\"')
  $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) '"goal": "' + $goalEscaped + '"' }
  $contractText = [regex]::Replace($contractText, '"goal":\s*"[^"]*"', $evaluator)
}
$contractPath = Join-Path $SessionRoot 'session_contract.json'
Set-Content -LiteralPath $contractPath -Value $contractText -Encoding UTF8

# START packet stub (Ambassador fills this; gate 1).
$startStub = @"
# START PACKET — $SessionId

> NEO_AMBASSADOR writes this. Human approves at the START gate BEFORE any edit.

- **Goal:** $Goal
- **Approved scope (paths):** _(see session_contract.json approved_paths)_
- **Budget:** _(unit / limit / spend-cap configured?)_
- **State surfaces:** filesystem
- **Blocking questions for human:**
  1. _(none / list here)_

**Gate:** Do not proceed until the human answers questions and approves.
"@
Set-Content -LiteralPath (Join-Path $SessionRoot 'start_packet.md') -Value $startStub -Encoding UTF8

Write-Host "Created NEO session at: $SessionRoot"
Get-ChildItem -Recurse -LiteralPath $SessionRoot | Select-Object FullName | Format-Table -AutoSize
Write-Host ""
Write-Host "Next: fill session_contract.json + start_packet.md, then run verify_session.ps1 -SessionPath `"$SessionRoot`""
