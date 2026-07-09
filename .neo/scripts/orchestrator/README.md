# NEO 4.0-P3-B (B1) - minimal serial master-orchestrator RUNTIME

Additive engine subtree. Installs/edits nothing outside `./.neo/scripts/orchestrator/`.
Builds against the 25 installed spine schemas in `../../schema/` (read-only). RT-HIGH
(governance core). Serial-only; concurrent orchestration has no enabled path (A5).

## Scope delivered (B1)
Core loop `S0-S4` INIT + schema-validated evidence I/O + the coordinate-not-validate
seam. The remaining enforcement (tiered audit, human gates, model-routing, rollback
boundary, rollover/HANDOFF) and the full seeded-defect matrix are **B2**.

## Scope delivered (B2a)
The dispatch-side enforcement layer, wired fail-closed into the loop:
**E1 tiered audit** (D4), **E2 human-gate binding** (D5), **E3 model-routing fail-closed**
(D6), plus the residual-(b) `$ref` cycle guard folded into the instance validator.
`Invoke-NeoGovernedDispatch` runs the precondition chain **E2 -> E3 -> E1** before any START
packet is built, and `Read-NeoAuditResult -RequiredTier` makes an auditor-class AUDIT_RESULT
mandatory where the selected tier is isolated/full_isolated. **E4** (rollback / dependent-
continuation) and **E5** (rollover / HANDOFF) are **B2b** (shipped with their wiring + tests).
Still coordinate-not-validate: the enforcement writes no AUDIT_RESULT/GO.

> Note (E3 capability ladder): the routing ladder is intentionally **stricter** than D6's literal
> "architecture" row - a strong_producer's work requires an **auditor-class** validator (validator=1,
> auditor=2 vs cheap=1/strong=2), so `validator < producer` is reachable and fail-closed by design.

## Scope delivered (B2b)
The dispatch-side **lifecycle** layer, wired fail-closed into the loop:
**E4 rollback / dependent-continuation** (D8), **E5 rollover / HANDOFF** (D7), plus the residual-(c)
malformed-ledger fold. All coordination - the lifecycle layer writes no AUDIT_RESULT/GO.

- **E4** (`orch_rollover.ps1`): `Assert-NeoDependentContinuationAllowed` inspects SUBSESSION_INDEX
  from the index alone and BLOCKS dependent continuation unless every declared dependency is in a
  *provably-safe* state. `Assert-NeoResolutionValid` enforces that a terminal resolution is valid:
  `rolled_back` requires a `rollback_ref` (E4c), `human_accepted_fail` requires a `gate_ref` that
  **binds in the HUMAN_GATE_LEDGER** (E4b - the cross-check the schema cannot express, reusing B2a
  `Resolve-NeoGate`). Wired as the **FIRST** precondition of `Invoke-NeoGovernedDispatch` (before
  E2->E3->E1); a dispatch with no declared dependency is a no-op, so B1/B2a callers are unchanged.
  The complete **A1 status->decision table** (every status incl. unknown/blank has an explicit
  allow-or-BLOCK verdict; nothing falls through to allow) lives in `Assert-NeoDependentContinuationAllowed`.
- **E5** (`orch_rollover.ps1`): `New-NeoHandoffPacket` emits a schema-valid HANDOFF_PACKET on any
  mandatory rollover trigger (context threshold / unresolved ambiguity / high-risk transition /
  failed sub-session / master drift); `packet_self_hash` covers the whole body (incl. `_provenance`)
  with only itself neutralized to a sentinel. `Assert-NeoPacketResumable` lets a fresh master resume
  from the packet **ALONE**: schema-valid; A2 not-stale gate (a missing/null flag REJECTS via the
  null/non-bool guard, never a bare `==false` - `$null -eq $false` is `$false` in PS 5.1);
  `packet_self_hash` recompute (E5c); every program `*_ref` re-hashed against its `<NAME>.json` home
  and `last_green_state.proof_ref` re-hashed; any mismatch/false/missing => REJECT.
- **Residual (c)**: `Read-NeoGateLedger` gains an OPTIONAL `-Index`; when supplied it validates the
  ledger on load so a malformed ledger fails as a **clean NEO-BLOCK** (via `Assert-NeoGateLedgerShape`,
  and full `Assert-NeoValid` iff the ledger schema is registered in the index). NOTE:
  `neo:human_gate_ledger` carries no `$id`, so the frozen `Get-NeoSchemaIndex` does not register it and
  a literal `Assert-NeoValid` against it is unreachable today - the structural shape guard delivers the
  same fail-closed intent without a protected-schema edit. The no-`-Index` path is byte-behaviour-
  identical to B2a, so the frozen enforce suite stays 48/48.

Concurrency stays **DISABLED**: `ownership_lease` is referenced read-only only; `orchestration_mode`
stays `serial`; there is no enabled concurrent path. Still coordinate-not-validate: G3c/G3d extended
to `orch_rollover.ps1` (no separate-auditor-writer reference; no `rehash_check` result literal).

### B2b-FIX (E5 resume hardening — 2 Codex-found fail-open surfaces closed)
- **F1 (blocking) proof_ref path traversal**: `Assert-NeoPacketResumable` resolved
  `last_green_state.proof_ref` with a bare `Join-Path` and no containment, so `'../../outside.txt'`
  (or rooted/drive/UNC/backslash) escaped the program root and resumed if the hash matched. Fixed by
  reusing the orch_schema helpers: `Assert-NeoSafeRel $proofRel` then
  `$proofPath = Assert-NeoContained $ProgramRoot $proofRel` (reject rooted/drive/UNC/backslash/`..`/empty
  + assert the resolved path stays under ProgramRoot). The `*_ref` loop was already safe (fixed
  `<NAME>.json` homes).
- **F2 envelope content_hash unverified on resume**: resume checked schema + `packet_self_hash` + `*_ref`
  hashes but never verified the packet's own `_provenance.content_hash` (every other artifact read does).
  Fixed with `Assert-NeoHandoffEnvelopeHash` (wired after the not-stale gate). CRITICAL: the content_hash
  was built while `integrity.packet_self_hash` was still the `'UNSET'` sentinel (content_hash first,
  self-hash after), so the verify reproduces that via the shared `Get-NeoHandoffBodyHashNeutralized` —
  a valid packet does NOT false-reject, a stale/tampered `_provenance.content_hash` REJECTs (the
  load-bearing guard for that tamper even when `packet_self_hash` is re-stamped self-consistent).
- **F3 containment sweep** (standing rule): every `Join-Path` of a non-fixed value across
  `orch_rollover`/`orch_enforce`/`orch_engine`/`orch_io` was classified; the proof_ref was the ONLY
  unguarded attacker-path. All other joins are fixed `<NAME>.json` homes or already
  `Assert-NeoSafeRel`+`Assert-NeoContained`-guarded — no protected file needed editing.

### B2a-FIX (fail-open surfaces closed)
Three Codex-found fail-open surfaces in the B2a enforcement were fixed surgically: **F1** gate
sensitivity is now fail-closed (a blank/missing area => BLOCK; only the exact `general_feature`
is batchable-eligible; every other/unknown area is sensitive; `never_batchable` may only ADD
sensitivity); **F2** a bound gate must authorize a non-empty declared scope (empty ScopePaths on a
gated dispatch => BLOCK, so authorized-path coverage can never be skipped); **F3** a non-empty
`-RequiredTier` outside `{lightweight, isolated, full_isolated}` => BLOCK (case-exact), so a typo'd
tier can no longer skip the auditor mandate. Each is covered by a load-bearing negative in the suite.

## Files
| File | Role |
|------|------|
| `orch_schema.ps1` | schema index + `Test-NeoSchema` ($ref-resolving JSON-Schema validator, FAIL-CLOSED; B2a: instance-pass `$ref` cycle guard) + canonical serialization + body/self hashing + structure-preserving pretty writer |
| `orch_class.ps1`  | artifact-class oracle over the live `artifact_classes.json`; routing-layer UNKNOWN => BLOCK (never uses `default_class`) |
| `orch_io.ps1`     | program evidence read/write to the exact `<NAME>.json` homes (never a `*.PLACEHOLDER`), provenance envelope build/verify, snapshot-before-overwrite |
| `orch_enforce.ps1` | **B2a** enforcement (COORDINATION only): E1 `Resolve-NeoAuditTier`, E2 `Read-NeoGateLedger`/`Resolve-NeoGate`/`Assert-NeoGateBound`, E3 `Assert-NeoRouteEdit`, the `Assert-NeoDispatchAllowed` precondition, `Add-NeoIndexRecord`; **B2b** residual-(c) `Assert-NeoGateLedgerShape` + `-Index` fold. Writes no AUDIT_RESULT/GO. |
| `orch_rollover.ps1` | **B2b** lifecycle (COORDINATION only): E4 `Assert-NeoDependentContinuationAllowed`/`Assert-NeoResolutionValid`/`Get-NeoIndexRecord`, E5 `New-NeoHandoffPacket`/`Assert-NeoPacketResumable`/`Assert-NeoNotStaleComplete` (+ handoff self-hash helpers). Writes no AUDIT_RESULT/GO; serial-only. |
| `orch_engine.ps1` | serial state machine: `Invoke-NeoInit`, `New-NeoStartPacket`, **B2a `Invoke-NeoGovernedDispatch`** (**B2b: E4 wired as the FIRST precondition**), `Read-NeoEndReport`, `New-NeoAuditBundle`, `Read-NeoAuditResult` (**B2a `-RequiredTier`**); the serial-only guard |
| `orchestrator.ps1`| operator CLI (`init` / `validate` / `status`) |
| `orch_auditor_stub.ps1` | **SEAM/STUB** for the separate isolated auditor. The ONLY writer of an AUDIT_RESULT. Deliberately OUTSIDE the engine library. |
| `harness/orch_fixture_suite.ps1` | B1 independent seeded-defect harness (v4 5.7) + end-to-end serial run. Kept separate from the engine it tests. |
| `harness/orch_enforce_suite.ps1` | **B2a** independent enforcement harness: E1/E2/E3 negatives + neuter-on-copy load-bearing proofs + the gated+tiered+routed E2E-to-GO. |
| `harness/orch_rollover_suite.ps1` | **B2b** independent lifecycle harness: E4 (a/b/c + A1 status table) + E5 (a/b/c + A2 not-stale) negatives + neuter-on-copy proofs + the RESUME-E2E (fresh master resumes from the packet ALONE) + residual-(c). |

## Coordinate-not-validate (crown jewel, v4 5.1)
The engine library **assembles** the audit bundle and **consumes** an AUDIT_RESULT, but has
**no code path that writes an AUDIT_RESULT or a GO**. `Read-NeoAuditResult` additionally
BLOCKS when `auditor_identity` (or the result's producer role) is the master/builder, and
independently re-hashes every bundle member (rehash mismatch => NO-GO). The auditor writer
lives only in the separate `orch_auditor_stub.ps1`. The engine cannot self-approve.

## Run the harness
```
powershell -File .\harness\orch_fixture_suite.ps1
```
Exits 0 iff every guard fails closed AND the end-to-end serial run yields a GO with
spine-valid evidence AND the scratch area is residue-clean. Use `-KeepScratch` to inspect,
`-ProofOut <path>` to emit a JSON report, `-ScratchRoot <dir>` to relocate the scratch.

## Guard table (NEGATIVE fail-closed guards; removing the guard flips the assertion)
The harness separates **NEGATIVE guards** (load-bearing; each must BLOCK bad input) from
**POSITIVE/info checks** (E2E happy run, known-class-resolves, numeric-equal control) which
confirm no regression but are NOT guards. The load-bearing count is the negative guards.

| Guard | Seeded defect | Enforced by |
|-------|---------------|-------------|
| G1 | schema-invalid evidence | `Test-NeoSchema` via `Assert-NeoValid` (required/type/enum/...) |
| G2 | concurrent orchestration | `Assert-NeoSerialMode` (code) + `master_checkpoint` enum `["serial"]` |
| G3 | engine writes its own GO | no emit path (structural) + `auditor_identity`/producer == master => BLOCK |
| G4 | unknown/unclassified artifact class | routing UNKNOWN => BLOCK; unknown envelope class => BLOCK |
| G6 | rehash mismatch in the audit bundle | independent re-hash + `all_members_matched=false => NO-GO` (engine-enforced prose) |
| F1 | malformed schema hidden in an `if`/`then`/`else` branch (unsupported keyword / unresolvable `$ref`) | `Test-NeoSchemaSupport` preflight over the whole schema graph => BLOCK before instance eval |
| F2 | audit-bundle member path escapes the bundle root (`..`, rooted, drive, UNC, backslash, empty) | `Assert-NeoSafeRel` + `Assert-NeoContained` at assembly, consume, AND the auditor stub |
| F3 | enum/const equating unlike JSON types (string "5" == number 5) | `Test-NeoJsonEqual` is JSON-type-aware; unlike types are never equal; no `[double]` on a non-number |

## PowerShell 5.1 correctness notes (governance-critical)
- **Array fidelity.** `Get-NeoVal` uses `Write-Output -NoEnumerate` so single-element
  arrays keep their array type through function returns; evidence files are written with a
  structure-preserving pretty writer (NOT `ConvertTo-Json`, which unwraps single-element
  arrays). Both are required for `type:array` validation and stable round-trip hashing.
- **Empty objects.** `Get-NeoPropNames` enumerates the property objects, because
  `.PSObject.Properties.Name` on an empty PSCustomObject (e.g. `{}` read back) yields a
  phantom empty name.
- **Hashing.** The envelope `content_hash` excludes `{_provenance, self_hash}`; the
  input_packet `self_hash` excludes `{self_hash}` and is stamped after the envelope. This
  breaks the mutual dependency for packet-family artifacts. The canonical serializer is
  container-type-independent (hashtable and PSCustomObject hash identically), which is what
  makes write/read hashing stable.
- **Time.** `created_at`/`updated_at` are caller-supplied; the engine never self-generates
  time (mirrors `neo:checkpoint`).
- **Schema well-formedness (F1).** `Test-NeoSchema` runs `Test-NeoSchemaSupport` ONCE over the
  whole schema graph before evaluating the instance, so a malformed/unsupported construct
  (including one buried in an `if`/`then`/`else` branch the instance would not take) is a
  fail-closed BLOCK and can never be mistaken for an unmet `if`-condition. Internal recursion
  passes `-NoPreflight` so the traversal runs exactly once.
- **Bundle path safety (F2).** Every audit-bundle member `rel` is validated with
  `Assert-NeoSafeRel` (rejects rooted / drive / UNC / backslash / `..` / empty) and, on
  consume, resolved through `Assert-NeoContained` (must stay under the bundle root) BEFORE any
  `Join-Path`/read -- at assembly, at engine consume, and in the auditor stub.
- **Type-aware equality (F3).** `Test-NeoJsonEqual` compares by JSON type; unlike types are
  never equal and no non-numeric value is ever `[double]`-coerced (which previously both
  equated "5" with 5 and threw a raw exception on a non-numeric string).
