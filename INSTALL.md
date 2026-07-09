# NEO 4.9 — INSTALL (read this first, follow in order)

Every step below is **your** action as the installing human — the package never installs itself.
Steps 1–5 are required; steps 6–9 are optional components. Commands are exact; run them in
**Windows PowerShell 5.1** (`powershell.exe`, ships with Windows 10/11 — check with
`$PSVersionTable.PSVersion`).

## Prerequisites

| Required | Notes |
|---|---|
| Windows 10/11 + PowerShell 5.1 | The entire harness is PS 5.1 (`powershell.exe`), not PowerShell 7 |
| Claude Code | The agent harness NEO governs; install per Anthropic's docs (CLI or desktop app) |
| The **published root SHA** | 64-hex string; obtain **out-of-band** from whoever sent you this package — never from a file inside it |

| Optional | Enables |
|---|---|
| codex CLI on PATH + login (`%USERPROFILE%\.codex\auth.json`) | External plan audits + HIGH-slice external audit lane (refuses/parks cleanly without it) |
| Gmail app-password credential | Gate notification mails (refuses cleanly without it; see step 8's honest note) |
| Admin rights (usually not needed) | Only if your account cannot register scheduled tasks (step 7) |

## Step 1 — Unblock the scripts (Mark-of-the-Web)

If this tree arrived as a zip/download, Windows tagged the files and PowerShell will refuse to run
them. From the tree root:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

## Step 2 — Put the tree where it will live

Copy/unzip the package to your chosen location (e.g. `D:\NEO`). **Do not run anything from the
original frozen media/location you received.** Paths with spaces are fine — keep quotes in commands.

## Step 3 — VERIFY authenticity (do not skip; do this BEFORE any other step)

From your install root:

```powershell
.\verify_neo.ps1 -PublishedRootSha <the-64-hex-SHA-from-step-1-of-prerequisites>
```

PASS requires all three: no file changed/missing/extra vs `RELEASE_MANIFEST.json`; the manifest's
internal root SHA recomputes; and it equals YOUR out-of-band published SHA. **Any FAIL = do not
use this tree**; re-obtain the package and the SHA from the sender.
*Verify is strict and one-time: it passes only on a pristine copy. Once you run steps 4–5 (which
write into your copy), verify will no longer pass — that is by design, not damage. To re-verify
later, start from a fresh unzip.*

## Step 4 — Bind the root-of-trust anchor to YOUR path

The shipped anchor records the path the package was frozen at, so `verify_root_of_trust` fails at
your location **by design** until you re-cut it (it refuses unless step 3 just PASSed):

```powershell
.\verify_neo.ps1 -PublishedRootSha <same-64-hex> -ReCutAnchor
powershell -ExecutionPolicy Bypass -File .\.neo\scripts\verify_root_of_trust.ps1   # expect: ALL CHECKS PASS
```

## Step 5 — Run the first-run setup script

```powershell
powershell -ExecutionPolicy Bypass -File .\_install\setup_neo49.ps1
```

It regenerates `.claude\settings.json` for your root (SessionStart orientation hook whose first
line points at README.md; the baseline file is kept as `settings.json.baseline_original`), points
the watchdog config at your `NEO_SESSION`, and patches the one hardcoded dev-tree path in
`subsession_watchdog.ps1`. It refuses to run against the origin machine's governed trees and is
safe to re-run. **It does not perform steps 6–9 — those are yours.**

Sanity check the core nets on your copy (each should end green / exit 0):

```powershell
powershell -ExecutionPolicy Bypass -File .\.neo\scripts\lint_skills.ps1
powershell -ExecutionPolicy Bypass -File .\.neo\scripts\regression_smoke.ps1
```

## Step 6 — (Optional) user-level AUTO-mode skills

```powershell
powershell -ExecutionPolicy Bypass -File .\_install\setup_neo49.ps1 -InstallUserSkills
```

Copies `NEO_AUTO_ON` / `NEO_AUTO_OFF` to `%USERPROFILE%\.claude\skills`. **Honest note:** the
skills alone do not grant AUTO mode — the shipped `.neo\AUTO_MODE_ATTESTATION.md` is the ORIGINAL
operator's signed attestation and does not transfer to you. To use AUTO mode you must issue your
own standing attestation under your own authority (see CAPABILITIES.md); until then, run NEO
interactively (the default).

## Step 7 — (Optional) watchdog scheduled task

The subsession watchdog is a 10-minute heartbeat that detects stalled runs/overruns (it never
kills anything). Register it from your install root:

```powershell
$wd = Join-Path (Get-Location) '.neo\scripts\watchdog\subsession_watchdog.ps1'
$a  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $wd + '"')
$t  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 3650)
Register-ScheduledTask -TaskName 'SubsessionWatchdog' -Action $a -Trigger $t
```

Remove later with `Unregister-ScheduledTask -TaskName 'SubsessionWatchdog'`.

## Step 8 — (Optional) gate notification mail

To route gate mail to YOURSELF:

1. **Set your addresses** (recipient/sender are config-resolved — no hardcoded address): either set
   env vars `NEO_NOTIFY_RECIPIENT` / `NEO_NOTIFY_SENDER`, or create
   `%USERPROFILE%\.neo_notify\config.json` = `{ "recipient": "you@example.com", "sender": "you@example.com" }`.
2. **Add your credential:** create `%USERPROFILE%\.neo_notify\` and place a Gmail **app password**
   (single line) in a file named `smtp_credential` there.
3. **Issue your own DEF-P8 attestation:** the shipped
   `NEO_SESSION\_neo_roadmap\DEF-P8_EMAIL_NOTIFY_ATTESTATION.md` is an **unapproved template** —
   fill it in and stamp `STATUS: **APPROVED / IN FORCE` on your own copy.

Until all three are in place, every live send **refuses cleanly** (fail-closed) and the run
continues — mail is convenience, never a dependency. Test mode always composes to disk with zero
network, so you can exercise the channel before configuring any credential.

## Step 9 — (Optional) codex external audit channel

Install the OpenAI codex CLI so `codex` resolves on PATH, and log in so
`%USERPROFILE%\.codex\auth.json` exists (subscription auth; the file's existence is checked, its
contents are never read by NEO). Without it, external plan audits and the HIGH-slice external lane
refuse/park fail-closed; everything else works.

## Step 10 — Use NEO

Start Claude Code **from your install root**. The SessionStart hook will point the agent at
README.md and run the NEO orientation; the entry router is `.claude\skills\NEO_SYSTEM\SKILL.md`;
doctrine is `.neo\NEO_DOCTRINE.md`. Read CAPABILITIES.md first if you have not — especially the
caveats that `CLAUDE.md` and all historical evidence speak from the ORIGIN machine's layout
(`S:\...` paths, original operator's policies), and that **you** are now the human gate-keeper NEO
requires: it will ask you for START approvals and END keep/iterate/toss decisions, and it is
designed to refuse to proceed without them.

## Troubleshooting

- "running scripts is disabled" → step 1 (or prefix commands with `powershell -ExecutionPolicy Bypass -File`).
- `verify_neo` FAILS on a fresh unzip → wrong published SHA or corrupt/tampered package; stop, re-obtain both.
- `verify_neo` FAILS after you used the tree → expected (see step 3); re-verify only from a fresh unzip.
- `verify_root_of_trust` FAILS after moving the folder → re-run step 4 at the new path.
- Hooks don't fire / point at `<NEO_ROOT>\...` → step 5 was skipped; run the setup script.
- Watchdog logs an error loading its notify module → step 5 was skipped (it patches that path).
