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
          const Duration(minutes: 25), 1250.0, const []);

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
          const Duration(minutes: 25), 127.5, const []);

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

  group('stored route', () {
    test('finishWalk persists the simplified route', () async {
      await repository.createWalk('routed', DateTime(2026, 6, 1, 9, 0));
      await repository.finishWalk(
        'routed',
        DateTime(2026, 6, 1, 9, 30),
        const Duration(minutes: 25),
        127.5,
        const [(lat: 55.676, lng: 12.568), (lat: 55.677, lng: 12.569)],
      );

      final walks = await repository.findAll();
      expect(walks.single.route, [
        (lat: 55.676, lng: 12.568),
        (lat: 55.677, lng: 12.569),
      ]);
    });

    test('findAll returns the route without hydrating coordinates', () async {
      await repository.createWalk('routed', DateTime(2026, 6, 1, 9, 0));
      await repository.appendCoordinate(
          'routed',
          Coordinate(
              lat: 55.676, lng: 12.568, recordedAt: DateTime(2026, 6, 1, 9, 0)),
          0);
      await repository.appendCoordinate(
          'routed',
          Coordinate(
              lat: 55.677, lng: 12.569, recordedAt: DateTime(2026, 6, 1, 9, 5)),
          1);
      await repository.finishWalk(
        'routed',
        DateTime(2026, 6, 1, 9, 30),
        const Duration(minutes: 25),
        127.5,
        const [(lat: 55.676, lng: 12.568), (lat: 55.677, lng: 12.569)],
      );

      final walks = await repository.findAll();
      // The preview route is available while the coordinates stay unhydrated.
      expect(walks.single.route, hasLength(2));
      expect(walks.single.coordinates, isEmpty);
    });

    test('an empty route round-trips as an empty list', () async {
      await repository.createWalk('short', DateTime(2026, 6, 1, 9, 0));
      // A walk with no fixes finishes with an empty route.
      await repository.finishWalk('short', DateTime(2026, 6, 1, 9, 30),
          const Duration(minutes: 25), 0.0, const []);

      final walks = await repository.findAll();
      // Empty, not null — the card renders the placeholder either way.
      expect(walks.single.route, isEmpty);
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

    test('v3 → v4 backfills the simplified route from stored coordinates',
        () async {
      final dir = await Directory.systemTemp.createTemp('walkable_test');
      final path = p.join(dir.path, 'walkable.db');

      // Build a v3 database by hand: distance column, but no route yet.
      final v3 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE walks (
                id TEXT PRIMARY KEY,
                start_time INTEGER NOT NULL,
                end_time INTEGER,
                duration_ms INTEGER,
                distance REAL
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
      await v3.insert('walks', {
        'id': 'legacy',
        'start_time': DateTime(2026, 5, 1, 8, 0).millisecondsSinceEpoch,
        'end_time': DateTime(2026, 5, 1, 8, 45).millisecondsSinceEpoch,
        'duration_ms': const Duration(minutes: 40).inMilliseconds,
        'distance': 250.0,
      });
      // Three fixes with a collinear midpoint the simplifier drops.
      final fixes = [
        (lat: 55.676, lng: 12.568),
        (lat: 55.677, lng: 12.568),
        (lat: 55.678, lng: 12.568),
      ];
      for (var i = 0; i < fixes.length; i++) {
        await v3.insert('coordinates', {
          'walk_id': 'legacy',
          'lat': fixes[i].lat,
          'lng': fixes[i].lng,
          'recorded_at':
              DateTime(2026, 5, 1, 8, 15 * i).millisecondsSinceEpoch,
          'sequence_index': i,
        });
      }
      await v3.close();

      // Reopening through the repository runs the v4 upgrade.
      final migrated = await WalkRepository.open(path);
      addTearDown(() async {
        await migrated.close();
        await dir.delete(recursive: true);
      });

      final walks = await migrated.findAll();
      // Backfilled and simplified: the collinear midpoint is gone.
      expect(walks.single.route, [
        (lat: 55.676, lng: 12.568),
        (lat: 55.678, lng: 12.568),
      ]);
      // The list still doesn't hydrate coordinates.
      expect(walks.single.coordinates, isEmpty);
    });

    test('migrating from v1 yields the same schema as a fresh onCreate',
        () async {
      final dir = await Directory.systemTemp.createTemp('walkable_test');
      addTearDown(() => dir.delete(recursive: true));

      // Describes every user table and index of the database at [path]:
      // object names from sqlite_master plus, per table, each column's
      // name/type/notnull/default/pk from PRAGMA table_info. Ordering and
      // whitespace are normalized so only real schema differences compare
      // unequal.
      Future<Map<String, Object?>> describeSchema(String path) async {
        final db = await databaseFactory.openDatabase(path);
        try {
          final master = await db.rawQuery(
            "SELECT type, name, tbl_name FROM sqlite_master "
            "WHERE type IN ('table', 'index') AND name NOT LIKE 'sqlite_%' "
            "ORDER BY type, name",
          );
          final objects = [
            for (final row in master)
              '${row['type']}:${row['name']} (on ${row['tbl_name']})',
          ];

          final tables = <String, Map<String, Object?>>{};
          for (final row in master.where((r) => r['type'] == 'table')) {
            final table = row['name'] as String;
            final columns = await db.rawQuery('PRAGMA table_info("$table")');
            tables[table] = {
              for (final col in columns)
                col['name'] as String: {
                  'type': (col['type'] as String)
                      .toUpperCase()
                      .replaceAll(RegExp(r'\s+'), ' ')
                      .trim(),
                  'notnull': col['notnull'],
                  'dflt_value': col['dflt_value'],
                  'pk': col['pk'],
                },
            };
          }
          return {'objects': objects, 'tables': tables};
        } finally {
          await db.close();
        }
      }

      // One database starts at v1 — the oldest schema the migration chain
      // supports (walks without duration_ms/distance/route) — and upgrades
      // through every migration to the current version.
      final migratedPath = p.join(dir.path, 'migrated.db');
      final v1 = await databaseFactory.openDatabase(
        migratedPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE walks (
                id TEXT PRIMARY KEY,
                start_time INTEGER NOT NULL,
                end_time INTEGER
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
      await v1.close();
      final migrated = await WalkRepository.open(migratedPath);
      await migrated.close();

      // The other database is created fresh at the current version.
      final freshPath = p.join(dir.path, 'fresh.db');
      final fresh = await WalkRepository.open(freshPath);
      await fresh.close();

      // If these diverge, onCreate has drifted from the migration chain and
      // new installs get a different schema than upgraded ones.
      expect(await describeSchema(migratedPath),
          equals(await describeSchema(freshPath)));
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
