#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: create-feature-worktree.sh <linear-url-or-ticket-id> [slug]

Extracts the Linear ticket identifier, creates a worktree for the current
repository on branch <ticket-id>[-slug], and prints:

  id=<TICKET-ID>
  branch=<branch>
  path=<absolute worktree path>
  created=<true|false>
USAGE
  exit 2
}

[ $# -ge 1 ] || usage
command -v wt >/dev/null || { echo "worktrunk (wt) not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not on PATH" >&2; exit 1; }

raw=$1
slug=${2:-}

ticket_id=$(printf '%s' "$raw" | grep -oiE '[a-z][a-z0-9_]*-[0-9]+' | head -n1 || true)
[ -n "$ticket_id" ] || { echo "no Linear ticket identifier found in: $raw" >&2; exit 1; }
ticket_id=$(printf '%s' "$ticket_id" | tr '[:lower:]' '[:upper:]')

prefix=$(printf '%s' "$ticket_id" | tr '[:upper:]' '[:lower:]')
if [ -n "$slug" ]; then
  slug=$(printf '%s' "$slug" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-40 \
    | sed -E 's/-+$//')
fi
branch=$prefix${slug:+-$slug}

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not inside a git repository" >&2; exit 1; }

worktree_path() {
  wt --config-set list.json-schema=2 list --format json --no-progressive \
    | jq -r --arg b "$1" '.items[] | select(.branch == $b) | .worktree.path' \
    | head -n1
}

existing=$(worktree_path "$branch")
if [ -n "$existing" ]; then
  created=false
else
  wt switch --create "$branch" --yes >&2
  created=true
  existing=$(worktree_path "$branch")
fi

[ -n "$existing" ] || { echo "worktree for $branch not found after creation" >&2; exit 1; }

printf 'id=%s\nbranch=%s\npath=%s\ncreated=%s\n' "$ticket_id" "$branch" "$existing" "$created"
