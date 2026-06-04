import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

export 'package:geolocator/geolocator.dart' show Position;

abstract interface class GeolocatorInterface {
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition({LocationSettings? locationSettings});
  Stream<Position> getPositionStream({LocationSettings? locationSettings});
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
  LocationService({GeolocatorInterface? geolocator})
      : _geolocator = geolocator ?? _DefaultGeolocator();

  final GeolocatorInterface _geolocator;
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
