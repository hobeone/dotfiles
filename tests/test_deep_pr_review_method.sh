#!/usr/bin/env bash
# Structural checks on the merged deep-pr-review method and its callers.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

core=skills-shared/deep-pr-review
m=$core/method.md
fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

want_phases=$'Phase 0 — Eligibility\nPhase 1 — Gather\nPhase 2 — Architecture Gate\nPhase 3 — Find\nPhase 4 — Verify\nPhase 5 — Gap Sweep\nPhase 6 — Render\nPhase 7 — Post'
got_phases=$(grep -E '^## Phase [0-9] — ' "$m" | sed 's/^## //')
[[ $got_phases == "$want_phases" ]] || err "phase headings differ:"$'\n'"$got_phases"

for a in A B C D E F G H I J K L M N O; do
  grep -qE "^### Angle $a — " "$m" || err "missing Angle $a"
done

if grep -nE 'Phase [0-9]' "$core/reference/go_rules.md"; then err "go_rules.md cites phase numbers"; fi
if grep -rn '/tmp/' "$m"; then err "method.md hard-codes /tmp"; fi
if grep -rnE '12-angle|twelve' "$core"; then err "stale 12-angle wording in core"; fi
grep -q -- '--expect-head' "$m" || err "method.md does not use --expect-head"
grep -q -- '--sequential' "$m" || err "method.md does not document --sequential"
grep -qF '<!-- deep-pr-review head:' "$m" || err "method.md does not describe the head marker"

adapters=(home/.claude/skills/deep-pr-review/SKILL.md home/.gemini/skills/deep-pr-review/SKILL.md)
callers=(home/.gemini/skills/adversarial-review/SKILL.md home/.gemini/skills/adversarial-review-loop/SKILL.md)

# The angle count must have exactly one owner: the number of "### Angle X —"
# headings in method.md. Every digit-count reference to it (core files +
# both adapters + both callers) must match that count, and callers must not
# quote a count at all.
angle_n=$(grep -c '^### Angle [A-Z] — ' "$m")
mapfile -t core_files < <(find "$core" -type f)
count_targets=("${core_files[@]}" "${adapters[@]}" "${callers[@]}")
count_pattern='[0-9]+-angle|[0-9]+ angles|[0-9]+ analytical|[0-9]+ subagents|[0-9]+ entries'
while IFS=: read -r file lineno match; do
  num=$(grep -oE '[0-9]+' <<<"$match")
  if [[ $num != "$angle_n" ]]; then
    err "angle count mismatch in $file:$lineno ($match, expected $angle_n)"
  fi
done < <(grep -nroE "$count_pattern" "${count_targets[@]}")

# Narrower than count_pattern's [0-9]+ subagents|entries (those legitimately
# describe fan-out sizing elsewhere): callers must not quote an angle *count*
# in any form, singular or plural. This intentionally does not match a bare
# "<N> angle" used as a non-count noun phrase (e.g. "Section 2 angle
# mappings" in go_rules.md cross-references), only counting phrasings.
if hits=$(grep -nE '[0-9]+-angle|[0-9]+ angles|[0-9]+ analytical' "${callers[@]}"); then
  err "callers must not quote an angle count at all:"
  printf '%s\n' "$hits"
fi

if grep -nE '12-angle|12 analytical' "${callers[@]}"; then err "callers still say 12 angles"; fi
# shellcheck disable=SC2016 # literal backticks in the pattern, no expansion intended
if grep -nE 'Phase [0-9] of `deep-pr-review`' "${callers[@]}"; then err "callers cite deep-pr-review phases by number"; fi

# Callers must not enumerate their own per-angle list (it drifts from
# method.md's names); they must instead cite deep-pr-review's own Angles A-O.
if hits=$(grep -nE '^[[:space:]]*[-*][[:space:]]*\**Angle [A-O]\b' "${callers[@]}"); then
  err "callers enumerate a per-angle list instead of citing deep-pr-review's Angles A-O:"
  printf '%s\n' "$hits"
fi

((fail)) && exit 1
echo PASS
