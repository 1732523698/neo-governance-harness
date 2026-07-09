# session_orient.ps1 - NEO SessionStart hook payload (Item 2, AUTOMODE-HARDWIRE session).
# ASCII-only (D10). Emits the NEO orientation block to stdout; the harness injects hook
# stdout into the fresh session's context, making self-orientation STRUCTURAL instead of
# manager discipline. Enforcement class: tamper-EVIDENT (an injected instruction + the
# on-disk audit trail), not tamper-PROOF - no hook can force a model to obey it.
# CONTRACT: read-only, no network, no writes anywhere, ALWAYS exits 0 (a broken hook must
# never block a session - same authority rule as DEF-P8 notify: convenience, never gate).

try {
  # AUTO-mode standing attestation status (fail-closed FOR DISPLAY: never claim IN FORCE
  # on any failure path). TEST-ONLY seam: if NEO_ORIENT_ATTESTATION_PATH is set, use it
  # instead of the real attestation file - governed callers never set this env var (same
  # convention as the frozen notify module's test seam).
  $autoStatus = 'UNKNOWN (attestation unreadable - verify from disk)'
  try {
    $attestationPath = $env:NEO_ORIENT_ATTESTATION_PATH
    if ([string]::IsNullOrEmpty($attestationPath)) {
      $neoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
      $attestationPath = Join-Path $neoRoot '.neo\AUTO_MODE_ATTESTATION.md'
    }
    if (Test-Path -LiteralPath $attestationPath -PathType Leaf) {
      $attLines = @(Get-Content -LiteralPath $attestationPath -ErrorAction Stop)
      $inForce = $false
      $revoked = $false
      foreach ($ln in $attLines) {
        if ($ln -match '^STATUS: \*\*APPROVED / IN FORCE') { $inForce = $true }
        if (($ln -match '^\s*REVOKED\b') -or ($ln -match '^\s*STATUS:.*REVOKED')) { $revoked = $true }
      }
      if ($revoked) {
        $autoStatus = 'REVOKED (AUTO runs fail-closed to park)'
      } elseif ($inForce) {
        $autoStatus = 'IN FORCE'
      } else {
        $autoStatus = 'NOT IN FORCE (no APPROVED / IN FORCE stamp)'
      }
    } else {
      $autoStatus = 'UNKNOWN (attestation unreadable - verify from disk)'
    }
  } catch {
    $autoStatus = 'UNKNOWN (attestation unreadable - verify from disk)'
  }

  $lines = @(
    '=== NEO SESSION ORIENTATION (structural SessionStart hook; do not skip) ===',
    'FIRST ACTION: load the NEO_SYSTEM skill (the router). ONE role per phase:',
    '  planning/gates/dispatch -> NEO_DIRECTOR; implementation -> NEO_BUILDER;',
    '  verification/audit/graduation -> NEO_AUDITOR. Never load all NEO skills.',
    'DEFAULT POSTURE: reach for the C1-C6 autonomous engine (orch_run.ps1) for DEV',
    '  app-build work; the manual two-gate loop is the fallback for NEO-own/governance,',
    '  PROD push-gates, and ambiguous scope.',
    'STARTING-PLAN AUDIT (Raphael policy 2026-07-08, MANDATORY): before presenting ANY',
    '  START gate, fire the external codex plan audit on the session starting plan',
    '  (packet.txt -> codex exec -s read-only, DEF-P7) and surface the verdict WITH the',
    '  gate. Iterate NEEDS-MORE findings to converged GO. Evidence lands in the session',
    '  NEO_SESSION\<session>\plan_audit\ folder.',
    'NOTIFY (DEF-P8): fire Send-NeoGateNotification -LiveSend at EVERY human-decision',
    '  gate and friction stop (APPROVAL_NEEDED / DECISION_NEEDED / SESSION_END /',
    '  ESCALATION_STOP / BREAKER_TRIP). The harness hooks mail automatically where',
    '  installed; the manager still fires gate mails explicitly (belt and braces).',
    'NAMING: the session name for gate mails is auto-captured from the first prompt; the manager MAY overwrite %USERPROFILE%\.neo_notify\session_names\<session_id>.txt with a cleaner name and on engine runs SHOULD append '' run:<run_id>''.',
    'HARD LINES: never self-approve a gate (START/END are Raphaels explicit answers);',
    '  PROD (S:\NEO) writes/re-pins/schema-adds = STOP-AND-WAIT with a recorded ledger;',
    '  DEV-only sandbox (no real users/money/accounts beyond attested sandbox ones);',
    '  surface every red - never sanitize; the audit nets are the authority, run',
    '  non-cached; a confident narrative never overrides a red net.',
    "AUTO MODE: standing attestation status: $autoStatus (.neo\AUTO_MODE_ATTESTATION.md).",
    '  Declare AUTO BEFORE Invoke-NeoRunPrepare (autonomy_mode.json in the run root);',
    '  the attestation sha256 in it must be LOWERCASE. Skills: NEO_AUTO_ON /',
    '  NEO_AUTO_OFF (user-level, %USERPROFILE%\.claude\skills). Procedure doc:',
    '  NEO_SESSION\_neo_roadmap\NEO_AUTO_MODE_MANAGER_PROCEDURE.md.',
    'DETAIL: CLAUDE.md (auto-loaded), .neo/NEO_DOCTRINE.md, .neo/DEFINITIONS.md.',
    '=== END NEO ORIENTATION ==='
  )
  $lines | ForEach-Object { Write-Output $_ }
} catch {
  # Belt-and-braces: even a payload failure must not block the session.
}
exit 0
