#!/usr/bin/env bash
# update-deps behavior against throwaway repos and stub go/bun commands.
# Nothing is downloaded: the stubs only log how they were called.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script="$PWD/home/bin/update-deps"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail=0
# err also leaves a marker file, so a failure inside a ( cd ... ) subshell,
# whose fail=1 never reaches this shell, still fails the run.
err() { printf 'FAIL: %s\n' "$*"; fail=1; touch "$work/failed"; }

# Keep the user's git config (signing, hooks) out of the fixture repos.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# Stub go and bun: each call appends "<cmd> <cwd basename> <args>" to $STUB_LOG.
# `bun update` also bumps foo in bun.lock when STUB_BUMP is set, so there is a
# dependency change to commit. `go list -m go@latest` reports STUB_GO_LATEST
# (default 1.27, the fixtures' go line, so nothing moves) and fails when
# STUB_GO_LATEST_FAIL is set; `go get go@X` and `go get toolchain@goX` rewrite
# that go.mod line.
mkdir -p "$work/bin"
for cmd in go bun; do
	cat >"$work/bin/$cmd" <<'EOF'
#!/usr/bin/env bash
printf '%s %s %s\n' "$(basename "$0")" "$(basename "$PWD")" "$*" >>"$STUB_LOG"
if [[ $(basename "$0") == bun && ${1:-} == update && -n ${STUB_BUMP:-} ]]; then
	sed -i.bak 's/foo@1.0.0/foo@1.1.0/' bun.lock && rm -f bun.lock.bak
fi
if [[ $(basename "$0") == go && ${1:-} == get && -n ${STUB_GO_BUMP:-} ]]; then
	sed -i.bak 's/v1.0.0/v1.1.0/' go.mod && rm -f go.mod.bak
fi
if [[ $(basename "$0") == go && ${1:-} == list && ${*: -1} == go@latest ]]; then
	if [[ -n ${STUB_GO_LATEST_FAIL:-} ]]; then
		echo "go: stub go@latest failure" >&2
		exit 1
	fi
	echo "go ${STUB_GO_LATEST:-1.27}"
	exit 0
fi
if [[ $(basename "$0") == go && ${1:-} == get && ${2:-} == go@* ]]; then
	sed -i.bak "s/^go .*/go ${2#go@}/" go.mod && rm -f go.mod.bak
fi
if [[ $(basename "$0") == go && ${1:-} == get && ${2:-} == toolchain@* ]]; then
	sed -i.bak "s/^toolchain .*/toolchain ${2#toolchain@}/" go.mod && rm -f go.mod.bak
fi
if [[ $(basename "$0") == go && ${1:-} == list && -n ${STUB_GO_LIST_FAIL:-} ]]; then
	echo "go: stub list failure" >&2
	exit 1
fi
if [[ $(basename "$0") == go && ${1:-} == list ]]; then
	sed -n 's/^[[:space:]]*require[[:space:]]*\([^[:space:]]*\).*/\1/p' go.mod
fi
EOF
	chmod +x "$work/bin/$cmd"
done
export PATH="$work/bin:$PATH"

# make_repo DIR UI_DIR KIT: a committed git repo with go.mod and a frontend in
# DIR/UI_DIR; KIT=1 makes the frontend depend on @sveltejs/kit.
make_repo() {
	local dir=$1 ui=$2 kit=$3 deps='"vite": "^8.0.0"'
	[[ $kit -eq 1 ]] && deps="\"@sveltejs/kit\": \"^3.0.0\", $deps"
	mkdir -p "$dir/$ui" "$dir/sub"
	printf 'module example.com/m\n\ngo 1.27\n' >"$dir/go.mod"
	: >"$dir/go.sum"
	printf '{ "devDependencies": { %s } }\n' "$deps" >"$dir/$ui/package.json"
	printf '{\n  "packages": {\n    "foo": ["foo@1.0.0", "", {}, "sha512-x"],\n  }\n}\n' \
		>"$dir/$ui/bun.lock"
	touch "$dir/sub/.keep"
	git -C "$dir" init -q
	git -C "$dir" add -A
	git -C "$dir" commit -q -m init
}

# run_main DIR ARGS...: runs update-deps from DIR/sub with a fresh stub log;
# output goes to $work/out, the exit code to $rc.
run_main() {
	local dir=$1
	shift
	export STUB_LOG="$work/log"
	: >"$STUB_LOG"
	(cd "$dir/sub" && "$script" "$@") >"$work/out" 2>&1 </dev/null
	rc=$?
}

# want_log DESC LINE: the stub log has LINE exactly.
want_log() { grep -qxF -- "$2" "$STUB_LOG" || err "$1: log lacks '$2'"; }
# no_log DESC PATTERN: no stub log line matches PATTERN.
no_log() { ! grep -q -- "$2" "$STUB_LOG" || err "$1: log has '$2'"; }

# --- helpers, sourced -------------------------------------------------------
# shellcheck source=home/bin/update-deps
source "$script"
set +e # the script's set -e must not end the test on an expected failure

check_detect() {
	local desc=$1 want_rc=$2 want_out=$3 out got_rc
	out=$(detect_ui_dir 2>"$work/stderr")
	got_rc=$?
	[[ $got_rc -eq $want_rc ]] || err "$desc: exit $got_rc, want $want_rc"
	[[ $out == "$want_out" ]] || err "$desc: '$out', want '$want_out'"
}

mkdir -p "$work/d/one/ui" "$work/d/none/ui" "$work/d/two/ui" "$work/d/two/web"
touch "$work/d/one/ui/bun.lock" "$work/d/two/ui/bun.lock" "$work/d/two/web/bun.lock"
(cd "$work/d/one" && check_detect "one frontend" 0 ui)
(cd "$work/d/none" && check_detect "no frontend" 1 "")
(cd "$work/d/two" && check_detect "two frontends" 1 "")
grep -q "several frontends (ui web)" "$work/stderr" ||
	err "two frontends: stderr lacks the candidate list"
(cd "$work/d/two" && UPDATE_DEPS_UI_DIR=web/ check_detect "override picks one" 0 web)
(cd "$work/d/one" && UPDATE_DEPS_UI_DIR=nope check_detect "override without bun.lock" 1 "")

printf '{ "devDependencies": { "@sveltejs/kit": "^3.0.0" } }\n' >"$work/d/one/ui/package.json"
printf '{ "devDependencies": { "svelte": "^5.0.0" } }\n' >"$work/d/two/ui/package.json"
uses_sveltekit "$work/d/one/ui" || err "uses_sveltekit: kit dependency not seen"
! uses_sveltekit "$work/d/two/ui" || err "uses_sveltekit: plain svelte taken for kit"

# --- end to end: SvelteKit frontend in ui/ ----------------------------------
make_repo "$work/kit" ui 1
run_main "$work/kit" --latest --skip-verify
[[ $rc -eq 0 ]] || err "kit --latest: exit $rc: $(cat "$work/out")"
# No direct dependencies: nothing to upgrade, and never a blanket get -u ./...
no_log "kit --latest" "^go kit get"
want_log "kit --latest" "go kit mod tidy"
grep -qF "No direct Go dependencies to update." "$work/out" ||
	err "kit --latest: no-deps skip not reported: $(cat "$work/out")"
want_log "kit --latest" "bun ui update --latest !typescript"
want_log "kit --latest" "bun ui prune"
want_log "kit --latest" "bun ui x svelte-kit sync"
no_log "kit --skip-verify" "go build"

STUB_BUMP=1 run_main "$work/kit"
[[ $rc -eq 0 ]] || err "kit verify: exit $rc: $(cat "$work/out")"
want_log "kit plain update" "bun ui update"
no_log "kit plain update" "update --latest"
order=$(grep -E '^bun ui (install|prune|x svelte-kit|run check)' "$STUB_LOG" | tail -n 4 | cut -d' ' -f3- | paste -sd'|' -)
[[ $order == "install --frozen-lockfile|prune|x svelte-kit sync|run check" ]] ||
	err "kit verify: frozen install, prune, sync, check out of order: '$order'"
# go build embeds the frontend build output, so bun run build must come first.
build_lines=$(grep -E '^(bun ui run build|go kit build)' "$STUB_LOG" | cut -d' ' -f1 | paste -sd' ' -)
[[ $build_lines == "bun go" ]] ||
	err "kit verify: want bun run build before go build, got '$build_lines'"

# --- end to end: plain svelte frontend in frontend/ -------------------------
make_repo "$work/plain" frontend 0
run_main "$work/plain" --latest --skip-verify
[[ $rc -eq 0 ]] || err "plain: exit $rc: $(cat "$work/out")"
want_log "plain" "bun frontend update --latest !typescript"
want_log "plain" "bun frontend prune"
no_log "plain" "svelte-kit"

# --- verification is skipped when the update changed nothing ----------------
make_repo "$work/same" ui 1
run_main "$work/same"
[[ $rc -eq 0 ]] || err "unchanged: exit $rc: $(cat "$work/out")"
grep -qF "Skipping verification: no dependency file changed" "$work/out" ||
	err "unchanged: skip not reported: $(cat "$work/out")"
want_log "unchanged" "bun ui update"
no_log "unchanged" "install --frozen-lockfile"
no_log "unchanged" "run check"
no_log "unchanged" "go build"

# A dependency edit made before the run is not a change by this run: it still
# skips, and a --commit of it says why it went unverified.
make_repo "$work/predirty" ui 0
sed -i.bak 's/foo@1.0.0/foo@1.0.5/' "$work/predirty/ui/bun.lock" && rm -f "$work/predirty/ui/bun.lock.bak"
run_main "$work/predirty" --commit --yes
[[ $rc -eq 0 ]] || err "pre-edited: exit $rc: $(cat "$work/out")"
no_log "pre-edited" "go build"
msg=$(git -C "$work/predirty" log -1 --format=%B)
grep -qxF -- "- foo 1.0.0 -> 1.0.5" <<<"$msg" || err "pre-edited: no foo change in message: '$msg'"
grep -qxF "Not verified: the update itself changed no dependency file." <<<"$msg" ||
	err "pre-edited: unverified reason missing: '$msg'"

make_repo "$work/verified" ui 0
STUB_BUMP=1 run_main "$work/verified" --commit --yes
[[ $rc -eq 0 ]] || err "verified commit: exit $rc: $(cat "$work/out")"
want_log "verified commit" "go verified build ./..."
msg=$(git -C "$work/verified" log -1 --format=%B)
grep -q "^Verified with go build" <<<"$msg" || err "verified commit: message: '$msg'"

# --- --commit commits only the dependency files -----------------------------
make_repo "$work/commit" ui 0
echo "local edit" >"$work/commit/sub/.keep"
STUB_BUMP=1 run_main "$work/commit" --skip-verify --commit --yes
[[ $rc -eq 0 ]] || err "commit: exit $rc: $(cat "$work/out")"
msg=$(git -C "$work/commit" log -1 --format=%B)
[[ $msg == "chore(deps): update go and bun dependencies"* ]] || err "commit: subject: '$msg'"
grep -qxF -- "- foo 1.0.0 -> 1.1.0" <<<"$msg" || err "commit: no foo bump in message: '$msg'"
grep -qxF "Not verified: update ran with --skip-verify." <<<"$msg" ||
	err "commit: --skip-verify not noted: '$msg'"
[[ $(git -C "$work/commit" show --name-only --format= HEAD) == "ui/bun.lock" ]] ||
	err "commit: committed $(git -C "$work/commit" show --name-only --format= HEAD | paste -sd' ' -)"
git -C "$work/commit" diff --quiet -- sub/.keep && err "commit: unrelated edit was committed"

make_repo "$work/clean" ui 0
run_main "$work/clean" --skip-verify --commit --yes
grep -qF "No dependency changes to commit." "$work/out" || err "clean commit: no-op not reported"

# --- direct dependencies from go.mod ----------------------------------------
make_repo "$work/direct" ui 0
printf 'module example.com/m\n\ngo 1.27\n\nrequire example.com/pkg v1.0.0\nrequire example.com/other v0.1.0\n' \
	>"$work/direct/go.mod"
git -C "$work/direct" commit -q -a -m "add dependencies"
run_main "$work/direct" --skip-verify
[[ $rc -eq 0 ]] || err "direct: exit $rc: $(cat "$work/out")"
# Each direct module goes to @upgrade with no -u, which would also raise
# transitive modules past what their dependents require.
want_log "direct deps" "go direct get -v -t example.com/pkg@upgrade example.com/other@upgrade"
no_log "direct deps" "get -u"

# A failing go list stops the run instead of falling back to some other get.
make_repo "$work/listfail" ui 0
STUB_GO_LIST_FAIL=1 run_main "$work/listfail" --go-only --skip-verify
[[ $rc -ne 0 ]] || err "go list failure: exit 0, want non-zero"
grep -qF "stub list failure" "$work/out" || err "go list failure: error not shown: $(cat "$work/out")"
no_log "go list failure" "^go listfail get"

# --- Go version ---------------------------------------------------------------
# A newer release moves the go line and the matching golang image tags; a
# longer version that merely starts with the old one, and vendored
# Dockerfiles, are left alone.
make_repo "$work/gover" ui 0
printf 'module example.com/m\n\ngo 1.27.3\n' >"$work/gover/go.mod"
mkdir -p "$work/gover/deploy" "$work/gover/vendor/x"
printf 'FROM golang:1.27.3-alpine AS go-builder\nFROM golang:1.27.30\nFROM golang:1.27.3\n' \
	>"$work/gover/Dockerfile"
printf 'FROM golang:1.27-alpine\n' >"$work/gover/deploy/app.Dockerfile"
printf 'FROM golang:1.27.3\n' >"$work/gover/vendor/x/Dockerfile"
git -C "$work/gover" add -A
git -C "$work/gover" commit -q -m "pin go"
STUB_GO_LATEST=1.27.4 run_main "$work/gover" --go-only --commit --yes
[[ $rc -eq 0 ]] || err "go version: exit $rc: $(cat "$work/out")"
want_log "go version" "go gover get go@1.27.4"
# The version moves before the modules, which may need the newer Go.
order=$(grep -E '^go gover (get go@|mod tidy)' "$STUB_LOG" | cut -d' ' -f3 | paste -sd' ' -)
[[ $order == "get mod" ]] || err "go version: want the version bump before tidy, got '$order'"
grep -qx 'go 1.27.4' "$work/gover/go.mod" || err "go version: go.mod: $(cat "$work/gover/go.mod")"
want_df=$'FROM golang:1.27.4-alpine AS go-builder\nFROM golang:1.27.30\nFROM golang:1.27.4'
[[ $(cat "$work/gover/Dockerfile") == "$want_df" ]] ||
	err "go version: Dockerfile: $(cat "$work/gover/Dockerfile")"
[[ $(cat "$work/gover/deploy/app.Dockerfile") == "FROM golang:1.27-alpine" ]] ||
	err "go version: a patch release moved a minor-only tag"
[[ $(cat "$work/gover/vendor/x/Dockerfile") == "FROM golang:1.27.3" ]] ||
	err "go version: vendored Dockerfile was rewritten"
msg=$(git -C "$work/gover" log -1 --format=%B)
grep -qxF -- "- go 1.27.3 -> 1.27.4" <<<"$msg" || err "go version: no go bump in message: '$msg'"
[[ $(git -C "$work/gover" show --name-only --format= HEAD | sort | paste -sd' ' -) == "Dockerfile go.mod" ]] ||
	err "go version: committed $(git -C "$work/gover" show --name-only --format= HEAD | paste -sd' ' -)"

# A new minor release moves minor-only tags too.
make_repo "$work/gominor" ui 0
printf 'module example.com/m\n\ngo 1.27.3\n' >"$work/gominor/go.mod"
printf 'FROM golang:1.27-alpine\nFROM golang:1.27\n' >"$work/gominor/Dockerfile"

git -C "$work/gominor" add -A && git -C "$work/gominor" commit -q -m "add Dockerfile"
STUB_GO_LATEST=1.28.0 run_main "$work/gominor" --go-only --skip-verify
[[ $rc -eq 0 ]] || err "go minor: exit $rc: $(cat "$work/out")"
[[ $(cat "$work/gominor/Dockerfile") == $'FROM golang:1.28-alpine\nFROM golang:1.28' ]] ||
	err "go minor: Dockerfile: $(cat "$work/gominor/Dockerfile")"

# With a toolchain line, the toolchain moves and the go line (the minimum
# Go the module supports) stays.
make_repo "$work/gotool" ui 0
printf 'module example.com/m\n\ngo 1.25.0\n\ntoolchain go1.26.3\n' >"$work/gotool/go.mod"
git -C "$work/gotool" commit -q -a -m "pin toolchain"
STUB_GO_LATEST=1.27.4 run_main "$work/gotool" --go-only --skip-verify
[[ $rc -eq 0 ]] || err "toolchain: exit $rc: $(cat "$work/out")"
want_log "toolchain" "go gotool get toolchain@go1.27.4"
no_log "toolchain" "get go@"
grep -qx 'go 1.25.0' "$work/gotool/go.mod" || err "toolchain: go line moved: $(cat "$work/gotool/go.mod")"

# Already current, or ahead of the latest release: nothing is fetched.
make_repo "$work/gocur" ui 0
printf 'module example.com/m\n\ngo 1.27.4\n' >"$work/gocur/go.mod"
git -C "$work/gocur" commit -q -a -m "pin go"
STUB_GO_LATEST=1.27.4 run_main "$work/gocur" --go-only --skip-verify
[[ $rc -eq 0 ]] || err "go current: exit $rc: $(cat "$work/out")"
no_log "go current" "get go@"
grep -qF "is the latest release" "$work/out" || err "go current: not reported: $(cat "$work/out")"
STUB_GO_LATEST=1.27.2 run_main "$work/gocur" --go-only --skip-verify
no_log "go ahead" "get go@"

# --skip-go-version and --bun-only leave the version alone.
STUB_GO_LATEST=1.28.0 run_main "$work/gocur" --go-only --skip-verify --skip-go-version
[[ $rc -eq 0 ]] || err "skip-go-version: exit $rc: $(cat "$work/out")"
no_log "skip-go-version" "go@latest"
no_log "skip-go-version" "get go@"
STUB_GO_LATEST=1.28.0 run_main "$work/gocur" --bun-only --skip-verify
no_log "bun-only go version" "go@"

# A failed lookup of the latest release stops the run before any update.
STUB_GO_LATEST_FAIL=1 run_main "$work/gocur" --skip-verify
[[ $rc -ne 0 ]] || err "go@latest failure: exit 0, want non-zero"
grep -qF "stub go@latest failure" "$work/out" || err "go@latest failure: error not shown: $(cat "$work/out")"
no_log "go@latest failure" "get"
no_log "go@latest failure" "bun"

# --- --go-only / --bun-only filtering ---------------------------------------
make_repo "$work/filter" ui 0
printf 'module example.com/m\n\ngo 1.27\n\nrequire example.com/pkg v1.0.0\n' >"$work/filter/go.mod"
git -C "$work/filter" commit -q -a -m "add dependency"
STUB_GO_BUMP=1 run_main "$work/filter" --go-only --commit --yes
[[ $rc -eq 0 ]] || err "go-only: exit $rc: $(cat "$work/out")"
want_log "go-only" "go filter get -v -t example.com/pkg@upgrade"
want_log "go-only" "go filter build ./..."
no_log "go-only" "bun ui"
msg=$(git -C "$work/filter" log -1 --format=%B)
[[ $msg == "chore(deps): update go dependencies"* ]] || err "go-only: subject: '$msg'"

make_repo "$work/filterbun" ui 0
STUB_BUMP=1 run_main "$work/filterbun" --bun-only --commit --yes
[[ $rc -eq 0 ]] || err "bun-only: exit $rc: $(cat "$work/out")"
want_log "bun-only" "bun ui update"
want_log "bun-only" "bun ui run check"
no_log "bun-only" "go filterbun get"
no_log "bun-only" "go filterbun build"
msg=$(git -C "$work/filterbun" log -1 --format=%B)
[[ $msg == "chore(deps): update bun dependencies"* ]] || err "bun-only: subject: '$msg'"

# --- arguments and preconditions --------------------------------------------
run_main "$work/kit" --go-only --bun-only
[[ $rc -eq 2 ]] || err "conflicting args: exit $rc, want 2"
grep -qF "cannot specify both --go-only and --bun-only" "$work/out" ||
	err "conflicting args: expected message: $(cat "$work/out")"

run_main "$work/kit" --bogus
[[ $rc -eq 2 ]] || err "unknown argument: exit $rc, want 2"

mkdir -p "$work/notgit/sub"
run_main "$work/notgit"
if [[ $rc -ne 1 ]] || ! grep -qF "not inside a git repository" "$work/out"; then
	err "outside git: exit $rc: $(cat "$work/out")"
fi

make_repo "$work/nogo" ui 0
git -C "$work/nogo" rm -q go.mod
run_main "$work/nogo"
if [[ $rc -ne 1 ]] || ! grep -qF "no go.mod" "$work/out"; then
	err "no go.mod: exit $rc: $(cat "$work/out")"
fi
[[ ! -s $STUB_LOG ]] || err "no go.mod: ran commands anyway"

# --help goes through a symlink, the way ~/bin/update-deps is installed.
ln -s "$script" "$work/bin/update-deps"
"$work/bin/update-deps" --help >"$work/out" 2>&1
grep -q "^Usage: update-deps" "$work/out" || err "--help via symlink: $(cat "$work/out")"

[[ -e $work/failed ]] && fail=1
[[ $fail -eq 0 ]] && echo "PASS"
exit "$fail"
