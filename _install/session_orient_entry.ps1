# FIRST: read README.md at the NEO tree root - it is the package entry point and wires INSTALL.md + CAPABILITIES.md.
# session_orient_entry.ps1 - NEO 4.9 SessionStart orientation entry (ships with the package).
# Registered as the SessionStart hook by _install\setup_neo49.ps1 on YOUR installed copy. Its first
# output line points the agent at README.md, then it runs the in-tree NEO session orientation.
# ASCII-only, PowerShell 5.1.
$ErrorActionPreference = 'Continue'
Write-Host 'READ README.md AT THE NEO TREE ROOT FIRST - it is the package entry point and wires INSTALL.md (how to install) and CAPABILITIES.md (what NEO 4.9 is and is not).'
$root = Split-Path -Parent $PSScriptRoot
$orient = Join-Path $root '.neo\scripts\hooks\session_orient.ps1'
if (Test-Path -LiteralPath $orient) {
  & $orient
} else {
  Write-Host "WARNING: in-tree orientation script not found at '$orient' - tree may be incomplete; re-verify with verify_neo.ps1."
}
