---
name: pr-comment-triage
description: Validate the review comments left on a pull request — typically AI-generated ones on the user's own PR — by tracing each comment through the code at the PR head, judging it valid, partly valid, invalid, outdated, or unverifiable, and ranking what is worth a human's attention. Read-only; never replies to, resolves, or edits comments. Use when asked to validate, check, assess, triage, filter, or sanity-check PR review comments, to find which review comments are valid or noise, to prioritize review feedback, or when the user says "pr-comment-triage".
compatibility: Requires `git`, the GitHub CLI (`gh`) authenticated against the PR's host, and network access. A local clone or worktree of the repository is strongly preferred for tracing.
---

# pr-comment-triage

Take every review comment on a PR, trace it through the code, and say which ones are real. The goal
is less noise: the user reads only the comments that survive, in priority order.

Two rules hold throughout:

- **Read-only.** Never post, reply, react, resolve, or edit anything on the PR. Never modify the
  working tree, switch branches, or stash.
- **Trace, do not trust.** A comment is a claim. It is valid only when the code at the PR head shows
  it. The comment's confidence, its author, and its severity label are not evidence.

## When to use

The user gives a PR link, an `owner/repo#n` reference, or a bare number in the current repository,
and asks which review comments are valid, which to act on, or to cut the noise. Without a reference,
use the PR for the current branch: `gh pr view --json number,url`.

To review the PR itself rather than its comments, use `pr-digest` instead.

## Instructions

### 1. Resolve the PR

```bash
gh pr view <ref> --json number,url,title,author,headRefName,baseRefName,headRefOid,state
```

If `gh` fails to authenticate or the host is not GitHub, stop and say so.

### 2. Collect the comments

Fetch review threads with their resolution and outdated state, plus top-level review bodies and
conversation comments:

```bash
gh api graphql --paginate -F owner=<owner> -F repo=<repo> -F number=<n> -f query='
query($owner:String!,$repo:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){ pullRequest(number:$number){
    reviewThreads(first:50,after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{ id isResolved isOutdated path line originalLine startLine diffSide
        comments(first:50){ nodes{ author{login} body createdAt url originalCommit{oid} } } } } } } }'
gh api "repos/<owner>/<repo>/pulls/<n>/reviews" --paginate
gh api "repos/<owner>/<repo>/issues/<n>/comments" --paginate
```

Build one list of items. Each item is a thread (inline) or a review body or conversation comment
that makes a concrete claim about the code. Rules:

- **Skip resolved threads** unless the user asks for them. Count them in the summary.
- **Skip pure noise without tracing:** bot summaries, CI status posts, walkthrough tables, "LGTM",
  and the user's own comments. Count them.
- **Split a comment that makes several claims** into one item per claim. A review body with a list
  of five issues is five items.
- **Keep the thread context.** Later replies in a thread may narrow, retract, or rebut the first
  comment; judge the thread as a whole.
- If the user names an author (e.g. one AI reviewer), filter to that author.

If there are no items left, say so and stop.

### 3. Get the code at the PR head

Find a local checkout of the repository: the current directory, or a clone or worktree under the
user's repository roots. Prefer a worktree already on the PR branch.

- If a checkout on the PR branch has `HEAD` equal to `headRefOid`, read from it directly.
- Otherwise fetch the head into a throwaway ref and read from it without checking out:

  ```bash
  git -C <clone> fetch origin "pull/<n>/head:refs/remotes/pr/<n>" --no-tags
  git -C <clone> show refs/remotes/pr/<n>:<path>
  git -C <clone> grep -n <pattern> refs/remotes/pr/<n>
  ```

- If the user's checkout of the branch has local commits or uncommitted changes beyond
  `headRefOid`, also note per item whether the local state already addresses it.
- With no local clone, read files with `gh api "repos/<owner>/<repo>/contents/<path>?ref=<headRefOid>"`
  and say in the report that tracing was shallower.

### 4. Trace each item

For every item, in order:

1. **Restate the claim** in one sentence: what the comment says is wrong, and what outcome it
   predicts (crash, wrong value, leak, race, security hole, convention break, and so on).
2. **Locate it.** Open the file at the PR head at the commented line. If the thread is outdated or
   the line moved, find the code it was about by content, not by line number.
3. **Trace the path.** Follow the code the claim depends on: callers up to an entry point, callees
   down to where the predicted failure would happen, the types, the guards, the config, and the
   tests. Read each frame; do not infer it from names.
4. **Try to disprove it.** Check, at minimum:
   - Is the input or state that triggers the failure actually reachable?
   - Is the "missing" check, error handling, or test present elsewhere — a caller, a middleware, a
     type constraint, a validator, a linter rule?
   - Is the behaviour pre-existing and only moved by this PR?
   - Did a later commit on the PR already fix it?
   - Does the suggested fix compile, keep the contract, and match how the repo does this elsewhere?
5. **Judge it** with one verdict:

   | Verdict | Meaning |
   | --- | --- |
   | `valid` | The trace shows the failure. Concrete trigger and outcome exist. |
   | `partly valid` | The concern is real but overstated, mis-located, or the suggested fix is wrong. |
   | `invalid` | The trace disproves it. Name the line that disproves it. |
   | `outdated` | True at the commented commit; fixed at the PR head or locally. |
   | `unverifiable` | Depends on runtime data, external systems, or intent the code cannot show. Say what would settle it. |

   A style or naming comment is `valid` only when the repository has a convention it breaks. Taste
   alone is `invalid`, not a nit.

6. **Assign a priority** to `valid` and `partly valid` items:
   - `P1 fix` — correctness, security, data loss, or a broken contract.
   - `P2 consider` — real but low consequence: missing test, edge case, maintainability.
   - `P3 optional` — convention or readability.

Record for each item: the trace as `path:line` frames with the decisive line quoted verbatim, the
verdict, the priority, and one sentence of reasoning. Never quote a line you did not read.

### 5. Report

Report in chat. Order: `valid` and `partly valid` by priority, then `unverifiable`, then `outdated`,
then `invalid`.

Start with one line of counts:

```
12 comments → 3 valid, 2 partly valid, 1 unverifiable, 2 outdated, 4 invalid (5 resolved, 3 noise skipped)
```

Then one table:

| # | Priority | Verdict | Location | Claim | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | P1 fix | valid | `pkg/auth/token.go:88` | nil `claims` deref on expired token | `parse()` returns `nil, nil` on expiry (`token.go:41`); caller derefs at `:88` |

Below the table, for each `valid` and `partly valid` item only, give the trace (three to six
`path:line` frames, entry point first, decisive line last) and the fix in one or two sentences.
Link each item to its comment URL. For `invalid` items the Evidence column is the whole
explanation; keep it to one clause naming the disproving line.

End with one line: the single comment to deal with first, or "nothing worth acting on".

State that nothing was written to the PR.

## Edge cases

- **Many comments (30+):** trace every item, but batch the tracing by file so each file is read
  once. Do not sample.
- **Duplicate comments** from several reviewers on the same issue: merge into one item and list all
  links.
- **Comment on a deleted line or file:** `outdated` if the concern went away with it; otherwise
  trace where the logic moved.
- **Comment about something outside the diff:** trace it the same way, and flag it as
  pre-existing — it may be valid but out of scope for this PR.
- **Suggested-change blocks:** check the suggestion itself; a valid concern with a broken
  suggestion is `partly valid`.
- **The user asks to reply or resolve:** this skill does not write to the PR. Say so and leave it
  to the user or the agent's PR-comment tooling.
- **Non-GitHub host:** stop and say what is needed.
