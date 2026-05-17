# Apex Developer Onboarding

How to ship your first Apex change on Engagement Attribution. Read top-to-bottom on day one.

## 1 — Tools

| Tool                                    | Why                                                           | Verify                                                    |
| --------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------- |
| **Salesforce CLI `sf` v2.x**            | All deploys / scratch-org / Apex execution.                   | `sf --version` (expect `@salesforce/cli/2.x`).            |
| **VS Code + Salesforce Extension Pack** | ApexDoc/intellisense, deploy on save (optional), Org Browser. | `code --install-extension salesforce.salesforcedx-vscode` |
| **Node 18+ + npm**                      | LWC Jest tests, Husky pre-commit, Prettier, ESLint.           | `node --version` (expect `v18` or `v20`).                 |
| **Git + SSH key for GitHub**            | Repo is `experance-dev/blue_sky`; PRs flow through GitHub.    | `ssh -T git@github.com`                                   |

Optional but recommended: [SFDX-Hardis](https://hardisgroupcom.github.io/sfdx-hardis/) for the org-diff and dependency-graph commands; the [Apex PMD VS Code extension](https://marketplace.visualstudio.com/items?itemName=ChuckJonas.apex-pmd) for in-editor complexity warnings (the project complexity budget is in [best-practices/apex.md](../../best-practices/apex.md#complexity-budget)).

## 2 — Repo + worktree

Engagement Attribution lives in a worktree off the main repo:

```bash
# clone (one-time)
git clone git@github.com:experance-dev/blue_sky.git ~/Work/Zelis
cd ~/Work/Zelis

# the engagement worktree
cd .claude/worktrees/feature-engagement-attribution
```

The worktree is on branch [`feature/engagement-attribution`](https://github.com/experance-dev/blue_sky/tree/feature/engagement-attribution). All Apex/LWC work lands here, not on `main`. Atlas merges to `main` after release sign-off.

Run `npm install` from the worktree root once to seed Husky + ESLint + Prettier hooks.

## 3 — Scratch-org access

David's personal Dev Hub is `ExperanceProd` ([david@experancepartners.com](mailto:david@experancepartners.com)). Ask David to add your SF user to the Dev Hub if you don't have access yet, then:

```bash
sf org login web --alias ExperanceProd --set-default-dev-hub
sf org list --target-dev-hub
```

Create your own scratch org from the project definition:

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias <your-initials>-engagementDev \
  --duration-days 30 \
  --target-dev-hub ExperanceProd
```

Full create → deploy → seed → demo loop is in [users/DEMO.md](../users/DEMO.md). Run it end-to-end before your first PR — that is the fastest way to internalize the data model.

## 4 — Read before writing

In order:

1. [architecture/overview.md](../architecture/overview.md) — the feature in one read.
2. [architecture/decisions/0001-three-layer-selector-service-controller.md](../architecture/decisions/0001-three-layer-selector-service-controller.md) — the layering rule you'll be ticketed against.
3. [development/apex-conventions.md](apex-conventions.md) — how every class header / method / catch block looks.
4. [best-practices/apex.md](../../best-practices/apex.md) and [best-practices/apex-tests.md](../../best-practices/apex-tests.md) — the canonical rules. Apex conventions doc links to these; do not duplicate.
5. One existing class top-to-bottom to internalize the style — [`EngagementServiceImpl`](../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls) is the canonical example.

## 5 — First commit walkthrough

Run an existing test in your scratch org to prove the toolchain works:

```bash
sf apex run test --tests EngagementServiceImplTest --target-org <your-alias> --result-format human --code-coverage --wait 10
```

Expected: 100% pass, ≥80% coverage on `EngagementServiceImpl`. If anything red, ping Boomer before chasing it — env mismatches are the most common cause.

Pick up a "starter task" — small, low-risk, in scope:

- ApexDoc gap on an existing class header (ping Marlowe for the current list).
- A `Logger.warn` line that should be `Logger.info`.
- A typo in a custom-label string.
- An extra null-check in a helper method.

**Do not write your own tests.** Per [TEAM.md hard rule #1](/Users/david/Work/Zelis/.claude/agents/TEAM.md), only the Test Team writes test code. If your change uncovers a coverage gap, file it with Pippa.

Open a PR with the `/review-pr` slash command (see [TEAM.md §PR review discipline](/Users/david/Work/Zelis/.claude/agents/TEAM.md)). Boomer is your Sr-dev reviewer for Apex; Atlas signs off architecturally; Sage signs off on security.

## 6 — Where to ask

| Question                                                                                    | Ask                                                                                  |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| "Should this be a Selector or a Service?"                                                   | [Atlas](/Users/david/Work/Zelis/.claude/agents/atlas.md) (TA — architecture).        |
| "What's the canonical way to write this Apex pattern?"                                      | [Boomer](/Users/david/Work/Zelis/.claude/agents/boomer-codey.md) (Sr Apex).          |
| "My test won't pass / is this enough coverage?"                                             | [Pippa](/Users/david/Work/Zelis/.claude/agents/pippa-codey.md) (Sr Test Architect).  |
| "Does this expose data without USER_MODE?"                                                  | [Sage Cloudy](/Users/david/Work/Zelis/.claude/agents/sage-cloudy.md) (Security).     |
| "How do I deploy / what's the scratch-org name / where does the package version come from?" | [Dash Earnie](/Users/david/Work/Zelis/.claude/agents/dash-earnie.md) (DevOps).       |
| "The ApexDoc I wrote is wrong"                                                              | [Marlowe](/Users/david/Work/Zelis/.claude/agents/marlowe-codey.md) (Apex docs — me). |

Cross-team disagreements escalate to Atlas, not the PR thread.

---

**Summary:** install `sf` + Node + VS Code; clone the repo and `cd` to the engagement worktree; create your own scratch org from `project-scratch-def.json`; read [architecture/overview.md](../architecture/overview.md) and [best-practices/apex.md](../../best-practices/apex.md); run an existing test; pick a starter ApexDoc/Logger ticket and PR it with `/review-pr`. Devs do not write their own tests — file gaps with Pippa.
