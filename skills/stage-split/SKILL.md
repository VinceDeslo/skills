---
name: stage-split
description: Split the currently staged changes into several focused commits with Conventional Commits messages, after showing the user a table of the proposed split and getting approval. Use when asked to split, break up, or divide staged changes into separate or atomic commits, to commit staged work in logical pieces, or when the user says "stage-split".
compatibility: Run from inside a git repository. Requires bash and git 2.20+. Operates only on the index (staged changes); it never pushes and never touches unstaged or untracked files.
---

# stage-split

Turn one large staged changeset into a series of small, self-contained commits — proposed first as a table, executed only after the user approves.

## When to use

The user has staged work and asks to split it into individual, atomic, or logical commits, or says "stage-split".

## Scope rules

- **Only staged content is committed.** Unstaged edits and untracked files stay exactly as they are, including edits in a file that is also partly staged.
- **Never push.** Stop after the last commit.
- **Never amend or rewrite existing history.** Only new commits on top of the current `HEAD`.
- **Never add commit trailers** (`Co-Authored-By`, generator footers, ticket identifiers) unless the user asks for them.

## Instructions

### 1. Check preconditions

```bash
git rev-parse --show-toplevel
git diff --cached --quiet && echo "NOTHING STAGED"
```

If nothing is staged, report it and stop — do not stage anything on the user's behalf. If the repository is mid-rebase, mid-merge, or mid-cherry-pick (`git status --short --branch`), stop and say so.

### 2. Take a safety snapshot

Record the exact staged tree so the index can be restored if anything fails later:

```bash
git write-tree          # prints a tree hash — keep it
git rev-parse HEAD      # keep it
```

Restore at any point with `git read-tree <tree-hash>` (index only) or `git reset --soft <head-hash>` followed by `git read-tree <tree-hash>` (after commits were made). Report both hashes to the user if you have to abort.

### 3. Inspect the staged changes

```bash
git diff --cached --stat
git diff --cached --name-status
git diff --cached
```

For a large diff, read the per-file diffs one at a time (`git diff --cached -- <path>`) instead of loading everything at once.

### 4. Group the changes

Group by **concern**, not by directory or file type. Guidelines:

- One commit = one reason to change. It should build and pass tests on its own where practical.
- Each commit gets exactly one Conventional Commits type. If a file contains two types of change (a fix plus a refactor), that is a hunk-level split — see [Hunk-level splits](#hunk-level-splits).
- Keep a test with the code it covers unless the tests were clearly added independently.
- Keep manifest and lockfile changes with the change that needs the dependency.
- Put pure formatting, renames, and mechanical churn in their own `style:`/`refactor:` commit so review stays readable.
- Order groups so that each one applies cleanly on the previous: schema/types/interfaces before their consumers, dependencies before use, docs last.

Write each message as Conventional Commits:

```
<type>(<optional-scope>): <imperative subject, lowercase, no trailing period>
```

Types: `feat`, `fix`, `refactor`, `perf`, `style`, `test`, `docs`, `build`, `ci`, `chore`, `revert`. Keep the subject at or under 72 characters. Add a body only when the *why* is not obvious from the subject; use `!` or a `BREAKING CHANGE:` footer for breaking changes.

### 5. Propose the split and wait for approval

Print a table and stop. Do not commit anything yet.

```markdown
| # | Commit message | Files | Why |
| - | -------------- | ----- | --- |
| 1 | `refactor(parser): extract token reader` | `src/parser.ts`, `src/token.ts` | Pure move, no behavior change |
| 2 | `fix(parser): handle empty input` | `src/parser.ts` (hunks 3–4), `test/parser.test.ts` | Bug fix plus its regression test |
| 3 | `docs: document parser options` | `README.md` | Documentation only |
```

Below the table, list anything the split leaves out — files staged but unassigned, unstaged edits that will remain in the working tree, and any group that needs a hunk-level split.

Ask for explicit approval, and offer to merge, reorder, resplit, or reword groups. Apply any requested change and re-print the table. **Only proceed once the user approves.**

### 6. Execute the split

Work through the index with patches so the working tree is never touched.

Write one patch per group into a scratch directory:

```bash
mkdir -p .git/stage-split
git diff --cached --binary -- <paths for group 1> > .git/stage-split/01.patch
git diff --cached --binary -- <paths for group 2> > .git/stage-split/02.patch
```

Clear the index once, then apply and commit each group in order:

```bash
git reset --quiet                                  # unstage everything; working tree untouched
for patch in .git/stage-split/*.patch; do
  git apply --cached --binary "$patch" || echo "FAILED: $patch"
done
```

In practice run one group at a time so a failure stops the sequence:

```bash
git apply --cached --binary .git/stage-split/01.patch
git commit -m "refactor(parser): extract token reader"
```

Repeat for each group. Verify after each commit that the index is clean of that group (`git diff --cached --stat`).

If `git apply --cached` fails, retry that patch with `git apply --cached --3way`. If it still fails, stop, restore with `git read-tree <tree-hash>` from step 2, and report which group failed.

### 7. Report

```bash
git log --oneline "<head-hash>..HEAD"
git status --short
rm -rf .git/stage-split
```

Confirm the commit list, confirm nothing was pushed, and note what is still uncommitted in the working tree.

## Hunk-level splits

When one file carries two concerns, generate the file's staged patch and split it by hunk:

```bash
git diff --cached --binary -- src/parser.ts > .git/stage-split/parser.patch
```

Copy the patch into one file per group, keeping the `diff --git`/`index`/`---`/`+++` header in each copy and deleting the hunks that belong to the other group. Do not edit `@@` line numbers by hand — `git apply` tolerates offsets. Apply the later patch with `--3way` if the earlier commit shifted its context.

Never use `git add -p` or `git commit -p`: they are interactive and block a non-interactive agent shell.

## Edge cases

- **Nothing staged:** report and stop. Do not run `git add` yourself.
- **Everything belongs to one concern:** say so, propose a single commit, and still ask before committing.
- **File is partly staged:** the patch flow commits only the staged half; the unstaged half stays in the working tree. Call this out in the table's notes.
- **Binary files:** always generate patches with `--binary`; a patch made without it fails to apply.
- **Renames:** `git diff --cached` records renames as delete+add unless `-M` is in effect; keep both sides of a rename in the same group.
- **Deleted or new files:** handled by the patch flow; list them in the table with their status (`A`, `D`).
- **A commit fails a pre-commit hook:** stop the sequence, report the hook output, and leave the remaining patches unapplied — the earlier commits stand. Restore the full index with `git read-tree <tree-hash>` if the user wants to start over.
- **User aborts after some commits:** undo with `git reset --soft <head-hash>` then `git read-tree <tree-hash>` to put the original staged set back exactly as it was.
