---
name: refresh-work
description: Fast-forward the default branch of every work repository under ~/repos/work so local clones match their remotes, using worktrunk (wt) to discover repositories and worktrees. Use when asked to refresh, update, or pull the latest work repos, the work or infracost projects, or when the user says "refresh-work".
compatibility: Requires bash, worktrunk (`wt`, https://worktrunk.dev), jq, git, a checkout root at ~/repos/work, and fetch credentials for each remote (SSH keys or a credential helper).
---

# refresh-work

Walk every repository under `~/repos/work` and fast-forward its default branch. Worktrunk is the source of truth for repository and worktree structure.

## When to use

The user asks to refresh, update, or pull the latest work repos, the work or infracost projects, or says "refresh-work".

## Instructions

1. Run the walker from this skill directory:

   ```bash
   scripts/refresh-repos.sh
   ```

   Pass a different root as the first argument to override `~/repos/work`.

2. Report the table it prints, one line per repository, plus the summary counts.

3. For every `failed` line, name the repository and the error. Do not retry with `--force`, `--rebase`, or `reset --hard`; report and stop.

## What the script does

For each direct child directory of the root it runs:

```bash
wt -C <dir> --config-set list.json-schema=2 list --format json --no-progressive
```

and reads from that listing:

- `repo.default_branch` — the branch to refresh, so `main` and `master` repos both work.
- `items[].worktree.main` — the repository's main worktree. Used as the repository identity, which collapses the `repo.branch` worktree siblings in the root into one entry per repository. A non-git directory makes `wt list` exit non-zero and is skipped.
- the item whose `branch` equals the default branch — the worktree the fast-forward lands in, so the pull is correct even when the main worktree sits on a feature branch.
- `upstream.remote`, `upstream.branch`, `upstream.ahead`, `upstream.behind` — the fast-forward decision.
- `worktree.changes` — reported as `dirty` next to the result.

Worktrunk exposes no fetch or pull command, so the two remote operations use git directly in the worktree worktrunk selected: `git fetch --prune`, then `git merge --ff-only <remote>/<branch>` when `behind > 0` and `ahead == 0`. The listing is re-read after the fetch to get fresh divergence counts.

Results per repository: `updated`, `up-to-date`, `skipped`, or `failed`. Exit status is non-zero if any repository failed.

## Notes

- Fast-forward only. The script never creates, moves, promotes, or removes a worktree and never switches a branch, so unmerged local work stays untouched. Use `wts` / `wtr` for those.
- Feature-branch worktrees are not updated. Only the default branch of each repository moves.
- The JSON schema is pinned to 2 with `--config-set list.json-schema=2`; schema 1 nests the same fields differently and the script does not read it.
- Repository identity is lowercased before comparison. macOS records worktree paths case-insensitively, so a linked worktree can report the main path as `~/Repos/...` while the parent reports `~/repos/...`; without the fold that repository is refreshed twice.
- Fetch is sequential. A root with many remotes takes time; let it finish instead of interrupting.
- Run `wtl` afterwards to inspect a repository whose result needs a closer look.

## Edge cases

- **Diverged default branch:** reported `failed` with the ahead and behind counts. No merge is attempted. The user decides whether to rebase or reset.
- **Dirty worktree:** the fast-forward is still attempted. Git refuses it when local changes would be overwritten, which surfaces as `failed`.
- **No upstream for the default branch:** reported `skipped`, nothing is changed.
- **Empty repository (no commits):** reported `skipped` with `no commits`.
- **Default branch checked out in no worktree:** reported `skipped`. Create one with `wts <default-branch>` and run again.
- **`wt` missing from PATH:** the script exits before touching any repository. Worktrunk is a hard requirement, not a convenience.
