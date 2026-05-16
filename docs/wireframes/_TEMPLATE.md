# <Feature Name> — Design

**Lucid:** [<descriptive name>](<lucid URL>) — source of truth, edit there
**Jira:** [<TICKET-N>](<jira URL>)
**Last design rev:** YYYY-MM-DD by Nova
**Status:** Draft | In review | Approved by Coda | Shipped

## Context

<One paragraph: what the feature is, who uses it, what business problem it solves. Iris's brief distilled to design-relevant context.>

## Mocks

![Desktop primary state](./<feature>-desktop-primary.png)
![Empty state](./<feature>-empty.png)
![Loading state](./<feature>-loading.png)
![Error state](./<feature>-error.png)
![Sales-console-narrow](./<feature>-narrow.png)
![Mobile (if applicable)](./<feature>-mobile.png)

<Screenshots exported from Lucid for offline reading. ≤500KB each, descriptive filenames.>

## Interaction spec

| Element        | Hover      | Click      | Keyboard  | Focus order |
| -------------- | ---------- | ---------- | --------- | ----------- |
| <element name> | <behavior> | <behavior> | <key map> | <N>         |

<Flow-level state machine notes after the table: empty → loading → success → error transitions, debounce timings, multi-select rules, anything that isn't a single element's behavior.>

## Accessibility

- **ARIA roles + labels** — per interactive element
- **Contrast ratios** — call out any waivers; default ≥4.5:1 text, ≥3:1 large text and non-text
- **Focus order** — diagram or numbered list above
- **Keyboard shortcuts** — if any
- **Screen reader notes** — how the experience reads audibly

## Responsive

- **Desktop (≥1024px):** <behavior>
- **Sales console narrow (~600–900px):** <what compresses, what hides, what reflows>
- **Mobile (<600px, if applicable):** <behavior>

## Copy strings

| Key             | String       | Notes         |
| --------------- | ------------ | ------------- |
| `title`         | <exact text> | <where shown> |
| `emptyState`    | <exact text> |               |
| `errorState`    | <exact text> |               |
| `buttonPrimary` | <exact text> |               |

<Every visible text string, exactly as it should appear. Lyric pulls from this for user-facing docs.>

## Design tokens + SLDS classes used

SLDS-first. Custom CSS only where no SLDS class or token covers the intent.

| Token / class                     | Use               |
| --------------------------------- | ----------------- |
| `slds-grid`                       | <layout>          |
| `slds-var-p-around_small`         | <element padding> |
| `--slds-c-badge-color-background` | <element>         |
| `--lwc-paletteNeutral10`          | <element>         |

## Implementation notes for Coda

- SLDS components to compose: `lightning-modal`, `lightning-formatted-date-time`, etc.
- Wire-pattern hints or DTO shape implications
- Event contract up to the parent: which click/hover dispatches which `CustomEvent`
- Performance considerations Nova noticed during design
- Anything else implementation-affecting

## Persona coverage

Which personas this design serves and what each one needs from it (good-path AND bad-path — see [feedback-persona-path-coverage](../../.claude/agents/) memory).

- **<Persona A>:** <primary use case>
- **<Persona B>:** <primary use case>

## Open questions

- [ ] <unresolved decision — tag whose answer you need: David / Iris / Atlas / Coda>
