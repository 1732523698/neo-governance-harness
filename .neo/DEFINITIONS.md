# NEO Sandbox — Encoded Definitions

These turn the previously "vibe-based" rules into machine-checkable definitions. They are the
authority for `verify_session.ps1`. Sandbox conventions win **inside `S:\NEO` only**; nothing here
overrides a real-project gate.

- **Sandbox root:** `S:\NEO`
- **Tier:** T1 (always — no real users/money/production data).
- **Execution path:** Claude API + provider-side spend cap (deterministic). Subscription is a
  documented fallback only.
- **Human gates:** START + END. No mid-session *safety* interrupt. The only mid-session human
  escalation is a budget/scope guardrail (cost control, not safety).
- **Secret rule:** key *names* OK; key *values* never written/echoed/logged/saved anywhere.

---

## Role ownership (de-overlap — exactly one owner each)
- **NEO_PM** — session-contract integrity ONLY (START packet exists & complete; no edit before
  approval; END packet diffs actual-vs-START).
- **NEO_ORCHESTRATOR** — routing / subagent dispatch / in-sandbox permission authority.
- **NEO_GOVERNOR** — budget + resumability/checkpoint.
- **NEO_AMBASSADOR** — ALL human-facing language. Other roles emit machine-readable reports only.

---

## Destructive operation (NEO_CODER must snapshot first)
`delete` · `overwrite` · `migration` · `data_mutation` · `credential_or_env_write` ·
`dependency_change` · `large_rename` · `generated_file_replacement`.
Coder must also record before/after `git status --short` (or sandbox equivalent).

## Zero-residue (NEO_VERIFIER pass requires ALL THREE)
1. **Layer 1 — manifest cleanup complete:** everything the verifier created is removed.
2. **Layer 2 — before/after snapshot diff clean** for **every declared `state_surface`**, ignoring
   only `volatile_paths_ignored_in_residue` (keep that list narrow).
3. **Second run** from a clean state passes again (no carried pollution).

### State surfaces (C5 scoping — keeps the first cut low-friction)
- Layer-2 snapshots are required for **every surface declared** in `session_contract.state_surfaces`.
- Foundation / local-only sessions declare `["filesystem"]`.
- `database` / `object_storage` / `external_account` become mandatory **when declared or used**.
- **Undeclared external/DB/object use = FAIL.** If `external_accounts_registry` is non-empty,
  `external_account` MUST be in `state_surfaces`.

### External-account attestation (P7 — sandbox status is HUMAN-ATTESTED, never inferred)
An external account is accepted only when the human has explicitly attested it, via fields on each
`external_accounts_registry` entry — NOT by matching "sandbox" in the name (a real `sandbox-prod`
must never pass). P7 (in `pm_consistency.ps1`) requires:
`environment == "sandbox"` · `human_attested_sandbox_only == true` · `forbidden_real_data == true` ·
`spend_cap_configured == true` · `account_label` present · `allowed_domains` present · and no
production/real marker (`prod|production|live|real|main`) in `account_label`/`provider`.
PM checks the attestation is present; it does not contact the provider.

## Auditor input allowlist (NEO_AUDITOR sees ONLY these)
`session_contract.json` · `changed_files/` · `git_diff.patch` · `test_results.txt` ·
`typecheck_results.txt` · `verifier_residue_report.json` · `known_constraints.md`.
**Forbidden to auditor:** coder chat, coder self-eval, "why this is safe" narrative, summarized or
cherry-picked output. A neutral implementation summary is allowed, but raw evidence dominates.

### Auditor findings — machine-readable (C7 hardening)
`auditor_findings.json` = an array of:
```json
{
  "severity": "low|medium|high|critical",
  "evidence_type": "file_line|diff_hunk|test_output",
  "path": "relative/path",
  "line_start": 0,
  "line_end": 0,
  "claim": "what is wrong and why"
}
```
`verify_session.ps1` C7 confirms cited `path` exists and the line range is within the file (for
`evidence_type=file_line`). Citations that point at non-existent files/lines = FAIL.

## Model routing log (C8 hardening — classification recorded up front)
`model_routing_log.json` = `{ "routing_mode": "...", "entries": [ ... ] }` where each entry:
```json
{
  "task_id": "...",
  "task_classification": "mechanical|moderate_judgment|hard_logic_or_audit",
  "model_used": "...",
  "policy_expected_model": "...",
  "reason": "..."
}
```
- `routing_mode: "not_applicable_foundation_only"` is valid when no subagent dispatch occurred.
- C8 fails if `model_used` != `policy_expected_model` for the recorded `task_classification`, or if an
  expensive model is used on a `mechanical` task. Classification is recorded at dispatch, not after.

## Governor honesty split (no overselling)
- **Reliable:** checkpoint · resume-from-checkpoint · API provider spend cap.
- **Best-effort:** own-counter token/cost estimate · pause before likely overrun.
- **Unsupported (needs external system):** auto-resume after reset (needs an external scheduler) ·
  exact Claude subscription quota awareness. These are NOT claimed.

## Ambassador END summary — required fields
what changed · what was tested · what failed/skipped · residue status · budget/scope deviations ·
**Known limitations / unverified items** · exact decision needed.
Decision question: **"Keep / iterate / toss? Does this match intent?"**

## Guards
- **Green-from-cache:** typecheck/test/build must run non-cached; record exit code + freshness flag.
- **Stale-checkpoint:** on resume, re-hash `changed_files_baseline` and compare before continuing.
- **Secret scan (C9):** HEURISTIC, shape-based (e.g. `sk-…`, `AKIA…`, `-----BEGIN`, long base64,
  `"api_key": "…"`). Necessary but **not complete** secret prevention; do not oversell it.

---

## verify_session.ps1 — the 10 checks (evidence, not claims)
| # | Check | Blocks when |
|---|---|---|
| C1 | Contract validates (required fields present) | always |
| C2 | START gate predates first edit | edits exist |
| C3 | Edited paths ⊆ approved, ∩ protected = ∅ | edits exist |
| C4 | Destructive op has a pre-op snapshot | destructive op in diff |
| C5 | Residue: manifest + snapshots per declared surface + 2nd run | END, or surfaces used |
| C6 | Tests = promised cmd, non-cached, exit 0 | END, or tests run |
| C7 | Auditor report + valid findings, citations resolve | a `fresh_audit_required_when` trigger fired |
| C8 | Routing log matches policy | subagent dispatch occurred |
| C9 | Secret-shaped value found (heuristic) | always |
| C10 | END summary has all required fields | END summary present |

`PASS` / `FAIL` / `NA` (not applicable this phase) / `PENDING` (artifact not yet produced).
**Exit non-zero if ANY check is `FAIL`.** Partial green = red.

### Audit modes & END-gate strictness
`verify_session.ps1 -Mode Auto|Fresh|EndGate` (default `Auto` = END when `ambassador_end_summary.md` exists).
- **Fresh / in-progress:** `PENDING` and `NA` are allowed; a session with no FAIL exits 0 as `INCOMPLETE`.
- **END gate:** stricter, per the rule below.

```
END_GATE_STRICTNESS:
  At END gate, any PENDING check -> FAIL (exit non-zero).
  NA on a MANDATORY check (C5, C6, C7, C10) -> FAIL, UNLESS session_contract.na_justifications
  contains an explicit reason for that check id. Structural NA on C3/C4/C8 (no diffs / no
  destructive op / no dispatch) remains allowed.
```

> **Foundation status:** full JSON Schema validation is PENDING (no package installs in this step).
> The script enforces the `required` arrays via pure PowerShell today.
