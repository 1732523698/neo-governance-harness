# NEO public cut - PROVENANCE

This repository is a **derived PUBLIC subset** of the frozen NEO 4.9 milestone. It is not the frozen
original; it is a scrubbed, harness-only cut prepared for public distribution.

## Source (frozen, byte-verified)
- Derived from the frozen tree **NEO 4.9**, whose authoritative release root SHA-256 is:
  `68318693361955e1eecbd0b60b0cb136f6663e129af28c39878c4ada009db990`
  (from the frozen tree's `.neo\release\RELEASE_MANIFEST.json` and confirmed by `verify_neo.ps1`).
- The frozen source was treated as **READ-ONLY** during this derivation and re-verified byte-identical
  before and after (its root SHA above was unchanged across the whole process).
- Prepared by session `neo49-public-cut` (manual two-gate loop; codex plan audit converged GO;
  recorded human START approval; END keep/iterate/toss recorded in the origin's session records).

## What was EXCLUDED (intentionally absent - this is a subset, by design)
- All internal session/decision history: `NEO_SESSION\` records, `_sessions\`, `.neo\sessions\`,
  `.neo\_v2.6_rollback\`, `.neo\_v3.1\`, and most of `.neo\_v3.0\` (only 3 net-load-bearing archive
  JSONs retained).
- Dev snapshots/patches: any `snapshots\` / `diffs\` / `changed_files\` dirs, `*.snap`, stray
  `coder_report.json`.
- The origin operator's reference application code, data, and session history
  (`modules\unified-analytics-rental-platform\` app tree). EXCEPTION: a SANITIZED example
  `NEO_APP_PROFILE.json` (+ `.md`) is retained under that path so the app-governance self-test suites
  pass out-of-box - governance RULES only; the app's development history, git/PR state, environment
  identities, machine paths, and deployment notes were stripped (see `KNOWN_LIMITATIONS.md`).
- The frozen tree's `_release\` freeze artifacts and DEV `.neo\release\` anchor/manifest - replaced
  here by a FRESH public `.neo\release\RELEASE_MANIFEST.json` cut over the public bytes.
- The machine-local `.claude\settings.local.json` (personal permission allowlist).

## Scrub transforms applied (personal data removed / parameterized)
- **Email**: the notify module recipient/sender are now **config-resolved** (env
  `NEO_NOTIFY_RECIPIENT` / `NEO_NOTIFY_SENDER`, or `%USERPROFILE%\.neo_notify\config.json`, else a
  non-routable placeholder that fails-closed). No personal address remains.
- **Username / home paths**: removed (the only occurrences were inside the removed email; no
  `C:\Users\<name>` paths remain).
- **The operator's private dev working-tree path and a private off-tree audit-scratch path**:
  removed / genericized to `<NEO_ROOT>` (the specific machine literals are deliberately not
  reproduced in this file).
- **settings.json** ships as a portable template (`<NEO_ROOT>` placeholders); the setup script
  regenerates real paths on install. The `subsession_watchdog.ps1` notify path now self-locates.
- **Retained by design** (documented, not private): the reference root `S:\NEO` where it appears in
  doctrine narrative and protective guards, and the persona name **"Raphael"** as project branding.
  This cut is therefore **personal-data scrubbed with the persona intentionally retained** - it is
  NOT described as fully identity-anonymized.

## Deltas BEYOND frozen 4.9 (this cut is not a pure subset)
- **Notify hook added (post-4.9 fix):** frozen 4.9 shipped no `notify_hook.ps1`. This cut adds
  `.neo\scripts\notify\notify_hook.ps1`, `set_session_name.ps1`, and `notify_hook_fixture_suite.ps1`
  from the maintained DEV tree, carrying the double-fire-suppression + stop-text-classifier fixes
  that postdate 4.9 (and the recipient/sender parameterization). The hook **ships UNWIRED** (the
  installer registers no Notification hook by default; opt-in only). Its fixture suite passes
  240/240. Files were scrubbed of the private dev-tree path (genericized to `S:\NEO_dev` in the
  tree-label logic/tests); no PII.

## Integrity / authenticity
- `.neo\release\RELEASE_MANIFEST.json` lists every shipped file with its SHA-256 and a canonical
  `root_sha256` over the sorted `"<sha>  <path>"` lines (this manifest excluded). `verify_neo.ps1`
  (adapted to ignore the `.git\` working tree) re-verifies it end-to-end.
- Per NEO's design, the **published root SHA of THIS public cut rides out-of-band** (printed at
  generation / recorded in the packaging session), never quoted inside the tree as self-proof: an
  in-tree value can only prove "unchanged since packaging", never authenticity (tamper-EVIDENT, not
  tamper-PROOF). Obtain the public root SHA from the distributor's trusted channel and pass it to
  `verify_neo.ps1 -PublishedRootSha <sha>` on first run.
