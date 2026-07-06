import 'package:flutter/widgets.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/repository/settings_repository.dart';

/// App-level user settings. Null [localeOverride] means "follow the system".
class SettingsController extends ChangeNotifier {
  final SettingsRepository repository;

  Locale? _localeOverride;

  SettingsController(this.repository);

  Locale? get localeOverride => _localeOverride;

  /// Restores the persisted override. A code we no longer support (or
  /// corrupt data) degrades to following the system rather than crashing.
  ///
  /// Deliberately doesn't notify: this must run before the first build
  /// (main() calls it before runApp), so there are no listeners yet.
  void load() {
    String? code;
    try {
      code = repository.readLocaleCode();
    } catch (_) {
      return; // corrupt/typed data -> follow system
    }
    if (code == null) return;
    final supported = AppLocalizations.supportedLocales
        .any((locale) => locale.languageCode == code);
    _localeOverride = supported ? Locale(code) : null;
  }

  Future<void> setLocaleOverride(Locale? locale) async {
    _localeOverride = locale;
    notifyListeners();
    try {
      await repository.writeLocaleCode(locale?.languageCode);
    } catch (_) {
      // The choice still applies this session; it just won't survive a
      // restart.
    }
  }
}
