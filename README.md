# NEO — governance sandbox / harness (public cut)

**NEO** is a governance sandbox / harness whose one thesis is that **scripts and artifacts decide
correctness — never agent confidence**. Two human gates wrap every session (START approval, END
keep/iterate/toss); a C1–C6 self-iteration engine drives DEV app-build runs; cold context-isolated
audits and fail-closed external channels keep the machine honest; and audit nets outrank any
confident narrative.

This repository is a **public cut**: a scrubbed, harness-only subset derived from the frozen **NEO
4.9** milestone. Internal session history and the origin operator's reference application were
intentionally excluded, and personal data was removed/parameterized. See **[PROVENANCE.md](PROVENANCE.md)**
for exactly what was derived, excluded, and scrubbed, and **[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)**
for what that means in practice.

**Read these first — they are the package:**

1. **[INSTALL.md](INSTALL.md)** — how to verify authenticity, install, and configure this package on
   your machine. Nothing works "out of the box"; the install steps are deliberate, human-performed.
2. **[CAPABILITIES.md](CAPABILITIES.md)** — what NEO **is** and, just as important, what it **is
   not**. NEO is not a product; it is a governed sandbox that requires a human gate-keeper by design.

## Quick orientation (30 seconds)

- **Verify before use.** `verify_neo.ps1` at this root re-hashes every file against
  `.neo\release\RELEASE_MANIFEST.json` and checks the result against the **published root SHA** you
  obtain **out-of-band** from whoever distributed this package (never from a file inside it). No
  published SHA = verify fails closed. It ignores the `.git\` working tree. Full steps: INSTALL.md.
- **Then install.** `verify_neo.ps1 -ReCutAnchor` binds the root-of-trust anchor to YOUR path, and
  `_install\setup_neo49.ps1` parameterizes the machine-specific pieces (hooks, watchdog) for YOUR
  copy. Optional components (gate mail, codex external audits, watchdog task, AUTO-mode skills) are
  explicit manual steps in INSTALL.md.
- **What NEO does**, once installed: two human gates around every session, a C1–C6 self-iteration
  engine for DEV app-build runs, cold context-isolated audits, fail-closed external channels, and
  audit nets that outrank any confident narrative. See CAPABILITIES.md, then
  `.claude\skills\NEO_SYSTEM\SKILL.md` (the role router) and `.neo\NEO_DOCTRINE.md`.

## Layout

| Path | What it is |
|---|---|
| `README.md`, `INSTALL.md`, `CAPABILITIES.md` | Package documentation (start with INSTALL.md) |
| `LICENSE` | Apache License 2.0 |
| `PROVENANCE.md` | How this public cut was derived from frozen NEO 4.9 (exclusions + scrub transforms) |
| `KNOWN_LIMITATIONS.md` | Honest limitations of the public cut (e.g. app-governance suites need a bring-your-own app profile) |
| `verify_neo.ps1` | Recipient authenticity gate + install anchor re-cut |
| `_install\` | First-run setup script, SessionStart orientation entry, user-level skill copies |
| `.neo\` | The engine: doctrine, definitions, schemas, scripts, nets, orchestrator, watchdog, release manifest |
| `.claude\skills\` | The NEO roles + router (NEO_SYSTEM / DIRECTOR / BUILDER / AUDITOR) |
| `.agents\skills\` | Subagent skill surface (mirror of the role skills) |
| `CLAUDE.md` | Operating instructions as they stood on the origin machine (see CAPABILITIES.md caveat) |
| `NEO_SESSION\` | Empty at ship time (working sessions are created here at runtime); carries the DEF-P8 attestation template |

*Documentation speaks from the origin machine's reference layout (`S:\NEO` as the canonical root) and
refers to a persona ("Raphael") as the human controller — intentional reference/branding, not live
machine paths. Adapt paths to your own environment on install.*
