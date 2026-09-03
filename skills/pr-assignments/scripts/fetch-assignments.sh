#!/usr/bin/env bash
# Collect every open PR whose review is requested from the authenticated user
# (directly or via one of their teams) and emit one normalized JSON array on stdout.
# Read-only: every call is a GET/GraphQL query. Requires only the GitHub CLI.
set -euo pipefail

limit="${1:-40}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query_file="$here/pr-query.graphql"
filter_file="$here/normalize.jq"

for f in "$query_file" "$filter_file"; do
  [ -r "$f" ] || { echo "missing $f" >&2; exit 1; }
done

command -v gh >/dev/null || { echo "gh not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated: run 'gh auth login'" >&2; exit 1; }

targets="$(mktemp "${TMPDIR:-/tmp}/pr-assignments-targets.XXXXXX")"
trap 'rm -f "$targets"' EXIT INT TERM

me="$(gh api graphql -f query='{viewer{login}}' --jq '.data.viewer.login')"

# read:org may be missing, in which case team-requested PRs are simply invisible.
team_paths="$(gh api "user/teams?per_page=100" \
  --jq '.[] | "\(.organization.login)/\(.slug)"' 2>/dev/null || true)"
teams="$(printf '%s\n' "$team_paths" | sed 's|.*/||' | grep . | sort -u \
  | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR>1 ? "," : ""), $0} END{printf "]"}')"
[ -n "$teams" ] || teams='[]'

# Union of direct and team review requests, de-duplicated on repo#number.
{
  gh search prs --review-requested="@me" --state=open --limit "$limit" \
    --json number,repository --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"'
  for t in $team_paths; do
    gh search prs --state=open --limit "$limit" "team-review-requested:$t" \
      --json number,repository --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"' || true
  done
} | grep . | sort -u > "$targets"

printf '['
first=1
while IFS='#' read -r nwo number; do
  [ -n "${number:-}" ] || continue
  owner="${nwo%%/*}"
  repo="${nwo##*/}"
  prelude="(\"$me\") as \$me | ($teams) as \$teams | (\"$nwo\") as \$repoFull |"
  record="$(gh api graphql \
      -F owner="$owner" -F repo="$repo" -F number="$number" \
      -F query=@"$query_file" \
      --jq "$prelude $(cat "$filter_file")" 2>/dev/null)" || {
    echo "warn: could not fetch $nwo#$number" >&2
    continue
  }
  [ -n "$record" ] || continue
  [ "$first" -eq 1 ] || printf ','
  first=0
  printf '%s' "$record"
done < "$targets"
printf ']\n'
