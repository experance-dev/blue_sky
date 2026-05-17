# PR Gate Protocol — `experance-dev/blue_sky`

Authoritative protocol for how pull requests get merged in this repo. Mirrors
the shape of [`experance-dev/fosfoundry`](https://github.com/experance-dev/fosfoundry)'s
gate, adapted for the Zelis Engagement Attribution engagement.

> **TL;DR** — every PR needs **3 review-team reviews + 1 codeowner approval + green status checks**.
> Review team (parallel, required-reviewers via branch protection): Sage (security), Iris (PO), Magnus (standards).
> Codeowners (this file's [`.github/CODEOWNERS`](../../.github/CODEOWNERS) gate): David (preferred) or Atlas (peer codeowner; logs every stand-in approval).

---

## 1. Gate model

**Codeowner ≠ reviewer.** Two independent gates, both required:

1. **CODEOWNERS gate** — substantive approval identity (David or Atlas)
2. **Review-team gate** — substantive review by Sage + Iris + Magnus

The review team gives *substantive review* (security, business-fit, standards).
The codeowner gives *final approval identity* — the signoff that says "this
ships." Branch protection enforces both.

### 1.1 Review team — 3 required, parallel

Enforced via branch protection's `required_pull_request_reviews`
settings (NOT via CODEOWNERS).

| Reviewer | Role | Scope |
| --- | --- | --- |
| **Sage Cloudy** | Security | Sharing, permsets, custom permissions, auth, FLS/CRUD, OWD-Private posture, HIPAA-perimeter design |
| **Iris Ruth** | Product Owner | Business-fit, persona acceptance, gate-1 spec adherence, gate-2 delivery |
| **Magnus** | CTA / Standards | [`docs/standards/sf-best-practices.md`](../standards/sf-best-practices.md) compliance, architecture, scanner severity, code-canon decisions |

All three review **in parallel**. Branch protection requires 3 reviews
total; the reviewer identities are pinned by the team membership when GH
accounts land.

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
| Iris Ruth has no GH account | Branch protection can only require Sage + Magnus as named reviewers | Provision Iris account; update branch-protection reviewer config |
| Other persona handles unconfirmed | Reviewer-team handles + Atlas codeowner handle won't resolve | Coordinate with Sharp Kai for canonical roster |
| `code-analyzer` + `apex-test-run` not yet required checks | CI runs but doesn't gate | Land [PR #8](https://github.com/experance-dev/blue_sky/pull/8), then add via §6 commands |

---

## 6. `gh api` commands David runs

> Replace `@<placeholder>` handles with real ones before executing.

### 6.0 How the two gates map to the GitHub API

Classic branch-protection's `required_pull_request_reviews` accepts a single
integer (`required_approving_review_count`) and one boolean
(`require_code_owner_reviews`). It does **not** natively let you pin
"reviewer X, Y, Z by name." Named-reviewer enforcement comes from two
mechanisms:

1. **CODEOWNERS** + `require_code_owner_reviews: true` → enforces named
   approval from the codeowner identities for files they own. We use this
   for the **codeowner gate (David + Atlas)** — the entire repo's catch-all
   line in [`.github/CODEOWNERS`](../../.github/CODEOWNERS) is `@david-wood @atlas`.
2. **Repository Rulesets** (newer API,
   [`POST /repos/{owner}/{repo}/rulesets`](https://docs.github.com/en/rest/repos/rules)) — support
   a `required_reviewers` clause that pins specific bypass / approval
   identities by name. We use this for the **review-team gate (Sage + Iris +
   Magnus)**.

The interim until Rulesets land: the integer count is set to 4 (3 review
team + 1 codeowner) and Sage/Iris/Magnus are auto-requested as reviewers
by a workflow (TODO: `.github/workflows/auto-request-reviewers.yml`).
Reviewer identity is enforced manually until Rulesets ship.

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

### 6.4 Review-team gate via Repository Ruleset — Sage + Iris + Magnus by name

[`POST /repos/{owner}/{repo}/rulesets`](https://docs.github.com/en/rest/repos/rules)
ships named-reviewer enforcement that classic branch protection can't.
This Ruleset applies to `develop` + `UAT` and requires Sage, Iris, and
Magnus by ID before merge. Run **once** per environment after the GH
accounts are provisioned and you have their numeric user IDs (look them up
with `gh api users/<handle> --jq .id`).

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
          { "id": "<sage-user-id>",   "type": "User" },
          { "id": "<iris-user-id>",   "type": "User" },
          { "id": "<magnus-user-id>", "type": "User" }
        ]
      }
    }
  ]
}
JSON
```

The Ruleset's `required_approving_review_count: 3` + named reviewers
satisfies the review-team gate (Sage + Iris + Magnus, each by identity).
The branch-protection's count-of-4 in §6.1 / §6.2 sums review-team (3) +
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

## 7. Sign-off

Owners of this protocol:
- **Dash Earnie** — DevOps, owns the mechanics (this doc, CODEOWNERS, workflows)
- **Magnus** — Standards canon, owns the gating posture
- **David Wood** — Sole approver on `main`, final authority on protocol changes

Changes to this file require: review-team review (Sage + Iris + Magnus) +
David codeowner approval (no Atlas stand-in for protocol changes).

— Dash
