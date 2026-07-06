import 'package:flutter/material.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  final SettingsController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.screenSettings)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          children: [
            _SectionHeader(l10n.settingsLanguage),
            RadioGroup<Locale?>(
              groupValue: controller.localeOverride,
              onChanged: controller.setLocaleOverride,
              child: Column(
                children: [
                  RadioListTile<Locale?>(
                    key: const Key('language_system'),
                    value: null,
                    title: Text(l10n.settingsSystemDefault),
                  ),
                  RadioListTile<Locale?>(
                    key: const Key('language_en'),
                    value: const Locale('en'),
                    title: Text(l10n.languageEnglish),
                  ),
                  RadioListTile<Locale?>(
                    key: const Key('language_da'),
                    value: const Locale('da'),
                    title: Text(l10n.languageDanish),
                  ),
                ],
              ),
            ),
            _SectionHeader(l10n.settingsTheme),
            RadioGroup<ThemeMode>(
              groupValue: controller.themeMode,
              onChanged: (mode) =>
                  controller.setThemeMode(mode ?? ThemeMode.system),
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_system'),
                    value: ThemeMode.system,
                    title: Text(l10n.settingsSystemDefault),
                  ),
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_light'),
                    value: ThemeMode.light,
                    title: Text(l10n.themeLight),
                  ),
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_dark'),
                    value: ThemeMode.dark,
                    title: Text(l10n.themeDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// M3 settings-section header: primary-colored titleSmall with list-inset
/// padding. Shared by the language and theme sections.
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall!
            .copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
