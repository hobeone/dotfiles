#!/usr/bin/env bash
# select-angles.sh: size tiers, pattern gates, --full, and the angle list
# staying derived from method.md's headings.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script=skills-shared/deep-pr-review/scripts/select-angles.sh
method=skills-shared/deep-pr-review/method.md
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

# add_file DIFF PATH new|mod LINE... — append one file to a unified diff. A
# modified file also carries one removed line, so it counts as 1 + #LINE lines.
add_file() {
  local out=$1 path=$2 kind=$3 line
  shift 3
  {
    printf 'diff --git a/%s b/%s\n' "$path" "$path"
    if [[ $kind == new ]]; then
      printf 'new file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1,%d @@\n' "$path" "$#"
    else
      printf 'index 1111111..2222222 100644\n--- a/%s\n+++ b/%s\n@@ -1,1 +1,%d @@\n-old\n' "$path" "$path" "$#"
    fi
    for line in "$@"; do printf '+%s\n' "$line"; done
  } >>"$out"
}

# many N — N distinct innocuous lines (none match any gate pattern).
many() { local i; for ((i = 1; i <= $1; i++)); do printf 'v%d=%d\n' "$i" "$i"; done; }

# run DIFF [ARGS...] — select-angles output, or a FAIL and empty output.
run() {
  local out
  out=$("$script" --diff "$@") || { err "select-angles.sh $* exited non-zero: $out"; return 1; }
  printf '%s' "$out"
}

# tier_of DIFF [ARGS...] — just the tier name ("" when the run failed).
tier_of() { local j; j=$(run "$@") && jq -r .tier <<<"$j"; }

# expect NAME JSON TIER "LETTERS" "SKIPPED LETTERS"
expect() {
  local name=$1 json=$2 tier=$3 want=$4 want_skip=$5 got got_skip
  got=$(jq -r '.angles | join(" ")' <<<"$json")
  got_skip=$(jq -r '[.skipped[].angle] | join(" ")' <<<"$json")
  [[ $(jq -r .tier <<<"$json") == "$tier" ]] || err "$name: tier is $(jq -r .tier <<<"$json"), want $tier"
  [[ $got == "$want" ]] || err "$name: angles '$got', want '$want'"
  [[ $got_skip == "$want_skip" ]] || err "$name: skipped '$got_skip', want '$want_skip'"
  # Every angle is either selected or skipped, never both and never lost.
  [[ $(jq -r '(.angles + [.skipped[].angle]) | sort | join("")' <<<"$json") \
     == "$(printf '%s' "$all" | tr -d ' ' | fold -w1 | sort | tr -d '\n')" ]] \
    || err "$name: angles + skipped is not the full angle list"
}

# --- the angle list is method.md's headings, and the policy letters exist ---
all=$(sed -nE 's/^### Angle ([A-Z]) — .*/\1/p' "$method" | tr '\n' ' ')
all=${all% }
[[ -n $all ]] || err "could not read angle headings from $method"

d=$work/full-src.diff; : >"$d"
add_file "$d" a.sh mod 'x=1'
json=$(run "$d" --full)
[[ $(jq -r '.angles | join(" ")' <<<"$json") == "$all" ]] \
  || err "--full angle list differs from method.md headings ('$all')"

for var in base_tiny base_docs gated; do
  letters=$(sed -nE "s/^$var=\"([A-Z ]+)\"\$/\\1/p" "$script")
  [[ -n $letters ]] || { err "could not read $var from $script"; continue; }
  for l in $letters; do
    grep -qE "^### Angle $l — " "$method" || err "$var names angle $l, which is not a heading in method.md"
  done
done

# --- docs tier ---
d=$work/docs.diff; : >"$d"
add_file "$d" README.md mod 'hello'
add_file "$d" docs/notes.go new 'package docs'
add_file "$d" notes.txt new 'x'
json=$(run "$d") && expect docs "$json" docs "A B J O P" "C D E F G H I K L M N"
jq -e '.skipped[] | select(.angle == "C") | .reason == "docs tier"' <<<"$json" >/dev/null || err "docs: skip reason is not 'docs tier'"
d=$work/notdocs.diff; : >"$d"
add_file "$d" README.md mod 'hello'
add_file "$d" main.sh mod 'x=1'
[[ $(tier_of "$d") == tiny ]] || err "README.md plus code is not a docs-only change"

# --- tiny tier: base set plus gates ---
d=$work/tiny.diff; : >"$d"
add_file "$d" a.sh mod 'x=1'
json=$(run "$d") && expect tiny "$json" tiny "A B C D J M N O P" "E F G H I K L"
jq -e '.lines == 2 and .files == 1' <<<"$json" >/dev/null || err "tiny: lines/files wrong: $json"
jq -e '.skipped[] | select(.angle == "F") | .reason == "tiny tier"' <<<"$json" >/dev/null || err "tiny: F reason is not 'tiny tier'"
jq -e '.skipped[] | select(.angle == "E") | .reason | startswith("gate not met")' <<<"$json" >/dev/null || err "tiny: E reason does not say the gate was not met"

json=$(run "$d" --github-remote no) && expect "tiny no remote" "$json" tiny "A B C D J M O P" "E F G H I K L N"
d2=$work/tiny-new.diff; : >"$d2"
add_file "$d2" a.sh new 'x=1'
json=$(run "$d2") && expect "tiny only new files" "$json" tiny "A B C D J N O P" "E F G H I K L M"

# Each content gate fires on its own pattern, and only that gate.
gate_case() { # gate_case LETTER LINE — LINE must fire LETTER's gate and no other content gate
  local letter=$1 line=$2 dd=$work/gate-$1.diff other
  : >"$dd"
  add_file "$dd" a.sh mod "$line"
  json=$(run "$dd") || return
  jq -e --arg l "$letter" '.angles | index($l)' <<<"$json" >/dev/null || err "gate $letter did not fire on '$line'"
  for other in E K L; do
    [[ $other == "$letter" ]] && continue
    ! jq -e --arg l "$other" '.angles | index($l)' <<<"$json" >/dev/null || err "gate $other fired on the $letter line '$line'"
  done
}
gate_case E 'p := newProxy()'
gate_case E 'return delegate.get(id)'
gate_case K 'mu := Mutex{}'
gate_case K 'seen := map[string]int{}'
gate_case K 'l := newLatch()'
gate_case K 'n := atomic.AddInt64(&c, 1)'
gate_case K 'var once Once'
gate_case L 'return nil'
gate_case L 'rescue StandardError'
gate_case L 'except ValueError:'
gate_case L 'throw new Error("x")'

# Gates look at ADDED lines only: a deleted line that matches must not fire.
d=$work/removed.diff
{
  printf 'diff --git a/a.sh b/a.sh\nindex 1..2 100644\n--- a/a.sh\n+++ b/a.sh\n@@ -1,2 +1,1 @@\n'
  printf -- '-proxy := wrap(cache)\n-if err != nil { return nil }\n+x=1\n'
} >"$d"
json=$(run "$d") && expect "removed lines do not fire gates" "$json" tiny "A B C D J M N O P" "E F G H I K L"

# --- boundaries: 49 vs 50 changed lines, 3 vs 4 files ---
d=$work/b49.diff; : >"$d"; mapfile -t ls < <(many 48); add_file "$d" a.sh mod "${ls[@]}"   # 1 removed + 48 added = 49
[[ $(tier_of "$d") == tiny ]] || err "49 changed lines should be tiny"
d=$work/b50.diff; : >"$d"; mapfile -t ls < <(many 49); add_file "$d" a.sh mod "${ls[@]}"   # 50
[[ $(tier_of "$d") == small ]] || err "50 changed lines should be small"
d=$work/f3.diff; : >"$d"; for f in a b c; do add_file "$d" "$f.sh" new 'x=1'; done
[[ $(tier_of "$d") == tiny ]] || err "3 small files should be tiny"
d=$work/f4.diff; : >"$d"; for f in a b c d; do add_file "$d" "$f.sh" new 'x=1'; done
[[ $(tier_of "$d") == small ]] || err "4 files should be small"

# A removed line whose text starts with "-- " prints as "--- ..." and must still count.
d=$work/dashes.diff
printf 'diff --git a/q.sql b/q.sql\nindex 1..2 100644\n--- a/q.sql\n+++ b/q.sql\n@@ -1,1 +1,1 @@\n--- a comment\n+++ b comment\n' >"$d"
json=$(run "$d")
jq -e '.lines == 2' <<<"$json" >/dev/null || err "'---'/'+++' content lines inside a hunk were not counted: $json"

# --- small tier: everything except gated angles whose gate is false ---
d=$work/small.diff; : >"$d"; mapfile -t ls < <(many 60); add_file "$d" a.sh mod "${ls[@]}"
json=$(run "$d") && expect small "$json" small "A B C D F G H I J M N O P" "E K L"
d=$work/small-e.diff; : >"$d"; mapfile -t ls < <(many 60); add_file "$d" a.sh mod "${ls[@]}" 'p := newProxy()'
json=$(run "$d") && expect "small with E gate" "$json" small "A B C D E F G H I J M N O P" "K L"

# --- large tier: all angles ---
d=$work/large.diff; : >"$d"; mapfile -t ls < <(many 300); add_file "$d" a.sh mod "${ls[@]}"
json=$(run "$d") && expect large "$json" large "$all" ""

# --- --full: everything, nothing skipped, real tier still reported ---
d=$work/tiny.diff
json=$(run "$d" --full) && expect "--full" "$json" tiny "$all" ""

# --- unusable diff: conservative, every angle ---
json=$(run "$work/does-not-exist.diff") && expect "missing diff" "$json" unknown "$all" ""
: >"$work/empty.diff"
json=$(run "$work/empty.diff") && expect "empty diff" "$json" unknown "$all" ""
printf 'not a diff\n' >"$work/garbage.diff"
json=$(run "$work/garbage.diff") && expect "garbage diff" "$json" unknown "$all" ""

# --- usage errors ---
if "$script" >/dev/null 2>&1; then err "no --diff exited 0"; fi
if "$script" --diff "$work/tiny.diff" --github-remote maybe >/dev/null 2>&1; then err "bad --github-remote exited 0"; fi

# --- reachable through both adapters' symlinked scripts/ ---
for ad in home/.claude/skills/deep-pr-review home/.gemini/skills/deep-pr-review; do
  json=$("$ad/scripts/select-angles.sh" --diff "$work/tiny.diff" --full 2>&1)
  [[ $(jq -r '.angles | join(" ")' <<<"$json") == "$all" ]] || err "$ad/scripts/select-angles.sh does not resolve method.md: $json"
done

((fail)) && exit 1
echo PASS
