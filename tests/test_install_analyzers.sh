#!/usr/bin/env bash
# install_analyzers.sh against stub gh/uv/pipx/brew/uname. Nothing is
# downloaded: the stub gh fabricates a release asset matching the -p glob.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script=$PWD/scripts/install_analyzers.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

stubs=$work/stubs
mkdir -p "$stubs"
export STUB_LOG=$work/calls.log

# gh release download -R REPO -p GLOB -D DIR: writes an asset named after GLOB
# ('*' -> 1.0). Tarballs nest the binary in a directory, as golangci-lint does.
cat >"$stubs/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$STUB_LOG"
[[ -z ${STUB_GH_FAIL:-} ]] || exit 1
while [[ $# -gt 0 ]]; do
	case $1 in -p) glob=$2; shift ;; -D) dir=$2; shift ;; esac
	shift
done
asset=${glob//\*/1.0}
tool=${glob%%[_-]\**}
if [[ $asset == *.tar.gz ]]; then
	mkdir -p "$dir/src/nested"
	printf '#!/bin/sh\necho %s\n' "$tool" >"$dir/src/nested/$tool"
	tar -czf "$dir/$asset" -C "$dir/src" nested
	rm -rf "$dir/src"
else
	printf '#!/bin/sh\necho %s\n' "$asset" >"$dir/$asset"
fi
EOF
cat >"$stubs/uname" <<'EOF'
#!/usr/bin/env bash
case $1 in -s) echo "${STUB_OS:-Linux}" ;; -m) echo "${STUB_ARCH:-x86_64}" ;; esac
EOF
# uv / pipx / brew log the call and, like the real ones, leave the tool (the
# last argument) behind as an executable unless STUB_NO_BIN is set.
for t in uv pipx brew; do
	# shellcheck disable=SC2016 # $* and $STUB_LOG belong to the generated stub
	printf '#!/usr/bin/env bash\necho "%s $*" >>"$STUB_LOG"\n[[ -n ${STUB_NO_BIN:-} ]] || { mkdir -p "$ANALYZER_INSTALL_DIR"; printf "#!/bin/sh\\n" >"$ANALYZER_INSTALL_DIR/${!#}"; chmod +x "$ANALYZER_INSTALL_DIR/${!#}"; }\n' "$t" >"$stubs/$t"
done
chmod +x "$stubs"/*

# run DESC WANT_RC [ENV=VAL...] -- ARGS... — PATH holds only the stubs (minus
# any listed in HIDE) and system dirs, so real analyzers in ~/.local/bin or
# ~/go/bin never count as present.
run() {
	local desc=$1 want_rc=$2 rc
	shift 2
	local envs=()
	while [[ $1 != -- ]]; do envs+=("$1"); shift; done
	shift
	: >"$STUB_LOG"
	rm -rf "${work:?}/bin" "${work:?}/path"
	mkdir -p "$work/path"
	for s in "$stubs"/*; do
		[[ " ${HIDE:-} " == *" $(basename "$s") "* ]] || ln -s "$s" "$work/path/"
	done
	env "${envs[@]}" PATH="$work/path:/usr/bin:/bin" ANALYZER_INSTALL_DIR="$work/bin" \
		"$script" "$@" >"$work/out" 2>&1
	rc=$?
	[[ $rc -eq $want_rc ]] || err "$desc: exit $rc, want $want_rc; output: $(cat "$work/out")"
}

# --- release binaries, x86_64 -----------------------------------------------
run "release installs" 0 -- hadolint osv-scanner golangci-lint trufflehog
for t in hadolint osv-scanner golangci-lint trufflehog; do
	[[ -x $work/bin/$t ]] || err "release installs: $t not installed as an executable"
done
grep -q -- "-R hadolint/hadolint -p hadolint-linux-x86_64 " "$STUB_LOG" || err "hadolint asset glob wrong: $(cat "$STUB_LOG")"
grep -q -- "-p golangci-lint-\*-linux-amd64.tar.gz " "$STUB_LOG" || err "golangci-lint asset glob wrong"
[[ $("$work/bin/golangci-lint") == golangci-lint ]] || err "nested tarball binary not extracted"
grep -q 'Installed: hadolint osv-scanner golangci-lint trufflehog' "$work/out" || err "summary missing: $(cat "$work/out")"
grep -q 'is not on PATH' "$work/out" || err "should warn that the install dir is not on PATH"

# --- arm64 asset names differ per project -----------------------------------
run "arm64 globs" 0 STUB_ARCH=aarch64 -- gitleaks hadolint
grep -q -- "-p gitleaks_\*_linux_arm64.tar.gz " "$STUB_LOG" || err "gitleaks arm64 glob wrong: $(cat "$STUB_LOG")"
grep -q -- "-p hadolint-linux-arm64 " "$STUB_LOG" || err "hadolint arm64 glob wrong"

run "unsupported arch fails" 1 STUB_ARCH=riscv64 -- hadolint
grep -q 'Failed: hadolint' "$work/out" || err "unsupported arch: should report Failed"

# --- failures are reported, not swallowed -----------------------------------
run "gh failure" 1 STUB_GH_FAIL=1 -- actionlint
[[ ! -e $work/bin/actionlint ]] || err "gh failure: nothing should be installed"
grep -q 'Failed: actionlint' "$work/out" || err "gh failure: should report Failed"

# --- python tools: uv, else pipx --------------------------------------------
run "uv preferred" 0 -- semgrep ruff
grep -qx 'uv tool install semgrep' "$STUB_LOG" || err "semgrep should use uv: $(cat "$STUB_LOG")"
run "installer lied" 1 STUB_NO_BIN=1 -- semgrep
grep -q "semgrep: the installer reported success but no 'semgrep' binary was found" "$work/out" || err "missing binary after install not caught: $(cat "$work/out")"
grep -q 'Failed: semgrep' "$work/out" || err "missing binary should be reported as Failed"
HIDE=uv run "pipx fallback" 0 -- ruff
grep -qx 'pipx install ruff' "$STUB_LOG" || err "ruff should fall back to pipx: $(cat "$STUB_LOG")"
HIDE="uv pipx" run "no python installer" 1 -- ruff
grep -q 'needs uv or pipx' "$work/out" || err "should explain uv/pipx missing"

# --- macOS uses brew for everything -----------------------------------------
run "brew on macOS" 0 STUB_OS=Darwin -- hadolint ruff
[[ $(cat "$STUB_LOG") == $'brew install hadolint\nbrew install ruff' ]] || err "macOS should brew install: $(cat "$STUB_LOG")"

# --- present tools are skipped; dry-run and --check write nothing -----------
printf '#!/bin/sh\n' >"$stubs/hadolint"
chmod +x "$stubs/hadolint"
run "already present" 0 -- hadolint
[[ ! -s $STUB_LOG ]] || err "present tool should not be reinstalled: $(cat "$STUB_LOG")"
grep -q 'Already present: hadolint' "$work/out" || err "should report already present"
rm "$stubs/hadolint"

run "dry run" 0 -- -n hadolint semgrep
[[ ! -s $STUB_LOG && ! -e $work/bin ]] || err "dry run must not call installers or write: $(cat "$STUB_LOG")"
grep -q 'Would install: hadolint semgrep' "$work/out" || err "dry run summary missing"

run "check reports missing" 1 -- --check hadolint
[[ ! -s $STUB_LOG ]] || err "--check must not install"
grep -q 'Missing: hadolint' "$work/out" || err "--check should list missing tools"

run "unknown tool" 1 -- nosuchlinter
grep -q 'Unknown analyzer: nosuchlinter' "$work/out" || err "unknown tool message missing"

[[ $fail -eq 0 ]] && echo "PASS: install_analyzers"
exit "$fail"
