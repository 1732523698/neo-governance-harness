---
name: NEO_AUTO_OFF
description: >-
  Turn NEO AUTO mode off - per-run (undeclare before prepare / fresh prepare) or globally
  (Raphael stamps REVOKED on the standing attestation; every AUTO run fail-closes to park).
  Utility skill, not a role: the engine enforces everything fail-closed; this skill only names
  the correct lever. Trigger: "AUTO mode off", "make this run interactive", "revoke auto",
  "kill autonomous runs". No use outside S:\NEO trees.
---

# NEO_AUTO_OFF - turn AUTO off (per-run or global)

**Reference (binding detail):** `NEO_SESSION\_neo_roadmap\NEO_AUTO_MODE_MANAGER_PROCEDURE.md`;
spec rev5 4F549F3A secs 3A/3B. Absence of a declaration IS the interactive default - there is
nothing to "switch off" for a run never declared AUTO.

## Lever 1 - keep/return a run to INTERACTIVE (per-run)
- NOT yet declared: do nothing. No `<RunRoot>\autonomy_mode.json` = interactive (per-run human
  C5 gate). NEVER write `autonomy_mode:'interactive'` as a safe default - a present-but-not-
  'auto' record deliberately PARKS (unknown is never coerced, either direction).
- Declared but NOT yet prepared: delete `<RunRoot>\autonomy_mode.json`, then prepare normally.
- Already PREPARED (or beyond): do NOT touch the record - a post-prepare flip in EITHER
  direction is the tamper lane (ESCALATION park, NF-A9). Correct path: abandon that prepare,
  remove the record, run a FRESH `Invoke-NeoRunPrepare` (new freeze binds segment NONE), fresh
  human START approval.

## Lever 2 - GLOBAL kill switch (Raphael only)
Add one line to `.neo\AUTO_MODE_ATTESTATION.md`, anchored at the start of a line:
```
STATUS: REVOKED (Raphael, <date>)
```
Effect: engine-validated fail-closed - every declared-AUTO run parks + notifies at its next
validation boundary (prepare or execute); no new AUTO run can start; the edit also breaks every
recorded hash-match (loud by design). Interactive runs are untouched.

## Re-enabling later
Re-signing = a NEW recorded signature event at a human gate (present the exact text; Raphael's
confirm = signature; stamp APPROVED / IN FORCE). The file hash changes, so stale
autonomy_mode.json records correctly PARK until re-declared against the new hash - expected,
not a defect.

## Never
Stamp/unstamp the attestation on Raphael's behalf (his revocation/signature, always); edit a
record mid-run to "downgrade gracefully" (park + fresh prepare is the graceful path); delete
ledger entries.
