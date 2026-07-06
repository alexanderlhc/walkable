// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Walkable';

  @override
  String get navHistory => 'Walk History';

  @override
  String get actionStart => 'Start';

  @override
  String get actionStop => 'Stop';

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Resume';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionFinish => 'Finish';

  @override
  String get actionRecenter => 'Recenter map';

  @override
  String get statDistance => 'Distance';

  @override
  String get statElapsed => 'Elapsed';

  @override
  String get statDuration => 'Duration';

  @override
  String get statPace => 'Pace';

  @override
  String get paceUnavailable => '--:--';

  @override
  String get durationUnavailable => '--';

  @override
  String get historyEmpty => 'No walks yet';

  @override
  String get historyLoadError => 'Couldn\'t load your walks';

  @override
  String get actionRetry => 'Try again';

  @override
  String get screenWalkDetail => 'Walk Detail';

  @override
  String get locationPermissionDenied => 'Location permission denied';

  @override
  String get backgroundTrackingWarning =>
      'Notifications are off, so your walk may stop recording when the screen is locked.';

  @override
  String get batteryOptimizationWarning =>
      'Battery optimisation is on, so your walk may stop recording when the screen is locked. Disable it in Settings.';

  @override
  String get openSettings => 'Settings';

  @override
  String get statusRecording => 'Recording';

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusConfirmStop => 'Finish walk?';

  @override
  String locationError(String error) {
    return 'Could not get location: $error';
  }

  @override
  String walksRecovered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Recovered $count interrupted walks to your history',
      one: 'Recovered an interrupted walk to your history',
    );
    return '$_temp0';
  }

  @override
  String get notificationTitle => 'Walk in progress';

  @override
  String get notificationText => 'Walkable is recording your walk';

  @override
  String unitKm(String value) {
    return '$value km';
  }
}
