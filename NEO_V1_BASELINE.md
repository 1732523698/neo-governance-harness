# NEO v1 — BASELINE (FROZEN 2026-06-09)

A low-stakes, self-policing sandbox for building and testing side modules. Correctness is judged by
**scripts and artifacts, not agent confidence**. Two human gates per session (START, END); auditors
recommend, the human decides. Sandbox conventions win **inside `S:\NEO` only**; nothing here
overrides a real-project gate.

> **STATUS: v1 COMPLETE & FROZEN.** Do not add features to this baseline. v2 work happens in a new
> session (see Handoff below).

## Roles (8/8) — `.claude/skills/NEO_*`
| Role | Job (one line) | Falsified by |
|---|---|---|
| NEO_PM | session-contract integrity only | pm_consistency.ps1 (P1–P11) |
| NEO_AMBASSADOR | sole human interface; summarize, never sanitize | ambassador_check.ps1 (A1–A4) |
| NEO_ORCHESTRATOR | dispatcher / cost-router / in-sandbox permission authority | C8 |
| NEO_CODER | implement approved slice only; diff evidence | C3, C3b, C4 |
| NEO_VERIFIER | seed→run→report→cleanup; 2-layer residue; 2nd run | C5, C6 |
| NEO_AUDITOR | fresh-context review from artifacts only | C7 |
| NEO_GOVERNOR | resumability-first checkpoint + budget; honest split | C11 |
| NEO_CONTRACT_CHECK | graduation-readiness (optional, candidates only) | C13 |

## Audit net — 14 checks (`verify_session.ps1`)
C1 contract valid · C2 START before edits · C3 scope ⊆ approved · C3b coder report vs diff ·
C4 destructive→snapshot · C5 residue (2-layer + 2nd run) · C6 tests promised/non-cached/exit0 ·
C7 auditor fresh + manifest hash-verified · C8 routing↔dispatch↔prompts reconciled · C9 secret scan
(heuristic) · C10 END summary 10 sections · C11 checkpoint valid · C12 END no-sanitize mapping ·
C13 graduation contract (candidates only). **Exit non-zero on any FAIL. END gate: PENDING→FAIL.**

## Scripts (`.neo/scripts`)
new_session · verify_session · pm_consistency · ambassador_check · verifier · assemble_auditor_input
· governor · contract_check.

## Schemas (`.neo/schema`)
session_contract · residue_report · checkpoint · module_contract. Full JSON-Schema validation is
**PENDING** — today the net enforces the `required` arrays via pure PowerShell.

## Proven
- **Full green E2E**: a trivial module driven through all 7 mandatory roles → EndGate exit 0.
- **Composed negative**: a sanitized summary hiding a high-severity auditor finding → C12 FAIL →
  EndGate exit 1. Serious findings cannot be sanitized past the human gate.

## Locked decisions
- Tier T1 (sandbox). Execution path: **Claude API + provider spend cap** (deterministic); subscription
  is a documented fallback only.
- Governor honesty split: **reliable** = checkpoint/resume/stale-detect/API spend cap · **best-effort**
  = own-counter estimate · **unsupported** = exact subscription quota, auto-resume after reset.
- External accounts: **human-attested** sandbox-only + spend cap (P7), never inferred from a name.
- Secret VALUES never written/echoed/logged anywhere; key names OK.
- PS 5.1 constraint: all `.ps1` are ASCII-only (UTF-8-without-BOM is misread as ANSI).

## How to run a session
1. `new_session.ps1 -SessionId <id> -Goal "<goal>"` → fill `session_contract.json` + `start_packet.md`.
2. `pm_consistency.ps1` (START) → human approves START gate.
3. Orchestrator writes routing log + dispatch ledger + prompts; Coder edits approved paths + diff.
4. `verifier.ps1` → `assemble_auditor_input.ps1` → Auditor findings → `governor.ps1 -Action checkpoint`.
5. Ambassador writes the 10-section END summary → `verify_session.ps1 -Mode EndGate` must exit 0 →
   `ambassador_check.ps1` → human decides keep/iterate/toss.

## Handoff → next session (NOT started here)
**NEO_SYSTEM / token-efficiency / v2 backlog**, e.g.:
- Full JSON-Schema validation (replace required-field-only checks).
- Stronger secret detection (beyond heuristic shapes).
- DB / object-storage / external-account residue surfaces (guarded today; P7 attestation already in place).
- Token-efficiency pass on the role prompts / scripts; possible `NEO_SYSTEM` meta-skill to orchestrate
  the roles end-to-end with minimal director overhead.
- Optional manual provider-spend attestation (`source: manual_provider_console`) so `is_estimate` can be false.

---

# NEO v1.1 — Entry Layer + Token Efficiency (2026-06-09)

> **Additive to the FROZEN v1 baseline above.** v1.1 changed only skills + docs and added ONE new
> script (`lint_skills.ps1`). The 8 v1 scripts and 4 schemas remain **FROZEN / byte-identical**.

## What v1.1 added (entry layer + shared doctrine)
- **`NEO_SYSTEM`** (`.claude/skills/NEO_SYSTEM/SKILL.md`, 86 lines) — the entry **router**: load it
  first and only it; it routes to exactly ONE role per phase. Encodes the one-role-at-a-time rule,
  the do-not-load-all-skills rule, the authority statement ("scripts and artifacts are authority, not
  agent confidence"), when-to / when-not-to-use NEO, and a PARKED future-upgrades list. It is a
  router, not a role: it embeds no role bodies and no doctrine.
- **`NEO_DOCTRINE.md`** (`.neo/NEO_DOCTRINE.md`) — the single home for shared principles
  **D1–D10**: authority>confidence · two human gates · roles recommend/human decides · Ambassador
  sole human surface · summarize-never-sanitize · isolation + hard external boundary · secret safety ·
  stop-don't-expand · resumability + honesty · ASCII-only `.ps1`. (`DEFINITIONS.md` stays the encoded
  audit machinery; `NEO_DOCTRINE.md` is the principles.)
- **`lint_skills.ps1`** (`.neo/scripts/`, ASCII-only) — entry-layer lints E/F/G + ASCII check.
- **8 role skills trimmed** — each now carries a one-line doctrine pointer and its `description`
  trigger + role-specific Owns/Must-not/Tools/Hard-line are preserved; duplicated doctrine removed.

## Phase -> role routing map (in NEO_SYSTEM; lint-verified, each role exactly once)
START/Planning scope -> NEO_PM ; START human gate -> NEO_AMBASSADOR ; Dispatch -> NEO_ORCHESTRATOR ;
Implementation -> NEO_CODER ; Verification -> NEO_VERIFIER ; Audit -> NEO_AUDITOR ;
Resume/Budget -> NEO_GOVERNOR ; Graduation only -> NEO_CONTRACT_CHECK.

## Verification (A-H, all green)
- **A no-loss doctrine:** every removed role sentence maps to a D1-D10 home (mapping table in the
  closeout doc); doctrine is a superset, nothing lost.
- **B trigger preservation:** all 8 role `description` frontmatter blocks **sha256 byte-identical**
  pre/post (edited body only).
- **C scripts/schemas frozen:** sha256 of all 8 `.ps1` + 4 `.json` unchanged pre/post.
- **D regression (reconstructed, option a):** GREEN E2E -> `verify_session -Mode EndGate` **exit 0**
  (all C-checks pass) + `ambassador_check` PASS + `governor resume-check` exit 0; COMPOSED NEGATIVE
  (HIGH auditor finding hidden under Status=GO) -> **C12 FAIL -> EndGate exit 1**, every other check
  green. Net behavior identical to v1. (Fixtures were ephemeral; `NEO_SESSION/` + `modules/` restored
  to empty.)
- **E/F/G + ASCII (lint_skills.ps1):** routing map all-8-once/resolve PASS; NEO_SYSTEM < 250 lines &
  no embedded bodies/doctrine PASS; no doctrine headings in role bodies PASS; new `.ps1` ASCII PASS.
- **H token efficiency:** v1.1 does **NOT** reduce total raw skill-file bytes - the raw 8-role total
  changed 34,884 -> 35,811 bytes (+927), the honest overhead of the per-role pointer + Dx refs. The
  correct claim is **structural** token efficiency: because NEO_SYSTEM routes ONE role at a time and
  avoids loading all role skills, normal per-phase load is NEO_SYSTEM (5,665) + doctrine (3,978) + ONE
  role (~4,476) = ~14,119 B vs the old all-8 footprint 34,884 B = **~59% less active context.**

## Still FROZEN / locked (unchanged from v1)
T1 sandbox · Claude API + provider spend cap · Governor honesty split · P7 human-attested accounts ·
no secret values · **ASCII-only `.ps1`** · 8 scripts + 4 schemas byte-identical. v1.1 is entry-layer +
docs + token-efficiency only; no script/schema/audit-net logic changed.

Closeout doc: `NEO_V1.1_CLOSEOUT_2026-06-09.md` (retained in the origin operator's off-tree audit archive; not shipped).

---

# NEO v2.0 — App-Development Governance CORE (2026-06-09)

> **Additive to the FROZEN v1 / accepted v1.1 baselines above.** v2.0 adds ONLY the app-development
> governance *foundation* — it is **NOT** the manager expansion. The 8 v1 scripts + 4 schemas + 8 role
> skills remain **FROZEN / SHA-256 byte-identical** (now machine-verified by `lint_skills.ps1` Check H).
> No git op, no package install, no provider/DB/secret/prod work. Sandbox-session tier stayed **T1**.

## What v2.0 added (governance core only)
- **`.neo/NEO_APP.md`** — a persistent per-project **app-memory TEMPLATE** (placeholders, not a filled
  app, **not a role**): product purpose, architecture, stack, repo layout, environments, current
  baseline, locked invariants, known risks, test/build commands, deployment + rollback notes, backlog.
- **`.neo/NEO_RISK_TIERS.md`** — **RT1-RT4** app-risk tiers (examples + gate each) + a tier->required-
  artifact matrix. RT1 reversible docs/local (no artifacts) · RT2 low-risk app code (NEO_APP read) ·
  RT3 runtime/business-sensitive (NEO_APP + tiers + release discipline) · RT4 prod/destructive/security/
  payment (explicit human approval; backup+rollback first; exact-command review; closeout audit).
  **RT1-RT4 (app risk) is deliberately DISTINCT from the sandbox-session `T1`** in `DEFINITIONS.md`.
- **`.neo/NEO_RELEASE_DISCIPLINE.md`** — release/rollback/backup checklist (last-known-good, changed
  surface, backup, rollback plan, irreversible-risk statement, environment-identity check, smoke proof,
  cleanup, no-prod-mutation-without-approval) **including DEP-GUARD**: any dependency/package/lockfile
  change is RT3 by default / RT4 if it touches auth·payment·database·crypto·email·deployment·build·prod
  runtime; evidence + explicit approval required BEFORE any install or lockfile mutation. Named
  **DEP-GUARD**, never `C11` (C11 stays "Checkpoint valid").
- **`NEO_SYSTEM` tier-aware routing** (86 -> **107 lines**, budget tightened **250 -> 160**) — adds ONE
  compact tier->lazy-load matrix and references the 3 artifacts; **embeds no artifact bodies** (RT1 doc
  sessions pull none). Still the only entry router; one role at a time; do-not-load-all preserved.
- **`lint_skills.ps1` Check H** (additive; ASCII) — 3 artifacts exist + carry anchors; NEO_SYSTEM
  references the artifacts + RT1..RT4 and embeds no ANCHOR body; no forbidden manager skill folders;
  no malformed `S:\NEO` paths; DEP-GUARD present; **frozen-core integrity** (8 scripts + 4 schemas + 8
  role skills SHA-256 unchanged, hashes embedded). Budget default lowered to 160.
- **`.neo/scripts/regression_smoke.ps1`** (NEW, v2.0 helper, ASCII, **NOT** a frozen v1 script) — fixes
  v1.1's missing replayable fixture: reconstructs GREEN E2E (`verify_session -Mode EndGate` exit 0) and
  the COMPOSED NEGATIVE (a GO end-summary hiding a HIGH auditor finding -> **C12 FAIL -> EndGate exit
  1**) on demand, cleaning `NEO_SESSION/` after. It only REPLAYS the frozen net; it never substitutes.

## Verification (A-G, all green)
- **A scope:** only the allowed files changed (3 created + NEO_SYSTEM/lint/baseline edited + 1 new
  helper script); nothing outside `S:\NEO`; no secrets; no git op.
- **B frozen core:** 8 v1 `.ps1` + 4 schemas + 8 role skills **SHA-256 unchanged** (verified twice:
  director-captured baseline + `lint_skills.ps1` Check H/H6). `lint_skills.ps1` changed (it is v1.1/v2
  governance lint, not one of the frozen 8).
- **C NEO_SYSTEM sanity:** 107 lines (< 160); no embedded artifact bodies (no ANCHOR tokens); still
  states one-role-at-a-time + do-not-load-all.
- **D artifact sanity:** NEO_APP is a template (not a role); RT1-RT4 routeable via the matrix; release
  discipline has rollback/backup/environment/smoke/cleanup; DEP-GUARD present.
- **E lint:** `lint_skills.ps1` exit 0 (E/F/G/H + ASCII all PASS); new helper ASCII-clean.
- **F regression (replayable):** `regression_smoke.ps1` exit 0 — GREEN EndGate exit 0 / 0 FAIL; COMPOSED
  NEGATIVE EndGate exit 1 with **C12=FAIL and zero non-C12 FAILs** (canonical case); fixtures removed,
  `NEO_SESSION/` restored. Net behavior identical to v1/v1.1.
- **G docs:** this section documents v2.0 as **governance-core ONLY**; managers parked/future-gated.

## Still FROZEN / locked (unchanged)
T1 sandbox · Claude API + provider spend cap · Governor honesty split · P7 human-attested accounts ·
no secret values · **ASCII-only `.ps1`** · 8 v1 scripts + 4 schemas + 8 role skills byte-identical.

## PARKED (NOT built; explicit approval required to start)
The manager expansion: **NEO_PRODUCT_SPEC / NEO_QA_SCENARIO / NEO_ENV_MANAGER / NEO_MIGRATION_MANAGER /
NEO_RELEASE_MANAGER** (lint Check H fails if any folder appears). Also still parked from v1.1: full
JSON-Schema validation, stronger secret detection, DB/object-storage/external-account residue surfaces.
RT3/RT4 sessions apply manager-equivalent discipline INLINE until the managers are approved and built.

---

# NEO v2.5 - Hardened Manager Foundation (ACCEPTED pending Raphael GO, 2026-06-10)

Combined-but-GATED session (B validation -> gate -> C dummy-app simulation -> gate -> explicit
Raphael GO -> D manager expansion -> final gate). ChatGPT auditor: GO-with-changes at START (all 7
items folded in + implemented), GO at the B+C gate, conditions preserved through D.

## Phase B - validation hardening
- **THE one justified frozen-core edit:** `verify_session.ps1` C1 hardened IN-PLACE to full recursive
  JSON-Schema validation (enum + type incl. unions + range minimum/minLength/minItems + nested
  required at every depth + unknown-key rejection per additionalProperties:false), pure PS 5.1, no
  installs. SHA re-pinned in lint H6: pre-edit 96F7CD4DC96EA5CFB2C07BEA3B8915974AF327A13E157AD538A9
  B60D487CF380 -> post-edit 29ABE03446B0BCE3A44D13E5E657499FE35933B44D509E3C7D43AA90D14BAC80 (old
  SHA recorded in an adjacent manifest comment). ASCII: 6 -> 6 non-ASCII bytes (zero new). All other
  19 frozen files SHA-unchanged.
- **Golden C1 matrix: 10/10 exact** (valid minimal PASS / valid full PASS / 8 invalids FAIL AS C1
  with zero non-C1 FAILs). Isolation proven 3 ways: invalids fail as C1; composed negative still
  fails AS C12 only; new routing negative fails AS C8 only with C1=PASS asserted.
- **`regression_smoke.ps1` hardened:** green leg now ASSERTS C1 is in v2.5 full-validation mode
  (anti-un-hardening guard); third leg added (routing-policy violation with honest NO-GO summary ->
  C8 FAIL only). 3 legs, exit 0.
- **Templates:** `.neo/templates/start_packet.template.md` + `closeout_packet.template.md` (human
  gate packets; closeout REQUIRES editable-artifact diff reporting). Gated by new lint Check I.

## Phase C - dummy-app simulation
- **`.neo/examples/DUMMY_APP.md`** - fictional "LemonLedger", a filled NEO_APP-template fixture
  (never routed, never a real project).
- **`.neo/scripts/scenario_sim.ps1`** (NEW helper, ASCII) - 7 scenarios, all green: RT1 ALLOWED with
  zero app artifacts; RT2 ALLOWED app-memory-only; RT2 dep-disguise BLOCKED (DEP-GUARD escalation);
  RT3 dep without approval BLOCKED (fail-closed, install-before-approval named); RT3 full 8-item
  pack ALLOWED; RT4 unverified rollback BLOCKED; RT4 full pack ALLOWED. DUMMY_APP byte-identical
  after run; fixtures auto-cleaned. Rule SSOT stays in the artifacts; the script only enforces.

## Phase D - manager expansion (after explicit Raphael GO)
- **5 managers built ONE AT A TIME, lint-green after each:** NEO_PRODUCT_SPEC / NEO_QA_SCENARIO /
  NEO_ENV_MANAGER / NEO_MIGRATION_MANAGER / NEO_RELEASE_MANAGER. All are GOVERNANCE/PLANNING ONLY
  (no app code, no provider/DB/secret/install/network/git/prod), each carries Scope / Trigger /
  Allowed / Forbidden / Handoff+checkpoint / Negative test (fail-closed), references SSOT artifacts
  and restates none.
- **lint H4 converted: block -> STRUCTURAL allowlist** (Raphael-approved): H4a unknown-skill guard
  (any non-role/non-system/non-approved folder FAILs); H4b per-manager structural checks (required
  sections + mandatory ban topics + per-manager negative-scenario coverage + required SSOT
  references + SSOT/doctrine-duplication ban + governance declaration); H4c NEO_SYSTEM manager-
  routing anti-monolith (5 '=>' arrows exactly once each, targets must exist on disk, no load-all,
  no embedded manager bodies, 'AT MOST ONE manager' rule required, >140-line target reported).
- **NEO_SYSTEM: 107 -> 120 lines** (<=140 target, <160 budget) - ONE compact manager-routing table
  ('=>' arrows, distinct from the role '->' arrows), lazy one-at-a-time, pointers only; PARKED list
  updated (full schema validation + managers now done; secret detection, residue surfaces, spend
  attestation still parked).
- **Fail-closed PROBES (all confirmed):** unknown folder NEO_BOGUS -> lint exit 1; routed manager
  SKILL.md removed -> lint exit 1; manager Negative-test section stripped -> lint exit 1. All
  restores byte-verified.

## Final gate (all green)
lint_skills exit 0 (E/F/G/ASCII/H1-H6/H4a-c/I) - regression_smoke exit 0 (3 legs) - scenario_sim
exit 0 (7 scenarios) - frozen core 20/20 SHA per v2.5 manifest (only verify_session re-pinned) -
editable artifacts NEO_APP/NEO_RISK_TIERS/NEO_RELEASE_DISCIPLINE UNCHANGED (SHA-verified vs session
start) - NEO_SESSION + modules EMPTY - no app code, no boundary touched.

## Still FROZEN / locked (v2.5)
T1 sandbox - Claude API + provider spend cap - Governor honesty split - P7 attested accounts - no
secret values - ASCII-only .ps1 - 7 v1 scripts + 4 schemas + 8 role skills byte-identical;
verify_session.ps1 frozen at its NEW v2.5 SHA (29ABE034...AC80). Managers + NEO_SYSTEM + lint +
regression_smoke + scenario_sim + templates are v2.5-governed (lint-checked, not SHA-frozen).

## PARKED (still not built)
Stronger secret detection - DB/object-storage/external-account residue surfaces - provider-spend
attestation.

## v2.5 closeout addendum (Raphael accept, 2026-06-10)
v2.5 ACCEPTED as the new NEO baseline. At acceptance Raphael ordered the golden C1 matrix made
PERMANENT: it now lives at `.neo/scripts/c1_golden_matrix.ps1` (10/10 green from its permanent
home; ASCII-clean; presence gated by lint Check I). The `_v2.5_rollback/` session scratch was
removed at closeout after the post-promotion full gate re-ran green.
