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
  /// Requests the permission if needed. Returns whether notifications are
  /// permitted afterwards — `false` means the foreground-service notification
  /// can't show, so background tracking will be unreliable.
  Future<bool> ensureGranted();
}

class _DefaultNotificationPermission implements NotificationPermission {
  @override
  Future<bool> ensureGranted() async {
    // Only Android gates the foreground-service notification this way.
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    var status = await Permission.notification.status;
    if (status.isDenied) {
      status = await Permission.notification.request();
    }
    return status.isGranted;
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
  bool _notificationsGranted = true;

  Stream<Position> get positions => _controller.stream;
  bool get isRunning => _running;

  /// Whether the foreground-service notification can be shown after the most
  /// recent [start]. When `false`, background tracking is unreliable and the
  /// user should be warned.
  bool get notificationsGranted => _notificationsGranted;

  /// Opens the OS app settings so the user can re-enable a denied permission.
  Future<void> openSettings() => openAppSettings();

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
    _notificationsGranted = await _notificationPermission.ensureGranted();

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
