import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
        Coordinate(
            lat: 55.676, lng: 12.568, recordedAt: DateTime(2026, 6, 1, 9, 0)),
        Coordinate(
            lat: 55.677, lng: 12.569, recordedAt: DateTime(2026, 6, 1, 9, 15)),
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

  group('incremental recording', () {
    test('createWalk + appendCoordinate persist an in-progress walk', () async {
      await repository.createWalk('live', DateTime(2026, 6, 1, 9, 0));
      await repository.appendCoordinate(
          'live',
          Coordinate(
              lat: 1.0, lng: 1.0, recordedAt: DateTime(2026, 6, 1, 9, 0)),
          0);
      await repository.appendCoordinate(
          'live',
          Coordinate(
              lat: 2.0, lng: 2.0, recordedAt: DateTime(2026, 6, 1, 9, 1)),
          1);

      // Recoverable even though finishWalk was never called (e.g. the process
      // was killed mid-walk): coordinates intact, end time still open.
      final found = await repository.findById('live');
      expect(found!.coordinates.map((c) => c.lat), [1.0, 2.0]);
      expect(found.endTime, isNull);
    });

    test('finishWalk records the end time and pause-aware duration', () async {
      await repository.createWalk('done', DateTime(2026, 6, 1, 9, 0));
      await repository.finishWalk('done', DateTime(2026, 6, 1, 9, 30),
          const Duration(minutes: 25), 1250.0);

      final found = await repository.findById('done');
      expect(found!.endTime, DateTime(2026, 6, 1, 9, 30));
      // 25 min moving time, not the 30 min wall-clock span.
      expect(found.duration, const Duration(minutes: 25));
      expect(found.distanceMetres, 1250.0);
    });

    test('findAll excludes unfinished walks; findById still returns them',
        () async {
      await repository.createWalk('in-progress', DateTime(2026, 6, 1, 9, 0));
      await repository.save(Walk(
        id: 'finished',
        startTime: DateTime(2026, 6, 1, 8, 0),
        endTime: DateTime(2026, 6, 1, 8, 30),
      ));

      // The history list only shows finished walks — an in-progress (or
      // orphaned) walk has no end time and must not appear.
      final walks = await repository.findAll();
      expect(walks.map((w) => w.id), ['finished']);

      // Direct lookup still works, e.g. for crash recovery.
      final found = await repository.findById('in-progress');
      expect(found, isNotNull);
      expect(found!.endTime, isNull);
    });
  });

  group('stored distance', () {
    test('findAll reads persisted distance without hydrating coordinates',
        () async {
      await repository.createWalk('walked', DateTime(2026, 6, 1, 9, 0));
      await repository.appendCoordinate(
          'walked',
          Coordinate(
              lat: 55.676, lng: 12.568, recordedAt: DateTime(2026, 6, 1, 9, 0)),
          0);
      await repository.appendCoordinate(
          'walked',
          Coordinate(
              lat: 55.677, lng: 12.569, recordedAt: DateTime(2026, 6, 1, 9, 5)),
          1);
      await repository.finishWalk('walked', DateTime(2026, 6, 1, 9, 30),
          const Duration(minutes: 25), 127.5);

      final walks = await repository.findAll();
      expect(walks.single.distanceMetres, 127.5);
      // The list query deliberately skips the coordinates.
      expect(walks.single.coordinates, isEmpty);

      // The detail lookup still hydrates the full route.
      final full = await repository.findById('walked');
      expect(full!.coordinates.length, 2);
      expect(full.distanceMetres, 127.5);
    });

    test('save computes and persists distance from coordinates', () async {
      final walk = Walk(
        id: 'walk-dist',
        startTime: DateTime(2026, 6, 1, 9, 0),
        endTime: DateTime(2026, 6, 1, 9, 30),
        coordinates: [
          Coordinate(
              lat: 55.676, lng: 12.568, recordedAt: DateTime(2026, 6, 1, 9, 0)),
          Coordinate(
              lat: 55.677,
              lng: 12.569,
              recordedAt: DateTime(2026, 6, 1, 9, 15)),
        ],
      );

      await repository.save(walk);
      final walks = await repository.findAll();

      // ~128 m between the two fixes (haversine).
      expect(walks.single.distanceMetres, closeTo(128, 5));
    });
  });

  group('schema migration', () {
    test('v2 → v3 backfills distance from stored coordinates', () async {
      final dir = await Directory.systemTemp.createTemp('walkable_test');
      final path = p.join(dir.path, 'walkable.db');

      // Build a v2 database by hand: no distance column yet.
      final v2 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE walks (
                id TEXT PRIMARY KEY,
                start_time INTEGER NOT NULL,
                end_time INTEGER,
                duration_ms INTEGER
              )
            ''');
            await db.execute('''
              CREATE TABLE coordinates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                walk_id TEXT NOT NULL,
                lat REAL NOT NULL,
                lng REAL NOT NULL,
                recorded_at INTEGER NOT NULL,
                sequence_index INTEGER NOT NULL,
                FOREIGN KEY (walk_id) REFERENCES walks (id)
              )
            ''');
          },
        ),
      );
      await v2.insert('walks', {
        'id': 'legacy',
        'start_time': DateTime(2026, 5, 1, 8, 0).millisecondsSinceEpoch,
        'end_time': DateTime(2026, 5, 1, 8, 45).millisecondsSinceEpoch,
        'duration_ms': const Duration(minutes: 40).inMilliseconds,
      });
      await v2.insert('coordinates', {
        'walk_id': 'legacy',
        'lat': 55.676,
        'lng': 12.568,
        'recorded_at': DateTime(2026, 5, 1, 8, 0).millisecondsSinceEpoch,
        'sequence_index': 0,
      });
      await v2.insert('coordinates', {
        'walk_id': 'legacy',
        'lat': 55.677,
        'lng': 12.569,
        'recorded_at': DateTime(2026, 5, 1, 8, 30).millisecondsSinceEpoch,
        'sequence_index': 1,
      });
      await v2.close();

      // Reopening through the repository runs the v3 upgrade.
      final migrated = await WalkRepository.open(path);
      addTearDown(() async {
        await migrated.close();
        await dir.delete(recursive: true);
      });

      final walks = await migrated.findAll();
      // ~128 m between the two fixes, backfilled from the coordinates.
      expect(walks.single.distanceMetres, closeTo(128, 5));
      expect(walks.single.duration, const Duration(minutes: 40));
    });
  });

  test('save round-trips the pause-aware duration', () async {
    final walk = Walk(
      id: 'walk-dur',
      startTime: DateTime(2026, 6, 1, 9, 0),
      endTime: DateTime(2026, 6, 1, 9, 30),
      duration: const Duration(minutes: 22, seconds: 30),
    );

    await repository.save(walk);
    final found = await repository.findById('walk-dur');

    expect(found!.duration, const Duration(minutes: 22, seconds: 30));
  });
}
