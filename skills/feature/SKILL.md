---
name: feature
description: Start a feature from a Linear ticket — read the ticket, create a worktree for the current repository named after the ticket identifier, and scaffold the implementation locally, stopping at a reviewable state without committing or pushing. Use when given a Linear issue link or identifier (ENG-123) and asked to start, implement, build, or scaffold the work, or when the user says "feature".
compatibility: Run from inside a git repository. Requires bash, git, worktrunk (`wt`, https://worktrunk.dev), and jq. Reading the ticket needs a Linear integration (an MCP server, the `linear` CLI, or a browser fetch); without one, ask the user to paste the ticket body.
---

# feature

Turn a Linear ticket into a scaffolded, reviewable branch in an isolated worktree. The skill stops before version control: no commit, no push, no pull request.

## When to use

The user supplies a Linear issue link (`https://linear.app/<workspace>/issue/ENG-123/<slug>`) or a bare identifier (`ENG-123`) and asks to start, build, implement, or scaffold that feature in the current repository.

## Instructions

### 1. Read the ticket

Extract the identifier — the `ABC-123` segment of the URL — and fetch the issue. In order of preference:

- a Linear MCP tool (`get_issue` with the identifier),
- the `linear` CLI,
- a plain fetch of the URL,
- as a last resort, ask the user to paste the title, description, and acceptance criteria.

Pull out: title, description, acceptance criteria, linked designs or documents, and any comments that change the requirements. If the ticket is thin, ask the user the questions the ticket leaves open **before** writing code — do not invent requirements.

### 2. Create the worktree

From the repository the user is working in:

```bash
scripts/create-feature-worktree.sh <linear-url-or-id> "<short slug from the ticket title>"
```

It prints `id=`, `branch=`, `path=`, and `created=`. The branch is `<lowercased-id>[-slug]` (`eng-123-add-cost-guardrails`), so every branch and worktree carries the ticket identifier. Re-running with the same input reuses the existing worktree and reports `created=false`.

Do all subsequent work in the printed `path=`. Nothing is written to the original worktree.

If the repository needs gitignored files that the new worktree lacks — `.env`, local certificates, a `terraform.tfvars` — copy them over:

```bash
wt step copy-ignored <path>
```

### 3. Explore before writing

In the new worktree, find the existing patterns the feature must match: the module the change belongs to, neighbouring implementations of the same shape, the test layout, the configuration and migration conventions. Read those files. Match their structure, naming, and error handling rather than importing a style from elsewhere.

### 4. Scaffold the implementation

Build the feature as far as the ticket is unambiguous:

- Real, working code for the parts the ticket specifies — not empty stubs where the behaviour is clear.
- Tests alongside the implementation, following the repository's existing test layout.
- Wiring: routes, handlers, migrations, configuration keys, feature flags, and dependency registration, so the feature is reachable rather than orphaned.
- Where a decision genuinely needs the user, leave the smallest possible marker and record the open question for the summary instead of guessing.

Keep the change scoped to the ticket. Unrelated refactors, formatting sweeps, and dependency bumps belong in their own branch.

### 5. Verify locally

Run what the repository already provides — its formatter, linter, type checker, and the test target covering the touched code. Report the actual output. A failing check is a result to state, not to hide or to work around by weakening the test.

### 6. Stop and hand over

Leave every change uncommitted in the working tree. Do not run `git commit`, `git push`, `wt merge`, `wt step commit`, or open a pull request, even if it looks like the obvious next step — the user reviews first.

Report:

1. **Ticket** — identifier, title, one-line restatement of the requirement.
2. **Worktree** — branch name and absolute path.
3. **What was built** — the changed files grouped by purpose, with the entry point for review named first.
4. **Checks** — the commands run and their real results.
5. **Open questions** — every decision left to the user, and what was assumed in the meantime.
6. **How to test it locally** — see below.

### 7. Local test guidance

Give commands the user can paste, derived from this repository rather than from a generic template. Cover, where they apply:

```bash
cd <worktree path>              # from the script output
<the repo's setup command>      # install / build / migrate, only if needed
<the repo's run command>        # start the service, CLI, or dev server
<the focused test command>      # just the tests for this change
```

Then state the manual path: what to click, curl, or invoke; the input to supply; the output that means it works. Name any prerequisite the user must provide — an environment variable, a running database, a seeded record, a feature flag to enable. If a step could not be verified, say so plainly instead of implying it passed.

## Edge cases

- **No identifier in the input:** the script exits non-zero. Ask for the full ticket link or the `ABC-123` identifier.
- **Ticket unreadable (no integration, private workspace):** ask the user to paste the ticket body rather than guessing the scope from the URL slug.
- **Branch or worktree already exists:** reused, `created=false`. Continue in it and tell the user it was pre-existing, since it may hold earlier work.
- **Uncommitted changes in the current worktree:** they stay where they are. The new worktree branches from the default branch, so unstaged work is not carried over — mention it if the feature depends on it.
- **Ticket too large for one branch:** scaffold the coherent first slice, and list the remaining slices in the summary instead of half-implementing all of them.
- **`wt` or `jq` missing:** hard requirement; the script exits before touching the repository.
