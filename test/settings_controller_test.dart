import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/settings_controller.dart';

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
}
