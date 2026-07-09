# NEO_APP - Persistent App-Memory TEMPLATE

> v2.0 governance-core artifact. **This is a TEMPLATE, not an active role skill and not a filled app.**
> It defines the persistent per-project app memory a NEO app-development session reads/writes so context
> survives across sessions. Copy it per real project (e.g. into that project's NEO workspace) and fill
> the placeholders. NEO_SYSTEM references this file by name; it never embeds the body.
> It is NOT routed to as a role - NEO_SYSTEM stays the only entry router.

<!-- ANCHOR:APP-TEMPLATE -->
## How to use
- One filled copy per app/project. Keep it the single durable home for "what is this app and what must
  not break." Update it at every session closeout that changes any of these facts.
- Tier the work via `NEO_RISK_TIERS.md`; follow `NEO_RELEASE_DISCIPLINE.md` for RT3/RT4.
- Secret VALUES never go in here - key names only.

---

## Product purpose
_(One paragraph: what the app does and for whom. The problem it solves.)_

## Architecture
_(Major components and how they talk; runtime topology; key data flows.)_

## Tech stack
_(Languages, frameworks, libraries, services, versions that matter.)_

## Repo layout
_(Top-level folders and what lives where; where the entry points are.)_

## Environments
_(local / sandbox / staging / production: how each is identified, how NOT to confuse them.)_

## Current baseline
_(The last-known-good: commit SHA / tag / deploy + date. Updated each closeout.)_

## Locked invariants
_(Things that MUST NOT change without explicit approval: financial rules, schemas, public contracts,
auth model, byte-exact rendering, etc. Cross-link the rule's source of truth.)_

## Known risks
_(Fragile areas, past incidents, sharp edges, intentional residue, anything to handle with care.)_

## Test / build commands
_(Exact commands: install, build, typecheck, unit/integration tests, lint. These feed the session
contract `test_plan` and the verifier.)_

## Deployment notes
_(How a release ships; who approves; environment-identity checks; smoke steps.)_

## Rollback notes
_(How to return to last-known-good for this app specifically; what is irreversible.)_

## Open decisions / backlog
_(Pending decisions, deferred work, next-session handoffs. Convert relative dates to absolute.)_
