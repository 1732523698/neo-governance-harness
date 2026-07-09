# NEO Release / Rollback / Backup Discipline

> v2.0 governance-core artifact. **Single source of truth for release, rollback, backup, and the
> dependency/package guard (DEP-GUARD).** NEO_SYSTEM references this file; it never restates the body.
> Lazy-load: pull this file only for RT3 and RT4 work (see `NEO_RISK_TIERS.md`).

<!-- ANCHOR:RELEASE-CORE -->
## Release core - the checklist every RT3/RT4 change satisfies BEFORE it ships

1. **Last-known-good identified.** Record the exact baseline (commit SHA / tag / snapshot) the change
   departs from and could roll back to.
2. **Changed surface stated.** Exactly which files/objects/config/data the change touches, and why.
3. **Backup requirement.** A restorable backup of anything the change could damage exists and is
   verified BEFORE the change runs. Secret-safe exclusions apply (never back up secret values).
4. **Rollback plan.** The exact command(s) / steps to return to last-known-good, written down and
   reviewed before edit - not improvised after a failure.
5. **Irreversible-risk statement.** Name anything that CANNOT be cleanly undone (data mutation, prod
   deploy, external send). If present, the work is RT4 and needs explicit human approval.
6. **Environment-identity check.** Prove which environment you are about to act on (sandbox vs staging
   vs prod). A wrong-environment action is treated as a breach. Never infer environment from a name.
7. **Smoke proof.** After the change, independent evidence it works (route smoke, DOM/text snapshot,
   API response, rendered output) - not the implementer's self-report.
8. **Cleanup.** Remove scratch artifacts; confirm zero unapproved residue.
9. **No prod mutation without explicit approval.** Production data/config/deploy is RT4: human approval
   every time, backup+rollback first, exact-command review.

---

<!-- ANCHOR:DEP-GUARD -->
## DEP-GUARD - dependency / package / lockfile guard

**Any** package, dependency, or lockfile change (add / remove / upgrade / downgrade / lockfile regen)
is governed:

- **Default tier: RT3.**
- **RT4** if the dependency touches any of: auth, payment, database, crypto, email, deployment, build
  system, or production runtime.

**Evidence required BEFORE any install or lockfile mutation (the gate; no install precedes approval):**

1. Before/after `package.json` (or equivalent manifest) summary.
2. Before/after lockfile summary (what versions resolved/changed).
3. Why the dependency is needed (the problem it solves; why existing deps cannot).
4. Alternatives considered (including "do nothing" / vendoring / writing it ourselves).
5. Runtime-vs-dev classification (is it shipped to users, or build/test only?).
6. Install / build / test evidence on a throwaway branch or sandbox copy.
7. Rollback command (exact steps to remove it and restore the prior lockfile).
8. **Explicit human approval BEFORE the install or lockfile mutation runs.**

DEP-GUARD is a release-discipline rule, **not** an audit-net check id. It is named **DEP-GUARD** and is
deliberately distinct from `C11` (which is "Checkpoint valid" in `verify_session.ps1`). Do not call it
C11 or fold it into the C-series.
