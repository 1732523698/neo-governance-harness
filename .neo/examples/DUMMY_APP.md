# DUMMY_APP - "LemonLedger" (FAKE app for governance simulation ONLY)

> v2.5 example artifact. This is a FILLED COPY of the `.neo\NEO_APP.md` template for a FICTIONAL
> app. It exists so `scenario_sim.ps1` can exercise the RT1-RT4 governance flows against realistic
> app memory WITHOUT any real project, real code, real environment, or real data. Nothing in this
> file is real. It must never be routed to as a role and never used to onboard a real project.

## Product purpose
LemonLedger is a fictional lemonade-stand bookkeeping app for a fictional owner ("Pat"). It tracks
fake daily sales, fake inventory (lemons, sugar, cups), and produces a fake weekly summary.

## Architecture
Fictional two-part app: a static frontend (display of daily totals) and a tiny backend (CSV-file
store, summary calculator). They communicate over a fictional local HTTP port. No real services.

## Tech stack
Fictional: plain HTML/JS frontend; a single-file backend ("ledger.js") on a fictional Node-like
runtime; CSV files as storage. Versions are irrelevant - nothing is ever installed or run.

## Repo layout
Fictional repo root `modules/lemonledger/`:
- `frontend/` - index page + display script (fake)
- `backend/ledger.js` - fake summary logic, marked as the financial surface
- `data/*.csv` - fake runtime data
- `package.json` / `lock.json` - fictional manifest + lockfile (DEP-GUARD simulation targets)

## Environments
- `local` - the only "real" tier in simulation; everything reversible.
- `staging-sim` - pretend staging; identified by marker file `ENV_STAGING_SIM`.
- `prod-sim` - pretend production; identified by marker file `ENV_PROD_SIM`. Any scenario touching
  `prod-sim` is RT4 by definition. Environment identity is proven by the marker file, never by name.

## Current baseline
Fictional last-known-good: tag `lemonledger-v0.3` dated 2026-06-01. (Fake; used by rollback drills.)

## Locked invariants
- `backend/ledger.js` summary math is the FINANCIAL surface: byte-exact unless explicitly approved
  (simulated RT3+).
- `data/*.csv` is runtime data: any write outside an approved scenario is a breach.
- The weekly-summary output format is a public contract (fictional consumers parse it).

## Known risks
- Fictional past incident: a dependency bump of "csv-parser-sim" broke summary rounding (this is the
  canned DEP-GUARD story scenario_sim replays).
- `data/` is easy to touch accidentally from backend edits - scenarios must scope-check it.

## Test / build commands
Fictional only - NEVER actually run: `sim-build`, `sim-typecheck`, `sim-test`. scenario_sim treats
these as strings to assert against, not commands to execute.

## Deployment notes
Fictional deploy = copying `frontend/` + `backend/` into the env folder carrying the right marker
file. RT4 approval, backup, rollback, and exact-command review are required for `prod-sim`.

## Rollback notes
Fictional rollback = restore `lemonledger-v0.3` snapshot folder over the env folder, then re-run
`sim-test`. The rollback is VERIFIED in simulation by the presence of a rollback-drill artifact,
never assumed.

## Open decisions / backlog
None - this file is a static fixture. If scenario_sim needs new story beats, extend the scenarios,
not this baseline (keep the fixture stable so simulations stay replayable).
