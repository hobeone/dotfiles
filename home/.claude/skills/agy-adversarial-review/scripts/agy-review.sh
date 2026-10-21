#!/usr/bin/env bash
# Run agy's /adversarial-review over a diff, read-only, and prove the tree did
# not move. Exits non-zero if the repository changed, regardless of what the
# review found — a dirty tree invalidates the run.
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage: agy-review.sh --prompt FILE --out FILE [options]

required:
  --prompt FILE     review prompt (compose per SKILL.md; first line is usually
                    /adversarial-review)
  --out FILE        where agy's stdout+stderr is written

options:
  --repo DIR        repository to guard (default: git toplevel of $PWD)
  --model NAME      model id, or auto:<family>-<tier>[-<effort>] to take the
                    newest matching model agy offers.
                    default: auto:gemini-flash-high
  --effort LEVEL    default: high
  --timeout DUR     --print-timeout value, default: 20m
  --allow-dirty     permit a dirty starting tree (still fails if it CHANGES)

exit codes:
  0  review ran and the repository is untouched
  1  usage or precondition error (includes a claude-* model, refused)
  2  agy exited non-zero (out file still written)
  3  the repository changed during the review  <-- treat the run as void
  4  the model is not available on agy (or availability could not be
     checked); the recommendation is on stderr and agy was NOT run. Show it
     to the user - never swap the model silently.
EOF
}

prompt=''
out=''
repo=''
allow_dirty=0
model=auto:gemini-flash-high
effort=high
timeout=20m

while [ $# -gt 0 ]; do
	case "$1" in
	--prompt) prompt=${2:?--prompt needs a value}; shift 2 ;;
	--out) out=${2:?--out needs a value}; shift 2 ;;
	--repo) repo=${2:?--repo needs a value}; shift 2 ;;
	--model) model=${2:?--model needs a value}; shift 2 ;;
	--effort) effort=${2:?--effort needs a value}; shift 2 ;;
	--timeout) timeout=${2:?--timeout needs a value}; shift 2 ;;
	--allow-dirty) allow_dirty=1; shift ;;
	-h | --help) usage; exit 0 ;;
	*) printf 'unknown argument: %s\n\n' "$1" >&2; usage; exit 1 ;;
	esac
done

if [ -z "$prompt" ] || [ -z "$out" ]; then usage; exit 1; fi
[ -r "$prompt" ] || { echo "prompt file not readable: $prompt" >&2; exit 1; }
command -v agy >/dev/null || { echo "agy not on PATH" >&2; exit 1; }

# Resolve the model against what agy actually offers, before any git check or
# agy run: a model that does not exist must stop here with a recommendation,
# not fail minutes into a review or be swapped for another behind the user's
# back. resolve-model.sh exits 3 (unavailable) or 4 (cannot list); both mean
# "ask", so both become 4 here, and its stderr carries the recommendation.
resolver=$(dirname "$0")/../../model-check/scripts/resolve-model.sh
[ -x "$resolver" ] || { echo "model-check resolver not found: $resolver" >&2; exit 1; }
resolve_rc=0
resolved=$("$resolver" "$model") || resolve_rc=$?
case "$resolve_rc" in
0) model=$resolved ;;
1) exit 1 ;;
*) exit 4 ;;
esac

repo=${repo:-$(git rev-parse --show-toplevel)}
[ -d "$repo/.git" ] || [ -f "$repo/.git" ] || { echo "not a git repo: $repo" >&2; exit 1; }

# A claude-* model forfeits the entire point: agy can drive Claude, and then the
# review is not an independent second opinion.
case "$model" in
claude-*) echo "refusing --model $model: defeats the cross-model purpose" >&2; exit 1 ;;
esac

status_before=$(git -C "$repo" status --porcelain)
stash_before=$(git -C "$repo" stash list)

if [ -n "$status_before" ] && [ "$allow_dirty" -eq 0 ]; then
	echo "repository is dirty; commit, or pass --allow-dirty and scope the" >&2
	echo "prompt to an explicit commit range so the working tree is not the target." >&2
	printf '%s\n' "$status_before" >&2
	exit 1
fi

mkdir -p "$(dirname "$out")"

echo "agy $model (effort=$effort, timeout=$timeout) -> $out" >&2
echo "this takes 10-25 minutes; do not interrupt" >&2

rc=0
# --mode plan is the read-only guard: it sets execution mode at the harness
# level, which a prompt asking nicely does not.
agy --model "$model" --effort "$effort" --mode plan \
	--print-timeout "$timeout" \
	-p "$(cat "$prompt")" >"$out" 2>&1 || rc=$?

status_after=$(git -C "$repo" status --porcelain)
stash_after=$(git -C "$repo" stash list)

moved=0
if [ "$status_after" != "$status_before" ]; then
	echo "WORKING TREE CHANGED during the review:" >&2
	diff <(printf '%s\n' "$status_before") <(printf '%s\n' "$status_after") >&2 || true
	moved=1
fi
if [ "$stash_after" != "$stash_before" ]; then
	echo "STASH STACK CHANGED during the review:" >&2
	diff <(printf '%s\n' "$stash_before") <(printf '%s\n' "$stash_after") >&2 || true
	moved=1
fi

if [ "$moved" -eq 1 ]; then
	echo "the run is void: findings from a review that mutated the repo cannot be trusted" >&2
	exit 3
fi

echo "repository untouched; findings in $out" >&2
[ "$rc" -eq 0 ] || { echo "agy exited $rc (output still written)" >&2; exit 2; }
