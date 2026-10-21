#!/usr/bin/env bash
# reply-thread.sh: Reply in-thread to a GitHub PR review comment (by PRRT_... thread ID
# or numeric comment databaseId) and optionally resolve the review thread via GraphQL.
#
# Usage:
#   reply-thread.sh <pr-number> <PRRT_id-or-comment_id> --body <text-or-file> [--resolve] [--repo OWNER/NAME]
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

pr=""
target_id=""
body=""
body_file=""
do_resolve=0
repo=""

while (($#)); do
  case "$1" in
    --repo)      repo="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --body)      body="${2:?--body needs text}"; shift 2 ;;
    --body-file) body_file="${2:?--body-file needs path}"; shift 2 ;;
    --resolve)   do_resolve=1; shift ;;
    -h|--help)
      sed -n '2,6p' "$0"
      exit 0
      ;;
    --*) die "unknown flag: $1" ;;
    *)
      if [[ -z $pr ]]; then pr="$1"
      elif [[ -z $target_id ]]; then target_id="$1"
      else die "unexpected positional argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n $pr ]] || die "missing <pr-number>"
[[ -n $target_id ]] || die "missing <PRRT_id-or-comment_id>"

if [[ -n $body_file ]]; then
  [[ -f $body_file ]] || die "body file not found: $body_file"
  body=$(cat "$body_file")
fi
[[ -n $body ]] || die "missing reply body (pass --body or --body-file)"

if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
fi
[[ -n $repo ]] || die "could not determine repository; pass --repo OWNER/NAME"

owner="${repo%%/*}"
name="${repo#*/}"

thread_id=""
comment_id=""

if [[ $target_id == PRRT_* ]]; then
  thread_id="$target_id"
  # shellcheck disable=SC2016 # $tid is a GraphQL variable, not a shell expansion
  comment_id=$(gh api graphql -F tid="$thread_id" -f query='
    query($tid: ID!) {
      node(id: $tid) {
        ... on PullRequestReviewThread {
          comments(first: 1) {
            nodes {
              databaseId
            }
          }
        }
      }
    }' --jq '.data.node.comments.nodes[0].databaseId // empty')
  [[ -n $comment_id ]] || die "could not resolve root databaseId for thread $thread_id on PR #$pr"
elif [[ $target_id =~ ^[0-9]+$ ]]; then
  comment_id="$target_id"
  if ((do_resolve)); then
    # shellcheck disable=SC2016 # $owner/$name/$pr are GraphQL variables
    thread_id=$(gh api graphql -F owner="$owner" -F name="$name" -F pr="$pr" -f query='
      query($owner: String!, $name: String!, $pr: Int!) {
        repository(owner: $owner, name: $name) {
          pullRequest(number: $pr) {
            reviewThreads(first: 100) {
              nodes {
                id
                comments(first: 50) {
                  nodes {
                    databaseId
                  }
                }
              }
            }
          }
        }
      }' | jq -r --argjson cid "$comment_id" '.data.repository.pullRequest.reviewThreads.nodes[] | select(any(.comments.nodes[]; .databaseId == $cid)) | .id // empty' | head -n1)
    [[ -n $thread_id ]] || die "could not resolve PRRT_ thread ID for comment $comment_id on PR #$pr"
  fi
else
  die "target ID must be a PRRT_... thread ID or numeric comment databaseId, got '$target_id'"
fi

reply_url=$(gh api "repos/$repo/pulls/$pr/comments/$comment_id/replies" -f body="$body" --jq .html_url)
printf 'Replied in thread (comment %s): %s\n' "$comment_id" "$reply_url"

if ((do_resolve)); then
  # shellcheck disable=SC2016 # $threadId is a GraphQL variable
  res=$(gh api graphql -f query='
    mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread {
          id
          isResolved
        }
      }
    }' -F threadId="$thread_id" --jq '.data.resolveReviewThread.thread.isResolved')
  if [[ $res == "true" ]]; then
    printf 'Thread %s resolved.\n' "$thread_id"
  else
    die "failed to resolve thread $thread_id: $res"
  fi
fi
