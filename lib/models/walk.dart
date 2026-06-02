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
  final List<Coordinate> coordinates;

  const Walk({
    required this.id,
    required this.startTime,
    this.endTime,
    this.coordinates = const [],
  });
}
