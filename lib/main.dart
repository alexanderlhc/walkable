import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/active_walk_screen.dart';
import 'package:walkable/screens/walk_detail_screen.dart';
import 'package:walkable/walk_recorder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
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
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Match the device language; fall back to English for anything we don't
      // translate (rather than the first supported locale, which is Danish).
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        for (final locale in supportedLocales) {
          if (locale.languageCode == deviceLocale?.languageCode) {
            return locale;
          }
        }
        return const Locale('en');
      },
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
