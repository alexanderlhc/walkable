import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

/// One fakeAsync auto-stop scenario: a recorder on the fake clock with the
/// no-op flaky repository, plus every self-stop event it emits.
class _AutoStopHarness {
  final FakeAsync async;
  final location = _FakeAsyncLocationService();
  final clock = _FakeClock();
  final flaky = _FlakyWalkRepository();
  late final WalkRecorder recorder = WalkRecorder(
    locationService: location,
    repository: flaky,
    now: clock.now,
  );
  final List<SelfStop> selfStops = [];
  late final StreamSubscription<SelfStop> _sub;

  _AutoStopHarness(this.async) {
    _sub = recorder.selfStops.listen(selfStops.add);
  }

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
    const limit = Duration(hours: 1);

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
        expect(h.selfStops, isEmpty);
      });
    });

    test('keeps recording until moving time reaches the limit', () {
      autoStopTest((h) {
        h.recorder.start(autoStopAfter: limit);
        h.flush();

        h.record(limit - const Duration(seconds: 1));

        expect(h.recorder.state, RecorderState.recording);
        expect(h.selfStops, isEmpty);
      });
    });

    test(
        'stops and saves the walk at the limit; the self-stop event carries '
        'the saved walk', () {
      autoStopTest((h) {
        h.recorder.start(autoStopAfter: limit);
        h.flush();
        h.location.emit(_pos(55.676, 12.568));
        h.location.emit(_pos(55.677, 12.569));
        h.flush();

        h.record(limit);

        expect(h.recorder.state, RecorderState.stopped);
        // Location and the foreground service shut down, as on a manual stop.
        expect(h.location.stopCalls, 1);
        expect(h.selfStops, hasLength(1));
        final walk = h.selfStops.single.walk;
        expect(walk, isNotNull);
        expect(walk!.duration, limit);
        expect(walk.distanceMetres, greaterThan(0));
        expect(h.selfStops.single.limit, limit);
      });
    });

    test('the saved duration equals the limit even when a tick runs late', () {
      autoStopTest((h) {
        h.recorder.start(autoStopAfter: limit);
        h.flush();

        h.record(limit - const Duration(seconds: 1));
        // The next tick lands 20 s late (e.g. a throttled background
        // process): moving time is already past the limit when it fires.
        h.clock.advance(const Duration(seconds: 21));
        h.async.elapse(const Duration(seconds: 1));
        h.flush();

        expect(h.recorder.state, RecorderState.stopped);
        expect(h.selfStops.single.walk!.duration, limit);
      });
    });

    test('paused time does not count; resuming continues the countdown', () {
      autoStopTest((h) {
        h.recorder.start(autoStopAfter: limit);
        h.flush();

        h.record(const Duration(minutes: 40));
        h.recorder.pause();
        h.flush();
        // A long café stop: far past the limit in wall-clock time.
        h.record(const Duration(hours: 3));
        expect(h.recorder.state, RecorderState.paused);
        expect(h.selfStops, isEmpty);

        h.recorder.resume();
        h.flush();
        h.record(const Duration(minutes: 20) - const Duration(seconds: 1));
        expect(h.recorder.state, RecorderState.recording);

        h.record(const Duration(seconds: 1));
        expect(h.recorder.state, RecorderState.stopped);
        expect(h.selfStops.single.walk!.duration, limit);
      });
    });

    test('a signal-lost spell does not affect the countdown', () {
      autoStopTest((h) {
        h.recorder.start(autoStopAfter: limit);
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
        expect(h.selfStops.single.walk!.duration, limit);
      });
    });

    test('the limit is captured per walk, not carried into the next one', () {
      autoStopTest((h) {
        h.recorder.start(autoStopAfter: limit);
        h.flush();
        h.record(limit);
        expect(h.recorder.state, RecorderState.stopped);
        h.recorder.reset();

        // The next walk starts with auto-stop Off.
        h.recorder.start();
        h.flush();
        h.record(const Duration(hours: 5));
        expect(h.recorder.state, RecorderState.recording);
        expect(h.selfStops, hasLength(1));
      });
    });

    test('a manual stop before the limit emits no self-stop event', () {
      autoStopTest((h) {
        h.recorder.start(autoStopAfter: limit);
        h.flush();
        h.record(const Duration(minutes: 30));

        h.recorder.stop();
        h.flush();
        h.record(const Duration(hours: 2));

        expect(h.recorder.state, RecorderState.stopped);
        expect(h.selfStops, isEmpty);
      });
    });

    test(
        'a manual stop and reset during the self-stop\'s save do not lose '
        'the walk', () {
      autoStopTest((h) {
        h.flaky.finishGate = Completer<void>();
        h.recorder.start(autoStopAfter: limit);
        h.flush();
        h.record(limit);
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
        expect(h.selfStops.single.walk!.duration, limit);
        h.recorder.reset();
        expect(h.recorder.state, RecorderState.idle);
      });
    });

    test('a pause during the self-stop\'s teardown is ignored', () {
      autoStopTest((h) {
        h.location.stopGate = Completer<void>();
        h.recorder.start(autoStopAfter: limit);
        h.flush();
        h.record(limit);

        Object? error;
        h.recorder.pause().catchError((Object e) => error = e);
        h.flush();
        h.location.stopGate!.complete();
        h.flush();

        expect(error, isNull);
        expect(h.recorder.state, RecorderState.stopped);
        expect(h.selfStops.single.walk!.duration, limit);
      });
    });

    test(
        'a failed location shutdown during the self-stop still announces it '
        'and leaves the recorder stopped', () {
      autoStopTest((h) {
        h.location.failStop = true;
        h.recorder.start(autoStopAfter: limit);
        h.flush();

        h.record(limit);

        expect(h.recorder.state, RecorderState.stopped);
        expect(h.selfStops, hasLength(1));
        h.recorder.reset();
        expect(h.recorder.state, RecorderState.idle);
      });
    });

    test('a resume during a manual stop of a paused walk is ignored', () {
      autoStopTest((h) {
        h.recorder.start(autoStopAfter: limit);
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
        'a persistence failure during the self-stop still leaves the '
        'recorder stopped and reusable', () {
      autoStopTest((h) {
        h.flaky.failFinishWalk = true;
        h.recorder.start(autoStopAfter: limit);
        h.flush();

        h.record(limit);

        expect(h.recorder.state, RecorderState.stopped);
        // Same as a failed manual stop: there is no saved walk to carry.
        expect(h.selfStops, hasLength(1));
        expect(h.selfStops.single.walk, isNull);

        h.recorder.reset();
        expect(h.recorder.state, RecorderState.idle);

        h.flaky.failFinishWalk = false;
        h.recorder.start(autoStopAfter: limit);
        h.flush();
        expect(h.recorder.state, RecorderState.recording);
        h.record(limit);
        expect(h.recorder.state, RecorderState.stopped);
        expect(h.selfStops.last.walk!.duration, limit);
      });
    });
  });
}
