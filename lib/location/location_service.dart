import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

export 'package:geolocator/geolocator.dart' show Position;

abstract interface class GeolocatorInterface {
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition({LocationSettings? locationSettings});
  Stream<Position> getPositionStream({LocationSettings? locationSettings});
}

/// Ensures the Android notification permission needed to show the
/// location foreground-service notification (required on Android 13+).
abstract interface class NotificationPermission {
  Future<void> ensureGranted();
}

class _DefaultNotificationPermission implements NotificationPermission {
  @override
  Future<void> ensureGranted() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }
}

class _DefaultGeolocator implements GeolocatorInterface {
  @override
  Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Geolocator.getCurrentPosition(
        locationSettings: locationSettings ?? const LocationSettings(),
      );

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      Geolocator.getPositionStream(locationSettings: locationSettings);
}

enum LocationServiceResult { started, running, permissionDenied }

class LocationService {
  LocationService({
    GeolocatorInterface? geolocator,
    NotificationPermission? notificationPermission,
  })  : _geolocator = geolocator ?? _DefaultGeolocator(),
        _notificationPermission =
            notificationPermission ?? _DefaultNotificationPermission();

  final GeolocatorInterface _geolocator;
  final NotificationPermission _notificationPermission;
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();
  StreamSubscription<Position>? _subscription;
  bool _running = false;

  Stream<Position> get positions => _controller.stream;
  bool get isRunning => _running;

  Future<bool> checkAndRequestPermission() async {
    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<Position> getCurrentPosition() =>
      _geolocator.getCurrentPosition();


  Stream<Position> watchPosition() => _geolocator.getPositionStream(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

  Future<LocationServiceResult> start() async {
    if (_running) return LocationServiceResult.running;

    final granted = await checkAndRequestPermission();
    if (!granted) return LocationServiceResult.permissionDenied;

    // The foreground-service notification can't appear on Android 13+ without
    // this runtime permission, and without a visible notification the OS will
    // throttle/kill GPS once the screen locks. Best-effort: failure to grant
    // doesn't block recording, it just makes background tracking less reliable.
    await _notificationPermission.ensureGranted();

    _running = true;
    _subscription = _geolocator
        .getPositionStream(locationSettings: _buildSettings())
        .listen(_controller.add, onError: _controller.addError);

    return LocationServiceResult.started;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _running = false;
  }

  void dispose() {
    stop();
    _controller.close();
  }

  LocationSettings _buildSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Walkable is recording your walk',
          notificationTitle: 'Walk in progress',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }
}
