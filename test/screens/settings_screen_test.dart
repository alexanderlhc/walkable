import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/auto_stop.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/power_settings.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/screens/settings_screen.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/units.dart';

class FakePowerSettings implements PowerSettings {
  int batterySaverSettingsOpened = 0;
  Uri? helpPage;
  final openedPages = <Uri>[];

  @override
  Future<bool> openBatterySaverSettings() async {
    batterySaverSettingsOpened++;
    return true;
  }

  @override
  Future<Uri?> manufacturerHelpPage() async => helpPage;

  @override
  Future<void> openPage(Uri page) async => openedPages.add(page);
}

void main() {
  late SettingsController controller;
  late FakePowerSettings powerSettings;

  setUp(() {
    powerSettings = FakePowerSettings();
    PackageInfo.setMockInitialValues(
      appName: 'Walkable',
      packageName: 'dk.raskrask.walkable',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
      installerStore: null,
    );
  });

  Future<void> setUpController(Map<String, Object> initialPrefs) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    controller = SettingsController(SettingsRepository(prefs))..load();
  }

  Widget buildSubject({Locale locale = const Locale('en')}) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          controller: controller,
          powerSettings: powerSettings,
        ),
      );

  testWidgets('shows language section with the three options', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('System default'),
        findsNWidgets(3)); // language + theme + units
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Dansk'), findsOneWidget);
  });

  // Selection state lives on the RadioGroup ancestor (per-tile groupValue —
  // and the `checked` getter built on it — is deprecated in Flutter 3.44 and
  // unset here, so don't assert on tile.checked).
  testWidgets('system default is selected when there is no override',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    final group =
        tester.widget<RadioGroup<Locale?>>(find.byType(RadioGroup<Locale?>));
    expect(group.groupValue, isNull);
  });

  testWidgets('persisted override is the selected radio', (tester) async {
    await setUpController({'locale_override': 'da'});
    await tester.pumpWidget(buildSubject());

    final group =
        tester.widget<RadioGroup<Locale?>>(find.byType(RadioGroup<Locale?>));
    expect(group.groupValue, const Locale('da'));
  });

  testWidgets('tapping Dansk updates the controller and persists',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('language_da')));
    await tester.pumpAndSettle();

    expect(controller.localeOverride, const Locale('da'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('locale_override'), 'da');
  });

  testWidgets('tapping English updates the controller and persists',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('language_en')));
    await tester.pumpAndSettle();

    expect(controller.localeOverride, const Locale('en'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('locale_override'), 'en');
  });

  testWidgets('tapping System default clears the override', (tester) async {
    await setUpController({'locale_override': 'da'});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('language_system')));
    await tester.pumpAndSettle();

    expect(controller.localeOverride, isNull);
  });

  testWidgets('renders Danish strings under the Danish locale', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));

    expect(find.text('Indstillinger'), findsOneWidget);
    expect(find.text('Sprog'), findsOneWidget);
    expect(find.text('Systemstandard'),
        findsNWidgets(3)); // language + theme + units
  });

  testWidgets('shows theme section with the three options', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('system theme is selected when there is no override',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>));
    expect(group.groupValue, ThemeMode.system);
  });

  testWidgets('persisted theme override is the selected radio', (tester) async {
    await setUpController({'theme_mode': 'dark'});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>));
    expect(group.groupValue, ThemeMode.dark);
  });

  testWidgets('tapping Dark updates the controller and persists',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('theme_dark')));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  });

  testWidgets('tapping System default clears the theme override',
      (tester) async {
    await setUpController({'theme_mode': 'dark'});
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const Key('theme_system')));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.system);
  });

  testWidgets('renders Danish theme strings under the Danish locale',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));

    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('Lyst'), findsOneWidget);
    expect(find.text('Mørkt'), findsOneWidget);
  });

  testWidgets('shows units section with the three options', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    expect(find.text('Units'), findsOneWidget);
    expect(find.text('Kilometers'), findsOneWidget);
    expect(find.text('Miles'), findsOneWidget);
  });

  testWidgets('system units selected when there is no override',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<UnitSystem?>>(find.byType(RadioGroup<UnitSystem?>));
    expect(group.groupValue, isNull);
  });

  testWidgets('tapping Miles updates the controller and persists',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.scrollUntilVisible(find.byKey(const Key('units_mi')), 500);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('units_mi')));
    await tester.pumpAndSettle();

    expect(controller.unitsOverride, UnitSystem.imperial);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('units_override'), 'imperial');
  });

  testWidgets('tapping System default clears the units override',
      (tester) async {
    await setUpController({'units_override': 'imperial'});
    await tester.pumpWidget(buildSubject());

    await tester.scrollUntilVisible(find.byKey(const Key('units_system')), 500);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('units_system')));
    await tester.pumpAndSettle();

    expect(controller.unitsOverride, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('units_override'), isNull);
  });

  testWidgets('renders Danish units strings under the Danish locale',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));

    expect(find.text('Enheder'), findsOneWidget);
    expect(find.text('Kilometer'), findsOneWidget);
    expect(find.text('Miles'), findsOneWidget);
  });

  testWidgets('shows auto-stop section with Off and the three limits',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.scrollUntilVisible(find.byKey(const Key('auto_stop_4h')), 500);
    await tester.pumpAndSettle();

    expect(find.text('Auto-stop walk'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('After 1 hour'), findsOneWidget);
    expect(find.text('After 2 hours'), findsOneWidget);
    expect(find.text('After 4 hours'), findsOneWidget);
  });

  testWidgets('Off is selected when nothing is stored', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());
    // The section sits below the fold; ListView builds it lazily.
    await tester.scrollUntilVisible(find.byKey(const Key('auto_stop_4h')), 500);
    await tester.pumpAndSettle();

    final group = tester.widget<RadioGroup<AutoStopLimit?>>(
        find.byType(RadioGroup<AutoStopLimit?>));
    expect(group.groupValue, isNull);
  });

  testWidgets('persisted auto-stop limit is the selected radio',
      (tester) async {
    await setUpController({'auto_stop_limit': 'twoHours'});
    await tester.pumpWidget(buildSubject());
    // The section sits below the fold; ListView builds it lazily.
    await tester.scrollUntilVisible(find.byKey(const Key('auto_stop_4h')), 500);
    await tester.pumpAndSettle();

    final group = tester.widget<RadioGroup<AutoStopLimit?>>(
        find.byType(RadioGroup<AutoStopLimit?>));
    expect(group.groupValue, AutoStopLimit.twoHours);
  });

  testWidgets('tapping After 2 hours updates the controller and persists',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    await tester.scrollUntilVisible(find.byKey(const Key('auto_stop_2h')), 500);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto_stop_2h')));
    await tester.pumpAndSettle();

    expect(controller.autoStopLimit, AutoStopLimit.twoHours);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auto_stop_limit'), 'twoHours');
  });

  testWidgets('tapping Off removes the stored auto-stop limit', (tester) async {
    await setUpController({'auto_stop_limit': 'oneHour'});
    await tester.pumpWidget(buildSubject());

    await tester.scrollUntilVisible(
        find.byKey(const Key('auto_stop_off')), 500);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto_stop_off')));
    await tester.pumpAndSettle();

    expect(controller.autoStopLimit, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('auto_stop_limit'), isFalse);
  });

  testWidgets('renders Danish auto-stop strings under the Danish locale',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));

    await tester.scrollUntilVisible(find.byKey(const Key('auto_stop_4h')), 500);
    await tester.pumpAndSettle();

    expect(find.text('Automatisk stop gåtur'), findsOneWidget);
    expect(find.text('Fra'), findsOneWidget);
    expect(find.text('Efter 1 time'), findsOneWidget);
    expect(find.text('Efter 2 timer'), findsOneWidget);
    expect(find.text('Efter 4 timer'), findsOneWidget);
  });

  testWidgets('shows the app version and build number at the bottom',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Version 1.2.3 (45)'), 500);
    expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
  });

  // ─── background tracking ───────────────────────────────────────────────────

  testWidgets('opens the Battery Saver settings', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('battery_saver_settings'));
    await tester.scrollUntilVisible(tile, 500);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);

    expect(powerSettings.batterySaverSettingsOpened, 1);
  });

  testWidgets('links to dontkillmyapp.com on phones whose maker kills apps',
      (tester) async {
    final page = Uri.parse('https://dontkillmyapp.com/samsung');
    powerSettings.helpPage = page;
    await setUpController({});
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('manufacturer_help'));
    await tester.scrollUntilVisible(tile, 500);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(find.text('Keep walks recording'), findsOneWidget);
    await tester.tap(tile);

    expect(powerSettings.openedPages, [page]);
  });

  testWidgets('has no dontkillmyapp.com link on other phones', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Version 1.2.3 (45)'), 500);
    expect(find.byKey(const Key('manufacturer_help')), findsNothing);
  });

  testWidgets('renders Danish background-tracking strings', (tester) async {
    powerSettings.helpPage = Uri.parse('https://dontkillmyapp.com/xiaomi');
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.byKey(const Key('manufacturer_help')), 500);
    expect(find.text('Sporing i baggrunden'), findsOneWidget);
    expect(find.text('Batterisparefunktion'), findsOneWidget);
    expect(find.text('Hold gåture i gang'), findsOneWidget);
  });
}
