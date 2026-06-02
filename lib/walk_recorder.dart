import 'dart:async';
import 'dart:math';

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
  final LocationService _locationService;
  final WalkRepository _repository;

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  DateTime? _startTime;
  DateTime? _periodStart;
  Duration _accumulatedDuration = Duration.zero;
  final List<Coordinate> _coordinates = [];
  StreamSubscription<Position>? _subscription;

  final StreamController<WalkSnapshot> _snapshots =
      StreamController<WalkSnapshot>.broadcast();
  Stream<WalkSnapshot> get snapshots => _snapshots.stream;

  WalkRecorder({
    required LocationService locationService,
    required WalkRepository repository,
  })  : _locationService = locationService,
        _repository = repository;

  Future<LocationServiceResult> start() async {
    if (_state != RecorderState.idle) return LocationServiceResult.running;
    final result = await _locationService.start();
    if (result == LocationServiceResult.permissionDenied) {
      return LocationServiceResult.permissionDenied;
    }
    _state = RecorderState.recording;
    _startTime = DateTime.now();
    _periodStart = _startTime;
    _subscription = _locationService.positions.listen(_onPosition);
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
    await _locationService.stop();
    _snapshots.add(_buildSnapshot(now));
  }

  Future<void> resume() async {
    if (_state != RecorderState.paused) return;
    _state = RecorderState.recording;
    _periodStart = DateTime.now();
    await _locationService.start();
    _subscription = _locationService.positions.listen(_onPosition);
  }

  Future<void> stop() async {
    if (_state != RecorderState.recording && _state != RecorderState.paused) {
      return;
    }
    await _subscription?.cancel();
    _subscription = null;
    await _locationService.stop();
    _state = RecorderState.stopped;

    final endTime = DateTime.now();
    _snapshots.add(_buildSnapshot(endTime));

    final walk = Walk(
      id: _generateId(_startTime!),
      startTime: _startTime!,
      endTime: endTime,
      coordinates: List.of(_coordinates),
    );
    await _repository.save(walk);
  }

  void reset() {
    if (_state != RecorderState.stopped) return;
    _state = RecorderState.idle;
    _startTime = null;
    _periodStart = null;
    _accumulatedDuration = Duration.zero;
    _coordinates.clear();
  }

  void dispose() {
    _subscription?.cancel();
    _snapshots.close();
  }

  void _onPosition(Position pos) {
    _coordinates.add(Coordinate(
      lat: pos.latitude,
      lng: pos.longitude,
      recordedAt: pos.timestamp,
    ));
    _snapshots.add(_buildSnapshot(DateTime.now()));
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
