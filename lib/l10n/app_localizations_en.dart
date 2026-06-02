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
  String get screenWalkDetail => 'Walk Detail';

  @override
  String get locationPermissionDenied => 'Location permission denied';

  @override
  String unitKm(String value) {
    return '$value km';
  }
}
