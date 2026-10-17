# Walkable dev tasks. Run `just` (or `just --list`) to see everything.

flutter := "fvm flutter"
emulator := "Walkable_Phone"

# Build-time secrets (CARTO_API_KEY), written by `just carto-key`. Dev runs use
# it when present; without it the map tiles show CARTO's "API key required"
# watermark. Release builds refuse to run without it.
defines_file := "dart_defines.local.json"
defines := if path_exists(defines_file) == "true" { "--dart-define-from-file=" + defines_file } else { "" }

# Show the available recipes.
default:
    @just --list

# Fetch/refresh Dart & Flutter dependencies.
deps:
    {{flutter}} pub get

# Build and launch the app. Optionally target a device:
#   just run                 # auto-select a connected device
#   just run emulator-5554   # a running emulator by id
run device="":
    {{flutter}} run {{defines}} {{ if device == "" { "" } else { "-d " + device } }}

# Boot the phone emulator (if needed), then build and launch on it.
launch:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! {{flutter}} devices | grep -qi emulator; then
        echo "Booting {{emulator}}…"
        {{flutter}} emulators --launch {{emulator}}
        # Wait for the emulator to register as a device.
        for _ in $(seq 1 60); do
            {{flutter}} devices | grep -qi emulator && break
            sleep 2
        done
    fi
    {{flutter}} run {{defines}}

# Static analysis.
analyze:
    {{flutter}} analyze

# Run the test suite.
test:
    {{flutter}} test

# Run the integration tests on an emulator (installs the app, grants its
# permissions and feeds a GPS fix first). Defaults to emulator-5554.
integration device="emulator-5554":
    tool/integration_test.sh {{device}}

# Format all Dart sources.
fmt:
    fvm dart format lib test

# Build a release APK (sideloadable), with the CARTO key.
apk: _require-defines
    {{flutter}} build apk --release --dart-define-from-file={{defines_file}}

# Build a release App Bundle (.aab) for the Play Store, with the CARTO key.
bundle: _require-defines
    {{flutter}} build appbundle --release --dart-define-from-file={{defines_file}}

# Get the CARTO basemaps API key and store it (GitHub secret CARTO_API_KEY +
# the gitignored dart_defines.local.json here and in the main checkout).
carto-key:
    tool/carto_key.sh

[private]
_require-defines:
    @test -f {{defines_file}} || { echo "missing {{defines_file}}: run 'just carto-key' first (release maps would be blank)"; exit 1; }

# Regenerate Play Store screenshots (light + dark). Optionally one device:
#   just screenshots             # phone + 7" + 10"
#   just screenshots phone
screenshots device="":
    tool/screenshots.sh {{device}}

# Record the Play Store walk-recording walkthrough video (Aarhus). Boots an
# emulator, screen-records the in-app walk, and writes an MP4 to upload to
# YouTube for the Location-permissions "Video instructions" field.
#   just walkthrough                       # → build/walkthrough.mp4
#   just walkthrough docs/walkthrough.mp4
walkthrough out="":
    tool/walkthrough_video.sh {{out}}

# Remove build artifacts.
clean:
    {{flutter}} clean

# One-time setup for tag-triggered Play Store releases: a wizard that uploads
# the signing keystore + key.properties and walks you through creating the
# Play service-account key, storing all three as GitHub Actions secrets.
release-secrets:
    tool/release_secrets.sh
