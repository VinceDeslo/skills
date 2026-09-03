# SLA, status, and ranking rules

Reference for the priority math and the status vocabulary. Read this before ranking or filling the
template.

## The window

Only PRs whose review clock started inside the window are in the queue at all — 14 days by default.
The fetch enforces it twice: `updated:>=<cutoff>` at the search level (a review request bumps
`updatedAt`, so this is a safe superset), then a hard drop on `clock.requestedAt` in the normalizer.

A request older than the window is a stale-PR problem, not a queue item. Widen the window only on
request, and say which window produced the report.

## Origin: direct vs. team

`origin` decides the section, and it outranks the clock: a direct request inside its budget still
sorts above an overdue team request.

- **`direct`** — the user is a pending reviewer by name, or the latest matching
  `ReviewRequestedEvent` named them. Nobody else can absorb it.
- **`team`** — the request names a team the user belongs to, listed in `originTeams`. Any teammate
  can take it.
- **`unattributed`** — neither resolved. Goes in the team section, with the ambiguity stated in the
  signals line.

The current `reviewRequests` list is checked before the timeline: a re-request that replaced a team
request with a direct one should read as `direct`, and only the live state shows that.

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

Ranking **within a section** is slack ascending — the most negative first. Break ties, in order, by:
CI failing before CI green (a red PR needs the author sooner), then larger `changedFiles` first,
then older `createdAt`. Slack never moves a PR across the direct/team boundary.

Draft PRs always sort last in their section regardless of slack, and carry a `draft` badge. Their
clock is real but nobody is blocked on a draft.

## Review status

From `myReview` and `lastCommitAt`:

| Condition | `REVIEW_LABEL` | Badge class | Section |
| --- | --- | --- | --- |
| `myReview` is null | `NOT REVIEWED` | `rev-none` | direct or team, by `origin` |
| `myReview.latestState` is `APPROVED` or `CHANGES_REQUESTED`, and `lastCommitAt` > `myReview.latestAt` | `RE-REVIEW: NEW COMMITS` | `rev-stale` | direct or team, by `origin` |
| `myReview.latestState` is `COMMENTED` only | `COMMENTED, NOT SIGNED OFF` | `rev-stale` | direct or team, by `origin` |
| `myReview.latestState` is `APPROVED`, no commits since | `APPROVED BY YOU` | `rev-done` | Already reviewed by you |
| `myReview.latestState` is `CHANGES_REQUESTED`, no commits since | `CHANGES REQUESTED BY YOU` | `rev-done` | Already reviewed by you |

A PR that reached the fetch output while `myReview` is non-null and `stillRequested` is true was
re-requested — that is exactly the `RE-REVIEW` case, and it belongs in its origin's section with a
live clock, not in "Already reviewed by you".

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
- The clock source was `pr-opened` or `ready-for-review` rather than an actual request event, which
  makes the position weaker than it looks.
- `origin` is `unattributed`, or the origin disagrees with `clock.source` — a team request later
  narrowed to a direct one, say.
- `reviewDecision` is `APPROVED` already — someone else signed off, so the user's review may be
  redundant.
- Unresolved review threads outnumber resolved ones.
- `lastCommitAt` is far older than `updatedAt` — the conversation moved but the code did not.
- The PR is very large (`changedFiles` above ~30) and will not be a quick review.

Skip the line entirely when there is nothing true and useful to put in it — delete the label and
paragraph rather than writing "nothing notable".
