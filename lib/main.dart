import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/active_walk_screen.dart';
import 'package:walkable/screens/walk_detail_screen.dart';
import 'package:walkable/walk_recorder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbPath = p.join(await getDatabasesPath(), 'walkable.db');
  final repository = await WalkRepository.open(dbPath);
  final locationService = LocationService();
  final recorder = WalkRecorder(
    locationService: locationService,
    repository: repository,
  );
  runApp(WalkableApp(recorder: recorder, repository: repository));
}

class WalkableApp extends StatelessWidget {
  final WalkRecorder recorder;
  final WalkRepository repository;

  const WalkableApp({
    super.key,
    required this.recorder,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Walkable',
      onGenerateRoute: (settings) {
        if (settings.name == '/walk-detail') {
          final walk = settings.arguments as Walk;
          return MaterialPageRoute(
            builder: (_) => WalkDetailScreen(walk: walk),
          );
        }
        return null;
      },
      home: ActiveWalkScreen(recorder: recorder, repository: repository),
    );
  }
}
