---
name: pr-digest
description: Review a pull request from its link in a series of focused passes, verify every claim against the code, and emit a short HTML digest — at most five major, five minor, and five nit items — into a reboot-cleared temp_reviews directory. Runs entirely in the current session and never writes back to the PR. Use when given a PR or merge request URL and asked to review, assess, sanity-check, or get up to speed on it, or when the user says "pr-digest".
compatibility: Requires `git`, the GitHub CLI (`gh`) authenticated against the PR's host, and network access. Optional — a local clone of the repository for deeper context, and a browser opener (`open`, `xdg-open`, or `start`) to display the digest.
---

# pr-digest

Read a pull request in structured passes, keep only what survives verification, and hand back a
digest a reader can absorb in under two minutes.

Three properties define this skill:

- **In-session.** You do the whole review yourself. No subagents, no delegation, no parallel
  reviewers. The passes below are stages of your own reading, and they run in order because each
  one depends on what the previous one established.
- **Read-only.** The review never touches the PR — no comments, no reviews, no labels, no
  description edits, no merges — and never modifies the working tree. The output is a local file
  and a chat summary. Nothing else.
- **Ruthlessly short.** At most five major, five minor, and five nit findings. The goal is to catch
  the biggest faults, not to block progress. A tidy PR with nothing worth saying gets an empty
  report, and that is a success.

## When to use

The user supplies a pull request link (or an `owner/repo#123` reference) and asks for a review, a
second opinion, a sanity check, or a summary of what changed — or says "pr-digest".

For reviewing uncommitted local work, use the agent's own diff-review tooling instead. This skill is
built around a PR that already exists.

## Instructions

### 1. Resolve the target

Parse the link into owner, repo, and number. Accept
`https://github.com/<owner>/<repo>/pull/<n>`, `<owner>/<repo>#<n>`, or a bare number when the
current directory is already that repository.

```bash
gh pr view <url> --json number,title,body,author,url,headRefName,baseRefName,headRefOid,additions,deletions,changedFiles,isDraft,state,labels
gh pr diff <url> --patch > "$WORK/pr.diff"
gh pr diff <url> --stat
```

If `gh` fails to authenticate, or the PR is on a host `gh` is not configured for, stop and say so.
Do not review from a pasted diff the user did not provide.

Note the state: if the PR is merged or closed, confirm the user still wants it reviewed before
spending the run.

### 2. Get the code within reach

Reading a diff in isolation produces confident nonsense. Before judging any hunk you need its
callers, its types, and the convention the rest of the repo follows — so find a local clone:

```bash
ls -d ~/repos/*/<repo> 2>/dev/null
```

If one exists, fetch the PR head into a throwaway ref without disturbing the user's working tree:

```bash
git -C <clone> fetch origin "pull/<n>/head:refs/remotes/pr/<n>" --no-tags
```

Read at that ref with `git show refs/remotes/pr/<n>:<path>`, `git grep <pattern> refs/remotes/pr/<n>`,
and `git diff <base>...refs/remotes/pr/<n>`. **Never check it out**, never switch branches, never
stash. The user's working tree is untouched by this skill.

If no clone exists, work from the diff plus `gh api` GET reads of individual files, and say so in
the methodology note — a diff-only review is shallower and the report should admit it.

Before reading further, take the size from `--stat` and identify what to skip: generated files,
lockfiles, vendored trees, and pure formatting churn get a glance, not a review. Note them; they go
in the file table and the methodology note, not in the findings.

### 3. Review in passes

Read [references/review-rubric.md](references/review-rubric.md) for the severity definitions, the
rules of evidence, and the verification bar. Then work through these passes **in order**. Each is a
distinct question asked of the same code, and mixing them produces a mushy review that catches
neither the bugs nor the design problems.

**Pass 1 — Orient.** Read the title, body, and the full diff end to end without judging anything.
Work out what the change is *for* and how it achieves that. Write the summary sentence now, before
you have opinions; if you cannot write it, you have not understood the PR and the rest of the
review will be worthless.

**Pass 2 — Correctness.** Re-read the risky hunks asking only: is this wrong? Unhandled error paths
that matter, off-by-one and boundary conditions, nil and empty cases, races and shared state,
resource leaks, broken contracts and migrations, security holes, performance cliffs on hot paths.
Open the callers. Check the types. This pass produces candidate majors.

**Pass 3 — Fit.** Re-read the same code asking only: does this belong here, in this shape? Logic
that already exists elsewhere in the repo, inconsistency with how the repo does this same thing, a
leaky abstraction, a missing test on exactly the branch pass 2 flagged as risky, a name that will
mislead on a wide surface. This pass produces candidate minors.

**Pass 4 — Verify.** Take every candidate from passes 2 and 3 and try to disprove it. Go back to
the code — not to your notes — and check the claim holds. For each candidate ask:

- Can I state the concrete failure: the input or state that triggers it, and the wrong outcome?
- Is the thing I assumed absent actually absent, or did I just not look where it lives?
- Is this pre-existing behaviour the PR only moves or reindents?
- Is this already enforced by a linter, a formatter, a type, or a test in this repo?

A candidate that survives is `confirmed`. One you still believe but could not fully pin down is
`likely` — allowed, but it must say what would settle it. One that fails any check is dropped
silently; do not report the fact that you considered it.

This pass is where the review earns its keep. Skipping it turns a digest into a list of guesses.

### 4. Rank and cap

Order within each severity by consequence, `confirmed` ahead of `likely` among equals. Then cut:

- **major** — at most 5
- **minor** — at most 5
- **nit** — at most 5

If a list overflows, drop the tail; do not demote overflow into the next list to make room. If more
were cut than kept, add one line to the verdict saying how many were dropped, so the reader knows
the list is a top-five and not an exhaustive audit.

Fewer than five is normal. Zero is a valid and good result.

Set the risk score 1–10: 1 a typo fix, 4 a new tested feature, 8 a public API change, 9 a schema
migration, 10 a change that introduces a security vulnerability. Interpolate with judgement.

### 5. Write the digest text

Three pieces of prose, and they carry the whole report:

- **Summary** — two or three sentences. What this PR does and how it does it, in plain terms, for
  someone who has not read the diff. Start from the sentence written in pass 1.
- **Verdict** — one or two sentences. Whether it is safe to merge, and what the single most
  important thing to fix first is. Say "nothing blocking" when nothing is blocking.
- **Intent vs. diff** — whether the change matches its title and body, and what it does beyond them.
  This goes in a collapsed section.

Write plainly. No praise, no hedging, no "great work" — the reader wants the shape of the change and
the risk, in that order.

### 6. Draw one diagram

The digest carries a single diagram whose job is to make the change legible at a glance. It is built
from plain HTML elements — there is no diagram library, no external script, and no rendering step —
so it reads at body text size and never needs zooming or sideways scrolling.

Read [references/diagram-kit.md](references/diagram-kit.md) for the markup. Pick one pattern:

- **`.flow`** — a path through components. The default, and right for most PRs. Use `.branch` lanes
  for a fan-out.
- **`.steps`** — ordered interactions between participants, when the change is about what calls what
  in what order.
- **`.stack`** — grouped layers or subsystems, when the change is about where something now lives.
- **`table.fields`** — a schema, payload, or config shape change.

Colour carries the whole point of the diagram:

- **`is-new`** (green) — introduced by this PR.
- **`is-changed`** (blue) — existed before, behaves differently now.
- **`is-gone`** (grey, dashed) — removed or bypassed; include only when its absence is the point.
- **uncoloured** — untouched context, and most nodes should be this. The colours only mean something
  if they are rare.

Every coloured node also carries its `<span class="tag">new</span>` or `mod` text label, so the
state does not depend on colour alone. Keep the legend rows for the states used and delete the rest.

Twelve nodes maximum, node labels under ~28 characters, edge labels under ~40. If it does not fit,
it is too big — cut nodes rather than widening anything.

If the change is not structural (a bug fix in one function, a dependency bump, a copy change), it
gets no diagram. Delete the `<figure class="card diagram">` block entirely rather than shipping a
diagram that says nothing.

### 7. Render

Start from [assets/review-template.html](assets/review-template.html). It is a complete document:
theme-aware, fully self-contained — no scripts, fonts, or network requests of any kind — with every
finding collapsed by default so the front page stays a digest.

Fill the tokens, repeat the `.finding` block per finding, and repeat the file row per notable file.
Rules:

- **Delete, never leave.** Any token you cannot fill goes, along with the element around it. A
  visible `{{TOKEN}}` in the output is a bug. The diagram block ships with one pattern filled in as
  an example — replace it wholesale with your own markup, or delete the figure.
- **Nothing important hides.** Everything a reader needs to decide — summary, verdict, risk,
  counts, diagram, and every finding's title and location — is visible without a click. Only
  detail, failure, fix, the file table, intent, and methodology live behind a `<details>`, and all
  of those stay closed.
- **Empty severity list** — replace its findings with
  `<div class="card empty">Nothing found.</div>`. Keep the heading; an absent section reads as an
  omission.
- **Verdict badge** — `confirmed` (with class `confirmed`) or `likely`, from pass 4. Nits carry no
  badge. A `likely` finding's detail must end with what would settle it.
- **Every identifier is `<code>`.** File paths, function and method names, types, variables, struct
  and table and column names, config keys, environment variables, CLI commands, branch names, and
  literal values get wrapped in `<code>` wherever they appear — in the summary, the verdict, finding
  titles and details, failures, fixes, the intent note, diagram labels, and captions. Prose names a
  thing; `<code>` shows it is a thing in the codebase. Do not wrap ordinary nouns: `<code>` around
  "the cache" or "the handler" is wrong, `<code>tenantCache</code>` is right.
- Escape `<`, `>`, and `&` in every value taken from code or the diff, **then** wrap identifiers in
  `<code>` — escaping afterwards would turn your own tags into visible text.

### 8. Deliver

Write into a reviews directory under the system temp root, which the OS clears on reboot — reports
stay readable for as long as the machine is up and never accumulate:

```bash
reviews="${TMPDIR:-/tmp}/temp_reviews"
mkdir -p "$reviews"
out="$reviews/<repo>-<number>-$(date +%Y%m%d-%H%M%S).html"
```

Write the document there, then open it:

```bash
open "$out"        # macOS
xdg-open "$out"    # Linux
start "" "$out"    # Windows
```

Then summarize in chat in **four lines at most**: risk score, the counts, the single most important
finding, and the file path. Everything else is in the digest — do not restate it.

Finally, confirm explicitly that nothing was written to the PR.

## Edge cases

- **Huge PR** (2000+ lines or 50+ files): scope passes 2 and 3 to the files carrying the behaviour
  change, and name what you skipped in the methodology note. Do not silently review a sample and
  present it as a full review.
- **Mostly generated or vendored diff:** review the hand-written remainder and say in the summary
  what fraction was generated.
- **Draft PR:** review it, but weight incompleteness as expected rather than as a finding. Missing
  tests on a draft is a minor at most.
- **No local clone:** the review is diff-only. Pass 2 gets weaker because callers are not readable
  without a `gh api` round trip per file — spend those reads on the risky hunks only, mark
  unverifiable candidates `likely`, and say in the methodology note that the review was diff-only.
- **Nothing found:** ship the digest anyway. The summary, diagram, and file table are worth the read
  on their own, and a verified "nothing found" is information.
- **The PR is the user's own and they ask for it to be posted:** this skill does not post. Say so
  and point at the agent's PR-comment tooling; do not improvise a write.
- **Non-GitHub host** (GitLab, Bitbucket): `gh` cannot fetch it. Stop and say what is needed rather
  than guessing at an equivalent CLI.
