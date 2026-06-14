# Walkable dev tasks. Run `just` (or `just --list`) to see everything.

flutter := "fvm flutter"
emulator := "Walkable_Phone"

# Show the available recipes.
default:
    @just --list

# Fetch/refresh Dart & Flutter dependencies.
deps:
    {{flutter}} pub get

# Build and launch the app. Optionally target a device:
#   just run                 # auto-select a connected device
#   just run linux           # desktop
#   just run emulator-5554   # a running emulator by id
run device="":
    {{flutter}} run {{ if device == "" { "" } else { "-d " + device } }}

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
    {{flutter}} run

# Static analysis.
analyze:
    {{flutter}} analyze

# Run the test suite.
test:
    {{flutter}} test

# Format all Dart sources.
fmt:
    fvm dart format lib test

# Build a release APK (sideloadable).
apk:
    {{flutter}} build apk --release

# Build a release App Bundle (.aab) for the Play Store.
bundle:
    {{flutter}} build appbundle --release

# Regenerate Play Store screenshots (light + dark). Optionally one device:
#   just screenshots             # phone + 7" + 10"
#   just screenshots phone
screenshots device="":
    tool/screenshots.sh {{device}}

# Remove build artifacts.
clean:
    {{flutter}} clean
