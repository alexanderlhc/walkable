#!/usr/bin/env bash
# Run the integration tests (the ones with assertions; the screenshot and
# walkthrough recorders are run by their own scripts) on an Android emulator.
#
#   tool/integration_test.sh [device-id]    # default emulator-5554
#
# The LocationService test uses the real GPS plugin, which nothing can tap
# through an OS permission dialog. So this script installs the app first,
# grants its permissions with adb, feeds the emulator a GPS fix every second,
# and runs `flutter test --no-uninstall`: the test build replaces the app with
# `adb install -r`, which keeps the grants.
#
# Env: FLUTTER overrides the flutter command (CI has no fvm).
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER=${FLUTTER:-fvm flutter}
DEVICE=${1:-emulator-5554}
PKG=dk.alexanderlhc.walkable
# Must match _fix in integration_test/location_service_integration_test.dart.
FIX_LAT=56.16928
FIX_LNG=10.20034

defines=()
[[ -f dart_defines.local.json ]] && defines=(--dart-define-from-file=dart_defines.local.json)

adb_() { adb -s "$DEVICE" "$@"; }

# Build only the device's ABI: smaller APK, faster build.
case "$(adb_ shell getprop ro.product.cpu.abi | tr -d '\r')" in
  x86_64) platform=android-x64 ;;
  arm64-v8a) platform=android-arm64 ;;
  *) platform=android-arm ;;
esac

$FLUTTER build apk --debug --target-platform "$platform" "${defines[@]}"
adb_ install -r -t build/app/outputs/flutter-apk/app-debug.apk

adb_ shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION
adb_ shell pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION
# Runtime permission only on Android 13+; older versions grant it at install.
adb_ shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
adb_ shell dumpsys deviceidle whitelist "+$PKG" >/dev/null
adb_ shell cmd location set-location-enabled true 2>/dev/null || true

# Keep a fix coming so the first one isn't missed whenever the test subscribes.
(while true; do adb_ emu geo fix "$FIX_LNG" "$FIX_LAT" >/dev/null 2>&1 || true; sleep 1; done) &
feeder=$!
trap 'kill $feeder 2>/dev/null' EXIT

$FLUTTER test --no-uninstall -d "$DEVICE" "${defines[@]}" \
  integration_test/happy_path_test.dart \
  integration_test/location_service_integration_test.dart
