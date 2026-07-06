import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walkable/units.dart';

/// Persists user settings. One key per setting; absence means "default".
class SettingsRepository {
  static const _localeKey = 'locale_override';
  static const _themeKey = 'theme_mode';
  static const _unitsKey = 'units_override';

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

  /// The persisted theme override. Absent, unknown, or corrupt data all mean
  /// "follow the system" — this never throws.
  ThemeMode readThemeMode() {
    String? name;
    try {
      name = _prefs.getString(_themeKey);
    } catch (_) {
      return ThemeMode.system; // corrupt/typed data -> follow system
    }
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> writeThemeMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      await _prefs.remove(_themeKey);
    } else {
      await _prefs.setString(_themeKey, mode.name);
    }
  }

  /// The persisted units override, or null to follow the system (derived
  /// from the device locale). Absent, unknown, or corrupt data all mean
  /// null — this never throws.
  UnitSystem? readUnitsOverride() {
    String? name;
    try {
      name = _prefs.getString(_unitsKey);
    } catch (_) {
      return null; // corrupt/typed data -> follow system
    }
    return switch (name) {
      'metric' => UnitSystem.metric,
      'imperial' => UnitSystem.imperial,
      _ => null,
    };
  }

  Future<void> writeUnitsOverride(UnitSystem? units) async {
    if (units == null) {
      await _prefs.remove(_unitsKey);
    } else {
      await _prefs.setString(_unitsKey, units.name);
    }
  }
}
