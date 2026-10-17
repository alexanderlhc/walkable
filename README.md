# Walkable

Record your walks and see your route, distance and time. No accounts, no
tracking: walks stay on the phone. Android only, built with Flutter.

- Privacy policy: [docs/privacy-policy.md](docs/privacy-policy.md)
- Play Store listing text: [docs/store-listing.md](docs/store-listing.md)

## Develop

Tasks live in the [justfile](justfile) (`just` lists them). Flutter is pinned
in [.fvmrc](.fvmrc), so use [fvm](https://fvm.app).

```sh
just deps          # fetch packages
just carto-key     # one-time: store the map API key (see below)
just run           # build and launch on a connected device
just test          # unit and widget tests
just analyze       # static analysis
just integration   # integration tests on an emulator
```

### Map key

The map tiles come from CARTO, which needs an API key. `just carto-key` stores
it in the gitignored `dart_defines.local.json` (and as the GitHub secret
`CARTO_API_KEY`). Without the file, dev builds run but the map shows CARTO's
"API key required" watermark, and `just apk` / `just bundle` refuse to build.
Never commit the key: this repo is public.

## Release

Push a version tag and GitHub builds it and uploads it to the Play internal
track; test it, then promote that same build to production from GitHub
Actions. Step by step, plus the one-time secrets setup:
[docs/releasing.md](docs/releasing.md).

```sh
git tag v0.5.1 && git push origin v0.5.1
```

## More docs

- [docs/battery-managers.md](docs/battery-managers.md): Battery Saver and
  manufacturer battery managers that stop tracking with the screen off
