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
}
