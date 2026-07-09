# set_session_name.ps1 - NEO manager CLI to reconcile a session's friendly name onto the
# ONE canonical key the notify hook reads: <session_id>.txt in the session_names sidecar
# dir. ASCII-only (D10). This is a MANAGER helper, NOT the hook: it fails CLOSED (writes
# NOTHING and exits NON-ZERO) on any ambiguity, whereas the hook (notify_hook.ps1) is
# fail-OPEN and never blocks a session. The manager treats a refusal as NON-BLOCKING and
# proceeds relying on the hook's <tree>-<uuid8> fallback (fail-toward-mail).
#
# It writes / overwrites %USERPROFILE%\.neo_notify\session_names\<session_id>.txt with
#   line1 = sanitized friendly Name (module charset [A-Za-z0-9_.-], cap 60)
#   line2 = ASCII one-line Desc (cap 80)
# so both the manager's explicit gate mail and the Stop-hook mail resolve the SAME name and
# share one slice root (the notify-doublefire-fix FIX-2 reconcile).
#
# CANONICAL SESSION_ID RESOLUTION (STOP at the first that yields EXACTLY ONE unambiguous id;
# NO newest/nearest-file heuristic anywhere):
#   1. -SessionId if non-empty (the authoritative hook evt.session_id the caller holds).
#   2. else parse the session_id UUID out of -TranscriptPath (the transcript filename / path
#      segment IS the session_id, per the harness invariant).
#   3. else REFUSE. (ITERATE-1, external codex MED: the former "single *.txt in NamesDir"
#      fallback was REMOVED. A lone marker only proves "one file exists," NOT "the marker
#      THIS session created" - in the live global sidecar dir a stale OTHER-session marker
#      would be silently overwritten. Per plan-audit HIGH-1, absent id => refuse, never guess.)
# Absent id (neither -SessionId nor a UUID in -TranscriptPath) => write NOTHING, print the
# reason to stderr, exit NON-ZERO (fail-CLOSED).
#
# The sidecar is the AUTHORITY the hook reads: a manager-authored value written here always
# wins over the hook's write-once auto-capture.

param(
  [Parameter(Mandatory)][string]$Name,
  [string]$Desc = '',
  [string]$SessionId = '',
  [string]$TranscriptPath = '',
  [string]$NamesDir = ''
)

# --- ASCII sanitize + cap (twin of the hook's Get-NeoHookAsciiLine; do NOT dot-source the
# frozen module - inline the small equivalent) ---
function Get-NeoNameAsciiLine {
  param([string]$s, [int]$max)
  if ($null -eq $s) { return '' }
  $s = ($s -replace '[^\x20-\x7E]', '?')
  if ($max -gt 0 -and $s.Length -gt $max) { $s = $s.Substring(0, $max) }
  return $s
}

# --- module SliceId-safe charset ([A-Za-z0-9_.-]; everything else -> '-') + cap (twin of
# the hook's Get-NeoHookCharsetName) ---
function Get-NeoNameCharsetName {
  param([string]$s, [int]$max)
  $s = Get-NeoNameAsciiLine $s 0
  $s = ($s -replace '[^A-Za-z0-9_.-]', '-')
  if ($max -gt 0 -and $s.Length -gt $max) { $s = $s.Substring(0, $max) }
  return $s
}

# --- session_id charset guard: the same sanitization the hook applies when it builds the
# sidecar filename (Get-NeoHookCharsetName -max 80), so the helper and the hook agree on the
# EXACT <session_id>.txt path. Returns the sanitized id, or '' when it has no usable char. ---
function Resolve-NeoSessionIdFile {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  $safe = Get-NeoNameCharsetName -s $s -max 80
  if ($safe -notmatch '[A-Za-z0-9_]') { return '' }
  return $safe
}

# --- parse the session_id UUID out of a transcript path. The harness names the transcript
# file after the session_id (a UUID); the UUID may sit anywhere in the path. Return the
# FIRST UUID found, or '' when none. A canonical UUID:
#   8-4-4-4-12 hex, e.g. e3f6d65f-2516-423a-8b8f-84c99241e31d ---
function Get-NeoSessionIdFromTranscript {
  param([string]$p)
  if ([string]::IsNullOrWhiteSpace($p)) { return '' }
  $m = [regex]::Match($p, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
  if ($m.Success) { return $m.Value }
  return ''
}

try {
  # --- resolve the names dir (default = live sidecar dir; -NamesDir is the test seam) ---
  if ([string]::IsNullOrWhiteSpace($NamesDir)) {
    $NamesDir = Join-Path $env:USERPROFILE '.neo_notify\session_names'
  }

  # --- canonical session_id resolution (STOP at the first that yields exactly one id) ---
  $resolvedId = ''
  $source = ''

  # (1) explicit -SessionId
  if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $resolvedId = $SessionId
    $source = 'SessionId'
  }

  # (2) parse the UUID out of -TranscriptPath
  if ([string]::IsNullOrWhiteSpace($resolvedId) -and (-not [string]::IsNullOrWhiteSpace($TranscriptPath))) {
    $fromT = Get-NeoSessionIdFromTranscript -p $TranscriptPath
    if (-not [string]::IsNullOrWhiteSpace($fromT)) {
      $resolvedId = $fromT
      $source = 'TranscriptPath'
    } else {
      [Console]::Error.WriteLine("set_session_name: refused - -TranscriptPath '$TranscriptPath' contains no session_id UUID (8-4-4-4-12 hex). Pass -SessionId explicitly.")
      exit 3
    }
  }

  # (3) REMOVED (ITERATE-1, external codex MED): there is NO single-marker fallback. A lone
  # *.txt in NamesDir only proves one file exists, not that THIS session created it, so in the
  # live global sidecar dir it could silently overwrite a stale OTHER-session marker. With
  # neither -SessionId nor a UUID-bearing -TranscriptPath, REFUSE (fail-closed; never guess).
  if ([string]::IsNullOrWhiteSpace($resolvedId)) {
    [Console]::Error.WriteLine("set_session_name: refused - no session_id resolved: pass -SessionId (authoritative), or -TranscriptPath containing the session_id UUID (8-4-4-4-12 hex). No marker/newest-file guess exists (fail-closed).")
    exit 4
  }

  # --- sanitize the resolved id to the exact filename the hook reads ---
  $sidFile = Resolve-NeoSessionIdFile -s $resolvedId
  if ([string]::IsNullOrWhiteSpace($sidFile)) {
    [Console]::Error.WriteLine("set_session_name: refused - resolved session_id '$resolvedId' (via $source) has no usable [A-Za-z0-9_] character after sanitization (fail-closed).")
    exit 6
  }

  # --- sanitize the friendly name + desc exactly as the hook does when it reads them ---
  $nameOut = Get-NeoNameCharsetName -s $Name -max 60
  if ($nameOut -notmatch '[A-Za-z0-9_]') {
    [Console]::Error.WriteLine("set_session_name: refused - -Name '$Name' sanitizes to no usable [A-Za-z0-9_] character (the hook would ignore it and fall back). Give a real name (fail-closed).")
    exit 7
  }
  $descOut = Get-NeoNameAsciiLine -s $Desc -max 80

  # --- write / overwrite <session_id>.txt: line1 = name, line2 = desc (ASCII) ---
  if (-not (Test-Path -LiteralPath $NamesDir)) {
    New-Item -ItemType Directory -Force -Path $NamesDir | Out-Null
  }
  $outPath = Join-Path $NamesDir ($sidFile + '.txt')
  $content = $nameOut + "`n" + $descOut
  [System.IO.File]::WriteAllText($outPath, $content, [System.Text.Encoding]::ASCII)

  [Console]::Out.WriteLine($outPath)
  exit 0
} catch {
  [Console]::Error.WriteLine("set_session_name: refused - internal error: $($_.Exception.Message) (fail-closed; nothing written on this path).")
  exit 2
}
