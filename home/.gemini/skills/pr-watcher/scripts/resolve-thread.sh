#!/usr/bin/env bash
# resolve-thread.sh: List or resolve GitHub PR review threads via GraphQL
#
# Usage:
#   resolve-thread.sh <thread-id> [<thread-id> ...]
#   resolve-thread.sh --list-unresolved <pr-number> [--repo OWNER/NAME]
#   resolve-thread.sh --pr <pr-number> --all [--repo OWNER/NAME]
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
usage:
  resolve-thread.sh <thread-id> [<thread-id> ...]
  resolve-thread.sh --list-unresolved <pr-number> [--repo OWNER/NAME]
  resolve-thread.sh --pr <pr-number> --all [--repo OWNER/NAME]
EOF
}

repo=""
pr_num=""
list_only=0
resolve_all=0
thread_ids=()

while (($#)); do
  case "$1" in
    --repo) repo="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --list-unresolved) pr_num="${2:?--list-unresolved needs PR number}"; list_only=1; shift 2 ;;
    --pr) pr_num="${2:?--pr needs PR number}"; shift 2 ;;
    --all) resolve_all=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown flag: $1" ;;
    *) thread_ids+=("$1"); shift ;;
  esac
done

resolve_one() {
  local thread_id="$1"
  local res
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
    printf 'Failed to resolve thread %s: %s\n' "$thread_id" "$res" >&2
    return 1
  fi
}

fetch_unresolved() {
  local owner name
  if [[ -z $repo ]]; then
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
  fi
  [[ -n $repo ]] || die "could not determine repository; pass --repo OWNER/NAME"
  owner="${repo%%/*}"
  name="${repo#*/}"

  gh api graphql -F owner="$owner" -F name="$name" -F pr="$pr_num" -f query='
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              path
              line
              comments(first: 1) {
                nodes {
                  author { login }
                  body
                }
              }
            }
          }
        }
      }
    }' --jq '.data.repository.pullRequest.reviewThreads.nodes[]
      | select(.isResolved == false)
      | "\(.id)\t\(.path):\(.line // 0)\t\((.comments.nodes[0].body // "") | split("\n")[0])"'
}

if ((list_only)); then
  fetch_unresolved
  exit 0
fi

if ((resolve_all)); then
  [[ -n $pr_num ]] || die "--all requires --pr <pr-number>"
  while IFS=$'\t' read -r tid _; do
    [[ -n $tid ]] && thread_ids+=("$tid")
  done < <(fetch_unresolved)
  if ((${#thread_ids[@]} == 0)); then
    printf 'No unresolved review threads on PR #%s.\n' "$pr_num"
    exit 0
  fi
fi

((${#thread_ids[@]})) || die "usage: resolve-thread.sh <thread-id> [...] or --list-unresolved <pr> or --pr <pr> --all"

for thread_id in "${thread_ids[@]}"; do
  [[ -n $thread_id ]] || continue
  resolve_one "$thread_id"
done
