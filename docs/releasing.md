# Releasing

Releases are built and uploaded by `.github/workflows/release.yml`. Nothing is
committed for a release:

- **versionName** comes from the tag: `v0.5.1` → `0.5.1`.
- **versionCode** is the highest code on any Play track (internal, alpha,
  beta, production) + 1. The `+N` in `pubspec.yaml` is only the floor, so
  stop bumping it.

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
   below 100 it is a staged rollout, and running promote again with a higher
   number (or 100) widens or completes it.

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
