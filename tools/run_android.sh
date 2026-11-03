#!/usr/bin/env bash
# Fast Android dev loop: reuse one debug APK so `flutter run` skips Gradle.
#
# `flutter run` builds through Gradle on every launch. On a low-core machine
# that is most of the startup time. Dart and asset changes do not need a new
# APK: the tool regenerates the kernel and asset bundle and pushes them over
# devfs. The APK is rebuilt only when native inputs change (Android sources,
# Gradle files, dependencies). See docs/BUILD_PERFORMANCE.md.
#
# Usage:
#   tools/run_android.sh                     # arm64, device chosen by flutter
#   tools/run_android.sh -d RQCXA02094D      # extra args pass to flutter run
#   tools/run_android.sh --rebuild           # force a new debug APK
#
# Set ABI=arm or ABI=x64 for other targets (default arm64).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"

ABI="${ABI:-arm64}"
APK="build/app/outputs/flutter-apk/app-debug.apk"
ABI_STAMP="build/app/outputs/flutter-apk/.run_android_abi"

args=()
REBUILD=0
for arg in "$@"; do
  if [[ "$arg" == "--rebuild" ]]; then
    REBUILD=1
  else
    args+=("$arg")
  fi
done

for arg in ${args[@]+"${args[@]}"}; do
  case "$arg" in
    --profile|--release)
      echo "run_android.sh runs a debug APK; use 'flutter run' for $arg." >&2
      exit 1
      ;;
  esac
done

# Native inputs: a change here can alter the APK, so rebuild it. Dart, assets
# and fonts are synced by devfs and do not appear in this list.
inputs=(
  pubspec.yaml pubspec.lock
  android/build.gradle.kts android/settings.gradle.kts
  android/gradle.properties android/app/build.gradle.kts
  android/app/src
)

need_build=$REBUILD
if [[ ! -f "$APK" ]] || [[ ! -f "$ABI_STAMP" ]] || [[ "$(cat "$ABI_STAMP")" != "$ABI" ]]; then
  need_build=1
elif find "${inputs[@]}" -newer "$APK" -print -quit 2>/dev/null | grep -q .; then
  need_build=1
fi

if (( need_build )); then
  echo "Building debug APK for android-$ABI..." >&2
  flutter build apk --debug --target-platform "android-$ABI" >&2
  echo "$ABI" >"$ABI_STAMP"
fi

exec flutter run "--use-application-binary=$APK" ${args[@]+"${args[@]}"}
