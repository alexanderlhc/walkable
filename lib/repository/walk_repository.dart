import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/walk_calculator.dart' as calc;

class WalkRepository {
  final Database _db;

  WalkRepository._(this._db);

  static Future<WalkRepository> inMemory() async {
    final db = await openDatabase(
      ':memory:',
      version: 4,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return WalkRepository._(db);
  }

  static Future<WalkRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 4,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return WalkRepository._(db);
  }

  static Future<void> _upgradeSchema(
      Database db, int oldVersion, int newVersion) async {
    // v2 adds the persisted pause-aware moving time (duration_ms).
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE walks ADD COLUMN duration_ms INTEGER');
    }
    // v3 adds the persisted route distance (metres), so list queries don't
    // have to hydrate every coordinate. Backfill existing walks from their
    // stored coordinates.
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE walks ADD COLUMN distance REAL');
      final walkRows = await db.query('walks', columns: ['id']);
      for (final row in walkRows) {
        final walkId = row['id'] as String;
        final coordRows = await db.query(
          'coordinates',
          columns: ['lat', 'lng'],
          where: 'walk_id = ?',
          whereArgs: [walkId],
          orderBy: 'sequence_index ASC',
        );
        final coords = coordRows
            .map((c) => (lat: c['lat'] as double, lng: c['lng'] as double))
            .toList();
        await db.update(
          'walks',
          {'distance': calc.totalDistance(coords)},
          where: 'id = ?',
          whereArgs: [walkId],
        );
      }
    }
    // v4 adds the simplified route (JSON [[lat,lng],...]) so history cards can
    // draw a mini map preview without hydrating the coordinates. Backfill
    // finished walks from their stored coordinates.
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE walks ADD COLUMN route TEXT');
      final walkRows = await db.query(
        'walks',
        columns: ['id'],
        where: 'end_time IS NOT NULL',
      );
      for (final row in walkRows) {
        final walkId = row['id'] as String;
        final coordRows = await db.query(
          'coordinates',
          columns: ['lat', 'lng'],
          where: 'walk_id = ?',
          whereArgs: [walkId],
          orderBy: 'sequence_index ASC',
        );
        final coords = coordRows
            .map((c) => (lat: c['lat'] as double, lng: c['lng'] as double))
            .toList();
        await db.update(
          'walks',
          {'route': _encodeRoute(calc.simplifyRoute(coords))},
          where: 'id = ?',
          whereArgs: [walkId],
        );
      }
    }
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE walks (
        id TEXT PRIMARY KEY,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        duration_ms INTEGER,
        distance REAL,
        route TEXT
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
  }

  /// Inserts the walk row at the start of recording, before any coordinates,
  /// so an in-progress walk survives the process being killed. The walk has no
  /// end time until [finishWalk].
  Future<void> createWalk(String id, DateTime startTime) async {
    await _db.insert(
      'walks',
      {
        'id': id,
        'start_time': startTime.millisecondsSinceEpoch,
        'end_time': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Appends a single recorded point, persisted immediately so a background
  /// kill loses at most the latest fix rather than the whole route.
  Future<void> appendCoordinate(
      String walkId, Coordinate coord, int sequenceIndex) async {
    await _db.insert('coordinates', {
      'walk_id': walkId,
      'lat': coord.lat,
      'lng': coord.lng,
      'recorded_at': coord.recordedAt.millisecondsSinceEpoch,
      'sequence_index': sequenceIndex,
    });
  }

  /// Marks a walk finished by recording its end time, the pause-aware moving
  /// [duration] accumulated during recording, the total route
  /// [distanceMetres], and the simplified [route] for the history preview —
  /// all persisted so list queries never need the coordinates.
  Future<void> finishWalk(String walkId, DateTime endTime, Duration duration,
      double distanceMetres, List<calc.Coord> route) async {
    await _db.update(
      'walks',
      {
        'end_time': endTime.millisecondsSinceEpoch,
        'duration_ms': duration.inMilliseconds,
        'distance': distanceMetres,
        'route': _encodeRoute(route),
      },
      where: 'id = ?',
      whereArgs: [walkId],
    );
  }

  /// Persists the pause-aware moving [duration] accumulated so far on a walk
  /// that is still being recorded. The duration lives only in the recorder's
  /// memory (coordinate gaps can't reconstruct it — GPS distance filters make
  /// stationary indistinguishable from paused), so periodic writes are what
  /// make it recoverable after a mid-walk process death. Guarded to unfinished
  /// rows so a late throttled write can never clobber a finished walk.
  Future<void> updateProgress(String id, Duration duration) async {
    await _db.update(
      'walks',
      {'duration_ms': duration.inMilliseconds},
      where: 'id = ? AND end_time IS NULL',
      whereArgs: [id],
    );
  }

  /// Salvages walks orphaned by a mid-walk process death: rows created by
  /// [createWalk] that never reached [finishWalk]. Runs once at startup,
  /// before any recording begins, so every unfinished row is an orphan.
  ///
  /// Orphans with fewer than two coordinates carry no route worth keeping and
  /// are deleted. The rest are finished in place with the same derived values
  /// [finishWalk] would have written: end time = the last fix's recorded_at,
  /// distance and simplified route computed from the stored coordinates, and
  /// duration = the last persisted [updateProgress] value when present,
  /// falling back to the start-to-last-fix wall-clock span.
  ///
  /// Returns the number of walks recovered (deletions don't count).
  Future<int> recoverOrphans() async {
    final orphanRows = await _db.query('walks', where: 'end_time IS NULL');
    var recovered = 0;
    for (final row in orphanRows) {
      final walkId = row['id'] as String;
      await _db.transaction((txn) async {
        final coordRows = await txn.query(
          'coordinates',
          columns: ['lat', 'lng', 'recorded_at'],
          where: 'walk_id = ?',
          whereArgs: [walkId],
          orderBy: 'sequence_index ASC',
        );

        if (coordRows.length < 2) {
          await txn
              .delete('coordinates', where: 'walk_id = ?', whereArgs: [walkId]);
          await txn.delete('walks', where: 'id = ?', whereArgs: [walkId]);
          return;
        }

        final coords = coordRows
            .map((c) => (lat: c['lat'] as double, lng: c['lng'] as double))
            .toList();
        final lastRecordedAt = coordRows.last['recorded_at'] as int;
        final durationMs = row['duration_ms'] as int? ??
            lastRecordedAt - (row['start_time'] as int);

        await txn.update(
          'walks',
          {
            'end_time': lastRecordedAt,
            'duration_ms': durationMs,
            'distance': calc.totalDistance(coords),
            'route': _encodeRoute(calc.simplifyRoute(coords)),
          },
          where: 'id = ?',
          whereArgs: [walkId],
        );
        recovered++;
      });
    }
    return recovered;
  }

  Future<void> save(Walk walk) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'walks',
        {
          'id': walk.id,
          'start_time': walk.startTime.millisecondsSinceEpoch,
          'end_time': walk.endTime?.millisecondsSinceEpoch,
          'duration_ms': walk.duration?.inMilliseconds,
          'distance': walk.distanceMetres ??
              calc.totalDistance(
                walk.coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList(),
              ),
          'route': _encodeRoute(walk.route ??
              calc.simplifyRoute(
                walk.coordinates.map((c) => (lat: c.lat, lng: c.lng)).toList(),
              )),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (var i = 0; i < walk.coordinates.length; i++) {
        final coord = walk.coordinates[i];
        await txn.insert(
          'coordinates',
          {
            'walk_id': walk.id,
            'lat': coord.lat,
            'lng': coord.lng,
            'recorded_at': coord.recordedAt.millisecondsSinceEpoch,
            'sequence_index': i,
          },
        );
      }
    });
  }

  Future<Walk?> findById(String id) async {
    final walkRows = await _db.query(
      'walks',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (walkRows.isEmpty) return null;

    return _hydrate(walkRows.first);
  }

  /// Returns all *finished* walks, newest first, for the history list. Walks
  /// still being recorded (or orphaned by a kill) have no end time and are
  /// excluded. Coordinates are deliberately not hydrated — the list reads the
  /// persisted distance instead; use [findById] for the full route.
  Future<List<Walk>> findAll() async {
    final walkRows = await _db.query(
      'walks',
      where: 'end_time IS NOT NULL',
      orderBy: 'start_time DESC',
    );
    return walkRows.map(_walkFromRow).toList();
  }

  Future<Walk> _hydrate(Map<String, dynamic> row) async {
    final walkId = row['id'] as String;
    final coordRows = await _db.query(
      'coordinates',
      where: 'walk_id = ?',
      whereArgs: [walkId],
      orderBy: 'sequence_index ASC',
    );

    final coordinates = coordRows
        .map((c) => Coordinate(
              lat: c['lat'] as double,
              lng: c['lng'] as double,
              recordedAt:
                  DateTime.fromMillisecondsSinceEpoch(c['recorded_at'] as int),
            ))
        .toList();

    return _walkFromRow(row, coordinates: coordinates);
  }

  Walk _walkFromRow(Map<String, dynamic> row,
      {List<Coordinate> coordinates = const []}) {
    final endTimeMs = row['end_time'] as int?;
    final durationMs = row['duration_ms'] as int?;

    return Walk(
      id: row['id'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(row['start_time'] as int),
      endTime: endTimeMs != null
          ? DateTime.fromMillisecondsSinceEpoch(endTimeMs)
          : null,
      duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      distanceMetres: (row['distance'] as num?)?.toDouble(),
      route: _decodeRoute(row['route'] as String?),
      coordinates: coordinates,
    );
  }

  /// The route column format: a JSON array of `[lat, lng]` pairs.
  static String _encodeRoute(List<calc.Coord> route) => jsonEncode([
        for (final c in route) [c.lat, c.lng]
      ]);

  static List<calc.Coord>? _decodeRoute(String? json) {
    if (json == null) return null;
    return [
      for (final pair in jsonDecode(json) as List)
        (lat: (pair[0] as num).toDouble(), lng: (pair[1] as num).toDouble()),
    ];
  }

  Future<void> close() => _db.close();
}
