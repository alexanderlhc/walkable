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
  String get actionDone => 'Done';

  @override
  String get actionViewRoute => 'View route';

  @override
  String get actionShare => 'Share';

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
  String get screenSettings => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsSystemDefault => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageDanish => 'Dansk';

  @override
  String get navMenu => 'Menu';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsUnits => 'Units';

  @override
  String get unitsKilometers => 'Kilometers';

  @override
  String get unitsMiles => 'Miles';

  @override
  String get locationPermissionDenied => 'Location permission denied';

  @override
  String get foregroundDisclosureTitle => 'Location access';

  @override
  String get foregroundDisclosureBody =>
      'Walkable collects location data to show your live position on the map and to record your walking route while you use the app. Your location data never leaves your device.\n\nNext, Android will ask you to allow location access.';

  @override
  String get locationDisclosureTitle => 'Allow background location';

  @override
  String get locationDisclosureBody =>
      'Walkable collects location data to record your walking route and show your live position on the map — including in the background, even when the app is closed or the screen is off. This keeps your walk recording while your phone is in your pocket. Your location is only used while a walk is running and never leaves your device.\n\nNext, Android will ask you to allow location access “All the time”.';

  @override
  String get locationDisclosureAccept => 'Continue';

  @override
  String get locationDisclosureDecline => 'Not now';

  @override
  String get backgroundTrackingWarning =>
      'Notifications are off, so your walk may stop recording when the screen is locked.';

  @override
  String get batteryOptimizationWarning =>
      'Battery optimisation is on, so your walk may stop recording when the screen is locked. Disable it in Settings.';

  @override
  String get batterySaverLocationWarning =>
      'Battery Saver turns off location while the screen is locked, so your walk may have gaps. Turn Battery Saver off, or keep the screen on.';

  @override
  String get leaveWalkTitle => 'Walk in progress';

  @override
  String get leaveWalkBody =>
      'Your walk is still recording. Keep recording, or stop and save it?';

  @override
  String get leaveWalkKeepRecording => 'Keep recording';

  @override
  String get leaveWalkStop => 'Stop walk';

  @override
  String get openSettings => 'Settings';

  @override
  String get statusRecording => 'Recording';

  @override
  String get statusNoSignal => 'No GPS signal';

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusConfirmStop => 'Finish walk?';

  @override
  String get walkCompleteTitle => 'Walk complete';

  @override
  String get walkCompleteSubtitle => 'Nice one — your walk has been saved.';

  @override
  String get markerStart => 'Start';

  @override
  String get markerFinish => 'Finish';

  @override
  String shareWalkSummary(String distance, String duration) {
    return 'I walked $distance in $duration with Walkable';
  }

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

  @override
  String unitMi(String value) {
    return '$value mi';
  }

  @override
  String settingsVersion(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get settingsAutoStop => 'Auto-stop walk';

  @override
  String get autoStopOff => 'Off';

  @override
  String autoStopAfterHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'After $hours hours',
      one: 'After 1 hour',
    );
    return '$_temp0';
  }

  @override
  String walkAutoStoppedNote(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Walk stopped automatically after $hours hours',
      one: 'Walk stopped automatically after 1 hour',
    );
    return '$_temp0';
  }

  @override
  String get autoStopWarningTitle => 'Still walking?';

  @override
  String autoStopWarningCountdown(String time) {
    return 'Your walk will stop in $time';
  }

  @override
  String get actionKeepWalking => 'Keep walking';

  @override
  String get actionStopNow => 'Stop now';
}
