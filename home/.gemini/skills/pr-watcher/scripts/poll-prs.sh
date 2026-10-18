#!/usr/bin/env bash
# poll-prs.sh: Poll open GitHub PRs for the PR watcher
#
# Usage:
#   poll-prs.sh [--repo OWNER/NAME] [--json]
set -euo pipefail

repo=""
as_json=0

while (($#)); do
  case "$1" in
    --repo) repo="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --json) as_json=1; shift ;;
    -h|--help)
      echo "usage: poll-prs.sh [--repo OWNER/NAME] [--json]"
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
fi

repo_flag=()
if [[ -n $repo ]]; then
  repo_flag=(--repo "$repo")
fi

if ((as_json)); then
  gh pr list "${repo_flag[@]}" --state open --json number,title,headRefOid,updatedAt,mergeStateStatus,isDraft,author
else
  gh pr list "${repo_flag[@]}" --state open --json number,title,headRefOid,updatedAt,mergeStateStatus \
    --jq '.[] | "\(.number)\t\(.headRefOid)\t\(.updatedAt)\t\(.mergeStateStatus)\t\(.title)"'
fi
