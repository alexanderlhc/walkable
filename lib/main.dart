import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:walkable/auto_stop_alerts.dart';
import 'package:walkable/auto_stop_notifications.dart';
import 'package:walkable/battery_saver_notifications.dart';
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
  // Draw behind the system bars on every Android version. Android 15+ enforces
  // edge-to-edge anyway, but enabling it here (not only natively) makes it
  // consistent for users on Android 14 and below too — the gap behind Play
  // Console's "edge-to-edge may not display for all users" advisory.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
  final prefs = await SharedPreferences.getInstance();
  final settingsController = SettingsController(SettingsRepository(prefs))
    ..load();
  final locationService = LocationService();
  // System notifications are Android-only; the desktop builds used for
  // development go without.
  AppLocalizations localizations() =>
      lookupAppLocalizations(settingsController.localeOverride ??
          resolveAppLocale(PlatformDispatcher.instance.locale));
  final android = defaultTargetPlatform == TargetPlatform.android;
  final AutoStopAlerts alerts = android
      ? AutoStopNotifications(localizations: localizations)
      : const NoAutoStopAlerts();
  final BatterySaverAlerts batterySaverAlerts = android
      ? BatterySaverNotifications(localizations: localizations)
      : const NoBatterySaverAlerts();
  final recorder = WalkRecorder(
    locationService: locationService,
    repository: repository,
    alerts: alerts,
  );
  if (alerts is AutoStopNotifications) {
    await alerts.initialize(
      onKeepWalking: recorder.keepWalking,
      onStopNow: recorder.stopNow,
    );
    // Like the auto-stop alerts: a fresh process has no walk for a Battery
    // Saver warning left by a dead one to be about.
    await batterySaverAlerts.cancelWarning();
  }
  runApp(WalkableApp(
    recorder: recorder,
    repository: repository,
    settingsController: settingsController,
    recoveredWalkCount: recoveredWalks,
    batterySaverAlerts: batterySaverAlerts,
  ));
  // The release smoke test (tool/release_smoke_test.sh) waits for this line:
  // proof that startup got past the splash screen. Keep it in sync.
  WidgetsBinding.instance.waitUntilFirstFrameRasterized
      .then((_) => debugPrint('walkable: first frame rasterized'));
}

/// The supported locale matching the device language. Anything we don't
/// translate falls back to English, rather than to the first supported
/// locale, which is Danish.
Locale resolveAppLocale(Locale? deviceLocale) {
  for (final locale in AppLocalizations.supportedLocales) {
    if (locale.languageCode == deviceLocale?.languageCode) return locale;
  }
  return const Locale('en');
}

class WalkableApp extends StatelessWidget {
  final WalkRecorder recorder;
  final WalkRepository repository;
  final SettingsController settingsController;

  /// How many orphaned walks startup recovery salvaged into the history; the
  /// main screen announces them once when the count is positive.
  final int recoveredWalkCount;

  /// Announces Battery Saver cutting location mid-walk outside the app.
  final BatterySaverAlerts batterySaverAlerts;

  const WalkableApp({
    super.key,
    required this.recorder,
    required this.repository,
    required this.settingsController,
    this.recoveredWalkCount = 0,
    this.batterySaverAlerts = const NoBatterySaverAlerts(),
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settingsController,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        // User theme override; ThemeMode.system follows the device.
        themeMode: settingsController.themeMode,
        // Null (no override) falls through to the device locale via the
        // resolution callback below.
        locale: settingsController.localeOverride,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Match the device language, falling back to English.
        localeResolutionCallback: (deviceLocale, _) =>
            resolveAppLocale(deviceLocale),
        onGenerateRoute: (settings) {
          if (settings.name == '/walk-detail') {
            final walk = settings.arguments as Walk;
            return MaterialPageRoute(
              builder: (_) => WalkDetailScreen(
                walk: walk,
                settingsController: settingsController,
              ),
            );
          }
          return null;
        },
        home: ActiveWalkScreen(
          recorder: recorder,
          repository: repository,
          settingsController: settingsController,
          recoveredWalkCount: recoveredWalkCount,
          batterySaverAlerts: batterySaverAlerts,
        ),
      ),
    );
  }
}
