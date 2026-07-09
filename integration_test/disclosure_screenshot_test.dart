// Captures the Google Play "Prominent Disclosure" dialogs (English) on a real
// device/emulator, so the in-app disclosures shown before each OS prompt can
// be handed to reviewers:
//
// - foreground_disclosure_en: shown on screen open, immediately before the
//   initial OS location prompt (the prompt Play's second rejection,
//   IN_APP_EXPERIENCE-749, flagged as appearing bare).
// - disclosure_en: shown on Start, immediately before the OS
//   "Allow all the time" background prompt.
//
// Forces the English locale and permissions that are *not* yet granted, so
// the consent gates surface their dialogs before any system prompt. Run via
// the wrapper:
//
//   tool/disclosure_screenshot.sh
//
// Or manually against a booted emulator:
//   SCREENSHOT_OUT=docs/screenshots/disclosure \
//   fvm flutter drive --profile \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/disclosure_screenshot_test.dart \
//     -d <emulator-id>

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/location/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/active_walk_screen.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/walk_recorder.dart';

const _base = LatLng(55.6761, 12.5683);
final _epoch = DateTime(2024, 5, 18, 9, 14, 0);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture background-location disclosure', (tester) async {
    await binding.convertFlutterSurfaceToImage();

    final repo = await WalkRepository.inMemory();
    final geo = _FakeGeolocator(_base);
    final location = LocationService(
      geolocator: geo,
      permissions: {
        LocationPermissionKind.notification: _GrantedPermission(),
        // Not yet granted → tapping Start runs the disclosure consent gate.
        LocationPermissionKind.background: _DisclosurePermission(),
        LocationPermissionKind.batteryOptimization: _GrantedPermission(),
      },
    );
    final recorder = WalkRecorder(locationService: location, repository: repo);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsController = SettingsController(SettingsRepository(prefs))
      ..load();

    // Force English regardless of device locale.
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ActiveWalkScreen(
        recorder: recorder,
        repository: repo,
        settingsController: settingsController,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    geo.emit(_base, _epoch); // place the "you are here" dot
    await _settleMap(tester);

    // Tap Start. start() blocks on the disclosure dialog (the consent gate
    // never resolves here), so pump — don't settle — to surface it.
    await tester.tap(find.byKey(const Key('start_button')));
    await tester.pump(); // build the dialog route
    expect(find.text('Allow background location'), findsOneWidget);

    // Pump several real-time frames so the dialog (and its scrim) is flushed to
    // the Android surface before the readback — two frames isn't enough.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    await binding.takeScreenshot('disclosure_en');
  });

  testWidgets('capture foreground-location disclosure', (tester) async {
    await binding.convertFlutterSurfaceToImage();

    final repo = await WalkRepository.inMemory();
    // Foreground permission not yet granted → the screen-open permission
    // request runs the foreground disclosure consent gate before any OS
    // prompt could appear.
    final geo = _FakeGeolocator(_base, permission: LocationPermission.denied);
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

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ActiveWalkScreen(
        recorder: recorder,
        repository: repo,
        settingsController: settingsController,
      ),
    ));
    // The post-frame permission request awaits the consent gate (which never
    // resolves here), leaving the disclosure dialog up over the map.
    await tester.pump(); // post-frame callback fires the permission request
    await tester.pump(); // build the dialog route
    expect(find.text('Location access'), findsOneWidget);

    // Let the map tiles load beneath the dialog before the readback.
    await _settleMap(tester);

    await binding.takeScreenshot('foreground_disclosure_en');
  });
}

Future<void> _settleMap(WidgetTester tester) async {
  for (var i = 0; i < 28; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _GrantedPermission implements RuntimePermission {
  @override
  Future<bool> isGranted() async => true;
  @override
  Future<bool> ensureGranted({LocationConsent? consent}) async => true;
}

/// Background permission that is not yet granted, so [ensureGranted] runs the
/// disclosure consent gate (surfacing the dialog) like the real one does.
class _DisclosurePermission implements RuntimePermission {
  @override
  Future<bool> isGranted() async => false;
  @override
  Future<bool> ensureGranted({LocationConsent? consent}) async =>
      consent != null && await consent();
}

class _FakeGeolocator implements GeolocatorInterface {
  _FakeGeolocator(LatLng start,
      {LocationPermission permission = LocationPermission.whileInUse})
      : _permission = permission,
        _last = _position(start.latitude, start.longitude, _epoch);

  final LocationPermission _permission;
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();
  Position _last;

  void emit(LatLng p, DateTime t) {
    _last = _position(p.latitude, p.longitude, t);
    _controller.add(_last);
  }

  @override
  Future<LocationPermission> checkPermission() async => _permission;
  @override
  Future<LocationPermission> requestPermission() async => _permission;
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
