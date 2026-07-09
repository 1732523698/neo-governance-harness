# session_orient_fixture_suite.ps1 - RED/GREEN fixture suite for session_orient.ps1
# (auto-hardening-watchdog-2026-07-08, slice 1). ASCII-only, PS 5.1.
# CONTRACT: each case launches the hook in its OWN child powershell.exe process
# (-NoProfile -ExecutionPolicy Bypass -File <hook>), non-cached, real process. The
# TEST-ONLY seam env var NEO_ORIENT_ATTESTATION_PATH points the hook at a per-case
# fixture file under $env:TEMP\neo_orient_fixtures_<random>\ ; the fixture dir is
# created fresh and deleted at the end (residue-clean). Prints one PASS/FAIL line
# per case; exits 0 only if ALL cases pass, 1 otherwise.

$ErrorActionPreference = 'Stop'

$hookPath = Join-Path $PSScriptRoot 'session_orient.ps1'

$rand = [System.Guid]::NewGuid().ToString('N').Substring(0,8)
$fixtureDir = Join-Path $env:TEMP "neo_orient_fixtures_$rand"
New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

$results = New-Object System.Collections.ArrayList
$anyFail = $false

function Add-Result([string]$Name, [bool]$Pass, [string]$Detail) {
  $line = if ($Pass) { "PASS: $Name" } else { "FAIL: $Name - $Detail" }
  [void]$results.Add($line)
  if (-not $Pass) { $script:anyFail = $true }
}

function Invoke-Hook([string]$AttestationPath) {
  $oldVal = $env:NEO_ORIENT_ATTESTATION_PATH
  try {
    if ($null -ne $AttestationPath) {
      $env:NEO_ORIENT_ATTESTATION_PATH = $AttestationPath
    } else {
      Remove-Item Env:\NEO_ORIENT_ATTESTATION_PATH -ErrorAction SilentlyContinue
    }
    $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $stdout = & $psExe -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>&1
    $exitCode = $LASTEXITCODE
    return @{ stdout = ($stdout -join "`n"); exit = $exitCode; lines = $stdout }
  } finally {
    if ($null -ne $oldVal) {
      $env:NEO_ORIENT_ATTESTATION_PATH = $oldVal
    } else {
      Remove-Item Env:\NEO_ORIENT_ATTESTATION_PATH -ErrorAction SilentlyContinue
    }
  }
}

# ---- Case 1: block-present ----
try {
  $f1 = Join-Path $fixtureDir 'case1_inforce.md'
  @('STATUS: **APPROVED / IN FORCE (fixture)') | Set-Content -LiteralPath $f1 -Encoding Ascii
  $r1 = Invoke-Hook $f1
  $hasBlock = $r1.stdout -match 'AUTO MODE:'
  $hasBefore = $r1.stdout -match 'BEFORE Invoke-NeoRunPrepare'
  $hasLower = $r1.stdout -match 'LOWERCASE'
  $hasOn = $r1.stdout -match 'NEO_AUTO_ON'
  $hasOff = $r1.stdout -match 'NEO_AUTO_OFF'
  $pass1 = $hasBlock -and $hasBefore -and $hasLower -and $hasOn -and $hasOff
  Add-Result '1-block-present' $pass1 "hasBlock=$hasBlock hasBefore=$hasBefore hasLower=$hasLower hasOn=$hasOn hasOff=$hasOff"
} catch {
  Add-Result '1-block-present' $false "exception: $($_.Exception.Message)"
}

# ---- Case 2: in-force ----
try {
  $f2 = Join-Path $fixtureDir 'case2_inforce.md'
  @('STATUS: **APPROVED / IN FORCE (fixture)') | Set-Content -LiteralPath $f2 -Encoding Ascii
  $r2 = Invoke-Hook $f2
  $statusLine = ($r2.lines | Where-Object { $_ -match 'AUTO MODE:' })
  $pass2 = ($statusLine -match 'IN FORCE') -and ($statusLine -notmatch 'REVOKED') -and ($statusLine -notmatch 'UNKNOWN')
  Add-Result '2-in-force' $pass2 "statusLine='$statusLine'"
} catch {
  Add-Result '2-in-force' $false "exception: $($_.Exception.Message)"
}

# ---- Case 3: revoked (in-force + later revoke; revoke wins) ----
try {
  $f3 = Join-Path $fixtureDir 'case3_revoked.md'
  @('STATUS: **APPROVED / IN FORCE (fixture)', 'REVOKED 2026-07-08') | Set-Content -LiteralPath $f3 -Encoding Ascii
  $r3 = Invoke-Hook $f3
  $statusLine = ($r3.lines | Where-Object { $_ -match 'AUTO MODE:' })
  $pass3 = ($r3.stdout -match 'REVOKED') -and (-not ($statusLine -match 'IN FORCE\b' -and $statusLine -notmatch 'REVOKED'))
  # More precise: the status line itself must show REVOKED, and must not claim plain IN FORCE.
  $pass3 = ($statusLine -match 'REVOKED') -and ($statusLine -notmatch '^\s*AUTO MODE:.*status:\s*IN FORCE\b')
  Add-Result '3-revoked' $pass3 "statusLine='$statusLine'"
} catch {
  Add-Result '3-revoked' $false "exception: $($_.Exception.Message)"
}

# ---- Case 4: missing (seam points at nonexistent path) ----
try {
  $f4 = Join-Path $fixtureDir 'does_not_exist_case4.md'
  $r4 = Invoke-Hook $f4
  $statusLine = ($r4.lines | Where-Object { $_ -match 'AUTO MODE:' })
  $pass4 = ($statusLine -match 'UNKNOWN') -and ($r4.exit -eq 0)
  Add-Result '4-missing' $pass4 "statusLine='$statusLine' exit=$($r4.exit)"
} catch {
  Add-Result '4-missing' $false "exception: $($_.Exception.Message)"
}

# ---- Case 5: unreadable (seam points at a DIRECTORY) ----
try {
  $f5 = Join-Path $fixtureDir 'case5_dir'
  New-Item -ItemType Directory -Path $f5 -Force | Out-Null
  $r5 = Invoke-Hook $f5
  $statusLine = ($r5.lines | Where-Object { $_ -match 'AUTO MODE:' })
  $pass5 = ($statusLine -match 'UNKNOWN') -and ($r5.exit -eq 0)
  Add-Result '5-unreadable' $pass5 "statusLine='$statusLine' exit=$($r5.exit)"
} catch {
  Add-Result '5-unreadable' $false "exception: $($_.Exception.Message)"
}

# ---- Case 6: unsigned template (STATUS: DRAFT only) ----
try {
  $f6 = Join-Path $fixtureDir 'case6_draft.md'
  @('STATUS: DRAFT') | Set-Content -LiteralPath $f6 -Encoding Ascii
  $r6 = Invoke-Hook $f6
  $statusLine = ($r6.lines | Where-Object { $_ -match 'AUTO MODE:' })
  $pass6 = ($statusLine -match 'NOT IN FORCE') -and ($statusLine -notmatch 'IN FORCE\)') -and ($statusLine -notmatch '\bIN FORCE\b(?!.*NOT IN FORCE)')
  # Simpler, precise check: must contain 'NOT IN FORCE' and must NOT match a bare 'IN FORCE' status word
  # (i.e. must not equal the plain in-force status). We check it does not contain 'REVOKED' or exact 'IN FORCE' without NOT.
  $pass6 = ($statusLine -match 'NOT IN FORCE') -and ($statusLine -notmatch 'REVOKED')
  Add-Result '6-unsigned-template' $pass6 "statusLine='$statusLine'"
} catch {
  Add-Result '6-unsigned-template' $false "exception: $($_.Exception.Message)"
}

# ---- Case 7: exit-0 everywhere ----
try {
  $exits = @($r1.exit, $r2.exit, $r3.exit, $r4.exit, $r5.exit, $r6.exit)
  $pass7 = -not ($exits | Where-Object { $_ -ne 0 })
  Add-Result '7-exit-0-everywhere' $pass7 "exits=$($exits -join ',')"
} catch {
  Add-Result '7-exit-0-everywhere' $false "exception: $($_.Exception.Message)"
}

# ---- Case 8: ascii (edited hook file contains no byte > 0x7F) ----
try {
  $bytes = [System.IO.File]::ReadAllBytes($hookPath)
  $nonAscii = $bytes | Where-Object { $_ -gt 0x7F }
  $pass8 = (@($nonAscii)).Count -eq 0
  Add-Result '8-ascii' $pass8 "nonAsciiByteCount=$((@($nonAscii)).Count)"
} catch {
  Add-Result '8-ascii' $false "exception: $($_.Exception.Message)"
}

# ---- Case 9: size discipline (total hook stdout line count <= 45) ----
try {
  $r9 = Invoke-Hook $f1
  $lineCount = (@($r9.lines)).Count
  $pass9 = $lineCount -le 45
  Add-Result '9-size-discipline' $pass9 "lineCount=$lineCount"
} catch {
  Add-Result '9-size-discipline' $false "exception: $($_.Exception.Message)"
}

# ---- residue cleanup ----
try {
  Remove-Item -LiteralPath $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  # best-effort cleanup; do not fail the suite solely on cleanup issues
}

foreach ($line in $results) { Write-Output $line }

if ($anyFail) {
  Write-Output 'SUITE RESULT: FAIL'
  exit 1
} else {
  Write-Output 'SUITE RESULT: PASS'
  exit 0
}
