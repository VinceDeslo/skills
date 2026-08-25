#!/usr/bin/env bash
set -uo pipefail

root="${1:-$HOME/repos/work}"
root="${root%/}"

for required in wt jq git; do
    command -v "$required" >/dev/null 2>&1 || { echo "missing dependency: $required" >&2; exit 1; }
done

if [ ! -d "$root" ]; then
    echo "root not found: $root" >&2
    exit 1
fi

worktrunk_list() {
    command wt -C "$1" --config-set list.json-schema=2 list --format json --no-progressive 2>/dev/null
}

DEFAULT_BRANCH_ROW='
    .repo.default_branch as $default
    | (.items[] | select(.worktree.main == true) | .worktree.path) as $repo_key
    | [ .items[] | select(.branch == $default and .worktree.path != null) ][0] as $target
    | [ $repo_key,
        $default,
        ($target.worktree.path // ""),
        (if $target.head == null then "no" else "yes" end),
        ($target.upstream.remote // ""),
        ($target.upstream.ahead // 0),
        ($target.upstream.behind // 0),
        ($target.head.short_sha // ""),
        (if ($target.worktree.changes // {} | to_entries | map(select(.key != "diff") | .value) | any) then "dirty" else "" end)
      ]
    | .[]
'

report() { printf '%-38s %-22s %-12s %s\n' "$1" "$2" "$3" "$4"; }

first_error_line() {
    printf '%s\n' "$1" | grep -m1 -E '^(fatal|error):' || printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | tail -1
}

updated=0
current=0
skipped=0
failed=0
seen="|"

report REPO BRANCH RESULT DETAIL

for candidate in "$root"/*; do
    [ -d "$candidate" ] || continue

    listing=$(worktrunk_list "$candidate") || continue
    [ -n "$listing" ] || continue

    fields=$(printf '%s' "$listing" | jq -r "$DEFAULT_BRANCH_ROW" 2>/dev/null) || continue
    {
        read -r repo_key
        read -r default_branch
        read -r target
        read -r has_head
        read -r remote
        read -r ahead
        read -r behind
        read -r before
        read -r dirty
    } <<<"$fields"
    [ -n "$repo_key" ] || continue

    repo_id=$(printf '%s' "$repo_key" | tr '[:upper:]' '[:lower:]')
    case "$seen" in
        *"|$repo_id|"*) continue ;;
    esac
    seen="$seen$repo_id|"
    name=$(basename "$repo_key")

    if [ -z "$target" ]; then
        report "$name" "$default_branch" "skipped" "no worktree on $default_branch — create one with wts $default_branch"
        skipped=$((skipped + 1))
        continue
    fi

    location=""
    [ "$target" = "$repo_key" ] || location=" in $(basename "$target")"
    suffix="${dirty:+ $dirty}$location"

    if [ "$has_head" = "no" ]; then
        report "$name" "$default_branch" "skipped" "no commits"
        skipped=$((skipped + 1))
        continue
    fi

    if [ -z "$remote" ]; then
        report "$name" "$default_branch" "skipped" "no upstream$suffix"
        skipped=$((skipped + 1))
        continue
    fi

    if ! pull_error=$(git -C "$target" pull --ff-only --prune 2>&1 >/dev/null); then
        { read -r ahead; read -r behind; } <<<"$(worktrunk_list "$target" | jq -r "$DEFAULT_BRANCH_ROW" | sed -n '6p;7p')"
        report "$name" "$default_branch" "failed" "ahead $ahead, behind $behind$suffix: $(first_error_line "$pull_error")"
        failed=$((failed + 1))
        continue
    fi

    after=$(git -C "$target" rev-parse --short HEAD)

    if [ "$before" = "$after" ]; then
        report "$name" "$default_branch" "up-to-date" "$after$suffix"
        current=$((current + 1))
        continue
    fi

    report "$name" "$default_branch" "updated" "$before -> $after$suffix"
    updated=$((updated + 1))
done

echo
echo "updated=$updated up-to-date=$current skipped=$skipped failed=$failed"
[ "$failed" -eq 0 ]
