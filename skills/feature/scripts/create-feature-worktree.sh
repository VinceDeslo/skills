#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: create-feature-worktree.sh <linear-url-or-ticket-id> <slug>

Extracts the Linear ticket identifier, creates a worktree for the current
repository on branch <ticket-id>-<slug>, based on the current branch when it is
not the default branch, and prints:

  id=<TICKET-ID>
  branch=<branch>
  base=<base branch the new branch was cut from, or - when reused>
  path=<absolute worktree path>
  created=<true|false>

The slug is mandatory: derive it from the ticket title.
USAGE
  exit 2
}

[ $# -eq 2 ] || usage
command -v wt >/dev/null || { echo "worktrunk (wt) not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not on PATH" >&2; exit 1; }

raw=$1
slug=$2

ticket_id=$(printf '%s' "$raw" | grep -oiE '[a-z][a-z0-9_]*-[0-9]+' | head -n1 || true)
[ -n "$ticket_id" ] || { echo "no Linear ticket identifier found in: $raw" >&2; exit 1; }
ticket_id=$(printf '%s' "$ticket_id" | tr '[:lower:]' '[:upper:]')

slug=$(printf '%s' "$slug" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-40 \
  | sed -E 's/-+$//')
[ -n "$slug" ] || { echo "slug is empty after normalisation: $2" >&2; exit 1; }

branch=$(printf '%s' "$ticket_id" | tr '[:upper:]' '[:lower:]')-$slug

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not inside a git repository" >&2; exit 1; }

listing=$(wt --config-set list.json-schema=2 list --format json --no-progressive)

worktree_path() {
  printf '%s' "$1" | jq -r --arg b "$2" \
    '.items[] | select(.branch == $b) | .worktree.path' | head -n1
}

default_branch=$(printf '%s' "$listing" | jq -r '.repo.default_branch // ""')
current_branch=$(printf '%s' "$listing" | jq -r \
  '.items[] | select(.worktree.current == true and .worktree.detached == false) | .branch' | head -n1)

if [ -n "$current_branch" ] && [ "$current_branch" != "$default_branch" ]; then
  base=$current_branch
else
  base=${default_branch:-HEAD}
fi

existing=$(worktree_path "$listing" "$branch")
if [ -n "$existing" ]; then
  created=false
  base=-
else
  wt switch --create "$branch" --base "$base" --yes >&2
  created=true
  existing=$(worktree_path "$(wt --config-set list.json-schema=2 list --format json --no-progressive)" "$branch")
fi

[ -n "$existing" ] || { echo "worktree for $branch not found after creation" >&2; exit 1; }

printf 'id=%s\nbranch=%s\nbase=%s\npath=%s\ncreated=%s\n' \
  "$ticket_id" "$branch" "$base" "$existing" "$created"
