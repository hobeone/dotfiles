#!/usr/bin/env bash
# tier-pr.sh: Classify a PR into tier1_lightweight or tier2_deep
#
# Usage:
#   tier-pr.sh <pr-number> [--repo OWNER/NAME] [--json]
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

pr=""
repo=""
base_sha=""
as_json=0

while (($#)); do
  case "$1" in
    --repo) repo="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --base) base_sha="${2:?--base needs SHA}"; shift 2 ;;
    --json) as_json=1; shift ;;
    -h|--help)
      echo "usage: tier-pr.sh <pr-number> [--base SHA] [--repo OWNER/NAME] [--json]"
      exit 0
      ;;
    -*) die "unknown flag: $1" ;;
    *)
      if [[ -z $pr ]]; then pr="$1"
      else die "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[[ -n $pr ]] || die "missing <pr-number>"
[[ $pr =~ ^[0-9]+$ ]] || die "pr-number must be numeric, got '$pr'"

if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
fi

repo_flag=()
if [[ -n $repo ]]; then
  repo_flag=(--repo "$repo")
fi

pr_data=$(gh pr view "$pr" "${repo_flag[@]}" --json files,additions,deletions,title,headRefOid)
title=$(jq -r '.title' <<< "$pr_data")
head_sha=$(jq -r '.headRefOid' <<< "$pr_data")

if [[ -n $base_sha ]]; then
  # Incremental classification against the prior audited head
  files_list=$(git diff --name-only "$base_sha...$head_sha" 2>/dev/null || true)
  if [[ -z $files_list ]]; then
    # Fallback to fetching head
    git fetch origin "$head_sha" "$base_sha" 2>/dev/null || true
    files_list=$(git diff --name-only "$base_sha...$head_sha" 2>/dev/null || true)
  fi
  files_json=$(printf '%s\n' "$files_list" | jq -R . | jq -s 'map(select(length > 0) | {path: .})')
  read -r additions deletions < <(git diff --numstat "$base_sha...$head_sha" 2>/dev/null | awk '{a+=$1; d+=$2} END {printf "%d %d\n", a, d}')
  additions=${additions:-0}
  deletions=${deletions:-0}
else
  files_json=$(jq -c '.files' <<< "$pr_data")
  additions=$(jq -r '.additions' <<< "$pr_data")
  deletions=$(jq -r '.deletions' <<< "$pr_data")
fi
total_changes=$((additions + deletions))

# Check file classifications
non_doc_count=0
non_test_count=0
non_script_count=0
core_touched=()

# Core high-stakes packages that demand Tier 2 review when modified
is_core_pkg() {
  local p="$1"
  [[ $p =~ ^internal/(app|dispatch|durability|downloader|assembler|nntp|par2|job)/ ]]
}

while IFS= read -r f; do
  [[ -z $f ]] && continue

  # Doc check
  if ! [[ $f =~ \.(md|txt|rst|adoc)$ || $f =~ ^docs/ ]]; then
    ((non_doc_count++)) || true
  fi

  # Test / spec check
  if ! [[ $f =~ _test\.go$ || $f =~ \.spec$ || $f =~ ^test/ || $f =~ /testdata/ ]]; then
    ((non_test_count++)) || true
  fi

  # Script / CI check
  if ! [[ $f =~ ^scripts/ || $f =~ ^\.github/ ]]; then
    ((non_script_count++)) || true
  fi

  # Core package check
  if is_core_pkg "$f" && ! [[ $f =~ _test\.go$ || $f =~ \.spec$ || $f =~ /testdata/ ]]; then
    core_touched+=("$f")
  fi
done < <(jq -r '.[].path' <<< "$files_json")

tier="tier2_deep"
reason="general code change"

# Check if diff consists entirely of comments or documentation
non_comment_diff_lines=-1
if [[ -n $base_sha ]]; then
  if git diff -U0 "$base_sha...$head_sha" 2>/dev/null | grep -q '^[+-]'; then
    non_comment_diff_lines=$(git diff -U0 "$base_sha...$head_sha" 2>/dev/null | grep '^[+-]' | grep -v '^[+-]\{3\}' | grep -vE '^[+-][[:space:]]*(//|/\*|\*|$)' | wc -l || true)
  fi
fi

if ((non_comment_diff_lines == 0)); then
  tier="tier1_lightweight"
  reason="documentation/comments only"
elif ((non_doc_count == 0)); then
  tier="tier1_lightweight"
  reason="documentation only"
elif ((non_test_count == 0)); then
  tier="tier1_lightweight"
  reason="test and spec additions only"
elif ((non_script_count == 0)); then
  tier="tier1_lightweight"
  reason="tooling and scripts only"
elif ((${#core_touched[@]} == 0)) && ((total_changes <= 30)); then
  tier="tier1_lightweight"
  reason="small diff ($total_changes lines) outside core pipeline"
else
  if ((${#core_touched[@]} > 0)); then
    reason="touches core pipeline packages (${#core_touched[@]} files)"
  else
    reason="substantial diff ($total_changes lines)"
  fi
fi

if ((as_json)); then
  jq -n \
    --arg pr "$pr" \
    --arg title "$title" \
    --arg tier "$tier" \
    --arg reason "$reason" \
    --argjson additions "$additions" \
    --argjson deletions "$deletions" \
    --argjson total "$total_changes" \
    --argjson core "$(printf '%s\n' "${core_touched[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')" \
    '{pr: ($pr|tonumber), title: $title, tier: $tier, reason: $reason, additions: $additions, deletions: $deletions, total_changes: $total, core_files_touched: $core}'
else
  printf '%s\t%s\t%d\t%s\n' "$tier" "$reason" "$total_changes" "$title"
fi
