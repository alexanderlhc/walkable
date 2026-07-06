# History map previews — design

**Date:** 2026-07-06
**Status:** Approved

## Motivation

The history list used to draw each walk's route as a vector sketch from
`walk.coordinates`. The N+1 fix made `WalkRepository.findAll()` stop hydrating
coordinates (the list only needs the persisted distance), which silently
reduced every history card to the empty-route placeholder dot. Cards should
show a real route preview again — without reintroducing the N+1 coordinate
loads.

## Decision

Render a mini tile map on each history card, driven by a **simplified
polyline stored on the walk row itself**. The full recording stays in the
`coordinates` table untouched; the preview is a small, bounded JSON blob the
list query gets for free.

## Parts

### 1. Route simplifier (`lib/walk_calculator.dart`)

`simplifyRoute(coords, {toleranceMetres = 15, maxPoints = 100})`:

- Douglas–Peucker with a ~15 m tolerance. Perpendicular distance uses an
  equirectangular metres approximation — accurate to well under a metre at
  walk scale, and much cheaper than proper geodesics.
- If the result still exceeds 100 points, uniform subsample down to 100,
  always keeping the first and last points.
- Fewer than 3 points are returned as-is.

### 2. Schema v4 (`lib/repository/walk_repository.dart`)

- New `route TEXT` column on `walks`: a JSON array `[[lat,lng],...]` of the
  simplified route.
- v3→v4 migration adds the column and backfills **finished** walks by loading
  their coordinates and simplifying (mirrors the v2→v3 distance backfill).
- New `Walk.route` field (`List<Coord>?`). `findAll()` reads it — still no
  coordinate hydration. `findById` unchanged (full hydration as before).

### 3. Write path

- `finishWalk` gains a `route` parameter.
- `WalkRecorder.stop()` simplifies the in-memory `_coordinates` and passes the
  result alongside the distance, inside the existing best-effort try/catch.

### 4. UI (`lib/screens/walk_history_screen.dart`)

- `_WalkCard` renders a non-interactive `FlutterMap` when `walk.route` has
  points: same tile layer setup as the detail screen (`mapTileUrl` per theme
  brightness, CartoCDN subdomains, `userAgentPackageName`
  `dk.alexanderlhc.walkable`), a `PolylineLayer` in `colorScheme.primary`, and
  a camera fit to the route bounds with padding — reusing the detail screen's
  degenerate-bounds fallback (<2 distinct points → centre + fixed zoom 17).
- `InteractionOptions(flags: InteractiveFlag.none)` plus an `IgnorePointer`
  wrapper so taps reach the card's `InkWell`.
- `route` null/empty → the existing placeholder dot. Date pill and stats row
  unchanged. The now-unused `_RouteSketch`/`_RoutePainter` vector sketch is
  removed (the placeholder keeps only its faint centred dot).

## Alternatives considered

- **PNG snapshot at finish time** — capture the map once and store an image.
  Rejected: offscreen tile capture is fiddly (headless rendering, tile
  readiness, DPI variants) for no real win over live tiles.
- **Vector-only sketch (status quo ante)** — draw the polyline without tiles.
  Rejected: renders instantly and offline, but shows no geography; a route
  with no map context is just a squiggle.
