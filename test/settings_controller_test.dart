import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/units.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => registerFallbackValue(ThemeMode.system));

  Future<SettingsController> buildController(
      Map<String, Object> initialPrefs) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    return SettingsController(SettingsRepository(prefs));
  }

  group('load', () {
    test('no stored value -> follows system (null override)', () async {
      final controller = await buildController({});
      controller.load();
      expect(controller.localeOverride, isNull);
    });

    test('stored "da" -> Danish override', () async {
      final controller = await buildController({'locale_override': 'da'});
      controller.load();
      expect(controller.localeOverride, const Locale('da'));
    });

    test('unsupported stored code -> follows system', () async {
      final controller = await buildController({'locale_override': 'de'});
      controller.load();
      expect(controller.localeOverride, isNull);
    });

    test('read failure -> follows system', () {
      final repository = MockSettingsRepository();
      when(() => repository.readThemeMode()).thenReturn(ThemeMode.system);
      when(() => repository.readLocaleCode()).thenThrow(TypeError());
      when(() => repository.readUnitsOverride()).thenReturn(null);
      when(() => repository.readAutoStopAfter()).thenReturn(null);
      final controller = SettingsController(repository);

      controller.load();

      expect(controller.localeOverride, isNull);
    });
  });

  group('setLocaleOverride', () {
    test('updates value, notifies, and persists', () async {
      final controller = await buildController({});
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setLocaleOverride(const Locale('da'));

      expect(controller.localeOverride, const Locale('da'));
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale_override'), 'da');
    });

    test('null clears the stored value (back to system)', () async {
      final controller = await buildController({'locale_override': 'da'});
      controller.load();

      await controller.setLocaleOverride(null);

      expect(controller.localeOverride, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale_override'), isNull);
    });

    test('persistence failure keeps the in-memory value', () async {
      final repository = MockSettingsRepository();
      when(() => repository.writeLocaleCode(any()))
          .thenThrow(Exception('disk full'));
      final controller = SettingsController(repository);

      await controller.setLocaleOverride(const Locale('en'));

      expect(controller.localeOverride, const Locale('en'));
    });
  });

  group('themeMode', () {
    test('defaults to system when nothing is stored', () async {
      final controller = await buildController({});
      controller.load();
      expect(controller.themeMode, ThemeMode.system);
    });

    test('restores a persisted dark override', () async {
      final controller = await buildController({'theme_mode': 'dark'});
      controller.load();
      expect(controller.themeMode, ThemeMode.dark);
    });

    test('unknown stored value -> system', () async {
      final controller = await buildController({'theme_mode': 'sepia'});
      controller.load();
      expect(controller.themeMode, ThemeMode.system);
    });

    test('type-corrupt stored value -> system', () async {
      // A non-string under the key makes SharedPreferences.getString throw;
      // readThemeMode must swallow that and follow the system.
      final controller = await buildController({'theme_mode': 42});
      controller.load();
      expect(controller.themeMode, ThemeMode.system);
    });

    test('setThemeMode updates, notifies, and persists', () async {
      final controller = await buildController({});
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setThemeMode(ThemeMode.dark);

      expect(controller.themeMode, ThemeMode.dark);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
    });

    test('selecting system removes the stored value', () async {
      final controller = await buildController({'theme_mode': 'dark'});
      controller.load();

      await controller.setThemeMode(ThemeMode.system);

      expect(controller.themeMode, ThemeMode.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), isNull);
    });

    test('persistence failure keeps the in-memory value', () async {
      final repository = MockSettingsRepository();
      when(() => repository.writeThemeMode(any()))
          .thenThrow(Exception('disk full'));
      final controller = SettingsController(repository);

      await controller.setThemeMode(ThemeMode.dark);

      expect(controller.themeMode, ThemeMode.dark);
    });
  });

  group('unitsOverride', () {
    test('defaults to null (system) when nothing is stored', () async {
      final controller = await buildController({});
      controller.load();
      expect(controller.unitsOverride, isNull);
    });

    test('restores a persisted imperial override', () async {
      final controller = await buildController({'units_override': 'imperial'});
      controller.load();
      expect(controller.unitsOverride, UnitSystem.imperial);
    });

    test('unknown stored value -> system', () async {
      final controller = await buildController({'units_override': 'nautical'});
      controller.load();
      expect(controller.unitsOverride, isNull);
    });

    test('type-corrupt stored value -> system', () async {
      final controller = await buildController({'units_override': 42});
      controller.load();
      expect(controller.unitsOverride, isNull);
    });

    test('setUnitsOverride updates, notifies, and persists', () async {
      final controller = await buildController({});
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setUnitsOverride(UnitSystem.imperial);

      expect(controller.unitsOverride, UnitSystem.imperial);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('units_override'), 'imperial');
    });

    test('null clears the stored value (back to system)', () async {
      final controller = await buildController({'units_override': 'metric'});
      controller.load();

      await controller.setUnitsOverride(null);

      expect(controller.unitsOverride, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('units_override'), isNull);
    });

    test('persistence failure keeps the in-memory value', () async {
      final repository = MockSettingsRepository();
      when(() => repository.writeUnitsOverride(any()))
          .thenThrow(Exception('disk full'));
      final controller = SettingsController(repository);

      await controller.setUnitsOverride(UnitSystem.metric);

      expect(controller.unitsOverride, UnitSystem.metric);
    });
  });

  group('autoStopAfter', () {
    test('defaults to null (Off) when nothing is stored', () async {
      final controller = await buildController({});
      controller.load();
      expect(controller.autoStopAfter, isNull);
    });

    test('restores a persisted 2 h limit', () async {
      final controller =
          await buildController({'auto_stop_after_minutes': 120});
      controller.load();
      expect(controller.autoStopAfter, const Duration(hours: 2));
    });

    test('unknown stored value -> Off', () async {
      final controller = await buildController({'auto_stop_after_minutes': 90});
      controller.load();
      expect(controller.autoStopAfter, isNull);
    });

    test('type-corrupt stored value -> Off', () async {
      final controller =
          await buildController({'auto_stop_after_minutes': 'two hours'});
      controller.load();
      expect(controller.autoStopAfter, isNull);
    });

    test('setAutoStopAfter updates, notifies, and persists', () async {
      final controller = await buildController({});
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.setAutoStopAfter(const Duration(hours: 4));

      expect(controller.autoStopAfter, const Duration(hours: 4));
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('auto_stop_after_minutes'), 240);
    });

    test('null (Off) removes the stored key', () async {
      final controller = await buildController({'auto_stop_after_minutes': 60});
      controller.load();

      await controller.setAutoStopAfter(null);

      expect(controller.autoStopAfter, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('auto_stop_after_minutes'), isFalse);
    });

    test('persistence failure keeps the in-memory value', () async {
      final repository = MockSettingsRepository();
      when(() => repository.writeAutoStopAfter(any()))
          .thenThrow(Exception('disk full'));
      final controller = SettingsController(repository);

      await controller.setAutoStopAfter(const Duration(hours: 1));

      expect(controller.autoStopAfter, const Duration(hours: 1));
    });
  });
}
