# Store screenshots

Repeatable Google Play screenshots for phone and 7" tablet, generated from the
real app driven with seeded data — so every run produces the same images.

```
tool/screenshots.sh            # phone + 7" tablet
tool/screenshots.sh phone      # just one (phone | tablet)
```

Output:

| Device | Folder | Size | Play category |
|--------|--------|------|---------------|
| Phone (Pixel 2) | `phone/` | 1080×1857 | Phone screenshots |
| 7" tablet (Nexus 7 2013) | `tablet_7inch/` | 1200×1800 | 7-inch tablet screenshots |

Each folder has: `01-home`, `02-recording`, `03-detail`, `04-history`.

## How it works

- `integration_test/screenshot_test.dart` — launches the app with an in-memory
  database seeded with fixed walks and a faked GPS feed, navigates each screen
  and captures it. All pixel-affecting inputs (data, route, location) are fixed.
- `test_driver/screenshot_driver.dart` — writes the captured PNGs to
  `$SCREENSHOT_OUT`.
- `tool/screenshots.sh` — creates fixed AVDs if missing, boots each clean
  (wiped, no snapshot, animations off), runs the test in `--profile` (no debug
  banner, no production code changes), and saves the PNGs.

## Determinism notes

- The only non-fixed input is the **map tiles**, fetched from OpenStreetMap /
  CartoDB. They're stable, but require network access during capture.
- The **recording** screen shows a genuine just-started walk (`00:03`, 0.00 km).
  `WalkRecorder` reads `DateTime.now()` for elapsed time and we deliberately do
  not modify production code to fake it, so a rich in-progress shot isn't
  generated here.

## Requirements

FVM Flutter, Android SDK with `emulator` + `avdmanager`, the
`system-images;android-34;google_apis;x86_64` image, and KVM for acceleration.
