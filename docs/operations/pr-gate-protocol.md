# PR Gate Protocol — `experance-dev/blue_sky`

Authoritative protocol for how pull requests get merged in this repo. Mirrors
the shape of [`experance-dev/fosfoundry`](https://github.com/experance-dev/fosfoundry)'s
gate, adapted for the Zelis Engagement Attribution engagement.

> **TL;DR** — every PR needs **3 review-team approvals + 1 codeowner approval + green status checks**.
> Review-team identities are **GitHub Apps**, not humans (Sage / Iris / Magnus = bot reviewers). Apps post `event: APPROVE` reviews via installation tokens; each App is the sole member of a single-member Team so Rulesets can pin them by Team-ID.
> Codeowners (this file's [`.github/CODEOWNERS`](../../.github/CODEOWNERS) gate) are **human identities**: David (preferred) or Atlas (peer codeowner; logs every stand-in approval).

---

## 1. Gate model

**Codeowner ≠ reviewer.** Two independent gates, both required:

1. **CODEOWNERS gate** — substantive approval identity (David or Atlas)
2. **Review-team gate** — substantive review by Sage + Iris + Magnus

The review team gives *substantive review* (security, business-fit, standards).
The codeowner gives *final approval identity* — the signoff that says "this
ships." Branch protection enforces both.

### 1.1 Review team — 3 required, parallel, **GitHub Apps**

Each reviewer is a **GitHub App** acting on the agent's behalf, posting PR
reviews via an installation access token. Each App is the sole member of a
single-member organization Team so Repository Rulesets can pin the App's
identity by **Team ID** (the Rulesets API only accepts `type: Team` for
required reviewers — there is no `App` / `Integration` reviewer type).

| Reviewer | App slug | Single-member team | Scope |
| --- | --- | --- | --- |
| **Sage Cloudy** | `bluesky-sage` | `@experance-dev/reviewer-sage` | Security — sharing, permsets, custom permissions, auth, FLS/CRUD, OWD-Private posture, HIPAA perimeter |
| **Iris Ruth** | `bluesky-iris` | `@experance-dev/reviewer-iris` | Product Owner — business-fit, persona acceptance, gate-1 spec, gate-2 delivery |
| **Magnus** | `bluesky-magnus` | `@experance-dev/reviewer-magnus` | CTA / Standards — [`sf-best-practices.md`](../standards/sf-best-practices.md), architecture, scanner severity, canon decisions |

All three review **in parallel**. The App posts an approval review from its
bot identity (`bluesky-sage[bot]` etc.); because the bot is the only member
of the matching Team, the Rulesets `required_reviewers` Team-ID requirement
is satisfied by exactly that App's approval. See [§6.4](#64-review-team-gate-via-repository-ruleset--apps-pinned-via-single-member-teams)
for the Ruleset shape; see [§7.3](#73-tier-b--review-team-approve-only) for the
review-team Apps and [§7.5](#75-provisioning-runbook--bash-for-loops) for the
full provisioning runbook.

> **Why single-member teams instead of direct App pinning?** GitHub Rulesets'
> `required_reviewers.reviewer.type` enum is `Team` only; CODEOWNERS likewise
> accepts users + teams + email addresses but **not** App slugs
> ([docs](https://docs.github.com/articles/about-code-owners)). Wrapping each
> App in a single-member Team is the canonical GitHub-idiomatic workaround.

### 1.2 Codeowner approval — 1 of 2 required

Enforced via [`.github/CODEOWNERS`](../../.github/CODEOWNERS) +
`require_code_owner_reviews: true` on branch protection.

| Codeowner | Preference |
| --- | --- |
| **David Wood** (`@david-wood`) | Preferred when David is around. Required on PRs targeting `main`. |
| **Atlas** | Peer codeowner. Real codeowner identity (not a stand-in workaround). When David is offline, Atlas's approval satisfies the gate. Every Atlas approval logged in [`atlas-standin-approvals.log`](atlas-standin-approvals.log) with full context. |

Both David and Atlas are listed in CODEOWNERS, so either's approval
satisfies the GitHub codeowner-review rule. The hard rule that David is
the only codeowner approver on `main` lives in §2 + §3; branch protection
on `main` enforces it via `enforce_admins: true` and David-only push allowlist.

### 1.3 Status checks — required green

- `code-analyzer` — `sf code-analyzer run` SPOTLESS gate ([§12.1 of standards](../standards/sf-best-practices.md))
- `apex-test-run` — `RunLocalTests` against `dwood_z` with canon-aware failure handling
- (added when [PR #8](https://github.com/experance-dev/blue_sky/pull/8) lands; workflow files at [`.github/workflows/code-analyzer.yml`](../../.github/workflows/code-analyzer.yml) and [`.github/workflows/apex-test-run.yml`](../../.github/workflows/apex-test-run.yml))

### 1.4 Merge action

Once **3 review-team reviews + 1 codeowner approval + all status checks**
are green, **anyone with write access** can click merge. David may choose to
be sole merger as preference; that's not a hard rule.

---

## 2. When Atlas approves vs waits for David

Atlas is a real codeowner — not a workaround for David being away. When David
is around, his approval is preferred (he's the engagement TA + sole approver on
`main`). When David is offline, Atlas's codeowner approval satisfies the
GitHub gate on `develop` / `UAT` and the PR moves.

Per [`feedback_atlas_verifies_before_uat`](https://docs.local/feedback) — Atlas
approves **only when** he has personally verified the work meets the
David-review bar. If Atlas is unsure, the PR waits for David.

### 2.1 Atlas may approve

- PRs targeting `develop` or `UAT`
- After Atlas has personally verified the change in `dwood_z` (or the relevant
  scratch org)
- When all three reviewer-tier sign-offs are present and clean
- When CI is green
- When the change does **not** touch:
  - production (`main`) — David explicit
  - standards canon ([`sf-best-practices.md`](../standards/sf-best-practices.md)) — Magnus + David explicit
  - test canon ([`known-failures-canon.md`](../testing/known-failures-canon.md)) — Pippa/Verity + David explicit
  - security architecture (permsets, sharing rules, custom permissions, OWD changes) — Sage + David explicit

### 2.2 Atlas must wait for David

- PRs targeting `main` (production)
- Any change in the categories listed in §2.1's "does **not** touch" list
- David is reachable within a reasonable window
- The change is sufficiently novel that Atlas cannot honestly say "I'd merge this myself if it were my repo"

### 2.3 Atlas approval audit trail

Atlas is a real codeowner, but every Atlas codeowner approval **must** still
be logged for traceability — David greps the log to confirm Atlas only signed
where David would have. See
[`atlas-standin-approvals.log`](atlas-standin-approvals.log). Format:

```
2026-05-16T22:30:00Z | PR #6 | feature/engagement-attribution → develop | Atlas codeowner-approved | Reason: <reason> | David context: <window or "after-hours">
```

Atlas commits the log row in the same PR he approves (or a follow-up PR if the
log write fails the protection rule). David greps the log periodically.

> **Deferred — append-only CI enforcement.** A workflow that fails any PR
> which modifies prior lines of [`atlas-standin-approvals.log`](atlas-standin-approvals.log)
> (i.e. enforces append-only) was scoped in Sage's PR #12 review and
> **deferred** as non-blocking. Sage's trigger condition for un-deferring:
> the first 10 logged Atlas approvals, **or** one calendar month from the
> first logged approval, whichever comes first. At that point Dash adds a
> workflow that diffs the file's history and rejects any PR whose diff
> deletes or rewrites pre-existing rows. Until then, the discipline is
> honor-system + David's periodic grep.

---

## 3. Branch model

Three permanent boxes (per [`feedback_branch_strategy`](https://docs.local/feedback)):

| Branch | Purpose | Codeowner approver | Atlas codeowner approval valid? |
| --- | --- | --- | --- |
| `main` | Production | David only | No (David explicit) |
| `UAT` | Pre-prod / Verity gate | David or Atlas | Yes (audit-logged) |
| `develop` | Integration | David or Atlas | Yes (audit-logged) |

Feature branches off `develop`; story branches off feature. Promotion path:
`story → feature → develop → UAT → main`.

---

## 4. Override paths

### 4.1 Emergency direct push (David / Dash / Atlas on `develop` and `UAT`; David only on `main`)

Branch-protection rule lists David, Dash, and Atlas in the "Restrict who can
push to matching branches" allowlist for emergency direct-push to `develop`
and `UAT`. The `main` allowlist narrows to **David only** — see the §6.3
payload's `restrictions.users: ["david-wood"]`. **Use is rare and audited.**
Document every direct push in a follow-up PR that backfills tests / standards
review.

### 4.2 Status-check waiver

Magnus signs scanner waivers as narrow exceptions with rationale in
[`docs/standards/sf-best-practices.md`](../standards/sf-best-practices.md).
**Never** skip CI via `--no-verify` or admin bypass.

### 4.3 Atlas override authorization

Per Dash's hard rules, Dash will not instant-merge a Dash-authored PR even
under tooling pressure unless **Atlas explicitly authorizes** with override
language (e.g. *"merge now, retroactive sign-offs"*). David shorthand like
"just ship it" still routes through PR → reviews → merge, not auto-merge.

---

## 5. Branch protection — current state & gaps

### 5.1 What this PR ships (in-repo)

- [`.github/CODEOWNERS`](../../.github/CODEOWNERS) — codeowner-gate enforcement (David + Atlas)
- [`docs/operations/pr-gate-protocol.md`](pr-gate-protocol.md) — this file
- [`docs/operations/atlas-standin-approvals.log`](atlas-standin-approvals.log) — Atlas codeowner-approval audit log

### 5.2 What David must apply via `gh api` / repo Settings UI

Branch-protection rules cannot be set from a PR. David runs these (or his
admin equivalent) once handles are confirmed. **Replace `@<handle>`
placeholders first.** See §6 for the exact `gh api` commands.

### 5.3 Known gaps

| Gap | Impact | Resolution |
| --- | --- | --- |
| Reviewer Apps (and the other 24) not yet created | Rulesets can't pin reviewers until the Tier B Apps + single-member teams exist | David provisions all 27 per [§7.5](#75-provisioning-runbook--bash-for-loops); paste Tier B numeric Team IDs into §6.4 |
| Atlas's GH user handle unconfirmed | CODEOWNERS catch-all has placeholder `@atlas` | Coordinate with Sharp Kai for canonical handle; replace in [`.github/CODEOWNERS`](../../.github/CODEOWNERS) |
| `code-analyzer` + `apex-test-run` not yet required checks | CI runs but doesn't gate | Land [PR #8](https://github.com/experance-dev/blue_sky/pull/8), then add via §6 commands |

---

## 6. `gh api` commands David runs

> Replace `@<placeholder>` handles with real ones before executing.

### 6.0 How the two gates map to the GitHub API

Two independent gates, two different GitHub mechanisms:

1. **CODEOWNERS** + `require_code_owner_reviews: true` → named approval from
   the codeowner identities (human users / teams) for files they own. We use
   this for the **codeowner gate (David + Atlas)**. CODEOWNERS does **not**
   accept GitHub App slugs as owners — owners are users, teams, or email
   addresses only ([docs](https://docs.github.com/articles/about-code-owners)).
   Codeowners therefore stay as human handles.
2. **Repository Rulesets** ([`POST /repos/{owner}/{repo}/rulesets`](https://docs.github.com/en/rest/repos/rules))
   with `required_reviewers.reviewer.type: Team` → named team-approval. We
   use this for the **review-team gate (Sage + Iris + Magnus Apps)**. Each
   reviewer App is the sole member of a Team; pinning the Team-ID effectively
   pins the App. Classic branch protection's `required_pull_request_reviews`
   does **not** have a `required_reviewers` shape at all — it only takes an
   integer count + a code-owner toggle. The named-reviewer pinning lives in
   Rulesets exclusively, which is why this protocol uses both layers.

**Why Apps cannot be pinned directly.** Rulesets' `required_reviewers.reviewer`
enum is `Team` only. Classic branch protection accepts Apps in
`restrictions.apps` (push), `dismissal_restrictions.apps`, and
`bypass_pull_request_allowances.apps` — but **never** as required reviewers.
The single-member-Team wrapper is the canonical workaround.

**What App approval gives us.** Apps post PR reviews via
`POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews` with `event: APPROVE`
using an installation access token (scope: `pull_requests: write`). The
approval is attributed to the App's bot user (`<app-slug>[bot]`), which
counts toward `required_approving_review_count` and — because the bot is the
sole member of its Team — satisfies the Ruleset's per-Team requirement.

### 6.1 `develop` — codeowner gate via branch protection

```bash
gh api -X PUT repos/experance-dev/blue_sky/branches/develop/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["code-analyzer", "apex-test-run"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 4,
    "require_last_push_approval": false
  },
  "restrictions": {
    "users": ["david-wood", "dash-earnie", "atlas"],
    "teams": [],
    "apps": []
  },
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

Count = 4 = (3 review-team) + (1 codeowner). `require_code_owner_reviews:
true` reserves one of the four slots for a David-or-Atlas approval (per
[`.github/CODEOWNERS`](../../.github/CODEOWNERS)). The other three slots
are filled by the review team — see §6.4 for the Ruleset that pins those
identities by name.

### 6.2 `UAT` — identical mechanics to develop

```bash
gh api -X PUT repos/experance-dev/blue_sky/branches/UAT/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["code-analyzer", "apex-test-run"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 4,
    "require_last_push_approval": false
  },
  "restrictions": {
    "users": ["david-wood", "dash-earnie", "atlas"],
    "teams": [],
    "apps": []
  },
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

### 6.3 `main` — David explicit, Atlas excluded from codeowner approval

Branch protection cannot encode *"David but not Atlas"* by identity within
CODEOWNERS — both are listed as codeowners and either's review satisfies
`require_code_owner_reviews`. The hard rule that **only David** approves
`main` lives in the protocol (§1.2, §2.2) + push-allowlist below +
`enforce_admins: true`. Atlas's audit-log discipline (§2.3) plus David's
periodic grep catches any violation:

```bash
gh api -X PUT repos/experance-dev/blue_sky/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["code-analyzer", "apex-test-run", "gate-atlas-main-block"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 4,
    "require_last_push_approval": true
  },
  "restrictions": {
    "users": ["david-wood"],
    "teams": [],
    "apps": []
  },
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

`enforce_admins: true` blocks even repo admins from bypassing the rule on
`main`. Push allowlist narrowed to David — Dash/Atlas push to feature/UAT
only; `main` is David's explicit lane.

The `gate-atlas-main-block` required status check is `main`-only — it
references the [`.github/workflows/gate-atlas-main-block.yml`](../../.github/workflows/gate-atlas-main-block.yml)
workflow, which fails any PR where `bluesky-atlas[bot]` (or the `@atlas`
human handle, when confirmed) posts `event: APPROVE` against a PR whose
`base.ref == 'main'`. The §6.1 / §6.2 `develop` and `UAT` payloads
deliberately omit this context so Atlas's codeowner approval continues to
satisfy those gates per §2.1.

### 6.4 Review-team gate via Repository Ruleset — Apps pinned via single-member Teams

[`POST /repos/{owner}/{repo}/rulesets`](https://docs.github.com/en/rest/repos/rules)
is the only API surface that pins specific reviewer identities by name on a
modern protected branch. The Rulesets `required_reviewers.reviewer.type`
enum is **`Team` only** — Apps can't be pinned directly. We wrap each
reviewer App in a one-member Team (per [§7](#7-app-provisioning)) and pin the
Team-ID here. Run **once** per environment after the Apps + teams exist
and you have the numeric Team IDs:

```bash
# Look up team IDs (one-time, after §7 provisioning)
gh api orgs/experance-dev/teams/reviewer-sage   --jq .id
gh api orgs/experance-dev/teams/reviewer-iris   --jq .id
gh api orgs/experance-dev/teams/reviewer-magnus --jq .id
```

```bash
gh api -X POST repos/experance-dev/blue_sky/rulesets \
  --input - <<'JSON'
{
  "name": "review-team-gate",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/develop", "refs/heads/UAT", "refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 3,
        "require_code_owner_review": false,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "required_reviewers": [
          {
            "file_patterns": ["**/*"],
            "minimum_approvals": 1,
            "reviewer": { "id": <reviewer-sage-team-id>,   "type": "Team" }
          },
          {
            "file_patterns": ["**/*"],
            "minimum_approvals": 1,
            "reviewer": { "id": <reviewer-iris-team-id>,   "type": "Team" }
          },
          {
            "file_patterns": ["**/*"],
            "minimum_approvals": 1,
            "reviewer": { "id": <reviewer-magnus-team-id>, "type": "Team" }
          }
        ]
      }
    }
  ]
}
JSON
```

Each `required_reviewers` entry needs `file_patterns`, `minimum_approvals`,
and `reviewer{id,type}` (per the [Rulesets create API
schema](https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset)).
`**/*` makes each team's approval required on every PR; tighten the pattern
later for path-specific gating (e.g., Sage on permsets only). The
Ruleset's count-of-3 + three single-member Teams = exactly one approval per
App. Branch protection's count-of-4 in §6.1 / §6.2 sums review-team (3) +
codeowner (1). Both gates evaluate independently; both must pass.

**Only Tier B Apps satisfy the required-reviewer gate.** Tier A
(orchestrator) and Tier C (worker) Apps have `pull_requests: write` so they
can open PRs and comment on review threads — that permission technically
allows them to also post `event: APPROVE`. The Ruleset doesn't care: it
counts approvals only from the three Tier B teams pinned above
(reviewer-sage / reviewer-iris / reviewer-magnus). A stray approval from a
worker or orchestrator App is visible in the PR timeline but does not
satisfy the gate. Worker / orchestrator workflows should issue `COMMENT` or
`REQUEST_CHANGES` only — see [§7.7](#77-honest-pre-flight-unknowns) #7.

### 6.5 Verifying

```bash
# Branch protection rules
for b in main UAT develop; do
  echo "=== $b ==="
  gh api repos/experance-dev/blue_sky/branches/$b/protection
done

# Repository rulesets
gh api repos/experance-dev/blue_sky/rulesets
```

---

## 7. App provisioning

**This is a one-time org-level action — David runs it.** Document only;
Dash does not create the Apps.

### 7.1 Overview — 27 Apps, 3 tiers, single-member-team wrapper

Every agent that touches `experance-dev/blue_sky` gets its own GitHub App.
Per-App isolation is the design point — **not** one umbrella App with many
slugs:

- **Per-App rate limits** — GitHub Apps get their own 5,000-req/hr/installation
  bucket ([rate-limit docs](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/rate-limits-for-github-apps)).
  Sharing a single App across 27 agents collapses everyone into one bucket
  and one mass-revocation switch.
- **Per-App revocation** — if one agent's logic drifts, suspend that App
  without affecting the other 26.
- **Auditability** — each App has its own activity stream; `bluesky-sage[bot]`
  approvals are filterable from `bluesky-boomer[bot]` commits at the API level.
- **Permission scope** — tier-specific permission sets keep blast radius
  minimal. Tier B (review-only) cannot commit; Tier A/C cannot touch settings.

We're at **27 of 100** Apps allowed per org installation. Plenty of room.

| Tier | Role | Count | Permission shape |
| --- | --- | --- | --- |
| **A** | Orchestrators | 2 | contents:write + pull_requests:write + issues:write + workflows:write |
| **B** | Reviewers | 3 | pull_requests:write + contents:read |
| **C** | Workers | 22 | contents:write + pull_requests:write |

Every App is wrapped in a single-member org Team so Rulesets + CODEOWNERS
can pin the App by Team-ID / Team-slug (the only GitHub-idiomatic shape;
neither accepts App slugs directly — see [§6.0](#60-how-the-two-gates-map-to-the-github-api)).

### 7.2 Tier A — Orchestrators (heavy GitHub write)

App slug pattern: `bluesky-<name>`. Team wrapper pattern: `@experance-dev/orchestrator-<name>`.

| App name | Slug | Bot identity | Team wrapper | Backing agent |
| --- | --- | --- | --- | --- |
| BlueSky Atlas | `bluesky-atlas` | `bluesky-atlas[bot]` | `@experance-dev/orchestrator-atlas` | Atlas — Dev Team orchestrator |
| BlueSky Reeve | `bluesky-reeve` | `bluesky-reeve[bot]` | `@experance-dev/orchestrator-reeve` | Reeve — Design Team orchestrator |

**Permissions (per App):**

| Permission | Level | Why |
| --- | --- | --- |
| Repository → Contents | **Read & write** | Branch ops, commit orchestration |
| Repository → Pull requests | **Read & write** | Open, comment, merge PRs |
| Repository → Issues | **Read & write** | Track work-items, link PR→issue |
| Repository → Workflows | **Read & write** | Update `.github/workflows/` for pipeline shape changes |
| Repository → Metadata | **Read** | Mandatory baseline |

No webhooks, no org-level permissions, no `administration`. Orchestrator
Apps still pass through the same PR-gate as workers — they commit, they
don't bypass.

### 7.3 Tier B — Review team (approve-only)

App slug pattern: `bluesky-<name>`. Team wrapper pattern: `@experance-dev/reviewer-<name>`.

| App name | Slug | Bot identity | Team wrapper | Scope |
| --- | --- | --- | --- | --- |
| BlueSky Sage | `bluesky-sage` | `bluesky-sage[bot]` | `@experance-dev/reviewer-sage` | Security — sharing, permsets, custom permissions, auth, FLS/CRUD, OWD-Private, HIPAA perimeter |
| BlueSky Iris | `bluesky-iris` | `bluesky-iris[bot]` | `@experance-dev/reviewer-iris` | Product Owner — business-fit, persona acceptance, gate-1/gate-2 |
| BlueSky Magnus | `bluesky-magnus` | `bluesky-magnus[bot]` | `@experance-dev/reviewer-magnus` | CTA / Standards — [`sf-best-practices.md`](../standards/sf-best-practices.md), architecture, scanner severity, canon |

**Permissions (per App) — read + approve only, no commit:**

| Permission | Level | Why |
| --- | --- | --- |
| Repository → Pull requests | **Read & write** | Post `event: APPROVE` reviews via `POST /repos/{o}/{r}/pulls/{n}/reviews` |
| Repository → Contents | **Read** | Fetch diff context for the review |
| Repository → Metadata | **Read** | Mandatory baseline |

The Tier B Apps **cannot commit code** — they approve only. This is the
deliberate separation that lets Rulesets pin them as required reviewers
without those approvals being self-reviews of their own commits.

### 7.4 Tier C — Workers (commit + push their slice)

App slug pattern: `bluesky-<name>`. Team wrapper pattern: `@experance-dev/worker-<name>`.

**Permissions (per App, all 22):**

| Permission | Level | Why |
| --- | --- | --- |
| Repository → Contents | **Read & write** | Commit + push feature work |
| Repository → Pull requests | **Read & write** | Open PRs, comment on review threads |
| Repository → Metadata | **Read** | Mandatory baseline |

| Sub-role | App slug | Bot identity | Team wrapper |
| --- | --- | --- | --- |
| **DevOps** | `bluesky-dash` | `bluesky-dash[bot]` | `@experance-dev/worker-dash` |
| **Apex dev** | `bluesky-boomer` | `bluesky-boomer[bot]` | `@experance-dev/worker-boomer` |
| **Apex dev** | `bluesky-tex` | `bluesky-tex[bot]` | `@experance-dev/worker-tex` |
| **Apex dev** | `bluesky-finn` | `bluesky-finn[bot]` | `@experance-dev/worker-finn` |
| **LWC dev** | `bluesky-coda` | `bluesky-coda[bot]` | `@experance-dev/worker-coda` |
| **LWC dev** | `bluesky-kit` | `bluesky-kit[bot]` | `@experance-dev/worker-kit` |
| **LWC dev** | `bluesky-robin` | `bluesky-robin[bot]` | `@experance-dev/worker-robin` |
| **Test** | `bluesky-pippa` | `bluesky-pippa[bot]` | `@experance-dev/worker-pippa` |
| **Test** | `bluesky-wren` | `bluesky-wren[bot]` | `@experance-dev/worker-wren` |
| **Doc writer** | `bluesky-marlowe` | `bluesky-marlowe[bot]` | `@experance-dev/worker-marlowe` |
| **Doc writer** | `bluesky-lyric` | `bluesky-lyric[bot]` | `@experance-dev/worker-lyric` |
| **Doc writer** | `bluesky-astrid` | `bluesky-astrid[bot]` | `@experance-dev/worker-astrid` |
| **Design Team** | `bluesky-vista` | `bluesky-vista[bot]` | `@experance-dev/worker-vista` |
| **Design Team** | `bluesky-nova` | `bluesky-nova[bot]` | `@experance-dev/worker-nova` |
| **Design Team** | `bluesky-scarlet` | `bluesky-scarlet[bot]` | `@experance-dev/worker-scarlet` |
| **Design Team** | `bluesky-helix` | `bluesky-helix[bot]` | `@experance-dev/worker-helix` |
| **Design Team** | `bluesky-ezra` | `bluesky-ezra[bot]` | `@experance-dev/worker-ezra` |
| **Design Team** | `bluesky-tally` | `bluesky-tally[bot]` | `@experance-dev/worker-tally` |
| **Design Team** | `bluesky-quill` | `bluesky-quill[bot]` | `@experance-dev/worker-quill` |
| **Design Team** | `bluesky-beacon` | `bluesky-beacon[bot]` | `@experance-dev/worker-beacon` |
| **Admin** | `bluesky-otto` | `bluesky-otto[bot]` | `@experance-dev/worker-otto` |
| **Admin** | `bluesky-mira` | `bluesky-mira[bot]` | `@experance-dev/worker-mira` |
| **QA** | `bluesky-echo` | `bluesky-echo[bot]` | `@experance-dev/worker-echo` |
| **QA** | `bluesky-vera` | `bluesky-vera[bot]` | `@experance-dev/worker-vera` |
| **QA** | `bluesky-marlo` | `bluesky-marlo[bot]` | `@experance-dev/worker-marlo` |
| **QA** | `bluesky-argus` | `bluesky-argus[bot]` | `@experance-dev/worker-argus` |
| **QA** | `bluesky-saba` | `bluesky-saba[bot]` | `@experance-dev/worker-saba` |
| **QA** | `bluesky-verity` | `bluesky-verity[bot]` | `@experance-dev/worker-verity` |

**Worker Apps commit; they do not satisfy the required-reviewer gate.** Only
Tier B Apps count toward `required_reviewers` on the develop → UAT → main
ruleset. A worker can open a PR and self-comment, but cannot approve it.

### 7.5 Provisioning runbook — bash for-loops

David runs this once per org. Each App takes ~30 seconds via the `gh` CLI;
~30 min total for all 27. Workflow per App:

1. Create the App (interactive, browser-confirmation required by GitHub —
   `gh api` cannot create Apps from scratch; we use the GH UI for the App
   manifest, then capture the App ID + private key).
2. Install the App on `experance-dev/blue_sky`.
3. Create the wrapping single-member team.
4. Add the App's bot user to that team.
5. Store App ID + private key as repo secrets.

**Step 1 (App creation) — manifest-flow approach.** GitHub's UI accepts a
JSON manifest at `https://github.com/organizations/experance-dev/settings/apps/new`
and pre-fills the App. We generate one manifest per tier, then create-from-
manifest 27 times. Manifest templates live in `.github/app-manifests/` (to
be added by Atlas once provisioning starts). David clicks "Create GitHub App
from manifest" once per slug — the manifest carries the permission shape so
there's no per-App permission-checkbox dance.

**Steps 2–4 (install + team + member)** — fully scriptable. Driving arrays:

```bash
# Tier A — orchestrators
TIER_A=(atlas reeve)

# Tier B — reviewers (already in place; here for completeness)
TIER_B=(sage iris magnus)

# Tier C — workers
TIER_C=(
  dash
  boomer tex finn
  coda kit robin
  pippa wren
  marlowe lyric astrid
  vista nova scarlet helix ezra tally quill beacon
  otto mira
  echo vera marlo argus saba verity
)
```

**Create the single-member teams** (after Apps exist + IDs captured):

```bash
ORG=experance-dev

# Tier A — orchestrator-<slug>
for slug in "${TIER_A[@]}"; do
  gh api -X POST orgs/$ORG/teams \
    -f name="orchestrator-$slug" \
    -f description="Single-member wrapper for bluesky-$slug[bot]" \
    -f privacy=closed
done

# Tier B — reviewer-<slug>
for slug in "${TIER_B[@]}"; do
  gh api -X POST orgs/$ORG/teams \
    -f name="reviewer-$slug" \
    -f description="Single-member wrapper for bluesky-$slug[bot]" \
    -f privacy=closed
done

# Tier C — worker-<slug>
for slug in "${TIER_C[@]}"; do
  gh api -X POST orgs/$ORG/teams \
    -f name="worker-$slug" \
    -f description="Single-member wrapper for bluesky-$slug[bot]" \
    -f privacy=closed
done
```

**Grant each team Read on `blue_sky`** (sufficient for Tier B; Tier A/C
get their write authority from their installation token, not from team
permissions — Read is fine):

```bash
REPO=blue_sky

for slug in "${TIER_A[@]}"; do
  gh api -X PUT orgs/$ORG/teams/orchestrator-$slug/repos/$ORG/$REPO -f permission=pull
done
for slug in "${TIER_B[@]}"; do
  gh api -X PUT orgs/$ORG/teams/reviewer-$slug/repos/$ORG/$REPO -f permission=pull
done
for slug in "${TIER_C[@]}"; do
  gh api -X PUT orgs/$ORG/teams/worker-$slug/repos/$ORG/$REPO -f permission=pull
done
```

**Add each App's bot user to its team.** The bot username is
`bluesky-<slug>[bot]`; GitHub stores it without the brackets for API calls:

```bash
# Adjust the prefix once on first App if GH uses a different shape
BOT_PREFIX=bluesky-

add_bot() {
  local team_kind=$1   # orchestrator | reviewer | worker
  local slug=$2
  local bot_login="${BOT_PREFIX}${slug}[bot]"   # verify exact shape on first run
  gh api -X PUT "orgs/$ORG/teams/${team_kind}-${slug}/memberships/${bot_login}"
}

for slug in "${TIER_A[@]}"; do add_bot orchestrator "$slug"; done
for slug in "${TIER_B[@]}"; do add_bot reviewer     "$slug"; done
for slug in "${TIER_C[@]}"; do add_bot worker       "$slug"; done
```

**Collect Team IDs for §6.4 Ruleset substitution** (Tier B only — those
are the required reviewers):

```bash
for slug in "${TIER_B[@]}"; do
  printf "reviewer-%s  team_id=%s\n" \
    "$slug" \
    "$(gh api orgs/$ORG/teams/reviewer-$slug --jq .id)"
done
```

### 7.6 Token flow + secret naming convention

**Per-App secrets, not per-tier.** Each App has its own private key — one
secret rotation = one App. Sharing a key across tier would defeat the
isolation-design.

**Storage recommendation: GitHub *organization* secrets** (not per-repo),
scoped to the `blue_sky` repository. 27 Apps × 2 secrets each = 54 secrets;
managing them at the org level avoids per-repo duplication once `blue_sky`
spawns sibling repos (which it will).

**Naming convention** — UPPERCASE, suffix indicates secret role:

| Secret name | Value |
| --- | --- |
| `APP_ID_<SLUG>` | App's numeric ID (integer) |
| `APP_PRIVATE_KEY_<SLUG>` | Full PEM contents of the private key |

Examples:

- `APP_ID_ATLAS` / `APP_PRIVATE_KEY_ATLAS`
- `APP_ID_SAGE` / `APP_PRIVATE_KEY_SAGE`
- `APP_ID_BOOMER` / `APP_PRIVATE_KEY_BOOMER`
- … (27 pairs)

**Why not per-tier shared secrets:** if Tier C shared one App, that App's
commit history would lose attribution (everyone shows as `bluesky-workers[bot]`)
and rotation would re-key 22 agents at once. The per-App design is the
whole point.

**Workflow consumption** — `actions/create-github-app-token@v1` (GitHub-
official; preferred over `tibdex/github-app-token`):

```yaml
- name: Mint Sage installation token
  id: sage-token
  uses: actions/create-github-app-token@v1
  with:
    app-id: ${{ secrets.APP_ID_SAGE }}
    private-key: ${{ secrets.APP_PRIVATE_KEY_SAGE }}

- name: Sage posts approval
  env:
    GH_TOKEN: ${{ steps.sage-token.outputs.token }}
  run: |
    gh api -X POST \
      repos/${{ github.repository }}/pulls/${{ github.event.pull_request.number }}/reviews \
      -f event=APPROVE \
      -f body="Sage security review — see workflow run for findings."
```

Tokens are valid for ~1 hour, scoped to the App's installation, and cannot
be replayed against other repos in the org or escalated.

### 7.7 Honest pre-flight unknowns

Flagged for verification once the first Apps from each tier are installed:

1. **Does an App's `event: APPROVE` count toward CODEOWNERS satisfaction
   when the bot is the sole member of a code-owner team?** Empirically the
   GitHub UI shows `[bot]` approvals as legitimate codeowner approvals when
   the bot is a team member — verify on first run by adding `bluesky-magnus[bot]`'s
   team to `/docs/standards/` and watching whether a Magnus App approval
   satisfies the codeowner-review gate.
2. **Stale review dismissal on bot approvals.** `dismiss_stale_reviews_on_push`
   should dismiss bot approvals identically to user approvals; verify by
   force-pushing after a bot approval.
3. **Fork PRs.** GitHub Apps installed on the head repo do not run on PRs
   from external forks by default. `experance-dev/blue_sky` is private — no
   external forks expected; flag if posture changes.
4. **App user-ID vs Team-ID drift.** If a team's sole member changes (e.g.,
   App reinstalled with new bot user), the Ruleset still pins the Team, so
   it keeps working — but verify the bot is re-added to the team after any
   App reinstall.
5. **Exact bot-login string for `gh api … memberships/`.** Most GitHub API
   surfaces use `bluesky-<slug>[bot]` with the brackets URL-encoded; a few
   accept the bare slug. Verify on the first Tier A App and adjust the
   `add_bot` helper if needed.
6. **Org-secret scoping.** Confirm `experance-dev` is on a plan that supports
   organization secrets with per-repo scoping (Team plan and above; Free orgs
   are public-only). If not, fall back to repo-scoped secrets.
7. **Worker-App PR-approval ambiguity.** Worker Apps have `pull_requests:
   write` so they can comment on review threads. That permission also lets
   them *post* approvals — confirm the Ruleset only counts Tier B teams'
   approvals (it does, via the explicit `required_reviewers` shape pinning
   reviewer-sage/iris/magnus team-IDs), so a stray worker `APPROVE` posts
   but doesn't satisfy the gate. Belt-and-suspenders: workflows should never
   issue `event: APPROVE` from a worker App; restrict to `COMMENT` /
   `REQUEST_CHANGES`.

### 7.8 Rotation runbook (stub)

One App = one private key = one rotation cycle. Annual rotation cadence
(or immediately on suspected compromise). Per App:

1. Generate a new private key in the App's settings page (Apps support
   multiple active keys, so add-then-remove is zero-downtime).
2. Update the matching `APP_PRIVATE_KEY_<SLUG>` organization secret.
3. Trigger a smoke workflow run that mints a token with the new key and
   posts a non-approving comment to a sentinel PR.
4. Revoke the old key in the App's settings.
5. Log the rotation in `docs/operations/app-key-rotation.log` (to be
   created on first rotation): `<UTC-timestamp> | <slug> | <human-actor> | <reason>`.

**Bulk rotation** — `gh api` cannot generate App private keys (UI-only
operation per GitHub design). For all-27-at-once rotation, the bottleneck
is the GH UI clicks; budget ~1 hour. Recommend staggered rotation (one
tier per quarter) to avoid the bulk burden.

### 7.9 Verification commands David can run

```bash
ORG=experance-dev
REPO=blue_sky

# Confirm Apps are installed on the repo (one entry per App)
gh api /repos/$ORG/$REPO/installations 2>/dev/null \
  || gh api /repos/$ORG/$REPO/installation   # singular if only one App installed

# Confirm every team exists and has exactly one member
ALL_TEAMS=(
  $(printf 'orchestrator-%s\n' atlas reeve)
  $(printf 'reviewer-%s\n'     sage iris magnus)
  $(printf 'worker-%s\n'       dash boomer tex finn coda kit robin pippa wren \
                               marlowe lyric astrid vista nova scarlet helix \
                               ezra tally quill beacon otto mira echo vera \
                               marlo argus saba verity)
)
for t in "${ALL_TEAMS[@]}"; do
  echo "=== $t ==="
  gh api orgs/$ORG/teams/$t --jq '{id, name, slug}'
  gh api orgs/$ORG/teams/$t/members --jq '.[].login'
done

# Confirm the review-team Ruleset pins the three reviewer teams
gh api repos/$ORG/$REPO/rulesets \
  --jq '.[] | select(.name=="review-team-gate") | .id' \
  | xargs -I{} gh api repos/$ORG/$REPO/rulesets/{}
```

---

## 8. Sign-off

Owners of this protocol:
- **Dash Earnie** — DevOps, owns the mechanics (this doc, CODEOWNERS, workflows)
- **Magnus** — Standards canon, owns the gating posture
- **David Wood** — Sole approver on `main`, final authority on protocol changes

Changes to this file require: review-team review (Sage + Iris + Magnus
Apps) + David codeowner approval (no Atlas stand-in for protocol changes).

— Dash
