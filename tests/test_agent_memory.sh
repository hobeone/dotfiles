#!/usr/bin/env bash
# agent-memory against throwaway repos, a throwaway store and a local bare
# remote. Nothing touches the real store or ~/.claude.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script="$PWD/home/bin/agent-memory"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
work=$(cd "$work" && pwd -P) # macOS: /var -> /private/var

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; touch "$work/failed"; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export AGENT_MEMORY_HOME="$work/store" CLAUDE_PROJECTS_DIR="$work/claude-projects"

# am ARGS...: runs agent-memory; output to $work/out, exit code to $rc.
am() {
	"$script" "$@" >"$work/out" 2>&1
	rc=$?
}

# make_repo DIR [ORIGIN]: a git repo with one commit and, optionally, origin.
make_repo() {
	mkdir -p "$1"
	git -C "$1" init -q
	git -C "$1" commit -q --allow-empty -m init
	[[ -n ${2:-} ]] && git -C "$1" remote add origin "$2"
	return 0
}

# --- helpers, sourced -------------------------------------------------------
# shellcheck source=home/bin/agent-memory
source "$script"
set +e

check_url() {
	local got
	got=$(key_from_url "$1")
	[[ $got == "$2" ]] || err "key_from_url '$1': got '$got', want '$2'"
}
check_url "git@github.com:hobeone/gonzbd.git" "hobeone/gonzbd"
check_url "https://github.com/hobeone/gonzbd" "hobeone/gonzbd"
check_url "https://github.com/hobeone/gonzbd.git/" "hobeone/gonzbd"
check_url "ssh://git@example.com:2222/team/tool.git" "team/tool"
check_url "/srv/git/team/tool.git" "team/tool"
# A key becomes a path under the store, so nothing may climb out of it.
check_url "https://github.com/HobeOne/GoNZBD.git" "hobeone/gonzbd"
for bad in "https://example.com/../x" "https://example.com/a/.." "https://example.com/.git/x" "gonzbd"; do
	key_from_url "$bad" >/dev/null 2>&1 && err "key_from_url accepted '$bad'"
done

mkdir -p "$work/fm"
printf -- '---\nname: plain\ndescription: "quoted: with colon"\nmetadata:\n  type: user\n---\nname: body-not-frontmatter\n' >"$work/fm/a.md"
[[ $(front_matter_field "$work/fm/a.md" name) == plain ]] || err "front matter name"
[[ $(front_matter_field "$work/fm/a.md" description) == "quoted: with colon" ]] ||
	err "front matter description: '$(front_matter_field "$work/fm/a.md" description)'"
[[ -z $(front_matter_field "$work/fm/a.md" type) ]] || err "front matter: nested field read as top-level"
printf 'no front matter\nname: x\n' >"$work/fm/b.md"
[[ -z $(front_matter_field "$work/fm/b.md" name) ]] || err "front matter read from a file without it"

# --- key --------------------------------------------------------------------
make_repo "$work/src/gonzbd" "git@github.com:hobeone/gonzbd.git"
git -C "$work/src/gonzbd" worktree add -q "$work/src/gonzbd-wt" 2>/dev/null
make_repo "$work/src/gonzbd_agy" "https://github.com/hobeone/gonzbd"
make_repo "$work/src/no remote"
mkdir -p "$work/src/plain dir/sub"

am key "$work/src/gonzbd"
[[ $rc -eq 0 && $(cat "$work/out") == hobeone/gonzbd ]] || err "key ssh origin: $(cat "$work/out")"
mkdir -p "$work/src/gonzbd/deep/er"
am key "$work/src/gonzbd/deep/er"
[[ $(cat "$work/out") == hobeone/gonzbd ]] || err "key from a subdirectory: $(cat "$work/out")"
am key "$work/src/gonzbd-wt"
[[ $(cat "$work/out") == hobeone/gonzbd ]] || err "key from a linked worktree: $(cat "$work/out")"
am key "$work/src/gonzbd_agy"
[[ $(cat "$work/out") == hobeone/gonzbd ]] || err "key of a second checkout: $(cat "$work/out")"
am key "$work/src/no remote"
[[ $(cat "$work/out") == local/no-remote ]] || err "key without origin: $(cat "$work/out")"
am key "$work/src/plain dir/sub"
[[ $(cat "$work/out") == local/sub ]] || err "key outside git: $(cat "$work/out")"

# --- paths ------------------------------------------------------------------
am paths "$work/src/gonzbd"
want="global: $work/store/global
project: $work/store/projects/hobeone/gonzbd"
[[ $(cat "$work/out") == "$want" ]] || err "paths: $(cat "$work/out")"
[[ -d $work/store/projects/hobeone/gonzbd && -d $work/store/global ]] || err "paths: folders not created"

# --- link -------------------------------------------------------------------
enc() { sed -E 's/[^A-Za-z0-9]/-/g' <<<"$1"; }
mem_of() { printf '%s/%s/memory' "$CLAUDE_PROJECTS_DIR" "$(enc "$1")"; }
target="$work/store/projects/hobeone/gonzbd"

am link "$work/src/gonzbd"
[[ $rc -eq 0 ]] || err "link: exit $rc: $(cat "$work/out")"
[[ $(readlink -f "$(mem_of "$work/src/gonzbd")") == "$target" ]] || err "link: not pointing at the project folder"
am link "$work/src/gonzbd"
[[ $rc -eq 0 ]] || err "link again: exit $rc"

# A linked worktree's memory is its main checkout's: no folder of its own.
am link "$work/src/gonzbd-wt"
[[ $rc -eq 0 ]] || err "link worktree: exit $rc: $(cat "$work/out")"
[[ ! -e $(mem_of "$work/src/gonzbd-wt") ]] || err "link worktree: made a folder for the worktree path"

# A stale link (the old hand-made gonzbd_agy -> gonzbd link) is replaced.
mkdir -p "$(dirname "$(mem_of "$work/src/gonzbd_agy")")" "$work/elsewhere"
ln -s "$work/elsewhere" "$(mem_of "$work/src/gonzbd_agy")"
am link "$work/src/gonzbd_agy"
[[ $rc -eq 0 && $(readlink -f "$(mem_of "$work/src/gonzbd_agy")") == "$target" ]] ||
	err "link: stale link not replaced: $(cat "$work/out")"

# An empty folder, or one holding only an empty MEMORY.md, is replaced.
m=$(mem_of "$work/src/no remote")
mkdir -p "$m" && : >"$m/MEMORY.md"
am link "$work/src/no remote"
[[ $rc -eq 0 && -L $m ]] || err "link: empty folder not replaced: $(cat "$work/out")"

# A folder holding memories is never replaced.
make_repo "$work/src/keep" "git@github.com:hobeone/keep.git"
m=$(mem_of "$work/src/keep")
mkdir -p "$m" && echo data >"$m/fact.md"
am link "$work/src/keep"
[[ $rc -ne 0 ]] || err "link: replaced a folder holding memories"
grep -qF "holds memories" "$work/out" || err "link refusal: $(cat "$work/out")"
[[ -f $m/fact.md && ! -L $m ]] || err "link refusal: folder was changed"

# --- index ------------------------------------------------------------------
g="$work/store/global"
printf -- '---\nname: zeta-rule\ndescription: last one\n---\nbody\n' >"$g/z.md"
printf -- '---\nname: alpha-rule\ndescription: "first: one"\n---\nbody\n' >"$g/a.md"
printf 'no front matter\n' >"$g/m.md"
echo "hand-written" >"$g/MEMORY.md"
echo "# readme" >"$g/README.md"
echo "x" >"$target/proj.md"
am index
[[ $rc -eq 0 ]] || err "index: exit $rc: $(cat "$work/out")"
got=$(grep '^- ' "$g/MEMORY.md")
want="- [alpha-rule](a.md) — first: one
- [m](m.md)
- [zeta-rule](z.md) — last one"
[[ $got == "$want" ]] || err "index global: got
$got"
grep -qF "hand-written" "$g/MEMORY.md" && err "index: hand edits survived"
grep -qF "[proj](proj.md)" "$target/MEMORY.md" || err "index: project folder not indexed"
mkdir -p "$work/store/projects/hobeone/.github" && echo y >"$work/store/projects/hobeone/.github/d.md"
am index
[[ -f $work/store/projects/hobeone/.github/MEMORY.md ]] || err "index: skipped a dot-named repo"
for f in "$g"/.MEMORY*; do [[ -e $f ]] && err "index: temp file left behind: $f"; done

# --- sync -------------------------------------------------------------------
git init -q --bare "$work/remote.git"
mk_store() {
	git clone -q "$work/remote.git" "$1" 2>/dev/null
}
mk_store "$work/m1"
mk_store "$work/m2"

AGENT_MEMORY_HOME="$work/m1" am sync
[[ $rc -eq 0 ]] || err "sync first push: exit $rc: $(cat "$work/out")"

mkdir -p "$work/m1/global" "$work/m2/projects/hobeone/gonzbd"
echo one >"$work/m1/global/from-m1.md"
echo two >"$work/m2/projects/hobeone/gonzbd/from-m2.md"
AGENT_MEMORY_HOME="$work/m1" am sync
[[ $rc -eq 0 ]] || err "sync m1: exit $rc: $(cat "$work/out")"
AGENT_MEMORY_HOME="$work/m2" am sync
[[ $rc -eq 0 ]] || err "sync m2: exit $rc: $(cat "$work/out")"
AGENT_MEMORY_HOME="$work/m1" am sync
[[ -f $work/m1/projects/hobeone/gonzbd/from-m2.md && -f $work/m2/global/from-m1.md ]] ||
	err "sync: machines did not converge"
grep -qF "from-m1.md" "$work/m2/global/MEMORY.md" || err "sync: index not rebuilt after pull"
git -C "$work/m1" ls-files | grep 'MEMORY.md' >/dev/null && err "sync: committed a generated index"
grep -qxF '.MEMORY.md.*' "$work/m1/.gitignore" || err "sync: .gitignore lacks the index temp files"

# A temp index left by a killed run is never committed.
echo junk >"$work/m1/global/.MEMORY.md.Stray1"
AGENT_MEMORY_HOME="$work/m1" am sync
git -C "$work/m1" ls-files | grep 'Stray1' >/dev/null && err "sync: committed a stray temp index"

# A new machine whose store has no commits yet takes the remote's.
mkdir -p "$work/m3" && git -C "$work/m3" init -q && git -C "$work/m3" remote add origin "$work/remote.git"
git -C "$work/m3" symbolic-ref HEAD "refs/heads/$(git -C "$work/m1" symbolic-ref --short HEAD)"
AGENT_MEMORY_HOME="$work/m3" am sync
[[ $rc -eq 0 && -f $work/m3/global/from-m1.md ]] || err "sync unborn store: rc=$rc $(cat "$work/out")"

# Files still changing during the sync wait for the next run; it is not a failure.
cat >"$work/m1/.git/hooks/post-commit" <<'HOOK'
#!/bin/sh
date +%s%N >>"$AGENT_MEMORY_HOME/global/busy.md"
HOOK
chmod +x "$work/m1/.git/hooks/post-commit"
echo start >"$work/m1/global/busy.md"
AGENT_MEMORY_HOME="$work/m1" am sync
[[ $rc -eq 0 ]] || err "sync while files change: exit $rc: $(cat "$work/out")"
grep -qF "go out with the next run" "$work/out" || err "sync while files change: $(cat "$work/out")"
rm -f "$work/m1/.git/hooks/post-commit"
AGENT_MEMORY_HOME="$work/m1" am sync

# The same memory edited on both machines: the run fails, nothing is lost.
echo "m1 edit" >"$work/m1/global/from-m1.md"
echo "m2 edit" >"$work/m2/global/from-m1.md"
AGENT_MEMORY_HOME="$work/m1" am sync
AGENT_MEMORY_HOME="$work/m2" am sync
[[ $rc -ne 0 ]] || err "sync conflict: exit 0"
grep -qF "conflicted" "$work/out" || err "sync conflict message: $(cat "$work/out")"
[[ $(git -C "$work/m2" show HEAD:global/from-m1.md) == "m2 edit" ]] || err "sync conflict: local edit lost"
[[ ! -d $work/m2/.git/rebase-merge && ! -d $work/m2/.git/rebase-apply ]] || err "sync conflict: rebase left in progress"

# A store with no remote just commits.
git init -q "$work/solo"
echo x >"$work/solo/fact.md"
AGENT_MEMORY_HOME="$work/solo" am sync
[[ $rc -eq 0 && -n $(git -C "$work/solo" ls-files fact.md) ]] || err "sync without origin: rc=$rc $(cat "$work/out")"

git -C "$work/m3" checkout -q --detach
AGENT_MEMORY_HOME="$work/m3" am sync
if [[ $rc -eq 0 ]] || ! grep -qF "detached HEAD" "$work/out"; then
	err "sync detached: rc=$rc $(cat "$work/out")"
fi

AGENT_MEMORY_HOME="$work/not-a-repo" am sync
if [[ $rc -eq 0 ]] || ! grep -qF "not a git repository" "$work/out"; then
	err "sync outside git: $(cat "$work/out")"
fi

# --- check ------------------------------------------------------------------
cs="$work/checkstore"
mkdir -p "$cs/global" "$cs/projects/hobeone/gonzbd"
printf -- '---\nname: ok\ndescription: fine\n---\n' >"$cs/global/ok.md"
printf -- '---\nname: dup\ndescription: fine\n---\n' >"$cs/global/dup.md"
AGENT_MEMORY_HOME="$cs" am check "$work/src/gonzbd"
[[ $rc -eq 0 && ! -s $work/out ]] || err "check clean: rc=$rc $(cat "$work/out")"
p="$cs/projects/hobeone/gonzbd"
printf 'no front matter\n' >"$p/bare.md"
printf -- '---\nname: nodesc\n---\n' >"$p/nodesc.md"
printf -- '---\ndescription: x\n---\n' >"$p/noname.md"
printf -- '---\nname: other-name\ndescription: x\n---\n' >"$p/renamed.md"
printf -- '---\nname: dup\ndescription: x\n---\n' >"$p/dup.md"
printf -- '---\nname: colon\ndescription: always brace: "x"\n---\n' >"$p/colon.md"
printf -- '---\nname: quoted\ndescription: "fine: quoted"\n---\nbody: with colon\n' >"$p/quoted.md"
AGENT_MEMORY_HOME="$cs" am check "$work/src/gonzbd"
[[ $rc -eq 1 ]] || err "check problems: exit $rc, want 1"
for want in "projects/hobeone/gonzbd/bare.md: no front matter" \
	"projects/hobeone/gonzbd/nodesc.md: front matter has no description" \
	"projects/hobeone/gonzbd/noname.md: front matter has no name" \
	"projects/hobeone/gonzbd/renamed.md: name 'other-name' does not match the file name" \
	"projects/hobeone/gonzbd/dup.md: global/dup.md has the same name" \
	'projects/hobeone/gonzbd/colon.md: a value containing ": " must be quoted'; do
	grep -qxF -- "$want" "$work/out" || err "check: missing '$want' in: $(cat "$work/out")"
done
[[ $(wc -l <"$work/out") -eq 6 ]] || err "check: want exactly 6 problems: $(cat "$work/out")"

# --- sync --if-needed and the lock ------------------------------------------
git init -q --bare "$work/hremote.git"
git clone -q "$work/hremote.git" "$work/hs" 2>/dev/null
export AGENT_MEMORY_HOME="$work/hs"
am sync
[[ $rc -eq 0 ]] || err "hook store first sync: $(cat "$work/out")"

# Nothing to commit or push: no network at all, proved by an origin that
# does not exist, which a real sync then fails on.
git -C "$work/hs" remote set-url origin "$work/nowhere.git"
am sync --if-needed
[[ $rc -eq 0 ]] || err "sync --if-needed with nothing to do touched the network: $(cat "$work/out")"
am sync
[[ $rc -ne 0 ]] || err "sync against a missing origin succeeded: the --if-needed check above proves nothing"
git -C "$work/hs" remote set-url origin "$work/hremote.git"

# A second sync waits for the lock instead of failing.
if command -v flock >/dev/null 2>&1; then
	(flock 9 && sleep 2) 9>"$work/hs/.git/agent-memory.lock" &
	sleep 0.3
	printf -- '---\nname: waited\ndescription: behind the lock\n---\n' >"$work/hs/global/waited.md"
	am sync
	[[ $rc -eq 0 ]] || err "sync behind a held lock: $(cat "$work/out")"
	wait
	git -C "$work/hremote.git" log --format= --name-only | grep -x global/waited.md >/dev/null ||
		err "sync behind a held lock did not push"
fi

# A rebase left in progress by a killed run is cancelled before syncing,
# and the local commit survives.
git clone -q "$work/hremote.git" "$work/stale" 2>/dev/null
mkdir -p "$work/stale/global"
echo theirs >"$work/hs/global/clash.md"
AGENT_MEMORY_HOME="$work/hs" am sync
echo mine >"$work/stale/global/clash.md"
git -C "$work/stale" add -A && git -C "$work/stale" commit -q -m mine
git -C "$work/stale" pull -q --rebase >/dev/null 2>&1
[[ -d $work/stale/.git/rebase-merge || -d $work/stale/.git/rebase-apply ]] || err "stale rebase: fixture made no rebase"
AGENT_MEMORY_HOME="$work/stale" am sync
if [[ -d $work/stale/.git/rebase-merge || -d $work/stale/.git/rebase-apply ]]; then
	err "stale rebase: still in progress after sync: $(cat "$work/out")"
fi
[[ $(git -C "$work/stale" show HEAD:global/clash.md 2>/dev/null) == mine ]] || err "stale rebase: local commit lost"
git -C "$work/stale" symbolic-ref -q HEAD >/dev/null || err "stale rebase: left a detached HEAD"
rm "$work/hs/global/clash.md"
AGENT_MEMORY_HOME="$work/hs" am sync

# --- hooks ------------------------------------------------------------------
# run_hook TOOL EVENT CWD: feeds the hook its JSON from an unrelated working
# directory, as agy does; stdout to $work/out.
run_hook() {
	printf '{"cwd":"%s","hookEventName":"x","workspacePaths":["%s"]}' "$3" "$3" |
		(cd / && "$script" hook "$1" "$2") >"$work/out" 2>"$work/err"
	rc=$?
}
# grep without -q reads all of git's output: under pipefail, -q can exit
# first and fail the pipeline with SIGPIPE although the file was pushed.
pushed() { git -C "$work/hremote.git" log --format= --name-only | grep -x "$1" >/dev/null; }

make_repo "$work/src/hooked" "git@github.com:hobeone/hooked.git"
run_hook claude start "$work/src/hooked"
[[ $rc -eq 0 && ! -s $work/out ]] || err "claude start: rc=$rc out=$(cat "$work/out") err=$(cat "$work/err")"
[[ $(readlink -f "$(mem_of "$work/src/hooked")") == "$work/hs/projects/hobeone/hooked" ]] ||
	err "claude start: project not linked"
[[ -f $work/hs/projects/hobeone/hooked/MEMORY.md ]] || err "claude start: index not built"

printf -- '---\nname: learned\ndescription: from a turn\n---\n' >"$work/hs/projects/hobeone/hooked/learned.md"
run_hook claude stop "$work/src/hooked"
[[ $rc -eq 0 && ! -s $work/out ]] || err "claude stop: rc=$rc out=$(cat "$work/out")"
pushed projects/hobeone/hooked/learned.md || err "claude stop: new memory not pushed"

printf -- '---\nname: wrong\n---\n' >"$work/hs/projects/hobeone/hooked/broken.md"
run_hook claude start "$work/src/hooked"
if ! grep -qF "memory files to fix" "$work/out" || ! grep -qF "broken.md: front matter has no description" "$work/out"; then
	err "claude start: problems not reported: $(cat "$work/out")"
fi
rm "$work/hs/projects/hobeone/hooked/broken.md"

run_hook claude start "$work/src/keep"
if [[ $rc -ne 0 ]] || ! grep -qF "not wired up" "$work/out"; then
	err "claude start link failure: rc=$rc $(cat "$work/out")"
fi

run_hook agy start "$work/src/hooked"
[[ $rc -eq 0 ]] || err "agy start: exit $rc"
msg=$(jq -r '.injectSteps[0].systemMessage.systemMessage' "$work/out" 2>/dev/null)
for want in "## Project hobeone/hooked: $work/hs/projects/hobeone/hooked" \
	"- [learned](learned.md) — from a turn" "## Global: $work/hs/global" \
	"- [waited](waited.md) — behind the lock"; do
	grep -qxF -- "$want" <<<"$msg" || err "agy start: context lacks '$want': $(cat "$work/out")"
done

printf -- '---\nname: wrong\n---\n' >"$work/hs/projects/hobeone/hooked/broken.md"
run_hook agy start "$work/src/hooked"
msg=$(jq -r '.injectSteps[0].systemMessage.systemMessage' "$work/out" 2>/dev/null)
if ! grep -qxF "## Memory files to fix" <<<"$msg" ||
	! grep -qF "broken.md: front matter has no description" <<<"$msg"; then
	err "agy start: problems not in context: $(cat "$work/out")"
fi
rm "$work/hs/projects/hobeone/hooked/broken.md"

echo x >"$work/hs/global/agy-wrote.md"
run_hook agy stop "$work/src/hooked"
[[ $rc -eq 0 && $(cat "$work/out") == "{}" ]] || err "agy stop: rc=$rc out=$(cat "$work/out")"
pushed global/agy-wrote.md || err "agy stop: memory not pushed"

# A failing sync is reported and the session still gets its memory.
git -C "$work/hs" remote set-url origin "$work/nowhere.git"
run_hook agy start "$work/src/hooked"
msg=$(jq -r '.injectSteps[0].systemMessage.systemMessage' "$work/out" 2>/dev/null)
if ! grep -qF "sync failed" <<<"$msg" || ! grep -qF "[learned](learned.md)" <<<"$msg"; then
	err "agy start with a failing sync: $(cat "$work/out")"
fi
git -C "$work/hs" remote set-url origin "$work/hremote.git"

# No store on this machine: nothing happens, and agy still gets valid JSON.
AGENT_MEMORY_HOME="$work/absent" run_hook claude start "$work/src/hooked"
[[ $rc -eq 0 && ! -s $work/out ]] || err "claude start without a store: $(cat "$work/out")"
AGENT_MEMORY_HOME="$work/absent" run_hook agy start "$work/src/hooked"
[[ $rc -eq 0 && $(cat "$work/out") == "{}" ]] || err "agy start without a store: $(cat "$work/out")"

printf '{}' | "$script" hook gemini start >/dev/null 2>&1
[[ $? -eq 2 ]] || err "hook with an unknown tool: want exit 2"
export AGENT_MEMORY_HOME="$work/store"

# --- arguments --------------------------------------------------------------
am bogus
[[ $rc -eq 2 ]] || err "unknown command: exit $rc"
ln -s "$script" "$work/agent-memory"
"$work/agent-memory" --help >"$work/out" 2>&1
grep -q "^Usage: agent-memory" "$work/out" || err "--help via symlink: $(cat "$work/out")"

[[ -e $work/failed ]] && fail=1
[[ $fail -eq 0 ]] && echo "PASS"
exit "$fail"
