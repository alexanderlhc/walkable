import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:walkable/auto_stop.dart';
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

  /// Whether the location stream reported an error (e.g. location switched
  /// off, or a power-saving mode cutting GPS) and no fix has arrived since.
  /// Recording carries on regardless; this only lets the UI say so.
  final bool signalLost;

  /// While the auto-stop warning is active, the moving time left until the
  /// walk stops itself; null means no warning is active. See
  /// [WalkRecorder.autoStopGrace].
  final Duration? autoStopIn;

  const WalkSnapshot({
    required this.stats,
    required this.polyline,
    this.signalLost = false,
    this.autoStopIn,
  });
}

/// The recorder auto-stopped a walk: its moving time reached the limit in
/// force, or the walker chose "stop now" during the warning. Carries the saved
/// [walk] the way [WalkRecorder.stop] returns it: null when nothing could be
/// saved.
class AutoStop {
  final Walk? walk;

  /// The walk's configured limit.
  final AutoStopLimit limit;

  /// How many periods of [limit] were in force: one, plus one per "keep
  /// walking".
  final int periods;

  const AutoStop({required this.walk, required this.limit, this.periods = 1});

  /// The limit in force when the walk stopped, in whole hours.
  int get hours => limit.hours * periods;
}

class WalkRecorder {
  /// How much recording time may pass between periodic duration writes. The
  /// pause-aware duration lives only in memory, so these throttled writes are
  /// what crash recovery falls back on — see [WalkRepository.recoverOrphans].
  static const progressPersistInterval = Duration(seconds: 30);

  /// How much moving time before the auto-stop limit the warning starts.
  static const autoStopGrace = Duration(minutes: 5);

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

  // Set from the moment a stop (manual or auto) begins until its save is done,
  // so nothing landing in its async gaps — another stop, pause/resume, or
  // reset() — can finalize the walk twice or clear it mid-save.
  bool _stopping = false;

  String? _id;
  DateTime? _startTime;
  DateTime? _periodStart;
  // When the pause-aware duration was last written to the walk row, per the
  // injected clock; throttles the ticker's progress writes to one per
  // [progressPersistInterval] instead of one per tick.
  DateTime? _lastProgressPersist;
  Duration _accumulatedDuration = Duration.zero;
  // This walk's auto-stop limit, captured at start(). Null means Off.
  AutoStopLimit? _autoStopLimit;
  // How many periods of [_autoStopLimit] are in force: one, plus one per
  // "keep walking".
  int _autoStopPeriods = 1;
  // Whether the auto-stop warning is up. Only [_setAutoStopWarning] writes it.
  bool _autoStopWarning = false;
  final List<Coordinate> _coordinates = [];
  // Set by a position stream error, cleared by the next fix. See [_onError].
  bool _signalLost = false;
  StreamSubscription<Position>? _subscription;
  Timer? _ticker;
  ForegroundNotificationText? _notification;
  // Serializes incremental DB writes and lets stop() drain them before
  // finalizing the walk.
  Future<void> _persist = Future<void>.value();

  final StreamController<WalkSnapshot> _snapshots =
      StreamController<WalkSnapshot>.broadcast();
  Stream<WalkSnapshot> get snapshots => _snapshots.stream;

  final StreamController<AutoStop> _autoStops =
      StreamController<AutoStop>.broadcast();

  /// Walks the recorder auto-stopped. A manual [stop] never appears here —
  /// its caller already has the result.
  Stream<AutoStop> get autoStops => _autoStops.stream;

  WalkRecorder({
    required this.locationService,
    required WalkRepository repository,
    DateTime Function() now = DateTime.now,
  })  : _repository = repository,
        _now = now;

  /// With an [autoStopLimit], the walk stops and saves itself once its moving
  /// time reaches the limit, announced on [autoStops]; null (Off) records
  /// until stopped. The limit is captured here for this walk only, so a
  /// settings change mid-walk applies from the next walk.
  Future<LocationServiceResult> start({
    ForegroundNotificationText? notification,
    LocationConsent? foregroundConsent,
    LocationConsent? backgroundConsent,
    AutoStopLimit? autoStopLimit,
  }) async {
    if (_starting || _state != RecorderState.idle) {
      return LocationServiceResult.running;
    }
    _starting = true;
    _notification = notification;
    try {
      final result = await locationService.start(
        notification: notification,
        foregroundConsent: foregroundConsent,
        backgroundConsent: backgroundConsent,
      );
      if (result == LocationServiceResult.permissionDenied) {
        // Stay idle so the user can try again after granting permission.
        return LocationServiceResult.permissionDenied;
      }
      _state = RecorderState.recording;
      _autoStopLimit = autoStopLimit;
      _startTime = _now();
      _periodStart = _startTime;
      _id = _generateId(_startTime!);
      // Persist the walk row up front so an in-progress walk survives a kill.
      // Best-effort like the coordinate writes: a failure is logged rather
      // than left as an unhandled rejection that would poison the chain and
      // wedge stop().
      _persist =
          _repository.createWalk(_id!, _startTime!).catchError((Object e) {
        debugPrint('WalkRecorder: failed to persist walk $_id: $e');
      });
      _lastProgressPersist = _startTime;
      _subscription =
          locationService.positions.listen(_onPosition, onError: _onError);
      _startTicker();
      return LocationServiceResult.started;
    } finally {
      _starting = false;
    }
  }

  Future<void> pause() async {
    if (_stopping || _state != RecorderState.recording) return;
    final now = _now();
    _accumulatedDuration += now.difference(_periodStart!);
    _periodStart = null;
    _signalLost = false;
    // Paused time doesn't count, so the warning waits too; the first tick
    // after a resume inside the window raises it again.
    _setAutoStopWarning(false);
    _state = RecorderState.paused;
    _ticker?.cancel();
    _ticker = null;
    // Same rule as [_finalize]: a failed shutdown is logged, and the pause
    // still persists its progress and emits its snapshot.
    try {
      await _subscription?.cancel();
      await locationService.stop();
    } catch (e) {
      debugPrint('WalkRecorder: failed to stop location: $e');
    }
    _subscription = null;
    // Persist the pause-aware duration now that it just grew: pauses are the
    // moments where wall-clock inference would drift furthest, so this write
    // is what keeps a later crash recovery honest.
    _lastProgressPersist = now;
    _persistProgress(now);
    _snapshots.add(_buildSnapshot(now));
  }

  /// [foregroundConsent] gates the OS foreground-location prompt in the rare
  /// case the permission was revoked while paused — without it resume() stays
  /// paused rather than prompting with no preceding disclosure.
  Future<void> resume({LocationConsent? foregroundConsent}) async {
    if (_starting || _stopping || _state != RecorderState.paused) return;
    _starting = true;
    try {
      final result = await locationService.start(
        notification: _notification,
        foregroundConsent: foregroundConsent,
      );
      if (result == LocationServiceResult.permissionDenied) {
        // Stay paused: entering recording without a position stream would show
        // a counting timer while zero coordinates are captured.
        return;
      }
      _state = RecorderState.recording;
      _periodStart = _now();
      _subscription =
          locationService.positions.listen(_onPosition, onError: _onError);
      _startTicker();
    } finally {
      _starting = false;
    }
  }

  /// The 1-second snapshot ticker shared by start() and resume(). Also drives
  /// the periodic progress persistence, throttled to one write per
  /// [progressPersistInterval] of recording, and the auto-stop check.
  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != RecorderState.recording || _stopping) return;
      final now = _now();
      final stopAt = _autoStopAt;
      if (stopAt != null) {
        final elapsed = _elapsedAt(now);
        if (elapsed >= stopAt) {
          _autoStop();
          return;
        }
        if (elapsed >= stopAt - autoStopGrace) _setAutoStopWarning(true);
      }
      _snapshots.add(_buildSnapshot(now));
      final lastPersist = _lastProgressPersist;
      if (lastPersist == null ||
          now.difference(lastPersist) >= progressPersistInterval) {
        _lastProgressPersist = now;
        _persistProgress(now);
      }
    });
  }

  /// Writes the pause-aware duration as of [now] to the walk row, serialized
  /// on the persistence chain. Best-effort like the coordinate writes: a
  /// failure is logged and must never disturb recording or wedge stop().
  void _persistProgress(DateTime now) {
    final id = _id;
    if (id == null) return;
    final duration = _elapsedAt(now);
    _persist = _persist.then((_) async {
      try {
        await _repository.updateProgress(id, duration);
      } catch (e) {
        debugPrint('WalkRecorder: failed to persist progress for $id: $e');
      }
    });
  }

  /// Stops recording and finalizes the walk. Returns the finished walk as it
  /// was saved, hydrated with its coordinates, so the caller can present it
  /// without re-querying the repository. Returns null when the recorder wasn't
  /// running, or when persistence failed (the recorder still ends up stopped).
  Future<Walk?> stop() => _stop();

  /// While the auto-stop warning is active, moves the limit back by one more
  /// full period from the current limit (2 h → 4 h → 6 h …) and clears the
  /// warning. Does nothing when no warning is active.
  void keepWalking() {
    if (!_autoStopWarning || _stopping) return;
    _autoStopPeriods++;
    _setAutoStopWarning(false);
    _snapshots.add(_buildSnapshot(_now()));
  }

  /// While the auto-stop warning is active, stops the walk now through the
  /// same path as reaching the limit, so it is announced on [autoStops] too.
  /// Does nothing when no warning is active.
  Future<void> stopNow() async {
    if (!_autoStopWarning || _stopping) return;
    await _autoStop(endTime: _now());
  }

  /// Finalizes the walk exactly like [stop] and announces it. It ends at
  /// [endTime], but never past the moment moving time reached the limit — a
  /// tick (or a late "stop now") can land a little after it, and the saved
  /// duration must still not exceed the limit.
  Future<void> _autoStop({DateTime? endTime}) async {
    final limit = _autoStopLimit!;
    final stopAt = _autoStopAt!;
    // Both callers run only while recording, so the open period holds the
    // moment the limit is crossed.
    final limitEnd = _periodStart!.add(stopAt - _accumulatedDuration);
    final walk = await _stop(
        endTime:
            endTime == null || endTime.isAfter(limitEnd) ? limitEnd : endTime);
    if (!_autoStops.isClosed) {
      _autoStops.add(AutoStop(
        walk: walk,
        limit: limit,
        periods: _autoStopPeriods,
      ));
    }
  }

  /// Shared by [stop] and [_autoStop]. [endTime] defaults to now.
  Future<Walk?> _stop({DateTime? endTime}) async {
    if (_stopping ||
        (_state != RecorderState.recording && _state != RecorderState.paused)) {
      return null;
    }
    _stopping = true;
    // [_stopping] stays set until the save below completes: a pause/resume in
    // the teardown gap, or a reset() in the save gap (a manual stop racing an
    // auto-stop), would otherwise pull state out from under the walk.
    try {
      return await _finalize(endTime ?? _now());
    } finally {
      _stopping = false;
    }
  }

  Future<Walk?> _finalize(DateTime end) async {
    _ticker?.cancel();
    _ticker = null;
    _setAutoStopWarning(false);
    // Freeze moving time at [end] before the async teardown below: the walk
    // ended then, however long the teardown takes.
    if (_periodStart != null) {
      _accumulatedDuration += end.difference(_periodStart!);
      _periodStart = null;
    }
    // A failed shutdown must not cost the walk: it is over either way, so log
    // and go on to save it (and so stop() never throws).
    try {
      await _subscription?.cancel();
      await locationService.stop();
    } catch (e) {
      debugPrint('WalkRecorder: failed to stop location: $e');
    }
    _subscription = null;
    _state = RecorderState.stopped;

    _snapshots.add(_buildSnapshot(end));

    // Drain pending coordinate writes, then mark the walk finished with the
    // canonical pause-aware moving time, the total route distance, and the
    // simplified route preview (stored so the history list never has to
    // reload the coordinates). Best-effort: a persistence failure must not
    // leave stop() unfinished — the recorder still ends up stopped so it can
    // be reset and reused.
    try {
      await _persist;
      final coords = _coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList();
      await _repository.finishWalk(_id!, end, _elapsedAt(end),
          totalDistance(coords), simplifyRoute(coords));
      return await _repository.findById(_id!);
    } catch (e) {
      debugPrint('WalkRecorder: failed to finish walk $_id: $e');
      return null;
    }
  }

  void reset() {
    if (_stopping || _state != RecorderState.stopped) return;
    _state = RecorderState.idle;
    _id = null;
    _startTime = null;
    _periodStart = null;
    _lastProgressPersist = null;
    _accumulatedDuration = Duration.zero;
    _autoStopLimit = null;
    _autoStopPeriods = 1;
    _signalLost = false;
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
    _autoStops.close();
  }

  /// Errors forwarded by [LocationService.positions] (e.g. location services
  /// toggled off mid-walk, or a power-saving mode cutting GPS while the screen
  /// is locked). Keep recording: the error doesn't end the platform location
  /// request, so fixes resume on their own once location is back. Pausing
  /// here used to stop the foreground service for good, silently losing the
  /// rest of a walk over a momentary glitch the user — phone in pocket —
  /// never saw. Flag the gap instead so the UI can show it.
  void _onError(Object error) {
    debugPrint('WalkRecorder: position stream error: $error');
    if (_state != RecorderState.recording || _signalLost) return;
    _signalLost = true;
    _snapshots.add(_buildSnapshot(_now()));
  }

  void _onPosition(Position pos) {
    // A fix that lands after the walk ended — during a stop's teardown, or
    // past the auto-stop limit before the ticker notices — isn't part of it.
    final stopAt = _autoStopAt;
    if (_stopping || (stopAt != null && _elapsedAt(_now()) >= stopAt)) {
      return;
    }
    final coord = Coordinate(
      lat: pos.latitude,
      lng: pos.longitude,
      recordedAt: pos.timestamp,
    );
    final index = _coordinates.length;
    _coordinates.add(coord);
    _signalLost = false;
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

  /// The moving time at which the walk stops itself; null means Off.
  Duration? get _autoStopAt {
    final limit = _autoStopLimit;
    return limit == null ? null : limit.duration * _autoStopPeriods;
  }

  /// The one place the auto-stop warning is raised (by the ticker) or
  /// cleared (by keepWalking(), a pause and the stop itself).
  void _setAutoStopWarning(bool active) => _autoStopWarning = active;

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
      signalLost: _signalLost,
      autoStopIn: _autoStopWarning ? _autoStopAt! - _elapsedAt(now) : null,
    );
  }

  static String _generateId(DateTime t) =>
      'walk-${t.millisecondsSinceEpoch}-${Random().nextInt(0xFFFFFF).toRadixString(16)}';
}
