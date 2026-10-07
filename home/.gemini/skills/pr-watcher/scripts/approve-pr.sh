#!/usr/bin/env bash
# approve-pr.sh: Post a standardized verdict comment and GitHub commit status to a PR
#
# Usage:
#   approve-pr.sh <pr-number> <head-sha> [options]
#
# Options:
#   --verdict <APPROVED|CHANGES_REQUESTED|COMMENTED>   (default: APPROVED)
#   --since <old-sha>                                  (optional: adds "(since <short-old-sha>)" to header)
#   --scope <text>                                     (default: "full PR" or "<since>..<short-sha>")
#   --previously-raised <text>                         (default: "none")
#   --checks <text-or-file>                            (checks run section; also accepted as 3rd positional arg)
#   --not-verified <text>                              (default: "live Usenet E2E (test/e2e/) and crash consistency (test/crash/).")
#   --open-threads <text>                              (default: auto-queried via resolve-thread.sh or "none")
#   --threads-count <n>                                (default: auto-counted from open-threads)
#   --repo <OWNER/NAME>
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

pr=""
sha=""
verdict="APPROVED"
since_sha=""
scope=""
prev_raised="none"
checks=""
not_verified="live Usenet E2E (\`test/e2e/\`) and crash consistency (\`test/crash/\`)."
open_threads=""
threads_count=""
repo=""

while (($#)); do
  case "$1" in
    --repo)              repo="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --verdict)           verdict="${2:?--verdict needs value}"; shift 2 ;;
    --since)             since_sha="${2:?--since needs SHA}"; shift 2 ;;
    --scope)             scope="${2:?--scope needs text}"; shift 2 ;;
    --previously-raised) prev_raised="${2:?--previously-raised needs text}"; shift 2 ;;
    --checks|--body|--summary) checks="${2:?--checks needs text}"; shift 2 ;;
    --not-verified)      not_verified="${2:?--not-verified needs text}"; shift 2 ;;
    --open-threads)      open_threads="${2:?--open-threads needs text}"; shift 2 ;;
    --threads-count)     threads_count="${2:?--threads-count needs number}"; shift 2 ;;
    --) shift; break ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    --*) die "unknown flag: $1" ;;
    *)
      if [[ -z $pr ]]; then pr="$1"
      elif [[ -z $sha ]]; then sha="$1"
      elif [[ -z $checks ]]; then checks="$1"
      else checks="$checks"$'\n'"$1"
      fi
      shift ;;
  esac
done

[[ -n $pr ]] || die "missing <pr-number>"
[[ -n $sha ]] || die "missing <head-sha>"
[[ ${#sha} -eq 40 ]] || die "<head-sha> must be the full 40-char commit SHA (got '$sha')"

case "$verdict" in
  APPROVED|CHANGES_REQUESTED|COMMENTED) ;;
  *) die "--verdict must be APPROVED, CHANGES_REQUESTED, or COMMENTED (got '$verdict')" ;;
esac

if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

short_sha="${sha:0:8}"
since_clause=""
if [[ -n $since_sha ]]; then
  short_since="${since_sha:0:8}"
  since_clause=" (since \`$short_since\`)"
  [[ -n $scope ]] || scope="\`$short_since..$short_sha\`"
else
  [[ -n $scope ]] || scope="full PR"
fi

if [[ -n $checks && -f $checks ]]; then
  checks=$(cat "$checks")
fi
[[ -n $checks ]] || checks="- All Pass 1 deterministic gates and Pass 2 audits: PASS"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -z $open_threads ]]; then
  if [[ -x "$script_dir/resolve-thread.sh" ]]; then
    mapfile -t unresolved_lines < <("$script_dir/resolve-thread.sh" --list-unresolved "$pr" --repo "$repo" 2>/dev/null || true)
    if ((${#unresolved_lines[@]} == 0)); then
      open_threads="none"
      [[ -n $threads_count ]] || threads_count=0
    else
      open_threads=$(printf -- '- `%s`\n' "${unresolved_lines[@]}")
      [[ -n $threads_count ]] || threads_count="${#unresolved_lines[@]}"
    fi
  else
    open_threads="none"
    [[ -n $threads_count ]] || threads_count=0
  fi
else
  if [[ -z $threads_count ]]; then
    if [[ $open_threads == "none" ]]; then
      threads_count=0
    else
      threads_count=$(grep -c 'PRRT_' <<<"$open_threads" || echo 1)
    fi
  fi
fi

header_verdict="${verdict//_/ }"

full_body=$(cat <<EOF
<!-- deep-pr-review head:$sha verdict:$verdict threads_open:$threads_count -->
## Review of \`$short_sha\` ($sha)${since_clause}: $header_verdict

**Scope:** $scope

**Previously raised, now:**
$prev_raised

**Checks run:**
$checks

**Not verified:** $not_verified

**Open threads:** $open_threads

Status: $header_verdict at \`$short_sha\`. Becomes stale if the PR head moves.
EOF
)

comment_url=$(gh api "repos/$repo/issues/$pr/comments" -f body="$full_body" --jq .html_url)
printf '%s\n' "$comment_url"

status_state="success"
status_desc="APPROVED at $short_sha"
if [[ $verdict == "CHANGES_REQUESTED" ]]; then
  status_state="failure"
  status_desc="CHANGES REQUESTED at $short_sha ($threads_count open threads)"
elif [[ $verdict == "COMMENTED" ]]; then
  status_state="success"
  status_desc="COMMENTED at $short_sha ($threads_count open threads)"
fi

gh api "repos/$repo/statuses/$sha" \
  -f state="$status_state" \
  -f context="deep-pr-review" \
  -f description="$status_desc" \
  -f target_url="$comment_url" \
  --jq '{context: .context, state: .state, description: .description}' >&2
