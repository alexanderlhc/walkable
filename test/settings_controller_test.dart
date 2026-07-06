import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/repository/settings_repository.dart';
import 'package:walkable/settings_controller.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
