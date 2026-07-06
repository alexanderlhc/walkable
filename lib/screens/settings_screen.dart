import 'package:flutter/material.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  final SettingsController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.screenSettings)),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                l10n.settingsLanguage,
                style: theme.textTheme.titleSmall!
                    .copyWith(color: theme.colorScheme.primary),
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}
