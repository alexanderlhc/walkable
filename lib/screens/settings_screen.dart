import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:walkable/auto_stop.dart';
import 'package:walkable/l10n/app_localizations.dart';
import 'package:walkable/power_settings.dart';
import 'package:walkable/settings_controller.dart';
import 'package:walkable/units.dart';

/// Walkable's privacy policy, published from docs/ on GitHub Pages.
final Uri privacyPolicyUrl =
    Uri.parse('https://alexanderlhc.github.io/walkable/');

class SettingsScreen extends StatelessWidget {
  final SettingsController controller;

  /// Backs the background-tracking shortcuts. Injectable for widget tests.
  final PowerSettings powerSettings;

  const SettingsScreen({
    super.key,
    required this.controller,
    this.powerSettings = const PowerSettings(),
  });

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
            _SectionHeader(l10n.settingsUnits),
            RadioGroup<UnitSystem?>(
              groupValue: controller.unitsOverride,
              onChanged: controller.setUnitsOverride,
              child: Column(
                children: [
                  RadioListTile<UnitSystem?>(
                    key: const Key('units_system'),
                    value: null,
                    title: Text(l10n.settingsSystemDefault),
                  ),
                  RadioListTile<UnitSystem?>(
                    key: const Key('units_km'),
                    value: UnitSystem.metric,
                    title: Text(l10n.unitsKilometers),
                  ),
                  RadioListTile<UnitSystem?>(
                    key: const Key('units_mi'),
                    value: UnitSystem.imperial,
                    title: Text(l10n.unitsMiles),
                  ),
                ],
              ),
            ),
            _SectionHeader(l10n.settingsAutoStop),
            RadioGroup<AutoStopLimit?>(
              groupValue: controller.autoStopLimit,
              onChanged: controller.setAutoStopLimit,
              child: Column(
                children: [
                  RadioListTile<AutoStopLimit?>(
                    key: const Key('auto_stop_off'),
                    value: null,
                    title: Text(l10n.autoStopOff),
                  ),
                  for (final limit in AutoStopLimit.values)
                    RadioListTile<AutoStopLimit?>(
                      key: Key('auto_stop_${limit.hours}h'),
                      value: limit,
                      title: Text(l10n.autoStopAfterHours(limit.hours)),
                    ),
                ],
              ),
            ),
            _SectionHeader(l10n.settingsBackgroundTracking),
            ListTile(
              key: const Key('battery_saver_settings'),
              leading: const Icon(Icons.battery_saver),
              title: Text(l10n.batterySaverSettings),
              subtitle: Text(l10n.settingsBatterySaverSubtitle),
              onTap: powerSettings.openBatterySaverSettings,
            ),
            _ManufacturerHelpTile(powerSettings),
            _SectionHeader(l10n.settingsAbout),
            _AboutTiles(powerSettings),
          ],
        ),
      ),
    );
  }
}

/// Links to dontkillmyapp.com's steps for this phone's maker, on phones whose
/// own battery manager can stop the walk's foreground service despite the
/// battery-optimisation exemption. Absent elsewhere.
class _ManufacturerHelpTile extends StatefulWidget {
  final PowerSettings powerSettings;

  const _ManufacturerHelpTile(this.powerSettings);

  @override
  State<_ManufacturerHelpTile> createState() => _ManufacturerHelpTileState();
}

class _ManufacturerHelpTileState extends State<_ManufacturerHelpTile> {
  // Fetched once: the settings list rebuilds on every setting change.
  late final Future<Uri?> _page = widget.powerSettings.manufacturerHelpPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return FutureBuilder<Uri?>(
      future: _page,
      builder: (context, snapshot) {
        final page = snapshot.data;
        if (page == null) return const SizedBox.shrink();
        return ListTile(
          key: const Key('manufacturer_help'),
          leading: const Icon(Icons.open_in_new),
          title: Text(l10n.settingsManufacturerHelp),
          subtitle: Text(l10n.settingsManufacturerHelpSubtitle),
          onTap: () => widget.powerSettings.openPage(page),
        );
      },
    );
  }
}

/// The About section's rows: the version, the privacy policy and the
/// open-source licenses.
class _AboutTiles extends StatefulWidget {
  /// Opens the privacy policy, like the dontkillmyapp.com link.
  final PowerSettings powerSettings;

  const _AboutTiles(this.powerSettings);

  @override
  State<_AboutTiles> createState() => _AboutTilesState();
}

class _AboutTilesState extends State<_AboutTiles> {
  // Fetched once: the settings list rebuilds on every setting change.
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Column(
          children: [
            if (info != null)
              ListTile(
                key: const Key('version'),
                leading: const Icon(Icons.info_outline),
                title:
                    Text(l10n.settingsVersion(info.version, info.buildNumber)),
              ),
            ListTile(
              key: const Key('privacy_policy'),
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l10n.settingsPrivacyPolicy),
              onTap: () => widget.powerSettings.openPage(privacyPolicyUrl),
            ),
            ListTile(
              key: const Key('licenses'),
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.settingsLicenses),
              onTap: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationVersion: info == null
                    ? null
                    : l10n.settingsVersion(info.version, info.buildNumber),
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    key: const Key('license_page_icon'),
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset('assets/app_icon.png', width: 64),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// M3 settings-section header: primary-colored titleSmall with list-inset
/// padding. Shared by every settings section.
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
