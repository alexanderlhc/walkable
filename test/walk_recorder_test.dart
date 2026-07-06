import 'dart:async';

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

  int startCalls = 0;

  @override
  Future<LocationServiceResult> start({
    ForegroundNotificationText? notification,
  }) async {
    startCalls++;
    final gate = startGate;
    if (gate != null) await gate.future;
    return startResult;
  }

  @override
  Future<void> stop() async {}

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
class _FlakyWalkRepository implements WalkRepository {
  final WalkRepository _inner;

  _FlakyWalkRepository(this._inner);

  bool failCreateWalk = false;
  bool failAppendCoordinate = false;
  bool failFinishWalk = false;

  @override
  Future<void> createWalk(String id, DateTime startTime) async {
    if (failCreateWalk) throw StateError('createWalk rejected');
    await _inner.createWalk(id, startTime);
  }

  @override
  Future<void> appendCoordinate(
      String walkId, Coordinate coord, int sequenceIndex) async {
    if (failAppendCoordinate) throw StateError('appendCoordinate rejected');
    await _inner.appendCoordinate(walkId, coord, sequenceIndex);
  }

  @override
  Future<void> finishWalk(String walkId, DateTime endTime, Duration duration,
      double distanceMetres, List<Coord> route) async {
    if (failFinishWalk) throw StateError('finishWalk rejected');
    await _inner.finishWalk(walkId, endTime, duration, distanceMetres, route);
  }

  @override
  Future<void> save(Walk walk) => _inner.save(walk);

  @override
  Future<Walk?> findById(String id) => _inner.findById(id);

  @override
  Future<List<Walk>> findAll() => _inner.findAll();

  @override
  Future<void> close() => _inner.close();
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

  test('stop from idle does nothing', () async {
    await recorder.stop();
    expect(recorder.state, RecorderState.idle);
  });

  test('stop transitions to stopped', () async {
    await recorder.start();
    await recorder.stop();
    expect(recorder.state, RecorderState.stopped);
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

  test('position stream error pauses the walk instead of going unhandled',
      () async {
    await recorder.start();
    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);

    location.emitError(StateError('location services disabled'));
    await Future<void>.delayed(Duration.zero);

    expect(recorder.state, RecorderState.paused);
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

      await recorder.stop(); // must complete without throwing
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
      await recorder.stop(); // must complete without throwing
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
}
