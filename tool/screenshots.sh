#!/usr/bin/env bash
# Generate Play Store screenshots, repeatably.
#
# For each target device it: creates a fixed AVD if missing, boots it clean
# (wiped, no snapshot, animations off), runs the screenshot integration test,
# saves the PNGs, and shuts the emulator down. Same AVD + same seeded data +
# same test = the same screenshots every run (only the network map tiles can
# vary, and those are stable).
#
# Usage:
#   tool/screenshots.sh              # all devices
#   tool/screenshots.sh phone        # one device by key
#
# Output: docs/screenshots/<device>/{01-home,02-recording,03-detail,04-history}.png
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# ── Config ────────────────────────────────────────────────────────────────────
SDK="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"
AVDMANAGER="$SDK/cmdline-tools/latest/bin/avdmanager"
SYS_IMAGE="system-images;android-34;google_apis;x86_64"
PORT=5560
SERIAL="emulator-$PORT"

# device-key | AVD name | device profile (avdmanager -d) | output subdir
DEVICES=(
  "phone|Walkable_Phone|pixel_2|phone"
  "tablet|Walkable_Tablet7|Nexus 7 2013|tablet_7inch"
)

FLUTTER="fvm flutter"

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { printf '\033[1;32m▸ %s\033[0m\n' "$*"; }

ensure_avd() {
  local name="$1" profile="$2"
  if "$EMULATOR" -list-avds | grep -qx "$name"; then
    log "AVD '$name' exists"
  else
    log "Creating AVD '$name' ($profile)"
    echo "no" | "$AVDMANAGER" create avd -n "$name" -k "$SYS_IMAGE" -d "$profile"
  fi
}

boot() {
  local name="$1"
  log "Booting $name (clean)…"
  "$EMULATOR" -avd "$name" -port "$PORT" \
    -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data \
    -gpu swiftshader_indirect >/tmp/walkable-emulator.log 2>&1 &
  EMU_PID=$!

  "$ADB" -s "$SERIAL" wait-for-device
  log "Waiting for boot to complete…"
  local tries=0
  until [ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 2
    tries=$((tries + 1))
    if [ "$tries" -gt 150 ]; then
      echo "Emulator failed to boot within 5 min (see /tmp/walkable-emulator.log)" >&2
      exit 1
    fi
  done
  # Kill animations for crisp, deterministic frames.
  "$ADB" -s "$SERIAL" shell settings put global window_animation_scale 0
  "$ADB" -s "$SERIAL" shell settings put global transition_animation_scale 0
  "$ADB" -s "$SERIAL" shell settings put global animator_duration_scale 0
  sleep 2
}

shutdown() {
  if [ -n "${EMU_PID:-}" ] && kill -0 "$EMU_PID" 2>/dev/null; then
    log "Shutting emulator down…"
    "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
    wait "$EMU_PID" 2>/dev/null || true
    EMU_PID=""
  fi
}
trap shutdown EXIT

capture() {
  local out="$1"
  rm -rf "$out" && mkdir -p "$out"
  log "Driving app → $out"
  # --profile removes the debug banner and renders release-like, with no
  # production code changes (the VM service the driver needs is still present).
  SCREENSHOT_OUT="$out" $FLUTTER drive \
    --profile \
    --driver=test_driver/screenshot_driver.dart \
    --target=integration_test/screenshot_test.dart \
    -d "$SERIAL"
}

# ── Run ───────────────────────────────────────────────────────────────────────
"$ADB" start-server >/dev/null 2>&1 || true
FILTER="${1:-}"

for entry in "${DEVICES[@]}"; do
  IFS='|' read -r key name profile subdir <<<"$entry"
  [ -n "$FILTER" ] && [ "$FILTER" != "$key" ] && continue

  log "=== $key ==="
  ensure_avd "$name" "$profile"
  boot "$name"
  capture "$ROOT/docs/screenshots/$subdir"
  shutdown
done

log "Done. Screenshots in docs/screenshots/"
