# NEO 4.9 — CAPABILITIES (honest statement of what this is and is not)

This document is deliberately blunt. It was written at freeze time by the packaging session, from
the portability audit and the attached health report — not from marketing intent. When in doubt,
trust the narrower claim.

## What NEO 4.9 IS

- **A governance sandbox / harness for agent-driven software work.** Its single organizing thesis:
  **scripts and artifacts decide correctness — never agent confidence.** Every phase is checked by
  runnable nets (`verify_session.ps1`, `verify_app_slice.ps1`, `lint_skills.ps1`, fixture suites,
  orchestrator harnesses — the full suite was green at the 4.9 freeze this cut derives from);
  a red net outranks any confident narrative, always.
- **A two-human-gate operating model.** Every session runs between a recorded human START approval
  and a human END decision (keep / iterate / toss). The harness is built so the agent cannot
  self-approve a gate; silence is never consent.
- **A three-role skill system** (`NEO_SYSTEM` router → `NEO_DIRECTOR` planning/gates/dispatch,
  `NEO_BUILDER` scoped implementation, `NEO_AUDITOR` verification/fresh-context audit), one active
  role at a time, with doctrine (`.neo\NEO_DOCTRINE.md`) and encoded check definitions
  (`.neo\DEFINITIONS.md`).
- **A C1–C6 self-iteration engine** (`.neo\scripts\orchestrator\orch_run.ps1`) for DEV app-build
  runs: C1 auto-act on verdicts, C2 cold context-firewalled builder per slice, C3 circuit-breaker,
  C4 external-model audit channel, C5 human clarity gate, C6 risk-tier router — strictly serial
  slices, an isolated cold auditor on every slice, engine coordinates but never validates its own
  work. Plus an optional AUTO mode (workflow-gates pre-authorized under a standing human
  attestation — see the non-transfer caveat below).
- **Fail-closed at every external edge.** Mail, codex, root-of-trust, AUTO mode: each checks its
  credential/attestation and **refuses cleanly** when absent. Missing optional components degrade
  loudly, never silently.
- **An honest evidence discipline.** The full private tree carries the real session records, audit
  outputs, snapshots, and quarantined legacy artifacts of its own construction — including failures
  and open findings. This PUBLIC cut **excludes that internal history** (see `PROVENANCE.md`); it
  ships the harness itself plus the minimal load-bearing fixtures the nets require.

## What NEO IS NOT

- **Not a product.** No installer beyond the documented manual steps, no support, no updates. It is
  a working research/governance harness that one operator built and ran on one machine, packaged
  honestly. This cut is derived from the frozen NEO 4.9 milestone (see `PROVENANCE.md`).
- **Not production-safe, and not for real stakes.** DEV-sandbox-only by doctrine and by code:
  no real users, no real money, no production data, no secrets, no external accounts beyond
  explicitly human-attested sandbox ones. The engine's own PROD guard pins the ORIGIN machine's
  path (`S:\NEO`) — **your** trees get no equivalent automatic protection; do not point NEO at
  anything you cannot afford to lose.
- **Not tamper-PROOF — tamper-EVIDENT only.** Manifests, anchors, and pins detect modification;
  they cannot prevent it. Anyone with write access to the tree can alter it AND its manifests;
  authenticity ultimately rides on the out-of-band published root SHA and on custody discipline.
  The root-of-trust anchor is in-tree and writable by the session principal (`custody:
  provisional-dev`) — a deliberate, documented limitation.
- **Not autonomous, and not meant to be.** NEO **requires a human gate-keeper by design**. Even
  AUTO mode replaces only the workflow gates, under a standing signed human attestation, with
  mandatory human review after. **The shipped attestations (AUTO mode, DEF-P7 codex, DEF-P8 mail)
  are the original operator's and do NOT transfer** — a new operator must issue their own or run
  interactively.
- **Not self-contained in its claims.** `CLAUDE.md` and the doctrine speak from the ORIGIN machine's
  reference layout (`S:\NEO` as the canonical root) and name a persona ("Raphael") as the human
  controller. These are intentional reference/branding, not instructions that work verbatim on your
  machine. Personal machine data (the operator's dev-tree path, username, email, home paths) has
  been removed or parameterized (see `PROVENANCE.md`); INSTALL.md + the setup script cover the
  pieces that must change for your environment.
- **Not a general agent framework.** It governs work inside its own tree with its own role/gate/
  net machinery. Real projects keep their own processes; NEO's conventions never override a real
  project's gates (doctrine SYS-4/D6).

## Known state of this cut (pointers, not paraphrase)

- Derivation, exclusions, and scrub transforms: `PROVENANCE.md` — including the frozen NEO 4.9 source
  root SHA this cut derives from and the fresh public `RELEASE_MANIFEST.json`.
- Honest limitations: `KNOWN_LIMITATIONS.md` — e.g. the app-governance self-test suites need a
  bring-your-own app profile (the reference app is not bundled); gate mail is unconfigured by
  default and fails closed.
- Integrity: `verify_neo.ps1` against `.neo\release\RELEASE_MANIFEST.json` and the out-of-band
  published root SHA. The health report and freeze artifacts of the frozen 4.9 original are retained
  with that original, not shipped in this derived public subset.
