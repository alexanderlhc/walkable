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

/// Decides whether a runtime permission should be (re-)requested given its
/// current [PermissionStatus]. This is where per-permission policy varies:
/// notification only re-requests while explicitly denied (a permanent denial
/// can't be re-prompted), whereas the others request whenever not yet granted.
typedef ShouldRequest = bool Function(PermissionStatus status);

/// Gate run immediately before an OS location-permission prompt. Returns
/// whether the user agreed to continue. This is where the Google Play
/// "Prominent Disclosure" dialog is shown: the disclosure must appear, and the
/// user must affirmatively accept it, *immediately before* the corresponding
/// OS prompt (foreground location and `ACCESS_BACKGROUND_LOCATION` each get
/// their own gate). Returning `false` (the user declined) means the OS prompt
/// is skipped entirely.
typedef LocationConsent = Future<bool> Function();

/// A single Android runtime permission the location service ensures before or
/// during tracking. Best-effort: a `false` result never blocks recording, it
/// just signals that some background reliability is lost (see the per-role
/// notes in [defaultLocationPermissions]).
abstract interface class RuntimePermission {
  /// Whether the permission is already granted, without prompting.
  Future<bool> isGranted();

  /// Requests the permission if needed. Returns whether it is granted
  /// afterwards.
  ///
  /// When [consent] is supplied it is awaited immediately before the OS prompt
  /// (and only when a prompt is actually about to happen); a `false` result
  /// skips the prompt and leaves the permission ungranted. This is how the
  /// background-location disclosure is enforced ahead of the system dialog.
  Future<bool> ensureGranted({LocationConsent? consent});
}

/// The role each [RuntimePermission] plays for the location service.
enum LocationPermissionKind { background, notification, batteryOptimization }

/// Default [RuntimePermission] backed by permission_handler. The
/// Android-platform guard plus the check-then-request-if-needed logic lives
/// here in one place; [permission] and [shouldRequest] carry the only real
/// per-permission variation.
class AndroidRuntimePermission implements RuntimePermission {
  AndroidRuntimePermission({
    required this.permission,
    required this.shouldRequest,
  });

  final Permission permission;
  final ShouldRequest shouldRequest;

  @override
  Future<bool> isGranted() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return (await permission.status).isGranted;
  }

  @override
  Future<bool> ensureGranted({LocationConsent? consent}) async {
    // Only Android gates tracking on these runtime permissions.
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    var status = await permission.status;
    if (shouldRequest(status)) {
      // Show the prominent disclosure right before the OS prompt. Declining
      // skips the prompt and leaves the permission as-is.
      if (consent != null && !await consent()) return status.isGranted;
      status = await permission.request();
    }
    return status.isGranted;
  }
}

/// The runtime permissions the location service ensures, keyed by role.
///
/// - [LocationPermissionKind.background]: the "Allow all the time"
///   background-location permission. Without it Android only delivers updates
///   while the app is in use, so a walk stops being tracked once the screen
///   locks or you switch apps. Requested whenever not yet granted.
/// - [LocationPermissionKind.notification]: the Android 13+ permission needed
///   to show the foreground-service notification; without a visible
///   notification the OS throttles/kills GPS once the screen locks. Only
///   re-requested while explicitly denied.
/// - [LocationPermissionKind.batteryOptimization]: exemption from Android's
///   battery optimisation (Doze mode), which can otherwise suspend GPS even for
///   a foreground service once the screen locks. Requested whenever not yet
///   granted.
Map<LocationPermissionKind, RuntimePermission> defaultLocationPermissions() => {
      LocationPermissionKind.background: AndroidRuntimePermission(
        permission: Permission.locationAlways,
        shouldRequest: (status) => !status.isGranted,
      ),
      LocationPermissionKind.notification: AndroidRuntimePermission(
        permission: Permission.notification,
        shouldRequest: (status) => status.isDenied,
      ),
      LocationPermissionKind.batteryOptimization: AndroidRuntimePermission(
        permission: Permission.ignoreBatteryOptimizations,
        shouldRequest: (status) => !status.isGranted,
      ),
    };

class _DefaultGeolocator implements GeolocatorInterface {
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

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
    Map<LocationPermissionKind, RuntimePermission>? permissions,
  })  : _geolocator = geolocator ?? _DefaultGeolocator(),
        // Merge any injected overrides over the defaults so the map is always
        // complete — callers (and tests) can supply just the roles they care
        // about.
        _permissions = {...defaultLocationPermissions(), ...?permissions};

  final GeolocatorInterface _geolocator;
  final Map<LocationPermissionKind, RuntimePermission> _permissions;
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

  /// Ensures foreground location, then optionally escalates to "Allow all the
  /// time" background location.
  ///
  /// Each OS prompt is gated behind its own Google Play "Prominent Disclosure"
  /// consent, shown and affirmatively accepted immediately before the prompt:
  ///
  /// - The foreground prompt fires **only** when [foregroundConsent] is
  ///   supplied and accepted. Without it the permission is merely checked —
  ///   no code path may surface the OS location dialog without a preceding
  ///   in-app disclosure (this is what Play rejected the app for, twice).
  /// - Background location is likewise requested **only** when
  ///   [backgroundConsent] is supplied. Without it (e.g. resuming a paused
  ///   walk) [backgroundGranted] just reflects whatever was granted earlier.
  ///
  /// Consents are awaited only when their prompt is actually about to happen,
  /// so an already-granted permission never re-shows a disclosure.
  Future<bool> checkAndRequestPermission({
    LocationConsent? foregroundConsent,
    LocationConsent? backgroundConsent,
  }) async {
    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied &&
        foregroundConsent != null &&
        await foregroundConsent()) {
      permission = await _geolocator.requestPermission();
    }
    final foregroundGranted = permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
    if (!foregroundGranted) {
      _backgroundGranted = false;
      return false;
    }
    final background = _permissions[LocationPermissionKind.background]!;
    // Escalate to "Allow all the time" so updates keep coming with the screen
    // off. Best-effort: declining doesn't block recording, just makes
    // background tracking unreliable (and the user can be warned).
    _backgroundGranted = backgroundConsent != null
        ? await background.ensureGranted(consent: backgroundConsent)
        : await background.isGranted();
    return true;
  }

  Future<Position> getCurrentPosition() => _geolocator.getCurrentPosition();

  Stream<Position> watchPosition() => _geolocator.getPositionStream(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

  /// [notification] supplies the localized title/body for the Android
  /// foreground-service notification. Required on Android; ignored elsewhere.
  ///
  /// [foregroundConsent] and [backgroundConsent] gate the two OS location
  /// prompts; see [checkAndRequestPermission]. Pass them when starting a walk
  /// so each prominent disclosure is shown before its OS prompt.
  Future<LocationServiceResult> start({
    ForegroundNotificationText? notification,
    LocationConsent? foregroundConsent,
    LocationConsent? backgroundConsent,
  }) async {
    if (_running) return LocationServiceResult.running;

    final granted = await checkAndRequestPermission(
      foregroundConsent: foregroundConsent,
      backgroundConsent: backgroundConsent,
    );
    if (!granted) return LocationServiceResult.permissionDenied;

    // The foreground-service notification can't appear on Android 13+ without
    // this runtime permission, and without a visible notification the OS will
    // throttle/kill GPS once the screen locks. Best-effort: failure to grant
    // doesn't block recording, it just makes background tracking less reliable.
    _notificationsGranted =
        await _permissions[LocationPermissionKind.notification]!
            .ensureGranted();

    // Without a battery-optimisation exemption, Android's Doze mode can
    // suspend GPS even when the foreground service + wake lock are active.
    // The system dialog lets the user grant the exemption in one tap.
    _batteryOptimizationGranted =
        await _permissions[LocationPermissionKind.batteryOptimization]!
            .ensureGranted();

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
        // Request a fix every second (1 Hz), the standard sampling rate for
        // sport/walk trackers and the GPS chip's native cadence. Without an
        // explicit interval the FusedLocationProvider picks a conservative one,
        // producing sparse points and long straight segments on the map.
        // distanceFilter 0 keeps fixes coming even at slow walking pace so
        // curves aren't lost.
        intervalDuration: const Duration(seconds: 1),
        distanceFilter: 0,
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
