# Releasing

Releases are built and uploaded by `.github/workflows/release.yml`. Nothing is
committed for a release:

- **versionName** comes from the tag: `v0.5.1` → `0.5.1`.
- **versionCode** is the highest code on any Play track (internal, alpha,
  beta, production) + 1. The `+N` in `pubspec.yaml` is only the floor, so
  stop bumping it.

## Before a release: the smoke test

Debug builds skip R8, so a release build can break where every test passes:
0.5.1 hung on the splash screen because R8 stripped methods that
`shared_preferences_android` 2.5.0 calls through JNI. CI's `integration` job
therefore also runs `tool/release_smoke_test.sh` on every PR: it builds a
`--release` APK (R8 and resource shrinking on, the CARTO key when the secret
is available), installs it fresh on the emulator, launches it, and fails
unless the app logs `walkable: first frame rasterized` (from `main()`) within
90 s without an uncaught exception or crash. Run it locally with
`just smoke [device]`.

Without `android/key.properties` (CI, a fresh clone) release builds are signed
with the debug key so they can be smoke-tested. `fastlane deploy` refuses to
build without `key.properties` and refuses to upload a bundle signed with the
debug key.

## Cut a release

Production gets the exact build you tested on internal: it is promoted on
Play, never rebuilt.

1. **Tag** the release. The push builds the tag and uploads it to the
   internal track:

   ```sh
   git checkout main && git pull
   git tag v0.5.1
   git push origin v0.5.1
   ```

2. **Test** the internal build on a phone (Play Console → Test and release →
   Testing → Internal testing). Note its version code if more than one build
   might be on internal.

3. **Promote** it: GitHub → Actions → Release → **Run workflow**, with
   **action:** `promote`. Leave **version code** empty to take the latest
   build on internal. **Rollout** is the percentage of production users;
   below 100 it is a staged rollout. To widen or complete it, run promote
   again with the **same version code** and a higher number (or 100); left
   empty, it would take whatever is newest on internal by then.

   Run it from `main` under "Use workflow from"; nothing is built, so it
   doesn't need to be the tag.

`action: build-internal` rebuilds a tag and uploads it to internal again (for
example when the tag push's run failed); pick the tag under "Use workflow
from". A run on a branch fails on purpose, so the version name always matches
the code being built. Nothing in the workflow builds for production.

From a machine with the secrets, in `android/`:

- `bundle exec fastlane deploy` does step 1 for the tag on the checked-out commit.
- `bundle exec fastlane promote [version_code:18] [rollout:20]` does step 3.

## One-time setup

The workflow needs four repo secrets. A missing one fails the run at the first step.
Promoting only needs `PLAY_STORE_JSON_KEY`.

| Secret | Set by |
| --- | --- |
| `CARTO_API_KEY` | `just carto-key` |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PROPERTIES` | `just release-secrets` (from `android/key.properties` and its keystore) |
| `PLAY_STORE_JSON_KEY` | `just release-secrets` (walks you through the Google Cloud service account and Play Console access) |

For local fastlane: `cd android && bundle config set --local path vendor/bundle && bundle install`.
