# Runbook — Stuck `AsyncApexJob` (status `Processing`, all child items done)

When a queued/batchable/scheduled Apex job lingers in `Processing` state even though every child item has completed, **new submissions of the same class can silently queue but never fire**. This runbook is the triage-and-clear playbook.

Discovered 2026-05-14 by Dash on `dwood_z` — job `707WL0000CnMZx3YQG` had been `Processing` for ~38 hours with all 202 child items already `Completed`, silently blocking [PR #6](https://github.com/experance-dev/blue_sky/pull/6) test resubmissions. Cleared via `System.abortJob`.

Owner: Otto. Escalation: Atlas (see [Escalation](#escalation)).

## Symptom

What "stuck" looks like in the wild:

- An `AsyncApexJob` row sits at `Status = 'Processing'` long past its expected runtime.
- `JobItemsProcessed == TotalJobItems` (every child batch already finished).
- `CompletedDate` is `null`; `NumberOfErrors` is often `0`.
- New `Database.executeBatch` / `System.enqueueJob` / `System.schedule` submissions for the **same class** appear to succeed (return a Job Id) but the new job never moves out of `Holding` or `Queued` — or, in the batchable case, the next submission silently re-uses the stuck job slot.
- Tests / scheduled work depending on that class appear to "never run." No errors in Setup → **Apex Jobs**, no errors in the org email log.

The tell: a `Processing`-status job older than its expected wall-clock window with no in-flight child work to justify the state.

## Detect

Single SOQL — paste into Developer Console or `sf data query` against the target org:

```sql
SELECT Id, ApexClass.Name, Status, JobType, NumberOfErrors,
       JobItemsProcessed, TotalJobItems, CreatedDate, CompletedDate,
       CreatedBy.Username, ExtendedStatus
FROM AsyncApexJob
WHERE Status = 'Processing'
  AND CreatedDate < :Datetime.now().addHours(-1)
ORDER BY CreatedDate ASC
```

From the CLI:

```bash
sf data query --target-org dwood_z --query "SELECT Id, ApexClass.Name, Status, JobType, JobItemsProcessed, TotalJobItems, CreatedDate, CompletedDate, ExtendedStatus FROM AsyncApexJob WHERE Status = 'Processing' AND CreatedDate < LAST_N_DAYS:1 ORDER BY CreatedDate ASC"
```

Any row returned is a candidate for the triage tree below. Zero rows = no stuck jobs.

A broader sweep — anything still `Processing` or `Queued` longer than an hour, across all classes:

```sql
SELECT Id, ApexClass.Name, Status, JobItemsProcessed, TotalJobItems,
       CreatedDate, ExtendedStatus
FROM AsyncApexJob
WHERE Status IN ('Processing', 'Queued', 'Preparing', 'Holding')
  AND CreatedDate < :Datetime.now().addHours(-1)
ORDER BY CreatedDate ASC
```

## Triage tree

Decide **abort** vs **investigate** vs **wait** by walking these in order:

1. **Is `JobItemsProcessed == TotalJobItems` and the job is older than 1 hour?**
   → **Safe to abort.** All child work completed; the parent never flipped to `Completed`. This is the canonical "stuck" pattern. Skip to [Clear](#clear).
2. **Is `JobItemsProcessed < TotalJobItems` but the job is older than 4 hours with no recent `LastModifiedDate` movement?**
   → **Likely stuck.** Confirm by querying again 5 minutes later — if `JobItemsProcessed` does not advance, treat as stuck and abort. Then escalate to Atlas (a true long-running batch that died mid-flight is usually a code or governor-limit bug, not an org-state issue).
3. **Is `JobItemsProcessed < TotalJobItems` and the job is < 4 hours old, with the counter still moving between checks?**
   → **Wait.** The batch is genuinely running. Re-check in 15 minutes.
4. **Is `NumberOfErrors > 0` and `ExtendedStatus` populated with an error message?**
   → **Investigate first, then abort.** Read `ExtendedStatus`. If it's a transient platform error (`UNABLE_TO_LOCK_ROW`, `STORAGE_LIMIT_EXCEEDED`), capture the message, abort, and file the root cause with the class owner. If it's an Apex exception, escalate to the class owner before clearing — the trace may not survive the abort.
5. **Is the job a `ScheduledApex` (`JobType = 'ScheduledApex'`) in `Processing`?**
   → **Don't abort.** `ScheduledApex` parents stay `Processing` between fire-times by design. Look at the `CronTrigger` instead (see "Scheduled job sanity-check" below).

### Scheduled job sanity-check

If the stuck row is a scheduled-cron parent, check the cron itself, not the AsyncApexJob:

```sql
SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime,
       TimesTriggered
FROM CronTrigger
ORDER BY CronJobDetail.Name
```

`State = 'WAITING'` is healthy; `State = 'ERROR'` or a `NextFireTime` in the past means the schedule needs to be re-armed via `System.schedule` or via Setup → **Scheduled Jobs**.

## Clear

Open Developer Console → Debug → **Open Execute Anonymous Window**, paste, and run:

```apex
String stuckJobId = '707WL0000CnMZx3YQG'; // replace with the Id from your detect query
System.abortJob(stuckJobId);
System.debug('Aborted ' + stuckJobId);
```

Or from the CLI:

```bash
sf apex run --target-org dwood_z <<'APEX'
String stuckJobId = '707WL0000CnMZx3YQG';
System.abortJob(stuckJobId);
System.debug('Aborted ' + stuckJobId);
APEX
```

Verify it's gone:

```bash
sf data query --target-org dwood_z --query "SELECT Id, Status, CompletedDate FROM AsyncApexJob WHERE Id = '707WL0000CnMZx3YQG'"
```

Expected: `Status = 'Aborted'`, `CompletedDate` populated.

Resubmit whatever was blocked (the test run, the batch execute, the scheduled trigger). It should now fire normally.

### Mass-abort (rare)

If multiple stuck jobs are blocking the queue, abort them in a single anon-Apex shot — `Database.delete`-style, not-all-or-nothing-friendly:

```apex
List<AsyncApexJob> stuck = [
  SELECT Id
  FROM AsyncApexJob
  WHERE Status = 'Processing'
    AND CreatedDate < :Datetime.now().addHours(-4)
    AND JobItemsProcessed = TotalJobItems
];
for (AsyncApexJob j : stuck) {
  try {
    System.abortJob(j.Id);
    System.debug('Aborted ' + j.Id);
  } catch (Exception e) {
    System.debug('Could not abort ' + j.Id + ': ' + e.getMessage());
  }
}
System.debug('Attempted abort on ' + stuck.size() + ' job(s).');
```

The query filter `JobItemsProcessed = TotalJobItems` is the safety net — only jobs where every child item completed are eligible. Don't widen this filter without escalating to Atlas.

## Prevent

The right durable fix is a CI-side pre-flight that catches stuck jobs before resubmitting a test run. Folded into Dash's [PR #8](https://github.com/experance-dev/blue_sky/pull/8) workflow proposal as a follow-on:

**Recommended `apex-test-run.yml` addition** (paste into Dash's workflow before the `sf apex run test` step):

```yaml
- name: Pre-flight — abort stuck AsyncApexJobs in the scratch org
  run: |
    sf data query --target-org "$SCRATCH_ALIAS" --query \
      "SELECT Id FROM AsyncApexJob \
       WHERE Status = 'Processing' \
         AND JobItemsProcessed = TotalJobItems \
         AND CreatedDate < LAST_N_DAYS:1" \
      --json > stuck-jobs.json
    STUCK=$(jq -r '.result.records[].Id' stuck-jobs.json)
    if [ -n "$STUCK" ]; then
      echo "Found stuck jobs — aborting before test resubmit:"
      echo "$STUCK"
      for ID in $STUCK; do
        sf apex run --target-org "$SCRATCH_ALIAS" <<APEX
    System.abortJob('$ID');
    APEX
      done
    else
      echo "No stuck jobs."
    fi
```

Since CI scratches are ephemeral (`ci-<runId>`), stuck jobs are unlikely to survive across runs — but for `dwood_z`-style persistent sandboxes, this guard is the right belt-and-suspenders.

Also worth doing in any sandbox where this happens twice: schedule a weekly `AsyncApexJob` sweep via a small scheduled class that runs the [Detect](#detect) query and emails Otto if any rows return. Not built today — propose to Atlas if recurrence rate justifies it.

## Escalation

| Trigger                                                           | Action                                                                                                                                                                                                      |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Single stuck job, `JobItemsProcessed == TotalJobItems`, no errors | **Otto clears.** Document the job Id + class name in the ticket; close.                                                                                                                                     |
| Stuck job with `NumberOfErrors > 0` or populated `ExtendedStatus` | **Otto clears after capture.** File the error trace with the class owner (Boomer / Coda / class-specific).                                                                                                  |
| **Multiple stuck jobs per day** across different classes          | **Escalate to Atlas.** This is a system-level / platform-side issue (org-pod health, governor pressure, async-resource exhaustion), not org-state. Atlas decides whether to open a Salesforce support case. |
| Stuck job is a `ScheduledApex` parent                             | **Don't clear; investigate the `CronTrigger`.** Loop in the class owner.                                                                                                                                    |
| Same class produces a stuck job more than once in 30 days         | **Escalate to Boomer / Coda** (whoever owns the class). The class has a defect — probably an uncaught exception in `finish()` or a governor-limit cliff in `execute()`.                                     |

## Change log

| Date       | Author | Change                                                                                  |
| ---------- | ------ | --------------------------------------------------------------------------------------- |
| 2026-05-16 | Otto   | Initial entry — triggered by Dash's 2026-05-14 `707WL0000CnMZx3YQG` clear on `dwood_z`. |

---

**Summary:** detect via SOQL (`Status='Processing' AND JobItemsProcessed=TotalJobItems AND CreatedDate < LAST_N_DAYS:1`), abort via `System.abortJob('<id>')` in anon Apex, prevent via a CI pre-flight in [`apex-test-run.yml`](https://github.com/experance-dev/blue_sky/pull/8). Otto first-pass; Atlas when recurrence suggests platform-level health.

— Otto
