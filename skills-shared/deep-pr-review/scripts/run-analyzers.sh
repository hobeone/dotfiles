#!/usr/bin/env bash
# Run the optional deterministic analyzers that apply to a diff and emit one
# normalised JSON result. Every tool is optional, but a tool that APPLIED to
# the diff and did not run is reported (not_installed / failed) so the review
# can say so; absence never fails the run.
#
# Usage:
#   run-analyzers.sh --base REF [--head REF] [--out FILE] [--all-lines]
#   run-analyzers.sh --summarize FILE
#
# --base REF     compare against REF (merge-base semantics: BASE...HEAD)
# --head REF     analyse that commit. Without it, the working tree vs BASE plus
#                untracked files. A --head other than the checked-out HEAD (or a
#                dirty tree) is analysed in a throwaway detached worktree; the
#                commit must already exist locally.
# --out FILE     write the JSON there instead of stdout
# --all-lines    keep findings on unchanged lines too (default: changed lines only;
#                the rest are counted per tool as outside_diff)
# --summarize F  print the two markdown lines for a review body and exit
#
# Env ANALYZER_BIN_DIR: when set, ONLY executables in that directory count as
# installed (test hook); otherwise PATH is searched.
#
# Exit 0 whenever analysis completed, even if every tool was missing; 1 on
# usage or git errors.
#
# Upstream formats implemented (verified against docs/--help where available;
# those marked (memory) could not be fetched or run on the authoring machine):
#   ShellCheck     0.10  -f json1 -> {"comments":[{file,line,level,code,message}]}
#   trufflehog     3.x   filesystem --json --no-update --no-verification: NDJSON,
#                        SourceMetadata.Data.Filesystem.{file,line}, DetectorName (memory)
#   gitleaks       8.19+ `dir` / <8.19 `detect --no-git`; --report-format json
#                        --report-path F --redact --exit-code 0: array of
#                        {RuleID,File,StartLine} (memory for shape)
#   semgrep        1.x   scan --json --metrics=off --quiet: {results:[{check_id,path,
#                        start.line,extra.{message,severity}}],errors:[]} (memory)
#   golangci-lint  v1 `--out-format json` (stdout) / v2 `--output.json.path F`:
#                        {"Issues":[{FromLinter,Text,Pos.{Filename,Line}}]}; v2 run live
#   ruff           0.x   check --output-format json --exit-zero: [{code,message,
#                        filename(abs),location.row}] (memory)
#   actionlint     1.7   -format '{{json .}}': [{message,filepath,line,kind}] (docs: array)
#   hadolint       2.x   -f json --no-fail: [{code,file,level,line,message}] (memory)
#   osv-scanner    v1 `--format json -L F` / v2 `scan source --format json -L F`:
#                        {results:[{source.path,packages:[{package,vulnerabilities:[{id,summary}]}]}]};
#                        exit 1 = vulnerabilities found, 128 = no packages (memory)
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }
usage() { sed -n '2,24p' "$0"; }

# ---------------------------------------------------------------------------
# --summarize: two markdown lines from a result file.
# ---------------------------------------------------------------------------
summarize() {
  [[ -r $1 ]] || die "cannot read result file: $1"
  jq -r '
    def pl($n; $w): "\($n) \($w)\(if $n == 1 then "" else "s" end)";
    def lbl: if .tool == "secrets" and .engine then "secrets/\(.engine)" else .tool end;
    def join_or_none: if length == 0 then "none" else join(" · ") end;
    "**Static analyzers run:** "
      + (.tools | map(select(.status == "ran")
          | "\(lbl) (\(pl(.files; "file")), \(pl(.findings; "finding")), \(.outside_diff) outside diff)")
        | join_or_none),
    "**Static analyzers NOT run:** "
      + (.tools | map(select(.status == "not_installed" or .status == "failed")
          | if .status == "not_installed"
            then "\(.tool) — not installed (applies to \(pl(.files; "changed file")))"
            else "\(.tool) — failed: \(.reason // "unknown") (applies to \(pl(.files; "changed file")))" end)
        | join_or_none)
  ' "$1"
}

base=""; head=""; out=""; all_lines=0; sum_file=""
while (($#)); do
  case "$1" in
    --base)       base="${2:?--base needs a ref}"; shift 2 ;;
    --head)       head="${2:?--head needs a ref}"; shift 2 ;;
    --out)        out="${2:?--out needs a file}"; shift 2 ;;
    --all-lines)  all_lines=1; shift ;;
    --summarize)  sum_file="${2:?--summarize needs a file}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null || die "jq is not installed"
if [[ -n $sum_file ]]; then summarize "$sum_file"; exit 0; fi
[[ -n $base ]] || die "usage: run-analyzers.sh --base REF [--head REF] [--out FILE] [--all-lines] | --summarize FILE"

toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$toplevel"
base_sha=$(git rev-parse --verify -q "${base}^{commit}") || die "cannot resolve --base '$base'"
head_sha=""
if [[ -n $head ]]; then
  head_sha=$(git rev-parse --verify -q "${head}^{commit}") || die "cannot resolve --head '$head' (is the commit fetched locally?)"
fi

tmp=$(mktemp -d)
wt_added=0
cleanup() {
  if ((wt_added)); then
    git -C "$toplevel" worktree remove --force "$tmp/wt" >/dev/null 2>&1 || true
    git -C "$toplevel" worktree prune >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Analysis root, changed files, changed line ranges.
# ---------------------------------------------------------------------------
root=$toplevel
if [[ -n $head_sha ]]; then
  cur=$(git rev-parse HEAD)
  if [[ $head_sha != "$cur" || -n $(git status --porcelain --untracked-files=no) ]]; then
    git worktree add -q --detach "$tmp/wt" "$head_sha" >/dev/null 2>&1 || die "cannot create worktree at $head_sha"
    wt_added=1
    root=$tmp/wt
  fi
  range=("$base_sha...$head_sha")
  head_label=$head_sha
else
  range=("$base_sha")
  head_label=WORKTREE
fi

mapfile -d '' changed < <(git diff -z --name-only --diff-filter=ACMR "${range[@]}")
untracked=()
if [[ -z $head_sha ]]; then
  mapfile -d '' untracked < <(git ls-files -z --others --exclude-standard)
  changed+=("${untracked[@]}")
fi

# Added-line ranges from `git diff -U0` hunk headers: "+a,b" -> a..a+b-1.
# Untracked files are all-added.
git -c core.quotepath=off diff -U0 --no-color --diff-filter=ACMR "${range[@]}" | awk '
  /^\+\+\+ / { p = substr($0, 7); sub(/\t.*$/, "", p); next }
  /^@@ / {
    if (!match($0, /\+[0-9]+(,[0-9]+)?/)) next
    spec = substr($0, RSTART + 1, RLENGTH - 1)
    n = split(spec, a, ",")
    s = a[1] + 0; c = (n > 1) ? a[2] + 0 : 1
    if (c > 0) printf "%s\t%d\t%d\n", p, s, s + c - 1
  }' > "$tmp/ranges.tsv"
for f in ${untracked[@]+"${untracked[@]}"}; do
  printf '%s\t1\t2147483647\n' "$f" >> "$tmp/ranges.tsv"
done

# ---------------------------------------------------------------------------
# Plumbing shared by every tool.
# ---------------------------------------------------------------------------
: > "$tmp/tools.jsonl"
: > "$tmp/findings.jsonl"

find_tool() {
  if [[ -n ${ANALYZER_BIN_DIR+x} ]]; then
    [[ -f $ANALYZER_BIN_DIR/$1 && -x $ANALYZER_BIN_DIR/$1 ]] && printf '%s' "$ANALYZER_BIN_DIR/$1"
  else
    command -v "$1"
  fi
}

# finish TOOL STATUS FILES [REASON] [ENGINE]
finish() {
  jq -nc --arg tool "$1" --arg status "$2" --argjson files "$3" \
         --arg reason "${4:-}" --arg engine "${5:-}" \
    '{tool: $tool, status: $status, files: $files}
     + (if $reason != "" then {reason: $reason} else {} end)
     + (if $engine != "" then {engine: $engine} else {} end)' >> "$tmp/tools.jsonl"
}

tail_of() { tail -c 300 "$1" 2>/dev/null | tr '\n\t' '  '; }

# run_in DIR OUTFILE ERRFILE CMD... — sets rc; never trips set -e.
rc=0
run_in() {
  local dir=$1 o=$2 e=$3
  shift 3
  rc=0
  (cd "$dir" && "$@") >"$o" 2>"$e" || rc=$?
}

# not_run TOOL NFILES MISSING_MSG — records not_installed.
not_installed() { finish "$1" not_installed "$2" "$3"; }

# simple_tool TOOL NFILES "OKRC..." JQPROG CMD... — run in $root, check the exit
# code against the allowed list, normalise stdout through JQPROG into findings.
simple_tool() {
  local tool=$1 n=$2 ok=" $3 " prog=$4
  shift 4
  run_in "$root" "$tmp/$tool.out" "$tmp/$tool.err" "$@"
  if [[ $ok != *" $rc "* ]]; then
    finish "$tool" failed "$n" "exit $rc: $(tail_of "$tmp/$tool.err")"
    return
  fi
  if ! jq -c "$prog" "$tmp/$tool.out" > "$tmp/f.$tool" 2>/dev/null; then
    finish "$tool" failed "$n" "unparseable output: $(tail_of "$tmp/$tool.err")"
    return
  fi
  cat "$tmp/f.$tool" >> "$tmp/findings.jsonl"
  finish "$tool" ran "$n"
}

# ---------------------------------------------------------------------------
# Applicability.
# ---------------------------------------------------------------------------
first_line_of() { local l=""; IFS= read -r l < "$root/$1" 2>/dev/null || true; printf '%s' "$l"; }

sh_files=(); src_files=(); go_files=(); py_files=(); wf_files=(); docker_files=(); manifests=()
for f in ${changed[@]+"${changed[@]}"}; do
  b=${f##*/}
  case $f in
    *.sh|*.bash) sh_files+=("$f") ;;
    *) if [[ $(first_line_of "$f") =~ ^#!\ *(/usr/bin/env\ +)?(/[^\ ]*/)?(ba)?sh(\ |$) ]]; then sh_files+=("$f"); fi ;;
  esac
  case $f in
    *.py|*.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.go|*.java|*.kt|*.rb|*.php|*.c|*.h|*.cc|*.cpp|*.hpp|*.cs|*.rs|*.swift|*.scala) src_files+=("$f") ;;
  esac
  case $f in *.go) go_files+=("$f") ;; esac
  case $f in *.py) py_files+=("$f") ;; esac
  case $f in .github/workflows/*.yml|.github/workflows/*.yaml) wf_files+=("$f") ;; esac
  case $b in Dockerfile|Dockerfile.*|*.Dockerfile) docker_files+=("$f") ;; esac
  case $b in
    go.mod|go.sum|package-lock.json|pnpm-lock.yaml|yarn.lock|requirements*.txt|poetry.lock|uv.lock|Cargo.lock|composer.lock|Gemfile.lock)
      manifests+=("$f") ;;
  esac
done

# ---------------------------------------------------------------------------
# Tools.
# ---------------------------------------------------------------------------
sev_map='(if . == "error" then "high" elif . == "warning" then "medium" else "low" end)'

# ShellCheck ---------------------------------------------------------------
if ((${#sh_files[@]})); then
  if t=$(find_tool shellcheck); then
    simple_tool shellcheck ${#sh_files[@]} "0 1" \
      ".comments[] | {tool: \"shellcheck\", rule: (\"SC\" + (.code|tostring)), file, line,
         severity: (.level | $sev_map), message}" \
      "$t" -x -f json1 -- "${sh_files[@]}"
  else
    not_installed shellcheck ${#sh_files[@]} "shellcheck not on PATH"
  fi
else
  finish shellcheck not_applicable 0
fi

# secrets (trufflehog, else gitleaks) -------------------------------------------
# The matched value (trufflehog Raw/Redacted, gitleaks Secret/Match) is never
# copied into a finding, a message, or a failure reason.
if ((${#changed[@]})); then
  nc=${#changed[@]}
  if t=$(find_tool trufflehog); then
    run_in "$root" "$tmp/th.out" "$tmp/th.err" "$t" filesystem --json --no-update --no-verification "${changed[@]}"
    if ((rc != 0)); then
      finish secrets failed "$nc" "trufflehog exit $rc" trufflehog
    elif jq -cR 'fromjson? | select(type == "object" and has("DetectorName"))
        | ((.SourceMetadata.Data // {}) | [.[]] | .[0] // {}) as $m
        | {tool: "secrets", rule: .DetectorName, file: ($m.file // "unknown"), line: ($m.line // 0),
           severity: "high",
           message: ("Possible " + .DetectorName + " secret detected by trufflehog (value withheld)")}' \
        "$tmp/th.out" > "$tmp/f.secrets" 2>/dev/null; then
      cat "$tmp/f.secrets" >> "$tmp/findings.jsonl"
      finish secrets ran "$nc" "" trufflehog
    else
      finish secrets failed "$nc" "trufflehog output unparseable" trufflehog
    fi
  elif t=$(find_tool gitleaks); then
    # Scan a copy holding just the changed files so the scan is bounded to the
    # diff and `dir`/`--source` need no file-list flag.
    scan=$tmp/scan; mkdir -p "$scan"
    for f in "${changed[@]}"; do
      [[ -f $root/$f ]] || continue
      mkdir -p "$scan/$(dirname "$f")"
      cp "$root/$f" "$scan/$f"
    done
    gv=$("$t" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
    gmaj=${gv%%.*}; gmin=${gv#*.}
    if [[ -n $gv ]] && ((gmaj > 8 || (gmaj == 8 && gmin >= 19))); then
      gcmd=("$t" dir . --no-banner)
    else
      gcmd=("$t" detect --no-git --no-banner --source .)
    fi
    run_in "$scan" "$tmp/gl.out" "$tmp/gl.err" "${gcmd[@]}" --redact --exit-code 0 \
      --report-format json --report-path "$tmp/gl.json"
    if ((rc != 0)); then
      finish secrets failed "$nc" "gitleaks exit $rc" gitleaks
    else
      [[ -s $tmp/gl.json ]] || echo '[]' > "$tmp/gl.json"
      if jq -c '.[] | {tool: "secrets", rule: .RuleID, file: .File, line: .StartLine, severity: "high",
          message: ("Possible secret detected by gitleaks, rule " + .RuleID + " (value withheld)")}' \
          "$tmp/gl.json" > "$tmp/f.secrets" 2>/dev/null; then
        cat "$tmp/f.secrets" >> "$tmp/findings.jsonl"
        finish secrets ran "$nc" "" gitleaks
      else
        finish secrets failed "$nc" "gitleaks report unparseable" gitleaks
      fi
    fi
  else
    not_installed secrets "$nc" "neither trufflehog nor gitleaks on PATH"
  fi
else
  finish secrets not_applicable 0
fi

# semgrep --------------------------------------------------------------------------
if ((${#src_files[@]})); then
  if t=$(find_tool semgrep); then
    cfg=p/default
    if [[ -e $root/.semgrep.yml ]]; then cfg=.semgrep.yml
    elif [[ -d $root/.semgrep ]]; then cfg=.semgrep; fi
    # A config/network failure must surface as `failed`: exit != 0, or an
    # empty result alongside config/fetch-type errors.
    simple_tool semgrep ${#src_files[@]} "0" \
      'if ((.results | length) == 0) and ([.errors[]? | select(.level == "error" and (.type | tostring | test("Config|Fetch|Network|Rule"; "i")))] | length) > 0
         then error("semgrep config error")
         else .results[] | {tool: "semgrep", rule: .check_id, file: .path, line: .start.line,
           severity: (.extra.severity | ascii_upcase
             | if . == "ERROR" or . == "CRITICAL" or . == "HIGH" then "high"
               elif . == "WARNING" or . == "MEDIUM" then "medium" else "low" end),
           message: .extra.message} end' \
      "$t" scan --json --metrics=off --quiet --config "$cfg" "${src_files[@]}"
  else
    not_installed semgrep ${#src_files[@]} "semgrep not on PATH"
  fi
else
  finish semgrep not_applicable 0
fi

# golangci-lint --------------------------------------------------------------------
if ((${#go_files[@]})); then
  if t=$(find_tool golangci-lint); then
    gv=$("$t" --version 2>/dev/null | grep -oE 'version v?[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
    declare -A mod_pkgs=()
    for f in "${go_files[@]}"; do
      d=$(dirname "$f"); m=$d
      while [[ ! -f $root/$m/go.mod && $m != . && $m != / ]]; do m=$(dirname "$m"); done
      [[ -f $root/$m/go.mod ]] || m=.
      pkg=${d#"$m"}; pkg=./${pkg#/}
      case " ${mod_pkgs[$m]:-} " in *" $pkg "*) ;; *) mod_pkgs[$m]="${mod_pkgs[$m]:-} $pkg" ;; esac
    done
    : > "$tmp/f.golangci"
    gl_fail=""
    for m in "${!mod_pkgs[@]}"; do
      read -r -a pkgs <<<"${mod_pkgs[$m]}"
      if [[ ${gv:-0} -ge 2 ]]; then
        flags=(--output.json.path "$tmp/gc.json"); : > "$tmp/gc.json"
        run_in "$root/$m" "$tmp/gc.out" "$tmp/gc.err" "$t" run --issues-exit-code 0 "${flags[@]}" "${pkgs[@]}"
        cp "$tmp/gc.json" "$tmp/gc.out"
      else
        run_in "$root/$m" "$tmp/gc.out" "$tmp/gc.err" "$t" run --issues-exit-code 0 --out-format json "${pkgs[@]}"
      fi
      if ((rc != 0)); then gl_fail="exit $rc in module $m: $(tail_of "$tmp/gc.err")"; break; fi
      if ! jq -c --arg m "$m" '(.Issues // [])[] | {tool: "golangci-lint", rule: .FromLinter,
            file: (if (.Pos.Filename | startswith("/")) or $m == "." then .Pos.Filename else $m + "/" + .Pos.Filename end),
            line: .Pos.Line, severity: "medium", message: .Text}' "$tmp/gc.out" >> "$tmp/f.golangci" 2>/dev/null; then
        gl_fail="unparseable output in module $m: $(tail_of "$tmp/gc.err")"; break
      fi
    done
    if [[ -n $gl_fail ]]; then
      finish golangci-lint failed ${#go_files[@]} "$gl_fail"
    else
      cat "$tmp/f.golangci" >> "$tmp/findings.jsonl"
      finish golangci-lint ran ${#go_files[@]}
    fi
  else
    not_installed golangci-lint ${#go_files[@]} "golangci-lint not on PATH"
  fi
else
  finish golangci-lint not_applicable 0
fi

# ruff -------------------------------------------------------------------------------
if ((${#py_files[@]})); then
  if t=$(find_tool ruff); then
    simple_tool ruff ${#py_files[@]} "0" \
      '.[] | {tool: "ruff", rule: .code, file: .filename, line: .location.row, severity: "medium", message: .message}' \
      "$t" check --output-format json --no-cache --exit-zero "${py_files[@]}"
  else
    not_installed ruff ${#py_files[@]} "ruff not on PATH"
  fi
else
  finish ruff not_applicable 0
fi

# actionlint -----------------------------------------------------------------------
if ((${#wf_files[@]})); then
  if t=$(find_tool actionlint); then
    simple_tool actionlint ${#wf_files[@]} "0 1" \
      '(. // [])[] | {tool: "actionlint", rule: .kind, file: .filepath, line: .line, severity: "medium", message: .message}' \
      "$t" -format '{{json .}}' "${wf_files[@]}"
  else
    not_installed actionlint ${#wf_files[@]} "actionlint not on PATH"
  fi
else
  finish actionlint not_applicable 0
fi

# hadolint -------------------------------------------------------------------------
if ((${#docker_files[@]})); then
  if t=$(find_tool hadolint); then
    simple_tool hadolint ${#docker_files[@]} "0" \
      '(. // [])[] | {tool: "hadolint", rule: .code, file, line,
         severity: (if .level == "error" then "high" elif .level == "warning" then "medium" else "low" end), message}' \
      "$t" --no-fail -f json "${docker_files[@]}"
  else
    not_installed hadolint ${#docker_files[@]} "hadolint not on PATH"
  fi
else
  finish hadolint not_applicable 0
fi

# osv-scanner ----------------------------------------------------------------------
# go.sum is not a lockfile osv-scanner reads; its sibling go.mod is.
if ((${#manifests[@]})); then
  osv_args=()
  for f in "${manifests[@]}"; do
    if [[ ${f##*/} == go.sum ]]; then
      alt=$(dirname "$f")/go.mod
      if [[ -f $root/$alt ]]; then f=$alt; else continue; fi
    fi
    case " ${osv_args[*]:-} " in *" $f "*) ;; *) osv_args+=("$f") ;; esac
  done
  if t=$(find_tool osv-scanner); then
    ov=$("$t" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
    if [[ ${ov%%.*} == 1 ]]; then ocmd=("$t" --format json); else ocmd=("$t" scan source --format json); fi
    largs=(); for f in "${osv_args[@]}"; do largs+=(-L "$f"); done
    # Exit 128 = no packages found in the given files: ran, nothing to report.
    # Dependency findings are not line-filtered (dep:true).
    # shellcheck disable=SC2016 # jq variables, no shell expansion intended
    simple_tool osv-scanner ${#manifests[@]} "0 1 128" \
      '(.results // [])[] | .source.path as $p | (.packages // [])[] | .package as $k
         | (.vulnerabilities // [])[] | {tool: "osv-scanner", rule: .id, file: $p, line: 0, severity: "high", dep: true,
             message: ($k.name + "@" + $k.version + ": " + (.summary // "known vulnerability"))}' \
      "${ocmd[@]}" "${largs[@]}"
  else
    not_installed osv-scanner ${#manifests[@]} "osv-scanner not on PATH"
  fi
else
  finish osv-scanner not_applicable 0
fi

# ---------------------------------------------------------------------------
# Assemble: repo-relative paths, changed-line filtering, per-tool counts.
# ---------------------------------------------------------------------------
result=$(jq -n --arg base "$base_sha" --arg head "$head_label" --arg root "$root" \
  --argjson all "$all_lines" --rawfile ranges "$tmp/ranges.tsv" \
  --slurpfile tools "$tmp/tools.jsonl" --slurpfile fnd "$tmp/findings.jsonl" '
  def rel: sub("^\\./"; "") | if startswith($root + "/") then .[($root | length) + 1:] else . end;
  ($ranges | split("\n") | map(select(length > 0) | split("\t"))
    | reduce .[] as $r ({}; .[$r[0]] += [[($r[1] | tonumber), ($r[2] | tonumber)]])) as $rg
  | ($fnd | map(.file |= rel | .line = ((.line | tonumber? // 0))
      | . + {keep: ($all == 1 or (.dep // false)
              or (.file as $f | .line as $l | ($rg[$f] // []) | any(.[]; $l >= .[0] and $l <= .[1])))})) as $all_f
  | ($all_f | map(select(.keep))) as $kept
  | {base: $base, head: $head,
     tools: ($tools | map(. as $t | if .status == "ran"
        then . + {findings: ($kept | map(select(.tool == $t.tool)) | length),
                  outside_diff: ($all_f | map(select(.tool == $t.tool and (.keep | not))) | length)}
        else . end)),
     findings: ($kept | map(del(.keep, .dep)))}')

if [[ -n $out ]]; then
  printf '%s\n' "$result" > "$out"
else
  printf '%s\n' "$result"
fi
