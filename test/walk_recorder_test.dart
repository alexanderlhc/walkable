import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/repository/walk_repository.dart';
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
  late WalkRepository repository;
  late WalkRecorder recorder;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    location = _StubLocationService();
    repository = await WalkRepository.inMemory();
    recorder = WalkRecorder(locationService: location, repository: repository);
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

    location.emit(_pos(55.676, 12.568));
    await Future<void>.delayed(Duration.zero);

    final elapsedAtPause = snapshots.last.stats.duration!;
    await recorder.pause();

    // simulate a pause gap
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await recorder.resume();
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();

    // elapsed should only have grown by the tiny gap between resume and emit,
    // not by the 50ms pause gap
    expect(snapshots.last.stats.duration! - elapsedAtPause,
        lessThan(const Duration(milliseconds: 40)));
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
}
