# START PACKET - <session_id>

The human-facing START gate packet (v2.5). Filled in by the director and presented to Raphael
BEFORE any edit. Complements (does not replace) session_contract.json - the contract is the
machine-checkable spine; this packet is the human confirmation surface.

## 1. Re-grounded baseline (verified ON DISK, not from memory)
- lint_skills.ps1 exit code: <0/1>
- regression_smoke.ps1 exit code: <0/1>
- Frozen-core SHA status: <unchanged / list mismatches>
- NEO_SESSION / modules residue: <clean / list>

## 2. Session intent
- Session id: <session_id>
- Goal (one sentence): <goal>
- Session tier: T1 (sandbox; fixed)
- App risk tier if app work is in scope: <RT1|RT2|RT3|RT4|n/a> (per .neo\NEO_RISK_TIERS.md)

## 3. Scope
- Approved paths (edit surface): <globs>
- Protected / never-touch paths: <globs>
- Frozen-core edits planned: <none / file + justification + pre-edit SHA>

## 4. Locked decisions being implemented
- <decision 1>
- <decision 2>

## 5. Gates and stop conditions
- Phase gates: <list each gate and its full-green condition>
- Stop conditions: <scope_breach / budget_breach / ambiguity / external_boundary + session-specific>
- Hard boundaries: stay in S:\NEO; no git, no provider, no DB, no secrets, no installs,
  no network, no real app code.

## 6. Auditor
- ChatGPT START verdict: <GO / GO-with-changes / NO-GO + folded-in items>

## 7. Human gate
- STOPPED for Raphael's GO: <yes>
- GO received at: <timestamp / quote>
