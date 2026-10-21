#!/usr/bin/env bash
# Check that a model id is actually offered by agy, and when it is not,
# recommend one that is. Never substitutes silently: the caller decides.
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage: resolve-model.sh [--models-file FILE] [--refresh] [--json] REQUEST

REQUEST is one of:
  an exact model id          gemini-3.8-flash-high
  a display name             "Gemini 3.8 Flash (High)"
  auto:<family>-<tier>[-<effort>]
                             auto:gemini-flash-high  (newest matching model)

options:
  --models-file FILE  read "id<TAB>display" rows from FILE instead of agy
                      (tests); the cache is neither read nor written
  --refresh           bypass the cache and re-run `agy models`
  --json              print {requested,available,resolved,recommended,display,reason}

environment:
  MODEL_CHECK_AGY  agy binary to run (default: agy)
  MODEL_CHECK_TTL  cache lifetime in seconds (default: 21600)

exit codes:
  0  available; stdout is the model id (for auto: the chosen id)
  3  not available; stdout is the recommended id, stderr explains
  4  could not list models (agy missing, failed, or empty list)
  1  usage error
EOF
}

die() {
	echo "model-check: $*" >&2
	exit 1
}

models_file=''
refresh=0
json=0
request=''

while [ $# -gt 0 ]; do
	case "$1" in
	--models-file) models_file=${2:?--models-file needs a value}; shift 2 ;;
	--refresh) refresh=1; shift ;;
	--json) json=1; shift ;;
	-h | --help) usage; exit 0 ;;
	-*) printf 'unknown argument: %s\n\n' "$1" >&2; usage; exit 1 ;;
	*)
		[ -z "$request" ] || { printf 'only one REQUEST allowed\n\n' >&2; usage; exit 1; }
		request=$1
		shift
		;;
	esac
done
[ -n "$request" ] || { usage; exit 1; }

# --- model list -------------------------------------------------------------

# fail_listing MSG — exit 4: availability could not be determined, which is
# different from "unavailable" and must not look like it.
fail_listing() {
	echo "model-check: cannot list models: $*" >&2
	exit 4
}

# Keep only well-formed "id<TAB>display" rows. agy prints a progress line
# ("Fetching available models...") first; it has no tab, so it drops out here.
filter_rows() {
	local id disp
	while IFS=$'\t' read -r id disp || [ -n "$id" ]; do
		id=${id%$'\r'}
		disp=${disp%$'\r'}
		if [ -n "$id" ] && [ -n "$disp" ]; then
			printf '%s\t%s\n' "$id" "$disp"
		fi
	done
}

file_mtime() {
	stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

load_rows() {
	if [ -n "$models_file" ]; then
		[ -r "$models_file" ] || fail_listing "models file not readable: $models_file"
		filter_rows <"$models_file"
		return
	fi

	local cache ttl now agy_bin raw
	cache=${XDG_CACHE_HOME:-$HOME/.cache}/model-check/agy-models.tsv
	ttl=${MODEL_CHECK_TTL:-21600}
	now=$(date +%s)
	if [ "$refresh" -eq 0 ] && [ -s "$cache" ] && [ $((now - $(file_mtime "$cache"))) -lt "$ttl" ]; then
		cat "$cache"
		return
	fi

	agy_bin=${MODEL_CHECK_AGY:-agy}
	command -v "$agy_bin" >/dev/null 2>&1 || fail_listing "$agy_bin not found"
	if command -v timeout >/dev/null 2>&1; then
		raw=$(timeout 60 "$agy_bin" models 2>/dev/null) || fail_listing "'$agy_bin models' failed"
	else
		raw=$("$agy_bin" models 2>/dev/null) || fail_listing "'$agy_bin models' failed"
	fi
	raw=$(filter_rows <<<"$raw")
	[ -n "$raw" ] || fail_listing "'$agy_bin models' returned no models"

	# Cache only a good listing, and atomically: a half-written file would be
	# served as truth for the next six hours.
	if mkdir -p "$(dirname "$cache")" 2>/dev/null; then
		if printf '%s\n' "$raw" >"$cache.$$"; then
			mv "$cache.$$" "$cache" || rm -f "$cache.$$"
		fi
	fi
	printf '%s\n' "$raw"
}

rows=$(load_rows)
[ -n "$rows" ] || fail_listing "no models in the listing"

ids=()
disps=()
while IFS=$'\t' read -r id disp; do
	ids+=("$id")
	disps+=("$disp")
done <<<"$rows"

# --- parsing ----------------------------------------------------------------

# normalize STR — lowercase, spaces to hyphens, parens dropped, so a display
# name ("Gemini 3.8 Flash (High)") compares equal to its id.
normalize() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -d '()' | tr -s '-'
}

# parse_attrs NORMALIZED — sets P_FAMILY P_TIER P_EFFORT P_VER. Unknown words
# (a codename like "argon") are ignored rather than guessed at. P_VER packs up
# to three numeric components (4-6 and 4.6 both read as 4.6) into one integer
# so "newest" is a plain comparison.
parse_attrs() {
	local tok part
	local -a toks nums=() parts
	P_FAMILY='' P_TIER='' P_EFFORT='' P_VER=0
	IFS='-' read -ra toks <<<"$1"
	for tok in "${toks[@]}"; do
		case $tok in
		gemini | claude | gpt) [ -n "$P_FAMILY" ] || P_FAMILY=$tok ;;
		opus | sonnet | haiku)
			P_TIER=$tok
			[ -n "$P_FAMILY" ] || P_FAMILY=claude
			;;
		flash) P_TIER=flash ;;
		lite) [ "$P_TIER" != flash ] || P_TIER=flash-lite ;;
		pro) P_TIER=pro ;;
		oss) P_TIER=oss ;;
		high | medium | low | thinking) P_EFFORT=$tok ;;
		*)
			if [[ $tok =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
				IFS=. read -ra parts <<<"$tok"
				for part in "${parts[@]}"; do nums+=("$part"); done
			fi
			;;
		esac
	done
	P_VER=$((10#${nums[0]:-0} * 1000000 + 10#${nums[1]:-0} * 1000 + 10#${nums[2]:-0}))
}

jstr() {
	local s=${1//\\/\\\\}
	s=${s//\"/\\\"}
	printf '"%s"' "$s"
}

# emit_json AVAILABLE RESOLVED RECOMMENDED DISPLAY REASON
emit_json() {
	local avail=$1 resolved=$2 rec=$3 disp=$4 reason=$5 r c d
	r=null c=null d=null
	[ -z "$resolved" ] || r=$(jstr "$resolved")
	[ -z "$rec" ] || c=$(jstr "$rec")
	[ -z "$disp" ] || d=$(jstr "$disp")
	printf '{"requested":%s,"available":%s,"resolved":%s,"recommended":%s,"display":%s,"reason":%s}\n' \
		"$(jstr "$request")" "$avail" "$r" "$c" "$d" "$(jstr "$reason")"
}

# --- resolution -------------------------------------------------------------

is_auto=0
want=$request
if [[ $request == auto:* ]]; then
	is_auto=1
	want=${request#auto:}
fi
nwant=$(normalize "$want")
parse_attrs "$nwant"
want_family=$P_FAMILY want_tier=$P_TIER want_effort=$P_EFFORT

if [ "$is_auto" -eq 0 ]; then
	# Exact id, or a display name / id after normalisation.
	for i in "${!ids[@]}"; do
		if [ "${ids[$i]}" = "$request" ] || [ "$(normalize "${ids[$i]}")" = "$nwant" ] \
			|| [ "$(normalize "${disps[$i]}")" = "$nwant" ]; then
			if [ "$json" -eq 1 ]; then
				emit_json true "${ids[$i]}" '' "${disps[$i]}" 'listed by agy'
			else
				printf '%s\n' "${ids[$i]}"
			fi
			exit 0
		fi
	done
else
	[ -n "$want_family" ] || die "cannot read a model family from '$request' (want auto:<family>-<tier>[-<effort>])"
	# auto: the newest model matching every part that was asked for. A missing
	# tier or effort is NOT filled in with a different one — that would be a
	# silent substitution; it falls through to "unavailable" below.
	best='' best_ver=-1
	for i in "${!ids[@]}"; do
		parse_attrs "$(normalize "${ids[$i]}")"
		[ "$P_FAMILY" = "$want_family" ] || continue
		[ -z "$want_tier" ] || [ "$P_TIER" = "$want_tier" ] || continue
		[ -z "$want_effort" ] || [ "$P_EFFORT" = "$want_effort" ] || continue
		# Strictly newer wins; equal versions keep the first id in sort order.
		if [ "$P_VER" -gt "$best_ver" ] || { [ "$P_VER" -eq "$best_ver" ] && [[ ${ids[$i]} < $best ]]; }; then
			best=${ids[$i]}
			best_ver=$P_VER
			best_disp=${disps[$i]}
		fi
	done
	if [ -n "$best" ]; then
		if [ "$json" -eq 1 ]; then
			emit_json true "$best" '' "$best_disp" "newest model matching $want"
		else
			printf '%s\n' "$best"
		fi
		exit 0
	fi
fi

# Unavailable: recommend the closest model that exists. Same family dominates,
# then tier, then effort; ties go to the newest version, then the smaller id,
# so the answer is deterministic.
rec='' rec_disp='' rec_score=-1 rec_ver=-1
for i in "${!ids[@]}"; do
	parse_attrs "$(normalize "${ids[$i]}")"
	score=0
	[ -z "$want_family" ] || [ "$P_FAMILY" != "$want_family" ] || score=$((score + 1000))
	[ -z "$want_tier" ] || [ "$P_TIER" != "$want_tier" ] || score=$((score + 100))
	[ -z "$want_effort" ] || [ "$P_EFFORT" != "$want_effort" ] || score=$((score + 10))
	if [ "$score" -gt "$rec_score" ] \
		|| { [ "$score" -eq "$rec_score" ] && [ "$P_VER" -gt "$rec_ver" ]; } \
		|| { [ "$score" -eq "$rec_score" ] && [ "$P_VER" -eq "$rec_ver" ] && [[ ${ids[$i]} < $rec ]]; }; then
		rec=${ids[$i]}
		rec_disp=${disps[$i]}
		rec_score=$score
		rec_ver=$P_VER
	fi
done

avail_list=$(printf '%s, ' "${ids[@]}")
avail_list=${avail_list%, }
echo "model-check: '$request' is not available on agy. Recommended: $rec ($rec_disp). Available: $avail_list" >&2

if [ "$json" -eq 1 ]; then
	emit_json false '' "$rec" "$rec_disp" "not listed by agy; closest by family, tier and effort"
else
	printf '%s\n' "$rec"
fi
exit 3
