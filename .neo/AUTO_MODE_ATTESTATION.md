# AUTO MODE STANDING ATTESTATION - WORKFLOW-GATE PRE-AUTHORIZATION (D-A1 envelope)

STATUS: **APPROVED / IN FORCE (Raphael recorded approval 2026-07-08 via the slice-1d START gate confirm; D-A1 default envelope)**

Durable record of Raphael's standing human START authority for AUTO-mode runs of the NEO
self-iteration engine (`orch_run.ps1`), per NEO_AUTOMODE_DESIGN_v1.md rev5 (sha8 4F549F3A)
sec 3B and governing plan v7 (sha8 BFAEBC6F) sec 6-A-AUTO. AUTO mode bypasses the WORKFLOW
human waits ONLY (per-run C5 START wait; synchronous END keep/iterate/toss). The SANDBOX
SAFETY FLOOR below is HARD, TOGGLE-BLIND, and NON-BYPASSABLE. This record is validated by
the ENGINE itself (anchored stamp + hash-match + envelope assertion, fail-closed at prepare
AND execute); it is never procedure-only.

HARD RULE - EACH AUTO RUN STILL CARRIES A RECORDED PER-RUN DECLARATION: a run is AUTO only
when the manager writes `<RunRoot>\autonomy_mode.json` (schema neo:run_autonomy_mode) whose
attestation_sha256 matches THIS file's content hash. Record absent => interactive. Record
present but ANY chain link invalid => PARK + NOTIFY at prepare. Unknown is NEVER coerced
to auto.

```
attested_by:        Raphael (controller)
date:               2026-07-08 (signature event = Raphael's confirm of this exact text at
                    the slice-1d START gate; pre-approved with the D-A1 default envelope in
                    the AUTOMODE-HARDWIRE session, 2026-07-08, recorded in that session's
                    handoff APPROVALS block)
authority_basis:    NEO_AUTOMODE_DESIGN_v1.md rev5 4F549F3A sec 3B (dual-lane converged GO);
                    NEO_UPGRADE_PROGRAM_ROADMAP_MASTER_v7.md BFAEBC6F sec 6-A-AUTO (ratified)
envelope:           D-A1 DEFAULT - LOW-RISK ONLY, until the first AUTO run graduates and
                    Raphael widens by RE-SIGNING (a widened envelope = a new signature event
                    + a new content hash; stale 3A records fail their hash-match and park):
  roots:            DEV-only. The run root and every approved path must live under
                    '<NEO_ROOT>'. Never 'S:\NEO' (PROD), never any other root.
  max_risk_tier:    LOW. Every risk row of the run's clarity-freeze slice plan must be LOW;
                    any higher or unknown/ambiguous tier is an envelope breach => PARK +
                    NOTIFY at prepare.
  plan_audit:       the run's pre-START external plan audit (DEF-P7 codex) must be a clean
                    converged GO; any NEEDS-MORE / NO-GO / missing verdict => PARK + NOTIFY.
  serial:           strictly-serial slices only (no parallel path until 3.1-S6 graduates).
  start_authority:  gate_kind 'attested_start_approval' (case-exact), citing this file:
                    authorized_by 'Raphael (standing AUTO attestation <sha8-of-this-file>)'.
                    Cross-pairing with 'human_start_approval' REFUSES (NF-A10).
  end_authority:    engine auto-keep IFF spec sec-4 (a)-(d) all hold (valid chain + END-site
                    re-hash match; clean END assembly; converged=true/stopped=false; human
                    class SESSION_END). Anything else PARKS + NOTIFIES. MANDATORY async
                    human review; engine_auto_keep NEVER substitutes a human keep downstream
                    (D-A2 default: dependent continuation, graduation, PROD promote all
                    refuse it).
revocation:         Raphael revokes AT ANY TIME by stamping a line-anchored REVOKED status
                    on this file; the engine then fail-closes (park lane) at the next
                    validation boundary. Post-record revocation also breaks every recorded
                    3A hash-match.
inferred:           NO (explicit standing attestation, DEF-P7/P8 anchored-stamp pattern,
                    engine-validated fail-closed)
```

## THE FLOOR (sec 5 rows, verbatim; each enforced by toggle-blind machinery)

| Never under AUTO | Enforced by (toggle-blind) | Fixture |
|---|---|---|
| PROD (S:\NEO) write | sandbox-boundary invariant + approved_paths containment (orch_enforce; Assert-NeoContained) | NF-A1a |
| Money / real external accounts | DEF-P7/P8 attestation gates; no other channel exists in the engine | NF-A1b |
| Destructive op outside approved_paths | C1b three-branch + E2 human-gate binding + enforcement BLOCK | NF-A1c |
| Non-serial execution | strictly-serial slice loop (no parallel path until 3.1-S6 graduates) | NF-A1d |
| Risk-router / classifier bypass | C6 router unchanged; UNKNOWN/ambiguous => STOP + PARK | NF-A1e |
| Cold-auditor skip on any slice | C2 spawn-correlated isolated auditor; lane split keeps the external verdict out of the auditor slot | NF-A1f |
| External-audit skip on HIGH | C4 fail-closed: external unavailable on HIGH => breaker => PARK | NF-A1g |
| Secret/credential CONTENT read | DEF-P7/P8 existence-only discipline; no engine path reads credential contents (grep-proven) | NF-A1h |
| Network/API side effects beyond the two attested channels (codex CLI, SMTP) | orch_external is the only process launcher; notify module is the only mailer; both attested + toggle-blind | NF-A1i |
| Dependency / tool install | DEP-GUARD (RT3/RT4 gating, NEO_RELEASE_DISCIPLINE); not an engine capability | NF-A1j |
| Arbitrary process / service launch | the engine launches ONLY the pinned codex exec + its own powershell suites; no generic launcher exists | NF-A1k |
| Governance re-version / re-pin / frozen-manifest tamper | govmanifest floor-27 checks + XC2 + stop-and-wait class (sec 2 last row) | NF-A1l |
| Self-modifying code (engine editing .neo governance / judging paths) | approved_paths EXCLUDE judging/governance paths (spec sec-9.4); containment BLOCK | NF-A1m |
| C3 breaker bypass | breaker unchanged; every trip class => PARK + notify | NF-A2 |

## Binding conditions
- Both artifacts required for a hands-off run: this attestation IN FORCE + a valid per-run
  autonomy_mode.json whose attestation_sha256 matches this file. Each alone is insufficient.
- Validation is ENGINE-OWNED (Get-NeoRunAutonomyMode, fail-closed, prepare AND execute);
  manager procedure never substitutes.
- Stop-and-wait event classes (PROD push, re-version, re-pin, schema-add) remain HUMAN and
  are outside AUTO's scope entirely.
- Breaker trips, floor stops, enforcement BLOCKs, classifier ambiguity, END-assembly
  failure: park + notify + human - RETAINED under AUTO, unchanged.
