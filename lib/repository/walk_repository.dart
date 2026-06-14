import 'package:sqflite/sqflite.dart';
import 'package:walkable/models/walk.dart';

class WalkRepository {
  final Database _db;

  WalkRepository._(this._db);

  static Future<WalkRepository> inMemory() async {
    final db = await openDatabase(
      ':memory:',
      version: 1,
      onCreate: _createSchema,
    );
    return WalkRepository._(db);
  }

  static Future<WalkRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: _createSchema,
    );
    return WalkRepository._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
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

  /// Marks a walk finished by recording its end time.
  Future<void> finishWalk(String walkId, DateTime endTime) async {
    await _db.update(
      'walks',
      {'end_time': endTime.millisecondsSinceEpoch},
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

  Future<List<Walk>> findAll() async {
    final walkRows = await _db.query(
      'walks',
      orderBy: 'start_time DESC',
    );
    return Future.wait(walkRows.map(_hydrate));
  }

  Future<Walk> _hydrate(Map<String, dynamic> row) async {
    final walkId = row['id'] as String;
    final coordRows = await _db.query(
      'coordinates',
      where: 'walk_id = ?',
      whereArgs: [walkId],
      orderBy: 'sequence_index ASC',
    );

    final coordinates = coordRows.map((c) => Coordinate(
      lat: c['lat'] as double,
      lng: c['lng'] as double,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(c['recorded_at'] as int),
    )).toList();

    final endTimeMs = row['end_time'] as int?;

    return Walk(
      id: walkId,
      startTime: DateTime.fromMillisecondsSinceEpoch(row['start_time'] as int),
      endTime: endTimeMs != null ? DateTime.fromMillisecondsSinceEpoch(endTimeMs) : null,
      coordinates: coordinates,
    );
  }

  Future<void> close() => _db.close();
}
