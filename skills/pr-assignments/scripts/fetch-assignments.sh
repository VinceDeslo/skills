#!/usr/bin/env bash
# Collect every open PR whose review was requested from the authenticated user
# (directly or via one of their teams) inside a recent window, and emit one
# normalized JSON array on stdout.
#
#   fetch-assignments.sh [days] [limit]
#     days   size of the review-request window, in calendar days (default 14)
#     limit  per-query result cap (default 40)
#
# Read-only: every call is a GET/GraphQL query. Requires only the GitHub CLI.
set -euo pipefail

days="${1:-14}"
limit="${2:-40}"

case "$days" in
  ''|*[!0-9]*) echo "days must be a positive integer, got '$days'" >&2; exit 1 ;;
esac

# A review request bumps the PR's updatedAt, so `updated:>=cutoff` is a safe
# superset of `requestedAt >= cutoff` and cheaply excludes long-dead PRs.
if cutoff="$(date -u -v-"${days}"d +%Y-%m-%d 2>/dev/null)"; then :
elif cutoff="$(date -u -d "${days} days ago" +%Y-%m-%d 2>/dev/null)"; then :
else echo "cannot compute a cutoff date with this 'date' implementation" >&2; exit 1; fi
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
    --updated=">=$cutoff" \
    --json number,repository --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"'
  for t in $team_paths; do
    gh search prs --state=open --limit "$limit" --updated=">=$cutoff" \
      "team-review-requested:$t" \
      --json number,repository --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"' || true
  done
} | grep . | sort -u > "$targets"

printf '['
first=1
outside=0
while IFS='#' read -r nwo number; do
  [ -n "${number:-}" ] || continue
  owner="${nwo%%/*}"
  repo="${nwo##*/}"
  prelude="(\"$me\") as \$me | ($teams) as \$teams | (\"$nwo\") as \$repoFull | (\"$cutoff\") as \$cutoff |"
  record="$(gh api graphql \
      -F owner="$owner" -F repo="$repo" -F number="$number" \
      -F query=@"$query_file" \
      --jq "$prelude $(cat "$filter_file")" 2>/dev/null)" || {
    echo "warn: could not fetch $nwo#$number" >&2
    continue
  }
  # The normalizer emits nothing for a PR whose review request predates the window.
  if [ -z "$record" ]; then
    outside=$((outside + 1))
    continue
  fi
  [ "$first" -eq 1 ] || printf ','
  first=0
  printf '%s' "$record"
done < "$targets"
printf ']\n'

[ "$outside" -eq 0 ] || \
  echo "note: $outside PR(s) excluded — review requested before $cutoff" >&2
