#!/usr/bin/env bash
# Fast local release APK build.
#
# `flutter build apk` defaults to three ABIs (arm, arm64, x64). Flutter runs
# one AOT gen_snapshot per ABI in parallel, which thrashes CPU and disk on a
# low-core machine. This script builds one ABI by default (arm64, the ABI of
# every current Android phone).
#
# Usage:
#   tools/build_apk.sh [--dev] [arm64|arm|x64] [extra flutter build apk args...]
#
#   --dev  Skip R8/resource shrinking and icon tree-shaking. Produces a larger
#          unoptimized APK that is fine for local device testing, not release.
#
# Keep the implicit `flutter pub get`: it also regenerates
# GeneratedPluginRegistrant.java with the release plugin set. Passing --no-pub
# here leaves a debug registrant behind (it includes integration_test) and the
# release Java compile then fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"

DEV=0
if [[ "${1:-}" == "--dev" ]]; then
  DEV=1
  shift
fi

ABI=arm64
if [[ "${1:-}" =~ ^(arm|arm64|x64)$ ]]; then
  ABI="$1"
  shift
fi

args=(build apk --release --target-platform "android-$ABI")
if (( DEV )); then
  args+=(--no-tree-shake-icons --android-project-arg=shrink=false)
fi

exec flutter "${args[@]}" "$@"
