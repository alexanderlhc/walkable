# Crash recovery — salvage orphaned walks at startup

**Date:** 2026-07-06
**Status:** Approved

## Problem

Walk rows are inserted at the start of recording and coordinates are
persisted per-fix (each with a `recorded_at` timestamp), but
`end_time`/`duration_ms`/`distance`/`route` are only written by
`finishWalk`. If the process dies mid-walk (OOM kill, crash, forced stop),
the row is left unfinished — and `findAll()` filters on
`end_time IS NOT NULL`, so the walk is hidden from the history **forever**,
even though its entire route is sitting in the database.

## What's recoverable

Everything except the pause-aware duration is derivable from what's already
on disk:

- **end_time** — the last coordinate's `recorded_at`: the final moment we
  know recording was running.
- **distance** — `totalDistance(coords)`, exactly what `finishWalk`
  computes.
- **route** — `simplifyRoute(coords)`, ditto.
- **duration** — the one unrecoverable value. It lives only in the
  recorder's memory, and coordinate gaps cannot infer it: the GPS distance
  filter makes a stationary user look identical to a paused walk. So the
  recorder must persist it periodically while recording; recovery falls
  back to the start-to-last-fix wall-clock span when no persisted value
  exists.

## Parts

### 1. Repository (`lib/repository/walk_repository.dart`)

- `updateProgress(String id, Duration duration)` — one UPDATE writing
  `duration_ms` on the unfinished row (guarded by `end_time IS NULL` so a
  straggler write can never clobber a finished walk).
- `recoverOrphans()` — finds walks `WHERE end_time IS NULL`; for each, in a
  per-walk transaction:
  - **< 2 coordinates** → delete the row and its coordinates (nothing worth
    keeping, and a stale stub would otherwise resurface on every launch);
  - **otherwise** → finish it in place: `end_time` = last coordinate's
    `recorded_at`, `distance` = `totalDistance(coords)`, `route` =
    `simplifyRoute(coords)` (reusing exactly what `finishWalk` writes), and
    `duration_ms` = the existing persisted value if non-null, else
    `last recorded_at − start_time`.
  - Returns the number of *recovered* (not deleted) walks.

### 2. Recorder (`lib/walk_recorder.dart`)

Persist progress during recording so the duration is recoverable:

- on every `pause()` — pauses are where wall-clock inference drifts
  furthest, so this write is the one that keeps recovery honest;
- from the existing 1-second ticker, throttled to one write per ~30 s of
  recording (tracked via the injected clock, so tests drive it
  deterministically).

Writes ride the existing serialized persistence chain and are best-effort,
mirroring `appendCoordinate`/`stop()`: a failure is logged and must never
disturb recording or wedge `stop()`.

### 3. Startup salvage (`lib/main.dart` → `ActiveWalkScreen`)

`main()` invokes `recoverOrphans()` once, right after opening the
repository and before the UI (and its history queries) starts — at that
point every unfinished row is by definition an orphan, so recovery can
never race an active recording. The count is threaded through
`WalkableApp` to `ActiveWalkScreen`, which shows a one-time snackbar when
it is positive ("Recovered an interrupted walk to your history",
ICU-pluralised, in both `app_en.arb` and `app_da.arb`). Recovery is
best-effort: a failure is logged and the app launches normally.

## Edge cases

- **Orphan with 0–1 coordinates** — deleted; there's no route to show and
  the history card would be meaningless.
- **No persisted duration** (killed before the first 30 s write) — fall
  back to start-to-last-fix span; slightly overstates moving time if the
  user paused, but it's the only honest estimate available.
- **Persisted duration exists** — kept verbatim; it is more accurate than
  any wall-clock inference (it's pause-aware up to ≤30 s staleness).
- **Several orphans at once** — each handled independently in its own
  transaction; one bad row doesn't block the rest.
- **Finished walks** — never touched: the query filters on
  `end_time IS NULL`.
- **Late `updateProgress` after `finishWalk`** — the `end_time IS NULL`
  guard makes it a no-op.

## Non-goal

Full resume-recording ("continue this walk?") was considered and rejected:
with the foreground service holding recording alive, mid-walk process death
is rare, and the resume UX (stale GPS, a gap in the track, a dialog on
launch) buys little over silently completing the walk with the data we
already have.
