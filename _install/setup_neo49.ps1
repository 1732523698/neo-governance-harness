# setup_neo49.ps1 - NEO 4.9 first-run setup. Run by the INSTALLING HUMAN on THEIR installed copy,
# AFTER verify_neo.ps1 has PASSED and -ReCutAnchor has been run (see INSTALL.md steps 1-4).
# What it does (all writes stay inside YOUR installed tree unless -InstallUserSkills):
#   [1] regenerates .claude\settings.json for YOUR install root (SessionStart -> the shipped
#       orientation entry; the baseline file is preserved as settings.json.baseline_original)
#   [2] points watchdog_config.json run_roots at YOUR <root>\NEO_SESSION
#   [3] patches the one hardcoded DEV-tree notify literal in subsession_watchdog.ps1 to YOUR root
#   [4] (optional -InstallUserSkills) copies NEO_AUTO_ON / NEO_AUTO_OFF to %USERPROFILE%\.claude\skills
#   [5] prints the remaining MANUAL steps (scheduled task, mail credential, codex) - it never does
#       them for you; they are the installing human's explicit actions.
# REFUSES to run against the origin machine's governed/frozen trees. Idempotent: safe to re-run.
# ASCII-only, PowerShell 5.1.

[CmdletBinding()]
param(
  [switch]$InstallUserSkills,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot   # <root>\_install\setup_neo49.ps1 -> <root>
function Norm([string]$p){ ($p.Trim().TrimEnd('\','/')).ToLowerInvariant() }
$nRoot = Norm $root
# Refuse to run in place against the reference/frozen distribution root. Copy the package to
# YOUR own install location first (INSTALL.md step 2). 'S:\NEO' is the origin's documented
# reference root; add your own frozen-copy path(s) here if you keep any.
foreach ($f in @('S:\NEO')) {
  if ($nRoot -eq (Norm $f)) {
    throw "REFUSED: setup must never run against the reference/frozen tree '$f'. Copy the package to YOUR install location first (INSTALL.md step 2)."
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $root '.neo')) -or
    -not (Test-Path -LiteralPath (Join-Path $root '.claude'))) {
  throw "REFUSED: '$root' is not a NEO tree (.neo + .claude both required)."
}

Write-Host '=== NEO 4.9 first-run setup ==='
Write-Host ('Install root: ' + $root)
Write-Host ''

# ---------------------------------------------------------------- [1] .claude\settings.json
$settingsPath = Join-Path $root '.claude\settings.json'
$orientEntry  = Join-Path $root '_install\session_orient_entry.ps1'
$notifyModule = Join-Path $root '.neo\scripts\notify\notify_raphael.ps1'
if ((Test-Path -LiteralPath $settingsPath) -and -not (Test-Path -LiteralPath ($settingsPath + '.baseline_original'))) {
  Copy-Item -LiteralPath $settingsPath -Destination ($settingsPath + '.baseline_original') -Force
}
# NOTE: settings.json is emitted from an explicit template, NOT ConvertTo-Json - PS 5.1's
# ConvertTo-Json collapses single-element arrays, which would corrupt the hooks schema.
function EscJson([string]$s){ $s.Replace('\','\\').Replace('"','\"') }
$allowEsc   = EscJson ("PowerShell(. '" + $notifyModule + "'*)")
$commandEsc = EscJson ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $orientEntry + '"')
$settingsJson = @"
{
  "permissions": {
    "allow": [
      "$allowEsc"
    ],
    "deny": []
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$commandEsc"
          }
        ]
      }
    ]
  }
}
"@
$settingsJson | Set-Content -LiteralPath $settingsPath -Encoding ascii
Write-Host '[1] .claude\settings.json regenerated for this root (baseline kept as settings.json.baseline_original).'
Write-Host '    NOTE: notify_hook.ps1 SHIPS (with the double-fire + classifier fixes) but is NOT auto-wired;'
Write-Host '    no Notification hook is registered by default. Gate mails are sent explicitly by the manager'
Write-Host '    (DEF-P8). To opt in, add a Notification hook pointing at .neo\scripts\notify\notify_hook.ps1.'

# ---------------------------------------------------------------- [2] watchdog run_roots
$wcPath = Join-Path $root '.neo\scripts\watchdog\watchdog_config.json'
$wc = Get-Content -LiteralPath $wcPath -Raw | ConvertFrom-Json
$wc.run_roots = @( (Join-Path $root 'NEO_SESSION') )
($wc | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $wcPath -Encoding ascii
Write-Host ('[2] watchdog_config.json run_roots -> ' + (Join-Path $root 'NEO_SESSION'))

# ---------------------------------------------------------------- [3] watchdog notify path
$wdPath = Join-Path $root '.neo\scripts\watchdog\subsession_watchdog.ps1'
$raw = [System.IO.File]::ReadAllText($wdPath)
# The shipped watchdog SELF-LOCATES its notify module from $PSScriptRoot (no hardcoded install
# path), so no patch is required. Verify the self-locating form is present; refuse if not.
if ($raw -match 'Join-Path \(Split-Path \(Split-Path \(Split-Path \$PSScriptRoot') {
  Write-Host '[3] subsession_watchdog.ps1: self-locating notify path (portable) - no patch needed.'
} else {
  throw "REFUSED [3]: subsession_watchdog.ps1 is missing the expected self-locating notify path and differs from the packaged bytes - stop, re-verify the tree (verify_neo.ps1 on a fresh unzip), and inspect before proceeding."
}

# ---------------------------------------------------------------- [4] optional user-level skills
if ($InstallUserSkills) {
  $dstBase = Join-Path $env:USERPROFILE '.claude\skills'
  foreach ($sk in @('NEO_AUTO_ON','NEO_AUTO_OFF')) {
    $src = Join-Path $root ('_install\user_skills\' + $sk + '\SKILL.md')
    $dstDir = Join-Path $dstBase $sk
    $dst = Join-Path $dstDir 'SKILL.md'
    if ((Test-Path -LiteralPath $dst) -and -not $Force) {
      Write-Host ('[4] SKIP ' + $sk + ': already present at ' + $dst + ' (use -Force to overwrite).')
      continue
    }
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host ('[4] installed user-level skill ' + $sk + ' -> ' + $dst)
  }
} else {
  Write-Host '[4] user-level skills NOT installed. Re-run with -InstallUserSkills to copy NEO_AUTO_ON /'
  Write-Host '    NEO_AUTO_OFF into your profile. NOTE: AUTO mode itself still requires YOUR OWN standing'
  Write-Host '    attestation - the shipped .neo\AUTO_MODE_ATTESTATION.md is the ORIGINAL operator''s record.'
}

# ---------------------------------------------------------------- [5] manual steps (yours, not the script's)
Write-Host ''
Write-Host '=== REMAINING MANUAL STEPS (the installing human''s explicit actions - see INSTALL.md) ==='
Write-Host '(A) OPTIONAL watchdog scheduled task (10-minute repetition):'
Write-Host ('    $a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument (''-NoProfile -ExecutionPolicy Bypass -File "'' + ''' + (Join-Path $root '.neo\scripts\watchdog\subsession_watchdog.ps1') + ''' + ''"'')')
Write-Host '    $t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 3650)'
Write-Host '    Register-ScheduledTask -TaskName "SubsessionWatchdog" -Action $a -Trigger $t'
Write-Host '(B) OPTIONAL gate mail (Gmail SMTP): to notify YOURSELF -'
Write-Host '    1) set your addresses: env NEO_NOTIFY_RECIPIENT / NEO_NOTIFY_SENDER, or create'
Write-Host '       %USERPROFILE%\.neo_notify\config.json = { "recipient": "you@example.com", "sender": "you@example.com" };'
Write-Host '    2) put your Gmail app-password (single line) in %USERPROFILE%\.neo_notify\smtp_credential;'
Write-Host '    3) issue your own DEF-P8 attestation (stamp STATUS: **APPROVED / IN FORCE in'
Write-Host '       NEO_SESSION\_neo_roadmap\DEF-P8_EMAIL_NOTIFY_ATTESTATION.md).'
Write-Host '    Until all three are done, live sends REFUSE cleanly (fail-closed); test mode always composes to disk.'
Write-Host '(C) OPTIONAL external audit channel: install the codex CLI on PATH and log in so'
Write-Host '    %USERPROFILE%\.codex\auth.json exists. Without it, external plan audits and HIGH-slice'
Write-Host '    external lanes REFUSE/park (fail-closed) - interactive NEO work still runs.'
Write-Host '(D) Claude Code: install it, then start sessions FROM this folder. CLAUDE.md speaks from the'
Write-Host '    original machine''s layout (S:\ paths, original operator policies) - read CAPABILITIES.md'
Write-Host '    before acting on it, and adapt paths on YOUR working copy if you operate NEO seriously.'
Write-Host ''
Write-Host '=== setup complete ==='
