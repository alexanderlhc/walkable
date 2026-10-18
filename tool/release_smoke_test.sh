#!/usr/bin/env bash
# Smoke-test a real release build on an Android emulator: build it the way a
# release is built (--release, so R8 and resource shrinking run), install it
# fresh, launch it, and wait for the app to log that its first frame is on
# screen. Fails if it never gets there or throws during startup.
#
#   tool/release_smoke_test.sh [device-id]    # default emulator-5554
#
# Debug builds skip R8, so only this catches release-only startup breakage:
# 0.5.1 hung on the splash screen because R8 renamed Kotlin classes that
# shared_preferences_android 2.5.0 calls through JNI (now kept in
# android/app/proguard-rules.pro). Its process stayed
# alive, so this waits for the line main() logs once the first frame is
# rasterized rather than for the process.
#
# Signing: without android/key.properties, build.gradle signs with the debug
# key.
#
# Env: FLUTTER overrides the flutter command (CI has no fvm).
#      CARTO_API_KEY is passed as a dart-define when dart_defines.local.json
#      is absent (CI); an empty key is fine.
#      SMOKE_TIMEOUT is how long to wait for the first frame (default 90 s).
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER=${FLUTTER:-fvm flutter}
DEVICE=${1:-emulator-5554}
TIMEOUT=${SMOKE_TIMEOUT:-90}
PKG=dk.alexanderlhc.walkable
# Must match the debugPrint at the end of main() in lib/main.dart.
READY='walkable: first frame rasterized'
# An uncaught Dart error (0.5.1's NoSuchMethodError in main()) or a Java crash.
ERRORS='Unhandled Exception|FATAL EXCEPTION'

defines=()
if [[ -f dart_defines.local.json ]]; then
  defines=(--dart-define-from-file=dart_defines.local.json)
elif [[ -n ${CARTO_API_KEY:-} ]]; then
  defines=(--dart-define=CARTO_API_KEY="$CARTO_API_KEY")
fi

adb_() { adb -s "$DEVICE" "$@"; }
# Blank out the CARTO key (it is in the map tile URLs) in logs we print.
redact() { sed -E 's/key=[^&[:space:]]*/key=REDACTED/g'; }

# Build only the device's ABI: smaller APK, faster build.
case "$(adb_ shell getprop ro.product.cpu.abi | tr -d '\r')" in
  x86_64) platform=android-x64 ;;
  arm64-v8a) platform=android-arm64 ;;
  *) platform=android-arm ;;
esac

$FLUTTER build apk --release --target-platform "$platform" "${defines[@]}"
# Fresh install, as a new user gets it (and no signature clash with a
# Play-signed copy). Uninstalled again afterwards, so the integration tests
# start clean and can install their debug build over nothing.
adb_ uninstall "$PKG" >/dev/null 2>&1 || true
adb_ install build/app/outputs/flutter-apk/app-release.apk
trap 'adb_ uninstall "$PKG" >/dev/null 2>&1 || true' EXIT

since=$(adb_ shell date +'%m-%d\ %H:%M:%S.000' | tr -d '\r')
activity=$(adb_ shell cmd package resolve-activity --brief "$PKG" | tr -d '\r' | tail -1)
# -W returns once the activity is launched, so the process exists.
adb_ shell am start -W -n "$activity" >/dev/null
pid=$(adb_ shell pidof "$PKG" | tr -d '\r' || true)
if [[ -z $pid ]]; then
  echo "release smoke test FAILED: the app did not start" >&2
  echo "--- logcat since launch (all processes) ---" >&2
  adb_ logcat -d -T "$since" | redact | tail -n 150 >&2
  exit 1
fi

# This process's logs (they outlive it).
app_log() { adb_ logcat -d -T "$since" --pid "$pid" | redact; }
alive() { adb_ shell "[ -d /proc/$pid ]"; }

fail() {
  echo "release smoke test FAILED: $1" >&2
  echo "--- logcat since launch ---" >&2
  app_log | tail -n 150 >&2
  exit 1
}

# Captured, not piped into grep -q: under pipefail an early-exiting grep
# can fail the pipeline.
reached_first_frame() {
  local log
  log=$(app_log)
  ! grep -qE "$ERRORS" <<<"$log" || fail "exception during startup"
  grep -qF "$READY" <<<"$log"
}

start=$SECONDS
until reached_first_frame; do
  alive || fail "the app died during startup"
  (( SECONDS - start < TIMEOUT )) || fail "no first frame within ${TIMEOUT}s (stuck on the splash screen?)"
  sleep 1
done
echo "first frame after $(( SECONDS - start ))s"

# Errors right after the first frame (the rest of startup) count too.
sleep 5
reached_first_frame
alive || fail "the app died after its first frame"
echo "release smoke test passed"
