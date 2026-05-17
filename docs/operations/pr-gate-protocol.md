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
for the Ruleset shape; see [§7](#7-app-provisioning) for what David creates in
org settings.

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

### 4.1 Emergency direct push (David / Dash / Atlas)

Branch-protection rule lists David, Dash, and Atlas in the "Restrict who can
push to matching branches" allowlist for emergency direct-push to `develop` /
`UAT` / `main`. **Use is rare and audited.** Document every direct push in a
follow-up PR that backfills tests / standards review.

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
| Reviewer Apps not yet created | Rulesets can't pin reviewers until the Apps + single-member teams exist | David provisions per [§7](#7-app-provisioning); paste numeric Team IDs into §6.4 |
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
    "contexts": ["code-analyzer", "apex-test-run"]
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

### 7.1 What to create — one App per agent

Three GitHub Apps, each registered under the `experance-dev` organization:

| App name | Slug | Bot identity | Backing agent |
| --- | --- | --- | --- |
| BlueSky Sage Reviewer | `bluesky-sage` | `bluesky-sage[bot]` | Sage Cloudy (security) |
| BlueSky Iris Reviewer | `bluesky-iris` | `bluesky-iris[bot]` | Iris Ruth (product owner) |
| BlueSky Magnus Reviewer | `bluesky-magnus` | `bluesky-magnus[bot]` | Magnus (standards) |

**One App per agent**, not one umbrella App with three slugs. Reasons:
- Each App has a single bot identity — three reviewer bots = three Apps.
- Per-App installation tokens give per-agent least-privilege blast radius.
- Auditability — each App's PR-review history is its own activity stream.
- Per-App revocation: if Sage's logic goes off the rails, suspend the Sage
  App without touching Iris or Magnus.

### 7.2 Required permissions — least-privilege

Each App needs **only**:

| Permission | Level | Why |
| --- | --- | --- |
| Repository → Pull requests | **Read & write** | Post `event: APPROVE` reviews via `POST /repos/{o}/{r}/pulls/{n}/reviews` |
| Repository → Contents | **Read** | Fetch diff context for the review |
| Repository → Metadata | **Read** | Mandatory baseline (auto-included) |

No webhooks. No commit/push. No org-level permissions. No `administration`.
The Apps approve only — they never modify code or settings.

### 7.3 Installation

Install all three Apps **on the `experance-dev/blue_sky` repo only** (not
org-wide). Each App should have a private key downloaded and stored as a
GitHub Actions secret in the repo:

| Secret | Value |
| --- | --- |
| `SAGE_APP_ID` / `SAGE_APP_PRIVATE_KEY` | Sage App's numeric ID + PEM contents |
| `IRIS_APP_ID` / `IRIS_APP_PRIVATE_KEY` | Iris App's numeric ID + PEM contents |
| `MAGNUS_APP_ID` / `MAGNUS_APP_PRIVATE_KEY` | Magnus App's numeric ID + PEM contents |

### 7.4 Single-member Teams (Rulesets pinning workaround)

After Apps are installed on the repo, create three org Teams in
`experance-dev` and add **only the App's bot user** to each:

| Team | Slug | Member |
| --- | --- | --- |
| Reviewer — Sage | `reviewer-sage` | `bluesky-sage[bot]` (sole member) |
| Reviewer — Iris | `reviewer-iris` | `bluesky-iris[bot]` (sole member) |
| Reviewer — Magnus | `reviewer-magnus` | `bluesky-magnus[bot]` (sole member) |

Each Team's repo permission on `blue_sky`: **Read** (sufficient for posting
PR reviews; Apps' approval authority comes from the App's installation
token, not from the Team's repo permission).

Once Teams exist, fetch their numeric IDs and substitute into §6.4:

```bash
gh api orgs/experance-dev/teams/reviewer-sage   --jq .id
gh api orgs/experance-dev/teams/reviewer-iris   --jq .id
gh api orgs/experance-dev/teams/reviewer-magnus --jq .id
```

### 7.5 Token flow at action-time

Reviewer agents run inside GitHub Actions workflows (or equivalent CI).
Each workflow step that posts a review mints a short-lived installation
token using `actions/create-github-app-token@v1` (GitHub-official; preferred
over `tibdex/github-app-token`):

```yaml
- name: Mint Sage installation token
  id: sage-token
  uses: actions/create-github-app-token@v1
  with:
    app-id: ${{ secrets.SAGE_APP_ID }}
    private-key: ${{ secrets.SAGE_APP_PRIVATE_KEY }}

- name: Sage posts approval
  env:
    GH_TOKEN: ${{ steps.sage-token.outputs.token }}
  run: |
    gh api -X POST \
      repos/${{ github.repository }}/pulls/${{ github.event.pull_request.number }}/reviews \
      -f event=APPROVE \
      -f body="Sage security review — see workflow run for findings."
```

Tokens are valid for ~1 hour and scoped to the App's installation —
they cannot be replayed against other repos in the org or escalated.

### 7.6 Honest pre-flight unknowns

Flagged for verification once the first App is installed:

1. **Does an App's `event: APPROVE` count toward CODEOWNERS satisfaction?**
   Not applicable to our model — CODEOWNERS catches David + Atlas only, never
   Apps. But worth knowing for future path-specific routing if we ever want
   Sage to *also* be a path codeowner. (Empirically: GitHub UI shows
   `[bot]` approvals as legitimate codeowner approvals **when** the bot is a
   member of a code-owner team. Verify on first run.)
2. **Stale review dismissal on bot approvals.** `dismiss_stale_reviews_on_push`
   should dismiss bot approvals the same as user approvals; verify by force-pushing
   after a bot approval and checking the review status.
3. **Fork PRs.** GitHub Apps installed on the head repo do not run on PRs from
   external forks by default. We don't take external-fork PRs on
   `experance-dev/blue_sky` (private workspace), so not blocking; flag if posture
   changes.
4. **App user-ID vs Team-ID drift.** If a team's sole member changes (e.g.,
   App reinstalled with new bot user), the Ruleset still pins the Team, so it
   keeps working — but verify the bot is re-added to the team after any App
   reinstall.

### 7.7 Verification commands David can run

```bash
# Confirm the Apps are installed on the repo
gh api /repos/experance-dev/blue_sky/installation

# Confirm each team exists and has one member
for t in reviewer-sage reviewer-iris reviewer-magnus; do
  echo "=== $t ==="
  gh api orgs/experance-dev/teams/$t --jq '{id, name, slug}'
  gh api orgs/experance-dev/teams/$t/members --jq '.[].login'
done

# Confirm the Ruleset pins the three teams
gh api repos/experance-dev/blue_sky/rulesets \
  --jq '.[] | select(.name=="review-team-gate") | .id' \
  | xargs -I{} gh api repos/experance-dev/blue_sky/rulesets/{}
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
