# PR Gate Protocol — `experance-dev/blue_sky`

Authoritative protocol for how pull requests get merged in this repo. Mirrors
the shape of [`experance-dev/fosfoundry`](https://github.com/experance-dev/fosfoundry)'s
gate, adapted for the Zelis Engagement Attribution engagement.

> **TL;DR** — every PR needs **3 reviewers + 1 approver + green status checks**.
> Reviewers (parallel): Sage (security), Iris (PO), Magnus (standards).
> Approvers: David (always) or Atlas (only on `develop` / `UAT`, with audit-log entry).

---

## 1. Gate model

### 1.1 Reviewer tier — 3 required, parallel

| Reviewer | Role | Scope |
| --- | --- | --- |
| **Sage Cloudy** | Security | Sharing, permsets, custom permissions, auth, FLS/CRUD, OWD-Private posture, HIPAA-perimeter design |
| **Iris Ruth** | Product Owner | Business-fit, persona acceptance, gate-1 spec adherence, gate-2 delivery |
| **Magnus** | CTA / Standards | [`docs/standards/sf-best-practices.md`](../standards/sf-best-practices.md) compliance, architecture, scanner severity, code-canon waiver decisions |

All three review **in parallel**. Required by [`.github/CODEOWNERS`](../../.github/CODEOWNERS).

### 1.2 Approver tier — 1 of 2 required

| Approver | When |
| --- | --- |
| **David Wood** (`@davidatexperance`) | Always eligible. Required on PRs targeting `main`. |
| **Atlas** | Stand-in for David on PRs targeting `develop` or `UAT` **only**. Records each approval in [`atlas-standin-approvals.log`](atlas-standin-approvals.log). |

The approval gate is **OR** — either David or (where eligible) Atlas signs.

### 1.3 Status checks — required green

- `code-analyzer` — `sf code-analyzer run` SPOTLESS gate ([§12.1 of standards](../standards/sf-best-practices.md))
- `apex-test-run` — `RunLocalTests` against `dwood_z` with canon-aware failure handling
- (added when [PR #8](https://github.com/experance-dev/blue_sky/pull/8) lands; workflow files at [`.github/workflows/code-analyzer.yml`](../../.github/workflows/code-analyzer.yml) and [`.github/workflows/apex-test-run.yml`](../../.github/workflows/apex-test-run.yml))

### 1.4 Merge action

Once **3 reviews + 1 approval + all status checks** are green, **anyone with
write access** can click merge. David may choose to be sole merger as preference;
that's not a hard rule.

---

## 2. When Atlas stands in vs waits for David

Per [`feedback_atlas_verifies_before_uat`](https://docs.local/feedback) — Atlas
approves on David's behalf **only when** he has personally verified the work
meets the David-review bar. If Atlas is unsure, the PR waits for David.

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

Every Atlas stand-in approval **must** be logged. See
[`atlas-standin-approvals.log`](atlas-standin-approvals.log). Format:

```
2026-05-16T22:30:00Z | PR #6 | feature/engagement-attribution → develop | Atlas approved on David's behalf | Reason: <reason> | David away: <timestamp range or "after-hours">
```

Atlas commits the log row in the same PR he approves (or a follow-up PR if the
log write fails the protection rule). David greps the log periodically.

---

## 3. Branch model

Three permanent boxes (per [`feedback_branch_strategy`](https://docs.local/feedback)):

| Branch | Purpose | Approver | Atlas may stand in? |
| --- | --- | --- | --- |
| `main` | Production | David only | No |
| `UAT` | Pre-prod / Verity gate | David or Atlas | Yes (with audit log) |
| `develop` | Integration | David or Atlas | Yes (with audit log) |

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

- [`.github/CODEOWNERS`](../../.github/CODEOWNERS) — reviewer-tier enforcement
- [`docs/operations/pr-gate-protocol.md`](pr-gate-protocol.md) — this file
- [`docs/operations/atlas-standin-approvals.log`](atlas-standin-approvals.log) — Atlas approval audit log

### 5.2 What David must apply via `gh api` / repo Settings UI

Branch-protection rules cannot be set from a PR. David runs these (or his
admin equivalent) once handles are confirmed. **Replace `@<handle>`
placeholders first.** See §6 for the exact `gh api` commands.

### 5.3 Known gaps

| Gap | Impact | Resolution |
| --- | --- | --- |
| Iris Ruth has no GH account | Branch protection can only require Sage + Magnus | Provision Iris account; update CODEOWNERS |
| Other persona handles unconfirmed | CODEOWNERS placeholders won't resolve | Coordinate with Sharp Kai for canonical roster |
| `code-analyzer` + `apex-test-run` not yet required checks | CI runs but doesn't gate | Land [PR #8](https://github.com/experance-dev/blue_sky/pull/8), then add via §6 commands |

---

## 6. `gh api` commands David runs

> Replace `@<placeholder>` handles with real ones before executing. These mirror
> the [fosfoundry development branch protection](https://github.com/experance-dev/fosfoundry/settings/branches)
> shape (1 review + status checks), extended to 3 reviewers + code-owner enforcement.

### 6.1 `develop` — 3 reviewers, Atlas may approve

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
    "users": ["davidatexperance", "dash-earnie", "atlas"],
    "teams": [],
    "apps": []
  },
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

Count = 4 because GitHub's `required_approving_review_count` is a single
integer that bundles reviewer-tier and approver-tier together (3 reviewers
+ 1 approver = 4). The reviewer-tier identities are pinned by CODEOWNERS
+ `require_code_owner_reviews: true`; the +1 is satisfied by David or Atlas
manually clicking Approve.

### 6.2 `UAT` — identical to develop

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
    "users": ["davidatexperance", "dash-earnie", "atlas"],
    "teams": [],
    "apps": []
  },
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

### 6.3 `main` — David explicit, Atlas excluded from approver tier

Branch protection cannot encode *"David but not Atlas"* directly — both have
write access. The hard rule lives in the protocol (§1.2, §2). Mechanical
protection is identical to develop/UAT plus `enforce_admins: true` and a
tighter push allowlist:

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
    "users": ["davidatexperance"],
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

### 6.4 Verifying

```bash
for b in main UAT develop; do
  echo "=== $b ==="
  gh api repos/experance-dev/blue_sky/branches/$b/protection
done
```

---

## 7. Sign-off

Owners of this protocol:
- **Dash Earnie** — DevOps, owns the mechanics (this doc, CODEOWNERS, workflows)
- **Magnus** — Standards canon, owns the gating posture
- **David Wood** — Sole approver on `main`, final authority on protocol changes

Changes to this file require: CODEOWNERS review (Sage + Iris + Magnus) +
David approval (no Atlas stand-in for protocol changes).

— Dash
