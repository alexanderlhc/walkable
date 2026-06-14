import 'dart:math';

double haversineDistance(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

typedef Coord = ({double lat, double lng});

double totalDistance(List<Coord> coords) {
  if (coords.length < 2) return 0.0;
  double total = 0.0;
  for (var i = 0; i < coords.length - 1; i++) {
    total += haversineDistance(
        coords[i].lat, coords[i].lng, coords[i + 1].lat, coords[i + 1].lng);
  }
  return total;
}

/// Returns pace in min/km. Sentinels: [double.infinity] for zero distance,
/// [0.0] for zero duration.
double pace(double distanceMetres, Duration duration) {
  if (distanceMetres == 0) return double.infinity;
  if (duration == Duration.zero) return 0.0;
  final minutes = duration.inMilliseconds / 60000.0;
  final km = distanceMetres / 1000.0;
  return minutes / km;
}

/// Formats a [minPerKm] pace as `m:ss`, returning [fallback] for the sentinel
/// values from [pace]. Rounds to whole seconds and carries 60s into the next
/// minute (so 11.997 → "12:00", never "11:60").
String formatPace(double minPerKm, {required String fallback}) {
  if (!minPerKm.isFinite || minPerKm == 0) return fallback;
  final totalSeconds = (minPerKm * 60).round();
  final m = totalSeconds ~/ 60;
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

double _toRad(double deg) => deg * pi / 180;
