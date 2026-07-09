// Integration test for LocationService.
//
// Must run on a real Android device or emulator with GPS enabled:
//   fvm flutter test integration_test/location_service_integration_test.dart -d <device-id>
//
// The test grants location permission via the OS dialog — ensure the emulator
// has a mocked GPS location set before running.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:walkable/location/location_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LocationService service;

  setUp(() => service = LocationService());
  tearDown(() => service.dispose());

  testWidgets(
      'start() requests permission and stream emits at least one position',
      (tester) async {
    final result = await service.start();

    expect(
      result,
      anyOf(LocationServiceResult.started,
          LocationServiceResult.permissionDenied),
      reason: 'start() must return a known result — never throws',
    );

    if (result == LocationServiceResult.started) {
      final position =
          await service.positions.first.timeout(const Duration(seconds: 10));
      expect(position.latitude, isNotNaN);
      expect(position.longitude, isNotNaN);

      await service.stop();
      expect(service.isRunning, isFalse);
    }
  });
}
