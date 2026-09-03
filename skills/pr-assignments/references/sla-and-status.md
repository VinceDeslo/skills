# SLA, status, and ranking rules

Reference for the priority math and the status vocabulary. Read this before ranking or filling the
template.

## The review clock

GitHub pull requests have no due date, so the skill derives one. The clock starts when the review
landed on the user, taken from `clock.requestedAt` in the fetch output, resolved in this order:

1. The most recent `ReviewRequestedEvent` naming the user directly — `source: direct-request`.
2. The most recent `ReviewRequestedEvent` naming a team the user belongs to — `source: team-request:<slug>`.
3. The `ReadyForReviewEvent`, for a PR that sat in draft — `source: ready-for-review`.
4. The PR's `createdAt`, as a last resort — `source: pr-opened`.

A re-request resets the clock: only the latest matching event counts. A PR whose source is
`pr-opened` has a weaker claim to its position — say so in the PR's signals line.

## The budget

- **2 business days** to review → the due date.
- **4 business days** → the overdue threshold.

Business days exclude Saturday and Sunday. Do not attempt holiday calendars; they vary by person
and the extra precision buys nothing. Count from the calendar date of `requestedAt` in the local
timezone.

**Slack** = due date − today, in business days.

| Slack | State | `DUE_LABEL` | Lane class |
| --- | --- | --- | --- |
| ≤ −2 business days past the overdue threshold | overdue | `OVERDUE 6D` | `lane-overdue` |
| past the overdue threshold | overdue | `OVERDUE 2D` | `lane-overdue` |
| 0 | due today | `DUE TODAY` | `lane-due` |
| −1 to the overdue threshold | due | `DUE 1D AGO` | `lane-due` |
| 1 | due tomorrow | `DUE TOMORROW` | `lane-due` |
| ≥ 2 | in budget | `2D LEFT` | `lane-ok` |

Ranking within "Awaiting your review" is slack ascending — the most negative first. Break ties, in
order, by: CI failing before CI green (a red PR needs the author sooner), then larger `changedFiles`
first, then older `createdAt`.

Draft PRs always sort last in their section regardless of slack, and carry a `draft` badge. Their
clock is real but nobody is blocked on a draft.

## Review status

From `myReview` and `lastCommitAt`:

| Condition | `REVIEW_LABEL` | Badge class | Section |
| --- | --- | --- | --- |
| `myReview` is null | `NOT REVIEWED` | `rev-none` | Awaiting your review |
| `myReview.latestState` is `APPROVED` or `CHANGES_REQUESTED`, and `lastCommitAt` > `myReview.latestAt` | `RE-REVIEW: NEW COMMITS` | `rev-stale` | Awaiting your review |
| `myReview.latestState` is `COMMENTED` only | `COMMENTED, NOT SIGNED OFF` | `rev-stale` | Awaiting your review |
| `myReview.latestState` is `APPROVED`, no commits since | `APPROVED BY YOU` | `rev-done` | Already reviewed by you |
| `myReview.latestState` is `CHANGES_REQUESTED`, no commits since | `CHANGES REQUESTED BY YOU` | `rev-done` | Already reviewed by you |

A PR that reached the fetch output while `myReview` is non-null and `stillRequested` is true was
re-requested — that is exactly the `RE-REVIEW` case, and it belongs in the top section with a live
clock.

## CI status

From the `ci` object, which reads the status check rollup of the head commit.

| `ci.rollup` | `CI_LABEL` | Badge class |
| --- | --- | --- |
| `SUCCESS` | `CI GREEN` | `ci-pass` |
| `FAILURE` or `ERROR` | `CI FAILING (n)` — n = `failing` length | `ci-fail` |
| `PENDING` | `CI RUNNING (n)` — n = `pending` length | `ci-pending` |
| `EXPECTED` | `CI QUEUED` | `ci-pending` |
| `NONE` or absent | `NO CHECKS` | `ci-none` |

`ci.rollup` is `NONE` when the head commit has no checks at all — common on very old PRs whose
workflows have since been deleted. That is not a failure; label it `NO CHECKS` and note the staleness
in the signals line.

`CI_DETAIL` names the failing or pending checks: `Failing: <code>build</code>, <code>test (go 1.24)</code>`.
When CI is green, `CI_DETAIL` is `All {{n}} checks green.` and when there are none, delete the CI
label and paragraph from that PR's body.

## Signals line

One or two sentences of triage context that is not already a badge. Draw only on what the fetch
output supports. Candidates, most useful first:

- Author is a bot (`dependabot[bot]`, `renovate[bot]`) and the PR is a dependency bump — say so, it
  changes how much reading it needs.
- The clock source was `pr-opened` or `team-request` rather than a direct request.
- `reviewDecision` is `APPROVED` already — someone else signed off, so the user's review may be
  redundant.
- Unresolved review threads outnumber resolved ones.
- `lastCommitAt` is far older than `updatedAt` — the conversation moved but the code did not.
- The PR is very large (`changedFiles` above ~30) and will not be a quick review.

Skip the line entirely when there is nothing true and useful to put in it — delete the label and
paragraph rather than writing "nothing notable".
