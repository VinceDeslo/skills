#!/usr/bin/env bash
set -uo pipefail

usage() {
    echo "usage: clone-org.sh [--dry-run] <org> [root]" >&2
    echo "  default root: ~/repos/work" >&2
    exit 2
}

dry_run=no
positional=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=yes ;;
        -h|--help) usage ;;
        --*) echo "unknown flag: $arg" >&2; usage ;;
        *) positional+=("$arg") ;;
    esac
done

[ "${#positional[@]}" -ge 1 ] || usage
org="${positional[0]}"
root="${positional[1]:-$HOME/repos/work}"
root="${root%/}"

for required in gh git jq; do
    command -v "$required" >/dev/null 2>&1 || { echo "missing dependency: $required" >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated; run gh auth login" >&2; exit 1; }

if [ ! -d "$root" ]; then
    echo "root not found: $root" >&2
    exit 1
fi

report() { printf '%-38s %-12s %s\n' "$1" "$2" "$3"; }

normalize_remote() {
    sed -E 's#^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)##; s#\.git$##; s#/$##' | tr '[:upper:]' '[:lower:]'
}

remote_repos=$(gh repo list "$org" --no-archived --limit 1000 --json name --jq '.[].name' | sort -f) || {
    echo "failed to list repositories for $org" >&2
    exit 1
}
[ -n "$remote_repos" ] || { echo "no non-archived repositories found for $org" >&2; exit 1; }

local_repos=$(
    for candidate in "$root"/*/; do
        [ -d "$candidate" ] || continue
        git -C "$candidate" remote get-url origin 2>/dev/null
    done | normalize_remote | sort -u
)

org_lower=$(printf '%s' "$org" | tr '[:upper:]' '[:lower:]')

echo
echo "${root/#$HOME/~}  <-  github.com/$org"
report REPO RESULT DETAIL

cloned=0
present=0
conflict=0
failed=0
planned=0

while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    repo_lower=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')

    if printf '%s\n' "$local_repos" | grep -qx "$org_lower/$repo_lower"; then
        report "$repo" "present" ""
        present=$((present + 1))
        continue
    fi

    if [ -e "$root/$repo" ]; then
        report "$repo" "conflict" "$root/$repo exists but its origin is not $org/$repo"
        conflict=$((conflict + 1))
        continue
    fi

    if [ "$dry_run" = "yes" ]; then
        report "$repo" "missing" "would run: gh repo clone $org/$repo"
        planned=$((planned + 1))
        continue
    fi

    if clone_error=$(cd "$root" && gh repo clone "$org/$repo" 2>&1 >/dev/null); then
        report "$repo" "cloned" "$root/$repo"
        cloned=$((cloned + 1))
    else
        report "$repo" "failed" "$(printf '%s\n' "$clone_error" | grep -v '^[[:space:]]*$' | tail -1)"
        failed=$((failed + 1))
    fi
done <<<"$remote_repos"

echo
if [ "$dry_run" = "yes" ]; then
    echo "missing=$planned present=$present conflict=$conflict"
else
    echo "cloned=$cloned present=$present conflict=$conflict failed=$failed"
fi
[ "$((failed + conflict))" -eq 0 ]
