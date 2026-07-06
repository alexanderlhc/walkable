class Coordinate {
  final double lat;
  final double lng;
  final DateTime recordedAt;

  const Coordinate({
    required this.lat,
    required this.lng,
    required this.recordedAt,
  });
}

class Walk {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;

  /// Pause-aware moving time recorded for this walk — the canonical duration,
  /// persisted on finish. Deliberately *not* `endTime - startTime`, which would
  /// include paused spans. Null for walks with no recorded duration (e.g. an
  /// in-progress walk that was never finished).
  final Duration? duration;

  /// Total route distance in metres, persisted on finish so list views can
  /// show it without loading every coordinate. Null for walks stored before
  /// the distance column existed (callers fall back to computing it from
  /// [coordinates]).
  final double? distanceMetres;

  /// The recorded route. May be empty on walks loaded for list views —
  /// [WalkRepository.findAll] deliberately skips coordinate hydration; use
  /// [WalkRepository.findById] for the full route.
  final List<Coordinate> coordinates;

  const Walk({
    required this.id,
    required this.startTime,
    this.endTime,
    this.duration,
    this.distanceMetres,
    this.coordinates = const [],
  });
}
