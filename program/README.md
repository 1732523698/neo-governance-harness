# ./program/ — RESERVED program-scope evidence home (A-BRIDGE cat 1 / v4 §5.5)

**Created 4.0-P3-A (INSTALL FOUNDATION). Structure/placeholders ONLY — no authoritative
content lives here yet.** The master orchestrator (**P3-B**) populates the real instances at
runtime. This slice is contracts/schemas only (spec-first); it authored no instance data.

## Program artifacts homed here (JSON authoritative per Q1)
Each artifact validates against its live spine schema under `../.neo/schema/`:

| Runtime file (populated by P3-B) | Live schema `$id`            | Schema file                                    |
|----------------------------------|------------------------------|------------------------------------------------|
| `PROJECT_SPEC.json`              | `neo:project_spec`           | `.neo/schema/project_spec.schema.json`         |
| `CONSTRAINT_PACKAGE.json`        | `neo:constraint_package`     | `.neo/schema/constraint_package.schema.json`   |
| `ARCHITECTURE.json`              | `neo:architecture`           | `.neo/schema/architecture.schema.json`         |
| `RISK_REGISTER.json`             | `neo:risk_register`          | `.neo/schema/risk_register.schema.json`        |
| `SUBSESSION_INDEX.json`          | `neo:subsession_index`       | `.neo/schema/subsession_index.schema.json`     |
| `MASTER_CHECKPOINT.json`         | `neo:master_checkpoint`      | `.neo/schema/master_checkpoint.schema.json`    |
| `HANDOFF_PACKET.json`            | `neo:handoff_packet`         | `.neo/schema/handoff_packet.schema.json`       |

## Placeholders in this directory
The `*.json.PLACEHOLDER` files are **NON-authoritative markers**, NOT runtime instances and
NOT valid schema instances. They exist only to reserve the home and document intent.

- They deliberately do **not** use the runtime `<NAME>.json` name, so no future discovery /
  consumer / glob logic can pick them up as real artifacts.
- **Note for P3-B:** when you populate a real artifact, write the runtime `<NAME>.json` file;
  do not treat any `*.PLACEHOLDER` as input. A consumer scanning `./program/` MUST match the
  exact `<NAME>.json` names above and MUST NOT glob `*.json*` (which would catch placeholders).

RELEASE_MANIFEST is intentionally absent here: it is homed under `./.neo/release/` and its
field schema remains HELD pending the OQ-5 producer reconciliation (not installed 4.0-P3-A).
