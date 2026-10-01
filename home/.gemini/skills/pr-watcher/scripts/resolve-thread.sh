#!/usr/bin/env bash
# resolve-thread.sh: Resolve one or more GitHub PR review threads via GraphQL
#
# Usage:
#   resolve-thread.sh <thread-id> [<thread-id> ...]
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

(($#)) || die "usage: resolve-thread.sh <thread-id> [<thread-id> ...]"

for thread_id in "$@"; do
  [[ -n $thread_id ]] || continue
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
  fi
done
