---
name: refresh-repos
description: Fast-forward the default branch of every repository under ~/repos/personal and ~/repos/work so local clones match their remotes, using worktrunk (wt) to discover repositories and worktrees. Use when asked to refresh, update, or pull the latest repos, the personal or work or infracost projects, or when the user says "refresh-repos".
compatibility: Requires bash, worktrunk (`wt`, https://worktrunk.dev), jq, git, checkout roots at ~/repos/personal and ~/repos/work, and fetch credentials for each remote (SSH keys or a credential helper).
---

# refresh-repos

Walk every repository under `~/repos/personal`, then every repository under `~/repos/work`, and fast-forward each default branch. Worktrunk is the source of truth for repository and worktree structure.

## When to use

The user asks to refresh, update, or pull the latest repos — personal, work, or both — or says "refresh-repos".

## Instructions

1. Run the walker from this skill directory:

   ```bash
   scripts/refresh-repos.sh
   ```

   With no arguments it processes `~/repos/personal` and then `~/repos/work`, sequentially, in that order. Pass roots as arguments to override the pair — `scripts/refresh-repos.sh ~/repos/work` for work only, or any other root.

2. Report both tables it prints, one line per repository, plus the combined summary counts.

3. For every `failed` line, name the repository and the error. Do not retry with `--force`, `--rebase`, or `reset --hard`; report and stop.

## What the script does

For each direct child directory of each root it runs:

```bash
wt -C <dir> --config-set list.json-schema=2 list --format json --no-progressive
```

and reads from that listing:

- `repo.default_branch` — the branch to refresh, so `main` and `master` repos both work.
- `items[].worktree.main` — the repository's main worktree. Used as the repository identity, which collapses the `repo.branch` worktree siblings in a root into one entry per repository. A non-git directory makes `wt list` exit non-zero and is skipped.
- the item whose `branch` equals the default branch — the worktree the fast-forward lands in, so the pull is correct even when the main worktree sits on a feature branch.
- `upstream.remote` — whether the default branch tracks anything at all.
- `worktree.changes` — reported as `dirty` next to the result.

Worktrunk exposes no fetch or pull command, so the update itself is one git command in the worktree worktrunk selected:

```bash
git -C <target> pull --ff-only --prune
```

`--ff-only` is what makes this safe to run unattended: the branch either fast-forwards or the pull refuses, so no merge commit and no rebase can appear behind your back. `--prune` drops remote-tracking refs for branches deleted on the forge, which otherwise accumulate for years. Nothing here needs a separate fetch — pull fetches first. `upstream.ahead` and `upstream.behind` are read from a second listing only when the pull fails, to say how far the branch diverged.

Results per repository: `updated`, `up-to-date`, `skipped`, or `failed`. The summary is combined across both roots, and the exit status is non-zero if any repository failed or a root is missing.

## Notes

- Fast-forward only. The script never creates, moves, promotes, or removes a worktree and never switches a branch, so unmerged local work stays untouched. Use `wts` / `wtr` for those.
- Feature-branch worktrees are not updated. Only the default branch of each repository moves.
- Roots are processed in sequence, and repositories within a root in alphabetical order. Repository identity is shared across roots, so the same repository reachable from both is refreshed once.
- The JSON schema is pinned to 2 with `--config-set list.json-schema=2`; schema 1 nests the same fields differently and the script does not read it.
- Repository identity is lowercased before comparison. macOS records worktree paths case-insensitively, so a linked worktree can report the main path as `~/Repos/...` while the parent reports `~/repos/...`; without the fold that repository is refreshed twice.
- Fetch is sequential. Roots with many remotes take time; let it finish instead of interrupting.
- Run `wtl` afterwards to inspect a repository whose result needs a closer look.

## Edge cases

- **Diverged default branch:** `--ff-only` refuses and the repository is reported `failed` with the ahead and behind counts. The user decides whether to rebase or reset.
- **Dirty worktree:** the pull is still attempted, and succeeds whenever the incoming commits do not touch the modified files. Otherwise git refuses and the repository is reported `failed` with the local changes named.
- **No upstream for the default branch:** reported `skipped`, nothing is changed.
- **Empty repository (no commits):** reported `skipped` with `no commits`.
- **Default branch checked out in no worktree:** reported `skipped`. Create one with `wts <default-branch>` and run again.
- **Missing root:** reported `failed` for that root; the other root is still processed.
- **`wt` missing from PATH:** the script exits before touching any repository. Worktrunk is a hard requirement, not a convenience.
