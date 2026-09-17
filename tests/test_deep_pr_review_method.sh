#!/usr/bin/env bash
# Structural checks on the merged deep-pr-review method and its callers.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

core=skills-shared/deep-pr-review
m=$core/method.md
fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

# Every path this script scans must exist before an absence-asserting grep
# runs against it — otherwise "no match" and "file missing" are silently
# indistinguishable, and a caller path that gets renamed stops being checked
# at all instead of failing loudly.
assert_exists() {
  local p
  for p in "$@"; do
    [[ -e $p ]] || err "missing: $p"
  done
}

# check_absent DESC PATTERN FILE... — passes when PATTERN matches nothing in
# FILE(s) (grep exit 1). Fails loudly on an actual grep error (exit 2: e.g. a
# missing file or a malformed regex) instead of treating it as "no match",
# and fails with the hits when PATTERN does match (exit 0).
check_absent() {
  local desc=$1 pattern=$2 out rc
  shift 2
  out=$(grep -nE "$pattern" "$@" 2>&1)
  rc=$?
  if ((rc == 2)); then
    err "grep failed on $desc: $out"
  elif ((rc == 0)); then
    err "$desc:"$'\n'"$out"
  fi
}

# Recursive variant of check_absent, for directory targets.
check_absent_r() {
  local desc=$1 pattern=$2 out rc
  shift 2
  out=$(grep -rnE "$pattern" "$@" 2>&1)
  rc=$?
  if ((rc == 2)); then
    err "grep failed on $desc: $out"
  elif ((rc == 0)); then
    err "$desc:"$'\n'"$out"
  fi
}

want_phases=$'Phase 0 — Eligibility\nPhase 1 — Gather\nPhase 2 — Architecture Gate\nPhase 3 — Find\nPhase 4 — Verify\nPhase 5 — Gap Sweep\nPhase 6 — Render\nPhase 7 — Post'
got_phases=$(grep -E '^## Phase [0-9] — ' "$m" | sed 's/^## //')
[[ $got_phases == "$want_phases" ]] || err "phase headings differ:"$'\n'"$got_phases"

for a in A B C D E F G H I J K L M N O; do
  grep -qE "^### Angle $a — " "$m" || err "missing Angle $a"
done

assert_exists "$core/reference/go_rules.md" "$m" "$core"
check_absent "go_rules.md cites phase numbers" 'Phase [0-9]' "$core/reference/go_rules.md"
check_absent "method.md hard-codes /tmp" '/tmp/' "$m"
check_absent_r "stale 12-angle wording in core" '12-angle|twelve' "$core"
grep -q -- '--expect-head' "$m" || err "method.md does not use --expect-head"
grep -q -- '--sequential' "$m" || err "method.md does not document --sequential"
grep -qF '<!-- deep-pr-review head:' "$m" || err "method.md does not describe the head marker"

adapters=(home/.claude/skills/deep-pr-review/SKILL.md home/.gemini/skills/deep-pr-review/SKILL.md)
callers=(home/.gemini/skills/adversarial-review/SKILL.md home/.gemini/skills/adversarial-review-loop/SKILL.md)
assert_exists "${adapters[@]}" "${callers[@]}"

# The angle count must have exactly one owner: the number of "### Angle X —"
# headings in method.md. Every digit-count reference to it (core files +
# both adapters + both callers) must match that count, and callers must not
# quote a count at all.
angle_n=$(grep -c '^### Angle [A-Z] — ' "$m")
mapfile -t core_files < <(find "$core" -type f)
count_targets=("${core_files[@]}" "${adapters[@]}" "${callers[@]}")
assert_exists "${count_targets[@]}"
count_pattern='[0-9]+-angle|[0-9]+ angles|[0-9]+ analytical|[0-9]+ subagents|[0-9]+ entries'
out=$(grep -nroE "$count_pattern" "${count_targets[@]}" 2>&1)
rc=$?
if ((rc == 2)); then
  err "grep failed scanning count_targets: $out"
elif ((rc == 0)); then
  while IFS=: read -r file lineno match; do
    num=$(grep -oE '[0-9]+' <<<"$match")
    if [[ $num != "$angle_n" ]]; then
      err "angle count mismatch in $file:$lineno ($match, expected $angle_n)"
    fi
  done <<<"$out"
fi

# Narrower than count_pattern's [0-9]+ subagents|entries (those legitimately
# describe fan-out sizing elsewhere): callers must not quote an angle *count*
# in any form, singular or plural. This intentionally does not match a bare
# "<N> angle" used as a non-count noun phrase (e.g. "Section 2 angle
# mappings" in go_rules.md cross-references), only counting phrasings.
check_absent "callers must not quote an angle count at all" \
  '[0-9]+-angle|[0-9]+ angles|[0-9]+ analytical' "${callers[@]}"

check_absent "callers still say 12 angles" '12-angle|12 analytical' "${callers[@]}"
# shellcheck disable=SC2016 # literal backticks in the pattern, no expansion intended
check_absent "callers cite deep-pr-review phases by number" \
  'Phase [0-9] of `deep-pr-review`' "${callers[@]}"

# Callers must not enumerate their own per-angle list (it drifts from
# method.md's names); they must instead cite deep-pr-review's own Angles A-O.
check_absent "callers enumerate a per-angle list instead of citing deep-pr-review's Angles A-O" \
  '^[[:space:]]*[-*][[:space:]]*\**Angle [A-O]\b' "${callers[@]}"

((fail)) && exit 1
echo PASS
