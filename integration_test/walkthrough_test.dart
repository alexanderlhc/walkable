// In-app walkthrough of the walk-recording feature, for the Play Store
// "Video instructions" / prominent-disclosure requirement.
//
// Drives the real app with a faked GPS feed placed in Aarhus and plays out a
// complete recording session in real time so a screen recorder can capture it:
//
//   open on the Aarhus map → START → route draws live as the walk progresses,
//   distance/time/pace tick up → pause → resume → FINISH.
//
// Everything that affects pixels is fixed here (route, position cadence,
// permissions), so the only external variable is the network map tiles. Run via
// the wrapper, which boots an emulator and screen-records while this drives:
//
//   tool/walkthrough_video.sh
//
// Or manually against a running emulator:
//   fvm flutter drive \
//     --driver=test_driver/walkthrough_driver.dart \
//     --target=integration_test/walkthrough_test.dart \
//     -d <emulator-id>

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/main.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/walk_recorder.dart';

// Universitetsparken, Aarhus — a large, recognisable green park, so the live
// track reads as a believable on-land walk. The camera auto-centres on the
// first GPS fix, so feeding Aarhus coordinates puts the whole walkthrough here.
const _centre = LatLng(56.16928, 10.20034);
final _epoch = DateTime(2024, 5, 18, 9, 14, 0);

// A gentle, slightly wandering loop around [_centre]. Kept small (~55 m radius)
// so the moving dot and the whole route stay inside the zoom-17 viewport the
// app opens at — no recentre chip, nothing leaves the frame. The loop closes
// back near where it started, like a real park lap (~0.35 km).
List<LatLng> _walkLoop() {
  const n = 40; // number of fixes along the loop
  const radiusMetres = 55.0;
  final rLat = radiusMetres / 111000; // metres → degrees latitude
  final rLng = rLat / cos(_centre.latitude * pi / 180);
  return [
    for (var i = 0; i <= n; i++)
      () {
        final t = 2 * pi * i / n;
        // Organic wobble so the path isn't a perfect circle.
        final wobble = 1 + 0.18 * sin(3 * t) + 0.07 * cos(5 * t);
        return LatLng(
          _centre.latitude + rLat * wobble * sin(t),
          _centre.longitude + rLng * wobble * cos(t),
        );
      }(),
  ];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('walk-recording walkthrough (Aarhus)', (tester) async {
    final repo = await WalkRepository.inMemory();

    final geo = _FakeGeolocator(_centre);
    final location = LocationService(
      geolocator: geo,
      permissions: {
        LocationPermissionKind.notification: _GrantedPermission(),
        LocationPermissionKind.background: _GrantedPermission(),
        LocationPermissionKind.batteryOptimization: _GrantedPermission(),
      },
    );
    final recorder = WalkRecorder(locationService: location, repository: repo);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsController = SettingsController(SettingsRepository(prefs))
      ..load();

    await tester.pumpWidget(
      WalkableApp(
        recorder: recorder,
        repository: repo,
        settingsController: settingsController,
      ),
    );

    // Let the home screen request permission and subscribe to the position
    // stream, then drop the first fix at the park centre. The camera
    // auto-centres here and the "you are here" dot appears.
    await tester.pump(const Duration(milliseconds: 600));
    geo.emit(_centre, _epoch);
    await _hold(tester, const Duration(seconds: 4)); // settle map + give the
    // screen recorder a moment to be rolling before anything happens.

    // ── Start recording ──────────────────────────────────────────────────────
    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pump(const Duration(milliseconds: 700)); // start() sets up
    await _hold(tester, const Duration(milliseconds: 800));

    // ── Walk the loop ────────────────────────────────────────────────────────
    // Emit fixes one at a time over real wall-clock time. Each fix extends the
    // live polyline and advances distance; the 1 Hz recorder ticker keeps the
    // elapsed/pace readouts moving between fixes.
    final loop = _walkLoop();
    final pauseAt = (loop.length * 0.55).round(); // pause a little past halfway
    var t = _epoch;
    for (var i = 0; i < loop.length; i++) {
      t = t.add(const Duration(seconds: 2));
      geo.emit(loop[i], t);
      await _hold(tester, const Duration(milliseconds: 650));

      if (i == pauseAt) {
        // ── Pause ────────────────────────────────────────────────────────────
        await tester.tap(find.byKey(const Key('pause_button')));
        await _hold(tester, const Duration(seconds: 2)); // status → PAUSED
        // ── Resume ───────────────────────────────────────────────────────────
        await tester.tap(find.byKey(const Key('resume_button')));
        await _hold(tester, const Duration(milliseconds: 900));
      }
    }

    await _hold(tester, const Duration(seconds: 1));

    // ── Finish ───────────────────────────────────────────────────────────────
    await tester.tap(find.byKey(const Key('stop_button')));
    await _hold(tester, const Duration(milliseconds: 1200)); // Cancel / Finish
    await tester.tap(find.byKey(const Key('confirm_stop_button')));
    await _hold(tester, const Duration(seconds: 2)); // back to idle home
  });
}

/// Pumps frames over [d] of real wall-clock time. Used everywhere instead of
/// pumpAndSettle: the live map's tile fade animations never "settle", and we
/// want genuine elapsed time to pass so the recorder ticks and the screen
/// recording captures motion.
Future<void> _hold(WidgetTester tester, Duration d) async {
  const frame = Duration(milliseconds: 50);
  for (var elapsed = Duration.zero; elapsed < d; elapsed += frame) {
    await tester.pump(frame);
  }
}

// ─── Fakes ───────────────────────────────────────────────────────────────────
// Same shape as the screenshot test: a granted permission and a geolocator
// whose single broadcast stream feeds both the "you are here" dot and the
// recorder, so one emit() advances both.

class _GrantedPermission implements RuntimePermission {
  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> ensureGranted({LocationConsent? consent}) async => true;
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
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
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
