import 'package:walkable/models/walk.dart';
import 'package:walkable/units.dart';
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

  /// Stats for a stored walk, from its persisted pause-aware [Walk.duration]
  /// and persisted [Walk.distanceMetres]. Walks stored before the distance
  /// column existed fall back to computing distance from the coordinates.
  factory WalkStats.of(Walk walk) => WalkStats(
        distanceMetres: walk.distanceMetres ??
            calc.totalDistance(
              walk.coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList(),
            ),
        duration: walk.duration,
      );

  static const _metresPerMile = 1609.344;

  double get distanceKm => distanceMetres / 1000;

  double get distanceMiles => distanceMetres / _metresPerMile;

  /// Pace in min/km. Carries [calc.pace]'s sentinels: infinity for zero
  /// distance or unknown duration, 0.0 for zero duration.
  double get paceMinPerKm =>
      duration == null ? double.infinity : calc.pace(distanceMetres, duration!);

  /// Pace in minutes per display unit (km or mile). The sentinels pass
  /// through unchanged (infinity stays infinity, 0.0 stays 0.0).
  double paceMinPerUnit(UnitSystem units) => units == UnitSystem.metric
      ? paceMinPerKm
      : paceMinPerKm * (_metresPerMile / 1000);

  /// Distance in the display unit to two decimals (e.g. `"1.23"`).
  String formattedDistance(UnitSystem units) =>
      (units == UnitSystem.metric ? distanceKm : distanceMiles)
          .toStringAsFixed(2);

  /// Duration as `h:mm:ss`, or `m:ss` when under an hour. Returns [fallback]
  /// when the duration is unknown.
  String formattedDuration({required String fallback}) {
    final d = duration;
    if (d == null) return fallback;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  /// Pace as `m:ss` in the display unit, or [fallback] for the unavailable
  /// sentinels.
  String formattedPace(UnitSystem units, {required String fallback}) =>
      calc.formatPace(paceMinPerUnit(units), fallback: fallback);
}
