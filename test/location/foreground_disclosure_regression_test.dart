import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:walkable/location/location_service.dart';

class MockGeolocatorInterface extends Mock implements GeolocatorInterface {}

/// Stand-in runtime permission that never touches platform channels; the
/// signature uses a raw function type so this file compiles both before and
/// after the consent-gate rename (needed for the red/green regression run).
class _GrantedPermission implements RuntimePermission {
  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> ensureGranted({Future<bool> Function()? consent}) async => true;
}

/// Regression tests for the Google Play "Inadequate Prominent Disclosure"
/// rejection (twice: first for the background prompt, then for the initial
/// foreground prompt fired bare from screen-open).
///
/// Play's User Data policy requires every OS location-permission prompt to be
/// *immediately preceded* by an in-app disclosure the user affirmatively
/// accepts. The structural guarantee pinned here: [LocationService] must never
/// surface the OS foreground-location prompt unless a consent gate was
/// supplied and accepted — a bare permission check may only *check*.
void main() {
  late MockGeolocatorInterface mock;
  late LocationService service;

  setUp(() {
    mock = MockGeolocatorInterface();
    service = LocationService(
      geolocator: mock,
      permissions: {
        for (final kind in LocationPermissionKind.values)
          kind: _GrantedPermission(),
      },
    );
    when(() => mock.checkPermission())
        .thenAnswer((_) async => LocationPermission.denied);
    when(() => mock.requestPermission())
        .thenAnswer((_) async => LocationPermission.whileInUse);
  });

  tearDown(() => service.dispose());

  test(
      'a consent-less permission check never fires the OS foreground prompt '
      '(the screen-open path Play rejected in IN_APP_EXPERIENCE-749)',
      () async {
    final granted = await service.checkAndRequestPermission();

    // Without an accepted prominent disclosure the OS dialog must not appear;
    // the permission simply stays denied.
    verifyNever(() => mock.requestPermission());
    expect(granted, isFalse);
  });
}
