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
  String get screenWalkDetail => 'Gåtur';

  @override
  String get locationPermissionDenied => 'Placeringstilladelse nægtet';

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
  String locationError(String error) {
    return 'Kunne ikke hente placering: $error';
  }

  @override
  String get notificationTitle => 'Gåtur i gang';

  @override
  String get notificationText => 'Walkable registrerer din gåtur';

  @override
  String unitKm(String value) {
    return '$value km';
  }
}
