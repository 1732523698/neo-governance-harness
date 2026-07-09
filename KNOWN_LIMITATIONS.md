# NEO - Known limitations of this public cut

This public release is a DERIVED subset of a private NEO working tree. Internal session history and
the operator's reference application were intentionally excluded (see `PROVENANCE.md`). A few
consequences follow honestly from that:

## App-governance self-test suites: a SANITIZED example profile is bundled
Three DEV-facing self-test suites exercise NEO's app-governance checks against a governed app, so they
need an app profile at `modules\<app_slug>\NEO_APP_PROFILE.json` (+ `.md`):
`app_adapter_fixture_suite.ps1`, `custody_fixture_suite.ps1`, and the F5 tier cases of
`role_governance_fixture_suite.ps1`.

This cut ships a **SANITIZED example profile** at
`modules\unified-analytics-rental-platform\NEO_APP_PROFILE.json` (+ `.md`) so all three suites PASS
out-of-box. Only the governance RULES the tests need are retained (denylist patterns, residue/risk
tokens, scoped forbidden imports, i18n/charset/migration/dependency rules, custom checks); the origin
app's development history, git/PR state, environment identities, and deployment notes were stripped.
It is an EXAMPLE, not a real app profile - see `.neo\NEO_APP.md` and the schema at
`.neo\schema\NEO_APP_PROFILE.schema.json` to author one for your own application. No app CODE, data,
or session history is bundled - only the profile. The recipient-facing `verify_neo.ps1` passes
regardless.

## The notify hook ships but is not wired by default
`.neo\scripts\notify\notify_hook.ps1` (+ `set_session_name.ps1` and its 240/240 fixture suite) ships
with the double-fire-suppression and stop-text-classifier fixes, but the installer does NOT register a
Notification hook - gate mails are sent explicitly by the manager. To auto-send on harness friction
events, add a Notification hook pointing at that script (and configure email per the next section).

## Gate-notification email is unconfigured by default
Recipient/sender are config-resolved (env `NEO_NOTIFY_RECIPIENT`/`NEO_NOTIFY_SENDER` or
`%USERPROFILE%\.neo_notify\config.json`) and the shipped DEF-P8 attestation is an UNAPPROVED
template, so live sends fail-closed until YOU configure them (see `INSTALL.md` step 8). Test mode
composes to disk with zero network at all times.

## Documentation speaks from the origin machine's layout
Doctrine and skill docs describe a reference layout using `S:\NEO` as the canonical root and refer to
a persona ("Raphael") as the human controller. These are intentional reference/branding, not live
machine paths - adapt them to your own environment. Machine-private identifiers (the operator's dev
tree path, username, email, and home paths) have been removed/parameterized.
