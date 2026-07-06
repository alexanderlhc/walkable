import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/location/location_service.dart';
import 'package:walkable/models/walk.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/repository/walk_repository.dart';
import 'package:walkable/screens/active_walk_screen.dart';
import 'package:walkable/screens/walk_detail_screen.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/theme.dart';
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
  // Salvage walks orphaned by a mid-walk process death before the UI can
  // query the repository. Best-effort: a recovery failure must not stop the
  // app from launching.
  var recoveredWalks = 0;
  try {
    recoveredWalks = await repository.recoverOrphans();
  } catch (e) {
    debugPrint('main: orphaned-walk recovery failed: $e');
  }
  final locationService = LocationService();
  final recorder = WalkRecorder(
    locationService: locationService,
    repository: repository,
  );
  final prefs = await SharedPreferences.getInstance();
  final settingsController = SettingsController(SettingsRepository(prefs))
    ..load();
  runApp(WalkableApp(
    recorder: recorder,
    repository: repository,
    settingsController: settingsController,
    recoveredWalkCount: recoveredWalks,
  ));
}

class WalkableApp extends StatelessWidget {
  final WalkRecorder recorder;
  final WalkRepository repository;
  final SettingsController settingsController;

  /// How many orphaned walks startup recovery salvaged into the history; the
  /// main screen announces them once when the count is positive.
  final int recoveredWalkCount;

  const WalkableApp({
    super.key,
    required this.recorder,
    required this.repository,
    required this.settingsController,
    this.recoveredWalkCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settingsController,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        // Null (no override) falls through to the device locale via the
        // resolution callback below.
        locale: settingsController.localeOverride,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Match the device language; fall back to English for anything we
        // don't translate (rather than the first supported locale, which is
        // Danish).
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
        home: ActiveWalkScreen(
          recorder: recorder,
          repository: repository,
          settingsController: settingsController,
          recoveredWalkCount: recoveredWalkCount,
        ),
      ),
    );
  }
}
