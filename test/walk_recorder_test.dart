import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:walkable/auto_stop.dart';
import 'package:walkable/auto_stop_alerts.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_calculator.dart';
import 'package:walkable/walk_recorder.dart';

class _StubLocationService extends LocationService {
  final StreamController<Position> _ctrl =
      StreamController<Position>.broadcast();

  /// What the next [start] call returns (e.g. permissionDenied).
  LocationServiceResult startResult = LocationServiceResult.started;

  /// When set, [start] suspends until the completer fires — lets tests hold
  /// the recorder inside start()'s async gap.
  Completer<void>? startGate;

  /// When set, [stop] suspends until the completer fires — lets tests hold
  /// the recorder inside a stop's teardown.
  Completer<void>? stopGate;

  /// When true, [stop] throws (e.g. the platform channel failed).
  bool failStop = false;

  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<LocationServiceResult> start({
    ForegroundNotificationText? notification,
    LocationConsent? foregroundConsent,
    LocationConsent? backgroundConsent,
  }) async {
    startCalls++;
    final gate = startGate;
    if (gate != null) await gate.future;
    return startResult;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    final gate = stopGate;
    if (gate != null) await gate.future;
    if (failStop) throw StateError('location stop rejected');
  }

  @override
  Stream<Position> get positions => _ctrl.stream;

  void emit(Position pos) => _ctrl.add(pos);

  void emitError(Object error) => _ctrl.addError(error);

  @override
  void dispose() => _ctrl.close();
}

/// Deterministic clock injected into the recorder: time only moves when a
/// test advances it, so elapsed-time assertions can be exact instead of
/// sleeping on the real clock.
class _FakeClock {
  DateTime current = DateTime(2026, 1, 1, 12);

  DateTime now() => current;

  void advance(Duration d) => current = current.add(d);
}

/// Delegates to a real repository but can be told to reject individual
/// operations, reproducing the persistence failures the recorder must
/// survive. Methods are async so a failure surfaces as a rejected future —
/// the shape of the original bug — rather than a synchronous throw.
///
/// The inner repository is optional: without one every operation is a no-op,
/// which keeps the double usable inside fakeAsync where a real sqflite call
/// (served from another isolate) would never complete.
class _FlakyWalkRepository implements WalkRepository {
  final WalkRepository? _inner;

  _FlakyWalkRepository([this._inner]);

  bool failCreateWalk = false;
  bool failAppendCoordinate = false;
  bool failFinishWalk = false;
  bool failUpdateProgress = false;

  /// When set, [finishWalk] suspends until the completer fires — lets tests
  /// hold the recorder inside a stop's save.
  Completer<void>? finishGate;

  /// Every duration passed to [updateProgress], including rejected calls.
  final List<Duration> updateProgressCalls = [];

  /// Without an inner repository, the walk the last successful [finishWalk]
  /// described — so [findById] can hand back a saved walk under fakeAsync.
  Walk? _finished;

  @override
  Future<void> createWalk(String id, DateTime startTime) async {
    if (failCreateWalk) throw StateError('createWalk rejected');
    await _inner?.createWalk(id, startTime);
  }

  @override
  Future<void> appendCoordinate(
      String walkId, Coordinate coord, int sequenceIndex) async {
    if (failAppendCoordinate) throw StateError('appendCoordinate rejected');
    await _inner?.appendCoordinate(walkId, coord, sequenceIndex);
  }

  @override
  Future<void> finishWalk(String walkId, DateTime endTime, Duration duration,
      double distanceMetres, List<Coord> route) async {
    final gate = finishGate;
    if (gate != null) await gate.future;
    if (failFinishWalk) throw StateError('finishWalk rejected');
    if (_inner == null) {
      _finished = Walk(
        id: walkId,
        startTime: endTime.subtract(duration),
        endTime: endTime,
        duration: duration,
        distanceMetres: distanceMetres,
        route: route,
      );
    }
    await _inner?.finishWalk(walkId, endTime, duration, distanceMetres, route);
  }

  @override
  Future<void> updateProgress(String id, Duration duration) async {
    updateProgressCalls.add(duration);
    if (failUpdateProgress) throw StateError('updateProgress rejected');
    await _inner?.updateProgress(id, duration);
  }

  @override
  Future<int> recoverOrphans() async => await _inner?.recoverOrphans() ?? 0;

  @override
  Future<void> save(Walk walk) async => _inner?.save(walk);

  @override
  Future<Walk?> findById(String id) async {
    final inner = _inner;
    if (inner != null) return inner.findById(id);
    return _finished?.id == id ? _finished : null;
  }

  @override
  Future<List<Walk>> findAll() async => await _inner?.findAll() ?? const [];

  @override
  Future<void> close() async => _inner?.close();
}

/// A [_StubLocationService] whose position subscriptions cancel with a future
/// from the current zone. A broadcast subscription's cancel() returns a
/// root-zone future that fakeAsync can never flush, which would hang every
/// awaited cancel in pause() and stop().
class _FakeAsyncLocationService extends _StubLocationService {
  @override
  Stream<Position> get positions {
    late StreamSubscription<Position> inner;
    late final StreamController<Position> ctrl;
    ctrl = StreamController<Position>(
      onListen: () =>
          inner = super.positions.listen(ctrl.add, onError: ctrl.addError),
      onCancel: () async {
        unawaited(inner.cancel());
      },
    );
    return ctrl.stream;
  }
}

/// Records every call the recorder makes on its auto-stop alerts port, in
/// order. Can be told to throw, as a broken notification plugin might.
class _FakeAutoStopAlerts implements AutoStopAlerts {
  final List<String> calls = [];
  // The time left passed with each showWarning call.
  final List<Duration> warningTimeLeft = [];
  bool fail = false;

  Future<void> _record(String call) async {
    calls.add(call);
    if (fail) throw StateError('$call rejected');
  }

  @override
  Future<void> showWarning(Duration timeLeft) {
    warningTimeLeft.add(timeLeft);
    return _record('showWarning');
  }

  @override
  Future<void> cancelWarning() => _record('cancelWarning');

  @override
  Future<void> showStoppedNotice() => _record('showStoppedNotice');
}

/// One fakeAsync auto-stop scenario: a recorder on the fake clock with the
/// no-op flaky repository and the fake alerts port, plus every auto-stop
/// event it emits.
class _AutoStopHarness {
  final FakeAsync async;
  final location = _FakeAsyncLocationService();
  final clock = _FakeClock();
  final flaky = _FlakyWalkRepository();
  final alerts = _FakeAutoStopAlerts();
  late final WalkRecorder recorder = WalkRecorder(
    locationService: location,
    repository: flaky,
    alerts: alerts,
    now: clock.now,
  );
  final List<AutoStop> autoStops = [];
  final List<WalkSnapshot> snapshots = [];
  late final StreamSubscription<AutoStop> _sub;
  late final StreamSubscription<WalkSnapshot> _snapshotSub;

  _AutoStopHarness(this.async) {
    _sub = recorder.autoStops.listen(autoStops.add);
    _snapshotSub = recorder.snapshots.listen(snapshots.add);
  }

  /// The moving time left until auto-stop per the latest snapshot; null when
  /// no warning is active.
  Duration? get autoStopIn => snapshots.last.autoStopIn;

  void flush() => async.flushMicrotasks();

  /// Advances clock and ticker in lockstep, one tick at a time, like the
  /// real 1-second ticker experiences time.
  void record(Duration d) {
    for (var i = 0; i < d.inSeconds; i++) {
      clock.advance(const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 1));
    }
    flush();
  }

  void dispose() {
    _sub.cancel();
    _snapshotSub.cancel();
    recorder.dispose();
    location.dispose();
    flush();
  }
}

Position _pos(double lat, double lng) => Position(
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
  late _StubLocationService location;
  late _FakeClock clock;
  late WalkRepository repository;
  late _FlakyWalkRepository flaky;
  late WalkRecorder recorder;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    location = _StubLocationService();
    clock = _FakeClock();
    repository = await WalkRepository.inMemory();
    flaky = _FlakyWalkRepository(repository);
    recorder = WalkRecorder(
      locationService: location,
      repository: flaky,
      now: clock.now,
    );
  });

  tearDown(() async {
    recorder.dispose();
    location.dispose();
    await repository.close();
  });

  test('initial state is idle', () {
    expect(recorder.state, RecorderState.idle);
  });

  test('start transitions to recording', () async {
    await recorder.start();
    expect(recorder.state, RecorderState.recording);
  });

  test('stop from idle does nothing and returns no walk', () async {
    expect(await recorder.stop(), isNull);
    expect(recorder.state, RecorderState.idle);
  });

  test('stop transitions to stopped', () async {
    await recorder.start();
    await recorder.stop();
    expect(recorder.state, RecorderState.stopped);
  });

  test('a failed location shutdown still saves the walk', () async {
    await recorder.start();
    location.emit(_pos(55.676, 12.568));
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);
    clock.advance(const Duration(seconds: 30));
    location.failStop = true;

    final walk = await recorder.stop();

    expect(recorder.state, RecorderState.stopped);
    expect(walk, isNotNull);
    expect(walk!.duration, const Duration(seconds: 30));
    expect(walk.coordinates.length, 2);
  });

  test('stop returns the saved walk hydrated with its coordinates', () async {
    await recorder.start();
    location.emit(_pos(55.676, 12.568));
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);
    clock.advance(const Duration(seconds: 30));

    final walk = await recorder.stop();

    expect(walk, isNotNull);
    expect(walk!.endTime, isNotNull);
    expect(walk.duration, const Duration(seconds: 30));
    expect(walk.distanceMetres, greaterThan(0));
    expect(walk.coordinates.length, 2);
    // And it is the walk the repository now lists — not a detached copy.
    final listed = await repository.findAll();
    expect(listed.single.id, walk.id);
  });

  test('reset after stop returns to idle', () async {
    await recorder.start();
    await recorder.stop();
    recorder.reset();
    expect(recorder.state, RecorderState.idle);
  });

  test('each position updates polyline and distance in snapshot', () async {
    await recorder.start();

    final snapshots = <WalkSnapshot>[];
    final sub = recorder.snapshots.listen(snapshots.add);

    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);

    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();

    expect(snapshots.length, 2);
    expect(snapshots[0].polyline.length, 1);
    expect(snapshots[1].polyline.length, 2);
    expect(snapshots[1].stats.distanceMetres, greaterThan(0));
  });

  test('snapshot exposes distance, elapsed, pace, and polyline', () async {
    await recorder.start();

    WalkSnapshot? latest;
    final sub = recorder.snapshots.listen((s) => latest = s);

    location.emit(_pos(55.676, 12.568));
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();

    expect(latest, isNotNull);
    expect(latest!.stats.distanceMetres, greaterThan(0));
    expect(latest!.stats.duration, greaterThanOrEqualTo(Duration.zero));
    expect(latest!.stats.paceMinPerKm, isNot(double.infinity));
    expect(latest!.polyline.length, 2);
  });

  test('pause transitions recording to paused', () async {
    await recorder.start();
    await recorder.pause();
    expect(recorder.state, RecorderState.paused);
  });

  test('resume transitions paused to recording', () async {
    await recorder.start();
    await recorder.pause();
    await recorder.resume();
    expect(recorder.state, RecorderState.recording);
  });

  test('stop from paused transitions to stopped', () async {
    await recorder.start();
    await recorder.pause();
    await recorder.stop();
    expect(recorder.state, RecorderState.stopped);
  });

  test('a failed location shutdown still completes the pause', () async {
    await recorder.start();
    final snapshots = <WalkSnapshot>[];
    final sub = recorder.snapshots.listen(snapshots.add);
    clock.advance(const Duration(seconds: 20));
    location.failStop = true;

    await recorder.pause();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.state, RecorderState.paused);
    expect(flaky.updateProgressCalls, [const Duration(seconds: 20)]);
    expect(snapshots.last.stats.duration, const Duration(seconds: 20));
    await sub.cancel();
  });

  test('resume and stop work after a pause whose shutdown failed', () async {
    await recorder.start();
    clock.advance(const Duration(seconds: 20));
    location.failStop = true;
    await recorder.pause();
    location.failStop = false;

    clock.advance(const Duration(seconds: 50));
    await recorder.resume();
    expect(recorder.state, RecorderState.recording);
    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);
    clock.advance(const Duration(seconds: 10));

    final walk = await recorder.stop();

    expect(recorder.state, RecorderState.stopped);
    expect(walk!.duration, const Duration(seconds: 30));
    expect(walk.coordinates.length, 1);
  });

  test('no coordinates added while paused', () async {
    await recorder.start();
    await recorder.pause();

    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);

    await recorder.stop();
    final walks = await repository.findAll();
    // findAll doesn't hydrate coordinates; check the full walk.
    final walk = await repository.findById(walks[0].id);
    expect(walk!.coordinates, isEmpty);
  });

  test('elapsed does not grow during pause gap', () async {
    await recorder.start();

    final snapshots = <WalkSnapshot>[];
    final sub = recorder.snapshots.listen(snapshots.add);

    clock.advance(const Duration(seconds: 5));
    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);

    expect(snapshots.last.stats.duration, const Duration(seconds: 5));
    await recorder.pause();

    // The pause gap: the clock keeps moving while the recorder is paused.
    clock.advance(const Duration(seconds: 50));

    await recorder.resume();
    clock.advance(const Duration(seconds: 3));
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();

    // Elapsed is exactly the time spent recording (5s + 3s) — none of the
    // 50s pause gap leaked in.
    expect(snapshots.last.stats.duration, const Duration(seconds: 8));
  });

  test('concurrent start calls run only one start flow', () async {
    location.startGate = Completer<void>();

    final first = recorder.start();
    final second = recorder.start(); // double-tap inside start()'s async gap
    location.startGate!.complete();
    final results = await Future.wait([first, second]);

    expect(results.where((r) => r == LocationServiceResult.started).length, 1);
    expect(results.where((r) => r == LocationServiceResult.running).length, 1);
    expect(location.startCalls, 1);
    expect(recorder.state, RecorderState.recording);

    // Only one walk row was created, and positions are not duplicated by a
    // leaked second subscription.
    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);
    await recorder.stop();

    final walks = await repository.findAll();
    expect(walks.length, 1);
    expect(walks[0].endTime, isNotNull);
    final full = await repository.findById(walks[0].id);
    expect(full!.coordinates.length, 1);
  });

  test('start stays idle when permission is denied', () async {
    location.startResult = LocationServiceResult.permissionDenied;

    final result = await recorder.start();

    expect(result, LocationServiceResult.permissionDenied);
    expect(recorder.state, RecorderState.idle);

    // The recorder is still usable once permission is granted.
    location.startResult = LocationServiceResult.started;
    expect(await recorder.start(), LocationServiceResult.started);
    expect(recorder.state, RecorderState.recording);
  });

  test('resume stays paused when permission is denied', () async {
    await recorder.start();
    await recorder.pause();

    location.startResult = LocationServiceResult.permissionDenied;
    await recorder.resume();
    expect(recorder.state, RecorderState.paused);

    // No coordinates sneak in while denied.
    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);

    // A later resume with permission granted works again.
    location.startResult = LocationServiceResult.started;
    await recorder.resume();
    expect(recorder.state, RecorderState.recording);

    await recorder.stop();
    final walks = await repository.findAll();
    expect(walks[0].coordinates, isEmpty);
  });

  test('reset emits a cleared snapshot', () async {
    await recorder.start();
    location.emit(_pos(55.676, 12.568));
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);
    await recorder.stop();

    WalkSnapshot? latest;
    final sub = recorder.snapshots.listen((s) => latest = s);

    recorder.reset();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(latest, isNotNull);
    expect(latest!.polyline, isEmpty);
    expect(latest!.stats.distanceMetres, 0);
  });

  test(
      'position stream error keeps recording, flags signal loss until the '
      'next fix', () async {
    final snapshots = <WalkSnapshot>[];
    final sub = recorder.snapshots.listen(snapshots.add);
    await recorder.start();
    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);

    location.emitError(StateError('location services disabled'));
    await Future<void>.delayed(Duration.zero);

    // Pausing here once stopped the foreground service for the rest of the
    // walk over a momentary glitch; the walk must keep going instead.
    expect(recorder.state, RecorderState.recording);
    expect(snapshots.last.signalLost, isTrue);

    // Location comes back: fixes keep arriving on the same subscription.
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(snapshots.last.signalLost, isFalse);
    expect(snapshots.last.polyline.length, 2);
    final walk = await recorder.stop();
    expect(walk!.coordinates.length, 2);
  });

  test('stop emits final snapshot and saves walk to repository', () async {
    await recorder.start();

    location.emit(_pos(55.676, 12.568));
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);

    final stopSnapshots = <WalkSnapshot>[];
    final sub = recorder.snapshots.listen(stopSnapshots.add);

    await recorder.stop();
    await sub.cancel();

    expect(recorder.state, RecorderState.stopped);
    expect(stopSnapshots.length, 1);

    final walks = await repository.findAll();
    expect(walks.length, 1);
    expect(walks[0].endTime, isNotNull);
    // The persisted duration is the canonical pause-aware moving time — the
    // same value shown in the final emitted snapshot, not endTime - startTime.
    expect(walks[0].duration, isNotNull);
    expect(walks[0].duration!.inMilliseconds,
        stopSnapshots.single.stats.duration!.inMilliseconds);
    // The route distance is persisted on finish so the history list can show
    // it without loading the coordinates findAll deliberately skips.
    expect(walks[0].coordinates, isEmpty);
    expect(walks[0].distanceMetres, stopSnapshots.single.stats.distanceMetres);

    final full = await repository.findById(walks[0].id);
    expect(full!.coordinates.length, 2);
  });

  // Regression coverage for the persistence-failure paths in stop(): a
  // rejected createWalk future once went unhandled, poisoning the _persist
  // chain so stop() never completed and the recorder was wedged in `stopped`
  // forever. flutter_test fails a test on any unhandled async error raised in
  // its zone, so these tests also guarantee no rejection escapes the recorder.
  group('persistence failures', () {
    test('stop completes and recorder is reusable when createWalk fails',
        () async {
      flaky.failCreateWalk = true;

      expect(await recorder.start(), LocationServiceResult.started);
      expect(recorder.state, RecorderState.recording);

      location.emit(_pos(55.676, 12.568));
      await Future<void>.delayed(Duration.zero);

      // Must complete without throwing; no walk was saved to return.
      expect(await recorder.stop(), isNull);
      expect(recorder.state, RecorderState.stopped);

      // The failed walk never reached the database.
      expect(await repository.findAll(), isEmpty);

      recorder.reset();
      expect(recorder.state, RecorderState.idle);

      // A subsequent cycle with a healthy repository records normally.
      flaky.failCreateWalk = false;
      clock.advance(const Duration(minutes: 1));
      expect(await recorder.start(), LocationServiceResult.started);
      location.emit(_pos(55.676, 12.568));
      location.emit(_pos(55.677, 12.569));
      await Future<void>.delayed(Duration.zero);
      clock.advance(const Duration(seconds: 30));
      await recorder.stop();

      final walks = await repository.findAll();
      expect(walks.length, 1);
      expect(walks.single.endTime, isNotNull);
      expect(walks.single.duration, const Duration(seconds: 30));
      expect(walks.single.distanceMetres, greaterThan(0));
      final full = await repository.findById(walks.single.id);
      expect(full!.coordinates.length, 2);
    });

    test('stop completes and recorder is reusable when finishWalk fails',
        () async {
      await recorder.start();
      location.emit(_pos(55.676, 12.568));
      await Future<void>.delayed(Duration.zero);

      flaky.failFinishWalk = true;
      // Must complete without throwing; the unfinished walk isn't returned.
      expect(await recorder.stop(), isNull);
      expect(recorder.state, RecorderState.stopped);

      // The walk row exists but was never finished, so history excludes it.
      expect(await repository.findAll(), isEmpty);

      recorder.reset();
      expect(recorder.state, RecorderState.idle);

      flaky.failFinishWalk = false;
      clock.advance(const Duration(minutes: 1));
      expect(await recorder.start(), LocationServiceResult.started);
      location.emit(_pos(55.676, 12.568));
      location.emit(_pos(55.677, 12.569));
      await Future<void>.delayed(Duration.zero);
      await recorder.stop();

      final walks = await repository.findAll();
      expect(walks.length, 1);
      expect(walks.single.endTime, isNotNull);
      final full = await repository.findById(walks.single.id);
      expect(full!.coordinates.length, 2);
    });

    test('recording survives appendCoordinate failures', () async {
      await recorder.start();

      flaky.failAppendCoordinate = true;
      location.emit(_pos(55.676, 12.568));
      location.emit(_pos(55.677, 12.569));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.state, RecorderState.recording);

      await recorder.stop();
      expect(recorder.state, RecorderState.stopped);

      // The walk still finishes with stats from the in-memory route, even
      // though the individual points never reached the database.
      final walks = await repository.findAll();
      expect(walks.length, 1);
      expect(walks.single.distanceMetres, greaterThan(0));
      final full = await repository.findById(walks.single.id);
      expect(full!.coordinates, isEmpty);
    });
  });

  // The pause-aware duration exists only in the recorder's memory; these
  // periodic writes are what crash recovery falls back on. See
  // WalkRepository.recoverOrphans.
  group('progress persistence', () {
    test('ticker writes progress once per 30 s of recording, not per tick', () {
      fakeAsync((async) {
        // Rebuilt inside the fakeAsync zone (the ticker must be created
        // here), and with no inner repository: a real sqflite call is served
        // from another isolate and would never complete under fakeAsync.
        final location = _StubLocationService();
        final clock = _FakeClock();
        final flaky = _FlakyWalkRepository();
        final recorder = WalkRecorder(
          locationService: location,
          repository: flaky,
          now: clock.now,
        );
        recorder.start();
        async.flushMicrotasks();
        expect(recorder.state, RecorderState.recording);

        // Drive the fake clock and the ticker in lockstep, one tick at a
        // time, like the real 1-second ticker experiences time.
        void record(Duration d) {
          for (var i = 0; i < d.inSeconds; i++) {
            clock.advance(const Duration(seconds: 1));
            async.elapse(const Duration(seconds: 1));
          }
          async.flushMicrotasks();
        }

        // 29 ticks: below the throttle interval, nothing written yet.
        record(const Duration(seconds: 29));
        expect(flaky.updateProgressCalls, isEmpty);

        // The 30th tick crosses the interval: exactly one write, carrying
        // the pause-aware duration at that moment.
        record(const Duration(seconds: 1));
        expect(flaky.updateProgressCalls, [const Duration(seconds: 30)]);

        // Another full minute: one write per further 30 s — 60 more ticks
        // yield exactly two more writes, not sixty.
        record(const Duration(minutes: 1));
        expect(flaky.updateProgressCalls, [
          const Duration(seconds: 30),
          const Duration(seconds: 60),
          const Duration(seconds: 90),
        ]);

        recorder.dispose();
        location.dispose();
        async.flushMicrotasks();
      });
    });

    test('pause writes the accumulated duration', () async {
      await recorder.start();
      clock.advance(const Duration(seconds: 42));

      await recorder.pause();
      // Let the serialized persistence chain run the write.
      await Future<void>.delayed(Duration.zero);

      expect(flaky.updateProgressCalls, [const Duration(seconds: 42)]);
    });

    test('recording survives updateProgress failures', () async {
      flaky.failUpdateProgress = true;

      await recorder.start();
      location.emit(_pos(55.676, 12.568));
      await Future<void>.delayed(Duration.zero);

      clock.advance(const Duration(seconds: 42));
      await recorder.pause(); // triggers a progress write that rejects
      // Drain the serialized persistence chain: the progress write is queued
      // behind createWalk's real sqlite write, so a single event-loop turn
      // isn't always enough (this was a flaky race).
      while (flaky.updateProgressCalls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(recorder.state, RecorderState.paused);
      expect(flaky.updateProgressCalls, hasLength(1));

      // The walk continues and still finishes normally afterwards.
      await recorder.resume();
      location.emit(_pos(55.677, 12.569));
      await Future<void>.delayed(Duration.zero);
      await recorder.stop();

      final walks = await repository.findAll();
      expect(walks.length, 1);
      expect(walks.single.duration, const Duration(seconds: 42));
      final full = await repository.findById(walks.single.id);
      expect(full!.coordinates.length, 2);
    });
  });

  test('stop stores a simplified route for the history preview', () async {
    await recorder.start();

    // Three fixes with a collinear midpoint the simplifier drops.
    location.emit(_pos(55.676, 12.568));
    location.emit(_pos(55.677, 12.568));
    location.emit(_pos(55.678, 12.568));
    await Future<void>.delayed(Duration.zero);

    await recorder.stop();

    final walks = await repository.findAll();
    expect(walks.single.route, [
      (lat: 55.676, lng: 12.568),
      (lat: 55.678, lng: 12.568),
    ]);
    // The full recording is untouched — only the preview is simplified.
    final full = await repository.findById(walks.single.id);
    expect(full!.coordinates.length, 3);
  });

  // Auto-stop counts pause-aware moving time on the recorder's own 1-second
  // ticker, so these drive the fake clock and the ticker in lockstep under
  // fakeAsync, like the progress-persistence test above.
  group('auto-stop', () {
    const limit = AutoStopLimit.oneHour;
    final limitTime = limit.duration;

    /// Runs [body] inside fakeAsync with a fresh recorder whose repository is
    /// the no-op flaky double (real sqflite never completes under fakeAsync).
    void autoStopTest(void Function(_AutoStopHarness h) body) {
      fakeAsync((async) {
        final h = _AutoStopHarness(async);
        body(h);
        h.dispose();
      });
    }

    test('with Off, the recorder never stops a walk on its own', () {
      autoStopTest((h) {
        h.recorder.start();
        h.flush();

        h.record(const Duration(hours: 10));

        expect(h.recorder.state, RecorderState.recording);
        expect(h.autoStops, isEmpty);
      });
    });

    test('keeps recording until moving time reaches the limit', () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();

        h.record(limitTime - const Duration(seconds: 1));

        expect(h.recorder.state, RecorderState.recording);
        expect(h.autoStops, isEmpty);
      });
    });

    test(
        'stops and saves the walk at the limit; the auto-stop event carries '
        'the saved walk', () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();
        h.location.emit(_pos(55.676, 12.568));
        h.location.emit(_pos(55.677, 12.569));
        h.flush();

        h.record(limitTime);

        expect(h.recorder.state, RecorderState.stopped);
        // Location and the foreground service shut down, as on a manual stop.
        expect(h.location.stopCalls, 1);
        expect(h.autoStops, hasLength(1));
        final walk = h.autoStops.single.walk;
        expect(walk, isNotNull);
        expect(walk!.duration, limitTime);
        expect(walk.distanceMetres, greaterThan(0));
        expect(h.autoStops.single.limit, limit);
      });
    });

    test('the saved duration equals the limit even when a tick runs late', () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();

        h.record(limitTime - const Duration(seconds: 1));
        // The next tick lands 20 s late (e.g. a throttled background
        // process): moving time is already past the limit when it fires.
        h.clock.advance(const Duration(seconds: 21));
        h.async.elapse(const Duration(seconds: 1));
        h.flush();

        expect(h.recorder.state, RecorderState.stopped);
        expect(h.autoStops.single.walk!.duration, limitTime);
      });
    });

    test('paused time does not count; resuming continues the countdown', () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();

        h.record(const Duration(minutes: 40));
        h.recorder.pause();
        h.flush();
        // A long café stop: far past the limit in wall-clock time.
        h.record(const Duration(hours: 3));
        expect(h.recorder.state, RecorderState.paused);
        expect(h.autoStops, isEmpty);

        h.recorder.resume();
        h.flush();
        h.record(const Duration(minutes: 20) - const Duration(seconds: 1));
        expect(h.recorder.state, RecorderState.recording);

        h.record(const Duration(seconds: 1));
        expect(h.recorder.state, RecorderState.stopped);
        expect(h.autoStops.single.walk!.duration, limitTime);
      });
    });

    test('a signal-lost spell does not affect the countdown', () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();

        h.record(const Duration(minutes: 10));
        h.location.emitError(StateError('location off'));
        h.flush();
        h.record(const Duration(minutes: 30));
        h.location.emit(_pos(55.676, 12.568));
        h.flush();
        h.record(const Duration(minutes: 20) - const Duration(seconds: 1));
        expect(h.recorder.state, RecorderState.recording);

        h.record(const Duration(seconds: 1));
        expect(h.recorder.state, RecorderState.stopped);
        expect(h.autoStops.single.walk!.duration, limitTime);
      });
    });

    test('the limit is captured per walk, not carried into the next one', () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();
        h.record(limitTime);
        expect(h.recorder.state, RecorderState.stopped);
        h.recorder.reset();

        // The next walk starts with auto-stop Off.
        h.recorder.start();
        h.flush();
        h.record(const Duration(hours: 5));
        expect(h.recorder.state, RecorderState.recording);
        expect(h.autoStops, hasLength(1));
      });
    });

    test('a manual stop before the limit emits no auto-stop event', () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();
        h.record(const Duration(minutes: 30));

        h.recorder.stop();
        h.flush();
        h.record(const Duration(hours: 2));

        expect(h.recorder.state, RecorderState.stopped);
        expect(h.autoStops, isEmpty);
      });
    });

    test(
        'a manual stop and reset during the auto-stop\'s save do not lose '
        'the walk', () {
      autoStopTest((h) {
        h.flaky.finishGate = Completer<void>();
        h.recorder.start(autoStopLimit: limit);
        h.flush();
        h.record(limitTime);
        // Teardown is done, the save is still in flight.
        expect(h.recorder.state, RecorderState.stopped);

        // The walk screen's Back dialog: the user confirms Stop now.
        Walk? manual;
        h.recorder.stop().then((w) => manual = w);
        h.flush();
        h.recorder.reset();

        h.flaky.finishGate!.complete();
        h.flush();

        expect(manual, isNull);
        expect(h.autoStops.single.walk!.duration, limitTime);
        h.recorder.reset();
        expect(h.recorder.state, RecorderState.idle);
      });
    });

    test('a pause during the auto-stop\'s teardown is ignored', () {
      autoStopTest((h) {
        h.location.stopGate = Completer<void>();
        h.recorder.start(autoStopLimit: limit);
        h.flush();
        h.record(limitTime);

        Object? error;
        h.recorder.pause().catchError((Object e) => error = e);
        h.flush();
        h.location.stopGate!.complete();
        h.flush();

        expect(error, isNull);
        expect(h.recorder.state, RecorderState.stopped);
        expect(h.autoStops.single.walk!.duration, limitTime);
      });
    });

    test(
        'a failed location shutdown during the auto-stop still saves and '
        'announces the walk', () {
      autoStopTest((h) {
        h.location.failStop = true;
        h.recorder.start(autoStopLimit: limit);
        h.flush();

        h.record(limitTime);

        expect(h.recorder.state, RecorderState.stopped);
        expect(h.autoStops.single.walk!.duration, limitTime);
        h.recorder.reset();
        expect(h.recorder.state, RecorderState.idle);
      });
    });

    test('fixes arriving after the limit, before the tick, are not recorded',
        () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();
        h.location.emit(_pos(55.676, 12.568));
        h.location.emit(_pos(55.677, 12.569));
        h.flush();
        h.record(limitTime - const Duration(seconds: 1));

        // The limit is crossed between ticks; a fix lands before the late
        // tick notices.
        h.clock.advance(const Duration(milliseconds: 1500));
        h.location.emit(_pos(55.700, 12.600));
        h.flush();
        h.async.elapse(const Duration(seconds: 1));
        h.flush();

        final walk = h.autoStops.single.walk!;
        expect(walk.duration, limitTime);
        expect(walk.route, [
          (lat: 55.676, lng: 12.568),
          (lat: 55.677, lng: 12.569),
        ]);
      });
    });

    test('a resume during a manual stop of a paused walk is ignored', () {
      autoStopTest((h) {
        h.recorder.start(autoStopLimit: limit);
        h.flush();
        h.record(const Duration(minutes: 10));
        h.recorder.pause();
        h.flush();

        h.location.stopGate = Completer<void>();
        h.recorder.stop();
        h.flush();
        h.recorder.resume();
        h.flush();
        h.location.stopGate!.complete();
        h.flush();

        expect(h.recorder.state, RecorderState.stopped);
        // Only the walk's own start: resume() must not restart location.
        expect(h.location.startCalls, 1);
      });
    });

    test(
        'a persistence failure during the auto-stop still leaves the '
        'recorder stopped and reusable', () {
      autoStopTest((h) {
        h.flaky.failFinishWalk = true;
        h.recorder.start(autoStopLimit: limit);
        h.flush();

        h.record(limitTime);

        expect(h.recorder.state, RecorderState.stopped);
        // Same as a failed manual stop: there is no saved walk to carry.
        expect(h.autoStops, hasLength(1));
        expect(h.autoStops.single.walk, isNull);

        h.recorder.reset();
        expect(h.recorder.state, RecorderState.idle);

        h.flaky.failFinishWalk = false;
        h.recorder.start(autoStopLimit: limit);
        h.flush();
        expect(h.recorder.state, RecorderState.recording);
        h.record(limitTime);
        expect(h.recorder.state, RecorderState.stopped);
        expect(h.autoStops.last.walk!.duration, limitTime);
      });
    });

    group('warning', () {
      const grace = Duration(minutes: 5);

      test('becomes active at exactly limit - 5 min, with the time left', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();

          h.record(limitTime - grace - const Duration(seconds: 1));
          expect(h.autoStopIn, isNull);

          h.record(const Duration(seconds: 1));
          expect(h.autoStopIn, grace);

          h.record(const Duration(seconds: 1));
          expect(h.autoStopIn, grace - const Duration(seconds: 1));
        });
      });

      test(
          'keep walking clears it; the next warning and the stop come one '
          'full period later', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - grace);

          h.recorder.keepWalking();
          h.flush();
          expect(h.autoStopIn, isNull);

          // Past the original limit: still recording, no warning.
          h.record(limitTime - const Duration(seconds: 1));
          expect(h.recorder.state, RecorderState.recording);
          expect(h.autoStopIn, isNull);

          h.record(const Duration(seconds: 1));
          expect(h.autoStopIn, grace);

          h.record(grace);
          expect(h.recorder.state, RecorderState.stopped);
          expect(h.autoStops.single.walk!.duration, limitTime * 2);
          // The summary note counts the limit in force: two periods.
          expect(h.autoStops.single.hours, 2);
        });
      });

      test('keep walking with no warning active does nothing', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(const Duration(minutes: 10));

          h.recorder.keepWalking();

          h.record(limitTime - grace - const Duration(minutes: 10));
          expect(h.autoStopIn, grace);
          h.record(grace);
          expect(h.autoStops.single.walk!.duration, limitTime);
          expect(h.autoStops.single.hours, 1);
        });
      });

      test(
          'stop now during the warning stops and saves the walk through the '
          'auto-stop event', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - const Duration(minutes: 3));

          h.recorder.stopNow();
          h.flush();

          expect(h.recorder.state, RecorderState.stopped);
          expect(h.location.stopCalls, 1);
          expect(h.autoStopIn, isNull);
          final autoStop = h.autoStops.single;
          // The walk ends now, not at the limit.
          expect(
              autoStop.walk!.duration, limitTime - const Duration(minutes: 3));
          expect(autoStop.limit, limit);
          expect(autoStop.hours, 1);

          // The ticker is gone: no second event at the limit.
          h.record(const Duration(minutes: 10));
          expect(h.autoStops, hasLength(1));
        });
      });

      test('stop now with no warning active does nothing', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(const Duration(minutes: 10));

          h.recorder.stopNow();
          h.flush();

          expect(h.recorder.state, RecorderState.recording);
          expect(h.autoStops, isEmpty);
        });
      });

      test('a manual stop during the warning clears it', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - grace);

          h.recorder.stop();
          h.flush();

          expect(h.recorder.state, RecorderState.stopped);
          expect(h.autoStopIn, isNull);
          expect(h.autoStops, isEmpty);
        });
      });

      test(
          'a pause during the warning clears it; paused time does not move '
          'it', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - grace + const Duration(minutes: 1));
          expect(h.autoStopIn, const Duration(minutes: 4));

          h.recorder.pause();
          h.flush();
          expect(h.autoStopIn, isNull);
          // Keep walking and stop now need an active warning.
          h.recorder.stopNow();
          h.flush();
          expect(h.recorder.state, RecorderState.paused);

          h.record(const Duration(hours: 2));
          expect(h.autoStopIn, isNull);

          // Resuming inside the window warns again with the same time left.
          h.recorder.resume();
          h.flush();
          h.record(const Duration(seconds: 1));
          expect(h.autoStopIn,
              const Duration(minutes: 4) - const Duration(seconds: 1));
        });
      });

      test('a stop now landing past the limit saves exactly the limit', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - const Duration(seconds: 1));

          // The limit passes between ticks; the tap lands before the tick.
          h.clock.advance(const Duration(milliseconds: 1500));
          h.recorder.stopNow();
          h.flush();

          expect(h.autoStops.single.walk!.duration, limitTime);
        });
      });

      test('a signal-lost spell does not move the warning', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(const Duration(minutes: 30));
          h.location.emitError(StateError('location off'));
          h.flush();

          h.record(limitTime - grace - const Duration(minutes: 30));

          expect(h.snapshots.last.signalLost, isTrue);
          expect(h.autoStopIn, grace);
        });
      });
    });

    group('alerts', () {
      const grace = Duration(minutes: 5);

      test('the warning is shown once, when it activates', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();

          h.record(limitTime - grace - const Duration(seconds: 1));
          expect(h.alerts.calls, isEmpty);

          h.record(const Duration(minutes: 2));
          expect(h.alerts.calls, ['showWarning']);
          expect(h.alerts.warningTimeLeft, [grace]);
        });
      });

      test('keep walking cancels the warning; the next one is shown later', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - grace);

          h.recorder.keepWalking();
          h.flush();
          expect(h.alerts.calls, ['showWarning', 'cancelWarning']);

          h.record(limitTime);
          expect(
              h.alerts.calls, ['showWarning', 'cancelWarning', 'showWarning']);
        });
      });

      test('a manual stop during the warning cancels it, with no notice', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - grace);

          h.recorder.stop();
          h.flush();

          expect(h.alerts.calls, ['showWarning', 'cancelWarning']);
        });
      });

      test('a manual stop with no warning up alerts nothing', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(const Duration(minutes: 10));

          h.recorder.stop();
          h.flush();

          expect(h.alerts.calls, isEmpty);
        });
      });

      test('a pause during the warning cancels it; resuming shows it again',
          () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - grace);

          h.recorder.pause();
          h.flush();
          expect(h.alerts.calls, ['showWarning', 'cancelWarning']);

          h.recorder.resume();
          h.flush();
          h.record(const Duration(seconds: 1));
          expect(
              h.alerts.calls, ['showWarning', 'cancelWarning', 'showWarning']);
        });
      });

      test(
          'reaching the limit cancels the warning and shows the notice before '
          'announcing the stop', () {
        autoStopTest((h) {
          final callsAtEvent = <List<String>>[];
          final sub = h.recorder.autoStops
              .listen((_) => callsAtEvent.add([...h.alerts.calls]));
          h.recorder.start(autoStopLimit: limit);
          h.flush();

          h.record(limitTime);

          const expected = [
            'showWarning',
            'cancelWarning',
            'showStoppedNotice'
          ];
          expect(h.alerts.calls, expected);
          expect(callsAtEvent, [expected]);
          sub.cancel();
        });
      });

      test('stop now cancels the warning and shows the notice', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.record(limitTime - grace);

          h.recorder.stopNow();
          h.flush();

          expect(h.alerts.calls,
              ['showWarning', 'cancelWarning', 'showStoppedNotice']);
        });
      });

      test(
          'a self-stop whose save failed shows no "saved" notice, and the '
          'recorder is still reusable', () {
        autoStopTest((h) {
          h.recorder.start(autoStopLimit: limit);
          h.flush();
          h.flaky.failFinishWalk = true;

          h.record(limitTime);

          expect(h.recorder.state, RecorderState.stopped);
          expect(h.autoStops.single.walk, isNull);
          expect(h.alerts.calls, ['showWarning', 'cancelWarning']);

          h.recorder.reset();
          expect(h.recorder.state, RecorderState.idle);
        });
      });

      test('failing alerts disturb neither the warning nor the stop', () {
        autoStopTest((h) {
          h.alerts.fail = true;
          h.recorder.start(autoStopLimit: limit);
          h.flush();

          h.record(limitTime - grace);
          expect(h.autoStopIn, grace);

          h.record(grace);
          expect(h.recorder.state, RecorderState.stopped);
          expect(h.autoStops.single.walk!.duration, limitTime);
          expect(h.alerts.calls,
              ['showWarning', 'cancelWarning', 'showStoppedNotice']);
        });
      });
    });
  });
}
