#!/usr/bin/env bash
# Choose which Find angles to dispatch for a diff, from its size tier and from
# patterns in the lines it adds, and say which angles were skipped and why.
# A small docs-only change does not need every angle; a large one does.
#
# Usage:
#   select-angles.sh --diff FILE [--full] [--github-remote yes|no]
#
# --diff FILE            unified diff (as `git diff` / `gh pr diff` print it)
# --full                 select every angle, skip nothing (the user asked for it)
# --github-remote yes|no does the repository have a GitHub remote? Angle N reads
#                        prior PR feedback, so it needs one. Default yes: when
#                        unknown, run the angle and let it report "no remote".
#
# Output (stdout, JSON):
#   {"tier":"docs|tiny|small|large|unknown","lines":N,"files":N,
#    "angles":["A",...],"skipped":[{"angle":"F","reason":"tiny tier"}]}
#
# Where the angle list comes from: the `### Angle X — ` headings of the
# method.md that sits one directory above this script. That file is the one
# owner of "which angles exist" (the count test in
# tests/test_deep_pr_review_method.sh already treats it that way); this script
# reads it at run time, so adding an angle there makes it selectable here with
# no second list to update. The letters named below (the tiny/docs base sets
# and the gated angles) are policy, not the list, and
# tests/test_select_angles.sh checks that each is a real heading.
#
# Tiers (documentation = *.md, *.rst, or anything under a leading docs/; *.txt
# is not, since requirements.txt and CMakeLists.txt are code):
#   docs   every changed path is documentation
#   tiny   under 50 changed lines and at most 3 files
#   small  under 300 changed lines
#   large  anything bigger
#   unknown  the diff is missing, unreadable or has no `diff --git` header: we
#            cannot size it, so the conservative answer is every angle
# "Changed lines" counts added plus removed lines inside hunks.
#
# Selection:
#   large, unknown  every angle
#   small           every angle except a gated one (E K L M N) whose gate is false
#   tiny            A B C D J O P, plus each gated angle whose gate is true
#   docs            A B J O P
#
# Gates. The regexes below run, case-insensitively, over ADDED lines only. They
# are deliberately loose (substring, not word-bounded): a false fire runs one
# more angle, a false miss drops one that might have found a bug.
#   E  wrapper/proxy/decorator/adapter/cache/delegate
#   K  map/cache/latch/mutex/atomic/sync/once/state
#   L  err/catch/except/Result</throw/rescue/return nil
#   M  at least one MODIFIED file (not new): the angle reads history at the base
#   N  --github-remote yes (the angle reads prior PR feedback)
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }
usage() { sed -n '2,51p' "$0"; }

gate_E='wrapper|proxy|decorator|adapter|cache|delegate'
gate_K='map|cache|latch|mutex|atomic|sync|once|state'
gate_L='err|catch|except|Result<|throw|rescue|return nil'

# Angles never dropped at a tier below large (see header). Changing a set here
# is a policy decision; the letters must exist in method.md.
base_tiny="A B C D J O P"
base_docs="A B J O P"
gated="E K L M N"

diff_file=""
full=0
remote="yes"

while (($#)); do
  case "$1" in
    --diff)          diff_file="${2:?--diff needs a file}"; shift 2 ;;
    --full)          full=1; shift ;;
    --github-remote) remote="${2:?--github-remote needs yes|no}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2; die "unknown argument: $1" ;;
  esac
done

[[ -n $diff_file ]] || { usage >&2; die "--diff FILE is required"; }
[[ $remote == yes || $remote == no ]] || die "--github-remote must be yes or no, got '$remote'"
command -v jq >/dev/null || die "jq is not installed"

method="$(dirname "${BASH_SOURCE[0]}")/../method.md"
[[ -r $method ]] || die "cannot read $method (the angle list is derived from its headings)"
mapfile -t all_angles < <(sed -nE 's/^### Angle ([A-Z]) — .*/\1/p' "$method")
((${#all_angles[@]})) || die "no '### Angle X — ' headings in $method"

in_list() { # in_list LETTER "SPACE SEPARATED LETTERS"
  case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

emit() { # emit TIER LINES FILES — reads selected/skipped from the arrays below
  local tier=$1 lines=$2 files=$3 skipped_json
  skipped_json=$(
    for i in "${!skip_angle[@]}"; do
      jq -n --arg a "${skip_angle[$i]}" --arg r "${skip_reason[$i]}" '{angle: $a, reason: $r}'
    done | jq -s '.'
  )
  jq -n --arg tier "$tier" --argjson lines "$lines" --argjson files "$files" \
        --arg angles "${sel_angle[*]}" --argjson skipped "$skipped_json" \
        '{tier: $tier, lines: $lines, files: $files,
          angles: ($angles | split(" ") | map(select(length > 0))), skipped: $skipped}'
}

sel_angle=()
skip_angle=()
skip_reason=()

select_all() { sel_angle=("${all_angles[@]}"); }

# ---------------------------------------------------------------------------
# One pass over the diff. Hunk state matters: inside a hunk a removed line
# whose text starts with "-- " prints as "--- ..." and must still count.
# Output: lines, files, modified_files, all_docs (1/0); added text goes to a
# side file for the gate greps.
# ---------------------------------------------------------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

lines=0 files=0 modified=0 all_docs=0
parsed=0
if [[ -r $diff_file ]] && grep -q '^diff --git ' "$diff_file"; then
  parsed=1
  read -r lines files modified all_docs < <(
    awk -v added="$work/added.txt" '
      function is_doc(p) { return p ~ /\.(md|rst)$/ || p ~ /^docs\// }
      function close_file() { if (infile && !isnew) modified++ }
      /^diff --git / {
        close_file()
        infile = 1; isnew = 0; inhunk = 0; files++
        p = $0; sub(/^diff --git a\/.* b\//, "", p)   # greedy: the last " b/"
        if (!is_doc(p)) nondoc++
        next
      }
      !inhunk && /^new file mode / { isnew = 1; next }
      /^@@ / { inhunk = 1; next }
      inhunk && /^\+/ { lines++; print substr($0, 2) > added; next }
      inhunk && /^-/  { lines++; next }
      END {
        close_file()
        printf "%d %d %d %d\n", lines, files, modified, (files > 0 && nondoc == 0)
      }
    ' "$diff_file"
  )
  [[ -e $work/added.txt ]] || : > "$work/added.txt"
fi

if ((!parsed)); then
  tier=unknown
elif ((all_docs)); then
  tier=docs
elif ((lines < 50 && files <= 3)); then
  tier=tiny
elif ((lines < 300)); then
  tier=small
else
  tier=large
fi

# An unsizable diff cannot be gated, and --full is the user's explicit request
# for everything. Both select every angle and skip none; --full still reports
# the tier the diff really has.
if ((full || !parsed)); then
  select_all
  emit "$tier" "$lines" "$files"
  exit 0
fi

gate_fires() { # gate_fires LETTER -> 0 when the gate is true
  case $1 in
    E) grep -qiE "$gate_E" "$work/added.txt" ;;
    K) grep -qiE "$gate_K" "$work/added.txt" ;;
    L) grep -qiE "$gate_L" "$work/added.txt" ;;
    M) ((modified > 0)) ;;
    N) [[ $remote == yes ]] ;;
  esac
}

gate_reason() {
  case $1 in
    E) echo "gate not met: no wrapper/proxy/decorator/adapter/cache/delegate in added lines" ;;
    K) echo "gate not met: no map/cache/latch/mutex/atomic/sync/once/state in added lines" ;;
    L) echo "gate not met: no error-path pattern (err/catch/except/Result</throw/rescue/return nil) in added lines" ;;
    M) echo "gate not met: no modified file (every changed file is new), so no history" ;;
    N) echo "gate not met: no GitHub remote, so no prior PR feedback" ;;
  esac
}

for a in "${all_angles[@]}"; do
  keep=0
  reason=""
  case $tier in
    large) keep=1 ;;
    small)
      if in_list "$a" "$gated"; then
        if gate_fires "$a"; then keep=1; else reason=$(gate_reason "$a"); fi
      else keep=1; fi ;;
    tiny)
      if in_list "$a" "$base_tiny"; then keep=1
      elif in_list "$a" "$gated"; then
        if gate_fires "$a"; then keep=1; else reason=$(gate_reason "$a"); fi
      else reason="tiny tier"; fi ;;
    docs)
      if in_list "$a" "$base_docs"; then keep=1; else reason="docs tier"; fi ;;
  esac
  if ((keep)); then
    sel_angle+=("$a")
  else
    skip_angle+=("$a")
    skip_reason+=("$reason")
  fi
done

emit "$tier" "$lines" "$files"
