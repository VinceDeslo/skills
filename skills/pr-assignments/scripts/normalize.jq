def trunc($n): if type == "string" then (if (.|length) > $n then (.[0:$n] + " …[truncated]") else . end) else "" end;
def name: (.requestedReviewer.login // .requestedReviewer.slug // "");
def ctxname: (.name // .context // "unknown");
def ctxstate: (.conclusion // .status // .state // "UNKNOWN");

.data.repository.pullRequest
| . as $pr
| ([$pr.timelineItems.nodes[] | select(.__typename == "ReviewRequestedEvent")]) as $reqs
| ([$reqs[] | select(name == $me)] | sort_by(.createdAt) | last) as $direct
| ([$reqs[] | select(name | IN($teams[]))] | sort_by(.createdAt) | last) as $viaTeam
| ([$pr.timelineItems.nodes[] | select(.__typename == "ReadyForReviewEvent")] | sort_by(.createdAt) | last) as $ready
| ([$pr.reviews.nodes[] | select(.author.login == $me)] | sort_by(.submittedAt)) as $mine
# Peer review: one decisive state per other reviewer. The author is excluded — their
# replies to review threads are recorded as COMMENTED reviews and are not peer review.
# GitHub ignores COMMENTED when deciding whether someone signed off, so it only counts
# here when nothing stronger exists.
| ($pr.author.login // "ghost") as $prAuthor
| ([$pr.reviews.nodes[]
    | select((.author.login // "ghost") | . != $me and . != $prAuthor)
    | select(.state != "PENDING")]) as $peerReviews
| ($peerReviews
   | group_by(.author.login // "ghost")
   | map(
       ([.[] | select(.state | IN("APPROVED", "CHANGES_REQUESTED", "DISMISSED"))]
        | sort_by(.submittedAt) | last) as $decisive
       | {
           author: (.[0].author.login // "ghost"),
           state: ($decisive.state // "COMMENTED"),
           at: ($decisive.submittedAt // ([.[].submittedAt] | sort | last))
         })) as $peers
| ([$peers[] | select(.state == "APPROVED")]) as $peerApprovals
| ([$peers[] | select(.state == "CHANGES_REQUESTED")]) as $peerBlocks
| (if ($peerBlocks | length) > 0 then "changes_requested"
   elif ($peerApprovals | length) > 0 then "approved"
   elif ([$peers[] | select(.state == "COMMENTED")] | length) > 0 then "commented"
   else "none" end) as $peerState
| (($pr.commits.nodes[0].commit.statusCheckRollup) // null) as $roll
| (($roll.contexts.nodes) // []) as $ctx
| ([$pr.reviewRequests.nodes[] | name]) as $pending
| (($pending | index($me)) != null) as $pendingMe
| ([$pending[] | select(IN($teams[]))]) as $pendingTeams
| (if $pendingMe then "direct"
   elif ($pendingTeams | length) > 0 then "team"
   elif $direct then "direct"
   elif $viaTeam then "team"
   else "unattributed" end) as $origin
| ($direct.createdAt // $viaTeam.createdAt // $ready.createdAt // $pr.createdAt) as $requestedAt
# Drop anything whose review clock started before the window.
| select($requestedAt >= ($cutoff + "T00:00:00Z"))
| {
  repo: $repoFull,
  number: $pr.number,
  url: $pr.url,
  title: $pr.title,
  author: ($pr.author.login // "ghost"),
  isDraft: $pr.isDraft,
  state: $pr.state,
  reviewDecision: ($pr.reviewDecision // "NONE"),
  createdAt: $pr.createdAt,
  updatedAt: $pr.updatedAt,
  size: { additions: $pr.additions, deletions: $pr.deletions, files: $pr.changedFiles },
  branches: { base: $pr.baseRefName, head: $pr.headRefName },
  labels: [$pr.labels.nodes[].name],
  body: ($pr.body | trunc(1500)),
  origin: $origin,
  originTeams: $pendingTeams,
  clock: {
    requestedAt: $requestedAt,
    source: (if $direct then "direct-request"
             elif $viaTeam then ("team-request:" + ($viaTeam | name))
             elif $ready then "ready-for-review"
             else "pr-opened" end)
  },
  stillRequested: ($pendingMe or ($pendingTeams | length) > 0),
  myReview: (if ($mine | length) == 0 then null else {
    latestState: ($mine | last | .state),
    latestAt: ($mine | last | .submittedAt),
    count: ($mine | length),
    states: [$mine[].state] | unique
  } end),
  otherReviews: [$pr.reviews.nodes[] | select(.author.login != $me) | {
    author: (.author.login // "ghost"), state: .state, at: .submittedAt, body: (.body | trunc(400))
  }],
  lastCommitAt: ($pr.commits.nodes[0].commit.committedDate // $pr.createdAt),
  peerReview: {
    state: $peerState,
    approvals: ($peerApprovals | length),
    changesRequested: ($peerBlocks | length),
    reviewers: [$peers[] | select(.state != "DISMISSED") | .author] | unique,
    latestAt: ([$peers[] | select(.state != "DISMISSED") | .at] | sort | last),
    # A sign-off that predates the newest commit no longer covers the code you are reading.
    stale: (
      ([$peers[] | select(.state | IN("APPROVED", "CHANGES_REQUESTED")) | .at] | sort | last) as $decidedAt
      | if $decidedAt == null then false
        else $decidedAt < ($pr.commits.nodes[0].commit.committedDate // $pr.createdAt) end
    )
  },
  ci: {
    rollup: ($roll.state // "NONE"),
    total: ($roll.contexts.totalCount // 0),
    failing: [$ctx[] | select(ctxstate | IN("FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED")) | ctxname],
    pending: [$ctx[] | select(ctxstate | IN("PENDING", "IN_PROGRESS", "QUEUED", "WAITING", "REQUESTED", "EXPECTED")) | ctxname]
  },
  issueComments: [$pr.comments.nodes[] | {
    author: (.author.login // "ghost"), at: .createdAt, body: (.body | trunc(600))
  }],
  reviewThreads: [$pr.reviewThreads.nodes[] | {
    path: .path, resolved: .isResolved, outdated: .isOutdated,
    comments: [.comments.nodes[] | { author: (.author.login // "ghost"), at: .createdAt, body: (.body | trunc(400)) }]
  }]
}
