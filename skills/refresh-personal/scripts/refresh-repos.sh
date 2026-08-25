#!/usr/bin/env bash
set -uo pipefail

root="${1:-$HOME/repos/personal}"
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
        ($target.upstream.branch // ""),
        ($target.upstream.ahead // 0),
        ($target.upstream.behind // 0),
        ($target.head.short_sha // ""),
        (if ($target.worktree.changes // {} | to_entries | map(select(.key != "diff") | .value) | any) then "dirty" else "clean" end)
      ]
    | @tsv
'

report() { printf '%-38s %-22s %-12s %s\n' "$1" "$2" "$3" "$4"; }

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

    row=$(printf '%s' "$listing" | jq -r "$DEFAULT_BRANCH_ROW" 2>/dev/null) || continue
    IFS=$'\t' read -r repo_key default_branch target has_head _ _ _ _ _ _ <<<"$row"
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

    if [ "$has_head" = "no" ]; then
        report "$name" "$default_branch" "skipped" "no commits"
        skipped=$((skipped + 1))
        continue
    fi

    if ! fetch_error=$(git -C "$target" fetch --prune 2>&1 >/dev/null); then
        report "$name" "$default_branch" "failed" "fetch: $(printf '%s' "$fetch_error" | tail -1)"
        failed=$((failed + 1))
        continue
    fi

    row=$(worktrunk_list "$target" | jq -r "$DEFAULT_BRANCH_ROW")
    IFS=$'\t' read -r _ _ _ _ remote remote_branch ahead behind short_sha worktree_state <<<"$row"

    location=""
    [ "$target" = "$repo_key" ] || location=" in $(basename "$target")"
    suffix="$location"
    [ "$worktree_state" = "clean" ] || suffix=" $worktree_state$location"

    if [ -z "$remote" ]; then
        report "$name" "$default_branch" "skipped" "no upstream$suffix"
        skipped=$((skipped + 1))
        continue
    fi

    if [ "$behind" -eq 0 ]; then
        report "$name" "$default_branch" "up-to-date" "$short_sha$suffix"
        current=$((current + 1))
        continue
    fi

    if [ "$ahead" -gt 0 ]; then
        report "$name" "$default_branch" "failed" "diverged: ahead $ahead, behind $behind$suffix"
        failed=$((failed + 1))
        continue
    fi

    if ! merge_error=$(git -C "$target" merge --ff-only "$remote/$remote_branch" 2>&1 >/dev/null); then
        report "$name" "$default_branch" "failed" "$(printf '%s' "$merge_error" | tail -1)"
        failed=$((failed + 1))
        continue
    fi

    after=$(git -C "$target" rev-parse --short HEAD)
    report "$name" "$default_branch" "updated" "$short_sha -> $after (+$behind)$suffix"
    updated=$((updated + 1))
done

echo
echo "updated=$updated up-to-date=$current skipped=$skipped failed=$failed"
[ "$failed" -eq 0 ]
