#!/usr/bin/env bash
# poll-feedback.sh: Poll authored GitHub PRs for review verdicts, unresolved threads,
# follow-up comments inside resolved threads, and CI/merge status.
#
# Usage:
#   poll-feedback.sh [<pr-number> ...] [--repo OWNER/NAME] [--json]
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

repo=""
as_json=0
prs=()

while (($#)); do
  case "$1" in
    --repo) repo="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --json) as_json=1; shift ;;
    -h|--help)
      echo "usage: poll-feedback.sh [<pr-number> ...] [--repo OWNER/NAME] [--json]"
      exit 0
      ;;
    --*) die "unknown flag: $1" ;;
    *)
      [[ $1 =~ ^[0-9]+$ ]] || die "PR number must be numeric, got '$1'"
      prs+=("$1")
      shift
      ;;
  esac
done

if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
fi
[[ -n $repo ]] || die "could not determine repository; pass --repo OWNER/NAME"

owner="${repo%%/*}"
name="${repo#*/}"

if ((${#prs[@]} == 0)); then
  mapfile -t prs < <(gh pr list --repo "$repo" --state open --json number --jq '.[].number')
fi

if ((${#prs[@]} == 0)); then
  if ((as_json)); then
    echo "[]"
  else
    echo "No open PRs found."
  fi
  exit 0
fi

results_json="[]"

for pr in "${prs[@]}"; do
  # shellcheck disable=SC2016 # $owner/$name/$pr are GraphQL variables
  pr_gql=$(gh api graphql -F owner="$owner" -F name="$name" -F pr="$pr" -f query='
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          number
          title
          state
          isDraft
          mergeStateStatus
          updatedAt
          headRefName
          baseRefName
          headRefOid
          author { login }
          commits(last: 1) {
            nodes {
              commit {
                oid
                statusCheckRollup {
                  state
                  contexts(first: 100) {
                    nodes {
                      __typename
                      ... on StatusContext {
                        context
                        state
                        description
                        targetUrl
                      }
                      ... on CheckRun {
                        name
                        status
                        conclusion
                      }
                    }
                  }
                }
              }
            }
          }
          comments(last: 50) {
            nodes {
              author { login }
              createdAt
              body
              url
            }
          }
          reviews(last: 50) {
            nodes {
              author { login }
              state
              submittedAt
              body
              url
            }
          }
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              path
              line
              comments(first: 50) {
                nodes {
                  databaseId
                  author { login }
                  createdAt
                  body
                  url
                }
              }
            }
          }
        }
      }
    }')

  pr_summary=$(jq -c '
    .data.repository.pullRequest as $pr |
    ($pr.headRefOid) as $head |
    ($pr.author.login) as $pr_author |
    (
      [
        ($pr.comments.nodes[]? | {body: .body, url: .url, createdAt: .createdAt}),
        ($pr.reviews.nodes[]?  | {body: .body, url: .url, createdAt: .submittedAt})
      ]
      | map(select(.body != null and (.body | contains("<!-- deep-pr-review "))))
      | sort_by(.createdAt)
      | last // null
    ) as $latest_verdict_comment |
    (
      if $latest_verdict_comment != null then
        ($latest_verdict_comment.body | capture("<!-- deep-pr-review head:(?<vhead>[0-9a-f]+) verdict:(?<verdict>[A-Z_]+) threads_open:(?<topen>[0-9]+) -->")) // null
      else null end
    ) as $parsed_marker |
    (
      $pr.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // []
      | map(select(.__typename == "StatusContext" and .context == "deep-pr-review"))
      | first // null
    ) as $deep_status |
    (
      $pr.reviewThreads.nodes // []
      | map({
          id: .id,
          isResolved: .isResolved,
          path: .path,
          line: (.line // 0),
          rootCommentId: (.comments.nodes[0].databaseId // 0),
          firstTitle: ((.comments.nodes[0].body // "") | split("\n") | map(select(length > 0)) | .[0] // ""),
          commentCount: (.comments.nodes | length),
          lastCommentId: (.comments.nodes[-1].databaseId // 0),
          lastCommentAt: (.comments.nodes[-1].createdAt // ""),
          lastCommentBody: (.comments.nodes[-1].body // ""),
          lastCommentUrl: (.comments.nodes[-1].url // ""),
          hasAuthorReply: ([.comments.nodes[1:][]? | select(.body | test("^(\\*\\*)?(Fixed|Declined|False [Pp]ositive|Addressed|Resolved|Escalated)"))] | length > 0),
          lastCommentIsReviewerFollowup: (
            (.comments.nodes | length) > 1 and
            ((.comments.nodes[-1].body // "") | contains("<!-- This is an auto-generated reply by CodeRabbit -->") | not) and
            ((.comments.nodes[-1].body // "") | contains("✅ Review thread resolved") | not) and
            ((.comments.nodes[-1].body // "") | test("^(\\*\\*)?(Fixed|Declined|False [Pp]ositive|Addressed|Resolved|Escalated)") | not)
          ),
          comments: (.comments.nodes | map({
            databaseId: .databaseId,
            author: .author.login,
            createdAt: .createdAt,
            body: .body,
            url: .url
          }))
        })
    ) as $threads |
    ($threads | map(select(.isResolved == false))) as $unresolved |
    ($threads | map(select(.isResolved == true and .lastCommentIsReviewerFollowup == true))) as $resolved_followups |
    (
      if ($parsed_marker != null and $parsed_marker.vhead == $head) then
        $parsed_marker.verdict
      elif ($deep_status != null and $deep_status.state == "success") then
        "APPROVED"
      elif ($deep_status != null and $deep_status.state == "failure") then
        "CHANGES_REQUESTED"
      else
        "PENDING_AT_HEAD"
      end
    ) as $head_verdict |
    (
      if ($pr.state != "OPEN") then
        $pr.state
      elif (($unresolved | length) > 0 or ($resolved_followups | length) > 0 or $head_verdict == "CHANGES_REQUESTED") then
        "ACTION NEEDED (FEEDBACK)"
      elif ($pr.mergeStateStatus == "DIRTY" or $pr.mergeStateStatus == "CONFLICTING") then
        "ACTION NEEDED (REBASE/CONFLICT)"
      elif ($head_verdict == "APPROVED" and ($unresolved | length) == 0 and ($resolved_followups | length) == 0) then
        "APPROVED (READY FOR MERGE)"
      else
        "AWAITING REVIEWER APPROVAL"
      end
    ) as $shepherd_status |
    {
      number: $pr.number,
      title: $pr.title,
      state: $pr.state,
      headRefName: $pr.headRefName,
      baseRefName: $pr.baseRefName,
      headRefOid: $head,
      shortHead: ($head[0:8]),
      updatedAt: $pr.updatedAt,
      mergeStateStatus: $pr.mergeStateStatus,
      shepherdStatus: $shepherd_status,
      verdictAtHead: $head_verdict,
      latestVerdictSha: ($parsed_marker.vhead // null),
      latestVerdict: ($parsed_marker.verdict // null),
      latestVerdictUrl: ($latest_verdict_comment.url // ($deep_status.targetUrl // null)),
      deepStatusState: ($deep_status.state // "none"),
      deepStatusDescription: ($deep_status.description // ""),
      unresolvedCount: ($unresolved | length),
      resolvedFollowupCount: ($resolved_followups | length),
      unresolvedThreads: $unresolved,
      resolvedFollowupThreads: $resolved_followups
    }
  ' <<<"$pr_gql")

  results_json=$(jq -c --argjson item "$pr_summary" '. + [$item]' <<<"$results_json")
done

if ((as_json)); then
  jq . <<<"$results_json"
else
  jq -r '.[] | "#\(.number)\t\(.shortHead)\t\(.mergeStateStatus)\t\(.verdictAtHead)\tunresolved=\(.unresolvedCount)\tfollowup=\(.resolvedFollowupCount)\t\(.shepherdStatus)\t\(.title)"' <<<"$results_json"
fi
