#!/usr/bin/env bash
set -uo pipefail

DEFAULT_ROOTS=("$HOME/repos/personal" "$HOME/repos/work")

usage() {
    cat <<'USAGE'
prune-trees.sh [--apply] [--min-age <age>] [root ...]

Removes worktrees merged into the default branch across every repository under
each root, via `wt step prune`.

  (no flags)        preview only — nothing is removed
  --apply           perform the removals
  --min-age <age>   skip worktrees younger than this (wt default: 1d)
  root ...          override the default roots (~/repos/personal ~/repos/work)
USAGE
}

mode=preview
min_age=""
roots=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply) mode=apply ;;
        --min-age) min_age="${2:-}"; shift ;;
        --min-age=*) min_age="${1#*=}" ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) roots+=("$1") ;;
    esac
    shift
done

[ "${#roots[@]}" -gt 0 ] || roots=("${DEFAULT_ROOTS[@]}")

for required in wt jq; do
    command -v "$required" >/dev/null 2>&1 || { echo "missing dependency: $required" >&2; exit 1; }
done

stderr_file=$(mktemp)
trap 'rm -f "$stderr_file"' EXIT

worktrunk_list() {
    command wt -C "$1" --config-set list.json-schema=2 list --format json --no-progressive 2>/dev/null
}

MAIN_WORKTREE='[ .items[] | select(.worktree.main == true) | .worktree.path ][0] // empty'

ROWS='
    (if type == "array" then .[] else . end)
    | [ (.kind // "worktree"),
        (.branch // ""),
        (.path // ""),
        (if has("branch_outcome") then (.branch_outcome // "") else (if .branch_deleted then "deleted" else "kept" end) end),
        ((.reason // "") + (if (.target // "") == "" then "" else " " + .target end)),
        (.branch_checked_out_at // "")
      ]
    | join("\u001f")
'

trunc() {
    local text="$1" width="$2"
    if [ "${#text}" -gt "$width" ]; then
        printf '%s…' "${text:0:$((width - 1))}"
    else
        printf '%s' "$text"
    fi
}

row() { printf '%-22s %-44s %-12s %-14s %s\n' "$(trunc "$1" 22)" "$(trunc "$2" 44)" "$3" "$4" "$5"; }

first_error_line() {
    printf '%s\n' "$1" | grep -m1 -E '^(fatal|error|Error):' || printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | tail -1
}

repos=()
seen="|"
missing=0

for root in "${roots[@]}"; do
    root="${root%/}"

    if [ ! -d "$root" ]; then
        echo "root not found: ${root/#$HOME/~}" >&2
        missing=$((missing + 1))
        continue
    fi

    for candidate in "$root"/*; do
        [ -d "$candidate" ] || continue

        main=$(worktrunk_list "$candidate" | jq -r "$MAIN_WORKTREE" 2>/dev/null) || continue
        [ -n "$main" ] || continue

        key=$(printf '%s' "$main" | tr '[:upper:]' '[:lower:]')
        case "$seen" in
            *"|$key|"*) continue ;;
        esac
        seen="$seen$key|"
        repos+=("$main")
    done
done

if [ "$mode" = preview ]; then
    echo "preview — nothing is removed (${#repos[@]} repositories)"
else
    echo "pruning ${#repos[@]} repositories"
fi
echo
row REPO BRANCH KIND RESULT DETAIL

worktrees=0
branches=0
skipped=0
failed=0
clean=0

for repo in ${repos[@]+"${repos[@]}"}; do
    name=$(basename "$repo")

    args=(step prune --format json)
    [ -n "$min_age" ] && args+=(--min-age "$min_age")
    if [ "$mode" = preview ]; then
        args+=(--dry-run)
    else
        args+=(--foreground)
    fi

    if ! output=$(command wt -C "$repo" "${args[@]}" 2>"$stderr_file" </dev/null); then
        row "$name" "-" "-" "failed" "$(first_error_line "$(cat "$stderr_file")")"
        failed=$((failed + 1))
        continue
    fi

    rows=$(printf '%s' "$output" | jq -r "$ROWS" 2>/dev/null)
    if [ -z "$rows" ]; then
        clean=$((clean + 1))
        continue
    fi

    while IFS=$'\x1f' read -r kind branch path outcome reason checked_out; do
        [ -n "$kind" ] || continue

        detail="$reason"
        if [ "$mode" = apply ]; then
            detail="branch $outcome${reason:+, $reason}"
        elif [ "$outcome" = kept ]; then
            detail="${reason:+$reason, }branch kept"
        fi
        [ -n "$checked_out" ] && detail="$detail, checked out at $checked_out"

        if [ "$kind" = branch_only ]; then
            if [ "$mode" = preview ]; then
                row "$name" "$branch" "branch-only" "would delete" "$detail"
                branches=$((branches + 1))
            elif [ "$outcome" = deleted ]; then
                row "$name" "$branch" "branch-only" "deleted" "$detail"
                branches=$((branches + 1))
            else
                row "$name" "$branch" "branch-only" "skipped" "$detail"
                skipped=$((skipped + 1))
            fi
            continue
        fi

        if [ "$mode" = preview ]; then
            row "$name" "${branch:-$(basename "$path")}" "$kind" "would remove" "$detail"
        else
            row "$name" "${branch:-$(basename "$path")}" "$kind" "removed" "$detail"
        fi
        worktrees=$((worktrees + 1))
    done <<<"$rows"
done

echo
if [ "$mode" = preview ]; then
    echo "would remove: worktrees=$worktrees branches=$branches"
else
    echo "removed: worktrees=$worktrees branches=$branches"
fi
echo "clean=$clean skipped=$skipped failed=$((failed + missing))"
[ "$((failed + missing))" -eq 0 ]
