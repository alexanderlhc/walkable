import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:walkable/location/location_service.dart';

class MockGeolocatorInterface extends Mock implements GeolocatorInterface {}

class FakeNotificationPermission implements NotificationPermission {
  FakeNotificationPermission({this.granted = true});

  bool granted;
  int ensureGrantedCalls = 0;

  @override
  Future<bool> ensureGranted() async {
    ensureGrantedCalls++;
    return granted;
  }
}

class FakeBackgroundLocationPermission
    implements BackgroundLocationPermission {
  FakeBackgroundLocationPermission({this.granted = true});

  bool granted;
  int ensureGrantedCalls = 0;

  @override
  Future<bool> ensureGranted() async {
    ensureGrantedCalls++;
    return granted;
  }
}

Position _pos({double lat = 55.676, double lng = 12.568}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026),
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 1.4,
      speedAccuracy: 0.0,
    );

void main() {
  late MockGeolocatorInterface mock;
  late FakeNotificationPermission notifications;
  late FakeBackgroundLocationPermission background;
  late LocationService service;

  setUp(() {
    mock = MockGeolocatorInterface();
    notifications = FakeNotificationPermission();
    background = FakeBackgroundLocationPermission();
    service = LocationService(
      geolocator: mock,
      notificationPermission: notifications,
      backgroundLocationPermission: background,
    );
  });

  tearDown(() => service.dispose());

  group('start()', () {
    test('returns started when permission already granted', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(
        () => mock.getPositionStream(
            locationSettings: any(named: 'locationSettings')),
      ).thenAnswer((_) => const Stream.empty());

      expect(await service.start(), LocationServiceResult.started);
      expect(service.isRunning, isTrue);
    });

    test('requests permission when initially denied; starts if then granted',
        () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);
      when(() => mock.requestPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);
      when(
        () => mock.getPositionStream(
            locationSettings: any(named: 'locationSettings')),
      ).thenAnswer((_) => const Stream.empty());

      expect(await service.start(), LocationServiceResult.started);
      verify(() => mock.requestPermission()).called(1);
    });

    test('returns permissionDenied when still denied after request', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);
      when(() => mock.requestPermission())
          .thenAnswer((_) async => LocationPermission.denied);

      expect(await service.start(), LocationServiceResult.permissionDenied);
      expect(service.isRunning, isFalse);
      verifyNever(
        () => mock.getPositionStream(
            locationSettings: any(named: 'locationSettings')),
      );
    });

    test('returns permissionDenied for deniedForever without requesting',
        () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.deniedForever);

      expect(await service.start(), LocationServiceResult.permissionDenied);
      verifyNever(() => mock.requestPermission());
    });

    test('requests notification permission so the FGS notification can show',
        () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(
        () => mock.getPositionStream(
            locationSettings: any(named: 'locationSettings')),
      ).thenAnswer((_) => const Stream.empty());

      await service.start();

      expect(notifications.ensureGrantedCalls, 1);
    });

    test('notificationsGranted reflects whether the permission was granted',
        () async {
      notifications.granted = false;
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(
        () => mock.getPositionStream(
            locationSettings: any(named: 'locationSettings')),
      ).thenAnswer((_) => const Stream.empty());

      await service.start();

      expect(service.notificationsGranted, isFalse);
    });

    test('returns running if already started', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(
        () => mock.getPositionStream(
            locationSettings: any(named: 'locationSettings')),
      ).thenAnswer((_) => const Stream.empty());

      await service.start();
      expect(await service.start(), LocationServiceResult.running);
    });
  });

  group('stop()', () {
    test('sets isRunning to false and cancels subscription', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(
        () => mock.getPositionStream(
            locationSettings: any(named: 'locationSettings')),
      ).thenAnswer((_) => const Stream.empty());

      await service.start();
      await service.stop();

      expect(service.isRunning, isFalse);
    });
  });

  group('positions stream', () {
    test('emits positions forwarded from geolocator', () async {
      final p1 = _pos(lat: 55.1);
      final p2 = _pos(lat: 55.2);

      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);
      when(
        () => mock.getPositionStream(
            locationSettings: any(named: 'locationSettings')),
      ).thenAnswer((_) => Stream.fromIterable([p1, p2]));

      final future = service.positions.take(2).toList();
      await service.start();

      expect(await future, [p1, p2]);
    });
  });

  group('checkAndRequestPermission()', () {
    test('returns true when permission already granted', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.always);

      expect(await service.checkAndRequestPermission(), isTrue);
      verifyNever(() => mock.requestPermission());
    });

    test('returns true for whileInUse without requesting', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);

      expect(await service.checkAndRequestPermission(), isTrue);
      verifyNever(() => mock.requestPermission());
    });

    test('requests when denied; returns true if then granted', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);
      when(() => mock.requestPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);

      expect(await service.checkAndRequestPermission(), isTrue);
      verify(() => mock.requestPermission()).called(1);
    });

    test('returns false when still denied after request', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);
      when(() => mock.requestPermission())
          .thenAnswer((_) async => LocationPermission.denied);

      expect(await service.checkAndRequestPermission(), isFalse);
    });

    test('returns false for deniedForever without requesting', () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.deniedForever);

      expect(await service.checkAndRequestPermission(), isFalse);
      verifyNever(() => mock.requestPermission());
    });

    test('escalates to background location once foreground is granted',
        () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);

      await service.checkAndRequestPermission();

      expect(background.ensureGrantedCalls, 1);
      expect(service.backgroundGranted, isTrue);
    });

    test('backgroundGranted is false when "all the time" is declined',
        () async {
      background.granted = false;
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);

      await service.checkAndRequestPermission();

      expect(service.backgroundGranted, isFalse);
    });

    test('does not request background location when foreground is denied',
        () async {
      when(() => mock.checkPermission())
          .thenAnswer((_) async => LocationPermission.deniedForever);

      await service.checkAndRequestPermission();

      expect(background.ensureGrantedCalls, 0);
      expect(service.backgroundGranted, isFalse);
    });
  });

  group('getCurrentPosition()', () {
    test('delegates to geolocator and returns position', () async {
      final expected = _pos();
      when(() => mock.getCurrentPosition(
              locationSettings: any(named: 'locationSettings')))
          .thenAnswer((_) async => expected);

      expect(await service.getCurrentPosition(), expected);
    });
  });

  group('watchPosition()', () {
    test('returns position stream from geolocator', () async {
      final p1 = _pos(lat: 55.1);
      final p2 = _pos(lat: 55.2);

      when(() => mock.getPositionStream(
              locationSettings: any(named: 'locationSettings')))
          .thenAnswer((_) => Stream.fromIterable([p1, p2]));

      expect(await service.watchPosition().take(2).toList(), [p1, p2]);
    });
  });
}
