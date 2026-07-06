import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/screens/settings_screen.dart';
import 'package:walkable/settings_controller.dart';

void main() {
  late SettingsController controller;

  Future<void> setUpController(Map<String, Object> initialPrefs) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    controller = SettingsController(SettingsRepository(prefs))..load();
  }

  Widget buildSubject({Locale locale = const Locale('en')}) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(controller: controller),
      );

  testWidgets('shows language section with the three options', (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject());

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
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

    final group = tester
        .widget<RadioGroup<Locale?>>(find.byType(RadioGroup<Locale?>));
    expect(group.groupValue, isNull);
  });

  testWidgets('persisted override is the selected radio', (tester) async {
    await setUpController({'locale_override': 'da'});
    await tester.pumpWidget(buildSubject());

    final group = tester
        .widget<RadioGroup<Locale?>>(find.byType(RadioGroup<Locale?>));
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

  testWidgets('renders Danish strings under the Danish locale',
      (tester) async {
    await setUpController({});
    await tester.pumpWidget(buildSubject(locale: const Locale('da')));

    expect(find.text('Indstillinger'), findsOneWidget);
    expect(find.text('Sprog'), findsOneWidget);
    expect(find.text('Systemstandard'), findsOneWidget);
  });
}
