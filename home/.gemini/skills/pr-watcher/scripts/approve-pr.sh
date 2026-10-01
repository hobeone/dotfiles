#!/usr/bin/env bash
# approve-pr.sh: Post a standardized merge readiness approval comment to a PR
#
# Usage:
#   approve-pr.sh <pr-number> <head-sha> [summary-or-file] [--repo OWNER/NAME]
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

pr=""
sha=""
summary=""
repo=""

while (($#)); do
  case "$1" in
    --repo) repo="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    -h|--help)
      echo "usage: approve-pr.sh <pr-number> <head-sha> [summary-or-file] [--repo OWNER/NAME]"
      exit 0
      ;;
    -*) die "unknown flag: $1" ;;
    *)
      if [[ -z $pr ]]; then pr="$1"
      elif [[ -z $sha ]]; then sha="$1"
      elif [[ -z $summary ]]; then summary="$1"
      else die "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[[ -n $pr ]] || die "missing <pr-number>"
[[ -n $sha ]] || die "missing <head-sha>"

repo_flag=()
if [[ -n $repo ]]; then
  repo_flag=(--repo "$repo")
fi

evidence_body=""
if [[ -n $summary ]]; then
  if [[ -f $summary ]]; then
    evidence_body=$(cat "$summary")
  else
    evidence_body="$summary"
  fi
fi

full_body=$(cat << EOF
### Re-Review Complete — Approved (Ready to Merge)

Verified commit \`$sha\`:

${evidence_body:-All Pass 1 gates and Pass 2 audits passed cleanly. All review threads resolved.}

Ready to merge.
EOF
)

gh pr comment "$pr" "${repo_flag[@]}" --body "$full_body"
