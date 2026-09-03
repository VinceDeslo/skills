---
name: pr-assignments
description: Crawl every open GitHub pull request whose review is requested from the authenticated user, summarize each one in a line, recap its comment conversation, and rank them by review-SLA expiry — unreviewed and most overdue first — into a self-contained HTML report in a reboot-cleared temp directory. Strictly read-only, GitHub CLI reads only. Use when asked what PRs are assigned to me, what is waiting on my review, to triage a review queue or review backlog, or when the user says "pr-assignments".
compatibility: Requires the GitHub CLI (`gh`) authenticated with `repo` and `read:org` scopes, `bash`, and network access. Optional — a browser opener (`open`, `xdg-open`, or `start`) to display the report.
---

# pr-assignments

Answer one question: **what is waiting on my review, and what is late?**

Three properties define this skill:

- **Read-only, `gh` only.** Every call is a GitHub API read. The skill posts no comment, submits no
  review, sets no label, clones nothing, and touches no working tree. `gh` is the only tool used to
  reach GitHub — no `git`, no `curl`, no web fetch, no other API client.
- **In-session.** You do the whole pass yourself. No subagents, no delegation.
- **Triage, not review.** The output tells the user which PR to open next and why. It does not
  critique the code — for that, hand the PR to the `pr-digest` skill.

## When to use

The user asks what PRs are assigned to them, what is waiting on their review, for a review queue or
backlog triage, or says "pr-assignments". No argument is needed; an optional cap on how many PRs to
fetch is the only input.

For reviewing one specific PR, use `pr-digest` instead.

## Instructions

### 1. Fetch the queue

One script does the whole crawl and prints a normalized JSON array on stdout:

```bash
skill_dir=<this skill's directory>
out="${TMPDIR:-/tmp}/temp_assignments"
mkdir -p "$out"
"$skill_dir/scripts/fetch-assignments.sh" 40 > "$out/queue.json"
```

The argument is the per-query result cap (default 40). It collects the union of
`review-requested:@me` and `team-review-requested:<org>/<team>` for every team the user belongs to,
de-duplicates on `repo#number`, then runs one GraphQL read per PR.

Each record carries: `repo`, `number`, `url`, `title`, `author`, `isDraft`, `state`,
`reviewDecision`, `createdAt`, `updatedAt`, `size`, `branches`, `labels`, a truncated `body`,
`clock` (`requestedAt` plus `source`), `stillRequested`, `myReview`, `otherReviews`, `lastCommitAt`,
`ci` (`rollup`, `total`, `failing`, `pending`), `issueComments`, and `reviewThreads`.

Read the JSON. If the array is empty, stop here and say the review queue is clear — do not render an
empty report.

If the script reports an authentication failure, stop and say what is needed. If it emits
`warn: could not fetch <repo>#<n>` lines, those PRs are missing from the array — usually a repo the
token cannot read — and the count must be named in the methodology note.

### 2. Rank

Read [references/sla-and-status.md](references/sla-and-status.md) for the clock, the budget, the
slack table, and the exact status vocabulary. Then, for every PR:

- Compute slack in business days from `clock.requestedAt` against a 2-business-day review budget and
  a 4-business-day overdue threshold, and derive `DUE_LABEL` plus the lane class.
- Derive `REVIEW_LABEL` from `myReview` and `lastCommitAt`, and with it the section the PR belongs
  in — anything not signed off goes in **Awaiting your review**.
- Derive `CI_LABEL` from `ci.rollup`.

Sort **Awaiting your review** by slack ascending, most overdue first, with the documented
tie-breaks. Drafts sort last in their section. Sort **Already reviewed by you** by `updatedAt`
descending.

Do the date arithmetic against today's real date. Never infer "now" from the newest `updatedAt` in
the data.

### 3. Write the one-liner

Every PR gets exactly one sentence, from its `title` and `body`, saying what the change does — not
what it touches. Under ~140 characters.

- Good: `Adds mappingConfidence to the finding-created event so we can tell which findings trace back to a source file.`
- Bad: `Changes 9 files in the API and web packages.` — that is the size field's job.
- Bad: `This PR adds a new feature.` — says nothing.

Bot dependency bumps get the shape of the bump, not the list: `Bumps 171 dev dependencies in /api, security patches included.`

A body that is a template with nothing filled in, or empty, gets `No description — the title is all
there is.` Do not invent intent that the PR does not state.

Strip PR-template boilerplate, checklists, bot linkbacks, and Linear/issue linkback blocks before
summarizing; they are noise, and `body` arrives truncated so do not treat a cut-off body as complete.

### 4. Recap the conversation

Two or three sentences per PR covering `issueComments`, `otherReviews`, and `reviewThreads`
together. Say what was actually discussed and where it landed — the state of the argument, not a
transcript.

- Attribute by login in `<code>`: `<code>aliscott</code> asked whether the retry budget is shared…`
- Say where it landed: agreed, unresolved, awaiting the author, or answered.
- Exclude bot noise — linkback comments, CI status comments, coverage bots, and automated review
  summaries are not conversation. If every comment is a bot, that is `No human discussion yet.`
- Name the count of unresolved review threads when there are any, and the files they cluster on.
- `No discussion yet.` is a complete and useful recap. Do not pad it.

Never speculate about what someone meant beyond what the comment text says.

### 5. Write the summary prose

- **`HEADLINE`** — one sentence sizing up the queue: how many are unreviewed, how many are past due,
  and where the pressure is. Example: `Six PRs need your review, three of them past the overdue
  threshold and all three in dashboard.`
- **`TRIAGE_ADVICE`** — one or two sentences naming the single PR to open first and why, plus
  anything that can be deferred or skipped cheaply (bot bumps, PRs already approved by someone else).
- **`METHODOLOGY`** — the queries run, the SLA thresholds applied, the clock source distribution
  (how many direct vs. team vs. fallback), any PRs the fetch could not reach, and the fact that the
  run was read-only. This is where honesty about the data's limits lives.

Write plainly. No praise, no filler.

### 6. Render

Start from [assets/assignments-template.html](assets/assignments-template.html). It is a complete
document: theme-aware, self-contained, no scripts, fonts, or network requests of any kind, with
every PR's detail collapsed so the front page stays a queue.

Repeat the `.pr` block per PR within each section, and one table row per PR in the at-a-glance fold.
Rules:

- **Delete, never leave.** Any token you cannot fill goes, along with the element around it. A
  visible `{{TOKEN}}` in the output is a bug.
- **Nothing needed for triage hides.** Due label, PR slug, title, one-liner, opened date, requested
  date, author, size, CI badge, and review badge are all visible without a click. Only the
  conversation recap, thread list, CI detail, signals, the table, and the methodology sit behind a
  `<details>`, and all of those stay closed.
- **Lane and badge classes must agree** with the labels they carry — a `lane-overdue` PR carries a
  `due-overdue` badge. Mismatched colour is worse than no colour.
- **Empty section** — replace its PRs with `<div class="card empty">Nothing here.</div>`. Keep the
  heading; an absent section reads as an omission.
- **Human dates** — `OPENED_HUMAN` and `REQUESTED_HUMAN` are relative and absolute together:
  `12 Aug 2025 (3 weeks ago)`. `OPENED_SHORT` and `REQUESTED_SHORT` in the table are `2025-08-12`.
  `SIZE_HUMAN` is `9 files, +202 −20`; `SIZE_SHORT` is `9f`.
- **No ticket identifiers.** Strip issue-tracker keys — `FIX-342`, `ENG-1180`, `JIRA-77` — from
  titles, one-liners, recaps, and signals. A title like `feat(api): report source mapping [FIX-342]`
  renders as `feat(api): report source mapping`. Link the PR, not the ticket.
- **Every identifier is `<code>`.** Logins, repo names, branch names, file paths, check names,
  labels, config keys, and literal values get wrapped in `<code>` wherever they appear — in the
  headline, advice, one-liners, recaps, and signals. Do not wrap ordinary nouns.
- Escape `<`, `>`, and `&` in every value taken from GitHub, **then** wrap identifiers in `<code>` —
  escaping afterwards would turn your own tags into visible text. PR titles and comment bodies
  routinely contain `<`, `>`, `&`, and raw HTML; a `<details>` block pasted from a bot comment will
  break the page if it survives into the output.

### 7. Deliver

Write into an assignments directory under the system temp root, which the OS clears on reboot — the
report stays readable for as long as the machine is up and never accumulates:

```bash
out="${TMPDIR:-/tmp}/temp_assignments"
mkdir -p "$out"
report="$out/pr-assignments-$(date +%Y%m%d-%H%M%S).html"
```

Write the document there, then open it:

```bash
open "$report"        # macOS
xdg-open "$report"    # Linux
start "" "$report"    # Windows
```

Then summarize in chat in **four lines at most**: the counts (unreviewed / overdue), the single PR
to open first, anything the fetch could not reach, and the file path. Everything else is in the
report — do not restate it.

Finally, confirm explicitly that nothing was written to any PR.

## Edge cases

- **Empty queue:** say so in one line and render nothing. A report with no rows is worse than no
  report.
- **A repo the token cannot read:** the fetch warns and skips it. Name the count in the methodology
  note rather than silently shipping a short queue.
- **`read:org` scope missing:** `user/teams` returns nothing, so team-requested PRs are invisible and
  the `team-request` clock source never resolves. The run still works on direct requests — say in the
  methodology note that team requests were not visible and that `gh auth refresh -s read:org` fixes
  it.
- **Very old PRs** (a year-old bot bump): `ci.rollup` is often `NONE` because the workflows are
  gone, and slack is deeply negative. Rank them honestly — they are overdue — but the triage advice
  should say plainly that a stale bot bump is a close-or-rebase decision, not a review.
- **A PR the user authored themselves** that also requests their review: keep it, and note the
  self-request in the signals line. It is usually a mis-set reviewer.
- **`reviewDecision` already `APPROVED`** by someone else while the user is still requested: keep it
  in the awaiting section — the request is live — but say in the signals line that sign-off already
  exists, so it can be deferred.
- **Huge queue** (40+ PRs): fetch them all, but write full one-liners and recaps only for the
  unreviewed and overdue ones. For the rest, the table row and the badges are enough — and say in
  the methodology note which PRs got the short treatment.
- **The user asks for the code to be reviewed too:** this skill does not read diffs. Point at
  `pr-digest` and offer to run it on the top PR.
- **The user asks for a comment to be posted, a review submitted, or a reviewer removed:** this skill
  does not write. Say so and point at the agent's own PR tooling; do not improvise a write.
- **Non-GitHub host** (GitLab, Bitbucket): out of scope. `gh` cannot see it — say what is needed
  rather than guessing at an equivalent CLI.
