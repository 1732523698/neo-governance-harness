# CLOSEOUT PACKET - <session_id>

The human-facing END gate packet (v2.5). Filled in by the director AFTER the final gate runs
and BEFORE Raphael's accept/reject decision. Summarize, never sanitize: every FAIL, WARN and
high-severity finding from the net MUST appear here, even on a NO-GO.

## 1. Verdict
- Director recommendation: <GO / NO-GO> (Raphael decides)
- One-line proof sentence: <scope verified, changes made or none, no boundary touched>

## 2. What changed
- Files created: <list>
- Files edited: <list with one-line reason each>
- Frozen-core edits: <none / file: pre-edit SHA -> post-edit SHA + re-pin location>
- Editable v2.0 artifacts (NEO_APP.md / NEO_RISK_TIERS.md / NEO_RELEASE_DISCIPLINE.md):
  <unchanged / changed: summarize diff> (required every closeout)

## 3. Verification net evidence (paste real output, not paraphrase)
- lint_skills.ps1: exit <0/1> - <summary line>
- regression_smoke.ps1: exit <0/1> - <summary line>
- Other scripted proof (scenario_sim, golden matrices, negative tests): <results>
- Anything that FAILED or was skipped: <list honestly / none>

## 4. Residue and cleanup
- NEO_SESSION fixtures: <removed / kept + why>
- Declared scratch (e.g. rollback snapshots): <removed at closeout / retained + why>
- Residual diff vs session start: <clean / list>

## 5. Boundary confirmation
- No secrets written/echoed/logged: <confirmed>
- No path outside S:\NEO touched (except explicitly authorized closeout copies): <confirmed>
- No git / provider / DB / install / network / real-app operations: <confirmed>

## 6. Honesty section
- Known limitations / unverified claims: <list>
- Deferred items (described, NOT started): <list>

## 7. Auditor + human gate
- Paste-ready ChatGPT CLOSEOUT block: <attached below / location>
- Raphael decision: <accept as new baseline / iterate / toss> at <timestamp>
