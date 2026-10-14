# Safety catalog

Every path the report lists falls in exactly one tier. The tier decides whether a cleanup command
appears for it. When a path matches nothing below, it is **Keep** — the default is never to clear.

## Tiers

| Tier | Meaning | Command in report |
| --- | --- | --- |
| **Safe** | Regenerated on demand by the tool that owns it. Clearing costs only a re-download or rebuild. | Yes |
| **Review** | Regenerable, but clearing loses something the user may want: a large model download, a built artifact for an active branch, simulator state, a stopped container's writable layer. | Yes, marked review |
| **Keep** | User data, configuration, credentials, system state, or anything unknown. | No — listed for size only |

## Safe

Prefer the owning tool's own clean command over `rm`. It knows its layout and its locks.

| Path or object | Owner | Command |
| --- | --- | --- |
| `go env GOCACHE` (`~/Library/Caches/go-build`, `~/.cache/go-build`) | Go | `go clean -cache` |
| `~/Library/Caches/goimports`, `~/Library/Caches/gopls` | Go tooling | `rm -rf "<path>"` |
| `~/.npm/_cacache` | npm | `npm cache clean --force` |
| `~/.bun/install/cache` | Bun | `bun pm cache rm` |
| `~/.local/share/pnpm/store` | pnpm | `pnpm store prune` |
| `~/.cache/uv` | uv | `uv cache clean` (or `uv cache prune` to keep in-use entries) |
| `~/.cache/pip`, `~/Library/Caches/pip` | pip | `pip cache purge` |
| `brew --cache` | Homebrew | `brew cleanup --prune=all` |
| `~/.cargo/registry/cache` | Cargo | `rm -rf ~/.cargo/registry/cache` (sources and index rebuild on next build) |
| `~/.gradle/caches` | Gradle | `rm -rf ~/.gradle/caches` with no Gradle daemon running (`gradle --stop`) |
| `~/Library/Developer/Xcode/DerivedData` | Xcode | `rm -rf ~/Library/Developer/Xcode/DerivedData` with Xcode closed |
| `~/Library/Developer/CoreSimulator/Caches` | Simulator | `xcrun simctl delete unavailable` then `rm -rf` the Caches dir |
| `~/.terraform.d/plugin-cache` | Terraform | `rm -rf ~/.terraform.d/plugin-cache/*` (keep the dir; config points at it) |
| Browser caches under `~/Library/Caches/<Browser>` | Browser | Clear from the browser's own settings, or `rm -rf` with the browser quit |
| Per-app dirs under `~/Library/Caches/<bundle-id>` | That app | `rm -rf "<path>"` with the app quit |
| `~/.Trash`, `~/.local/share/Trash` | OS | Empty Trash from Finder / file manager |
| Dangling Docker images | Docker | `docker image prune` |
| Docker build cache | Docker | `docker builder prune` |
| Nix store paths with no GC root | Nix | `nix-collect-garbage` (never `-d` without asking: it removes rollback generations) |

## Review

| Path or object | Why review | Command |
| --- | --- | --- |
| Build dirs (`target`, `node_modules`, `.next`, `.terraform`, `.venv`, …) that are git-**ignored** | Rebuild costs time; a worktree may be in active use | `rm -rf "<path>"`, or `cargo clean` in the crate root for `target` |
| Build dirs in a worktree whose branch is merged | Usually dead weight | Suggest the `prune-trees` skill rather than deleting build dirs piecemeal |
| `~/.cache/huggingface` | Model downloads, often tens of GB, slow to re-fetch | `hf cache delete` (interactive) or `rm -rf` one model dir |
| `go env GOMODCACHE` | Re-download on next build; offline builds break | `go clean -modcache` |
| `~/.m2/repository` | Maven re-downloads; some artifacts may be locally installed only | `rm -rf ~/.m2/repository/<group>` per group |
| `~/Library/Developer/Xcode/Archives`, `iOS DeviceSupport` | Archives may be needed for symbolication | `rm -rf` per entry the user names |
| `~/Library/Developer/CoreSimulator/Devices` | Holds simulator app data | `xcrun simctl delete unavailable` only |
| Stopped Docker containers | Writable layer may hold state | `docker container prune` |
| Dangling Docker volumes | Volumes hold data (databases) by design | `docker volume prune` — list names first, never `-a` |
| Unused (non-dangling) Docker images | Pull cost; may be base images for local work | `docker image prune -a` |
| `~/Library/Logs`, `/var/tmp` | Logs may be needed for a live investigation | `rm -rf` older entries only |
| Old Nix profile generations | Removes rollback points | `nix-collect-garbage --delete-older-than 14d` |

## Keep — never emit a delete command

- Any build-named dir that is git-**tracked** or **untracked** (not ignored). A `build/` or `dist/`
  dir checked into the repo is source; an untracked one may be unsaved work.
- Anything under `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`,
  `~/repos` outside the build dirs above, `~/.ssh`, `~/.gnupg`, `~/.config`, `~/.local/share`
  (except Trash and the pnpm store), `~/Library/Application Support`, `~/Library/Containers` (except
  the Docker data dir, which is managed only through `docker` commands), `~/Library/Group
  Containers`, `~/Library/Mail`, `~/Library/Messages`, `~/Library/Keychains`, `~/Library/Mobile
  Documents`.
- `/nix/store` directly — only `nix-collect-garbage` touches it.
- `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private/var` except `/private/var/tmp`, `/opt`,
  `/Applications`.
- Docker's VM disk image (`Docker.raw`) or OrbStack's data image — shrink only through the app.
- `$TMPDIR` as a whole: running processes hold files there. Report its size; suggest a reboot, not
  `rm`.
- `~/.cache` as a whole: classify its children individually; the parent itself is never cleared.
- Agent state such as `~/.claude`, `~/.codex`, `~/.cache/claude*`: sessions and config live beside
  caches.

## Command rules

- Quote every path. Paths under `~/Library` routinely contain spaces.
- Never emit `sudo`, `rm -rf /…` on a system path, `rm` with a glob that could expand to `~`, or
  `find … -delete`.
- Never emit `docker system prune -a --volumes`, `docker volume prune -a`, or `nix-collect-garbage -d`.
- Each command removes one target and stands alone, so the user can copy only the lines they want.
- Order commands Safe first, then Review, each by reclaimable size descending.
