// End-to-end happy path on a real Android device or emulator: record a walk,
// stop it, find it in the history and open its route and stats.
//
// Runs the real app (WalkableApp, WalkRecorder, SQLite repository, screens)
// with a faked GPS feed and clock. Location is faked on purpose: emulator geo
// fixes arrive on the OS's schedule (first-fix latency, fused-provider
// throttling), which makes exact route and stat assertions flaky in CI. The
// real GPS path is covered by location_service_integration_test.dart.
//
//   just integration                    # all integration tests (as CI runs them)
//   fvm flutter test integration_test/happy_path_test.dart -d <device-id>

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/main.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/walk_detail_screen.dart';
import 'package:walkable/screens/walk_history_screen.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/units.dart';
import 'package:walkable/walk_recorder.dart';

const _start = LatLng(55.6761, 12.5683);

// Ten 0.0009° steps due north: 10 × 100.08 m ≈ 1.00 km.
final _route = [
  for (var i = 0; i <= 10; i++)
    LatLng(_start.latitude + i * 0.0009, _start.longitude),
];

// 12:30 of moving time over 1.0008 km → 749.4 s/km → "12:29".
const _walkDuration = Duration(minutes: 12, seconds: 30);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('record a walk, then find it in history with route and stats',
      (tester) async {
    var now = DateTime(2024, 5, 18, 9, 14);
    final repo = await WalkRepository.inMemory();
    final geo = _FakeGeolocator(_start, now);
    final location = LocationService(
      geolocator: geo,
      permissions: {
        LocationPermissionKind.notification: _GrantedPermission(),
        LocationPermissionKind.background: _GrantedPermission(),
        LocationPermissionKind.batteryOptimization: _GrantedPermission(),
      },
      batterySaverRestrictsLocation: () async => false,
    );
    final recorder = WalkRecorder(
      locationService: location,
      repository: repo,
      now: () => now,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsController = SettingsController(SettingsRepository(prefs))
      ..load();
    // Fix the copy and units so the stat strings below hold on any device.
    await settingsController.setLocaleOverride(const Locale('en'));
    await settingsController.setUnitsOverride(UnitSystem.metric);

    await tester.pumpWidget(WalkableApp(
      recorder: recorder,
      repository: repo,
      settingsController: settingsController,
    ));
    await _pumpFor(tester, const Duration(milliseconds: 600));

    // ── Record ───────────────────────────────────────────────────────────────
    await tester.tap(find.byKey(const Key('start_button')));
    await _pumpUntil(tester, find.byKey(const Key('stop_button')));
    expect(recorder.state, RecorderState.recording);

    final step = _walkDuration ~/ (_route.length - 1);
    for (var i = 0; i < _route.length; i++) {
      if (i > 0) now = now.add(step);
      geo.emit(_route[i], now);
      await _pumpFor(tester, const Duration(milliseconds: 100));
    }

    // ── Stop ─────────────────────────────────────────────────────────────────
    await tester.tap(find.byKey(const Key('stop_button')));
    await _pumpUntil(tester, find.byKey(const Key('confirm_stop_button')));
    await tester.tap(find.byKey(const Key('confirm_stop_button')));
    await _pumpUntil(tester, find.byKey(const Key('done_button')));
    await tester.tap(find.byKey(const Key('done_button')));
    await _pumpUntil(tester, find.byKey(const Key('start_button')));

    // ── History ──────────────────────────────────────────────────────────────
    await tester.tap(find.byKey(const Key('menu_button')));
    await _pumpUntil(tester, find.byKey(const Key('history_button')));
    await tester.tap(find.byKey(const Key('history_button')));
    final card = find.descendant(
      of: find.byType(WalkHistoryScreen),
      matching: find.text('1.00 km'),
    );
    await _pumpUntil(tester, card);
    expect(card, findsOneWidget, reason: 'exactly one saved walk');
    expect(
      find.descendant(
          of: find.byType(WalkHistoryScreen), matching: find.text('12:30')),
      findsOneWidget,
    );

    // ── Detail ───────────────────────────────────────────────────────────────
    await tester.tap(card);
    await _pumpUntil(tester, find.byType(WalkDetailScreen));
    await _pumpFor(tester, const Duration(milliseconds: 500));

    Finder inDetail(Finder f) =>
        find.descendant(of: find.byType(WalkDetailScreen), matching: f);
    final polylines = tester
        .widget<PolylineLayer>(inDetail(find.byType(PolylineLayer)))
        .polylines;
    expect(polylines, hasLength(1));
    expect(polylines.single.points, _route);

    expect(inDetail(find.text('1.00 km')), findsOneWidget);
    expect(inDetail(find.text('12:30')), findsOneWidget);
    expect(inDetail(find.text('12:29 /km')), findsOneWidget);
  });
}

/// Pumps frames over [d] of real time. The live map's tile animations never
/// settle, so pumpAndSettle can't be used.
Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  const frame = Duration(milliseconds: 50);
  for (var elapsed = Duration.zero; elapsed < d; elapsed += frame) {
    await tester.pump(frame);
  }
}

/// Pumps until [finder] matches something, failing after [timeout]. Covers the
/// real async gaps (SQLite writes, route transitions) between steps.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out after $timeout waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _GrantedPermission implements RuntimePermission {
  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> ensureGranted({LocationConsent? consent}) async => true;
}

class _FakeGeolocator implements GeolocatorInterface {
  _FakeGeolocator(LatLng start, DateTime t) : _last = _position(start, t);

  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();
  Position _last;

  void emit(LatLng p, DateTime t) {
    _last = _position(p, t);
    _controller.add(_last);
  }

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      _last;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      _controller.stream;
}

Position _position(LatLng p, DateTime t) => Position(
      latitude: p.latitude,
      longitude: p.longitude,
      timestamp: t,
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 1.3,
      speedAccuracy: 0,
    );
