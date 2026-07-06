import 'package:sqflite/sqflite.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/walk_calculator.dart' as calc;

class WalkRepository {
  final Database _db;

  WalkRepository._(this._db);

  static Future<WalkRepository> inMemory() async {
    final db = await openDatabase(
      ':memory:',
      version: 3,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return WalkRepository._(db);
  }

  static Future<WalkRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 3,
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
  }

  static Future<void> _createSchema(Database db, int version) async {
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
  /// [duration] accumulated during recording, and the total route
  /// [distanceMetres], persisted so list queries never need the coordinates.
  Future<void> finishWalk(String walkId, DateTime endTime, Duration duration,
      double distanceMetres) async {
    await _db.update(
      'walks',
      {
        'end_time': endTime.millisecondsSinceEpoch,
        'duration_ms': duration.inMilliseconds,
        'distance': distanceMetres,
      },
      where: 'id = ?',
      whereArgs: [walkId],
    );
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
      coordinates: coordinates,
    );
  }

  Future<void> close() => _db.close();
}
