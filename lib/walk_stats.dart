import 'package:walkable/models/walk.dart';
import 'package:walkable/walk_calculator.dart' as calc;

/// The canonical stats for a walk — distance, duration and pace — together with
/// the formatted strings the UI renders. This is the single place these values
/// are derived; no screen should recompute them.
///
/// Duration is **pause-aware moving time**: the time spent actively recording,
/// excluding any paused spans. The recorder accumulates it live and persists it
/// on finish (see [Walk.duration]). This is deliberately *not*
/// `endTime - startTime`, which would include paused time. A walk with no
/// recorded duration reports a null [duration] and renders the unavailable
/// fallback.
class WalkStats {
  final double distanceMetres;
  final Duration? duration;

  const WalkStats({required this.distanceMetres, required this.duration});

  /// Stats for a live or in-progress recording, from the current polyline and
  /// the pause-aware elapsed time.
  factory WalkStats.fromParts({
    required List<calc.Coord> coordinates,
    required Duration duration,
  }) =>
      WalkStats(
        distanceMetres: calc.totalDistance(coordinates),
        duration: duration,
      );

  /// Stats for a stored walk, from its persisted pause-aware [Walk.duration].
  factory WalkStats.of(Walk walk) => WalkStats(
        distanceMetres: calc.totalDistance(
          walk.coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList(),
        ),
        duration: walk.duration,
      );

  double get distanceKm => distanceMetres / 1000;

  /// Pace in min/km. Carries [calc.pace]'s sentinels: infinity for zero
  /// distance or unknown duration, 0.0 for zero duration.
  double get paceMinPerKm =>
      duration == null ? double.infinity : calc.pace(distanceMetres, duration!);

  /// Distance in kilometres to two decimals (e.g. `"1.23"`).
  String formattedDistance() => distanceKm.toStringAsFixed(2);

  /// Duration as `h:mm:ss`, or `m:ss` when under an hour. Returns [fallback]
  /// when the duration is unknown.
  String formattedDuration({required String fallback}) {
    final d = duration;
    if (d == null) return fallback;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  /// Pace as `m:ss`, or [fallback] for the unavailable sentinels.
  String formattedPace({required String fallback}) =>
      calc.formatPace(paceMinPerKm, fallback: fallback);
}
