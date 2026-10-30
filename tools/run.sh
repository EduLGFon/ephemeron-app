#!/usr/bin/env bash
# Run Flutter with OAuth credentials read from env/*.json (no Python).
# Usage: tools/run.sh [platform] [flutter args...]
#   platform: android | ios | linux | macos | web | windows (optional; auto-detected)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"

PLATFORM=""
if [[ $# -gt 0 ]]; then
  case "$1" in
    android|ios|linux|macos|web|windows) PLATFORM="$1"; shift ;;
  esac
fi

if [[ -z "$PLATFORM" ]]; then
  args=("$@")
  i=0
  while (( i < ${#args[@]} )); do
    a="${args[$i]}"
    if [[ "$a" == "-d" || "$a" == "--device-id" ]]; then
      dev="${args[$((i+1))]:-}"
      case "$dev" in
        chrome|web-server|web) PLATFORM=web ;;
        linux) PLATFORM=linux ;;
        windows) PLATFORM=windows ;;
        android) PLATFORM=android ;;
        macos) PLATFORM=macos ;;
        ios) PLATFORM=ios ;;
      esac
    fi
    i=$((i+1))
  done
fi

if [[ -z "$PLATFORM" ]]; then
  case "$(uname -s)" in
    Linux) PLATFORM=linux ;;
    Darwin) PLATFORM=macos ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
    *) PLATFORM=linux ;;
  esac
fi

mkdir -p "$ROOT/log" /tmp/opencode

DEFINES_FILE="$(mktemp /tmp/opencode/dart_defines.XXXXXX.json)"
trap 'rm -f "$DEFINES_FILE"' EXIT

jq -n \
  --arg android "$(jq -r '.installed.client_id' "$ROOT/env/android.json")" \
  --arg web "$(jq -r '.web.client_id' "$ROOT/env/web.json")" \
  --arg web_secret "$(jq -r '.web.client_secret // ""' "$ROOT/env/web.json")" \
  --arg linux "$(jq -r '.installed.client_id' "$ROOT/env/linux.json")" \
  --arg linux_secret "$(jq -r '.installed.client_secret // ""' "$ROOT/env/linux.json")" \
  '{
    GOOGLE_ANDROID_CLIENT_ID: $android,
    GOOGLE_WEB_CLIENT_ID: $web,
    GOOGLE_WEB_CLIENT_SECRET: $web_secret,
    GOOGLE_LINUX_CLIENT_ID: $linux,
    GOOGLE_LINUX_CLIENT_SECRET: $linux_secret
  }' > "$DEFINES_FILE"

LOG_FILE="$ROOT/log/$PLATFORM"

flutter run \
  --dart-define-from-file="$DEFINES_FILE" \
  "$@" 2>&1 | tee "$LOG_FILE"
