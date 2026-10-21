#!/usr/bin/env bash
# Report how the user changed a deep-pr-review draft before submitting it.
#
# Usage:
#   read-back.sh <pr-number> [--repo O/R] [--review-id ID]
#
# post-review.sh --draft saves a snapshot of the pending review it created
# (${XDG_STATE_HOME:-~/.local/state}/deep-pr-review/<owner>_<repo>_<N>_<id>.json).
# This script re-fetches that review's body and comments and prints JSON:
#
#   {"kept":[{id,path,line}], "edited":[{id,path,line,before,after}],
#    "removed":[{id,path,line,body}], "added":[{id,path,line,body}],
#    "body_changed":bool}
#
# Comments are matched by id (an edit in the GitHub UI keeps the id). Bodies are
# compared after dropping CR characters and trailing whitespace: the web UI
# rewrites line endings, which is not an edit. Read-only: never publishes and
# never modifies the review.
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

pr=""
repo=""
review_id=""

while (($#)); do
  case "$1" in
    --repo)      repo="${2:?--repo needs OWNER/NAME}"; shift 2 ;;
    --review-id) review_id="${2:?--review-id needs an id}"; shift 2 ;;
    -h|--help)   sed -n '2,17p' "$0"; exit 0 ;;
    -*)          die "unknown flag: $1" ;;
    *)
      [[ -z $pr ]] || die "unexpected argument: $1"
      pr="$1"; shift ;;
  esac
done

[[ -n $pr ]] || die "usage: read-back.sh <pr-number> [--repo O/R] [--review-id ID]"
[[ $pr =~ ^[0-9]+$ ]] || die "pr-number must be numeric, got '$pr'"
[[ -z $review_id || $review_id =~ ^[0-9]+$ ]] || die "--review-id must be numeric, got '$review_id'"
command -v gh >/dev/null || die "gh is not installed"
command -v jq >/dev/null || die "jq is not installed"

if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/deep-pr-review"
snap_for() { printf '%s/%s_%s_%s.json' "$state_dir" "${repo//\//_}" "$pr" "$1"; }

if [[ -z $review_id ]]; then
  # The user's newest review on this PR that we hold a snapshot for. Pending
  # reviews are listed too (to their owner), so one list covers both cases.
  me=$(gh api user --jq .login) || die "could not resolve the authenticated GitHub user"
  mapfile -t ids < <(gh api "repos/$repo/pulls/$pr/reviews" --paginate \
    | jq -rs --arg me "$me" 'add // [] | map(select(.user.login == $me) | .id) | sort | .[]')
  if ((${#ids[@]})); then
    for id in "${ids[@]}"; do
      [[ -r $(snap_for "$id") ]] && review_id=$id
    done
  fi
  [[ -n $review_id ]] || die "no snapshot found for $repo#$pr in $state_dir; create one with post-review.sh --draft"
fi

snap=$(snap_for "$review_id")
[[ -r $snap ]] || die "no snapshot for review $review_id at $snap; create one with post-review.sh --draft"

review_json=$(gh api "repos/$repo/pulls/$pr/reviews/$review_id") \
  || die "could not fetch review $review_id (deleted?)"
current_body=$(jq -r '.body // ""' <<<"$review_json")
current_comments=$(gh api "repos/$repo/pulls/$pr/reviews/$review_id/comments" --paginate \
  | jq -s 'add // []') || die "could not fetch the comments of review $review_id"

jq -n --slurpfile snap "$snap" --argjson cur "$current_comments" --arg body "$current_body" '
  def norm: gsub("\r"; "") | sub("\\s+$"; "");
  def keyed: map({key: (.id | tostring), value: .}) | from_entries;
  ($snap[0].comments | keyed) as $old
  | ($cur | map({id, path, line: (.line // .original_line), body}) | keyed) as $new
  | {
      kept:    [ $new | to_entries[] | select($old[.key] != null and ($old[.key].body | norm) == (.value.body | norm))
                 | .value | del(.body) ],
      edited:  [ $new | to_entries[] | select($old[.key] != null and ($old[.key].body | norm) != (.value.body | norm))
                 | {id: .value.id, path: .value.path, line: .value.line, before: $old[.key].body, after: .value.body} ],
      removed: [ $old | to_entries[] | select($new[.key] == null) | .value ],
      added:   [ $new | to_entries[] | select($old[.key] == null) | .value ],
      body_changed: (($snap[0].body | norm) != ($body | norm))
    }'
