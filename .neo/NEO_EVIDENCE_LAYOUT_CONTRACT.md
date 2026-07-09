# NEO EVIDENCE-LAYOUT CONTRACT (A-BRIDGE)

> Governing, host-independent, forward-compatible directory contract for NEO's evidence
> artifacts. Authored in Phase A (A-BRIDGE), BEFORE PORT-S2, so the dev->export producer targets
> the right in-tree home for every evidence category. Governing plan: roadmap v4
> (SHA 4432E2B9C97FBDC432F43D6EC86F3E06BB20BB6433CF9CC2BA0D560C063A2A27), lines 39-41 + sections
> 5.5 / 5.6. **This contract fixes HOMES (locations) only. Full field-level JSON schemas are
> DEFERRED to 4.0 Session-0** (see section 7). Additive doctrine document; RT1.

## 0. Status and authority
- **Type:** governing doctrine contract (peer of `NEO_DOCTRINE.md`, `NEO_RELEASE_DISCIPLINE.md`).
- **In-tree home of this contract:** `./.neo/NEO_EVIDENCE_LAYOUT_CONTRACT.md`.
- **Machine-readable companion:** `./.neo/evidence_layout_manifest.json` (a small, versioned, open
  list of the same canonical relative paths, for the PORT-S2 producer to consume).
- **Scope:** defines the canonical, NEO-root-RELATIVE in-tree home for every evidence category.
  It does NOT author field schemas, does NOT move any file, and does NOT populate any reserved
  home. It gives PORT-S2 an unambiguous export target.
- **Pinning:** because this contract lives under `./.neo/`, it is pinned/attested at ship. That
  is the correct behavior for a governing contract and is recorded as expected push-gate debt.

## 1. Host-independence rules (NON-NEGOTIABLE)
1. **Root-relative only.** Every path in this contract and its manifest is expressed relative to
   the NEO root, written `./...`. There are ZERO absolute paths, ZERO drive letters, and no literal
   host store names anywhere in this document or the manifest.
2. **The PORT-S1 self-locating resolver is the SOLE root authority.** Every path resolves against
   the root that resolver returns (or an explicit `-NeoRoot` override passed to a trusted operator).
   No consumer of this contract may hardcode a host path.
3. **Off-tree / external concepts are named by ROLE, never by path.** Where this contract must
   refer to something outside the governed tree, it uses a role name ("the resolved NEO root", "the
   host backup store", "the out-of-band published root SHA") and never a filesystem location.
4. **The published root SHA is deliberately out-of-band.** It is an authenticity value published on
   a release channel (release page / signed checksum / tag), NOT a file in the governed tree. See
   section 5.

`./` in this document always denotes the PORT-S1-resolved NEO root.

## 2. Grounded current layout (the reality this contract formalizes)
- `./.neo/` — engine + governance. Contains doctrine `.md` (`DEFINITIONS.md`, `NEO_APP.md`,
  `NEO_DOCTRINE.md`, `NEO_RELEASE_DISCIPLINE.md`, `NEO_RISK_TIERS.md`, and now this contract),
  `./.neo/schema/` (the 12-schema spine), `./.neo/gates/` (live governance state),
  `./.neo/scripts/`, `./.neo/sessions/`, `./.neo/templates/`, `./.neo/examples/`, and version
  archives.
- `./NEO_SESSION/<slug>/` — per-subsession records. Established PORT-S1 shape: `snapshots/`,
  `changed_files/`, `diffs/`, `proof/`, `coder_report.json`. Also `./NEO_SESSION/_neo_roadmap/`
  (START packets + roadmap-for-audit docs).
- **Off-tree (host backup store, named by role):** roadmap masters + `.sha256` sidecars, the
  provisional-dev root-of-trust anchor, and restore-point archives. These are exactly the bits
  PORT-S2 must bring in-tree (or represent via an in-tree manifest) plus an external published root
  SHA. This contract RESERVES their in-tree homes; it does not move them.

## 3. Canonical evidence homes (category -> canonical root-relative path)

| # | Category | Canonical in-tree home (root-relative) | Disposition |
|---|----------|----------------------------------------|-------------|
| 1 | Program / project docs (roadmap master, spec, program memory) | `./program/` | RESERVED (named; empty; no move now) |
| 2 | Per-subsession records | `./NEO_SESSION/<slug>/` with `snapshots/`, `changed_files/`, `diffs/`, `proof/`, `coder_report.json` | FORMALIZED (existing shape = contract) |
| 3 | Audit bundles (isolated-auditor evidence) | `./NEO_SESSION/<slug>/audit/` (sibling to `proof/`) | NEW home name (per subsession) |
| 4 | Release / authenticity — in-tree anchor + manifest | `./.neo/release/ROOT_OF_TRUST_ANCHOR.json`, `./.neo/release/RELEASE_MANIFEST.json` | RESERVED (PORT-S2 populates by RE-CUT) |
| 4 | Release / authenticity — external published root SHA | OUT-OF-BAND release channel (role, not a path) | External anchor (never in-tree) |
| 5 | Live governance state | `./.neo/gates/` (`HUMAN_GATE_LEDGER.json`, `OWNERSHIP_LEASE.json`), `./.neo/schema/` (12-schema spine) | REFERENCED as canonical; NOT moved |
| 6 | Forward-compat section-5.5 map | see section 6 | RESERVED homes (locations only) |

### 3.1 Category 1 — Program / project docs (`./program/`)
`./program/` is the canonical home for program-scope evidence and program memory: the roadmap
master, the 4.0 program spec, and the program-level structured evidence files of section 6. It is
deliberately distinct from `./NEO_SESSION/` (per-subsession) and from `./.neo/` (engine). This
contract RESERVES the name only. The authoritative roadmap masters remain a release-time / host
backup concern until 4.0 Session-0 populates `./program/`; no file is moved by this contract.

### 3.2 Category 2 — Per-subsession records (`./NEO_SESSION/<slug>/`)
The established PORT-S1 shape is adopted verbatim AS the contract:
```
./NEO_SESSION/<slug>/
  snapshots/            # pre-change snapshots (rollback boundary, section 5.6)
  changed_files/        # post-change file copies
  diffs/                # unified diffs
  proof/                # builder proof (tests/checks the builder ran)
  coder_report.json     # structured builder report
  audit/                # isolated-auditor evidence (category 3)
```
`<slug>` is a per-subsession identifier (existing convention, e.g. `port-s1-self-locating-root-2026-07-02`).
The 4.0 per-subsession folder is this same folder; its added files get homes here without changing
the shape.

### 3.3 Category 3 — Audit bundles (`./NEO_SESSION/<slug>/audit/`)
Isolated-auditor evidence lives in `./NEO_SESSION/<slug>/audit/`, a SIBLING to `proof/`. The
separation is deliberate: `proof/` = the builder's own proof; `audit/` = the independent,
fresh-context isolated auditor's evidence (section 5.2 audit tiers). Keeping them separate keeps
builder self-report and independent audit from co-mingling.

### 3.4 Category 4 — Release / authenticity
Two artifacts with two different jobs:
- **In-tree** `./.neo/release/ROOT_OF_TRUST_ANCHOR.json` and `./.neo/release/RELEASE_MANIFEST.json`.
- **Out-of-band** published root SHA on a release channel (named by role, never in-tree).

See section 5 for the authenticity relationship. This contract RESERVES `./.neo/release/`; PORT-S2
RE-CUTS the anchor and manifest fresh into that home (it does NOT copy the stale provisional-dev
anchor from the host backup store).

### 3.5 Category 5 — Live governance state (referenced, NOT moved)
`./.neo/gates/` and `./.neo/schema/` already exist in-tree and are canonical:
- `./.neo/gates/HUMAN_GATE_LEDGER.json` — the human-gate authority (RT4-R1).
- `./.neo/gates/OWNERSHIP_LEASE.json` — live ownership lease state.
- `./.neo/schema/` — the 12-schema spine (schema-checking authority for structured evidence).
This contract REFERENCES these as canonical and does NOT move or edit them.

## 4. Reserved-home policy (what "RESERVED" means here)
A RESERVED home is a canonical path NAMED by this contract and its manifest. Naming a home does not
create evidence content and does not require the directory to exist yet. PORT-S2 (and 4.0 Session-0)
populate reserved homes; this contract authors none of their content. Empty placeholder directories
MAY be created if judged necessary, but no evidence content is authored by A-BRIDGE.

## 5. Release / authenticity relationship (v4 fix #1 / T1 fail-closed) — STATED PLAINLY
This section is a required honesty statement; PORT-S2 and Session-0 MUST NOT weaken it.
1. **The in-tree anchor / RELEASE_MANIFEST prove only "unchanged since packaging."** They establish
   internal consistency of the tree against itself. They do NOT, by themselves, establish
   authenticity.
2. **Authenticity rides the OUT-OF-BAND published root SHA.** The "authentic from Raphael" claim is
   anchored by the external published root SHA on a release channel, compared against the folder's
   computed root hash by the PORT-S3 verify entrypoint.
3. **Fail closed for others-install.** For an others-install release, verify MUST FAIL CLOSED when no
   published external root SHA is available — it must never pass on internal consistency alone
   (roadmap v4 fix #1 / T1).
4. **Tamper-evident is not tamper-proof.** An in-tree anchor with custody `provisional-dev` is a file
   the session principal can still write: tamper-EVIDENT, not tamper-PROOF. Genuine un-forgeability
   arrives only when Option A / S6 places the anchor under an admin-owned ACL outside the principal's
   write scope (custody `host-anchored`). Until then the DEV->PROD push gate is the backstop.
5. **PORT-S2 RE-CUTS, does not copy.** PORT-S2 regenerates the anchor and manifest fresh for the
   export scope into `./.neo/release/`; it does NOT relocate the stale provisional-dev dev anchor.
   Custody semantics (`provisional-dev` vs `host-anchored`) are preserved, not conflated with the
   mere fact of in-tree presence.

## 6. Forward-compatibility map — section-5.5 evidence files (LOCATIONS ONLY)
Every roadmap section-5.5 structured evidence file has a named home. Field-level schemas, file
extensions, provenance/timestamp fields, and record formats are DEFERRED to 4.0 Session-0.

| Section-5.5 artifact | Named home (root-relative) | Scope |
|----------------------|----------------------------|-------|
| PROJECT_SPEC | `./program/PROJECT_SPEC.*` | program |
| CONSTRAINT_PACKAGE | `./program/CONSTRAINT_PACKAGE.*` | program |
| ARCHITECTURE | `./program/ARCHITECTURE.*` | program |
| RISK_REGISTER | `./program/RISK_REGISTER.*` | program |
| SUBSESSION_INDEX | `./program/SUBSESSION_INDEX.*` | program (index of all subsessions) |
| per-subsession folders | `./NEO_SESSION/<slug>/` | per-subsession (section 3.2, incl. `audit/`) |
| MASTER_CHECKPOINT | `./program/MASTER_CHECKPOINT.*` | program (checkpoint schema already in the spine) |
| HANDOFF_PACKET | `./program/HANDOFF_PACKET.*` | program (master-rollover artifact, section 5.8) |

All 8 section-5.5 artifacts are covered. `.*` denotes an extension deferred to Session-0.

## 7. Deferred to 4.0 Session-0 (kept OUT to stay minimal)
This contract intentionally does NOT author any of the following; they are Session-0 work:
- Full field-level JSON schemas for every section-5.5 file.
- Provenance / timestamp field specifications.
- The SUBSESSION_INDEX record format.
- MASTER_CHECKPOINT and HANDOFF_PACKET contents.
- The audit-bundle internal schema.
- The RELEASE_MANIFEST field schema.
- The stale-packet / hash check for master rollover (section 5.8).
- File extensions for the section-6 artifacts.

## 8. Acceptance self-statement
This contract is: host-INDEPENDENT (zero absolute paths / drive letters / literal host-store names;
root-relative only; PORT-S1 resolver is the sole root authority); forward-COMPATIBLE (all 8
section-5.5 artifacts have a named home); MINIMAL (schemas explicitly deferred to Session-0);
CONSISTENT with the real `./.neo/` and `./NEO_SESSION/` layout; and gives PORT-S2 an UNAMBIGUOUS
export target, including the in-tree-anchor vs external-published-SHA relationship (section 5).
