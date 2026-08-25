#!/usr/bin/env bash
set -uo pipefail

root="${1:-$HOME/repos/personal}"
root="${root%/}"

if [ ! -d "$root" ]; then
    echo "root not found: $root" >&2
    exit 1
fi

default_branch() {
    local repo="$1" ref
    ref=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    if [ -z "$ref" ]; then
        git -C "$repo" remote set-head origin --auto >/dev/null 2>&1
        ref=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    fi
    if [ -n "$ref" ]; then
        echo "${ref#origin/}"
        return
    fi
    for candidate in main master; do
        if git -C "$repo" show-ref --verify --quiet "refs/heads/$candidate"; then
            echo "$candidate"
            return
        fi
    done
}

worktree_holding_branch() {
    git -C "$1" worktree list --porcelain | awk -v want="refs/heads/$2" '
        /^worktree /  { path = substr($0, 10) }
        /^branch /    { if (substr($0, 8) == want) { print path; exit } }
    '
}

report() { printf '%-38s %-22s %-12s %s\n' "$1" "$2" "$3" "$4"; }

updated=0
current=0
skipped=0
failed=0

report REPO BRANCH RESULT DETAIL

for candidate in "$root"/*; do
    [ -d "$candidate" ] || continue
    [ -e "$candidate/.git" ] || continue

    name=$(basename "$candidate")
    gitdir=$(git -C "$candidate" rev-parse --path-format=absolute --git-dir 2>/dev/null) || continue
    commondir=$(git -C "$candidate" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
    [ "$gitdir" = "$commondir" ] || continue

    branch=$(default_branch "$candidate")
    if [ -z "$branch" ]; then
        report "$name" "-" "skipped" "no default branch"
        skipped=$((skipped + 1))
        continue
    fi

    worktree=$(worktree_holding_branch "$candidate" "$branch")
    if [ -z "$worktree" ]; then
        report "$name" "$branch" "skipped" "no worktree on $branch"
        skipped=$((skipped + 1))
        continue
    fi

    location=""
    [ "$worktree" = "$candidate" ] || location=" in $(basename "$worktree")"

    if ! fetch_output=$(git -C "$worktree" fetch --prune 2>&1); then
        report "$name" "$branch" "failed" "fetch: $(echo "$fetch_output" | tail -1)"
        failed=$((failed + 1))
        continue
    fi

    if ! upstream=$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name "$branch@{upstream}" 2>/dev/null); then
        report "$name" "$branch" "skipped" "no upstream${location}"
        skipped=$((skipped + 1))
        continue
    fi

    before=$(git -C "$worktree" rev-parse --short "$branch")
    after=$(git -C "$worktree" rev-parse --short "$upstream")

    if [ "$before" = "$after" ]; then
        report "$name" "$branch" "up-to-date" "$before${location}"
        current=$((current + 1))
        continue
    fi

    if ! merge_output=$(git -C "$worktree" merge --ff-only "$upstream" 2>&1); then
        report "$name" "$branch" "failed" "$(echo "$merge_output" | tail -1)"
        failed=$((failed + 1))
        continue
    fi

    report "$name" "$branch" "updated" "$before -> $after${location}"
    updated=$((updated + 1))
done

echo
echo "updated=$updated up-to-date=$current skipped=$skipped failed=$failed"
[ "$failed" -eq 0 ]
