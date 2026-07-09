# DEF-P8 EMAIL NOTIFICATION CHANNEL ATTESTATION - TEMPLATE (NOT IN FORCE)

STATUS: DRAFT / NOT IN FORCE - this shipped template is intentionally UNAPPROVED. The notify
module's live-send path fail-closes (refuses) until the installing operator replaces this with
their OWN attestation stamped `STATUS: **APPROVED / IN FORCE`. Gate mails still compose in test
mode; no email can egress until this is in force AND a credential file exists AND a non-placeholder
recipient/sender is configured (see .neo\scripts\notify\notify_raphael.ps1).

This record is the authority the notify module checks before ANY live send (DEF-P8 / DEF-P7
pattern: external-account use = recorded, capped, sandbox-marked, never inferred).

```
attested_by:         <the operator/controller - fill in on YOUR copy>
date:                <yyyy-mm-dd of your recorded approval>
provider / account:  Gmail SMTP (smtp.gmail.com:587 STARTTLS), sending account <your-sender-address>
recipient:           <your-recipient-address>  (config-resolved: env NEO_NOTIFY_RECIPIENT or
                     %USERPROFILE%\.neo_notify\config.json; the module has NO recipient parameter)
auth_method:         Gmail App Password (you create it; requires 2-Step Verification on the account)
auth_credential:     location-by-name: %USERPROFILE%\.neo_notify\smtp_credential (single line = the
                     App Password; existence/mtime verified only - contents NEVER read into chat,
                     logs, commits, or any governed tree)
scope:               OUTBOUND gate notifications ONLY, restricted to the FRICTION EVENT CLASSES:
                     human DECISION needed / human APPROVAL needed / SESSION END, plus the engine-side
                     escalation STOP and circuit-breaker trip. Any GateType outside this set =>
                     the module REFUSES. NOT a general mail capability; NOT inbound; NOT any other
                     Google service.
content_rules:       subject + max ~12 summary lines; gate type, slice id, one-line question, and an
                     evidence folder PATH (path only). NEVER source, diffs, secrets, or real data. ASCII.
caps:                the event-class restriction above IS the cap. Anti-runaway guard: an IDENTICAL
                     notification (same gate + slice + summary hash) within 10 minutes is deduplicated.
authority_rule:      notification is a CONVENIENCE channel, never authority: a sent email is not a gate
                     answer; the in-chat gate question remains the ONLY decision surface.
test_mode:           fixture mode composes a .eml.txt on disk (no egress); live mode requires this
                     attestation IN FORCE + the credential file present + a configured recipient/sender.
revocation:          revocable at any time; revocation = delete/disable the App Password and mark this
                     record REVOKED; the module fail-closes to no-send + in-chat surfacing only.
inferred:            NO (must be an explicit attestation, per DEF-P7 pattern)
```

## Binding conditions (enforced at every send)
- Applies ONLY to the account/method above; any other recipient, account, provider, or content class
  = unattested = refused.
- The credential file is read by the SENDING PROCESS only; its contents never enter chat, evidence,
  logs, or any governed tree. This record carries its location-by-name only.
- A failed send never blocks a gate; a successful send never advances one.
- DEV-only operational surface; the notify module is implementation-class (non-judging).

## Not covered
- Reading mail, calendar, or any inbound Google surface.
- Notifications containing source/diff/secret content (expressly out of scope).
