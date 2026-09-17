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
# shellcheck disable=SC2016 # literal backticks in the pattern, no expansion intended
forbidden_backticked='`(Bash|Read|Edit|Write|Agent|Workflow|Grep|Glob|WebFetch|WebSearch|TodoWrite|Skill|NotebookEdit|AskUserQuestion)`'
forbidden_agy='code_search|find_by_name|grep_search|list_dir|manage_subagents|define_subagent|replace_file_content|multi_replace_file_content|write_to_file|read_url_content|search_web'
forbidden="$forbidden|$forbidden_backticked|$forbidden_agy"
verb_re='⟨[a-z-]+⟩'

# check_absent_r DESC PATTERN DIR — passes when PATTERN matches nothing under
# DIR (grep exit 1, "no match" is success here). Fails loudly on an actual
# grep error (exit 2 — a missing/unreadable path, not "no match") instead of
# treating it as a pass, and fails with the hits when PATTERN does match.
check_absent_r() {
  local desc=$1 pattern=$2 dir=$3 out rc
  [[ -e $dir ]] || { err "missing: $dir"; return; }
  out=$(grep -rnE "$pattern" "$dir" 2>&1)
  rc=$?
  if ((rc == 2)); then
    err "grep failed on $desc: $out"
  elif ((rc == 0)); then
    err "$desc:"$'\n'"$out"
  fi
}

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

  check_absent_r "$name: harness tokens in neutral core" "$forbidden" "$core"

  token_out=$(grep -rIohE '⟨[^⟩]*⟩' "$core" 2>&1)
  token_rc=$?
  if ((token_rc == 2)); then
    err "$name: grep failed scanning core for verb tokens: $token_out"
  elif ((token_rc == 0)); then
    while IFS= read -r tok; do
      [[ -z $tok ]] && continue
      [[ $tok =~ ^⟨[a-z][a-z-]*⟩$ ]] || err "$name: malformed verb token: $tok"
    done < <(sort -u <<<"$token_out")
  fi

  used_out=$(grep -rIohE "$verb_re" "$core" 2>&1)
  used_rc=$?
  if ((used_rc == 2)); then
    err "$name: grep failed scanning core for verbs: $used_out"
    used=""
  else
    used=$(sort -u <<<"$used_out")
  fi

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

    if [[ -z $used ]]; then
      # A core that uses no verbs legitimately has an adapter with no
      # "## Harness mapping" rows — that is not a failure by itself. It is
      # only a failure when the adapter binds verbs nothing in the core
      # asked for.
      if [[ -n $bound ]]; then
        n=$(wc -l <<<"$bound")
        err "$name: no verbs used but $adir/SKILL.md binds $n: $(tr '\n' ' ' <<<"$bound")"
      fi
    else
      missing=$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$bound") | sed '/^$/d')
      dead=$(comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$bound") | sed '/^$/d')
      [[ -z $missing ]] || err "$adir/SKILL.md does not bind: $(tr '\n' ' ' <<<"$missing")"
      [[ -z $dead ]] || err "$adir/SKILL.md binds unused verbs: $(tr '\n' ' ' <<<"$dead")"
    fi
  done
  ((adapters)) || err "$name: no adapter under home/.claude/skills or home/.gemini/skills"
done

((fail)) && exit 1
echo PASS
