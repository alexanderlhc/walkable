import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_calculator.dart';
import 'package:walkable/walk_stats.dart';

enum RecorderState { idle, recording, paused, stopped }

class WalkSnapshot {
  /// The canonical stats (distance, duration, pace) for this moment.
  final WalkStats stats;

  /// The route so far, for drawing the live track.
  final List<Coord> polyline;

  const WalkSnapshot({required this.stats, required this.polyline});
}

class WalkRecorder {
  final LocationService locationService;
  final WalkRepository _repository;

  /// The clock used for every time read (start/pause/resume/stop timestamps
  /// and ticker snapshots). Injectable so tests can drive time
  /// deterministically; production uses the real clock.
  final DateTime Function() _now;

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  // Guards the async gap in start()/resume(): the state only flips after
  // locationService.start() succeeds, so without this a double-tap would pass
  // the state guard twice and run two full start flows (two walk rows, leaked
  // subscriptions/tickers).
  bool _starting = false;

  String? _id;
  DateTime? _startTime;
  DateTime? _periodStart;
  Duration _accumulatedDuration = Duration.zero;
  final List<Coordinate> _coordinates = [];
  StreamSubscription<Position>? _subscription;
  Timer? _ticker;
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
    DateTime Function() now = DateTime.now,
  })  : _repository = repository,
        _now = now;

  Future<LocationServiceResult> start({
    ForegroundNotificationText? notification,
  }) async {
    if (_starting || _state != RecorderState.idle) {
      return LocationServiceResult.running;
    }
    _starting = true;
    _notification = notification;
    try {
      final result = await locationService.start(notification: notification);
      if (result == LocationServiceResult.permissionDenied) {
        // Stay idle so the user can try again after granting permission.
        return LocationServiceResult.permissionDenied;
      }
      _state = RecorderState.recording;
      _startTime = _now();
      _periodStart = _startTime;
      _id = _generateId(_startTime!);
      // Persist the walk row up front so an in-progress walk survives a kill.
      // Best-effort like the coordinate writes: a failure is logged rather
      // than left as an unhandled rejection that would poison the chain and
      // wedge stop().
      _persist = _repository.createWalk(_id!, _startTime!).catchError((Object e) {
        debugPrint('WalkRecorder: failed to persist walk $_id: $e');
      });
      _subscription =
          locationService.positions.listen(_onPosition, onError: _onError);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state == RecorderState.recording) {
          _snapshots.add(_buildSnapshot(_now()));
        }
      });
      return LocationServiceResult.started;
    } finally {
      _starting = false;
    }
  }

  Future<void> pause() async {
    if (_state != RecorderState.recording) return;
    final now = _now();
    _accumulatedDuration += now.difference(_periodStart!);
    _periodStart = null;
    _state = RecorderState.paused;
    _ticker?.cancel();
    _ticker = null;
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    _snapshots.add(_buildSnapshot(now));
  }

  Future<void> resume() async {
    if (_starting || _state != RecorderState.paused) return;
    _starting = true;
    try {
      final result = await locationService.start(notification: _notification);
      if (result == LocationServiceResult.permissionDenied) {
        // Stay paused: entering recording without a position stream would show
        // a counting timer while zero coordinates are captured.
        return;
      }
      _state = RecorderState.recording;
      _periodStart = _now();
      _subscription =
          locationService.positions.listen(_onPosition, onError: _onError);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_state == RecorderState.recording) {
          _snapshots.add(_buildSnapshot(_now()));
        }
      });
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    if (_state != RecorderState.recording && _state != RecorderState.paused) {
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    await _subscription?.cancel();
    _subscription = null;
    await locationService.stop();
    _state = RecorderState.stopped;

    final endTime = _now();
    _snapshots.add(_buildSnapshot(endTime));

    // Drain pending coordinate writes, then mark the walk finished with the
    // canonical pause-aware moving time, the total route distance, and the
    // simplified route preview (stored so the history list never has to
    // reload the coordinates). Best-effort: a persistence failure must not
    // leave stop() unfinished — the recorder still ends up stopped so it can
    // be reset and reused.
    try {
      await _persist;
      final coords =
          _coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList();
      await _repository.finishWalk(_id!, endTime, _elapsedAt(endTime),
          totalDistance(coords), simplifyRoute(coords));
    } catch (e) {
      debugPrint('WalkRecorder: failed to finish walk $_id: $e');
    }
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
    // Emit a cleared snapshot so listeners drop the finished walk's polyline
    // instead of rendering it on the idle map (and into the next walk).
    if (!_snapshots.isClosed) {
      _snapshots.add(_buildSnapshot(_now()));
    }
  }

  void dispose() {
    _ticker?.cancel();
    _subscription?.cancel();
    _snapshots.close();
  }

  /// Errors forwarded by [LocationService.positions] (e.g. location services
  /// toggled off mid-walk). Pause instead of silently truncating the walk with
  /// the timer still counting; pause() also emits a snapshot so the UI reacts.
  void _onError(Object error) {
    debugPrint('WalkRecorder: position stream error: $error');
    if (_state == RecorderState.recording) {
      unawaited(pause());
    }
  }

  void _onPosition(Position pos) {
    final coord = Coordinate(
      lat: pos.latitude,
      lng: pos.longitude,
      recordedAt: pos.timestamp,
    );
    final index = _coordinates.length;
    _coordinates.add(coord);
    _snapshots.add(_buildSnapshot(_now()));

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

  /// Pause-aware moving time up to [now]: accumulated time plus the open
  /// recording period, or just the accumulated time while paused.
  Duration _elapsedAt(DateTime now) => _periodStart != null
      ? _accumulatedDuration + now.difference(_periodStart!)
      : _accumulatedDuration;

  WalkSnapshot _buildSnapshot(DateTime now) {
    final polyline = _coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList();
    return WalkSnapshot(
      stats:
          WalkStats.fromParts(coordinates: polyline, duration: _elapsedAt(now)),
      polyline: polyline,
    );
  }

  static String _generateId(DateTime t) =>
      'walk-${t.millisecondsSinceEpoch}-${Random().nextInt(0xFFFFFF).toRadixString(16)}';
}
