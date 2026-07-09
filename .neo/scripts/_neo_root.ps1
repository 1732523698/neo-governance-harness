# _neo_root.ps1 - shared NEO root resolver (PORT-S1, self-locating root).
# Dot-source from any in-tree script:  . "$PSScriptRoot\_neo_root.ps1"
# Then:  if (-not $NeoRoot) { $NeoRoot = Resolve-NeoRoot $PSScriptRoot }
#
# Rule: walk UP from the start directory to the first ancestor that contains
# BOTH .neo AND .claude; that ancestor is the NEO root. Fails LOUD (throws,
# non-zero exit) if no such ancestor exists - never silently defaults.
function Resolve-NeoRoot {
  [CmdletBinding()]
  param([string]$StartDir = $PSScriptRoot)
  if ([string]::IsNullOrEmpty($StartDir)) {
    throw "Resolve-NeoRoot: StartDir is empty; cannot locate the NEO root."
  }
  $dir = (Resolve-Path -LiteralPath $StartDir).Path
  while ($dir) {
    if ((Test-Path -LiteralPath (Join-Path $dir ".neo")) -and
        (Test-Path -LiteralPath (Join-Path $dir ".claude"))) {
      return $dir
    }
    $parent = [System.IO.Path]::GetDirectoryName($dir)
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { break }
    $dir = $parent
  }
  throw "NEO root not found: no ancestor of '$StartDir' contains BOTH .neo and .claude. NEO must be run from inside a NEO folder."
}
