// Integration test for LocationService against the real GPS plugin and
// Android permissions, on an emulator.
//
// Nothing here can tap an OS permission dialog, so the permissions must be
// granted before the test starts and a GPS fix must be fed to the emulator.
// tool/integration_test.sh does both (pm grant, deviceidle whitelist, a
// `geo fix` at [_fix] every second) and runs the tests with --no-uninstall so
// the grants survive the test app's reinstall:
//
//   tool/integration_test.sh [device-id]

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:walkable/location/location_service.dart';

// Universitetsparken, Aarhus — must match FIX_LAT/FIX_LNG in
// tool/integration_test.sh.
const _fix = LatLng(56.16928, 10.20034);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LocationService service;

  setUp(() => service = LocationService());
  tearDown(() => service.dispose());

  testWidgets('start() with permission granted streams the emulator GPS fix',
      (tester) async {
    // Any permission still missing would put an OS dialog up that nobody can
    // answer and hang start(). Fail fast with the fix instead.
    expect(await Geolocator.checkPermission(),
        anyOf(LocationPermission.whileInUse, LocationPermission.always),
        reason: 'location not granted: run via tool/integration_test.sh');
    expect(await Permission.ignoreBatteryOptimizations.isGranted, isTrue,
        reason: 'not battery-exempt: run via tool/integration_test.sh');
    expect(await Permission.notification.isDenied, isFalse,
        reason: 'notifications denied: run via tool/integration_test.sh');

    var consentAsked = false;
    final result = await service.start(foregroundConsent: () async {
      consentAsked = true;
      return true;
    });

    expect(result, LocationServiceResult.started);
    expect(consentAsked, isFalse,
        reason: 'an already-granted permission must not re-show a disclosure');
    expect(service.isRunning, isTrue);
    expect(service.notificationsGranted, isTrue);
    expect(service.batteryOptimizationGranted, isTrue);

    final position =
        await service.positions.first.timeout(const Duration(seconds: 30));
    final metresOff = const Distance().as(
        LengthUnit.Meter, _fix, LatLng(position.latitude, position.longitude));
    expect(metresOff, lessThan(50),
        reason: 'expected the emulator fix at $_fix, got '
            '${position.latitude},${position.longitude}');

    await service.stop();
    expect(service.isRunning, isFalse);
  });
}
