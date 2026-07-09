# NEO App-Risk Tiers (RT1-RT4)

> v2.0 governance-core artifact. **Single source of truth for app-development risk tiers.**
> These RT tiers classify the APP WORK a NEO session governs. They are DISTINCT from the
> sandbox-session tier `T1` in `.neo/DEFINITIONS.md` (which is "always T1" for editing NEO itself).
> Never overload bare `T1` to mean app risk. NEO_SYSTEM references this file; it never restates the
> criteria below. Lazy-load: pull this file only when the work's tier is RT2 or higher.

Tier is chosen by the HIGHEST-risk surface the work touches (a single RT4 surface makes the whole
slice RT4). When ambiguous between two tiers, escalate to the higher one and ask at the human gate.

---

<!-- ANCHOR:RT1 -->
## RT1 - docs / sandbox / local, fully reversible
**Examples:** documentation, NEO self-edits, local-only scratch, comment/typo fixes, a throwaway
experiment under `modules/**` with no shared consumer.
**Gate:** light START audit; focused verification (the change is its own proof). No app artifacts
required. Reversible by discard.
**Required artifacts:** none beyond the NEO session net.

<!-- ANCHOR:RT2 -->
## RT2 - low-risk app code
**Examples:** frontend-only changes, an isolated refactor with no behavior change, non-financial
display logic, added tests, internal tooling that does not touch runtime data.
**Gate:** scoped plan; build + typecheck must pass; focused smoke of the changed surface.
**Required artifacts:** `NEO_APP.md` (read, for context: stack, commands, invariants).

<!-- ANCHOR:RT3 -->
## RT3 - runtime / business-sensitive
**Examples:** backend logic, database read/write, financial or business rules, auth/access control,
environment/config, object storage, email, cron/schedulers, staging-or-prod data, migrations,
**and any dependency/package/lockfile change by default (see DEP-GUARD in NEO_RELEASE_DISCIPLINE.md).**
**Gate:** full START audit; backup/rollback plan recorded BEFORE edit; independent verification of
rendered/runtime behavior (not just a mechanical diff).
**Required artifacts:** `NEO_APP.md` + `NEO_RISK_TIERS.md` + `NEO_RELEASE_DISCIPLINE.md`; plus
product / QA / env / migration / release governance **as applicable** (those managers are PARKED for a
future session - apply the discipline inline until they exist).

<!-- ANCHOR:RT4 -->
## RT4 - production / destructive / security / payment
**Examples:** production deploy or config mutation, destructive/irreversible operations, security or
access-control changes, payment/billing, crypto/secret material, anything that can lose or expose real
data. Dependency changes touching auth/payment/database/crypto/email/deployment/build-system/prod
runtime are RT4 (see DEP-GUARD).
**Gate:** **explicit human (Raphael) approval, every time.** Backup + rollback executed/verified FIRST.
Exact command review before running. Closeout audit after. No automatic anything.
**Required artifacts:** all RT3 artifacts + an explicit approved command list + a verified rollback path.

---

<!-- ANCHOR:RT-MATRIX -->
## Tier -> required-artifact / gate matrix (the routeable summary)

| Tier | Risk | Gate | Lazy-load |
|---|---|---|---|
| RT1 | reversible docs/sandbox/local | light START; focused verify | none |
| RT2 | low-risk app code | scoped plan; build+typecheck+smoke | NEO_APP (read) |
| RT3 | runtime/business-sensitive | START audit; backup/rollback first; behavior proof | NEO_APP + NEO_RISK_TIERS + NEO_RELEASE_DISCIPLINE |
| RT4 | prod/destructive/security/payment | explicit human approval; backup+rollback first; exact-command review; closeout audit | all RT3 + approved command list + verified rollback |

**Manager note:** NEO_PRODUCT_SPEC / NEO_QA_SCENARIO / NEO_ENV_MANAGER / NEO_MIGRATION_MANAGER /
NEO_RELEASE_MANAGER are PARKED. Until they exist, RT3/RT4 sessions apply the equivalent discipline
inline and record it in the session evidence. Creating any of those skills needs explicit approval.
