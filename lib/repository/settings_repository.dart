import 'package:shared_preferences/shared_preferences.dart';

/// Persists user settings. One key per setting; absence means "default".
class SettingsRepository {
  static const _localeKey = 'locale_override';

  final SharedPreferences _prefs;

  SettingsRepository(this._prefs);

  /// The persisted language-code override, or null to follow the system.
  String? readLocaleCode() => _prefs.getString(_localeKey);

  Future<void> writeLocaleCode(String? code) async {
    if (code == null) {
      await _prefs.remove(_localeKey);
    } else {
      await _prefs.setString(_localeKey, code);
    }
  }
}
