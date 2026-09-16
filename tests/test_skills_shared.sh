#!/usr/bin/env bash
# Enforce the skills-shared pattern for every skills-shared/<name>/:
# the core names no harness tools, every verb it uses is bound by every
# adapter (and nothing extra), and adapter links resolve into the core.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

forbidden='run_subagent|invoke_subagent|view_file|run_command|ask_question|AskUserQuestion|subagent_type|TypeName|~/\.gemini|~/\.claude'
verb_re='⟨[a-z-]+⟩'

shopt -s nullglob
cores=(skills-shared/*/)
((${#cores[@]})) || err "no shared skills under skills-shared/"

for core in "${cores[@]}"; do
  core=${core%/}
  name=${core##*/}
  if [[ ! -f $core/method.md ]]; then
    err "$name: missing method.md"
    continue
  fi

  if hits=$(grep -rnE "$forbidden" "$core"); then
    err "$name: harness tokens in neutral core:"
    printf '%s\n' "$hits"
  fi

  used=$(grep -rIohE "$verb_re" "$core" | sort -u)
  adapters=0
  for harness in .claude .gemini; do
    adir=home/$harness/skills/$name
    [[ -d $adir ]] || continue
    adapters=$((adapters + 1))

    for entry in "$core"/*; do
      link=$adir/${entry##*/}
      if [[ ! -L $link ]]; then
        err "$link is not a symlink"
        continue
      fi
      target=$(readlink "$link")
      [[ $target != /* ]] || err "$link target '$target' is not relative"
      want=$(realpath "$entry")
      got=$(realpath "$link" 2>/dev/null || true)
      [[ $got == "$want" ]] || err "$link resolves to '$got', want '$want'"
    done

    for link in "$adir"/*; do
      [[ -L $link ]] || continue
      base=${link##*/}
      [[ -e $core/$base ]] || err "$link is a symlink with no matching top-level entry in $core"
    done

    if [[ ! -f $adir/SKILL.md ]]; then
      err "$adir: missing SKILL.md"
      continue
    fi
    bound=$(grep -oE "^\| \`$verb_re\`" "$adir/SKILL.md" | grep -oE "$verb_re" | sort -u)
    missing=$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$bound") | sed '/^$/d')
    dead=$(comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$bound") | sed '/^$/d')
    [[ -z $missing ]] || err "$adir/SKILL.md does not bind: $(tr '\n' ' ' <<<"$missing")"
    [[ -z $dead ]] || err "$adir/SKILL.md binds unused verbs: $(tr '\n' ' ' <<<"$dead")"
  done
  ((adapters)) || err "$name: no adapter under home/.claude/skills or home/.gemini/skills"
done

((fail)) && exit 1
echo PASS
