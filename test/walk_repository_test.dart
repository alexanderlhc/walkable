import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';

void main() {
  late WalkRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    repository = await WalkRepository.inMemory();
  });

  tearDown(() async {
    await repository.close();
  });

  // Cycle 1 — tracer bullet: save + findById round-trips walk and coordinates
  test('findById returns saved walk with coordinates', () async {
    final walk = Walk(
      id: 'walk-1',
      startTime: DateTime(2026, 6, 1, 9, 0),
      endTime: DateTime(2026, 6, 1, 9, 30),
      coordinates: [
        Coordinate(lat: 55.676, lng: 12.568, recordedAt: DateTime(2026, 6, 1, 9, 0)),
        Coordinate(lat: 55.677, lng: 12.569, recordedAt: DateTime(2026, 6, 1, 9, 15)),
      ],
    );

    await repository.save(walk);
    final found = await repository.findById('walk-1');

    expect(found, isNotNull);
    expect(found!.id, 'walk-1');
    expect(found.startTime, DateTime(2026, 6, 1, 9, 0));
    expect(found.endTime, DateTime(2026, 6, 1, 9, 30));
    expect(found.coordinates.length, 2);
    expect(found.coordinates[0].lat, 55.676);
    expect(found.coordinates[0].lng, 12.568);
    expect(found.coordinates[1].lat, 55.677);
  });

  // Cycle 2 — findAll returns empty list when no walks exist
  test('findAll returns empty list when no walks exist', () async {
    final walks = await repository.findAll();
    expect(walks, isEmpty);
  });

  // Cycle 3 — findAll returns walks newest-first
  test('findAll returns walks in reverse-chronological order', () async {
    final older = Walk(
      id: 'walk-old',
      startTime: DateTime(2026, 5, 1, 8, 0),
      endTime: DateTime(2026, 5, 1, 8, 45),
    );
    final newer = Walk(
      id: 'walk-new',
      startTime: DateTime(2026, 6, 1, 9, 0),
      endTime: DateTime(2026, 6, 1, 9, 30),
    );

    await repository.save(older);
    await repository.save(newer);

    final walks = await repository.findAll();
    expect(walks.length, 2);
    expect(walks[0].id, 'walk-new');
    expect(walks[1].id, 'walk-old');
  });

  // Cycle 4 — findById returns null for unknown ID
  test('findById returns null for unknown id', () async {
    final result = await repository.findById('no-such-walk');
    expect(result, isNull);
  });

  // Cycle 5 — coordinates come back in insertion order
  test('save preserves coordinate sequence order', () async {
    final walk = Walk(
      id: 'walk-seq',
      startTime: DateTime(2026, 6, 1, 9, 0),
      endTime: DateTime(2026, 6, 1, 9, 30),
      coordinates: [
        Coordinate(lat: 1.0, lng: 1.0, recordedAt: DateTime(2026, 6, 1, 9, 0)),
        Coordinate(lat: 2.0, lng: 2.0, recordedAt: DateTime(2026, 6, 1, 9, 10)),
        Coordinate(lat: 3.0, lng: 3.0, recordedAt: DateTime(2026, 6, 1, 9, 20)),
      ],
    );

    await repository.save(walk);
    final found = await repository.findById('walk-seq');

    expect(found!.coordinates.map((c) => c.lat), [1.0, 2.0, 3.0]);
  });
}
