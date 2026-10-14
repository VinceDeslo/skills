---
name: disk-cleanup
description: Find what can be safely cleared from the local disk — leftover Docker containers, volumes, images and build cache, package-manager and app caches, temporary files, Trash, and local codebase build output such as node_modules, target, .terraform, and .venv — with a strictly read-only du scan, classify every candidate as safe, review, or keep, and deliver an HTML report with the exact cleanup commands through the generate-artifact skill. Never deletes anything itself. Use when asked to free disk space, reclaim storage, find what is eating the disk, clean up caches, temp files, Docker leftovers, or build artifacts, or when the user says "disk-cleanup".
compatibility: Requires bash, du, df, find, and git. Optional — docker (daemon running), nix, brew, go for their sections. Delivery uses the generate-artifact skill. Paths are tuned for macOS and Linux.
---

# disk-cleanup

Answer one question: **what is using my disk, and what can I clear without breaking anything?**

Three properties define this skill:

- **Read-only.** The skill runs `du`, `df`, `find`, `git ls-files`, `git check-ignore`, and
  read-only `docker`/`nix-env` listings. It never runs a delete, prune, or clean command, even when
  asked during the run — it writes the commands into the report and the user runs them.
- **Temporary data only.** A path gets a cleanup command only when the
  [safety catalog](references/safety-catalog.md) classifies it as regenerable. Anything unknown is
  **Keep**. User data, config, credentials, and system state never get a command.
- **Prefer the owner's command.** `go clean -cache` over `rm -rf` on the Go cache; `docker image
  prune` over touching Docker's data dir.

## When to use

The user asks to free disk space, find what is consuming storage, clean caches, temp files, Docker
leftovers, or build output, or says "disk-cleanup". Optional input: the repo roots to search for
build output (default `~/repos`).

For removing whole merged worktrees, point at the `prune-trees` skill instead.

## Instructions

### 1. Scan

```bash
skill_dir=<this skill's directory>
out="${TMPDIR:-/tmp}/temp_disk_cleanup"
mkdir -p "$out"
"$skill_dir/scripts/scan.sh" ~/repos > "$out/scan.tsv" 2> "$out/scan.err"
```

The scan takes one to a few minutes on a large home. Pass extra repo roots as further arguments.

Output is TSV, one row per item: `section`, `kib`, `path-or-label`, and for builds a fourth column,
the git state.

| Section | Rows |
| --- | --- |
| `disk` | `total`, `used`, `available` for `/` |
| `top-home` | Every top-level entry of `$HOME` (symlinks skipped) |
| `candidate` | Known cache and temp locations, each `~/Library/Caches/*` child on macOS, `brew --cache`, `GOCACHE`, `GOMODCACHE` |
| `build` | Build-named dirs under the repo roots, with `ignored`, `tracked`, `untracked`, or `no-git` |
| `docker` | `docker system df` lines, stopped containers, dangling volumes and images (kib is 0; sizes are in the label) |
| `nix` | `/nix/store` size and user profile generation count |

`scan.err` holds `du` permission errors. Paths the scan could not read (macOS TCC on `~/Documents`,
`~/Desktop`, `~/Library/Mail`) are not candidates anyway; name the count in the method section.

If Docker is installed but the daemon is not running, the `docker` section is empty. Say so in the
report and give `docker system df` as the command to re-check once it is up — do not start the
daemon.

### 2. Classify

Read [references/safety-catalog.md](references/safety-catalog.md). Then for every row:

- Assign **Safe**, **Review**, or **Keep** by the catalog. No match means **Keep**.
- A `build` row is a candidate only when its git state is `ignored`. `tracked`, `untracked`, and
  `no-git` build dirs are **Keep** — listed, never given a command.
- Nested paths count once. `~/Library/Caches` and `~/Library/Caches/go-build` both appear; total the
  children and report the parent only as context. Never sum a parent and its child.
- Group build dirs per repository, and flag repos with several worktrees (`<repo>.<branch>` dirs)
  carrying the same heavy dir — that is the strongest hint to run `prune-trees`.
- Skip items under 100 MiB from the command list; fold them into one "small items" line.

### 3. Write the report

Start from the `generate-artifact` template. Sections, in order:

1. **Summary** — disk total, used, free, and the reclaimable total split Safe vs. Review, in three
   sentences at most. Lead with the biggest single win.
2. **Where the space goes** — a horizontal bar chart (inline SVG, turquoise and grey only) of the
   top 15 `top-home` entries plus `/nix/store` when present, and a table with size and tier.
3. **Safe to clear** — a table: path, size, owner, what regenerates it. Then one `<pre>` block with
   the commands, one per line, ordered by size descending.
4. **Review before clearing** — the same shape, plus a column stating what is lost.
5. **Build output** — per repository: worktree count, total size, heaviest dirs. Commands only for
   `ignored` dirs. Note any repo that would benefit from `prune-trees`.
6. **Docker** — the `system df` table, stopped containers, dangling volumes and images, with the
   prune commands from the catalog. Volume names are listed before `docker volume prune`.
7. **Kept** — large items that got no command, and one line each on why (user data, config,
   tracked build dir, system).
8. **Method** — commands run, roots scanned, unreadable path count, Docker state, and the statement
   that nothing was deleted.

Rules:

- Human sizes: `38.6 GB`, `412 MB`. Compute from KiB with 1024 multiples, and say so in Method.
- Every path, command, and tool name in `<code>`. Quote paths with spaces inside commands.
- Commands come only from the catalog's command column, adapted to the exact path. Never invent a
  flag. Never emit `sudo`, a glob reaching `~`, or any command the catalog's rules forbid.
- No ticket identifiers. Worktree names like `coast.TRK-670-additional-context` render with the
  identifier stripped: `coast.additional-context`.

### 4. Deliver

Save and serve with the `generate-artifact` skill:

```bash
report="$HOME/.artifacts/disk-cleanup-$(date +%Y%m%d-%H%M%S).html"
python3 <generate-artifact-dir>/scripts/check_artifact.py "$report"
python3 <generate-artifact-dir>/scripts/serve.py --open
```

If `generate-artifact` is not installed, write the file under `$out` and open it directly.

Summarize in chat in **three lines at most**: free space now, reclaimable Safe vs. Review, and the
artifact path with its URL. Then state that nothing was deleted.

## Edge cases

- **User asks the agent to run the cleanup:** decline in this skill's run. The report is the
  deliverable; the user copies the lines they choose. If they insist, they can ask for a specific
  command outside this skill and confirm it.
- **Docker Desktop or OrbStack data dir is huge but `docker system df` reclaimable is small:** the VM
  disk image does not shrink on prune. Say so; the fix is in the app's settings, not `rm`.
- **`/nix/store` is large:** report it, give `nix-collect-garbage` as Safe and
  `nix-collect-garbage --delete-older-than 14d` as Review. On nix-darwin or NixOS, system
  generations need `sudo` — mention that it exists, do not emit the command.
- **A build dir is `untracked`:** keep it. It may be output of an uncommitted generator, or work in
  progress.
- **`$TMPDIR` is large:** report it as Keep; a reboot clears it safely.
- **Scan is slow on a huge repo root:** narrow it by passing specific roots.
- **Linux:** the `~/Library` paths do not exist and are skipped; `~/.cache` children and
  `~/.local/share/Trash` carry the weight.
