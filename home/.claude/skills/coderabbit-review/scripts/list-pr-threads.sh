#!/usr/bin/env bash
# List PR inline review threads as JSONL, with optional filters for
# resolved state, reply state, and head author.
#
# Default: only threads whose head author is `coderabbitai` (GraphQL
# reports app logins without the `[bot]` suffix REST uses).
# Override with `--author <login>` (exact match).
#
# Usage:
#   ./list-pr-threads.sh OWNER/REPO PR [--unresolved] [--unreplied] [--author <login>]
#
# Output (one JSON object per line):
#   {
#     "head_id": <int>,           # databaseId of the thread head comment
#     "path": <str>,
#     "line": <int|null>,
#     "resolved": <bool>,
#     "outdated": <bool>,         # diff has moved past this hunk
#     "reply_count": <int>,       # number of comments after the head
#     "head_author": <str>,
#     "head_body_excerpt": <str>  # first 120 chars of head body
#   }
#
# Limit: fetches up to 100 threads with up to 50 comments each (GraphQL
# `first:` caps). Larger PRs need pagination — extend the query if you
# hit the cap.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

unresolved=false
unreplied=false
author="coderabbitai"
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unresolved) unresolved=true; shift ;;
    --unreplied)  unreplied=true;  shift ;;
    --author)
      [[ $# -ge 2 ]] || { echo "error: --author needs a value" >&2; exit 2; }
      author="$2"; shift 2
      ;;
    -h|--help) usage 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done ;;
    -*) echo "error: unknown flag: $1" >&2; usage 2 ;;
    *)  positional+=("$1"); shift ;;
  esac
done

if [[ ${#positional[@]} -ne 2 ]]; then
  echo "error: expected OWNER/REPO and PR number" >&2
  usage 2
fi

repo="${positional[0]}"
pr="${positional[1]}"
owner="${repo%%/*}"
name="${repo##*/}"

if [[ -z "$owner" || -z "$name" || "$owner" == "$repo" ]]; then
  echo "error: invalid OWNER/REPO: $repo" >&2
  exit 2
fi

read -r -d '' query <<'GRAPHQL' || true
query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
          comments(first: 50) {
            nodes {
              databaseId
              author { login }
              path
              line
              body
            }
          }
        }
      }
    }
  }
}
GRAPHQL

gh api graphql \
  -f query="$query" \
  -F owner="$owner" \
  -F name="$name" \
  -F pr="$pr" \
  --jq "
    .data.repository.pullRequest.reviewThreads.nodes
    | map(select(
        (.comments.nodes[0].author.login == \"$author\")
        and (if $unresolved then (.isResolved | not) else true end)
        and (if $unreplied  then ((.comments.nodes | length) == 1) else true end)
      ))
    | .[]
    | {
        head_id: .comments.nodes[0].databaseId,
        path: .comments.nodes[0].path,
        line: .comments.nodes[0].line,
        resolved: .isResolved,
        outdated: .isOutdated,
        reply_count: ((.comments.nodes | length) - 1),
        head_author: .comments.nodes[0].author.login,
        head_body_excerpt: (.comments.nodes[0].body | .[0:120])
      }
    | @json
  "
