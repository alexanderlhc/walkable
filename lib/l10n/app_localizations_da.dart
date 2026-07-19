// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Danish (`da`).
class AppLocalizationsDa extends AppLocalizations {
  AppLocalizationsDa([String locale = 'da']) : super(locale);

  @override
  String get appTitle => 'Walkable';

  @override
  String get navHistory => 'Tidligere gåture';

  @override
  String get actionStart => 'Start';

  @override
  String get actionStop => 'Stop';

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Fortsæt';

  @override
  String get actionCancel => 'Annullér';

  @override
  String get actionFinish => 'Afslut';

  @override
  String get actionRecenter => 'Centrér kort';

  @override
  String get actionDone => 'Færdig';

  @override
  String get actionViewRoute => 'Se rute';

  @override
  String get actionShare => 'Del';

  @override
  String get statDistance => 'Distance';

  @override
  String get statElapsed => 'Tid';

  @override
  String get statDuration => 'Varighed';

  @override
  String get statPace => 'Tempo';

  @override
  String get paceUnavailable => '--:--';

  @override
  String get durationUnavailable => '--';

  @override
  String get historyEmpty => 'Ingen gåture endnu';

  @override
  String get historyLoadError => 'Kunne ikke indlæse dine gåture';

  @override
  String get actionRetry => 'Prøv igen';

  @override
  String get screenWalkDetail => 'Gåtur';

  @override
  String get screenSettings => 'Indstillinger';

  @override
  String get settingsLanguage => 'Sprog';

  @override
  String get settingsSystemDefault => 'Systemstandard';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageDanish => 'Dansk';

  @override
  String get navMenu => 'Menu';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get themeLight => 'Lyst';

  @override
  String get themeDark => 'Mørkt';

  @override
  String get settingsUnits => 'Enheder';

  @override
  String get unitsKilometers => 'Kilometer';

  @override
  String get unitsMiles => 'Miles';

  @override
  String get locationPermissionDenied => 'Placeringstilladelse nægtet';

  @override
  String get foregroundDisclosureTitle => 'Adgang til placering';

  @override
  String get foregroundDisclosureBody =>
      'Walkable indsamler placeringsdata for at vise din position på kortet og registrere din gårute, mens du bruger appen. Dine placeringsdata forlader aldrig din enhed.\n\nDernæst beder Android dig om at tillade adgang til placering.';

  @override
  String get locationDisclosureTitle => 'Tillad placering i baggrunden';

  @override
  String get locationDisclosureBody =>
      'Walkable indsamler placeringsdata for at registrere din gårute og vise din position på kortet – også i baggrunden, selv når appen er lukket eller skærmen er slukket. Det holder din gåtur i gang, mens telefonen ligger i lommen. Din placering bruges kun, mens en gåtur registreres, og forlader aldrig din enhed.\n\nDernæst beder Android dig om at tillade placering “Hele tiden”.';

  @override
  String get locationDisclosureAccept => 'Fortsæt';

  @override
  String get locationDisclosureDecline => 'Ikke nu';

  @override
  String get backgroundTrackingWarning =>
      'Notifikationer er slået fra, så din gåtur kan stoppe med at blive registreret, når skærmen er låst.';

  @override
  String get batteryOptimizationWarning =>
      'Batterioptimiering er slået til, så din gåtur kan stoppe med at blive registreret, når skærmen er låst. Slå det fra i Indstillinger.';

  @override
  String get openSettings => 'Indstillinger';

  @override
  String get statusRecording => 'Optager';

  @override
  String get statusPaused => 'På pause';

  @override
  String get statusConfirmStop => 'Afslut gåtur?';

  @override
  String get walkCompleteTitle => 'Gåtur gennemført';

  @override
  String get walkCompleteSubtitle => 'Godt gået — din gåtur er gemt.';

  @override
  String get markerStart => 'Start';

  @override
  String get markerFinish => 'Mål';

  @override
  String shareWalkSummary(String distance, String duration) {
    return 'Jeg gik $distance på $duration med Walkable';
  }

  @override
  String locationError(String error) {
    return 'Kunne ikke hente placering: $error';
  }

  @override
  String walksRecovered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count afbrudte gåture blev gendannet til din historik',
      one: 'En afbrudt gåtur blev gendannet til din historik',
    );
    return '$_temp0';
  }

  @override
  String get notificationTitle => 'Gåtur i gang';

  @override
  String get notificationText => 'Walkable registrerer din gåtur';

  @override
  String unitKm(String value) {
    return '$value km';
  }

  @override
  String unitMi(String value) {
    return '$value mi';
  }

  @override
  String settingsVersion(String version, String build) {
    return 'Version $version ($build)';
  }
}
