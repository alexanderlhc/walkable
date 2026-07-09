import 'package:flutter_test/flutter_test.dart';
import 'package:walkable/walk_calculator.dart';

void main() {
  group('haversineDistance', () {
    test('returns approximate distance between London and Paris', () {
      final d = haversineDistance(51.5074, -0.1278, 48.8566, 2.3522);
      expect(d, closeTo(344000, 2000));
    });

    test('returns 0 for identical coordinates', () {
      expect(haversineDistance(51.5074, -0.1278, 51.5074, -0.1278), 0.0);
    });
  });

  group('totalDistance', () {
    test('returns 0 for empty list', () {
      expect(totalDistance([]), 0.0);
    });

    test('returns 0 for single coordinate', () {
      expect(totalDistance([(lat: 51.5074, lng: -0.1278)]), 0.0);
    });

    test('returns haversine distance for two coordinates', () {
      final d = totalDistance([
        (lat: 51.5074, lng: -0.1278),
        (lat: 48.8566, lng: 2.3522),
      ]);
      expect(d, closeTo(344000, 2000));
    });

    test('sums segment distances for multiple coordinates', () {
      // A→B→A should be double A→B
      const a = (lat: 51.5074, lng: -0.1278);
      const b = (lat: 48.8566, lng: 2.3522);
      final ab = haversineDistance(a.lat, a.lng, b.lat, b.lng);
      expect(totalDistance([a, b, a]), closeTo(ab * 2, 4000));
    });
  });

  group('simplifyRoute', () {
    test('returns fewer than three points unchanged', () {
      expect(simplifyRoute([]), isEmpty);
      expect(simplifyRoute([(lat: 55.0, lng: 12.0)]), [(lat: 55.0, lng: 12.0)]);
      expect(
        simplifyRoute([(lat: 55.0, lng: 12.0), (lat: 55.001, lng: 12.001)]),
        [(lat: 55.0, lng: 12.0), (lat: 55.001, lng: 12.001)],
      );
    });

    test('collapses collinear points to the endpoints', () {
      final route = [
        for (var i = 0; i <= 20; i++) (lat: 55.0 + i * 0.0001, lng: 12.0),
      ];
      expect(simplifyRoute(route), [route.first, route.last]);
    });

    test('drops deviations within tolerance and keeps ones beyond it', () {
      // The midpoint sits ~11 m north of the A–B line (0.0001° latitude).
      const a = (lat: 55.0, lng: 12.0);
      const m = (lat: 55.0001, lng: 12.001);
      const b = (lat: 55.0, lng: 12.002);

      expect(simplifyRoute([a, m, b], toleranceMetres: 15), [a, b]);
      expect(simplifyRoute([a, m, b], toleranceMetres: 5), [a, m, b]);
    });

    test('caps the result at maxPoints, keeping first and last', () {
      // A zigzag every point of which deviates far beyond the tolerance, so
      // Douglas–Peucker keeps all of them and the cap has to kick in.
      final route = [
        for (var i = 0; i < 500; i++)
          (lat: 55.0 + (i.isEven ? 0.0 : 0.005), lng: 12.0 + i * 0.001),
      ];

      final simplified = simplifyRoute(route);

      expect(simplified.length, 100);
      expect(simplified.first, route.first);
      expect(simplified.last, route.last);
    });
  });

  group('pace', () {
    test('returns min/km for valid inputs', () {
      // 1 km in 6 minutes = 6 min/km
      final p = pace(1000, const Duration(minutes: 6));
      expect(p, closeTo(6.0, 0.001));
    });

    test('returns infinity sentinel for zero distance', () {
      expect(pace(0, const Duration(minutes: 10)), double.infinity);
    });

    test('returns 0 sentinel for zero duration', () {
      expect(pace(1000, Duration.zero), 0.0);
    });
  });

  group('formatPace', () {
    test('formats whole minutes and seconds as m:ss', () {
      expect(formatPace(7.5, fallback: '--'), '7:30');
    });

    test('carries 60 rounded seconds into the next minute', () {
      // 11.997 min/km rounds to 720s → 12:00, never "11:60".
      expect(formatPace(11.997, fallback: '--'), '12:00');
    });

    test('returns fallback for the infinity and zero sentinels', () {
      expect(formatPace(double.infinity, fallback: '--'), '--');
      expect(formatPace(0, fallback: '--'), '--');
    });
  });
}
