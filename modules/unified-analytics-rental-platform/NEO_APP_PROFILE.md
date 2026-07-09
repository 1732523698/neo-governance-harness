# NEO_APP_PROFILE - example app (public cut: rules retained, history stripped)

> App profile. An app profile RECORDS constraints; it does NOT grant edit permission on the app.
> Real-app execution requires explicit human boundary sign-off per target app path.
> Machine-readable directives use `KEY: value` lines parsed by `verify_app_slice.ps1` /
> `check_app_end_evidence.ps1` - keep their format exact.
> NOTE (public cut): the origin app's development history, git state, PR/merge records, environment
> identities, and deployment notes were stripped. The governance RULES below are retained so the
> app-governance nets remain exercisable. The authoritative profile is the sibling `.json`.

## Identity
APP_SLUG: unified-analytics-rental-platform
APP_NAME: Unified Analytics Rental Platform
BOUNDARY_APPROVED: no
NOT_APPROVED_FOR: general future real-app execution
NOT_APPROVED_FOR: production apply/deploy without separate explicit approval

## Denylist (forbidden paths / locked files - byte-unchanged; entries with ** are globs)
DENY: backend/src/logic/payments.ts
DENY: backend/src/logic/pool.ts
DENY: backend/src/logic/charges.ts
DENY: backend/src/logic/future-charges.ts
DENY: backend/src/logic/status.ts
DENY: backend/src/logic/tenants-ledger-combined.ts
DENY: backend/src/routes/tenants-ledger-combined.ts
DENY: backend/src/logic/future-charges-review.ts
DENY: backend/src/logic/futureChargesAutoScheduler.ts
DENY: backend/src/logic/reports.ts
DENY: backend/src/routes/reports.ts
DENY: backend/src/logic/utility-v2-reports.ts
DENY: backend/src/routes/utility-v2-reports.ts
DENY: backend/src/logic/settlement.ts
DENY: backend/src/logic/paymentsAllocationSuggest.ts
DENY: backend/src/routes/payments.ts
DENY: backend/src/routes/charges.ts
DENY: backend/src/logic/dashboard.ts
DENY: backend/src/logic/dashboard-utility-v2.ts
DENY: backend/src/routes/dashboard.ts
DENY: backend/src/routes/dashboard-utility-v2.ts
DENY: frontend/src/app/dashboard/**
DENY: frontend/src/components/dashboard/**
DENY: frontend/src/hooks/useDashboard.ts
DENY: frontend/src/hooks/useDashboardTierB.ts
DENY: frontend/src/lib/guidance/dashboardAlerts.ts
DENY: frontend/src/i18n/dictionaries/en/dashboard.ts
DENY: frontend/src/i18n/dictionaries/fr/dashboard.ts
DENY: frontend/src/i18n/dictionaries/zh-CN/dashboard.ts

## Residue tokens (must not exist anywhere in the app tree at END)
TOKEN: V26X_
TOKEN: NEO_SCRATCH_
TOKEN: DO_NOT_SHIP

## i18n (per-namespace TypeScript dictionaries, one folder per locale)
I18N_STYLE: ts_namespace_dirs
I18N_DIR: frontend/src/i18n/dictionaries
I18N_LOCALES: en,fr,zh-CN
Parity rules (enforced by AS6): identical namespace-file sets across locales; identical flattened
nested key paths per namespace; missing keys FAIL; extra keys FAIL; parse failure fails CLOSED;
dynamic/computed keys FAIL unless `I18N_DYNAMIC_KEYS_ACCEPTED` is recorded in HUMAN_ACCEPTANCE.md.

## Charset
ASCII_GLOB: *.ps1
ASCII_GLOB: *.sql
Files matching these globs must be ASCII-only.

## Migrations
MIGRATIONS_DIR: database/migrations
Any new/edited file here, or DDL tokens in changed files, requires a written rollback proof in the
slice evidence (`ROLLBACK_PROOF.md`) plus staging-apply evidence where applicable.

## Dependencies (DEP-GUARD)
DEP_FILE: package.json
DEP_FILE: package-lock.json
Any change to these requires DEP-GUARD evidence (`DEP_GUARD.md` in the slice dir) approved BEFORE
install. See `.neo/NEO_RELEASE_DISCIPLINE.md`.

## Scoped forbidden imports (SCRIPT-ENFORCED - AS17 inspects actual import edges)
SCOPED_DENY_IMPORT: backend/src/logic/depositsHeld.ts => insertPaymentAndAllocate, confirmDuplicatePayment, createPaymentWithExplicitAllocation, applyAllocationMode, suggestAllocation, allocateOldestFirst, pool, charges, future-charges, paymentsAllocationSuggest, payments, index

The deposit branch (`depositsHeld.ts`) must never import/call payment-pool writers or the charge
pipeline. `index` is the conservative barrel blocker. The rule is SCOPED to the deposit branch only.

## Risk-token detectors (force stronger evidence; classifier may only UPGRADE risk)
AUTH_TOKEN: owner_user_id
AUTH_TOKEN: req.user
AUTH_TOKEN: auth.uid
AUTH_TOKEN: tenant_id
AUTH_TOKEN: organization_id
AUTH_TOKEN: service_role
AUTH_TOKEN: SECURITY DEFINER
AUTH_TOKEN: ROW LEVEL SECURITY
FIN_TOKEN: payment
FIN_TOKEN: charge
FIN_TOKEN: rent
FIN_TOKEN: deposit
FIN_TOKEN: ledger
FIN_TOKEN: balance
FIN_TOKEN: payout
FIN_TOKEN: allocation
FIN_TOKEN: settlement
FIN_TOKEN: refund
FIN_TOKEN: invoice
FIN_TOKEN: amount
FIN_TOKEN: cents

## Commands (exact; evidence must record cmd + cwd + exit_code + timestamp + output path)
CMD_TYPECHECK: npm run typecheck
CMD_BUILD: npm run build

## Custom checks (every one MUST appear in APP_END_EVIDENCE)
CUSTOM_CHECK: oldest_first_allocation_untouched
CUSTOM_CHECK: locked_dashboard_untouched
CUSTOM_CHECK: deposit_confirm_makes_zero_payment_pool_rows
CUSTOM_CHECK: deposits_held_only
CUSTOM_CHECK: new_tenant_first_transfer_held
CUSTOM_CHECK: outflow_exact_tenant_stays_ignored

## Client-side-logic verification rule
For client-side React state / money logic, require >= 1 of: reducer/function-extraction test,
component/unit test, Playwright/browser scenario. Manual browser proof is DEGRADED evidence for
money-affecting state and requires explicit human acceptance. Client-side display-only math is
still financial logic if the user may make a decision from it.

## Fast lane (RT1/RT2 cosmetic) - reduced EVIDENCE lane, not reduced AUTHORITY lane
Eligible only when the classifier proves frontend-UI-only buckets, no financial/auth/backend/
schema/dependency/locked surface. Still required: classifier output, denylist proof, typecheck or
targeted smoke, full APP_END_EVIDENCE, human gate.
