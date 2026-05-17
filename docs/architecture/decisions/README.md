# Architecture Decision Records

This folder is the canonical log of architectural decisions for the Engagement Attribution feature. One file per decision, numbered sequentially. New decisions append; superseded decisions are marked but not deleted.

## Format

Every ADR follows the [Michael Nygard template](https://github.com/joelparkerhenderson/architecture-decision-record/tree/main/locales/en/templates/decision-record-template-by-michael-nygard):

1. **Title** — `NNNN-kebab-case-summary.md`.
2. **Status** — `Proposed` / `Accepted` / `Deprecated` / `Superseded by NNNN`.
3. **Context** — what forces are in play.
4. **Decision** — the choice made.
5. **Consequences** — what becomes easier; what becomes harder.

Keep it crisp. ADRs are not essays — one page per decision, two if the trade-off is genuinely complex.

## Index

|                                                       # | Title                                               | Status   |
| ------------------------------------------------------: | --------------------------------------------------- | -------- |
| [0001](0001-three-layer-selector-service-controller.md) | Three-layer Selector / Service / Controller pattern | Accepted |

## When to write a new ADR

Open a new ADR when the team makes a decision that:

- Constrains future Apex/LWC code (e.g. "all SOQL goes through Selector classes").
- Changes the data contract between layers (DTO shape, REST envelope, signal idempotency key).
- Locks in a security posture (sharing model, USER_MODE enforcement, hard-delete vs. soft-delete).
- Defines an extension point (custom metadata schema, custom setting hierarchy).

Don't open an ADR for routine implementation choices — those live in [development/apex-conventions.md](../../development/apex-conventions.md) and the [best-practices/](../../../best-practices/) tree.

## Authoring flow

1. Copy the most recent ADR file, increment the number.
2. Draft Context → Decision → Consequences.
3. Open a PR; ping Atlas as reviewer.
4. On merge, update this index.
