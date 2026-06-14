// Deterministic Play Store screenshots.
//
// Drives the real app with a seeded in-memory database and a faked GPS feed,
// then captures one PNG per store screen. Run via the wrapper script which
// boots a fixed emulator and points the driver at an output directory:
//
//   tool/screenshots.sh
//
// Or manually:
//   SCREENSHOT_OUT=docs/screenshots/phone \
//   fvm flutter drive \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/screenshot_test.dart \
//     -d <emulator-id>
//
// Everything that affects pixels is fixed here (data, route, clock), so the
// only external variable is the map tiles fetched from the network.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/main.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_calculator.dart';
import 'package:walkable/walk_recorder.dart';

// The live map on the home/recording screens is fixed by the app to central
// Copenhagen; the "you are here" dot sits here.
const _base = LatLng(55.6761, 12.5683);
// Seeded walks loop through Fælledparken (a large green park) so the detail map
// shows a believable on-land walking route.
const _park = LatLng(55.7026, 12.5700);
final _epoch = DateTime(2024, 5, 18, 9, 14, 0);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture store screenshots', (tester) async {
    // Required on Android before takeScreenshot() can read the surface.
    await binding.convertFlutterSurfaceToImage();

    final repo = await WalkRepository.inMemory();
    await _seedHistory(repo);

    final geo = _FakeGeolocator(_base);
    final location = LocationService(
      geolocator: geo,
      notificationPermission: _GrantedNotifications(),
      backgroundLocationPermission: _GrantedBackgroundLocation(),
    );
    final recorder = WalkRecorder(
      locationService: location,
      repository: repo,
    );

    await tester.pumpWidget(
      WalkableApp(recorder: recorder, repository: repo),
    );
    // Let the screen request permission and subscribe to the position stream.
    await tester.pump(const Duration(milliseconds: 600));
    geo.emit(_base, _epoch); // place the "you are here" dot at centre
    await _settleMap(tester);

    // 1) Home — live map + Start button.
    await binding.takeScreenshot('01-home');

    // 2) History list (seeded walks). Pump over real time before capturing so
    // the Android surface readback reflects the pushed route (a plain
    // pumpAndSettle is instant with animations off and can capture a stale
    // frame, especially on slower/larger devices).
    await tester.tap(find.byKey(const Key('history_button')));
    await tester.pumpAndSettle();
    await _breathe(tester);
    await binding.takeScreenshot('04-history');

    // 3) Walk detail — tap the most recent walk (route + stats).
    await tester.tap(find.byType(Card).first);
    await tester.pump(const Duration(milliseconds: 400));
    await _settleMap(tester);
    await binding.takeScreenshot('03-detail');

    // Back to the home screen.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _settleMap(tester);

    // 4) Recording in progress — an honest just-started walk. We can't freeze
    // elapsed without touching production (WalkRecorder uses DateTime.now), so
    // we show the genuine early state: the recording UI live, ~3s elapsed, the
    // location dot on the map, no fabricated distance/pace.
    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pump(const Duration(milliseconds: 700)); // start() sets up
    await tester.pump(const Duration(seconds: 3)); // a few real seconds elapse
    geo.emit(_base, _epoch); // one fix → snapshot reflects ~3s elapsed, 0.00 km
    await _settleMap(tester);
    await binding.takeScreenshot('02-recording');
  });
}

/// Pumps frames over several seconds of real time so network map tiles can load
/// and fade in. (pumpAndSettle can't be used on map screens — tile fade
/// animations never "settle".)
Future<void> _settleMap(WidgetTester tester) async {
  for (var i = 0; i < 28; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// A short real-time settle (~2s) so the captured surface reflects the latest
/// frame on non-map screens.
Future<void> _breathe(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

// ─── Seed data ───────────────────────────────────────────────────────────────

Future<void> _seedHistory(WalkRepository repo) async {
  // Three finished walks on fixed dates: distinct loop sizes through the park,
  // each at a realistic walking pace (~11–12 min/km).
  await repo.save(_walk(
    id: 'seed-2024-05-18',
    start: DateTime(2024, 5, 18, 7, 32),
    route: _loop(radiusMetres: 470, phase: 0.0),
    paceMinPerKm: 11.4,
  ));
  await repo.save(_walk(
    id: 'seed-2024-05-15',
    start: DateTime(2024, 5, 15, 18, 5),
    route: _loop(radiusMetres: 330, phase: 2.1),
    paceMinPerKm: 12.0,
  ));
  await repo.save(_walk(
    id: 'seed-2024-05-12',
    start: DateTime(2024, 5, 12, 9, 48),
    route: _loop(radiusMetres: 660, phase: 4.0),
    paceMinPerKm: 11.0,
  ));
}

/// Builds a Walk whose duration follows from its measured length and the given
/// walking [paceMinPerKm], with coordinate timestamps spread across it.
Walk _walk({
  required String id,
  required DateTime start,
  required List<Coordinate> route,
  required double paceMinPerKm,
}) {
  final lengthMetres =
      totalDistance(route.map((c) => (lat: c.lat, lng: c.lng)).toList());
  final duration =
      Duration(seconds: (lengthMetres / 1000 * paceMinPerKm * 60).round());
  final stepMs =
      route.length > 1 ? duration.inMilliseconds ~/ (route.length - 1) : 0;
  final coords = [
    for (var i = 0; i < route.length; i++)
      Coordinate(
        lat: route[i].lat,
        lng: route[i].lng,
        recordedAt: start.add(Duration(milliseconds: stepMs * i)),
      ),
  ];
  return Walk(
    id: id,
    startTime: start,
    endTime: start.add(duration),
    coordinates: coords,
  );
}

/// A smooth, slightly wandering closed loop around [_park], sized by
/// [radiusMetres]. Deterministic: [phase] just rotates/varies the wobble so the
/// three seeded walks look distinct.
List<Coordinate> _loop({required double radiusMetres, required double phase}) {
  const n = 72;
  final rLat = radiusMetres / 111000; // metres → degrees latitude
  final rLng = rLat / cos(_park.latitude * pi / 180);
  final coords = <Coordinate>[];
  for (var i = 0; i <= n; i++) {
    final t = 2 * pi * i / n;
    final wobble = 1 + 0.16 * sin(3 * t + phase) + 0.08 * cos(5 * t + phase);
    coords.add(Coordinate(
      lat: _park.latitude + rLat * wobble * sin(t),
      lng: _park.longitude + rLng * wobble * cos(t),
      recordedAt: _epoch,
    ));
  }
  return coords;
}

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _GrantedNotifications implements NotificationPermission {
  @override
  Future<bool> ensureGranted() async => true;
}

class _GrantedBackgroundLocation implements BackgroundLocationPermission {
  @override
  Future<bool> ensureGranted() async => true;
}

class _FakeGeolocator implements GeolocatorInterface {
  _FakeGeolocator(LatLng start)
      : _last = _position(start.latitude, start.longitude, _epoch);

  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();
  Position _last;

  void emit(LatLng p, DateTime t) {
    _last = _position(p.latitude, p.longitude, t);
    _controller.add(_last);
  }

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async =>
      _last;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _controller.stream;
}

Position _position(double lat, double lng, DateTime t) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: t,
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 1.3,
      speedAccuracy: 0,
    );
