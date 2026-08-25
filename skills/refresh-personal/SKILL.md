---
name: refresh-personal
description: Fast-forward the default branch of every personal repository under ~/repos/personal so local clones match their remotes. Use when asked to refresh, update, or pull the latest personal repos, the personal projects, or when the user says "refresh-personal".
compatibility: Requires bash, git, a checkout root at ~/repos/personal, and push/fetch credentials for each remote (SSH keys or a credential helper).
---

# refresh-personal

Walk every repository under `~/repos/personal`, fetch its remote, and fast-forward the default branch.

## When to use

The user asks to refresh, update, or pull the latest personal repos, the personal projects, or says "refresh-personal".

## Instructions

1. Run the walker from this skill directory:

   ```bash
   scripts/refresh-repos.sh
   ```

   Pass a different root as the first argument to override `~/repos/personal`.

2. Report the table it prints, one line per repository, plus the summary counts.

3. For every `failed` line, name the repository and the git error. Do not retry with `--force`, `--rebase`, or `reset --hard`; report and stop.

## What the script does

For each direct child directory of the root:

- Skips anything that is not a git repository, and skips linked worktrees (`repo.branch` siblings) by comparing `git rev-parse --git-dir` with `--git-common-dir`.
- Resolves the default branch from `refs/remotes/origin/HEAD`, refreshing it with `git remote set-head origin --auto` when unset, then falling back to `main` or `master`.
- Locates the worktree that holds the default branch through `git worktree list --porcelain`, so the pull lands in the right place even when the primary checkout is on a feature branch.
- Runs `git fetch --prune`, then `git merge --ff-only` against the upstream.

Results per repository: `updated`, `up-to-date`, `skipped`, or `failed`. Exit status is non-zero if any repository failed.

## Notes

- Fast-forward only. The script never creates, moves, or removes a worktree, never switches a branch, and never rewrites history, so unmerged local work stays untouched.
- Feature-branch worktrees are not updated. Only the default branch of each repository moves.
- Fetch is sequential. A root with many remotes takes time; let it finish instead of interrupting.
- Use `wt` (`wts`, `wtl`, `wtr`) for any worktree change. This skill is not a substitute.

## Edge cases

- **Diverged default branch:** `merge --ff-only` fails and the repository is reported `failed`. The user decides whether to rebase or reset.
- **Dirty worktree:** the fast-forward is still attempted. Git refuses it when local changes would be overwritten, which surfaces as `failed`.
- **No upstream for the default branch:** reported `skipped`, nothing is changed.
- **Empty repository (no commits):** reported `skipped` with `no default branch`.
- **Default branch checked out in no worktree:** reported `skipped`. Create one with `wts <default-branch>` and run again.
