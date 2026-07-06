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

/// Simplifies a recorded route for preview rendering: Douglas–Peucker with a
/// [toleranceMetres] band (points within it of the surrounding segment are
/// dropped), then a uniform subsample down to [maxPoints] if the result is
/// still too long. First and last points are always kept; fewer than three
/// points are returned as-is.
List<Coord> simplifyRoute(
  List<Coord> coords, {
  double toleranceMetres = 15,
  int maxPoints = 100,
}) {
  if (coords.length < 3) return List.of(coords);

  final keep = List<bool>.filled(coords.length, false);
  keep[0] = true;
  keep[coords.length - 1] = true;

  // Iterative Douglas–Peucker (explicit stack, so a pathological route can't
  // blow the call stack): keep the point furthest from the segment between
  // the range ends whenever it strays beyond the tolerance, then recurse into
  // both halves.
  final ranges = <(int, int)>[(0, coords.length - 1)];
  while (ranges.isNotEmpty) {
    final (start, end) = ranges.removeLast();
    var maxDist = 0.0;
    var furthest = -1;
    for (var i = start + 1; i < end; i++) {
      final d =
          _distanceToSegmentMetres(coords[i], coords[start], coords[end]);
      if (d > maxDist) {
        maxDist = d;
        furthest = i;
      }
    }
    if (furthest != -1 && maxDist > toleranceMetres) {
      keep[furthest] = true;
      ranges
        ..add((start, furthest))
        ..add((furthest, end));
    }
  }

  final simplified = <Coord>[
    for (var i = 0; i < coords.length; i++)
      if (keep[i]) coords[i],
  ];
  if (simplified.length <= maxPoints) return simplified;

  // Still over the cap: uniform subsample, keeping the first and last points.
  final step = (simplified.length - 1) / (maxPoints - 1);
  return [for (var i = 0; i < maxPoints; i++) simplified[(i * step).round()]];
}

/// Perpendicular distance in metres from [p] to the segment [a]–[b], using an
/// equirectangular projection — accurate to well under a metre at walk scale,
/// which is all the simplifier needs.
double _distanceToSegmentMetres(Coord p, Coord a, Coord b) {
  const metresPerDegree = 111320.0;
  final cosLat = cos(_toRad((a.lat + b.lat) / 2));
  final bx = (b.lng - a.lng) * cosLat * metresPerDegree;
  final by = (b.lat - a.lat) * metresPerDegree;
  final px = (p.lng - a.lng) * cosLat * metresPerDegree;
  final py = (p.lat - a.lat) * metresPerDegree;
  final lenSq = bx * bx + by * by;
  final t = lenSq == 0 ? 0.0 : ((px * bx + py * by) / lenSq).clamp(0.0, 1.0);
  final dx = px - t * bx;
  final dy = py - t * by;
  return sqrt(dx * dx + dy * dy);
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
