# START Reconciliation - plan assumptions vs environment reality (v2.6)

> Required at START for every app session (RT2+) BEFORE implementation. Env-identity proves
> WHICH environment you are in; it does NOT prove WHAT IS IN IT (the "2 owners vs 1 owner"
> miss). Every plan assumption touching schema / ownership / auth / financial logic /
> migration / routing must be reconciled against LIVE or STAGING evidence below. START packets
> must inline the real SQL/DDL (or real code excerpt), never a summary of it.

Session: <session_id>
App: <app_slug>  (profile: S:\NEO\modules\<app_slug>\NEO_APP_PROFILE.md)
Environment proven by: <marker/attestation command + output, e.g. staging:check-env>

## Assumption table (one row per plan assumption; ALL rows must be RECONCILED before coding)

| # | Plan assumption | Category (schema/ownership/auth/financial/migration/routing) | Reality evidence (command/query + literal output) | Verdict (CONFIRMED / CONTRADICTED / UNKNOWN) |
|---|---|---|---|---|
| 1 | <e.g. "houses have exactly 1 owner_user_id"> | ownership | <SELECT count(*) ... ; literal result inlined> | <CONFIRMED> |

Rules:
- UNKNOWN is not allowed to proceed: resolve to CONFIRMED or CONTRADICTED first.
- CONTRADICTED stops the plan: re-plan or route to the human gate before any edit.
- Reality evidence must be literal command output / SQL result, copied verbatim - never
  "checked, looks fine".
- Inline the REAL DDL: for any migration or schema-touching assumption, paste the actual
  CREATE/ALTER statements being relied on, not a prose description.

## Inlined SQL/DDL appendix (verbatim, required when any schema/migration row exists)

```sql
<paste the actual current DDL and the planned migration SQL here>
```

Reconciled by: <role>   Date: <date>   Human gate: <pending/approved>
