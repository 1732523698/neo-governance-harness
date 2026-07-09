---
name: NEO_SYSTEM
description: >-
  Entry router and operating manual for the NEO sandbox skill system. Load THIS skill first (and only
  this one) when starting or resuming any NEO session inside S:\NEO; it routes you to exactly ONE of the
  three NEO roles per phase instead of loading them all. Use it to decide which role to activate for the
  current phase (planning/gates/dispatch/budget -> Director, implementation -> Builder,
  verification/audit/graduation -> Auditor), to recall the one-role-at-a-time and do-not-load-all rules,
  and to check whether NEO is even the right tool. It is a ROUTER, not a role or a doctrine dump: it does
  not plan, code, test, audit, route models, or talk to the human - it points you at the role that does.
  Trigger inside S:\NEO for "start a NEO session", "which NEO role", "route this NEO phase",
  "resume the NEO session", "use the NEO system". No use outside S:\NEO.
---

# NEO_SYSTEM - Entry Router & Operating Manual (3.0 three-role)

**One job:** be the single low-overhead entry point. Load NEO_SYSTEM first, let it route you to the ONE
role that owns the current phase, and activate only that role. NEO_SYSTEM is a **router, not a role** - it
never does the work itself and never restates role bodies or doctrine (those live in the role skills and
in `.neo/NEO_DOCTRINE.md`).

## Authority (the rule that overrides agent confidence)
**Scripts and artifacts are the authority, not agent confidence.** A role's or subagent's self-report is a
hint, never a gate - the scripts, the diff, and the audit nets decide correctness and win over any
confident narrative. The enforcing checks are named by ID in each role body and in `.neo/DEFINITIONS.md`:
app-slice **AS1-AS17**, end-evidence **E1-E8**, session **C1-C13**, plus the **P/A/H** helpers
(`pm_consistency` P*, `ambassador_check` A*, `lint_skills` H*). Full principles: `.neo/NEO_DOCTRINE.md`.

## Loading rules (the whole point of the entry layer)
1. **ONE active role skill at a time.** Activate the single role that owns the current phase; finish it;
   then switch. Never run two role skills as your active lens at once.
2. **Do NOT load or paste all NEO skills into context.** NEO_SYSTEM + the one current role is the whole
   footprint. Loading every `NEO_*` skill defeats the entry layer and pollutes context.
3. **Shared doctrine is referenced, not copied** - it lives once in `.neo/NEO_DOCTRINE.md`.

## Phase -> role map (route to exactly one of three)
The 3.0 surface is **three roles**. Each consolidates several legacy seats, but routing is one arrow per
phase to exactly one role. Detail and the enforcing check-IDs live in each role body, not here.

| Phase | Activate | Owns (enforced by check-IDs) |
|---|---|---|
| START / planning - scope & contract; both human gates; dispatch & cost-route; budget & resume; app-governance manager hosting | `-> NEO_DIRECTOR` | contract integrity (C1/C2, P*); human gates (A*, C10/C12); dispatch reconcile (C8); budget/resume (C11) |
| Implementation - edit the approved slice and leave diff evidence | `-> NEO_BUILDER` | scope discipline + snapshot-before-destructive (C3/C3b/C4/C10b) |
| Verification, audit, graduation - run promised tests, prove zero residue, fresh-context review, I/O conformance | `-> NEO_AUDITOR` | tests/residue (C5/C6); fresh-context review (C7); graduation (C13) |

Routing notes:
- The **human gates** (START approval, END keep/iterate/toss) are carried by NEO_DIRECTOR, the single
  human surface; approval is the human's explicit answer, never inferred from silence.
- **Graduation** runs only when `session_contract.graduation_target != null`; otherwise the Auditor
  skips it (C13 NA).
- **App-governance managers** (product-spec / QA / env / migration / release) are **hosted by
  NEO_DIRECTOR**, lazy-loaded AT MOST ONE manager at a time; they are planning-only and are not separate
  routing targets at the entry layer.
- The audit nets - `verify_session.ps1` (sessions) and `verify_app_slice.ps1` /
  `check_app_end_evidence.ps1` (app slices) - are the authority for every phase regardless of which role
  is active.

## App-risk tier routing (RT1-RT4)
NEO governs app work by an **app-risk tier** (RT1-RT4), SEPARATE from the sandbox-session `T1` in
`.neo/DEFINITIONS.md` (that one is "always T1" for editing NEO itself). Pick the tier by the highest-risk
surface the work touches, then **lazy-load only the artifacts that tier needs** - their full criteria
live in the files below, never here.

| App-risk tier | Lazy-load (do not load otherwise) |
|---|---|
| RT1 reversible docs/sandbox/local | none |
| RT2 low-risk app code | `.neo/NEO_APP.md` (read) |
| RT3 runtime/business-sensitive | `.neo/NEO_APP.md` + `.neo/NEO_RISK_TIERS.md` + `.neo/NEO_RELEASE_DISCIPLINE.md` |
| RT4 prod/destructive/security/payment | all RT3 artifacts + explicit human approval first |

Dependency/package/lockfile changes are governed (RT3 by default; RT4 if they touch
auth/payment/database/crypto/email/deployment/build/prod runtime) - see `.neo/NEO_RELEASE_DISCIPLINE.md`.
Full tier criteria (`.neo/NEO_RISK_TIERS.md`), the release/rollback/backup checklist
(`.neo/NEO_RELEASE_DISCIPLINE.md`), and the per-project app-memory template (`.neo/NEO_APP.md`) live in
those files - NEO_SYSTEM only points at them; it never restates them, and `NEO_APP.md` is a template,
not a role to route to.

## When to use NEO
- Building or testing a **side module / experiment inside `S:\NEO`** where you want scripts and
  artifacts - not agent confidence - to decide correctness.
- You want **two human gates**, fresh-context audit, zero-residue proof, and resumable checkpoints.
- The work is **sandbox-safe**: no real users, money, production data, or external accounts beyond
  human-attested sandbox ones.

## When NOT to use NEO
- Work on a **real project** (AI_Orchestrator, rental-platform, EMS, etc.) - use that project's process;
  NEO conventions never override a real-project gate.
- Anything touching **production, real accounts/data, secrets, migrations, or money** - outside the
  sandbox's hard external boundary.
- A **one-off question or trivial edit** that doesn't need the role/gate/audit machinery.

## What NEO_SYSTEM does NOT do
It does not plan, code, test, audit, route models, manage budget, or talk to the human - each of those is
one of the three roles above. NEO_SYSTEM only tells you which role to load, and it never embeds the role
bodies or the full doctrine - keeping the entry footprint small is its reason to exist.

## Transitional note (3.0 cutover - Session 8)
The live surface routes to **NEO_DIRECTOR / NEO_BUILDER / NEO_AUDITOR** only. Legacy role folders and the
app-governance manager folders may still be present but are **UNROUTED pending Session-9 quarantine** - do
not activate them as a routing target.

---
*Shared doctrine: `.neo/NEO_DOCTRINE.md`. Encoded audit definitions/checks: `.neo/DEFINITIONS.md`.
Role specifics + their enforcing check-IDs: the individual `NEO_*/SKILL.md` files.*
