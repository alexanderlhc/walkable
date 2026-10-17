# Releasing

Releases are built and uploaded by `.github/workflows/release.yml`. Nothing is
committed for a release:

- **versionName** comes from the tag: `v0.5.1` → `0.5.1`.
- **versionCode** is the highest code on any Play track (internal, alpha,
  beta, production) + 1. The `+N` in `pubspec.yaml` is only the floor, so
  stop bumping it.

## Cut a release

```sh
git checkout main && git pull
git tag v0.5.1
git push origin v0.5.1          # → builds and uploads to the internal track
```

Check the internal build on a phone (Play Console → Test and release →
Testing → Internal testing). Then ship that tag to production:

- GitHub → Actions → Release → **Run workflow**
- **Use workflow from:** Tags → `v0.5.1`, **Play Store track:** `production`

This builds the tag again with the next versionCode and uploads it to
production. A run on a branch instead of a tag fails on purpose, so the
version name always matches the code being built.

From a machine with the secrets, `cd android && bundle exec fastlane deploy track:internal`
does the same as the workflow, for the tag on the checked-out commit.

## One-time setup

The workflow needs four repo secrets. A missing one fails the run at the first step.

| Secret | Set by |
| --- | --- |
| `CARTO_API_KEY` | `just carto-key` |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PROPERTIES` | `just release-secrets` (from `android/key.properties` and its keystore) |
| `PLAY_STORE_JSON_KEY` | `just release-secrets` (walks you through the Google Cloud service account and Play Console access) |

For local fastlane: `cd android && bundle config set --local path vendor/bundle && bundle install`.
