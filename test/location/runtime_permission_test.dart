import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:walkable/location/location_service.dart';

void main() {
  group('defaultLocationPermissions()', () {
    final defaults = defaultLocationPermissions();

    test('wraps the expected permission for each role', () {
      expect(
        (defaults[LocationPermissionKind.background]!
                as AndroidRuntimePermission)
            .permission,
        Permission.locationAlways,
      );
      expect(
        (defaults[LocationPermissionKind.notification]!
                as AndroidRuntimePermission)
            .permission,
        Permission.notification,
      );
      expect(
        (defaults[LocationPermissionKind.batteryOptimization]!
                as AndroidRuntimePermission)
            .permission,
        Permission.ignoreBatteryOptimizations,
      );
    });

    test('notification only re-requests while denied, not when permanent', () {
      final shouldRequest = (defaults[LocationPermissionKind.notification]!
              as AndroidRuntimePermission)
          .shouldRequest;

      expect(shouldRequest(PermissionStatus.denied), isTrue);
      expect(shouldRequest(PermissionStatus.permanentlyDenied), isFalse);
      expect(shouldRequest(PermissionStatus.granted), isFalse);
    });

    test('background and battery re-request whenever not granted', () {
      for (final kind in [
        LocationPermissionKind.background,
        LocationPermissionKind.batteryOptimization,
      ]) {
        final shouldRequest =
            (defaults[kind]! as AndroidRuntimePermission).shouldRequest;

        expect(shouldRequest(PermissionStatus.denied), isTrue,
            reason: '$kind should request when denied');
        expect(shouldRequest(PermissionStatus.permanentlyDenied), isTrue,
            reason: '$kind should request when permanently denied');
        expect(shouldRequest(PermissionStatus.granted), isFalse,
            reason: '$kind should not request when already granted');
      }
    });
  });
}
