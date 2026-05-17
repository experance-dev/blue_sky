# Brief for Sharp Kai — Jira + Confluence workspace setup

**From:** Atlas (Technical Architect, Engagement Attribution team)
**To:** Sharp Kai
**Date:** 2026-05-16
**Subject:** Stand up our own Jira project + Confluence space; provision worker credentials per the team roster.

---

## 1. Decision: Jira + Confluence (recommended)

Two options were on the table for our ticket and documentation surface:

| Option                              | Pros                                                                                                                                                                                                                                                                                                                               | Cons                                                                                                                                                                           |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **GitHub Issues + repo `docs/`**    | Same place as code; no extra tooling; PR↔issue linking native.                                                                                                                                                                                                                                                                     | Diverges from Zelis's stack. Tickets I write don't live alongside the rest of the Zelis ticket history Sharp Kai admins. Confluence still needed somewhere for narrative docs. |
| **Jira + Confluence (recommended)** | Same stack Zelis lives in. Single ticket surface for all our work. Worker actions (story creation, transitions, comments) attribute to specific agents per [`TEAM.md`](/Users/david/Work/Zelis/.claude/agents/TEAM.md). Confluence handles the narrative docs (test standards, runbooks, BRDs) that don't belong in repo markdown. | Two new spaces to administer (our project + our Confluence space). Credentials to provision (see §3).                                                                          |

**Recommendation: Jira + Confluence.** Zelis already runs on Atlassian; staying inside that stack keeps the audit trail in one place and lets David hand a Jira link to any Zelis stakeholder without a tooling primer.

## 2. What we need stood up

### 2.1 Jira project

- **Project key:** `BSKY` (Blue Sky — matches the repo codename `experance-dev/blue_sky` and the Confluence space). URL surface reads "BSKY-123".
- **Project template:** Scrum or Kanban — Atlas defers; whichever Sharp Kai standardizes on for product teams.
- **Issue types:** Story, Bug, Task, Epic. Sub-task optional.
- **Workflow:** Standard 3-or-4-state (Backlog → In Progress → In Review → Done) is fine. Atlas does NOT need a custom workflow on day one.
- **Custom fields:** None on day one. The standard fields (priority, assignee, fix version, labels, components) are enough.
- **Components:** Seed with `MI / Engagement Attribution`, `CSI-7162 / Jira Push`, `Salesforce Utilities`, `Test Standards`, `DevOps`, `Documentation`. Atlas can add more as the team grows.
- **Boards (under BSKY):**
  - **Blueprint** — architecture decisions, ADRs, RFCs, standards work, schema reviews, design-doc approval gate. Owners: Atlas + Iris Ruth + Standards Team.
  - **Sprint** — active dev work, stories in flight, current iteration. Owner: Dev Team.
  - **Triage** — defects (prod + UAT + scratch), sev-sorted, owner-assigned. Owners: Verity Hootie + Otto Cloudy + whoever owns the broken thing.
- **Permissions:** All workers in [`TEAM.md`](/Users/david/Work/Zelis/.claude/agents/TEAM.md) need create / edit / comment / transition. David needs admin. Atlas needs project-admin (so he can adjust components / labels without bothering Sharp Kai).

### 2.2 Confluence space

- **Space name:** **Blue Sky** (the engagement codename — already established in the repo name `experance-dev/blue_sky`). Space key: `BSKY` to match Jira.
- **Initial pages Atlas will populate:**
  - **Test standards** — Marlowe's writeup (TestWarehouse, DI-injected tests, TestFactory + portable defaults, runAs hygiene, persona coverage, no-real-emails, compound-FLS gotcha, junior-dev template + samples). Spec at [`project-test-standards-confluence-writeup`](../../../../../.claude/projects/-Users-david-Work-Zelis/memory/project_test_standards_confluence_writeup.md).
  - **Engagement Attribution architecture** — current state of the feature (Atlas + Marlowe).
  - **CSI-7162 Jira Push architecture** — event-driven pattern reference (Boomer + Marlowe).
  - **Runbooks** — deploy, rollback, error-triage (Dash + Otto + Marlowe).
- **Permissions:** Same workers, view + edit. David admin.

### 2.3 Atlassian ↔ Jira linking

- The Atlassian MCP (`atlassian-sharp-kai`) is already wired into our environment. Once the project + space exist and credentials are provisioned per §3, the tools will pick them up automatically.

## 3. Worker credentials — provision per TEAM.md

**See the canonical team roster: [`/Users/david/Work/Zelis/.claude/agents/TEAM.md`](/Users/david/Work/Zelis/.claude/agents/TEAM.md), §"Role + agent + identity".**

That file is the source of truth for:

- Display name
- Email address (`firstname.lastname@fndrix.ai`; Atlas is the single-name exception `atlas@fndrix.ai`)
- Role + scope of work

**Same email is used for both git commits and Atlassian identity** per [`feedback-worker-git-identity-per-worktree`](../../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_worker_git_identity_per_worktree.md). One identity, every tool. Post-fact forensics ("who wrote this ticket?", "who made this commit?") resolves to a specific worker, not a generic David.

**Email pattern:** `firstname.lastname@fndrix.ai` for everyone except the two architectural north-stars — **Atlas** (internal TA) and **Magnus** (external CTA) — who hold single-name emails as a tier exception.

**Total seats needed:** 23 Dev Team (incl. Verity Hootie, QA Architect) + 6 Standards Team + David = **30**. (David already has an Atlassian identity via Zelis; he just needs grant to our new project + space.)

**Team structure:** The **Salesforce Team** umbrella has two subteams:

- **Salesforce Development Team** — Atlas + Apex/LWC/Test/DevOps/Admin/Security/QA + Iris Ruth (PO/PM). Builds and ships.
- **Salesforce Standards Team** — Magnus / Vista Ruth / Helix Genie / Tally Saasy / Quill Koa / Beacon Blaze. Advises, sets the bar, owns standards artifacts. Does not ship code.

**Notable inclusions:**

- **6 Standards Team members** (Magnus, Vista Ruth, Helix Genie, Tally Saasy, Quill Koa, Beacon Blaze) — write to Confluence, comment on Jira, review PRs. Output flows into the Dev Team via Atlas.
- **5 QA members** under Echo Hootie (Echo, Vera, Marlo, Argus, Saba — all Hootie family) — post-build verification specialists, distinct from the dev-side test team (Wren Hootie + Pippa Codey). They write tickets, file bugs, sign off on QA-readiness.
- **Iris Ruth** (Solution Architect, Dev Team) writes the most tickets — she's the ticket-author by role.
- **Marlowe Codey + Lyric Astro** (docs writers) own Confluence pages.
- **Otto + Mira Cloudy** (admins) handle config tickets.
- **Surnames follow Salesforce mascot families** by role group: architects = **Ruth**, Apex = **Codey**, LWC = **Astro**, admin/security = **Cloudy**, QA + test-dev = **Hootie**. Standards Team members take role-specific mascots (Genie / Saasy / Koa / Blaze) plus the Ruth architects family.

## 4. What Atlas needs back from Sharp Kai

1. **Project URL** — e.g., `https://<workspace>.atlassian.net/jira/software/projects/BSKY/board`.
2. **Confluence space URL.**
3. **Per-worker API tokens** — Atlas wires them into the MCP server config. (Or single OAuth grant if Sharp Kai's workspace prefers — Atlas can adapt.)
4. **Confirmation that David has admin on both** so he can adjust anything Atlas can't.

Once that's in hand, Atlas will:

- Convert the 9 user stories from [`docs/research/zelis-test-failure-categorization.md`](../research/zelis-test-failure-categorization.md) into Jira stories (Pareto top-2 close 71% of failures — those go in first).
- Move active Engagement Attribution + CSI-7162 work into Jira epics with the right components / labels.
- Hand Marlowe the Confluence space to start the test-standards writeup.

## 5. Out of scope (don't provision yet)

- Bitbucket / GitLab / source-hosting — we stay on GitHub (`experance-dev/blue_sky`).
- Atlassian Trello / Statuspage / Opsgenie — not needed for this team.
- Custom Jira workflows, automations, or apps — Atlas will request them if a real need shows up.
- Service Management (JSM) — not needed; we're internal-build, not customer-support.

---

**Summary:** Stand up a Jira project (`FNDRX` or your call) + Confluence space for the Fndrix engineering team. Provision 23 Atlassian seats per the roster at [`/Users/david/Work/Zelis/.claude/agents/TEAM.md`](/Users/david/Work/Zelis/.claude/agents/TEAM.md) — emails follow `firstname.lastname@fndrix.ai` (Atlas single-name). Hand back URLs + tokens + admin grant to David; Atlas wires the MCP and gets the team into Jira.
