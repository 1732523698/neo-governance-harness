---
name: NEO_AUTO_ON
description: >-
  Declare a NEO engine run AUTO (hands-off, workflow-gate pre-authorized). Utility skill, not a
  role: walks the manager through the sec-3A per-run declaration - preconditions, writing
  <RunRoot>\autonomy_mode.json with the LOWERCASE attestation hash BEFORE Invoke-NeoRunPrepare,
  and the attested_start_approval ledger wording. The ENGINE validates everything fail-closed;
  this skill is convenience, never authority. Trigger: "declare this run AUTO", "AUTO mode on",
  "hands-off run". No use outside S:\NEO trees.
---

# NEO_AUTO_ON - declare a run AUTO (per-run toggle ON)

**Authority chain (verify from disk, never assume):** spec `NEO_SESSION\_neo_roadmap\
NEO_AUTOMODE_DESIGN_v1.md` rev5 4F549F3A secs 3-4; standing attestation
`.neo\AUTO_MODE_ATTESTATION.md` must be stamped `STATUS: **APPROVED / IN FORCE` (Raphael-signed;
currently the D-A1 LOW-only envelope). Full procedure (BINDING detail, this skill only wraps it):
`NEO_SESSION\_neo_roadmap\NEO_AUTO_MODE_MANAGER_PROCEDURE.md`.

## Preconditions (ALL required; any miss => stay interactive or PARK, never force)
1. Attestation IN FORCE (no REVOKED stamp) - read it.
2. Run is DEV-only, every slice-plan risk row LOW (D-A1), strictly serial.
3. You are declaring BEFORE `Invoke-NeoRunPrepare`. NEVER after (post-prepare flip = tamper lane).

## Step 1 - write the record (BEFORE prepare)
```powershell
$att = (Get-FileHash '<NEO_ROOT>\.neo\AUTO_MODE_ATTESTATION.md' -Algorithm SHA256).Hash.ToLower()
@{ schema_id='neo:run_autonomy_mode'; run_id='<run manifest run_id, exact>'; autonomy_mode='auto'
   declared_by='<manager seat>'; declared_at=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
   attestation_sha256=$att } | ConvertTo-Json | Out-File '<RunRoot>\autonomy_mode.json' -Encoding utf8
```
LOWERCASE hash is load-bearing (engine matches -ceq vs its lowercase re-hash; uppercase PARKS).
`autonomy_mode` is case-exact `'auto'`.

## Step 2 - after prepare emits the START package, record the attested entry
- gate_kind: `attested_start_approval` (case-exact; NEVER `human_start_approval`)
- gate_ref: the engine-computed 6-segment tuple from the package, VERBATIM
- authorized_by: `Raphael (standing AUTO attestation <current sha8>)`
Cross-pairing refuses both ways; a conflicted ledger (same 5-segment prefix, different 6th
segment) refuses - fix by fresh prepare, never by editing the ledger.

## Never
Edit the attestation; declare after prepare; write `engine_auto_keep.json` yourself; treat an
engine auto-keep as a human keep (D-A2/NF-A6); widen the envelope in a record. Changed your
mind pre-execute? -> load `NEO_AUTO_OFF`.

## After the run
Clean converged GO => engine writes `<RunRoot>\engine_auto_keep.json` (human_review 'pending')
+ AUTO-KEPT mail. MANDATORY: surface to Raphael for async review. Anything non-clean => PARKED
+ notified; treat as a normal friction stop.
