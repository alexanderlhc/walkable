#!/usr/bin/env bash
# Record the "Video instructions" walkthrough for the Play Store, repeatably.
#
# Boots the fixed phone AVD (clean), starts the app via `flutter drive` against
# integration_test/walkthrough_test.dart, screen-records the device while the
# walk-recording session plays out (Aarhus: START → live route → pause → resume
# → FINISH), then pulls an MP4 ready to upload to YouTube and link in the
# Play Console Location-permissions declaration.
#
# Usage:
#   tool/walkthrough_video.sh                 # default output build/walkthrough.mp4
#   tool/walkthrough_video.sh path/to/out.mp4
#
# Notes:
#   - GPS is faked in-app, so there are NO system permission dialogs to click —
#     the capture is deterministic.
#   - Screen recording starts only once the app is foreground, so the build/
#     install noise is kept out of the video.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

OUT="${1:-build/walkthrough.mp4}"
OUT="$(mkdir -p "$(dirname "$OUT")" && cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

# ── Config ────────────────────────────────────────────────────────────────────
SDK="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"
AVDMANAGER="$SDK/cmdline-tools/latest/bin/avdmanager"
SYS_IMAGE="system-images;android-34;google_apis;x86_64"
# A dedicated AVD (not the screenshots' Walkable_Phone) so this never collides
# with the screenshot tooling or an emulator you have open in Android Studio —
# booting two instances of the same AVD is fatal and corrupts the run.
AVD="Walkable_Video"
PROFILE="pixel_2"
PORT=5562
SERIAL="emulator-$PORT"
DEVICE_MP4="/sdcard/walkable-walkthrough.mp4"
APP_PKG="dk.alexanderlhc.walkable"

FLUTTER="fvm flutter"

log() { printf '\033[1;32m▸ %s\033[0m\n' "$*"; }

# ── Emulator lifecycle ────────────────────────────────────────────────────────
ensure_avd() {
  if "$EMULATOR" -list-avds | grep -qx "$AVD"; then
    log "AVD '$AVD' exists"
  else
    log "Creating AVD '$AVD' ($PROFILE)"
    echo "no" | "$AVDMANAGER" create avd -n "$AVD" -k "$SYS_IMAGE" -d "$PROFILE"
  fi
}

boot() {
  # Refuse to stomp on an emulator already on our port.
  if "$ADB" devices | grep -q "^$SERIAL"; then
    echo "An emulator is already running on $SERIAL. Close it and retry." >&2
    exit 1
  fi
  # Clear a stale lock left by a previously force-killed emulator on this AVD;
  # otherwise the launch dies with "Running multiple emulators with the same AVD".
  local avd_dir="${ANDROID_AVD_HOME:-$HOME/.android/avd}/$AVD.avd"
  rm -f "$avd_dir"/*.lock "$avd_dir"/hardware-qemu.ini.lock 2>/dev/null || true

  log "Booting $AVD (clean)…"
  "$EMULATOR" -avd "$AVD" -port "$PORT" \
    -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data \
    -gpu swiftshader_indirect >/tmp/walkable-walkthrough-emulator.log 2>&1 &
  EMU_PID=$!

  "$ADB" -s "$SERIAL" wait-for-device
  log "Waiting for boot to complete…"
  local tries=0
  until [ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 2
    tries=$((tries + 1))
    if [ "$tries" -gt 150 ]; then
      echo "Emulator failed to boot within 5 min (see /tmp/walkable-walkthrough-emulator.log)" >&2
      exit 1
    fi
  done
  # Leave UI animations ON — the page transitions read nicely in a video. Just
  # lock orientation to portrait.
  "$ADB" -s "$SERIAL" shell settings put system accelerometer_rotation 0
  sleep 2
}

shutdown() {
  [ -n "${REC_PID:-}" ] && kill "$REC_PID" 2>/dev/null || true
  if [ -n "${EMU_PID:-}" ] && kill -0 "$EMU_PID" 2>/dev/null; then
    log "Shutting emulator down…"
    "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
    wait "$EMU_PID" 2>/dev/null || true
  fi
}
trap shutdown EXIT

# Starts screen recording once the app is foreground, so the video doesn't open
# on the launcher/build noise. Runs in a subshell that waits for the resumed
# activity, then execs screenrecord; we keep its PID to stop it cleanly.
start_recording_when_app_foreground() {
  (
    for _ in $(seq 1 120); do
      if "$ADB" -s "$SERIAL" shell dumpsys activity activities 2>/dev/null \
        | grep -qiE "ResumedActivity.*$APP_PKG"; then
        break
      fi
      sleep 0.5
    done
    # 1080x1920 @ 8 Mbps, capped at 180s (the walkthrough is ~90s).
    exec "$ADB" -s "$SERIAL" shell screenrecord \
      --bit-rate 8000000 --size 1080x1920 --time-limit 180 "$DEVICE_MP4"
  ) &
  REC_PID=$!
}

stop_recording() {
  log "Stopping screen recording…"
  # SIGINT the device-side process so it finalises the MP4 moov atom.
  "$ADB" -s "$SERIAL" shell pkill -INT screenrecord >/dev/null 2>&1 || true
  wait "$REC_PID" 2>/dev/null || true
  REC_PID=""
  sleep 2 # let the file flush to /sdcard
}

# ── Run ───────────────────────────────────────────────────────────────────────
"$ADB" start-server >/dev/null 2>&1 || true
ensure_avd
boot

log "Clearing any old recording on device…"
"$ADB" -s "$SERIAL" shell rm -f "$DEVICE_MP4" >/dev/null 2>&1 || true

start_recording_when_app_foreground

log "Driving the walkthrough…"
# --profile renders release-like (no debug banner) while keeping the VM service
# the driver needs.
$FLUTTER drive \
  --profile \
  --driver=test_driver/walkthrough_driver.dart \
  --target=integration_test/walkthrough_test.dart \
  -d "$SERIAL"

stop_recording

log "Pulling video → $OUT"
"$ADB" -s "$SERIAL" pull "$DEVICE_MP4" "$OUT"

log "Done. Upload $OUT to YouTube (Unlisted is fine) and paste the link into"
log "the Play Console Location-permissions declaration → Video instructions."
