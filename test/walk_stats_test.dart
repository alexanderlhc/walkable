import 'package:flutter_test/flutter_test.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/units.dart';
import 'package:walkable/walk_stats.dart';

void main() {
  // London → Paris, ~344 km, used to give a known non-zero distance.
  const london = (lat: 51.5074, lng: -0.1278);
  const paris = (lat: 48.8566, lng: 2.3522);

  group('WalkStats.fromParts', () {
    test('exposes distance, duration and pace from coordinates + elapsed', () {
      final stats = WalkStats.fromParts(
        coordinates: [london, paris],
        duration: const Duration(hours: 1),
      );

      expect(stats.distanceMetres, closeTo(344000, 2000));
      expect(stats.duration, const Duration(hours: 1));
      // ~344 km in 60 min ≈ 0.174 min/km
      expect(stats.paceMinPerKm, closeTo(60 / 344, 0.01));
    });

    test('zero coordinates give zero distance and infinity pace sentinel', () {
      final stats = WalkStats.fromParts(
        coordinates: const [],
        duration: const Duration(minutes: 10),
      );

      expect(stats.distanceMetres, 0.0);
      expect(stats.paceMinPerKm, double.infinity);
    });
  });

  group('WalkStats.of', () {
    test('uses the walk\'s persisted pause-aware duration', () {
      final walk = Walk(
        id: 'w',
        startTime: DateTime(2026, 6, 1, 9, 0),
        endTime: DateTime(2026, 6, 1, 9, 30),
        duration: const Duration(minutes: 25),
        coordinates: [
          Coordinate(
              lat: london.lat, lng: london.lng, recordedAt: DateTime(2026)),
          Coordinate(
              lat: paris.lat, lng: paris.lng, recordedAt: DateTime(2026)),
        ],
      );

      final stats = WalkStats.of(walk);

      expect(stats.distanceMetres, closeTo(344000, 2000));
      // 25 minutes, NOT the 30 minutes of endTime - startTime.
      expect(stats.duration, const Duration(minutes: 25));
    });

    test('duration is null when the walk has none (unfinished / unrecorded)',
        () {
      final walk = Walk(id: 'w', startTime: DateTime(2026, 6, 1, 9, 0));

      expect(WalkStats.of(walk).duration, isNull);
    });
  });

  group('formattedDistance', () {
    test('formats metres as kilometres to two decimals', () {
      const stats = WalkStats(distanceMetres: 1234.5, duration: null);
      expect(stats.formattedDistance(UnitSystem.metric), '1.23');
    });
  });

  group('formattedDuration', () {
    WalkStats withDuration(Duration? d) => WalkStats.fromParts(
        coordinates: const [], duration: d ?? Duration.zero);

    test('formats under an hour as mm:ss', () {
      expect(
          withDuration(const Duration(minutes: 30))
              .formattedDuration(fallback: '--'),
          '30:00');
    });

    test('formats an hour or more as h:mm:ss', () {
      expect(
          withDuration(const Duration(hours: 1, minutes: 5, seconds: 9))
              .formattedDuration(fallback: '--'),
          '1:05:09');
    });

    test('returns fallback when duration is unknown', () {
      final walk = Walk(id: 'w', startTime: DateTime(2026));
      expect(WalkStats.of(walk).formattedDuration(fallback: '--'), '--');
    });
  });

  group('formattedPace', () {
    test('formats min/km as m:ss', () {
      // 1 km in 6 minutes = 6:00 /km
      final stats = WalkStats.fromParts(
        coordinates: [london, paris],
        duration: Duration(milliseconds: (344 * 6 * 60000).round()),
      );
      expect(stats.formattedPace(UnitSystem.metric, fallback: '--:--'), '6:00');
    });

    test('returns fallback for the zero-distance sentinel', () {
      final stats = WalkStats.fromParts(
        coordinates: const [],
        duration: const Duration(minutes: 10),
      );
      expect(
          stats.formattedPace(UnitSystem.metric, fallback: '--:--'), '--:--');
    });
  });

  group('imperial units', () {
    test('distanceMiles converts from metres', () {
      const stats = WalkStats(
        distanceMetres: 1609.344,
        duration: Duration(minutes: 10),
      );
      expect(stats.distanceMiles, closeTo(1.0, 0.0001));
    });

    test('formattedDistance formats per unit system', () {
      const stats = WalkStats(
        distanceMetres: 3218.688, // 2 miles, ~3.22 km
        duration: Duration(minutes: 40),
      );
      expect(stats.formattedDistance(UnitSystem.metric), '3.22');
      expect(stats.formattedDistance(UnitSystem.imperial), '2.00');
    });

    test('paceMinPerUnit scales pace to min per mile', () {
      const stats = WalkStats(
        distanceMetres: 1609.344, // 1 mile in 16 min -> 16 min/mi
        duration: Duration(minutes: 16),
      );
      expect(stats.paceMinPerUnit(UnitSystem.imperial), closeTo(16.0, 0.001));
      expect(stats.paceMinPerUnit(UnitSystem.metric),
          closeTo(16.0 / 1.609344, 0.001));
    });

    test('pace sentinels pass through unchanged in imperial', () {
      const zeroDistance = WalkStats(
        distanceMetres: 0,
        duration: Duration(minutes: 5),
      );
      expect(zeroDistance.paceMinPerUnit(UnitSystem.imperial), double.infinity);

      const noDuration = WalkStats(distanceMetres: 1000, duration: null);
      expect(noDuration.paceMinPerUnit(UnitSystem.imperial), double.infinity);

      const zeroDuration = WalkStats(
        distanceMetres: 1000,
        duration: Duration.zero,
      );
      expect(zeroDuration.paceMinPerUnit(UnitSystem.imperial), 0.0);
      expect(zeroDuration.formattedPace(UnitSystem.imperial, fallback: '--'),
          '--');
    });
  });
}
