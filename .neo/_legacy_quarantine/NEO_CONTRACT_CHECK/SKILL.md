---
name: NEO_CONTRACT_CHECK
description: >-
  OPTIONAL NEO graduation-readiness check. Use ONLY when a module is a graduation candidate
  (session_contract.graduation_target != null). It verifies the module's declared I/O contract:
  declared inputs/outputs, exported symbols and connection points actually present, allowed vs
  forbidden side effects (disjoint, and forbidden not performed in source), and non-colliding
  names — so the module can move to the larger platform without a rewrite. It emits
  contract_check_report.json. If the module is NOT a graduation candidate it is SKIPPED/NA and never
  blocks sandbox-only or throwaway modules. It does NOT code, test beyond contract checks, deploy,
  or decide approval. Trigger inside S:\NEO only for "graduation check", "is this ready to graduate",
  "contract conformance". No use outside S:\NEO.
---

# NEO_CONTRACT_CHECK — Graduation Readiness (optional)

**One job:** confirm a module that intends to graduate conforms to its declared I/O contract and
won't collide on names — nothing else. It is the *only* concession to the larger platform, and it
runs **only** for graduation candidates.

> Shared doctrine (evidence over confidence; two gates; one human surface; no secret values; stop, don't widen scope; ASCII .ps1): see `.neo/NEO_DOCTRINE.md`.

## Runs only when
`session_contract.graduation_target != null`. Otherwise → **SKIPPED/NA** with a reason. Throwaway
sandbox experiments are never forced to carry a contract.

## Owns exactly this
- Verify the module `contract.json`: declared **inputs**, **outputs**, **exported symbols**,
  **connection points**, **allowed/forbidden side effects**, `graduation_target`.
- Confirm each **exported symbol actually appears** in the module source.
- Confirm **names are non-colliding** (no duplicates; optional collision registry).
- Confirm `allowed_side_effects` ∩ `forbidden_side_effects` = ∅, and that the source performs **no
  declared forbidden side effect** (static scan: network / child_process / fs-write / env / eval).
- Emit `contract_check_report.json` (`status: PASS | FAIL | SKIPPED`).

## Must NOT do
- No coding · no testing beyond contract checks · no deployment · **no approval decision** ·
  **no blocking sandbox-only modules** · **no forcing contracts on throwaway experiments.**

## Module contract shape (`modules/<name>/contract.json`)
```json
{
  "module_name": "util",
  "declared_inputs": ["a:number", "b:number"],
  "declared_outputs": ["number"],
  "exported_symbols": ["add"],
  "connection_points": ["require('modules/util')"],
  "allowed_side_effects": [],
  "forbidden_side_effects": ["network", "child_process"],
  "test_commands": ["..."],
  "graduation_target": "platform/utils"
}
```
Validated against `.neo/schema/module_contract.schema.json`.

## Tool & gate
`contract_check.ps1 -SessionPath <dir> -ModuleRoot <module dir> [-CollisionRegistry <json>]`.
The audit net's **C13** enforces it: if `graduation_target` is set, `contract_check_report.json`
must exist with `status == PASS`, else the session is red. If `graduation_target` is null, C13 is
NA — graduation logic never burdens a sandbox-only module.

## Hard line
Contract_Check recommends graduation-readiness; it never deploys, never approves, and never blocks a
module that wasn't trying to graduate in the first place.
