import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_da.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('da'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Walkable'**
  String get appTitle;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'Walk History'**
  String get navHistory;

  /// No description provided for @actionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get actionStart;

  /// No description provided for @actionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get actionStop;

  /// No description provided for @actionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// No description provided for @actionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get actionFinish;

  /// No description provided for @actionRecenter.
  ///
  /// In en, this message translates to:
  /// **'Recenter map'**
  String get actionRecenter;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionViewRoute.
  ///
  /// In en, this message translates to:
  /// **'View route'**
  String get actionViewRoute;

  /// No description provided for @actionShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionShare;

  /// No description provided for @statDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get statDistance;

  /// No description provided for @statElapsed.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get statElapsed;

  /// No description provided for @statDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get statDuration;

  /// No description provided for @statPace.
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get statPace;

  /// No description provided for @paceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'--:--'**
  String get paceUnavailable;

  /// No description provided for @durationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'--'**
  String get durationUnavailable;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No walks yet'**
  String get historyEmpty;

  /// No description provided for @historyLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your walks'**
  String get historyLoadError;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @screenWalkDetail.
  ///
  /// In en, this message translates to:
  /// **'Walk Detail'**
  String get screenWalkDetail;

  /// No description provided for @screenSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get screenSettings;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsSystemDefault;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageDanish.
  ///
  /// In en, this message translates to:
  /// **'Dansk'**
  String get languageDanish;

  /// No description provided for @navMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get navMenu;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @settingsUnits.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get settingsUnits;

  /// No description provided for @unitsKilometers.
  ///
  /// In en, this message translates to:
  /// **'Kilometers'**
  String get unitsKilometers;

  /// No description provided for @unitsMiles.
  ///
  /// In en, this message translates to:
  /// **'Miles'**
  String get unitsMiles;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied'**
  String get locationPermissionDenied;

  /// No description provided for @foregroundDisclosureTitle.
  ///
  /// In en, this message translates to:
  /// **'Location access'**
  String get foregroundDisclosureTitle;

  /// No description provided for @foregroundDisclosureBody.
  ///
  /// In en, this message translates to:
  /// **'Walkable collects location data to show your live position on the map and to record your walking route while you use the app. Your exact position and route are never sent anywhere; only the map tiles for the area on screen are downloaded from the map provider, CARTO.\n\nNext, Android will ask you to allow location access.'**
  String get foregroundDisclosureBody;

  /// No description provided for @locationDisclosureTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow background location'**
  String get locationDisclosureTitle;

  /// No description provided for @locationDisclosureBody.
  ///
  /// In en, this message translates to:
  /// **'Walkable collects location data to record your walking route and show your live position on the map — including in the background, even when the app is closed or the screen is off. This keeps your walk recording while your phone is in your pocket. Your location is only used while a walk is running, and your exact position and route are never sent anywhere; only the map tiles for the area on screen are downloaded from CARTO.\n\nNext, Android will ask you to allow location access “All the time”.'**
  String get locationDisclosureBody;

  /// No description provided for @locationDisclosureAccept.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get locationDisclosureAccept;

  /// No description provided for @locationDisclosureDecline.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get locationDisclosureDecline;

  /// No description provided for @backgroundTrackingWarning.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off, so your walk may stop recording when the screen is locked.'**
  String get backgroundTrackingWarning;

  /// No description provided for @batteryOptimizationWarning.
  ///
  /// In en, this message translates to:
  /// **'Battery optimisation is on, so your walk may stop recording when the screen is locked. Disable it in Settings.'**
  String get batteryOptimizationWarning;

  /// No description provided for @batterySaverLocationWarning.
  ///
  /// In en, this message translates to:
  /// **'Battery Saver turns off location while the screen is locked, so your walk may have gaps. Turn Battery Saver off, or keep the screen on.'**
  String get batterySaverLocationWarning;

  /// No description provided for @leaveWalkTitle.
  ///
  /// In en, this message translates to:
  /// **'Walk in progress'**
  String get leaveWalkTitle;

  /// No description provided for @leaveWalkBody.
  ///
  /// In en, this message translates to:
  /// **'Your walk is still recording. Keep recording, or stop and save it?'**
  String get leaveWalkBody;

  /// No description provided for @leaveWalkKeepRecording.
  ///
  /// In en, this message translates to:
  /// **'Keep recording'**
  String get leaveWalkKeepRecording;

  /// No description provided for @leaveWalkStop.
  ///
  /// In en, this message translates to:
  /// **'Stop walk'**
  String get leaveWalkStop;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get openSettings;

  /// No description provided for @statusRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get statusRecording;

  /// No description provided for @statusNoSignal.
  ///
  /// In en, this message translates to:
  /// **'No GPS signal'**
  String get statusNoSignal;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statusPaused;

  /// No description provided for @statusConfirmStop.
  ///
  /// In en, this message translates to:
  /// **'Finish walk?'**
  String get statusConfirmStop;

  /// No description provided for @walkCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Walk complete'**
  String get walkCompleteTitle;

  /// No description provided for @walkCompleteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nice one — your walk has been saved.'**
  String get walkCompleteSubtitle;

  /// No description provided for @markerStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get markerStart;

  /// No description provided for @markerFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get markerFinish;

  /// No description provided for @shareWalkSummary.
  ///
  /// In en, this message translates to:
  /// **'I walked {distance} in {duration} with Walkable'**
  String shareWalkSummary(String distance, String duration);

  /// No description provided for @locationError.
  ///
  /// In en, this message translates to:
  /// **'Could not get location: {error}'**
  String locationError(String error);

  /// No description provided for @walksRecovered.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Recovered an interrupted walk to your history} other{Recovered {count} interrupted walks to your history}}'**
  String walksRecovered(int count);

  /// No description provided for @notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Walk in progress'**
  String get notificationTitle;

  /// No description provided for @notificationText.
  ///
  /// In en, this message translates to:
  /// **'Walkable is recording your walk'**
  String get notificationText;

  /// No description provided for @unitKm.
  ///
  /// In en, this message translates to:
  /// **'{value} km'**
  String unitKm(String value);

  /// No description provided for @unitMi.
  ///
  /// In en, this message translates to:
  /// **'{value} mi'**
  String unitMi(String value);

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String settingsVersion(String version, String build);

  /// No description provided for @settingsAutoStop.
  ///
  /// In en, this message translates to:
  /// **'Auto-stop walk'**
  String get settingsAutoStop;

  /// No description provided for @autoStopOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get autoStopOff;

  /// No description provided for @autoStopAfterHours.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{After 1 hour} other{After {hours} hours}}'**
  String autoStopAfterHours(int hours);

  /// No description provided for @walkAutoStoppedNote.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{Walk stopped automatically after 1 hour} other{Walk stopped automatically after {hours} hours}}'**
  String walkAutoStoppedNote(int hours);

  /// No description provided for @autoStopWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Still walking?'**
  String get autoStopWarningTitle;

  /// In-app auto-stop banner; time is the moving time left, as m:ss.
  ///
  /// In en, this message translates to:
  /// **'Your walk will stop in {time}'**
  String autoStopWarningCountdown(String time);

  /// No description provided for @actionKeepWalking.
  ///
  /// In en, this message translates to:
  /// **'Keep walking'**
  String get actionKeepWalking;

  /// No description provided for @actionStopNow.
  ///
  /// In en, this message translates to:
  /// **'Stop now'**
  String get actionStopNow;

  /// Android notification channel name, shown in the system's notification settings.
  ///
  /// In en, this message translates to:
  /// **'Auto-stop warnings'**
  String get autoStopChannelName;

  /// No description provided for @autoStopChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Warns before a walk stops itself, and tells you when it has.'**
  String get autoStopChannelDescription;

  /// Auto-stop warning notification text, under autoStopWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{Your walk will stop in 1 minute.} other{Your walk will stop in {minutes} minutes.}}'**
  String autoStopWarningBody(int minutes);

  /// No description provided for @autoStopNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Walk stopped and saved'**
  String get autoStopNoticeTitle;

  /// No description provided for @autoStopNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'Open Walkable to see your walk.'**
  String get autoStopNoticeBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['da', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'da':
      return AppLocalizationsDa();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
