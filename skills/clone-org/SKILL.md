---
name: clone-org
description: Clone every non-archived repository of a GitHub organization that is not yet checked out locally, by listing the org with the GitHub CLI, diffing it against the clones already under a root directory, and running `gh repo clone <org>/<repo>` for each missing one. Defaults to the infracost org into ~/repos/work. Use when asked to clone, mirror, sync down, or check out all the repos of an org, to find repos missing locally, or when the user says "clone-org".
compatibility: Requires bash, GitHub CLI (`gh`) authenticated against github.com with read access to the organization, git, jq, and clone credentials (SSH keys or a credential helper) for the configured `gh` protocol.
---

# clone-org

List the non-archived repositories of a GitHub organization, compare them with what is already cloned under a local root, and clone the missing ones. The first use case is the `infracost` org into `~/repos/work`.

## When to use

The user asks to clone, mirror, or check out every repo of an organization, asks which org repos are missing locally, or says "clone-org".

## Instructions

1. Preview the diff from this skill directory. With no root the script uses `~/repos/work`:

   ```bash
   scripts/clone-org.sh --dry-run infracost
   ```

   Pass another org or root as needed: `scripts/clone-org.sh --dry-run <org> <root>`.

2. Show the user the `missing` rows and the summary line, then wait for approval. Cloning tens of repositories is slow and fills the disk, so never skip this step.

3. On approval run the same command without `--dry-run`:

   ```bash
   scripts/clone-org.sh infracost
   ```

4. Report the table it prints, one line per repository, plus the summary counts. For every `failed` or `conflict` line, name the repository and the reason. Do not delete or move anything to resolve a conflict; report and stop.

## What the script does

Remote inventory, one call:

```bash
gh repo list <org> --no-archived --limit 1000 --json name --jq '.[].name'
```

Local inventory: for each direct child directory of the root it reads `git remote get-url origin`, strips the `git@github.com:`, `ssh://git@github.com/`, or `https://github.com/` prefix and the `.git` suffix, and lowercases the result to an `org/repo` key. Worktree siblings named `<repo>.<branch>` share the origin of their repository, so they collapse into the same key and never trigger a duplicate clone. A directory that is not a git repository contributes nothing.

Each remote repository is then classified:

- `present` — its `org/repo` key is in the local inventory.
- `conflict` — nothing local has that origin, but `<root>/<repo>` already exists. Nothing is touched.
- `missing` — with `--dry-run`, the clone that would run.
- `cloned` or `failed` — without `--dry-run`, the outcome of `gh repo clone <org>/<repo>` executed with the root as working directory, so the clone lands in `<root>/<repo>`.

The exit status is non-zero if any repository failed or conflicted, or if the org listing, `gh` authentication, or the root is missing.

## Notes

- Only non-archived repositories are considered. Forks owned by the org are included; archived repos are never cloned.
- Clones are sequential and in case-insensitive alphabetical order. Let it finish instead of interrupting.
- The remote protocol comes from `gh` configuration (`gh config get git_protocol`), not from the script.
- The script never fetches, pulls, or modifies an existing clone. Use `refresh-repos` for that.
- The listing is capped at 1000 repositories per org.

## Edge cases

- **Repository cloned under a different directory name:** matched by origin URL, so it is `present` regardless of directory name.
- **Directory exists with another origin, or no git repository:** reported `conflict`, skipped. The user decides whether to move or remove it.
- **Private repository the token cannot read:** absent from the listing, so it is silently not cloned. Check `gh auth status` scopes if the count looks low.
- **Clone interrupted:** a partial `<root>/<repo>` directory is left behind and reported `conflict` on the next run. Remove it by hand and run again.
- **`gh` not authenticated:** the script exits before listing or cloning anything.
