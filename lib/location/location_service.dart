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

/// Ensures the app is exempt from Android's battery optimisation (Doze mode).
/// Without the exemption, the OS can suspend GPS even for a foreground service
/// once the screen locks — resulting in only a start and end point being
/// recorded. Fitness tracking apps routinely require this exemption.
abstract interface class BatteryOptimizationPermission {
  /// Requests the exemption if needed. Returns whether it is granted
  /// afterwards. Best-effort: a `false` result means GPS may be suspended by
  /// Doze, but recording can still proceed.
  Future<bool> ensureGranted();
}

class _DefaultBatteryOptimizationPermission
    implements BatteryOptimizationPermission {
  @override
  Future<bool> ensureGranted() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    var status = await Permission.ignoreBatteryOptimizations.status;
    if (!status.isGranted) {
      status = await Permission.ignoreBatteryOptimizations.request();
    }
    return status.isGranted;
  }
}

/// Ensures the "Allow all the time" background-location permission. Without it
/// Android only delivers location updates while the app is in use, so a walk
/// stops being tracked once the screen locks or you switch apps.
abstract interface class BackgroundLocationPermission {
  /// Requests the permission if needed. Returns whether it is granted
  /// afterwards. Best-effort: a `false` result means screen-off tracking will
  /// be unreliable, but recording can still proceed.
  Future<bool> ensureGranted();
}

class _DefaultBackgroundLocationPermission
    implements BackgroundLocationPermission {
  @override
  Future<bool> ensureGranted() async {
    // Only Android distinguishes background ("all the time") location.
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    var status = await Permission.locationAlways.status;
    if (!status.isGranted) {
      status = await Permission.locationAlways.request();
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

/// Localized copy for the Android foreground-service notification.
class ForegroundNotificationText {
  final String title;
  final String body;

  const ForegroundNotificationText({required this.title, required this.body});
}

class LocationService {
  LocationService({
    GeolocatorInterface? geolocator,
    NotificationPermission? notificationPermission,
    BackgroundLocationPermission? backgroundLocationPermission,
    BatteryOptimizationPermission? batteryOptimizationPermission,
  })  : _geolocator = geolocator ?? _DefaultGeolocator(),
        _notificationPermission =
            notificationPermission ?? _DefaultNotificationPermission(),
        _backgroundLocationPermission = backgroundLocationPermission ??
            _DefaultBackgroundLocationPermission(),
        _batteryOptimizationPermission = batteryOptimizationPermission ??
            _DefaultBatteryOptimizationPermission();

  final GeolocatorInterface _geolocator;
  final NotificationPermission _notificationPermission;
  final BackgroundLocationPermission _backgroundLocationPermission;
  final BatteryOptimizationPermission _batteryOptimizationPermission;
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();
  StreamSubscription<Position>? _subscription;
  bool _running = false;
  bool _notificationsGranted = true;
  bool _backgroundGranted = true;
  bool _batteryOptimizationGranted = true;

  Stream<Position> get positions => _controller.stream;
  bool get isRunning => _running;

  /// Whether the foreground-service notification can be shown after the most
  /// recent [start]. When `false`, background tracking is unreliable and the
  /// user should be warned.
  bool get notificationsGranted => _notificationsGranted;

  /// Whether "Allow all the time" background location was granted after the
  /// most recent permission check. When `false`, tracking may stop once the
  /// screen locks.
  bool get backgroundGranted => _backgroundGranted;

  /// Whether the app is exempt from battery optimisation after the most recent
  /// [start]. When `false`, Android's Doze mode may suspend GPS even with a
  /// foreground service running, causing gaps or total loss of tracking.
  bool get batteryOptimizationGranted => _batteryOptimizationGranted;

  /// Opens the OS app settings so the user can re-enable a denied permission.
  Future<void> openSettings() => openAppSettings();

  Future<bool> checkAndRequestPermission() async {
    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
    }
    final foregroundGranted = permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
    if (!foregroundGranted) {
      _backgroundGranted = false;
      return false;
    }
    // Escalate to "Allow all the time" so updates keep coming with the screen
    // off. Best-effort: declining doesn't block recording, just makes
    // background tracking unreliable (and the user can be warned).
    _backgroundGranted = await _backgroundLocationPermission.ensureGranted();
    return true;
  }

  Future<Position> getCurrentPosition() =>
      _geolocator.getCurrentPosition();

  Stream<Position> watchPosition() => _geolocator.getPositionStream(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

  /// [notification] supplies the localized title/body for the Android
  /// foreground-service notification. Required on Android; ignored elsewhere.
  Future<LocationServiceResult> start({
    ForegroundNotificationText? notification,
  }) async {
    if (_running) return LocationServiceResult.running;

    final granted = await checkAndRequestPermission();
    if (!granted) return LocationServiceResult.permissionDenied;

    // The foreground-service notification can't appear on Android 13+ without
    // this runtime permission, and without a visible notification the OS will
    // throttle/kill GPS once the screen locks. Best-effort: failure to grant
    // doesn't block recording, it just makes background tracking less reliable.
    _notificationsGranted = await _notificationPermission.ensureGranted();

    // Without a battery-optimisation exemption, Android's Doze mode can
    // suspend GPS even when the foreground service + wake lock are active.
    // The system dialog lets the user grant the exemption in one tap.
    _batteryOptimizationGranted =
        await _batteryOptimizationPermission.ensureGranted();

    _running = true;
    _subscription = _geolocator
        .getPositionStream(locationSettings: _buildSettings(notification))
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

  LocationSettings _buildSettings(ForegroundNotificationText? notification) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationText: notification?.body ?? 'Recording your walk',
          notificationTitle: notification?.title ?? 'Walk in progress',
          enableWakeLock: true,
          // Persistent, non-dismissable notification: keeps the foreground
          // service (and therefore GPS) alive while the screen is locked.
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }
}
