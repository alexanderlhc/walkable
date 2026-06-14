import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_calculator.dart';

enum RecorderState { idle, recording, paused, stopped }

class WalkSnapshot {
  final double distanceMetres;
  final Duration elapsed;
  final double paceMinPerKm;
  final List<Coord> polyline;

  const WalkSnapshot({
    required this.distanceMetres,
    required this.elapsed,
    required this.paceMinPerKm,
    required this.polyline,
  });
}

class WalkRecorder {
  final LocationService locationService;
  final WalkRepository _repository;

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  String? _id;
  DateTime? _startTime;
  DateTime? _periodStart;
  Duration _accumulatedDuration = Duration.zero;
  final List<Coordinate> _coordinates = [];
  StreamSubscription<Position>? _subscription;
  ForegroundNotificationText? _notification;
  // Serializes incremental DB writes and lets stop() drain them before
  // finalizing the walk.
  Future<void> _persist = Future<void>.value();

  final StreamController<WalkSnapshot> _snapshots =
      StreamController<WalkSnapshot>.broadcast();
  Stream<WalkSnapshot> get snapshots => _snapshots.stream;

  WalkRecorder({
    required this.locationService,
    required WalkRepository repository,
  }) : _repository = repository;

  Future<LocationServiceResult> start({
    ForegroundNotificationText? notification,
  }) async {
    if (_state != RecorderState.idle) return LocationServiceResult.running;
    _notification = notification;
    final result = await locationService.start(notification: notification);
    if (result == LocationServiceResult.permissionDenied) {
      return LocationServiceResult.permissionDenied;
    }
    _state = RecorderState.recording;
    _startTime = DateTime.now();
    _periodStart = _startTime;
    _id = _generateId(_startTime!);
    // Persist the walk row up front so an in-progress walk survives a kill.
    _persist = _repository.createWalk(_id!, _startTime!);
    _subscription = locationService.positions.listen(_onPosition);
    return LocationServiceResult.started;
  }

  Future<void> pause() async {
    if (_state != RecorderState.recording) return;
    final now = DateTime.now();
    _accumulatedDuration += now.difference(_periodStart!);
    _periodStart = null;
    _state = RecorderState.paused;
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    _snapshots.add(_buildSnapshot(now));
  }

  Future<void> resume() async {
    if (_state != RecorderState.paused) return;
    _state = RecorderState.recording;
    _periodStart = DateTime.now();
    await locationService.start(notification: _notification);
    _subscription = locationService.positions.listen(_onPosition);
  }

  Future<void> stop() async {
    if (_state != RecorderState.recording && _state != RecorderState.paused) {
      return;
    }
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    _state = RecorderState.stopped;

    final endTime = DateTime.now();
    _snapshots.add(_buildSnapshot(endTime));

    // Drain pending coordinate writes, then mark the walk finished.
    await _persist;
    await _repository.finishWalk(_id!, endTime);
  }

  void reset() {
    if (_state != RecorderState.stopped) return;
    _state = RecorderState.idle;
    _id = null;
    _startTime = null;
    _periodStart = null;
    _accumulatedDuration = Duration.zero;
    _coordinates.clear();
    _persist = Future<void>.value();
  }

  void dispose() {
    _subscription?.cancel();
    _snapshots.close();
  }

  void _onPosition(Position pos) {
    final coord = Coordinate(
      lat: pos.latitude,
      lng: pos.longitude,
      recordedAt: pos.timestamp,
    );
    final index = _coordinates.length;
    _coordinates.add(coord);
    _snapshots.add(_buildSnapshot(DateTime.now()));

    // Persist this point immediately, serialized after earlier writes.
    // Best-effort: a write failure mustn't kill recording, and the point is
    // still in memory for the live snapshot.
    final id = _id;
    if (id != null) {
      _persist = _persist.then((_) async {
        try {
          await _repository.appendCoordinate(id, coord, index);
        } catch (e) {
          debugPrint('WalkRecorder: failed to persist coordinate $index: $e');
        }
      });
    }
  }

  WalkSnapshot _buildSnapshot(DateTime now) {
    final polyline = _coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList();
    final dist = totalDistance(polyline);
    final elapsed = _periodStart != null
        ? _accumulatedDuration + now.difference(_periodStart!)
        : _accumulatedDuration;
    return WalkSnapshot(
      distanceMetres: dist,
      elapsed: elapsed,
      paceMinPerKm: pace(dist, elapsed),
      polyline: polyline,
    );
  }

  static String _generateId(DateTime t) =>
      'walk-${t.millisecondsSinceEpoch}-${Random().nextInt(0xFFFFFF).toRadixString(16)}';
}
