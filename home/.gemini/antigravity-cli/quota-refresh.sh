#!/bin/bash
set -euo pipefail

# ─── Configuration & Directories ─────────────────────────────────────────────
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/antigravity"
CACHE_FILE="${CACHE_DIR}/quota_cache.json"
LOG_FILE="${CACHE_DIR}/quota_refresh.log"
LOCK_FILE="${CACHE_DIR}/quota_cache.lock"

mkdir -p "$CACHE_DIR" 2>/dev/null || true

# ─── Error Logging Helper ───────────────────────────────────────────────────
log_err() {
  local msg="$1"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  echo "[${ts}] [ERROR] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() {
  local msg="$1"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)
  echo "[${ts}] [INFO] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}

# ─── Non-Blocking Process Lock (flock or mkdir fallback) ────────────────────
exec 200>"$LOCK_FILE" 2>/dev/null || true
if command -v flock &>/dev/null; then
  if ! flock -n 200 2>/dev/null; then
    exit 0
  fi
fi

# ─── 1. Discover Process & CSRF Token ────────────────────────────────────────
PS_LINE=$(ps aux 2>/dev/null | grep -E 'language_server.*--csrf_token' | grep -v grep | head -n 1 || true)

if [ -z "$PS_LINE" ]; then
  # Try matching agy binary directly if language_server isn't running
  PS_LINE=$(ps aux 2>/dev/null | grep -E '(^|\s)(/[^/]+/)*agy(\s|$)' | grep -v grep | head -n 1 || true)
fi

if [ -z "$PS_LINE" ]; then
  log_err "No running language_server or agy process found in ps aux"
  exit 1
fi

PID=$(echo "$PS_LINE" | awk '{print $2}')
CSRF_TOKEN=""
if [[ "$PS_LINE" =~ --csrf_token[[:space:]]+([a-zA-Z0-9-]+) ]]; then
  CSRF_TOKEN="${BASH_REMATCH[1]}"
fi

if [ -z "$PID" ] || ! [[ "$PID" =~ ^[0-9]+$ ]]; then
  log_err "Failed to extract valid PID from process line: $PS_LINE"
  exit 1
fi

# ─── 2. Discover Listening TCP Ports ──────────────────────────────────────────
PORTS=()
if command -v lsof &>/dev/null; then
  LSOF_OUT=$(lsof -nP -iTCP -a -p "$PID" 2>/dev/null || true)
  while read -r p; do
    [ -n "$p" ] && PORTS+=("$p")
  done <<< "$(echo "$LSOF_OUT" | grep LISTEN | grep -oE '(127\.0\.0\.1|localhost):[0-9]+' | cut -d: -f2 | sort -u || true)"
fi

if [ "${#PORTS[@]}" -eq 0 ] && command -v ss &>/dev/null; then
  SS_OUT=$(ss -tlnp 2>/dev/null | grep "pid=${PID}" || true)
  while read -r p; do
    [ -n "$p" ] && PORTS+=("$p")
  done <<< "$(echo "$SS_OUT" | grep -oE '127\.0\.0\.1:[0-9]+' | cut -d: -f2 | sort -u || true)"
fi

if [ "${#PORTS[@]}" -eq 0 ]; then
  log_err "No listening TCP port found for PID $PID (lsof/ss yielded empty port)"
  exit 1
fi

# ─── 3. Query Local Language Server RPC ──────────────────────────────────────
HEADERS=(
  -H "Content-Type: application/json"
  -H "Connect-Protocol-Version: 1"
)
if [ -n "$CSRF_TOKEN" ]; then
  HEADERS+=(-H "X-Codeium-Csrf-Token: ${CSRF_TOKEN}")
fi

RESPONSE=""
if command -v curl &>/dev/null; then
  for PORT in "${PORTS[@]}"; do
    # Try HTTPS first (with -k for self-signed cert), then HTTP
    RESPONSE=$(curl -k -s -m 3 -X POST "${HEADERS[@]}" -d '{}' "https://127.0.0.1:${PORT}/exa.language_server_pb.LanguageServerService/GetUserStatus" 2>/dev/null || true)
    if [ -n "$RESPONSE" ] && [[ "$RESPONSE" =~ userStatus ]]; then
      break
    fi

    RESPONSE=$(curl -s -m 3 -X POST "${HEADERS[@]}" -d '{}' "http://127.0.0.1:${PORT}/exa.language_server_pb.LanguageServerService/GetUserStatus" 2>/dev/null || true)
    if [ -n "$RESPONSE" ] && [[ "$RESPONSE" =~ userStatus ]]; then
      break
    fi
  done
fi

if [ -z "$RESPONSE" ] || ! [[ "$RESPONSE" =~ userStatus ]]; then
  log_err "GetUserStatus query across ports (${PORTS[*]}) failed or timed out"
  exit 1
fi

# ─── 4. Parse & Atomically Write Cache ───────────────────────────────────────
if ! command -v jq &>/dev/null; then
  log_err "jq is required to parse quota RPC response"
  exit 1
fi

PARSED_CACHE=$(echo "$RESPONSE" | jq '{
  timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  models: (
    [.userStatus.cascadeModelConfigData.clientModelConfigs[]? | select(.label != null and .quotaInfo != null) | {
      key: .label,
      value: {
        remainingFraction: (.quotaInfo.remainingFraction // (if .quotaInfo.resetTime != null and .quotaInfo.resetTime != "" then 0.0 else 1.0 end)),
        resetTime: (.quotaInfo.resetTime // "")
      }
    }] | from_entries
  )
}' 2>/dev/null || true)

if [ -z "$PARSED_CACHE" ] || [ "$PARSED_CACHE" = "null" ]; then
  log_err "Failed to parse malformed GetUserStatus JSON response"
  exit 1
fi

TMP_FILE="${CACHE_FILE}.tmp.$$"
(umask 077; echo "$PARSED_CACHE" > "$TMP_FILE") 2>/dev/null || true

if [ -s "$TMP_FILE" ]; then
  mv -f "$TMP_FILE" "$CACHE_FILE"
  log_info "Successfully updated quota cache at ${CACHE_FILE}"
else
  rm -f "$TMP_FILE" 2>/dev/null || true
  log_err "Failed to write temporary quota cache file"
  exit 1
fi
