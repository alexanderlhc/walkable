import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/walk_recorder.dart';

class _StubLocationService extends LocationService {
  final StreamController<Position> _ctrl =
      StreamController<Position>.broadcast();

  @override
  Stream<Position> get positions => _ctrl.stream;

  void emit(Position pos) => _ctrl.add(pos);

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

  test('start transitions to recording', () {
    recorder.start();
    expect(recorder.state, RecorderState.recording);
  });

  test('stop from idle does nothing', () async {
    await recorder.stop();
    expect(recorder.state, RecorderState.idle);
  });

  test('stop transitions to stopped', () async {
    recorder.start();
    await recorder.stop();
    expect(recorder.state, RecorderState.stopped);
  });

  test('each position updates polyline and distance in snapshot', () async {
    recorder.start();

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
    expect(snapshots[1].distanceMetres, greaterThan(0));
  });

  test('snapshot exposes distance, elapsed, pace, and polyline', () async {
    recorder.start();

    WalkSnapshot? latest;
    final sub = recorder.snapshots.listen((s) => latest = s);

    location.emit(_pos(55.676, 12.568));
    location.emit(_pos(55.677, 12.569));
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();

    expect(latest, isNotNull);
    expect(latest!.distanceMetres, greaterThan(0));
    expect(latest!.elapsed, greaterThanOrEqualTo(Duration.zero));
    expect(latest!.paceMinPerKm, isNot(double.infinity));
    expect(latest!.polyline.length, 2);
  });

  test('stop emits final snapshot and saves walk to repository', () async {
    recorder.start();

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
    expect(walks[0].coordinates.length, 2);
    expect(walks[0].endTime, isNotNull);
    expect(walks[0].endTime, isNotNull);
  });
}
