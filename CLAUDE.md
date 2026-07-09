# NEO - Operating Instructions (auto-loaded; read before acting)

**What this is.** NEO is a governance sandbox / harness. Its thesis: **scripts and artifacts decide
correctness, never agent confidence.** The self-iteration engine (C1 auto-act, C2 cold-builder firewall,
C3 circuit-breaker, C4 external-model channel, C5 clarity gate, C6 risk-tier router + the loop layer + the
one-call run surface `orch_run.ps1`) is BUILT, triple-audited, and live in PROD.

**FIRST ACTION every session: load the `NEO_SYSTEM` skill.** It is the ROUTER - it points you to exactly
ONE role per phase and nothing else. Do NOT load all NEO skills. Route:
- planning / gates / dispatch / budget / the human surface  -> `NEO_DIRECTOR`
- implementing an approved slice                            -> `NEO_BUILDER`
- verification / audit / graduation                         -> `NEO_AUDITOR`
One active role at a time; finish it, then switch.

**STARTING-PLAN AUDIT (mandatory, Raphael 2026-07-08):** before presenting ANY START gate, fire the
external codex audit on the session's starting plan (packet -> `codex exec -s read-only`, DEF-P7);
iterate NEEDS-MORE to converged GO; present the verdict WITH the gate; evidence lands in the session's
`plan_audit\` folder.

**Default operating model = REACH FOR THE AUTONOMOUS ENGINE (Raphael, 2026-07-08).** For DEV app-build
work, the C1-C6 self-iteration engine (`orch_run.ps1`) is the FIRST choice, not the fallback:
1. `Invoke-NeoRunPrepare`: freeze -> pre-START plan audit -> the ONE human **C5 clarity gate** (Raphael
   sees + approves the slice plan + risk rows).
2. `Invoke-NeoRunExecute`: **END-gate-only autonomy** - strictly-serial slices, C1 auto-act on verdict,
   C3 circuit-breaker, an isolated cold auditor on EVERY slice (+ external Codex on HIGH slices), a cold
   context-firewalled builder per slice; NO per-slice human questions.
3. **Human END gate:** Raphael's explicit keep / iterate / toss on the whole run.

**AUTO MODE (v7 sec 6-A-AUTO; ratified 2026-07-08, live once the build slice + Raphael's signed
attestation land):** a run may be declared AUTO via a per-run autonomy record under the standing
`AUTO_MODE_ATTESTATION` - START authority = the engine-validated attestation envelope (gate_kind
`attested_start_approval`), END = engine auto-keep on a clean converged GO (recorded engine-decided;
MANDATORY async human review; never substitutes a human keep downstream); anything non-clean parks +
notifies. The sandbox floor is toggle-blind and non-bypassable. Binding design:
`NEO_SESSION/_neo_roadmap/NEO_AUTOMODE_DESIGN_v1.md` (rev5 4F549F3A).

Use the **MANUAL two-gate loop as the FALLBACK** for work the engine does not cover: changes to NEO's OWN
governance/harness, PROD push-gates, one-off fixes, or ambiguous scope that needs a human START per step
(draft START packet -> human gate -> cold builder -> triple audit from disk -> human END gate).

**Preferring the engine NEVER relaxes its design-baked guardrails (non-negotiable):** DEV-only (never
PROD / real money / security); EVERY run carries a RECORDED human START authority (per-run C5 in
interactive mode; the engine-validated standing attestation envelope in AUTO mode) AND a human END
decision (synchronous keep/iterate/toss, or under AUTO the mandatory async review of an engine-decided
auto-keep); strictly serial until 3.1-S6 graduates; unknown/ambiguous risk => STOP + surface. The
engine's FIRST real autonomous run is the pre-declared LOW-risk EMS slice in AUTO MODE (Raphael
2026-07-08 recorded override of watched-first; driven by a SEPARATE fresh manager; requires the AUTO
build slice + the signed attestation first) - the engine is BUILT + triple-audited + smoke-tested but
has NOT yet driven a real build; that first run is its live proof.

**Hard lines (never cross):**
- **Never self-approve a gate.** START and END (keep/iterate/toss) are Raphael's explicit answers.
- **PROD (`S:\NEO`) writes, re-pins, schema-adds, and frozen-manifest changes are STOP-AND-WAIT.**
  Assemble the exact old->new ledger, independently re-hash on disk, present for Raphael's RECORDED
  authorization, THEN execute.
- **Sandbox boundary:** DEV-only; no real users, money, production data, or external accounts beyond
  human-attested sandbox ones (DEF-P7 codex / DEF-P8 notify).
- **Honesty:** surface every red/finding, never sanitize; name every deferral with its unblocking
  dependency; classify controls honestly (tamper-EVIDENT vs tamper-PROOF).
- **The audit nets are the authority** (`verify_session.ps1`, `verify_app_slice.ps1`, the orchestrator
  suites) - run them non-cached; a confident narrative never overrides a red net.

**Tree layout.** Work happens in the DEV tree `<NEO_ROOT>`. `S:\NEO` is the stable PUBLISHED
PROD baseline; changing it is a push-gate event (back up BOTH trees first -> additive promote -> re-prove
-> publish the new baseline SHA). Off-tree backups + baselines live in `S:\NEO_backups\` (never inside a
governed tree).

**Where the detail lives (reference, do NOT restate):** shared doctrine `.neo/NEO_DOCTRINE.md`; encoded
checks `.neo/DEFINITIONS.md`; the binding autonomy spec
`NEO_SESSION/_neo_roadmap/NEO_SELF_ITERATION_DESIGN_v3_1.md` (SHA-256 prefix 10652365); the governing plan
`S:\NEO_backups\NEO_UPGRADE_PROGRAM_ROADMAP_MASTER_v7.md` (BFAEBC6F; v6 778777BD + v5 8E65619B
retained); operating
policies + full history in memory (`neo-session-control-operating-doctrine`, `neo-distribution-pivot-2026-07-01`). A fresh manager
seat is a COLD chat the human drives (paste the relevant handoff), NEVER a spawned sub-agent.

**The engine COORDINATES; it never validates its own work** (the C2 firewall + spawn-correlated auditor +
lane-split are the machinery that guarantees it). The first pre-declared LOW-risk run and its handoff live
in `NEO_SESSION/_neo_roadmap/NEO_FIRST_AUTONOMOUS_RUN_MANAGER_HANDOFF.md`.
